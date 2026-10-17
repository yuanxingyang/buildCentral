# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Maintenance scope

Keep this file in sync with changes to the build **framework** only — i.e. everything **except `workspace/`**: `tools/buildCentral/`, `tools/make_image/`, `project/build/`, and `external/`. Ignore changes under `workspace/`: it holds the source trees of the modules being built (independently versioned/checked-out), and the framework merely references them via the `Path` field in `project/build/build_central.cfg`. New/changed modules in `workspace/` are recorded by editing that cfg, not by editing this file. Do not describe individual `workspace/` packages, their APIs, or their build quirks here.

## What this is

`buildCentral` is a package build-management tool: it resolves dependencies between software packages, orders the build, and drives CMake/Make across native and cross targets (QNX, ARM Linux, RH850, Windows, Cygwin, Linux host). There is no application code or test suite here — the repo is the tooling plus an example project configuration.

## Repository layout

The project root is auto-detected by scanning parent directories for a dir containing all four signature entries: `external/`, `project/`, `tools/`, `workspace/`. Everything keyframe-loads from that root.

- `tools/buildCentral/` — the build tool itself. `build_central.py` (CLI entry, argparse) + `bc_core.py` (config loading, dependency graph, command construction, build execution). Python 2/3 compatible.
- `tools/buildCentral/rules/` — shared CMake rules included into every package build (`rule_base.cmake`), default `toolchain.cmake`, `toolchain_rh850.cmake`, `cmake_uninstall.cmake.in`, `dummy.c`, and the config templates (`build_central.cfg.tmpl`, `buildcentralrc.tmpl`, `.build_central.tmpl`).
- `tools/buildCentral/install/` — `mk` (bash) / `mk.cmd` (Windows) wrappers that guess project root and invoke `build_central.py`; `install` (pip dependency bootstrap); sample `.build_central` and `build_central.cfg`.
- `project/build/` — the actual project config: `build_central.cfg` (packages/groups/variants) and `buildcentralrc` (per-arch toolchain/flags), plus target-specific toolchain files like `aarch64le-nto-toolchain.cmake`.
- `tools/make_image/` — a **separate, Python-2-only** packaging tool (`script/make_image.py`) that lays out target-board images from staged outputs. It predates buildCentral, reads `~/.build_central` (different name), and uses a different project-root signature (`deliveries, workspace, sys_root, toolchain`). Treat it as independent.

`workspace/` and `external/` are placeholders here (just `Readme.txt`); in a real project they hold source packages and third-party deliverables respectively.

## Commands

Install dependencies (run once):
```bash
bash tools/buildCentral/install/install   # pip install python-magic networkx simplejson
```
Plus optional tools referenced in that script (commented out): `matplotlib` + `python-tk` (for the `-p` plot flag), `cppcheck`, `astyle`, `cloc`.

Run the build tool — from anywhere under the project root:
```bash
python tools/buildCentral/build_central.py [options] [packages]
# or, if mk is on PATH / symlinked:
mk [options] [packages]
```
The `mk`/`mk.cmd` wrappers auto-locate the root and dispatch to `build_central.py`. (`gmk` would dispatch to a GUI `gbuild_central.py` that is **not present** in this repo.)

Key flags (authoritative source: the `argparse` block at the top of `build_central.py` — see "Gotchas" re. the Readme drifting from these):
- `-l` list packages; `-la` list with dependency order; `-i` show info + installed files; `-a` build with dependencies; `-e` build everything *except* the named packages
- `-t <arch>` target arch, `-r <variant>` build variant, `-d` debug, `-v` verbose, `-j N` jobs, `-g <generator>` CMake generator, `-D a,b` extra (c)make vars
- `-c` clean (uninstall + clean), `-cb` clean then build, `-p` plot dependency graph (needs matplotlib)
- No package arg → `mk` builds the package whose source dir matches `pwd` (or all if at root).

make_image (Python 2):
```bash
python2 tools/make_image/script/make_image.py [-n] [-t TARGET_ARCH] image_root packages
```

There is no test suite and no linter wired in; `.astylerc` exists for optional `astyle` formatting.

## How a build works (the big picture)

1. **Config load** (`bc_core.load_build_config`): parses `project/build/build_central.cfg` with `$PROOT` template substitution. The cfg defines `TARGETS`, `PACKAGES` (each with `Path`, `Dependency`, `Tools`, `MAKE_VAR`, `MACRO_DEF`, `MakeTarget`, `Label`), `PACKAGES-PER-ARCH` (per-arch overrides), `GROUPS` (named package sets, composable via `BASE`), and `BUILD_VARIANTS` (per-arch: `DEFAULT_VARIANT` + named variants, each a `MACRO` + `GROUPS`).
2. **Toolchain config** (`import_private_config`): layers three `buildcentralrc` files in order — `tools/buildCentral/rules/buildcentralrc` (defaults), `project/build/buildcentralrc` (project), `~/.buildcentralrc` (per-user, private). Each sets per-arch compilers, flags, macros, make vars, env, stage dir, toolchain file, and `ENV_SOURCE_CMD` (a shell snippet sourced to capture extra env).
3. **Graph + ordering**: per variant, packages are expanded through groups into a `networkx.DiGraph` (edges = dependency; `Tools` edges go target→host). Cycles are detected and fail the build. `generate_build_order` / `figure_out_build_order` produce a topological order. A synthetic `__all__` root is added so bare `mk` builds everything.
4. **Build execution** (`do_build_packages`): host tools are built first (`get_tools` + their own build order), then target packages. For each package, `get_build_cmd_type` picks `cmake` (if `CMakeLists.txt` exists) or `make` (if `Makefile`/`GNUMakefile`); `create_build_command` assembles the cmake/make invocation passing all flags/definitions as `-D` vars; output is tee'd to stdout **and** to `output/log/<arch>/log`.
5. **Stage + uninstall**: `CMAKE_INSTALL_PREFIX` is the stage dir; `install_manifest.txt` records installed files. `make uninstall` (via `cmake_uninstall.cmake.in`) and `-i`/`-c` rely on it. A package's `MakeTarget == "install"` controls whether uninstall runs during clean.

**Output layout** (under `OUTPUT_DIR`, default `proj_root/output`):
- build dir: `output/build/<variant>/<pkg>/<arch>/`
- stage dir: `output/stage/<variant>/<arch>/` (host build → `output/stage/<HOST>/`)
- logs: `output/log/<arch>/log`

**Host-vs-target interaction**: a package's `Tools` are host-built helper packages. When `target_arch == host_arch`, any package already built as a tool is skipped from the target list, so tools aren't rebuilt twice. `arch_is_host` and `config['os_type']` drive this split.

## CMake integration

Every package build pulls in `rules/rule_base.cmake`, which: applies `MACRO_DEF`/`MACRO_VARIANT`, release/debug flags, `SYSTEM_ROOT`/`INC_PATH`/`LIB_PATH`, sets `CMAKE_INSTALL_PREFIX`, wires the `uninstall` target, and exposes helpers (`target_create_executable`, `target_create_library`, `target_source_files`, `target_source_directories`, `generate_glob_list`). Cross targets need a toolchain file — `TOOLCHAIN_FILE` in `buildcentralrc`, else the default `rules/toolchain.cmake`; RH850 uses `rules/toolchain_rh850.cmake`. When adding a new target arch, add it to `TARGETS`/`BUILD_VARIANTS` in the cfg and a matching entry in `buildcentralrc`.

## Gotchas

- **Config filename drift.** The Chinese `tools/buildCentral/Readme` says the private toolchain config is `~/.build_central` and its template is `tools/buildCentral/rules/.build_central`. The **actual** code in `bc_core.py` reads `~/.buildcentralrc`, `project/build/buildcentralrc`, and `tools/buildCentral/rules/buildcentralrc` — the `.build_central` file in `install/` is a leftover sample, not what runtime loads. Templates in `rules/` are named `buildcentralrc.tmpl` and `.build_central.tmpl`. When configuring toolchains, edit the `buildcentralrc` files (or copy the template to `~/.buildcentralrc`); ignore the `.build_central` naming unless working on `make_image`, which does use `~/.build_central`.
- **Readme flag drift.** The Readme documents `-m BUILD_MODEL` and `-i --installed_list`; the real argparse uses `-r/--build_variant` and `-i/--info` (different semantics). Always trust `build_central.py`'s argparse over the Readme.
- **Two Python versions.** `tools/buildCentral/` is Py2/Py3-safe; `tools/make_image/script/make_image.py` is **Python 2 only** (`print line,`). Run make_image with `python2`.
- **Missing default config file.** `bc_core.py` loads `tools/buildCentral/rules/buildcentralrc` as the default toolchain layer, but that file is not committed — only `buildcentralrc.tmpl` is. The layer is silently skipped (the loader treats a missing file as a warning, not an error), so per-arch defaults come only from `project/build/buildcentralrc` and `~/.buildcentralrc` unless you create that file.
- **`gmk`/GUI not in repo.** `mk`/`mk.cmd` reference `gbuild_central.py`; that file is absent. Only the CLI path works.
