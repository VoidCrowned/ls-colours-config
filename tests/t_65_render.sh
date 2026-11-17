# edit: the screen as text. The render functions never look at the terminal,
# so a frame can be built from any state and compared with what is expected.

# list_text W H: RET = the list pane as plain text, empty rows at the end dropped
list_text() {
  local r out=""
  render_list "$1" "$2"
  for r in "${!LP_TXT[@]}"; do strip_sgr "${LP_TXT[r]}"; out+="$RET$NL"; done
  while [[ $out == *"$NL" ]]; do out=${out%"$NL"}; done
  RET=$out
}
# frame_text: RET = the whole screen as plain text, one line per row
frame_text() {
  local seg out=""
  local -a segs=()
  compose_frame
  IFS=$ROW_AT read -r -d '' -a segs <<<"$RET"
  for seg in "${segs[@]}"; do
    [[ $seg == *"$ROW_TXT"* ]] || continue
    seg=${seg#*"$ROW_TXT"}
    strip_sgr "${seg%"$NL"}"
    out+="$RET$NL"
  done
  RET=${out%"$NL"}
}
# plain FUNCTION ARGS...: RET = the result of a render function without colours
plain() { "$@"; strip_sgr "$RET"; }
# widest: RET = the length of the longest line of $1
widest() {
  local line n=0
  while IFS= read -r line; do (( ${#line} > n )) && n=${#line}; done <<<"$1"
  RET=$n
}
render_state() {
  OPT_TERM=xterm OPT_CASE=0 OPT_256=0 OPT_DRY=0 OPT_ASCII=1
  setup_glyphs
  read_file "$FIX/pairs.dircolors"
  FILE=pairs.dircolors
  ST=() V_DESC=() V_HARD=()
  T_FILTER="" T_MSG="" T_CUR=0 T_TOP=0 T_RAW=0 T_FOCUS=list T_CTX=list
  T_VIEW=section T_FOLD_DEFAULT=0 FOLD=() FOLD_F=() CUR_ID=""
  F_LINE=() F_WHAT=()
  build_entries
  build_rows
}

group "edit: the list as text"
render_state
list_text 60 8
is "$RET" " - archives     3   red  (1 differ)
>    example.tar       .tar / .TAR     red
     example.gz        .gz / .GZ       red | green  differs
     example.zip       .zip            red
 - images       2   magenta
     example.png       .png / .PNG     magenta
     example.jpg       .jpg            magenta" "headings with a summary; sample, pattern and the colour in words; the cursor is a mark in the margin"
hasnt "${LP_TXT[1]}" "${ESC}[7m" "the cursor row is not drawn in reverse video"
ST[2]=33 ST[3]=33; build_rows
list_text 60 2
is "$RET" " - archives     3   yellow  (2 differ)
>    example.tar       .tar / .TAR     * -> yellow" "a changed row is marked and shows the new colour"
T_RAW=1
list_text 60 3
is "$RET" " - archives     3   33  (2 differ)
>    example.tar       .tar / .TAR     * -> 33
     example.gz        .gz / .GZ       31 | 32  differs" "x shows the codes instead"
T_RAW=0 ST=()
ST[6]=30
list_text 60 4
has "$RET" "     example.zip exam  .zip            * -> black" "a name that is hard to read is repeated in plain text"
ST=(); build_rows
list_text 30 4
widest "$RET"; ok "rows are cut to the width of the pane" test "$RET" -le 30

# every row knows its own width, which the layout relies on to place the
# right-hand pane
widths_ok() {
  local w r bad=""
  for w in 30 44 60 69 70 100; do
    render_list "$w" 8
    for r in "${!LP_TXT[@]}"; do
      strip_sgr "${LP_TXT[r]}"
      (( ${#RET} == LP_LEN[r] && ${#RET} <= w )) || bad+=" w$w/r$r:${#RET}/${LP_LEN[r]}"
    done
  done
  printf '%s' "$bad"
}
ST[6]=30; F_LINE=(6) F_WHAT=("odd"); map_findings; build_rows
is "$(widths_ok)" "" "each row's recorded width matches its text, at every width"
F_LINE=() F_WHAT=(); map_findings; ST=(); build_rows

group "edit: folded sections and findings"
CUR_ID="h:images"; place_cursor; toggle_fold
F_LINE=(6) F_WHAT=(".zip is odd"); map_findings
CUR_ID="e:2"; build_rows
list_text 60 6
is "$RET" " - archives     3   red  (1 differ)  ! 1
     example.tar       .tar / .TAR     red
     example.gz        .gz / .GZ       red | green  differs
>  ! example.zip       .zip            red
 + images       2   magenta" "a folded section is one row; findings of check are marked on rows and headings"
plain info_line 60
is "$RET" " ! .zip is odd" "the finding of the row under the cursor is shown"
CUR_ID="h:archives"; place_cursor
plain info_line 60
has "$RET" "findings for 1 of these entries" "...and on a heading how many entries have findings"
fold_all 1; build_rows
list_text 60 6
is "$RET" ">+ archives     3   red  (1 differ)  ! 1
 + images       2   magenta" "every section folded"
T_RAW=1; list_text 60 1; T_RAW=0
has "$RET" "3   31  (1 differ)" "x shows the code in the summary too"
render_state

group "edit: header and key hints"
plain render_header 70
is "$RET" " ls_colours_config.sh - pairs.dircolors - section view - 0 unsaved    " "a narrow header keeps the file name and the view"
plain render_header 120
is "$RET" " ls_colours_config.sh - pairs.dircolors - 16 colours - pairs joined - section view - 0 unsaved                          " "a wide header shows the settings, straight after the file name"
plain render_header 90
is "$RET" " ls_colours_config.sh - pairs.dircolors - pairs joined - section view - 0 unsaved         " "...dropping the least important first"
OPT_DRY=1 FILE=/a/rather/long/path/to/the/dircolors/file
plain render_header 60
is "$RET" " /a/rather/long/path/t - dry run - section view - 0 unsaved " "a dry run and the view stay; the tool's name goes and a long file name is cut"
OPT_DRY=0 FILE=pairs.dircolors
ST[2]=33
plain render_header 90
has "$RET" "1 unsaved" "the header counts staged changes"
is "${#RET}" 90 "...and fills the width exactly"
ST=()
plain render_footer 60 list 1/5
is "$RET" " up/down move   Enter edit   Space fold   ? help        1/5 " "hints that do not fit are left out; the position is on the right"
plain render_footer 60 picker ""
has "$RET" "Tab next field" "the picker has hints of its own"
plain render_footer 60 prompt ""
has "$RET" "Esc cancel" "...and so has the search"

group "edit: the whole screen"
COLS=60 ROWS=12
frame_text
is "$RET" " pairs.dircolors - section view - 0 unsaved                 
------------------------------------------------------------
 - archives     3   red  (1 differ)
>    example.tar       .tar / .TAR     red
     example.gz        .gz / .GZ       red | green  differs
     example.zip       .zip            red
 - images       2   magenta
     example.png       .png / .PNG     magenta
     example.jpg       .jpg            magenta
------------------------------------------------------------

 up/down move   Enter edit   Space fold   ? help        1/5 " "header, rule, list, rule, message row, key hints"
T_FILTER=png CUR_ID=""; build_rows
frame_text
has "$RET" " filter: png  (Esc clears)" "an active filter is shown above the hints"
T_FILTER=""; build_rows
T_MSG="Undone."
frame_text
has "$RET" "${NL} Undone.${NL}" "...and so is a message"
T_MSG=""
ROWS=24
PK_REF=0 PK_OLD=31 PK_START=31 PK_FILE=31 T_FOCUS=picker T_CTX=picker
picker_load 31
frame_text
has "$RET" "Foreground   red" "below $SPLIT_COLS columns the picker takes the place of the list"
has "$RET" "arrows choose" "...with its own hints (in ASCII: 'arrows', otherwise arrow symbols)"
T_FOCUS=list T_CTX=list
ROWS=12

# the same screen with box-drawing characters, when the system has a UTF-8 locale
if ( LC_ALL=C.UTF-8; x="─"; (( ${#x} == 1 )) ) 2>/dev/null; then
  CUR_ID="e:0"; build_rows
  out=$(LC_ALL=C.UTF-8; OPT_ASCII=0; setup_glyphs; frame_text; printf '%s' "$RET")
  has "$out" "▌    example.tar" "UTF-8: the cursor is a bar"
  has "$out" "────────────" "UTF-8: rules are lines"
  is "$(LC_ALL=C.UTF-8; widest "$out"; printf '%s' "$RET")" 60 "UTF-8: widths are counted in characters, not bytes"
  is "$(LC_ALL=C.UTF-8; OPT_ASCII=0; setup_glyphs; widths_ok)" "" "UTF-8: each row's recorded width matches its text"
  out=$(LC_ALL=C.UTF-8; OPT_ASCII=1; setup_glyphs; frame_text; printf '%s' "$RET")
  hasnt "$out" "▌" "--ascii wins over the locale"
else
  skip "UTF-8 frame" "no C.UTF-8 locale"
fi

group "edit: split pane, full-screen picker and small terminals"
render_state
# open_picker without its key loop: the state it sets up
picker_open_state() {
  entry_values "$1"
  PK_START=$EV_EFF PK_OLD=$EV_EFF PK_REF=$1 PK_ENTRIES=" $1" PK_GRP=-1
  file_value "$1"; PK_FILE=$RET
  picker_load "$PK_START"
  PK_FIELD=0 PK_AT=0 T_FOCUS=picker T_CTX=picker
  CUR_ID="e:$1"; place_cursor
}
# columns_at N: the characters in column N (1-based) of every line of $RET
columns_at() {
  local line out=""
  while IFS= read -r line; do out+="${line:$(( $1 - 1 )):1}"; done <<<"$RET"
  RET=$out
}
picker_open_state 0
COLS=100 ROWS=24
frame_text
frame=$RET
widest "$frame"
is "$RET" 100 "split: no row is wider than the terminal"
RET=$frame; columns_at 56
is "${RET:1:21}" "+|||||||||||||||||||+" "split: the panes are divided by one straight line"
has "$frame" "|  .tar / .TAR" "split: the picker is on the right"
has "$frame" ">    example.tar" "split: the list stays on the left"
has "$frame" "Foreground   red" "split: the colour under the cursor is named next to the field"
has "$frame" "was " "split: the picker shows the colour before"
layout; is "$T_LAYOUT" split "at 100 columns the picker opens beside the list"
COLS=99; layout; is "$T_LAYOUT" full "below 100 columns it takes the whole screen"
COLS=39; layout; is "$T_LAYOUT" small "below 40 columns the terminal is too small"
COLS=100 ROWS=9; layout; is "$T_LAYOUT" small "...and below 10 rows"
ROWS=10; layout; is "$T_LAYOUT" split "...10 rows are enough, also for the picker"
render_picker 44 5
is "${#RP_TXT[@]}" 5 "a picker in 10 rows scrolls instead of spilling over"
has "$(printf '%s\n' "${RP_TXT[@]}")" "Foreground" "...and keeps the field with the focus in view"
COLS=200 ROWS=24
frame_text
frame=$RET
RET=$frame; columns_at 79
is "${RET:1:3}" "+||" "on a wide screen the picker sits next to the list, not at the far edge"
widest "$frame"; is "$RET" 200 "...and the rules still span the screen"
OPT_256=1; frame_text; OPT_256=0
widest "$RET"; ok "with --256 the picker pane is wider" test "$RET" -le 200
T_FOCUS=picker
COLS=30 ROWS=12
frame_text
has "$RET" "too small" "a small terminal gets a note instead of a broken screen"
has "$RET" "it is 30 x 12 now" "...that says how big it is"
widest "$RET"; ok "...and fits" test "$RET" -le 30

# the edited entry changes in the list as the cursor moves over the colours
COLS=100 ROWS=24
picker_move 0 2
preview_set
frame_text
has "$RET" ">    example.tar       .tar / .TAR     * -> yellow" "the list shows the colour under the picker's cursor"
has "$RET" "0 unsaved" "...without staging it"
PV=(); build_rows
frame_text
has "$RET" ">    example.tar       .tar / .TAR     red" "cancelling leaves the list as it was"

group "edit: the palette"
picker_open_state 1
is "$FG_B|$PK_SFG|$PK_FG" "1|3|3" "the colour in the file has a mark of its own (here also the cursor)"
picker_move 0 1
render_picker 44 30
out=$(printf '%s\n' "${RP_TXT[@]}")
has "$out" "df $GL_SW $GL_SW $GL_SAVED $PK_MARK $GL_SW" "the saved colour and the cursor are marked differently"
has "$out" "  Foreground   yellow" "the field names the colour under the cursor"
picker_move 1 0
is "${FG_CELLS[PK_FG]}" 93 "down from a normal colour is its bright twin"
picker_move -1 0; picker_move -1 0
is "$PK_FIELD|${FG_CELLS[PK_FG]}" "0|33" "up from the top row stays in the foreground"
picker_move 0 -9
is "${FG_CELLS[PK_FG]}" "" "the default is the first cell"
picker_move 1 0
is "${FG_CELLS[PK_FG]}" 90 "...and down from it is the first bright colour"
picker_move 1 0
is "$PK_FIELD" 1 "down from the bright row goes to the background"
picker_load "38;5;208"; PK_FIELD=0
is "$FG_B|${FG_CELLS[0]}" "2|38;5;208" "a value the palette lacks gets a cell in front"
picker_move 1 0
is "${FG_CELLS[PK_FG]}" 90 "...and the bright row still starts under the normal colours"
PK_FILE="00;31"; picker_load "01;34"
picker_move 0 1
picker_load "$PK_FILE"
picker_value; is "$RET" "00;31" "r goes back to the colour in the file"
OPT_256=1 PK_FILE=31
picker_load 31
render_picker 44 12
is "${#RP_TXT[@]}" 12 "a short pane shows as many rows as it has"
has "$(printf '%s\n' "${RP_TXT[@]}")" "Foreground" "...keeping the field that has the focus"
PK_FIELD=1
render_picker 44 12
has "$(printf '%s\n' "${RP_TXT[@]}")" "Background" "...also when the focus moves on"
render_picker 44 40
bad=""
for r in "${!RP_TXT[@]}"; do strip_sgr "${RP_TXT[r]}"; (( ${#RET} == RP_LEN[r] && ${#RET} <= 44 )) || bad+=" $r"; done
is "$bad" "" "every row of the picker fits the pane and knows its width"
PK_CW=36
is "$(grid_rows_n 1; printf %s "$RET")" 9 "full width: 2 rows of 16 colours, 6 of the cube, 1 of greys"
PK_CW=18
is "$(grid_rows_n 1; printf %s "$RET")" 16 "in the pane: 2, 12 and 2"
OPT_256=0 PK_CW=36

group "edit: every key is described"
# Every key the list, the picker and the help screen react to must appear in
# the help screen, so that a new key cannot be added without describing it.
OPT_ASCII=1; setup_glyphs
help_lines
helptext=$(printf '%s\n' "${HELP[@]}")
undocumented=""
while IFS= read -r label; do
  label=${label//[[:space:]]/}
  label=${label%)}
  IFS='|' read -r -a keys <<<"$label"
  for k in "${keys[@]}"; do
    case $k in
      eof|'*') continue ;;
      up|down) doc="up/down" ;;
      left|right|pgup|pgdn|home|end|enter|tab|esc|space)
        case $k in
          left) doc="left" ;; right) doc="right" ;; pgup) doc="PgUp" ;; pgdn) doc="PgDn" ;;
          home) doc="Home" ;; end) doc="End" ;; enter) doc="Enter" ;; tab) doc="Tab" ;;
          esc) doc="Esc" ;; space) doc="Space" ;;
        esac ;;
      backtab) doc="Shift-Tab" ;;
      quit)    doc="Ctrl-C" ;;
      '\?')    doc="?" ;;
      *)       doc=$k ;;
    esac
    found=0
    if (( ${#doc} == 1 )); then
      [[ $helptext =~ (^|[ ,/])"$doc"([ ,/]|$) ]] && found=1
    else
      [[ $helptext == *"$doc"* ]] && found=1
    fi
    (( found )) || undocumented+=" $k"
  done
done < <(declare -f cmd_edit open_picker show_help | grep -E '^\s*[^ ()]+( \| [^ ()]+)*\)$')
is "$undocumented" "" "every key the editor handles is in the help screen"
plain render_footer 200 picker ""
has "$RET" "Esc/q cancel" "the picker's hints name q next to Esc"
plain render_footer 60 list ""
has "$RET" "? help" "the list's hints keep ? even at 60 columns"
plain render_footer 200 prompt ""
is "${RET%% *([[:space:]])}" " Enter apply   Esc cancel" "while a code or a search is typed, the hints say how to finish"

group "edit: a whole section at once"
render_state
stage_value " 0 1 2" 33
is "${ST[2]}|${ST[3]}|${ST[4]}|${ST[5]}|${ST[6]}" "33|33|33|33|33" "colouring a section stages every line of every entry"
count_changes " 0 1 2" 33
is "$RET" 0 "...after which nothing would change any more"
count_changes " 0 1 2" 31
is "$RET" 3 "every entry counts that would look different"
ST=()
count_changes " 2" "00;31"
is "$RET" 0 "00;31 and 31 look the same: no change"
build_rows
stage_value " 0 1 2" 33; build_rows
CUR_ID="h:archives"; place_cursor
undo_here
is "${#ST[@]}|$T_MSG" "0|archives: back to the colours in the file (3 entries)" "u on a heading undoes the whole section"
stage_value " 0 1 2" 33; stage_value " 3" 32; build_rows
CUR_ID="e:1"; place_cursor
undo_here
is "${ST[2]}|${ST[4]:-none}|${ST[5]:-none}|${ST[9]}" "33|none|none|32" "u on an entry undoes just that entry, both of its spellings"
undo_here
is "$T_MSG" ".gz / .GZ has no changes to undo." "...and says so when there is nothing to undo"
revert_count; is "$RET" 3 "U counts the entries it would undo"
ST=(); build_rows
# the picker for a section: title, entry count, how many differ, live preview
CUR_ID="h:archives"; build_rows
summarise 0
# G_ENTRIES comes from the script, which shellcheck does not follow here
# shellcheck disable=SC2153
PK_GRP=0 PK_GNAME=archives PK_ENTRIES=${G_ENTRIES[0]} PK_REF=0 PK_START=${G_MAJ[0]} PK_GDIFF=${G_DIFF[0]} PK_OLD="31 (1 differ)" PK_FILE=31
picker_load 31; PK_FIELD=0; T_FOCUS=picker T_CTX=picker
picker_move 0 2
preview_set
COLS=100 ROWS=24
frame_text
has "$RET" "all of archives" "the picker for a section names it"
has "$RET" "3 entries" "...and how many entries it has"
has "$RET" "1 of the entries have another colour" "...and how many differ"
has "$RET" ">- archives     3   yellow" "the section's summary follows the picker"
has "$RET" "example.gz        .gz / .GZ       * -> yellow" "...and so do all of its entries"
T_FILTER=tar; build_rows
frame_text
has "$RET" "archives, matches only" "with a search on, the picker says only the matches change"
has "$RET" "1 matching" "...and how many they are"
T_FILTER=""
PV=() PK_GRP=-1 T_FOCUS=list T_CTX=list; build_rows

group "edit: palette view"
render_state
T_VIEW=palette; CUR_ID=""; build_rows
# pairs: .tar red, .gz red|green (green counts), .zip red, .png and .jpg magenta
is "$(IFS=,; printf '%s' "${G_TITLE[*]}")" "31,35,32" "groups by colour, the most used first"
is "${G_ENTRIES[0]}|${G_ENTRIES[2]}" " 0 2| 1" "...each with the entries of that colour"
list_text 60 9
is "$RET" " - ## red         2
>    example.tar       .tar / .TAR     archives
     example.zip       .zip            archives
 - ## magenta     2
     example.png       .png / .PNG     images
     example.jpg       .jpg            images
 - ## green       1
     example.gz        .gz / .GZ       archives" "a heading is the colour with a swatch and a count; a row names its section"
COLS=100 ROWS=12
frame_text
has "$RET" "palette view" "the header says which view is on"
CUR_ID="e:2"; place_cursor
PK_GRP=-1 PK_ENTRIES=" 2" PK_REF=2; picker_load 31; PK_FIELD=0; picker_move 0 1; preview_set
build_groups
is "${G_ENTRIES[0]}" " 0 2" "while the picker is open the entry stays in its group"
PV=()
stage_value " 2" 32; build_rows
is "${G_TITLE[*]}|${G_ENTRIES[0]}" "32 35 31| 1 2" "on accept it moves to the group of its new colour"
cur_entry; is "$RET" 2 "...and the cursor goes with it"
ST=(); build_rows
stage_value "${G_ENTRIES[0]}" 35; build_rows
is "${G_TITLE[*]}" "35 32" "recolouring a whole colour merges its group into another"
CUR_ID="h:35"; place_cursor; undo_here
is "${G_TITLE[*]}" "31 35 32" "...and u on that group splits it again"
T_FILTER=png; FOLD_F=(); CUR_ID=""; build_rows
is "${G_TITLE[*]}|${ROW_KIND[*]}" "35|h e" "a search in the palette shows only the colours with matches"
T_FILTER=""; build_rows
fold_all 1; build_rows
is "${ROW_KIND[*]}" "h h h" "folding works the same"
T_VIEW=section; build_rows
is "${ROW_KIND[*]}" "h e e e h e e" "...and the section view keeps its own folds"
T_VIEW=section

group "edit: spellings of one colour"
read_file "$FIX/spellings.dircolors"; ST=(); build_entries; F_LINE=(); map_findings
T_VIEW=palette; CUR_ID=""; build_rows
is "${#G_TITLE[@]}|${G_N[0]}" "1|3" "01;35, 1;35 and 00;01;35 are one colour in the palette"
T_VIEW=section; build_rows
is "${G_DIFF[0]}" 0 "...and in a section's summary"
count_changes "${G_ENTRIES[0]}" "01;35"
is "$RET" 0 "...and none of them counts as a change to 01;35"
render_state

group "edit: the help screen fits"
# at 80 columns every word of every line is still there, and no row is wider
help_lines
want=$(printf '%s\n' "${HELP[@]}" | tr "$TAB" ' ' | tr -s ' ' '\n' | grep -v '^$' | sort)
help_rows 78
got=$(printf '%s\n' "${HELP_ROWS[@]}" | tr -s ' ' '\n' | grep -v '^$' | sort)
is "$got" "$want" "at 80 columns long descriptions wrap and no word is lost"
widest "$(printf '%s\n' "${HELP_ROWS[@]}")"
ok "...and no row is wider than the screen" test "$RET" -le 78
