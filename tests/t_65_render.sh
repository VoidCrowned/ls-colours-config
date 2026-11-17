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
  ST=() UNDO=() V_DESC=() V_HARD=()
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
is "$RET" " - archives     3   mixed, 3 colours
>    example.tar       .tar / .TAR     * -> yellow" "a changed row is marked and shows the new colour"
T_RAW=1
list_text 60 3
is "$RET" " - archives     3   mixed, 3 colours
>    example.tar       .tar / .TAR     * -> 33
     example.gz        .gz / .GZ       31 | 32  differs" "x shows the codes instead"
T_RAW=0 ST=()
ST[6]=30
list_text 60 4
has "$RET" "     example.zip exam  .zip            * -> black" "a name that is hard to read is repeated in plain text"
ST=(); build_rows
list_text 30 4
widest "$RET"; ok "rows are cut to the width of the pane" test "$RET" -le 30

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
is "$RET" " ls_colours_config.sh - pairs.dircolors                     0 unsaved " "a narrow header keeps the file name"
plain render_header 90
is "$RET" " ls_colours_config.sh - pairs.dircolors             16 colours - pairs joined - 0 unsaved " "a wide header shows the settings"
ST[2]=33
plain render_header 90
has "$RET" "1 unsaved" "the header counts staged changes"
is "${#RET}" 90 "...and fills the width exactly"
ST=()
plain render_footer 60 list 1/5
is "$RET" " up/down move   Enter edit   Space fold   / search      1/5 " "hints that do not fit are left out; the position is on the right"
plain render_footer 60 picker ""
has "$RET" "Tab next field" "the picker has hints of its own"
plain render_footer 60 search ""
has "$RET" "Esc cancel" "...and so has the search"

group "edit: the whole screen"
COLS=60 ROWS=12
frame_text
is "$RET" " ls_colours_config.sh - pairs.dircolors           0 unsaved 
------------------------------------------------------------
 - archives     3   red  (1 differ)
>    example.tar       .tar / .TAR     red
     example.gz        .gz / .GZ       red | green  differs
     example.zip       .zip            red
 - images       2   magenta
     example.png       .png / .PNG     magenta
     example.jpg       .jpg            magenta
------------------------------------------------------------

 up/down move   Enter edit   Space fold   / search      1/5 " "header, rule, list, rule, message row, key hints"
T_FILTER=png CUR_ID=""; build_rows
frame_text
has "$RET" " filter: png  (Esc clears)" "an active filter is shown above the hints"
T_FILTER=""; build_rows
T_MSG="Undone."
frame_text
has "$RET" "${NL} Undone.${NL}" "...and so is a message"
T_MSG=""
PK_REF=0 PK_OLD=31 T_FOCUS=picker T_CTX=picker
picker_load 31
frame_text
has "$RET" "Foreground: red" "the picker takes the place of the list"
has "$RET" "arrows choose" "...with its own hints"
T_FOCUS=list T_CTX=list

# the same screen with box-drawing characters, when the system has a UTF-8 locale
if ( LC_ALL=C.UTF-8; x="─"; (( ${#x} == 1 )) ) 2>/dev/null; then
  CUR_ID="e:0"; build_rows
  out=$(LC_ALL=C.UTF-8; OPT_ASCII=0; setup_glyphs; frame_text; printf '%s' "$RET")
  has "$out" "▌    example.tar" "UTF-8: the cursor is a bar"
  has "$out" "────────────" "UTF-8: rules are lines"
  is "$(LC_ALL=C.UTF-8; widest "$out"; printf '%s' "$RET")" 60 "UTF-8: widths are counted in characters, not bytes"
  out=$(LC_ALL=C.UTF-8; OPT_ASCII=1; setup_glyphs; frame_text; printf '%s' "$RET")
  hasnt "$out" "▌" "--ascii wins over the locale"
else
  skip "UTF-8 frame" "no C.UTF-8 locale"
fi
