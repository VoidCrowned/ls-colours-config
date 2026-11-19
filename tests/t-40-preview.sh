# preview

group "preview"
mkdir -p "$WORK/tmp"
TMPDIR="$WORK/tmp" run preview --term xterm "$ROOT/examples/dircolors.sample"
is "$RC" 0 "exit status 0"
has "$OUT" "file types" "lists the file types"
has "$OUT" "sticky_other_writable" "file type samples are created"
has "$OUT" "orphan -> nowhere" "shows the missing target of a broken link"
has "$OUT" "/dev/null" "borrows a character device from /dev"
has "$OUT" "${NL}archives${NL}" "output is grouped by the section comments"
has "$OUT" "example.tar" "one sample per pattern"
has "$OUT" "Findings of check" "findings follow the listing"
hasnt "$OUT" "$ESC" "no escape codes when piped"
count "$WORK"/tmp/* "$WORK"/tmp/.[!.]*; is "$RET" 0 "the sample directory is removed"

TMPDIR="$WORK/tmp" run preview --keep --term xterm "$ROOT/examples/dircolors.sample"
has "$OUT" "samples kept in $WORK/tmp/lscc-preview." "--keep prints the path"
kept=$(printf '%s\n' "$WORK"/tmp/lscc-preview.*)
ok "--keep keeps the samples" test -e "$kept/s2/example.tar"
chmod -R u+rwx "$kept"; rm -rf "$kept"

run preview --codes --term xterm "$ROOT/examples/dircolors.sample"
has "$OUT" "*.tar                    31" "--codes prints pattern and code"
has "$OUT" "DIR                      01;34" "--codes covers file types"

run preview --codes --colour=always --term xterm "$FIX/problems.dircolors"
has "$OUT" "${ESC}[31mexample.tar" "--colour=always keeps the colours of ls"
# GNU ls prints the code as written (00;34), uutils shortens it to 34.
if [[ $OUT == *"${ESC}[00;34mexample.txt"* || $OUT == *"${ESC}[34mexample.txt"* ]]; then
  pass "a duplicated pattern shows its last definition"
else
  fail "a duplicated pattern shows its last definition"
fi
has "$OUT" "${ESC}[33mexample.term" "a TERM-scoped line applies when TERM matches"
run preview --codes --color=always --term dumb "$FIX/problems.dircolors"
hasnt "$OUT" "${ESC}[33mexample.term" "...and not when it does not"

run preview --term xterm "$FIX/novalue.dircolors"
is "$RC" 1 "exit status 1 when dircolors rejects the file"
has "$OUT" "rejects this file" "says that dircolors rejects the file"
has "$OUT" "Errors (1)" "...and still prints the findings"
run preview --help
has "$OUT" "Usage: ls-colours-config.sh preview" "preview --help"
