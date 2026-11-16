# fix: the guided repair.

export LSCC_DATABASE="$FIX/database.txt"

# fixrun ANSWERS ARGS...: run fix with one answer per line; sets OUT and RC
fixrun() {
  local answers=$1
  shift
  OUT=$(printf '%b' "$answers" | "$BASH" "$SCRIPT" fix --term xterm "$@" 2>&1)
  RC=$?
}
lines_of() { grep -c -- "$1" "$2"; }

group "fix: duplicates, dead lines, missing entries"
fresh problems.dircolors
before=$(cat "$F")
# .txt: Enter (keep the last); .pdf: 1 (keep the first); obsolete: y;
# dead TERM: y; file types: y; patterns: all; reorganise: n; write: y
fixrun '\n1\ny\ny\ny\na\nn\ny\n' --case-sensitive "$F"
is "$RC" 0 "exit status 0"
has "$OUT" "<- in effect" "shows which duplicate is in effect"
is "$(lines_of '^\.txt ' "$F"):$(grep '^\.txt ' "$F")" "1:.txt 00;34" "Enter keeps the last definition"
is "$(lines_of '^\.pdf ' "$F"):$(grep '^\.pdf ' "$F")" "1:.pdf 34" "a number keeps that definition"
is "$(grep -c -E '^(COLOR|OPTIONS|EIGHTBIT) ' "$F")" 0 "obsolete keywords removed"
is "$(lines_of '^TERM trailing' "$F")" 0 "TERM line without effect removed"
is "$(lines_of '^TERM xterm' "$F")" 1 "TERM lines that scope something stay"
is "$(sed -n 1p "$F")" "# header comment: keep me" "header comment kept"
has "$(cat "$F")" ".zip 31   # trailing comment" "untouched lines keep their trailing comment"
has "$(cat "$F")" "${TAB}.indented  36  " "untouched lines keep their whitespace"
has "$(cat "$F")" "SOCK 1x;31${NL}SETUID 37;41${NL}SETGID 30;43${NL}STICKY 37;44" "missing file types added after the existing ones"
has "$(cat "$F")" ".mkv 31${NL}.tgz 31" "missing archives are added at the end of the archives section"
has "$(cat "$F")" "${NL}.rpm 31${NL}" "...in the colour most archives have"
hasnt "$(cat "$F")" ".RPM" "no twin added when the file has no twin convention"
has "$(cat "$F")" "# other${NL}.dbonly 01;33" "entry without a matching section gets a new section"
has "$OUT" "[cd]" "the source of each suggestion is shown"
has "$OUT" "no colour to propose" "says so when there is no colour to propose"
has "$OUT" "Backup of the old file" "reports the backup"
bak=$(printf '%s\n' "$F".bak-*)
is "$(cat "$bak")" "$before" "backup holds the old content"
"$BASH" "$SCRIPT" check --term xterm --ignore missing "$F" >/dev/null 2>&1
dircolors_ok=$(TERM=xterm "$DC" -b "$F" >/dev/null 2>&1; echo $?)
is "$dircolors_ok" 0 "dircolors accepts the result"

group "fix: nothing happens without consent"
fresh problems.dircolors
before=$(cat "$F")
fixrun '\na\ny\ny\ny\na\ny\ny\n' --dry-run "$F"
is "$(cat "$F")" "$before" "--dry-run leaves the file alone"
has "$OUT" "Dry run: nothing was written" "--dry-run says so"
has "$OUT" "line(s) removed" "--dry-run still shows the diff"
count "$F".bak-*; is "$RET" 0 "--dry-run makes no backup"
fixrun '\na\ny\ny\ny\na\ny\nn\n' "$F"
is "$(cat "$F")" "$before" "answering n at the end writes nothing"
OUT=$("$BASH" "$SCRIPT" fix --term xterm "$F" </dev/null 2>&1)
is "$(cat "$F")" "$before" "no answers at all change nothing"
has "$OUT" "No changes" "...and say so"
fixrun 'n\nn\nn\nn\n\nn\n' --case-sensitive "$F"
is "$(cat "$F")" "$before" "skipping every step changes nothing"

group "fix: case twins"
fresh pairs.dircolors
if (( LS_NOCASE )); then
  fixrun 'y\nn\n\nn\ny\n' "$F"
  is "$(lines_of '^\.TAR' "$F")$(lines_of '^\.PNG' "$F")" "00" "redundant twins are dropped on request"
  is "$(lines_of '^\.GZ 32' "$F")" 1 "a twin with its own colour stays"
  fresh pairs.dircolors
  fixrun 'n\nn\na\nn\ny\n' "$F"
else
  skip "redundant twins are dropped on request" "this ls matches case-sensitively"
  fixrun 'n\na\nn\ny\n' "$F"
fi
has "$(cat "$F")" ".rpm 31${NL}.RPM 31" "new entries follow the twin convention of the file"
fresh pairs.dircolors
fixrun 'n\na\nn\ny\n' --case-sensitive "$F"
hasnt "$(cat "$F")" ".RPM" "--case-sensitive adds no twins"

group "fix: reorganise"
OPT_TERM=xterm OPT_CASE=0
read_file "$FIX/problems.dircolors"
declare -A eff_before=()
for p in "${PAT_ORDER[@]}"; do effective "${PAT_LINES[$p]}"; eff_before[$p]=$RET; done
nonblank_before=$(printf '%s\n' "${SRC[@]:1}" | grep -v '^[[:space:]]*$' | LC_ALL=C sort)
build_reorganised
SRC=("${REORG[@]}"); N=$(( ${#SRC[@]} - 1 )); parse
text=$(printf '%s\n' "${SRC[@]:1}")
same=1
for p in "${PAT_ORDER[@]}"; do effective "${PAT_LINES[$p]}"; [[ ${eff_before[$p]} == "$RET" ]] || same=0; done
is "$same" 1 "the effective colour of every pattern is unchanged"
is "${#REORG_FLIPS[@]}" 0 "no overlapping pattern changes its winner"
is "${SRC[1]}" "# header comment: keep me" "header comment stays first"
has "$text" "# video${NL}.mkv 31" "misplaced entry moves to a section of its category"
has "$text" ".gz 31${NL}.GZ 32" "case twins are adjacent, lower case first"
has "$text" ".tar 31${NL}.TAR 31" "case twins are adjacent (second pair)"
has "$text" "# documents${NL}.doc 34${NL}.hid 08${NL}.pdf 34${NL}.pdf 35" "sections are sorted; duplicates keep their order"
has "$text" "TERM xterm*${NL}.term 33${NL}TERM nomatch-term${NL}.other 33${NL}TERM trailing" "TERM-scoped lines do not move"
has "$text" "EXEC 01;32" "file type lines stay"
nonblank_after=$(printf '%s\n' "${SRC[@]:1}" | grep -v '^[[:space:]]*$' | grep -v -x -e '# video' -e '# temporary' | LC_ALL=C sort)
is "$nonblank_after" "$nonblank_before" "no line is lost or invented apart from the new headings"
first_pass=$text
build_reorganised
is "$(printf '%s\n' "${REORG[@]:1}")" "$first_pass" "reorganising twice changes nothing more"

printf '# images\n.xcf.gz 35\n.png 35\n\n# archives\n.gz 31\n.tar.gz 33\n.tar 31\n' >"$WORK/overlap"
read_file "$WORK/overlap"; build_reorganised
has "$(printf '%s\n' "${REORG[@]:1}")" ".gz 31${NL}.tar.gz 33${NL}.tar 31" "a longer pattern stays behind the shorter one it extends"
printf '# archives\n.tar.gz 33\n.gz 31\n' >"$WORK/overlap2"
read_file "$WORK/overlap2"; build_reorganised
has "${REORG_FLIPS[*]}" "example.tar.gz: now 31, would become 33" "warns when the new order changes a colour"

fresh problems.dircolors
fixrun 'n\nn\nn\nn\n\ny\ny\n' --case-sensitive "$F"
has "$OUT" ".mkv -> video" "lists the entries that change section"
has "$(cat "$F")" "# video${NL}.mkv 31" "reorganise is written after confirmation"
fixrun 'n\nn\nn\nn\n\ny\ny\n' --case-sensitive "$F"
has "$OUT" "already in order" "a second run finds nothing to reorganise"
run fix --help
has "$OUT" "Usage: ls_colours_config fix" "fix --help"
