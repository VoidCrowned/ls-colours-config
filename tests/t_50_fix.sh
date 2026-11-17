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
# dead TERM: y; odd colours: Enter (none); file types: y; patterns: all;
# reorganise: n; write: y
fixrun '\n1\ny\ny\n\ny\na\nn\ny\n' --case-sensitive "$F"
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
fixrun 'a\ny\ny\na\ny\na\ny\ny\n' --dry-run --case-sensitive "$F"
is "$(cat "$F")" "$before" "--dry-run leaves the file alone"
has "$OUT" "Dry run: nothing was written" "--dry-run says so"
has "$OUT" "line(s) removed" "--dry-run still shows the diff"
count "$F".bak-*; is "$RET" 0 "--dry-run makes no backup"
fixrun 'a\ny\ny\na\ny\na\ny\nn\n' --case-sensitive "$F"
is "$(cat "$F")" "$before" "answering n at the end writes nothing"
OUT=$("$BASH" "$SCRIPT" fix --term xterm "$F" </dev/null 2>&1)
is "$(cat "$F")" "$before" "no answers at all change nothing"
has "$OUT" "No changes" "...and say so"
fixrun 'n\nn\nn\n\nn\n\nn\nn\n' --case-sensitive "$F"
is "$(cat "$F")" "$before" "skipping every step changes nothing"

group "fix: colours that stand out"
printf '# documents\n.pdf 34\n.txt 00;34\n.doc 34\n.DOC 34\n.odt 34\n.rtf 31   # odd\n.RTF 31\n.md 34\n.epub 34\n.tex 34\n' >"$WORK/odd"
OPT_CASE=0 OPT_TERM=xterm
read_file "$WORK/odd"; LS_NOCASE=0; run_checks
is "${O_PAT[*]}|${O_VAL[*]}|${CAT_MAJ[documents]}" "*.rtf|31|34" "the one entry with another colour is found; 34 and 00;34 count as the same; a pair is listed once"
printf '# documents\n.pdf 34\n.txt 34\n.doc 31\n.odt 31\n.md 34\n' >"$WORK/mixed"
read_file "$WORK/mixed"; run_checks
is "${#O_PAT[@]}" 0 "no overwhelming majority (3 of 5): nothing stands out"
printf '# documents\n.pdf 34\n.txt 34\n.doc 34\n.rtf 31\n' >"$WORK/small"
read_file "$WORK/small"; run_checks
is "${#O_PAT[@]}" 0 "fewer than five entries: nothing stands out"
probe_nocase   # back to what the installed ls really does
F="$WORK/odd"
# (twins: n, where ls ignores case;) odd colours: a (all); file types: n;
# patterns: Enter; reorganise: n; write: y
answers='a\nn\n\nn\ny\n'
(( LS_NOCASE )) && answers="n\\n$answers"
fixrun "$answers" "$F"
has "$OUT" "(8 of 10 documents entries)" "fix shows how strong the majority is"
has "$(cat "$F")" ".rtf 34   # odd${NL}.RTF 34" "the entry and its twin take the colour of the category; the comment stays"
has "$(cat "$F")" ".txt 00;34" "an equivalent spelling of the colour is left alone"

group "fix: case twins"
fresh pairs.dircolors
if (( LS_NOCASE )); then
  fixrun 'y\nn\n\nn\ny\n' "$F"
  is "$(lines_of '^\.TAR' "$F")$(lines_of '^\.PNG' "$F")" "00" "redundant twins are dropped on request"
  is "$(lines_of '^\.GZ 32' "$F")" 1 "a twin with its own colour stays"
  fresh pairs.dircolors
  fixrun 'n\n\nn\na\nn\ny\n' "$F"
else
  skip "redundant twins are dropped on request" "this ls matches case-sensitively"
  fixrun '\nn\na\nn\ny\n' "$F"
fi
has "$(cat "$F")" ".rpm 31${NL}.RPM 31" "new entries follow the twin convention of the file"
fresh pairs.dircolors
fixrun '\nn\na\nn\ny\n' --case-sensitive "$F"
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
fixrun 'n\nn\nn\n\nn\n\ny\ny\n' --case-sensitive "$F"
has "$OUT" ".mkv -> video" "lists the entries that change section"
has "$(cat "$F")" "# video${NL}.mkv 31" "reorganise is written after confirmation"
fixrun 'n\nn\nn\n\nn\n\ny\ny\n' --case-sensitive "$F"
has "$OUT" "already in order" "a second run finds nothing to reorganise"
run fix --help
has "$OUT" "Usage: ls_colours_config.sh fix" "fix --help"
