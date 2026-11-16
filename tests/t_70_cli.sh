# Command line and config discovery.

group "command line"
run --version
has "$OUT" "ls_colours_config 0." "--version"
run --help
has "$OUT" "Usage: ls_colours_config COMMAND" "--help"
run help fix
has "$OUT" "Usage: ls_colours_config fix" "help COMMAND"
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
has "$OUT" "$home/.dircolors" "finds ~/.dircolors"
cp "$FIX/pairs.dircolors" "$home/.dir_colors"
OUT=$(HOME=$home XDG_CONFIG_HOME="" "$BASH" "$SCRIPT" check --term xterm --ignore missing </dev/null 2>&1)
has "$OUT" "$home/.dir_colors" "~/.dir_colors comes before ~/.dircolors"
cp "$FIX/pairs.dircolors" "$home/.config/dircolors"
OUT=$(HOME=$home XDG_CONFIG_HOME="" "$BASH" "$SCRIPT" check --term xterm --ignore missing </dev/null 2>&1)
has "$OUT" "$home/.config/dircolors" "~/.config/dircolors is the default XDG location and comes first"
cp "$FIX/pairs.dircolors" "$home/xdg/.dir_colors"
OUT=$(HOME=$home XDG_CONFIG_HOME="$home/xdg" "$BASH" "$SCRIPT" check --term xterm --ignore missing </dev/null 2>&1)
has "$OUT" "$home/xdg/.dir_colors" "\$XDG_CONFIG_HOME is honoured"
OUT=$(HOME=$home XDG_CONFIG_HOME="$home/xdg" "$BASH" "$SCRIPT" check --term xterm --ignore missing "$ROOT/examples/dircolors.sample" </dev/null 2>&1)
has "$OUT" "examples/dircolors.sample" "a file argument wins over the default locations"
