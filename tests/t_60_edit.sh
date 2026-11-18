# edit: the model behind the editor, and the editor itself in a pseudo-terminal.

group "edit: entries"
OPT_TERM=xterm OPT_CASE=0 OPT_256=0
read_file "$FIX/pairs.dircolors"
ST=()
build_entries
is "${E_LABEL[0]}|${E_NAME[0]}|${E_LINES[0]}" ".tar / .TAR|example.tar| 2 3" "a case pair is one entry that knows both lines"
is "${#E_LABEL[@]}" 5 "pairs are listed once"
entry_values 1
is "${EV_LIST[*]}" "31 32" "a pair with different values shows both"
OPT_CASE=1; build_entries
is "${#E_LABEL[@]}" 8 "--case-sensitive lists every spelling"
is "${E_LABEL[1]}|${E_LINES[1]}" ".TAR| 3" "...each with its own line"
OPT_CASE=0; build_entries
F_LINE=() FOLD=() FOLD_F=() T_FOLD_DEFAULT=0 T_VIEW=section
build_entries
T_FILTER="png"; CUR_ID=""; build_rows
is "${#ROW_KIND[@]}" 2 "search filters the list (heading plus one entry)"
T_FILTER=""; CUR_ID=""; build_rows
is "$(IFS=; printf '%s' "${ROW_KIND[*]}")" "heeehee" "each section is a heading row followed by its entries"
is "$T_CUR" 1 "the cursor starts on the first entry"
T_CUR=3; move_cursor 1
is "$T_CUR|$CUR_ID" "4|h:images" "the cursor can rest on a heading"

group "edit: folding"
toggle_fold
is "$(IFS=; printf '%s' "${ROW_KIND[*]}")" "heeeh" "a section folds away"
is "$CUR_ID" "h:images" "...and the cursor stays on its heading"
toggle_fold
is "${#ROW_KIND[@]}" 7 "...and unfolds again"
CUR_ID="e:1"; place_cursor
is "$T_CUR" 2 "the cursor finds its entry"
toggle_fold
is "$T_CUR|$CUR_ID" "0|h:archives" "folding from an entry puts the cursor on the heading"
fold_all 1; build_rows
is "$(IFS=; printf '%s' "${ROW_KIND[*]}")" "hh" "z folds every section"
T_FILTER="png"; FOLD_F=(); CUR_ID=""; build_rows
is "$(IFS=; printf '%s' "${ROW_KIND[*]}")" "he" "a search unfolds the sections with matches and hides the others"
T_FILTER=""; build_rows
is "$(IFS=; printf '%s' "${ROW_KIND[*]}")" "hh" "...and the folds are back when the search ends"
fold_all 0; CUR_ID=""; build_rows
is "${#ROW_KIND[@]}" 7 "Z unfolds every section"
summarise 0
is "${G_N[0]}|${G_MAJ[0]}|${G_DIFF[0]}" "3|31|1" "a section knows its most common colour and how many entries differ"
ST[3]=35 ST[5]=37 ST[6]=33
summarise 0
is "${G_MAJ[0]}|${G_DIFF[0]}" "35|2" "without a clear majority the first of the most common colours is shown"
ST=()
F_LINE=(6) F_WHAT=(".zip is odd"); map_findings; build_rows
is "${E_WARN[2]}|${G_WARN[0]}|${G_WARN[1]}" ".zip is odd|1|0" "findings of check are attached to their entries and counted per section"
F_LINE=() F_WHAT=(); map_findings; build_rows

group "edit: colour picker"
picker_load "00;33"
picker_value; is "$RET" "00;33" "an untouched value comes back unchanged"
PK_FIELD=0; picker_move 0 1
picker_value; is "$RET" "00;33" "moving the cursor chooses nothing"
picker_preview; is "$RET" "00;34" "...but the preview is the colour under the cursor, written in the style of the old value"
picker_choose; picker_value; is "$RET|$PK_TOUCHED" "00;34|1" "Space chooses it"
PK_TOUCHED=0; picker_choose; is "$PK_TOUCHED" 0 "Space on the chosen colour does nothing"
picker_move 0 1; picker_focus 1
is "${FG_CELLS[PK_FG]}|$PK_FIELD" "34|1" "leaving a field puts its cursor back on the chosen colour"
picker_move 0 2; picker_preview; is "$RET" "00;34;41" "the preview takes the cursor of the focused field only (here the background)"
picker_move 0 -2; picker_focus 0
picker_load "38;5;208"
is "${FG_CELLS[0]}" "38;5;208" "an existing 256-colour value gets its own cell in 16-colour mode"
picker_value; is "$RET" "38;5;208" "...and is kept as it is"
is "${#FG_CELLS[@]}" 18 "16-colour mode offers default and 16 colours"
OPT_256=1; picker_load "38;5;208"
is "${#FG_CELLS[@]}" 257 "--256 offers the whole palette"
is "${FG_CELLS[PK_FG]}" "38;5;208" "...with the current colour selected"
picker_move 1 0; picker_choose; picker_value; is "$RET" "38;5;244" "moving down in the palette changes row"
OPT_256=0
picker_load "01;03;31;44"
PK_ATTRS=${PK_ATTRS/" 1 "/ }
picker_value; is "$RET" "03;31;44" "codes the picker has no control for (italic) are kept"
picker_load "01;05;31"
is "$PK_ATTRS" " 1 5 " "blink is one of the attributes"
PK_ATTRS=${PK_ATTRS/" 5 "/ }
picker_value; is "$RET" "01;31" "blink can be switched off"
picker_load "31"; PK_ATTRS+="5 "
picker_value; is "$RET" "05;31" "...and on"

swatch 34 1; has "$RET" "$PK_MARK" "the selected swatch carries the mark"
swatch 34 0; hasnt "$RET" "$PK_MARK" "...and the others do not"
# The inner script is meant for the child shell, so it must not expand here.
# shellcheck disable=SC2016
is "$(LC_ALL=C LANG=C "$BASH" -c 'source "$1"; printf %s "$PK_MARK"' _ "$SCRIPT")" "<>" "the mark falls back to ASCII without a UTF-8 locale"
# shellcheck disable=SC2016
is "$(LC_ALL=C.UTF-8 "$BASH" -c 'source "$1"; printf %s "$PK_MARK"' _ "$SCRIPT")" "▐▌" "the mark is a solid square in a UTF-8 locale"

group "edit: keys"
keys() { local out=""; while read_key 0.2 && [[ $KEY != eof ]]; do out+="$KEY "; done; RET=$out; }
keys < <(printf '\033q\033\n\033[Aj')
is "$RET" "esc q esc enter up j " "a key typed right after Esc is not lost"
KEY_NEXT=""

group "edit: in a terminal"
run edit "$FIX/pairs.dircolors" </dev/null
is "$RC" 2 "refuses to start without a terminal"
if command -v script >/dev/null 2>&1 && script -qec true /dev/null >/dev/null 2>&1; then
  # keys ARGS -- KEY...: run edit in a pseudo-terminal, one key group every
  # 0.4 s; an editor that does not quit is stopped after 40 s (status 124)
  tui() {
    local args=() k
    while [[ $1 != -- ]]; do args+=("$1"); shift; done
    shift
    OUT=$({ sleep 1; for k in "$@"; do printf '%b' "$k"; sleep 0.4; done; } |
      TERM=xterm timeout 40 script -qec "stty rows 30 cols 100; '$BASH' '$SCRIPT' edit ${args[*]}" /dev/null 2>&1)
    RC=$?
  }
  fresh pairs.dircolors
  before=$(cat "$F")
  # Enter on .tar/.TAR, two colours to the right, choose, accept, save, confirm, back, quit
  tui "$F" -- '\r' 'll' ' ' '\r' 's' 'y\n' '\n' 'q'
  is "$(sed -n 2,3p "$F")" ".tar 33${NL}.TAR 33" "a case pair is edited together and saved"
  is "$(sed -e 2,3d "$F")" "$(printf '%s\n' "$before" | sed -e 2,3d)" "the other lines are untouched"
  count "$F".bak-*; is "$RET" 1 "a backup is written"
  hasnt "$OUT" "Press Enter to return" "after writing, the editor closes instead of asking to go back"
  is "$RC" 0 "...and ends without an error"
  has "$OUT" "${ESC}[?1049l" "the alternate screen is left on exit"
  has "$OUT" "${ESC}[?25h" "the cursor is shown again on exit"

  fresh pairs.dircolors
  before=$(cat "$F")
  tui "$F" -- '\r' 'l' ' ' '\r' 'u' 'q'
  is "$(cat "$F")" "$before" "undo, then quit: nothing is written"
  tui "$F" -- '\r' 'l' ' ' '\r' 's' 'n\n' '\n' 'q' 'y'
  is "$(cat "$F")" "$before" "declining the review writes nothing"
  tui "$F" --dry-run -- '\r' 'l' ' ' '\r' 's' '\n' 'q' 'y'
  is "$(cat "$F")" "$before" "--dry-run never writes"
  # the terminal shrinks and grows again while the picker is open
  OUT=$({ sleep 0.8; printf '\r'; sleep 0.5; printf 'l'; sleep 3.6; printf '\033'; sleep 0.5; printf 'q'; sleep 0.3; printf 'y'; } |
    TERM=xterm timeout 40 script -qec "stty rows 30 cols 110; (sleep 1.6; stty cols 80 rows 24 </dev/tty; sleep 1; stty cols 30 rows 12 </dev/tty; sleep 1; stty cols 110 rows 30 </dev/tty) </dev/null & exec '$BASH' '$SCRIPT' edit '$F'" /dev/null 2>&1)
  RC=$?
  # the output is long, and the texts looked for are each written in one piece
  has "$OUT" "Foreground" "resizing: the picker is drawn"
  has "$OUT" "too small" "...a terminal that gets too small shows a note"
  is "$RC|$(cat "$F")" "0|$before" "...Esc still cancels and nothing is written"
  tui "$F" -- '\003'
  is "$RC" 0 "Ctrl-C without changes quits at once"
  has "${OUT: -40}" "${ESC}[?1049l" "...and restores the terminal"
  tui "$F" -- '\r' 'l' ' ' '\r' '\003' 'n' 'j' '\003' '\003'
  has "$OUT" "Quit without saving?" "Ctrl-C with unsaved changes asks"
  is "$RC" 0 "...n stays, a second Ctrl-C at the question quits"
  has "${OUT: -40}" "${ESC}[?1049l" "...and restores the terminal"
  is "$(cat "$F")" "$before" "...without writing"
  tui "$F" -- '\r' 'l' ' ' '\r' '\r' '\003' 'y'
  has "$OUT" "Quit without saving?" "Ctrl-C in the picker closes it and asks too"
  is "$RC|$(cat "$F")" "0|$before" "...y quits without writing"
  tui "$F" -- '\r' 'l' 'q' 'q'
  is "$RC|$(cat "$F")" "0|$before" "q in the picker cancels; nothing was staged, so q in the list quits at once"
  tui "$F" -- '\r' '?' 'x' '\033' 'q'
  has "$OUT" "Keys in the list" "? opens the help from the picker"
  is "$RC" 0 "...and the editor carries on afterwards"

  # Enter on the heading of the archives (the cursor starts on the first
  # entry, k goes up to it), one colour to the right, accept, confirm
  # (the section was not of one colour), save
  fresh pairs.dircolors
  tui "$F" -- 'k' '\r' 'l' ' ' '\r' 'y' 's' 'y\n' '\n' 'q'
  is "$(sed -n 2,6p "$F")" ".tar 32${NL}.TAR 32${NL}.gz 32${NL}.GZ 32${NL}.zip 32" "a whole section gets one colour"
  fresh pairs.dircolors
  before=$(cat "$F")
  tui "$F" -- 'k' '\r' 'l' ' ' '\r' 'n' 'q'
  is "$(cat "$F")" "$before" "...declining the question changes nothing"
  has "$OUT" "Give all 3 entries of archives the colour green? 3 of them change." "...the question names the colour and how many entries change"

  # y on .tar, down, p on .gz/.GZ, down, d on .zip, save
  fresh pairs.dircolors
  tui "$F" -- 'y' 'j' 'p' 'j' 'd' 's' 'y\n' '\n' 'q'
  is "$(sed -n 2,6p "$F")" ".tar 31${NL}.TAR 31${NL}.gz 31${NL}.GZ 31${NL}.zip 00" "y, p and d in the list are saved"

  # on the heading, one colour to the right without Space, Enter: the
  # chosen colour (red, most of the section) is given, not the cursor's
  fresh pairs.dircolors
  tui "$F" -- 'k' '\r' 'l' '\r' 'y' 's' 'y\n' '\n' 'q'
  is "$(sed -n 5p "$F")" ".GZ 31" "Enter accepts the chosen colour, not the one under the cursor"
  has "$OUT" "Give all 3 entries of archives the colour red? 1 of them change." "...and the question names the chosen colour"
  fresh pairs.dircolors
  tui "$F" -- '\r' 'l' '\r' 'q'
  has "$OUT" "Nothing chosen: Space chooses" "Enter without Space on an entry says how to choose"

  # palette view: up to the heading of red, one colour to the right (green),
  # accept, save
  fresh pairs.dircolors
  tui "$F" -- 'v' 'k' '\r' 'l' ' ' '\r' 's' 'y\n' '\n' 'q' 'q'
  has "$OUT" "palette view" "v switches to the palette view"
  is "$RC" 0 "...the first q leaves it, the second quits"
  is "$(sed -n 2,6p "$F")" ".tar 32${NL}.TAR 32${NL}.gz 31${NL}.GZ 32${NL}.zip 32" "...where Enter on a colour recolours every entry of that colour"
else
  skip "editor in a pseudo-terminal" "needs the script command"
fi
run edit --help
has "$OUT" "Usage: ls_colours_config.sh edit" "edit --help"
