# Facts about ls and dircolors that the tool relies on, checked against every
# GNU-compatible ls/dircolors pair installed here.

facts_for() {
  local l=$1 d=$2 dir="$WORK/facts.$RANDOM" out
  mkdir "$dir"
  ( cd "$dir" && : >a.tar && : >a.TAR && : >a.Tar && : >tar && : >myREADME && : >run.sh && chmod +x run.sh )

  out=$(TERM=xterm "$d" -b "$FIX/pairs.dircolors")
  has "$out" "*.tar=31" "[$l] .ext in the file becomes *.ext in LS_COLORS"
  printf '*README 33\n.tar 31\n' >"$dir/c1"
  out=$(TERM=xterm "$d" -b "$dir/c1")
  has "$out" "*README=33" "[$l] a pattern starting with * is used as written"
  out=$(cd "$dir" && LS_COLORS='*README=33:*.tar=31' "$l" --color=always myREADME a.tar tar)
  has "$out" "${ESC}[33mmyREADME" "[$l] matching is on the filename suffix"
  hasnt "$out" "mtar" "[$l] a name without the suffix is not coloured"

  out=$(cd "$dir" && LS_COLORS='*.tar=31:*.tar=32' "$l" --color=always a.tar)
  has "$out" "${ESC}[32ma.tar" "[$l] the last definition of a pattern wins"

  printf '.a 31\nTERM nomatch\n.b 32\nTERM xterm\n.c 33\n' >"$dir/c2"
  out=$(TERM=xterm "$d" -b "$dir/c2")
  has "$out" "*.a=31" "[$l] lines before the first TERM are global"
  hasnt "$out" "*.b=32" "[$l] lines after a non-matching TERM are dropped"
  has "$out" "*.c=33" "[$l] lines after a matching TERM apply"

  printf '.a 31\n.b 32\nTERM nomatch\nTERM other\n' >"$dir/c3"
  printf '.a 31\n.b 32\n' >"$dir/c4"
  is "$(TERM=dumb "$d" -b "$dir/c3")" "$(TERM=dumb "$d" -b "$dir/c4")" "[$l] TERM lines after all colour lines have no effect"

  out=$(cd "$dir" && LS_COLORS='ex=01;32:*.sh=35' "$l" --color=always run.sh)
  has "$out" "${ESC}[01;32mrun.sh" "[$l] the executable bit beats the extension"

  printf 'COLOR all\nOPTIONS -F\nEIGHTBIT 1\n.a 31\n' >"$dir/c5"
  out=$(TERM=xterm "$d" -b "$dir/c5" 2>&1); rc=$?
  is "$rc" 0 "[$l] COLOR, OPTIONS and EIGHTBIT are accepted"
  hasnt "$out" "c5:" "[$l] ...without any message"

  out=$(TERM=xterm "$d" -b "$FIX/novalue.dircolors" 2>/dev/null); rc=$?
  is "$rc:$out" "1:" "[$l] a key without a value makes dircolors fail with no output"

  LS=$l DC=$d probe_nocase
  out=$(cd "$dir" && LS_COLORS='*.tar=31' "$l" --color=always a.TAR a.Tar)
  if (( LS_NOCASE )); then
    has "$out" "${ESC}[31ma.TAR" "[$l] extensions match case-insensitively (probe agrees)"
    out=$(cd "$dir" && LS_COLORS='*.tar=31:*.TAR=32' "$l" --color=always a.tar a.TAR a.Tar)
    has "$out" "${ESC}[32ma.TAR" "[$l] differing twins are matched exactly"
    hasnt "$out" "ma.Tar" "[$l] ...and a third spelling then gets no colour"
  else
    hasnt "$out" "ma.TAR" "[$l] extensions match case-sensitively (probe agrees)"
  fi
}

group "facts about ls and dircolors"
facts_seen=0
for pair in "ls dircolors" "gls gdircolors" "gnuls gnudircolors"; do
  l=${pair% *} d=${pair#* }
  if tools_usable "$l" "$d"; then
    facts_for "$l" "$d"
    facts_seen=1
  fi
done
(( facts_seen )) || fail "no GNU ls/dircolors pair found"
LS="" DC=""
detect_tools
probe_nocase
