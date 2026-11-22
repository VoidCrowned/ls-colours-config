# shell-init: load the new colours into the calling shell after a write (#4).

# The tests look for literal $(...) text and pass shell code to bash -c and
# zsh -c, so single quotes are meant.
# shellcheck disable=SC2016

group "shell-init: the wrapper function (#4)"
real="$(cd "$ROOT" && pwd -P)/ls-colours-config.sh"
run shell-init
is "$RC" 0 "shell-init: exit status 0"
has "$OUT" "ls-colours-config.sh() {" "prints a function with the name of the tool"
has "$OUT" "'$real' \"\$@\"" "...that runs this copy by its absolute path"
OUT2=$(cd "$ROOT/tests" && "$BASH" ../ls-colours-config.sh shell-init 2>&1)
has "$OUT2" "'$real' \"\$@\"" "...also when started by a relative path"
ok "the function is valid bash" "$BASH" -n -c "$OUT"
if command -v zsh >/dev/null 2>&1; then
  ok "the function is valid zsh" zsh -n -c "$OUT"
else
  skip "the function is valid zsh" "zsh not installed"
fi
run help shell-init
has "$OUT" "Usage: ls-colours-config.sh shell-init" "help shell-init"
has "$OUT" 'eval "$(ls-colours-config.sh shell-init)"' "...shows the line for the start-up file"
run --help
has "$OUT" "shell-init" "--help lists shell-init"

group "shell-init: the reload question after fix (#4)"
# answers for problems.dircolors up to and including the write question
fixans='\n1\ny\ny\n\ny\na\nn\ny\n'
# reloadrun ANSWERS RELOAD: run fix with LSCC_RELOAD=RELOAD; sets OUT and RC
reloadrun() {
  OUT=$(printf '%b' "$1" | LSCC_RELOAD=$2 "$BASH" "$SCRIPT" fix --term xterm --case-sensitive "$F" 2>&1)
  RC=$?
}
fresh problems.dircolors
OUT=$(printf '%b' "$fixans" | env -u LSCC_RELOAD "$BASH" "$SCRIPT" fix --term xterm --case-sensitive "$F" 2>&1)
hasnt "$OUT" "Load the new colours in this shell now?" "without the wrapper: no second question"
has "$OUT" 'Load the new colours with: eval "$(' "...the eval line as before"
has "$OUT" 'Tip: with eval "$(ls-colours-config.sh shell-init)"' "...and a hint about shell-init"

fresh problems.dircolors
hand="$WORK/hand.$RANDOM"; : >"$hand"
reloadrun "${fixans}y\n" "$hand"
is "$RC" 0 "with the wrapper, yes: exit status 0"
has "$OUT" "Load the new colours in this shell now? [y/N]" "...asks the second question"
has "$OUT" "Loaded:" "...says the colours are loaded"
hasnt "$OUT" "Tip: with eval" "...without the shell-init hint"
has "$(cat "$hand")" "LS_COLORS='" "...hands the dircolors output over"
has "$(cat "$hand")" "export LS_COLORS" "...with the export"
has "$(cat "$hand")" "*.rpm=31" "...made from the file as written"

fresh problems.dircolors
hand="$WORK/hand.$RANDOM"; : >"$hand"
reloadrun "${fixans}n\n" "$hand"
is "$(wc -c <"$hand" | tr -d ' ')" 0 "with the wrapper, no: nothing is handed over"
has "$OUT" 'Load the new colours with: eval "$(' "...the eval line instead"

fresh problems.dircolors
hand="$WORK/hand.$RANDOM"; : >"$hand"
OUT=$(printf '%b' "$fixans" | LSCC_RELOAD=$hand "$BASH" "$SCRIPT" fix -n --term xterm --case-sensitive "$F" 2>&1)
hasnt "$OUT" "Load the new colours in this shell now?" "dry run: no reload question"

fresh problems.dircolors
reloadrun "${fixans}y\n" "$WORK/missing.$RANDOM"
hasnt "$OUT" "Load the new colours in this shell now?" "LSCC_RELOAD names a missing file: treated as no wrapper"
fresh problems.dircolors
mkdir -p "$WORK/handdir"
reloadrun "${fixans}y\n" "$WORK/handdir"
hasnt "$OUT" "Load the new colours in this shell now?" "LSCC_RELOAD names a directory: treated as no wrapper"
fresh problems.dircolors
: >"$WORK/handtarget"; ln -sf "$WORK/handtarget" "$WORK/handlink"
reloadrun "${fixans}y\n" "$WORK/handlink"
hasnt "$OUT" "Load the new colours in this shell now?" "LSCC_RELOAD names a symlink: treated as no wrapper"

group "shell-init: end to end in a real shell (#4)"
# e2e SHELL: eval the wrapper in SHELL, run fix through it, then print the
# exit status, LS_COLORS as the shell now has it, whether it is exported,
# and how many hand-over files are left
e2e() {
  local tmp="$WORK/tmp.$RANDOM"
  mkdir -p "$tmp"
  fresh problems.dircolors
  OUT=$(TMPDIR=$tmp "$1" -c '
    eval "$("$1" shell-init)"
    LS_COLORS=old
    ls-colours-config.sh fix --term xterm --case-sensitive "$2" < <(printf "%b" "$3") >/dev/null 2>&1
    rc=$?
    printf "%s|%s|%s|" "$rc" "${LS_COLORS:0:6}" "$(env | grep -c "^LS_COLORS=")"
    ls -A "$TMPDIR" | wc -l | tr -d " "' _ "$SCRIPT" "$F" "${fixans}y\n" 2>&1)
}
e2e "$BASH"
is "$OUT" "0|di=01;|1|0" "bash: LS_COLORS is loaded and exported in the calling shell, no temporary file left"
if command -v zsh >/dev/null 2>&1; then
  e2e zsh
  is "$OUT" "0|di=01;|1|0" "zsh: LS_COLORS is loaded and exported in the calling shell, no temporary file left"
else
  skip "zsh: LS_COLORS is loaded in the calling shell" "zsh not installed"
fi

group "shell-init: the reload question after edit (#4)"
if command -v script >/dev/null 2>&1 && script -qec true /dev/null >/dev/null 2>&1; then
  fresh pairs.dircolors
  hand="$WORK/hand.$RANDOM"; : >"$hand"
  # Enter on .tar/.TAR, two colours to the right, choose, accept, save,
  # confirm the write, confirm the reload
  OUT=$({ sleep 1; for k in '\r' 'll' ' ' '\r' 's' 'y\n' 'y\n'; do printf '%b' "$k"; sleep 0.4; done; } |
    TERM=xterm LSCC_RELOAD=$hand timeout 40 script -qec "stty rows 30 cols 100; '$BASH' '$SCRIPT' edit '$F'" /dev/null 2>&1)
  RC=$?
  is "$RC" 0 "edit with the wrapper: exit status 0"
  has "$OUT" "Load the new colours in this shell now?" "...asks the reload question after the write"
  has "$(cat "$hand")" "*.tar=33" "...and hands the new colours over"
else
  skip "the reload question after edit" "script cannot run a pseudo-terminal here"
fi
