---
name: buildcentral-build
description: Build, clean-build, or list C/C++ modules under workspace/ via the `mk` wrapper. Use to compile a package, list packages (`mk -l`), or diagnose a build failure. Emits minimal output — one line on success, error tail on failure — to conserve context.
---

# buildCentral build

Build/compile packages under `workspace/` via the `mk` wrapper. CLAUDE.md already documents the cfg, toolchain layering, full flag list, and output paths — this skill adds only the **run procedure** and failure triage.

## Output policy

Build output is large. **Never dump full build output into the conversation.** The helper script captures output to a temp file and prints one line on success or the error tail on failure.

## Run (from anywhere under repo root)

```bash
bash .claude/skills/buildcentral-build/scripts/bc_build.sh -l                       # list packages (add -t <arch>)
bash .claude/skills/buildcentral-build/scripts/bc_build.sh -bcv <pkg>                # clean + build + verbose, one pkg
bash .claude/skills/buildcentral-build/scripts/bc_build.sh -abcv <pkg>               # also build deps first (1st time / after dep changed)
bash .claude/skills/buildcentral-build/scripts/bc_build.sh -c <pkg>                  # clean only (uninstall + clean)
bash .claude/skills/buildcentral-build/scripts/bc_build.sh -bcv <pkg> -t linux       # target a platform
bash .claude/skills/buildcentral-build/scripts/bc_build.sh -abcv <pkg> -t arm-qnx -r dev-high-local   # platform + variant
```

`-t <arch>` chooses the platform (cfg `TARGETS` keys: `arm-qnx`, `arm-android`, `windows`, `win-lin`, `cygwin`, `linux`; `host` aliases the host OS). `-r <variant>` chooses a variant inside it (defaults apply if omitted). Unknown arch → `Error: invalid target arch`. Large compiles can exceed the 2-min Bash timeout — run with a longer timeout or in the background.

## Inline (if the script is unavailable)

```bash
LOG=$(mktemp); ./tools/buildCentral/install/mk -bcv <pkg> >"$LOG" 2>&1; code=$?
if [ $code -eq 0 ]; then echo "✓ built <pkg>"; else
  echo "✗ failed ($code):"; grep -iE 'error|fail|cannot|undefined|no such|loop|invalid' "$LOG" | tail -40
  echo "log: $LOG ; mk log: output/log/<arch>/log"; fi
```

## Failure triage (analyze, don't just retry)

- `Invalid package X` — not in cfg for the arch → `mk -l [-t <arch>]` to confirm names; arch defaults to `DEFAULT_TARGET`.
- `Loop dependency is found` — circular `Dependency` in cfg; break the cycle.
- `cmake fail` / `make fail` — toolchain issue; for cross-compile check toolchain paths in `~/.buildcentralrc` exist; confirm the package's `Path` has `CMakeLists.txt`/`Makefile`.
- undefined reference / headers not found — missing dep → rebuild with `-abcv`.
- Stale build — `-c` cleans (uninstall + clean); `-cb` cleans then rebuilds.

Real build log: `output/log/<arch>/log`.
