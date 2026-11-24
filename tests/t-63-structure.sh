# edit: new entries, new sections and deletions (the model, without a terminal).

# struct_state FIXTURE: the editor's state for a fixture, as cmd_edit sets it up
struct_state() {
  OPT_TERM=xterm OPT_CASE=0 OPT_256=0
  FILE="$FIX/$1"
  read_file "$FILE"
  prepare_checks
  # the colours of the system database, the same on every machine
  DB_VAL=() DB_TYPE=()
  DB_VAL["*.flac"]="00;36" DB_TYPE[pi]="40;33"
  run_checks
  F_LINE0=("${F_LINE[@]}")
  style_detect
  ST=() ADDED=() GONE=()
  T_FILTER="" T_MSG="" T_CUR=0 T_TOP=0 T_VIEW=section T_FOLD_DEFAULT=0 FOLD=() FOLD_F=() CUR_ID=""
  build_entries
  build_rows
}
# entry_named LABEL -> RET: the index of the entry with that label
entry_named() {
  local e
  RET=""
  for e in "${!E_LABEL[@]}"; do [[ ${E_LABEL[e]} == "$1" ]] && RET=$e; done
}
# rows W H: RET = the list pane as plain text
rows() {
  local r out=""
  render_list "$1" "$2"
  for r in "${!LP_TXT[@]}"; do strip_sgr "${LP_TXT[r]}"; out+="${out:+$NL}$RET"; done
  RET=$out
}
# doc: RET = the document as it would be saved
doc() { RET=$(doc_print); }
ORIG_PAIRS=$(cat "$FIX/pairs.dircolors")

group "edit: new entries"
struct_state pairs.dircolors
add_entry .webp
e=$RET
doc
is "$(sed -n 7,8p <<<"$RET")" ".webp 31${NL}.WEBP 31" "n adds the entry at the end of the section under the cursor, with its majority colour"
is "${E_LABEL[e]}|${E_SEC[e]}" ".webp / .WEBP|archives" "...with its upper-case twin, as the file writes them as a rule"
is "$CUR_ID" "e:$e" "...and the cursor is on it"
entry_state "$e"; is "$RET" added "...marked as new"
unsaved; is "$RET" 2 "...and the header counts its lines as unsaved"
add_entry .TAR; is "$?|$T_MSG" "1|.tar / .TAR is in the file already; the cursor is on it" "a key that is there already is refused, in any spelling"
entry_named ".tar / .TAR"; is "$CUR_ID" "e:$RET" "...and the cursor goes to it"
add_entry webp; has "$T_MSG" "is not an entry" "a word that is neither a pattern nor a file type is refused"
add_entry "*."; has "$T_MSG" "needs more than" "a pattern of nothing is refused"
add_entry "a b"; has "$T_MSG" "no spaces" "a key with a space is refused"
add_entry LEFTCODE; has "$T_MSG" "not a colour" "codes that are not colours are refused"

struct_state pairs.dircolors
add_entry fifo
e=$RET
doc
is "$(head -n 1 <<<"$RET")|$(sed -n 2p <<<"$RET")" "FIFO 40;33|" "a file type goes in front of the sections when there are none yet, named in capitals, with the system's colour"
is "${E_SEC[e]}" "file types" "...in the file types"

struct_state pairs.dircolors
ST[2]=33 ST[3]=33
entry_named ".png / .PNG"; CUR_ID="e:$RET"; place_cursor
add_entry "*~"
doc
is "$(tail -n 2 <<<"$RET")" ".jpg 35$NL*~ 35" "a pattern without a dot gets no twin"
is "${!ST[*]}" "2 3" "staged colours in front of the new line keep their lines"
struct_state pairs.dircolors
ST[10]=33
CUR_ID="e:0"; place_cursor
add_entry .7z
is "${!ST[*]}|${ST[12]:-}" "12|33" "...and those after it move with their lines"
F_LINE=(11) F_WHAT=(".png is odd"); map_findings
CUR_ID="e:0"; place_cursor
add_entry .xz
is "${F_LINE[0]}" 13 "the findings of check move with their lines too"
F_LINE=() F_WHAT=()

struct_state pairs.dircolors
T_VIEW=palette; build_rows
CUR_ID="h:35"; place_cursor
add_entry .gif
e=$RET
is "${E_SEC[e]}|$(sed -n '$p' <<<"$(doc_print)")" "images|.GIF 35" "in the palette view a new entry gets the colour under the cursor, in the section of its category"
CUR_ID="h:35"; place_cursor
add_entry .mp3
e=$RET
is "${E_SEC[e]}|$(tail -n 4 <<<"$(doc_print)")" "audio|${NL}# audio${NL}.mp3 35${NL}.MP3 35" "...and a category without a section gets one of its own"
T_VIEW=section

group "edit: new sections"
struct_state pairs.dircolors
CUR_ID="e:0"; place_cursor
add_section music .flac
e=$RET
doc
is "$(sed -n 7,11p <<<"$RET")" "${NL}# music${NL}.flac 00;36${NL}.FLAC 00;36" "N puts the section with its first entry after the section under the cursor, a heading like the others"
is "$(sed -n 12p <<<"$RET")" "# images" "...and the next section follows after an empty line"
is "${E_SEC[e]}|$CUR_ID" "music|e:$e" "...and the cursor is on the new entry"
add_section Archives .7z; has "$T_MSG" "There is a section archives already" "a title that is there already is refused"
add_section "web 2" .wasm; has "$T_MSG" "cannot be a section title" "a title that reads like an entry is refused"
add_section docs DIR; has "$T_MSG" "File types have a section of their own" "a file type cannot start a section"
undo_entries " $e"
is "$RET|$DROPPED|$(doc_print)" "1|1|$ORIG_PAIRS" "u on the only entry of a new section takes the section out again"
is "${#ADDED[@]}" 0 "...and nothing is left marked as new"
struct_state pairs.dircolors
entry_named ".jpg"; CUR_ID="e:$RET"; place_cursor
add_section music .flac
is "$(tail -n 4 <<<"$(doc_print)")" "${NL}# music${NL}.flac 00;36${NL}.FLAC 00;36" "a section after the last one gets no empty line after it"
undo_entries " $RET"
is "$(doc_print)" "$ORIG_PAIRS" "...and goes without a trace"

group "edit: deleting entries"
struct_state pairs.dircolors
entry_named ".gz / .GZ"; e=$RET
ST[4]=35
delete_entries " $e"
is "$RET|${!GONE[*]}|${!ST[*]}" "1|4 5|" "D marks both lines of a pair for deletion and drops their staged colour"
entry_state "$e"; is "$RET" gone "...the entry stays in the list, marked"
summarise 0; is "${G_N[0]}|${G_GONE[0]}" "2|1" "...and its section counts it apart"
unsaved; is "$RET" 2 "...the header counts its lines"
open_picker "$e"; is "$?|$T_MSG" "1|.gz / .GZ is marked for deletion; u brings it back." "the picker does not open on it"
undo_entries " $e"
is "$RET|${#GONE[@]}" "1|0" "u brings it back"
entry_named ".png / .PNG"; a=$RET; entry_named ".jpg"; b=$RET
delete_entries " $a $b"
is "${!GONE[*]}" "7 8 9 10 11" "deleting every entry of a section takes its heading and the empty line in front of it"
undo_entries " $b"
is "${!GONE[*]}" "9 10" "...and bringing one back keeps them"
delete_entries " $b"
ST[2]=33
save_doc() { local i; for i in "${!ST[@]}"; do set_value "$i" "${ST[i]}"; done; for i in "${!GONE[@]}"; do delete_line "$i"; done; doc_rebuild; }
save_doc
is "$(doc_print)" "# archives${NL}.tar 33${NL}.TAR 31${NL}.gz 31${NL}.GZ 32${NL}.zip 31" "on saving, the marked lines go and the colours are set"

struct_state pairs.dircolors
CUR_ID="e:0"; place_cursor
add_entry .webp; e=$RET
delete_entries " $e"
is "$DROPPED|$(doc_print)|${#GONE[@]}" "1|$ORIG_PAIRS|0" "D on a new entry takes it out at once"

struct_state pairs.dircolors
OPT_CASE=1; build_entries
entry_named ".gz"; delete_entries " $RET"
OPT_CASE=0; build_entries; build_rows
entry_named ".gz / .GZ"; entry_state "$RET"
is "$RET" part "an entry of which c had one spelling deleted is partly deleted"
OPT_ASCII=1; setup_glyphs
rows 80 8
has "$RET" ".gz / .GZ             - one spelling deleted" "...and says so in the list"
GONE=(); build_rows

group "edit: undo all"
struct_state pairs.dircolors
F_LINE=(6) F_WHAT=(".zip is odd"); F_LINE0=(6)
CUR_ID="e:0"; place_cursor
add_entry .webp
entry_named ".png / .PNG"; delete_entries " $RET"
ST[2]=33
revert_count; is "$RET" 3 "U counts new, deleted and recoloured entries"
saved_ask=$(declare -f ask_yes)
ask_yes() { return 0; }
undo_all
is "$(doc_print)|${#ST[@]}${#ADDED[@]}${#GONE[@]}|${F_LINE[*]}" "$ORIG_PAIRS|000|6" "U puts the document, the marks and the findings back as they were in the file"
eval "$saved_ask"
F_LINE=() F_WHAT=() F_LINE0=()

group "edit: the list with new and deleted entries"
struct_state pairs.dircolors
OPT_ASCII=1; setup_glyphs
CUR_ID="e:0"; place_cursor
add_entry .webp
entry_named ".gz / .GZ"; delete_entries " $RET"
build_rows
rows 60 8
has "$RET" "example.webp      .webp / .WEBP   + red" "a new entry is marked with +"
has "$RET" "example.gz        .gz / .GZ       - deleted" "a deleted one with - and the word"
F_LINE=(5) F_WHAT=(".GZ is odd"); map_findings; build_rows
rows 60 8
has "$RET" "     example.gz        .gz / .GZ       - deleted" "...without the mark of check's findings"
F_LINE=() F_WHAT=(); map_findings
has "$RET" "archives     3   red" "...and the heading counts only the entries that stay"
entry_named ".png / .PNG"; a=$RET; entry_named ".jpg"; delete_entries " $a $RET"; build_rows
rows 60 10
has "$RET" "images       0   deleted" "a section whose entries are all deleted says so"
ST=() ADDED=() GONE=() F_LINE=() F_WHAT=() F_LINE0=() T_FILTER="" T_MSG="" CUR_ID=""
