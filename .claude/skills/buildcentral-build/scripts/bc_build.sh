#!/bin/bash
# bc_build.sh — run the buildCentral `mk` wrapper with minimal, error-focused output.
# Keeps build output out of the agent's context: stdout/stderr are captured to a
# temp file; on success a single line is printed, on failure only the error tail.
#
# Usage: bash bc_build.sh [any mk flags/args]
#   bash bc_build.sh -l                 # list buildable packages (shown as-is)
#   bash bc_build.sh -bcv fdbus         # clean + build + verbose, one package
#   bash bc_build.sh -abcv protobus     # build package AND its dependencies
#   bash bc_build.sh -c fdbus           # clean only (uninstall + clean)
#
# Note: real compiles can exceed the default 2-min Bash timeout. Run with a longer
# timeout (e.g. 600000 ms) or in the background for large dependency sets.

set -u

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

find_root() {
  local d="$1"
  while [ "$d" != "/" ]; do
    if [ -d "$d/external" ] && [ -d "$d/project" ] && [ -d "$d/tools" ] && [ -d "$d/workspace" ]; then
      printf '%s' "$d"; return 0
    fi
    d="$(dirname "$d")"
  done
  return 1
}

repo_root="$(find_root "$here")" || { echo "✗ buildCentral project root not found (need external/ project/ tools/ workspace/)" >&2; exit 2; }
mk="$repo_root/tools/buildCentral/install/mk"

run_mk() {
  if [ -x "$mk" ]; then "$mk" "$@"; else bash "$mk" "$@"; fi
}

# `-l` (list) and `-i` (info) have small, useful text output — show directly.
info_only=0
for a in "$@"; do
  case "$a" in
    -l|--list|-i|--info) info_only=1 ;;
    -*)
      if printf '%s' "$a" | grep -qE 'l|i'; then info_only=1; fi
      ;;
  esac
done

if [ "$info_only" -eq 1 ]; then
  run_mk "$@"
  exit $?
fi

log="$(mktemp)"
run_mk "$@" >"$log" 2>&1
code=$?

if [ "$code" -eq 0 ]; then
  echo "✓ ok: mk $*"
  rm -f "$log"
  exit 0
fi

echo "✗ failed (exit $code): mk $*"
echo "--- error tail ---"
errs="$(grep -iE 'error|fail|cannot|undefined|no such|not found|loop|invalid|could not' "$log" | tail -40)"
if [ -n "$errs" ]; then
  printf '%s\n' "$errs"
else
  echo "(no error markers matched; last 20 lines:)"
  tail -20 "$log"
fi
echo "--- end ---"

# Show the real build log path. Prefer `-t <arch>` from the command line; else
# read DEFAULT_TARGET from the cfg; else print the generic hint.
arch=""
prev=""
for a in "$@"; do
  if [ "$prev" = "-t" ] || [ "$prev" = "--target_arch" ]; then arch="$a"; fi
  prev="$a"
done
if [ -z "$arch" ]; then
  cfg="$repo_root/project/build/build_central.cfg"
  if [ -f "$cfg" ]; then
    arch="$(grep -m1 'DEFAULT_TARGET' "$cfg" | sed -E 's/.*"DEFAULT_TARGET"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/')"
  fi
fi
if [ -n "$arch" ]; then
  echo "mk log: $repo_root/output/log/$arch/log"
else
  echo "mk log: $repo_root/output/log/<arch>/log  (arch = DEFAULT_TARGET in project/build/build_central.cfg)"
fi
echo "captured: $log (kept for debugging)"
exit "$code"
