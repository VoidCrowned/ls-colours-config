# Command line and config discovery.

group "command line"
run --version
has "$OUT" "ls-colours-config.sh 0." "--version"
run --help
has "$OUT" "Usage: ls-colours-config.sh COMMAND" "--help"
has "$OUT" "-n, --dry-run" "--help lists the dry run of fix and edit"
run help fix
has "$OUT" "Usage: ls-colours-config.sh fix" "help COMMAND"
run
is "$RC" 2 "no command is a usage error"
run frobnicate
is "$RC" 2 "unknown command is a usage error"
run check --frobnicate
is "$RC" 2 "unknown option is a usage error"
run check --colour sometimes "$FIX/pairs.dircolors"
is "$RC" 2 "bad --colour value is a usage error"
run check --no-color --term xterm --ignore missing "$ROOT/examples/dircolors.sample"
is "$RC" 0 "--no-color is accepted as a spelling of --no-colour"

group "config discovery"
home="$WORK/home"
mkdir -p "$home/.config" "$home/xdg"
OUT=$(HOME=$home XDG_CONFIG_HOME="" "$BASH" "$SCRIPT" check --term xterm </dev/null 2>&1); RC=$?
is "$RC" 1 "no config anywhere: exit status 1"
has "$OUT" "no dircolors file found" "...with an explanation"
has "$OUT" "sample >" "...and how to create one"
cp "$ROOT/examples/dircolors.sample" "$home/.dircolors"
OUT=$(HOME=$home XDG_CONFIG_HOME="" "$BASH" "$SCRIPT" check --term xterm --ignore missing </dev/null 2>&1)
has "$OUT" "$home/.dircolors" "finds .dircolors in the home directory"
cp "$FIX/pairs.dircolors" "$home/.dir_colors"
OUT=$(HOME=$home XDG_CONFIG_HOME="" "$BASH" "$SCRIPT" check --term xterm --ignore missing </dev/null 2>&1)
has "$OUT" "$home/.dir_colors" "the home .dir_colors comes before .dircolors"
cp "$FIX/pairs.dircolors" "$home/.config/dircolors"
OUT=$(HOME=$home XDG_CONFIG_HOME="" "$BASH" "$SCRIPT" check --term xterm --ignore missing </dev/null 2>&1)
has "$OUT" "$home/.config/dircolors" "the .config directory is the default XDG location and comes first"
cp "$FIX/pairs.dircolors" "$home/xdg/.dir_colors"
OUT=$(HOME=$home XDG_CONFIG_HOME="$home/xdg" "$BASH" "$SCRIPT" check --term xterm --ignore missing </dev/null 2>&1)
has "$OUT" "$home/xdg/.dir_colors" "\$XDG_CONFIG_HOME is honoured"
OUT=$(HOME=$home XDG_CONFIG_HOME="$home/xdg" "$BASH" "$SCRIPT" check --term xterm --ignore missing "$ROOT/examples/dircolors.sample" </dev/null 2>&1)
has "$OUT" "examples/dircolors.sample" "a file argument wins over the default locations"

group "start-up file decides where a new config goes (#7)"
# st RCNAME CONTENT: write CONTENT to a fresh home's start-up file RCNAME, run
# startup_target there; sets RET to "TARGET|FILE" or "none".
st() {
  local h="$WORK/st.$RANDOM"
  mkdir -p "$h"
  printf '%s\n' "$2" >"$h/$1"
  RET=$(HOME=$h XDG_CONFIG_HOME="" ZDOTDIR=""
        if startup_target; then printf '%s|%s' "${STARTUP_TARGET#"$h"}" "${STARTUP_FILE#"$h"}"; else printf none; fi)
}
# The start-up file lines are single-quoted: their $ is literal text.
# shellcheck disable=SC2016
{
  st .bashrc '    test -r ~/.dircolors && eval "$(dircolors -b ~/.dircolors)" || eval "$(dircolors -b)"'
  is "$RET" "/.dircolors|/.bashrc" "Ubuntu's default .bashrc: ~/.dircolors"
  st .zshrc 'eval "$(dircolors -b $HOME/.dir_colors)"'
  is "$RET" "/.dir_colors|/.zshrc" ".zshrc with \$HOME"
  st .bashrc 'eval "$(dircolors -b "${XDG_CONFIG_HOME:-$HOME/.config}/dircolors")"'
  is "$RET" "/.config/dircolors|/.bashrc" "XDG spelling"
  st .profile 'eval "$(dircolors -b ${HOME}/.dircolors)"'
  is "$RET" "/.dircolors|/.profile" ".profile with \${HOME}"
  st .bashrc '# eval "$(dircolors -b ~/.dircolors)"'
  is "$RET" "none" "a commented-out line does not count"
  st .bashrc 'eval "$(dircolors -b ~/.dircolors.bak)"'
  is "$RET" "none" "a different file name does not count"
  st .bashrc 'eval "$(dircolors -b)"'
  is "$RET" "none" "dircolors without a file does not count"
  st .bashrc 'export PATH=~/.dircolors:$PATH'
  is "$RET" "none" "the path on a line without dircolors does not count"
}

group "help pages look like a man page"
B=$'\e[1m' U=$'\e[4m' Z=$'\e[0m'
run --colour always --help
has "$OUT" "${B}Commands:$Z" "headings are bold"
has "$OUT" "${B}Usage:$Z" "...and so is Usage:"
has "$OUT" "[$Z${U}FILE$Z$B]" "placeholders on the Usage line are underlined"
has "$OUT" "  ${B}fix$Z       walk through" "command names are bold"
has "$OUT" "  ${B}-n, --dry-run$Z" "options are bold"
run --colour always help check
has "$OUT" "  ${B}--term $Z${U}NAME$Z        judge" "an option's placeholder is underlined, not bold"
has "$OUT" "$NL                     get no colour$NL" "continuation lines stay plain"
run --help
hasnt "$OUT" $'\e' "piped help has no escape codes"
OPT_COLOUR=always; setup_colour
is "$(printf 'Options:\n' | help_style)" "${B}Options:$Z" "help_style: heading"
is "$(printf '  --scan DIR   text\n' | help_style)" "  ${B}--scan $Z${U}DIR$Z   text" "help_style: option with placeholder"
is "$(printf '  --256, --term NAME\n' | help_style)" "  ${B}--256, --term $Z${U}NAME$Z" "help_style: line of options only"
is "$(printf '               more text\n' | help_style)" "               more text" "help_style: continuation line"
is "$(printf 'Some prose, with FILE in it.\n' | help_style)" "Some prose, with FILE in it." "help_style: prose"
is "$(printf '  ~/.dir_colors, ~/.dircolors\n' | help_style)" "  ~/.dir_colors, ~/.dircolors" "help_style: indented text that is not an option"
OPT_COLOUR=never; setup_colour
if command -v script >/dev/null 2>&1 && script -qec true /dev/null >/dev/null 2>&1; then
  printf '#!/bin/sh\necho PAGED\ncat >/dev/null\n' >"$WORK/pager"
  chmod +x "$WORK/pager"
  # paged ROWS ARGS...: run the script in a pseudo-terminal of ROWS rows
  paged() {
    local rows=$1; shift
    OUT=$(SHELL=/bin/sh TERM=xterm timeout 20 script -qec "stty rows $rows cols 100; PAGER='$WORK/pager' '$BASH' '$SCRIPT' $*" /dev/null 2>&1 </dev/null)
  }
  paged 20 --help
  has "$OUT" "PAGED" "a page longer than the terminal opens in \$PAGER"
  paged 60 --help
  hasnt "$OUT" "PAGED" "...a page that fits does not"
  has "$OUT" "Commands:" "...and is printed"
  paged 20 help check
  hasnt "$OUT" "PAGED" "...help check fits in 20 rows"
else
  skip "help pager" "script is not available"
fi
