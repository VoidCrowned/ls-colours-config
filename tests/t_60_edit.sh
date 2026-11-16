# edit: the model behind the editor, and the editor itself in a pseudo-terminal.

group "edit: entries"
OPT_TERM=xterm OPT_CASE=0 OPT_256=0
read_file "$FIX/pairs.dircolors"
ST=() UNDO=()
build_entries
is "${E_LABEL[0]}|${E_NAME[0]}|${E_LINES[0]}" ".tar / .TAR|example.tar| 2 3" "a case pair is one entry that knows both lines"
is "${#E_LABEL[@]}" 5 "pairs are listed once"
entry_values 1
is "${EV_LIST[*]}" "31 32" "a pair with different values shows both"
OPT_CASE=1; build_entries
is "${#E_LABEL[@]}" 8 "--case-sensitive lists every spelling"
is "${E_LABEL[1]}|${E_LINES[1]}" ".TAR| 3" "...each with its own line"
OPT_CASE=0; build_entries
T_FILTER="png"; T_CUR=0; build_rows
is "${#ROW_KIND[@]}" 2 "search filters the list (heading plus one entry)"
T_FILTER=""; build_rows
is "$(IFS=; printf '%s' "${ROW_KIND[*]}")" "heeebhee" "a blank row separates the sections"
T_CUR=3; move_cursor 1
is "$T_CUR" 6 "the cursor skips the blank row and the heading"

group "edit: colour picker"
picker_load "00;33"
picker_value; is "$RET" "00;33" "an untouched value comes back unchanged"
PK_FIELD=0; picker_move 0 1
picker_value; is "$RET" "00;34" "one step right is the next colour, written in the style of the old value"
picker_load "38;5;208"
is "${FG_CELLS[0]}" "38;5;208" "an existing 256-colour value gets its own cell in 16-colour mode"
picker_value; is "$RET" "38;5;208" "...and is kept as it is"
is "${#FG_CELLS[@]}" 18 "16-colour mode offers default and 16 colours"
OPT_256=1; picker_load "38;5;208"
is "${#FG_CELLS[@]}" 257 "--256 offers the whole palette"
is "${FG_CELLS[PK_FG]}" "38;5;208" "...with the current colour selected"
picker_move 1 0; picker_value; is "$RET" "38;5;244" "moving down in the palette changes row"
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

group "edit: in a terminal"
run edit "$FIX/pairs.dircolors" </dev/null
is "$RC" 2 "refuses to start without a terminal"
if command -v script >/dev/null 2>&1 && script -qec true /dev/null >/dev/null 2>&1; then
  # keys ARGS -- KEY...: run edit in a pseudo-terminal, one key group every 0.4 s
  tui() {
    local args=() k
    while [[ $1 != -- ]]; do args+=("$1"); shift; done
    shift
    OUT=$({ sleep 0.6; for k in "$@"; do printf '%b' "$k"; sleep 0.4; done; } |
      TERM=xterm script -qec "stty rows 30 cols 100; '$BASH' '$SCRIPT' edit ${args[*]}" /dev/null 2>&1)
    RC=$?
  }
  fresh pairs.dircolors
  before=$(cat "$F")
  # Enter on .tar/.TAR, two colours to the right, accept, save, confirm, back, quit
  tui "$F" -- '\r' 'll' '\r' 's' 'y\n' '\n' 'q'
  is "$(sed -n 2,3p "$F")" ".tar 33${NL}.TAR 33" "a case pair is edited together and saved"
  is "$(sed -e 2,3d "$F")" "$(printf '%s\n' "$before" | sed -e 2,3d)" "the other lines are untouched"
  count "$F".bak-*; is "$RET" 1 "a backup is written"
  has "$OUT" "${ESC}[?1049l" "the alternate screen is left on exit"
  has "$OUT" "${ESC}[?25h" "the cursor is shown again on exit"

  fresh pairs.dircolors
  before=$(cat "$F")
  tui "$F" -- '\r' 'l' '\r' 'u' 'q'
  is "$(cat "$F")" "$before" "undo, then quit: nothing is written"
  tui "$F" -- '\r' 'l' '\r' 's' 'n\n' '\n' 'q' 'y'
  is "$(cat "$F")" "$before" "declining the review writes nothing"
  tui "$F" --dry-run -- '\r' 'l' '\r' 's' '\n' 'q' 'y'
  is "$(cat "$F")" "$before" "--dry-run never writes"
  tui "$F" -- '\r' 'l' '\r' '\003'
  is "$RC" 130 "Ctrl-C ends the editor"
  has "${OUT: -40}" "${ESC}[?1049l" "...and restores the terminal"
  is "$(cat "$F")" "$before" "...without writing"
else
  skip "editor in a pseudo-terminal" "needs the script command"
fi
run edit --help
has "$OUT" "Usage: ls_colours_config edit" "edit --help"
