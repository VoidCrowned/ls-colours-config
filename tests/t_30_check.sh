# check: the linter.

export LSCC_DATABASE="$FIX/database.txt"
DB_LOADED=0

# finding ID LINE: true when check reported that kind of finding on that line
finding() {
  local i
  for i in "${!F_ID[@]}"; do
    [[ ${F_ID[i]} == "$1" && ${F_LINE[i]} == "$2" ]] && return 0
  done
  return 1
}
expect() { if finding "$1" "$2"; then pass "$3"; else fail "$3" "no $1 finding on line $2"; fi; }
expect_not() { if finding "$1" "$2"; then fail "$3" "unexpected $1 finding on line $2"; else pass "$3"; fi; }

group "check: findings"
OPT_TERM=xterm OPT_256=0 OPT_CASE=0 OPT_IGNORE=""
read_file "$FIX/problems.dircolors"
LS_NOCASE=1
run_checks
expect obsolete 2 "obsolete keyword COLOR"
expect obsolete 3 "obsolete keyword OPTIONS"
expect obsolete 4 "obsolete keyword EIGHTBIT"
expect blink 10 "blink code"
expect unknown-sgr 11 "unknown SGR code"
expect bad-sgr 12 "malformed SGR code"
expect duplicate 23 "duplicate pattern, reported on its first line"
expect duplicate 24 "duplicate across two sections"
expect twin-differs 17 "case twins with different values"
expect twins 16 "redundant case twin"
expect wrong-section 20 "video extension in the archives section"
expect invisible 27 "black text without a background"
expect invisible 28 "concealed text"
expect colour256 33 "256-colour code while 256 mode is off"
expect term-mismatch 40 "colour line behind a TERM that does not match"
expect term-noeffect 41 "TERM line after the last colour line"
expect missing-type 0 "file types that are not set"
OPT_CASE=1; run_checks
expect outlier 18 "entry that differs from nearly all others of its category"
OPT_CASE=0; run_checks
expect_not term-mismatch 38 "matching TERM block is not reported"
for i in "${!F_ID[@]}"; do
  if [[ ${F_ID[i]} == duplicate && ${F_LINE[i]} == 23 ]]; then
    has "${F_WHAT[i]}" "line 23 (34, documents), line 25 (00;34, documents)" "duplicate lists every definition with line and value"
    has "${F_WHY[i]}" "line 25 is in effect" "duplicate says which definition is in effect"
    is "${F_SEV[i]}" warning "duplicate with differing values is a warning"
  fi
  if [[ ${F_ID[i]} == duplicate && ${F_LINE[i]} == 24 ]]; then
    has "${F_WHY[i]}" "different sections" "duplicate across sections says so"
  fi
  [[ -n ${F_WHY[i]} && -n ${F_FIX[i]} ]] || fail "finding ${F_ID[i]} has a consequence and a fix note"
done

OPT_256=1; run_checks
expect_not colour256 33 "--256 accepts 256-colour codes"
OPT_256=0
LS_NOCASE=0; run_checks
expect_not twins 16 "twins are not redundant when ls is case-sensitive"
LS_NOCASE=1
OPT_CASE=1; run_checks
expect_not twin-differs 17 "--case-sensitive does not compare twins"
OPT_CASE=0
OPT_IGNORE="blink,obsolete"; run_checks
expect_not blink 10 "--ignore drops a kind of finding"
OPT_IGNORE=""

read_file "$FIX/novalue.dircolors"; run_checks
expect novalue 2 "key without a value"
is "${F_SEV[0]}" error "...is an error"

group "check: missing entries"
read_file "$FIX/pairs.dircolors"
find_missing
is "${CAT_MAJ[archives]}|${CAT_MAJ[images]}" "31|35" "majority colour per category"
is "$TWIN_CONVENTION" 1 "upper-case twin convention detected"
missing_of() { local i; RET="-"; for i in "${!M_PAT[@]}"; do [[ ${M_PAT[i]} == "$1" ]] && RET="${M_CAT[i]}|${M_VAL[i]}|${M_SRC[i]}"; done; }
missing_of "*.rpm";    is "$RET" "archives|31|curated, database" "new archive takes the majority colour; both sources named"
missing_of "*.opus";   is "$RET" "audio|00;36|curated, database" "no entries in the category: value from the database"
missing_of "*.mp3";    is "$RET" "audio||curated" "no majority and no database value: nothing proposed"
missing_of "*.dbonly"; is "$RET" "other|01;33|database" "database-only entry"
missing_of "*.tar";    is "$RET" "-" "existing entry is not missing"
missing_of "*.png";    is "$RET" "-" "existing entry is not missing (twin)"
printf '# audio\n.mp3 36\n.flac 36\n.ogg 35\n.wav 35\n' >"$WORK/tie"
read_file "$WORK/tie"; find_missing
missing_of "*.opus";   is "$RET" "audio|00;36|curated, database" "a tie is no majority: database value"
is "$TWIN_CONVENTION" 0 "no twin convention without twins"
has "${MT_CODE[*]}" "su" "missing file type listed"

mkdir -p "$WORK/scan/sub" "$WORK/scan/.git"
: >"$WORK/scan/a.xyz"; : >"$WORK/scan/sub/b.XYZ"; : >"$WORK/scan/c.tar"; : >"$WORK/scan/d.qq"; : >"$WORK/scan/.git/e.zzz"; : >"$WORK/scan/x.tar.png"
read_file "$FIX/pairs.dircolors"
scan_dir "$WORK/scan"
is "${SCAN_EXT[*]}" "*.qq *.xyz" "--scan finds the extensions without a colour"
is "${SCAN_COUNT[*.xyz]}" 2 "--scan counts files regardless of case"
find_missing
missing_of "*.xyz"; is "$RET" "other||scan" "scan result is a suggestion with its source"
SCAN_EXT=() SCAN_COUNT=()

group "check: command"
run check --term xterm "$FIX/problems.dircolors"
is "$RC" 1 "exit status 1 with findings"
has "$OUT" "Warnings (" "findings are grouped by severity"
has "$OUT" "line 23" "findings name the line"
hasnt "$OUT" "$ESC" "no escape codes when output is not a terminal"
run check --term xterm --ignore missing "$ROOT/examples/dircolors.sample"
is "$RC" 0 "exit status 0 for the sample config"
has "$OUT" "No problems found" "clean file is reported as clean"
run check --term xterm "$FIX/novalue.dircolors"
has "$OUT" "Errors (1)" "errors come first"
run check --color=always --term xterm "$FIX/novalue.dircolors"
has "$OUT" "${ESC}[" "--color is accepted as a spelling of --colour"
run check "$WORK/does-not-exist"
is "$RC" 2 "missing file is a usage error"
run check --help
has "$OUT" "Usage: ls_colours_config.sh check" "check --help"
