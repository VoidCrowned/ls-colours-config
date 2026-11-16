#!/usr/bin/env bash
#
# Test runner for ls_colours_config. Plain bash, no framework.
#
#   tests/run.sh           run everything, human-readable
#   tests/run.sh --json    the same, with a JSON summary as the last line
#
# The tests run under the bash that runs this file, so "bash-4.0 tests/run.sh"
# tests against bash 4.0.

# The helpers and variables defined here are used by the sourced tests/t_*.sh
# files, which shellcheck cannot see from this file.
# shellcheck disable=SC2034,SC2317,SC2329

cd "$(dirname "$0")/.." || exit 1
ROOT=$PWD
SCRIPT="$ROOT/ls_colours_config"
FIX="$ROOT/tests/fixtures"
JSON=0
[[ ${1:-} == --json ]] && JSON=1

PASS=0 FAIL=0 SKIP=0
FAILED=()
WORK=$(mktemp -d "${TMPDIR:-/tmp}/lscc-test.XXXXXX") || exit 1
trap 'chmod -R u+rwx "$WORK" 2>/dev/null; rm -rf "$WORK"' EXIT

# Source the script for its functions; main does not run when sourced.
# shellcheck source=../ls_colours_config
source "$SCRIPT"
OPT_COLOUR=never
setup_colour

group() { printf '\n%s\n' "$1"; }
pass()  { PASS=$(( PASS + 1 )); printf '  ok    %s\n' "$1"; }
fail()  { FAIL=$(( FAIL + 1 )); FAILED+=("$1"); printf '  FAIL  %s\n' "$1"; [[ -n ${2:-} ]] && printf '        %s\n' "$2"; }
skip()  { SKIP=$(( SKIP + 1 )); printf '  skip  %s (%s)\n' "$1" "$2"; }
# is ACTUAL EXPECTED NAME
is() { if [[ $1 == "$2" ]]; then pass "$3"; else fail "$3" "expected [$2], got [$1]"; fi; }
# has HAYSTACK NEEDLE NAME
has() { if [[ $1 == *"$2"* ]]; then pass "$3"; else fail "$3" "[$2] not found in: ${1:0:300}"; fi; }
hasnt() { if [[ $1 != *"$2"* ]]; then pass "$3"; else fail "$3" "[$2] unexpectedly found"; fi; }
# run ARGS...: run the script as a program; sets OUT (stdout+stderr) and RC
run() { OUT=$("$BASH" "$SCRIPT" "$@" 2>&1); RC=$?; }
# fresh NAME: copy a fixture into the work directory, sets F
fresh() { F="$WORK/$1.$RANDOM"; cp "$FIX/$1" "$F"; }

for part in "$ROOT"/tests/t_*.sh; do
  # shellcheck source=/dev/null
  source "$part"
done

printf '\n%d passed, %d failed, %d skipped\n' "$PASS" "$FAIL" "$SKIP"
if (( JSON )); then
  list=""
  for f in "${FAILED[@]}"; do
    f=${f//\\/\\\\}
    list+="${list:+,}\"${f//\"/\\\"}\""
  done
  printf '{"passed":%d,"failed":%d,"skipped":%d,"bash":"%s","ls":"%s","failures":[%s]}\n' \
    "$PASS" "$FAIL" "$SKIP" "$BASH_VERSION" "$("${LS:-ls}" --version 2>/dev/null | head -n 1)" "$list"
fi
(( FAIL == 0 ))
