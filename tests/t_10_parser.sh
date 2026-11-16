# Parser and data model.

group "parser"
OPT_TERM=xterm
read_file "$FIX/problems.dircolors"
is "$N" 41 "reads every line"
is "${L_KIND[1]}" comment "comment line"
is "${L_KIND[2]}" obsolete "obsolete keyword"
is "${L_KIND[5]}" blank "blank line"
is "${L_KIND[7]}:${L_NORM[7]}:${L_VAL[7]}" "type:di:01;34" "file type line"
is "${L_KIND[15]}:${L_NORM[15]}:${L_VAL[15]}" "pattern:*.tar:31" ".ext becomes *.ext"
is "${L_VAL[19]}|${L_POST[19]}" "31|   # trailing comment" "trailing comment is not part of the value"
is "${L_PRE[35]}|${L_VAL[35]}|${L_POST[35]}" "${TAB}.indented  |36|  " "whitespace around key and value is kept apart"
is "${L_KIND[37]}" term "TERM line"
is "${PAT_LINES[*.txt]}" " 23 25" "all definitions of a pattern are recorded"
effective "${PAT_LINES[*.txt]}"
is "$RET@$RET2" "00;34@25" "the last definition is the effective one"
is "${LPAT[*.tar]}" " *.tar *.TAR" "case twins are linked"

group "sections"
is "${SEC_TITLE[1]}|${SEC_CAT[1]}" "archives|archives" "heading comment starts a section"
is "${SEC_TITLE[${L_SEC[23]}]}" documents "pattern belongs to the section above it"
is "${SEC_TITLE[${L_SEC[31]}]}" audio "next heading starts the next section"
is "${L_SEC[38]}" 0 "patterns after a TERM line have no section"
section_category "Archives or compressed (bright red)"; is "$RET" archives "category from heading words"
section_category "everything else"; is "$RET" "" "unknown heading has no category"

group "TERM scoping"
is "${L_ACTIVE[15]}${L_SCOPE[15]}" "1" "lines before the first TERM are global"
is "${L_ACTIVE[38]}|${L_SCOPE[38]}" "1|xterm*" "line after a matching TERM is active"
is "${L_ACTIVE[40]}|${L_SCOPE[40]}" "0|nomatch-term" "line after a non-matching TERM is inactive"
OPT_TERM=dumb; parse
is "${L_ACTIVE[38]}${L_ACTIVE[15]}" "01" "a different TERM flips the scoped line only"
OPT_TERM=xterm

group "SGR codes"
sgr_parse "01;07;31;44"; is "$SGR_FG|$SGR_BG|$SGR_ATTRS|$SGR_BAD" "31|44| 1 7 |" "attributes, foreground, background"
sgr_parse "38;5;208;48;5;17"; is "$SGR_FG|$SGR_BG|$SGR_EXT" "38;5;208|48;5;17|1" "256-colour codes"
sgr_parse "38;2;10;20;30"; is "$SGR_FG|$SGR_EXT" "38;2;10;20;30|1" "24-bit colour"
sgr_parse "1x;31"; is "$SGR_BAD" "1x" "malformed token"
sgr_parse "31;"; has "$SGR_BAD" "31;" "trailing separator is malformed"
sgr_parse "99"; is "$SGR_UNKNOWN" "99" "unknown code"
sgr_parse "00;33"; sgr_compose "34" "" " " "" "$SGR_PAD" "$SGR_ZERO"; is "$RET" "00;34" "compose keeps the leading 00"
sgr_parse "1;33"; sgr_compose "33" "41" " 1 4 " "" "$SGR_PAD" "$SGR_ZERO"; is "$RET" "1;4;33;41" "compose keeps unpadded style"
sgr_compose "" "" " " "" 1 0; is "$RET" "00" "nothing selected composes to 00"

group "in-place editing"
fresh problems.dircolors
before=$(cat "$F")
FILE=$F; FILE_REAL=$F; BACKUP_PATH=""; read_file "$F"
save_file; is "$?" 1 "no write when nothing changed"
is "$(ls "$WORK" | grep -c "bak-")" 0 "no backup when nothing changed"
set_value 19 "01;31"
set_value 35 "35"
save_file; is "$?" 0 "save succeeds"
is "$(sed -n 19p "$F")" ".zip 01;31   # trailing comment" "value replaced, trailing comment kept"
is "$(sed -n 35p "$F")" "${TAB}.indented  35  " "value replaced, whitespace kept"
is "$(sed -e 19d -e 35d "$F")" "$(printf '%s\n' "$before" | sed -e 19d -e 35d)" "all other lines are byte-identical"
[[ -f $BACKUP_PATH ]] && pass "backup created" || fail "backup created"
is "$(cat "$BACKUP_PATH")" "$before" "backup holds the old content"
first_backup=$BACKUP_PATH
set_value 15 "32"; save_file
is "$BACKUP_PATH" "$first_backup" "one backup per run"
is "$(ls -A "$WORK" | grep -c '^\.lscc\.')" 0 "no temp file left behind"

fresh problems.dircolors
FILE=$F; FILE_REAL=$F; BACKUP_PATH=""; read_file "$F"
delete_line 25; insert_after 26 ".docx 34"; doc_rebuild
is "${SRC[25]}|${SRC[26]}" ".doc 34|.docx 34" "delete and insert"
is "$N" 41 "line count after delete and insert"
is "${SRC[1]}" "# header comment: keep me" "header comment untouched"
make_diff; is "$DIFF_REMOVED/$DIFF_ADDED" "1/1" "diff counts one removal and one addition"
OPT_DRY=1; out=$(save_file); rc=$?; OPT_DRY=0
is "$rc" 1 "dry run does not write"
is "$(sed -n 25p "$F")" ".txt 00;34" "file untouched by dry run"
echo "# someone else" >>"$F"
save_file 2>/dev/null; is "$?" 2 "refuses to overwrite a file that changed on disk"

printf '.a 31\n.b 32' >"$WORK/noeol"
FILE="$WORK/noeol"; FILE_REAL=$FILE; BACKUP_PATH=""; read_file "$FILE"
set_value 1 "33"; save_file
is "$(od -c "$FILE" | tail -n 2 | head -n 1 | grep -c '\\n$')" 0 "missing final newline is preserved"

ln -s "$WORK/noeol" "$WORK/link"
FILE="$WORK/link"; resolve_path "$FILE"; FILE_REAL=$RET; BACKUP_PATH=""; read_file "$FILE_REAL"
set_value 2 "34"; save_file
[[ -L "$WORK/link" ]] && pass "a symlinked config stays a symlink" || fail "a symlinked config stays a symlink"
is "$(cat "$WORK/noeol")" ".a 33${NL}.b 34" "the link target was written"

group "sample config"
is "$("$BASH" "$SCRIPT" sample)" "$(cat "$ROOT/examples/dircolors.sample")" "examples/dircolors.sample matches the built-in sample"
