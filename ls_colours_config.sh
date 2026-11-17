#!/usr/bin/env bash
#
# ls_colours_config.sh - preview, check and edit a GNU dircolors configuration file.
#
# Needs bash 4.0 or newer and GNU coreutils (ls, dircolors). Nothing else.
# Licence: WTFPL, see LICENSE.

if [ -z "${BASH_VERSION:-}" ] || [ "${BASH_VERSINFO[0]}" -lt 4 ]; then
  echo "ls_colours_config.sh needs bash 4.0 or newer (this is ${BASH_VERSION:-not bash})." >&2
  echo "On macOS: brew install bash coreutils" >&2
  exit 1
fi

shopt -s extglob

VERSION=0.1.0
PROG=ls_colours_config.sh

# Special characters live in variables: bash 4.0 is picky about $'...' inside
# quoted parameter expansions.
ESC=$'\033'
NL=$'\n'
TAB=$'\t'

# ---------------------------------------------------------------------------
# Options and global state
# ---------------------------------------------------------------------------

OPT_256=0          # --256: allow and offer 256-colour codes
OPT_CASE=0         # --case-sensitive: treat .deb and .DEB as separate entries
OPT_DRY=0          # --dry-run: never write
OPT_ASCII=0        # edit --ascii: draw with ASCII characters only
OPT_KEEP=0         # preview --keep
OPT_CODES=0        # preview --codes
OPT_SCAN=""        # --scan DIR
OPT_TERM=""        # --term NAME: pretend TERM is NAME
OPT_COLOUR=auto    # --colour=auto|always|never
OPT_IGNORE=""      # check --ignore id,id
USE_COLOUR=0

FILE=""            # config file as given or discovered
FILE_REAL=""       # the same with symlinks resolved; this is what gets written
FILE_EOL=1         # 1 when the file ends with a newline
BACKUP_PATH=""     # backup made in this run, if any
LS=""              # GNU ls
DC=""              # GNU dircolors
LS_NOCASE=0        # 1 when this ls matches extensions case-insensitively
TMP_DIR=""         # sample directory of preview
TMP_FILE=""        # temp file of an atomic write in progress
TUI_ACTIVE=0
STTY_SAVED=""
RET=""             # return value of helpers (avoids a subshell per call)
RET2=""

# The document: SRC[1..N] are the lines of the file, ORIG is the text on disk.
declare -a SRC=() ORIG=()
N=0

# Per-line model, filled by parse().
declare -a L_KIND=() L_KEY=() L_VAL=() L_PRE=() L_POST=() L_SEC=() L_ACTIVE=() L_SCOPE=() L_NORM=()
# Sections of pattern lines. Section 0 collects patterns without a heading.
declare -a SEC_TITLE=() SEC_LINE=() SEC_CAT=()
declare -A PAT_LINES=()   # normalised pattern (*.ext) -> " 12 34" line numbers
declare -A LPAT=()        # lower-cased pattern -> " *.deb *.DEB" spellings in use
declare -A TYPE_LINES=()  # ls type code (di, ln, ...) -> line numbers
declare -a PAT_ORDER=()   # normalised patterns in order of first appearance
LAST_COLOUR_LINE=0        # last line that sets a colour

# Pending structural edits, applied by doc_rebuild().
declare -a DEL=() INS=()

# Findings of check.
declare -a F_SEV=() F_ID=() F_LINE=() F_WHAT=() F_WHY=() F_FIX=()

RE_BLANK='^[[:space:]]*$'
RE_COMMENT='^[[:space:]]*#'
RE_ENTRY='^([[:space:]]*)([^[:space:]]+)([[:space:]]*)(.*)$'
RE_COMMENTED='^[.*]?[^[:space:]]+[[:space:]]+[0-9;]+([[:space:]]*#.*)?$'
RE_NUM='^[0-9]+$'
RE_SGR='^[0-9;]+$'
RE_WORD='^[A-Z_]+$'
RE_ALNUM='[[:alnum:]]'

# dircolors keywords for file types and the two-letter codes ls uses for them.
declare -A TYPE_CODE=(
  [NORMAL]=no [NORM]=no [FILE]="fi" [RESET]=rs [DIR]=di [LNK]=ln [LINK]=ln
  [SYMLINK]=ln [ORPHAN]=or [MISSING]=mi [FIFO]=pi [PIPE]=pi [SOCK]=so
  [BLK]=bd [BLOCK]=bd [CHR]=cd [CHAR]=cd [DOOR]="do" [EXEC]=ex [LEFT]=lc
  [LEFTCODE]=lc [RIGHT]=rc [RIGHTCODE]=rc [END]=ec [ENDCODE]=ec [SUID]=su
  [SETUID]=su [SGID]=sg [SETGID]=sg [STICKY]=st [OTHER_WRITABLE]=ow [OWR]=ow
  [STICKY_OTHER_WRITABLE]=tw [OWT]=tw [CAPABILITY]=ca [MULTIHARDLINK]=mh
  [CLRTOEOL]=cl
)
declare -A TYPE_NAME=(
  [no]=NORMAL ["fi"]=FILE [rs]=RESET [di]=DIR [ln]=LINK [or]=ORPHAN [mi]=MISSING
  [pi]=FIFO [so]=SOCK [bd]=BLK [cd]=CHR ["do"]=DOOR [ex]=EXEC [su]=SETUID
  [sg]=SETGID [st]=STICKY [ow]=OTHER_WRITABLE [tw]=STICKY_OTHER_WRITABLE
  [ca]=CAPABILITY [mh]=MULTIHARDLINK [lc]=LEFT [rc]=RIGHT [ec]=END [cl]=CLRTOEOL
)
declare -A TYPE_SAMPLE=(
  [no]=text ["fi"]=file [rs]=reset [di]=dir [ln]=link [or]=orphan [mi]=missing
  [pi]=fifo [so]=socket [bd]=block_device [cd]=char_device ["do"]=door
  [ex]=executable [su]=setuid [sg]=setgid [st]=sticky [ow]=other_writable
  [tw]=sticky_other_writable [ca]=capability [mh]=multihardlink
)
# Every code, in the order ls documents them. A string rather than a literal
# list in the loops, because "fi" and "do" are shell keywords.
TYPE_CODES="no fi rs di ln or mi pi so bd cd do ex su sg st ow tw ca mh lc rc ec cl"
# The file types preview lists, in display order.
TYPES_SHOWN="fi di ln or pi so bd cd ex su sg st ow tw mh"
# File types a config is expected to set; anything missing is reported.
TYPES_EXPECTED="di ln or mi pi so bd cd ex su sg st ow tw"
# Keys whose value is not an SGR colour code.
TYPES_RAW="lc rc ec cl"

# ---------------------------------------------------------------------------
# Categories: the curated table of common extensions
# ---------------------------------------------------------------------------

CAT_ORDER="executables archives images audio video documents source config temporary"

# Words in a section heading that give the section a category.
declare -A CAT_WORDS=(
  [executables]="exec binar"
  [archives]="archiv compress packag"
  [images]="image picture graphic photo"
  [audio]="audio music sound"
  [video]="video movie film"
  [documents]="document text office book"
  [source]="source code program script develop"
  [config]="config dotfile setting"
  [temporary]="backup temp junk"
)

# Extensions that are suggested when the config does not colour them.
declare -A CAT_SUGGEST=(
  [executables]=".exe .com .bat .cmd .msi .app .appimage .run .bin"
  [archives]=".tar .tgz .tbz2 .txz .gz .bz2 .xz .zst .lz4 .lzma .zip .7z .rar .cab .cpio .deb .rpm .jar .iso .img .dmg"
  [images]=".jpg .jpeg .png .gif .bmp .tif .tiff .webp .avif .heic .svg .ico .xcf .psd"
  [audio]=".mp3 .flac .ogg .oga .opus .m4a .aac .wav .wma .aiff .mid .midi"
  [video]=".mp4 .mkv .webm .avi .mov .wmv .flv .m4v .mpg .mpeg .ogv"
  [documents]=".pdf .txt .md .rtf .doc .docx .odt .xls .xlsx .ods .ppt .pptx .odp .csv .epub .tex"
  [source]=".c .h .cpp .hpp .cc .cs .go .rs .java .kt .py .rb .pl .php .js .mjs .jsx .tsx .lua .sh .bash .zsh .fish .swift .sql .html .htm .css .scss"
  [config]=".json .yml .yaml .toml .xml .ini .conf .cfg"
  [temporary]=".bak .tmp .swp .old .orig .part *~"
)
# Extensions that are recognised (for section checks and reorganising) but
# not suggested.
declare -A CAT_KNOWN=(
  [executables]=".btm .ps1 .dll .so .apk"
  [archives]=".tar.gz .tar.xz .tar.bz2 .tar.zst .tbz .tzst .tlz .lz .lzo .lzop .lrz .z .ace .arj .war .ear .pkg .zoo .alz"
  [images]=".ppm .pgm .pbm .xpm .xbm .tga .pcx .jxl .svgz .mng .cr2 .nef .dng .eps"
  [audio]=".ape .ac3 .dts .aiffc .au .mka .mpc .ra .spx .weba .m4b"
  [video]=".ogm .vob .m2ts .3gp .fli .flc .swf .rm .rmvb .asf .qt .m2v .mp4v"
  [documents]=".ps .djvu .mobi .markdown .mkd .rst .org .pps .ppsx .pot .potm .ott .ots .otp .odg .fodt .textile .nfo"
  [source]=".coffee .tcl .ex .exs .erl .clj .scala .dart .nim .zig .ml .pm .hs .lisp .el .vim .awk .sed .asm .jsm .jsp .r .vue .diff .patch *makefile *dockerfile"
  [config]=".rc .properties .desktop .service .bashrc .bash_profile .zshrc .zlogin .vimrc .nvimrc .gitconfig .gitignore .hgrc .hgignore .inputrc .xinitrc .xresources .xdefaults .xmodmap .muttrc .netrc"
  [temporary]=".pacnew .pacsave .dpkg-old .dpkg-new .dpkg-dist .rpmnew .rpmsave .rej .pid .lock .log .crdownload"
)
declare -A CUR_CAT=()      # lower-cased pattern -> category

# norm_pattern KEY -> RET: the pattern as it appears in LS_COLORS.
norm_pattern() {
  case $1 in
    .*) RET="*$1" ;;
    *)  RET=$1 ;;
  esac
}

init_tables() {
  local cat w
  local -a words=()
  [[ ${#CUR_CAT[@]} -gt 0 ]] && return
  for cat in $CAT_ORDER; do
    # read -a splits without globbing: the lists contain patterns such as *~
    read -r -a words <<<"${CAT_SUGGEST[$cat]}"
    for w in "${words[@]}"; do
      norm_pattern "$w"
      CUR_CAT[$RET]=$cat
    done
    read -r -a words <<<"${CAT_KNOWN[$cat]}"
    for w in "${words[@]}"; do
      norm_pattern "$w"
      CUR_CAT[$RET]=$cat
    done
  done
}

# section_category TITLE -> RET: category named by a heading, or "".
section_category() {
  local title=${1,,} cat w
  RET=""
  for cat in $CAT_ORDER; do
    for w in ${CAT_WORDS[$cat]}; do
      if [[ $title == *"$w"* ]]; then RET=$cat; return; fi
    done
  done
}

# ---------------------------------------------------------------------------
# Small helpers
# ---------------------------------------------------------------------------

err()  { printf '%s: %s\n' "$PROG" "$*" >&2; }
die()  { err "$@"; exit 2; }

setup_colour() {
  case $OPT_COLOUR in
    always) USE_COLOUR=1 ;;
    never)  USE_COLOUR=0 ;;
    *)      if [[ -t 1 && -z ${NO_COLOR:-} ]]; then USE_COLOUR=1; else USE_COLOUR=0; fi ;;
  esac
  if (( USE_COLOUR )); then
    C_B="${ESC}[1m" C_D="${ESC}[2m" C_R="${ESC}[31m" C_G="${ESC}[32m"
    C_Y="${ESC}[33m" C_C="${ESC}[36m" C_U="${ESC}[4m" C_0="${ESC}[0m"
  else
    C_B="" C_D="" C_R="" C_G="" C_Y="" C_C="" C_U="" C_0=""
  fi
}
C_B="" C_D="" C_R="" C_G="" C_Y="" C_C="" C_U="" C_0=""

# paint CODE TEXT -> RET: TEXT wrapped in the SGR code, the way ls prints it.
paint() {
  if (( USE_COLOUR )) && [[ $1 =~ $RE_SGR ]]; then
    RET="${ESC}[0;${1}m${2}${ESC}[0m"
  else
    RET=$2
  fi
}

# sample_name PATTERN -> RET: a file name that the pattern matches.
sample_name() {
  local rest=${1#\*}
  case $rest in
    .*) RET="example$rest" ;;
    *)  RET=$rest ;;
  esac
}

# strip_sgr TEXT -> RET without escape sequences (ESC [ numbers m or K).
# A loop over the sequences: an extglob pattern is far slower on rows with
# many colours.
strip_sgr() {
  local t=$1 out="" seq
  while [[ $t == *"${ESC}["* ]]; do
    out+=${t%%"${ESC}["*}
    t=${t#*"${ESC}["}
    seq=${t%%[!0-9;]*}
    t=${t:${#seq}}
    case $t in
      [mK]*) t=${t:1} ;;
      *)     out+="${ESC}[$seq" ;;
    esac
  done
  RET=$out$t
}

# resolve_path PATH -> RET: PATH with a final symlink chain followed.
resolve_path() {
  local p=$1 t n=0
  [[ $p == */* ]] || p="./$p"
  while [[ -L $p ]] && (( n++ < 40 )); do
    t=$(readlink -- "$p") || break
    if [[ $t == /* ]]; then p=$t; else p="${p%/*}/$t"; fi
  done
  RET=$p
}

term_size() {
  local size
  ROWS=24 COLS=80
  if size=$(stty size 2>/dev/null </dev/tty) && [[ $size =~ ^([0-9]+)\ ([0-9]+)$ ]]; then
    (( BASH_REMATCH[1] > 0 )) && ROWS=${BASH_REMATCH[1]}
    (( BASH_REMATCH[2] > 0 )) && COLS=${BASH_REMATCH[2]}
  elif [[ ${COLUMNS:-} =~ $RE_NUM ]] && (( COLUMNS > 0 )); then
    COLS=$COLUMNS
    [[ ${LINES:-} =~ $RE_NUM ]] && (( LINES > 0 )) && ROWS=$LINES
  fi
}
ROWS=24 COLS=80

cleanup() {
  if (( TUI_ACTIVE )); then
    TUI_ACTIVE=0
    printf '%s' "${ESC}[0m${ESC}[?25h${ESC}[?1049l"
    [[ -n $STTY_SAVED ]] && stty "$STTY_SAVED" 2>/dev/null </dev/tty
  fi
  [[ -n $TMP_FILE && -e $TMP_FILE ]] && rm -f -- "$TMP_FILE"
  if [[ -n $TMP_DIR && -d $TMP_DIR ]]; then
    if (( OPT_KEEP )); then
      printf '\nsamples kept in %s\n' "$TMP_DIR"
    else
      chmod -R u+rwx -- "$TMP_DIR" 2>/dev/null
      rm -rf -- "$TMP_DIR"
    fi
  fi
  TMP_DIR="" TMP_FILE=""
}

install_traps() {
  trap cleanup EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  trap 'exit 129' HUP
}

# ---------------------------------------------------------------------------
# Tools: find GNU ls and dircolors
# ---------------------------------------------------------------------------

# A candidate pair is usable when ls knows --color and dircolors can print its
# database. Besides GNU this accepts compatible reimplementations (uutils).
tools_usable() {
  command -v "$1" >/dev/null 2>&1 || return 1
  command -v "$2" >/dev/null 2>&1 || return 1
  "$1" --color=always -d / >/dev/null 2>&1 || return 1
  "$2" --print-database >/dev/null 2>&1 || return 1
}

detect_tools() {
  local pair l d
  [[ -n $LS && -n $DC ]] && return 0
  if [[ -n ${LSCC_LS:-} || -n ${LSCC_DIRCOLORS:-} ]]; then
    LS=${LSCC_LS:-ls} DC=${LSCC_DIRCOLORS:-dircolors}
    tools_usable "$LS" "$DC" && return 0
    err "$LS / $DC (from LSCC_LS / LSCC_DIRCOLORS) are not GNU ls and dircolors."
    exit 1
  fi
  for pair in "ls dircolors" "gls gdircolors" "gnuls gnudircolors"; do
    l=${pair% *} d=${pair#* }
    if tools_usable "$l" "$d"; then LS=$l DC=$d; return 0; fi
  done
  err "GNU ls and dircolors not found."
  err "Install GNU coreutils (macOS: brew install coreutils, which provides gls and gdircolors)."
  exit 1
}

# Newer ls versions match extensions without regard to case, as long as the
# differently-cased entries do not disagree. Ask the installed ls.
probe_nocase() {
  local d out
  LS_NOCASE=0
  d=$(mktemp -d "${TMPDIR:-/tmp}/lscc.XXXXXX") || return 0
  : >"$d/probe.lsccprobe"
  out=$(LS_COLORS='*.LSCCPROBE=01;31' "$LS" --color=always -- "$d/probe.lsccprobe" 2>/dev/null)
  [[ $out == *"01;31"* ]] && LS_NOCASE=1
  rm -rf -- "$d"
}

# ---------------------------------------------------------------------------
# Parser
# ---------------------------------------------------------------------------

# parse: build the per-line model from SRC[1..N]. Mirrors what dircolors does:
# a line is KEY VALUE, "#" starts a comment, TERM/COLORTERM lines scope the
# lines after them.
parse() {
  local i line key rest val post t upper kind norm lower
  local state=G scope="" prev_term=0 pend_title="" pend_line=0 cur=0 subject
  local term=${OPT_TERM:-${TERM:-}}
  L_KIND=() L_KEY=() L_VAL=() L_PRE=() L_POST=() L_SEC=() L_ACTIVE=() L_SCOPE=() L_NORM=()
  SEC_TITLE=("(no section)") SEC_LINE=(0) SEC_CAT=("")
  PAT_LINES=() LPAT=() TYPE_LINES=() PAT_ORDER=()
  LAST_COLOUR_LINE=0
  init_tables

  for (( i = 1; i <= N; i++ )); do
    line=${SRC[i]}
    L_KIND[i]=blank L_KEY[i]="" L_VAL[i]="" L_PRE[i]="" L_POST[i]=""
    L_SEC[i]=0 L_ACTIVE[i]=1 L_SCOPE[i]="" L_NORM[i]=""
    [[ $line =~ $RE_BLANK ]] && continue

    if [[ $line =~ $RE_COMMENT ]]; then
      L_KIND[i]=comment
      # The last comment before a group of patterns is its section heading.
      t=${line#"${line%%[!#+[:space:]]*}"}
      t=${t%"${t##*[![:space:]:#]}"}
      if [[ $t =~ $RE_ALNUM && ! $t =~ $RE_COMMENTED ]]; then
        pend_title=$t pend_line=$i
      fi
      continue
    fi

    [[ $line =~ $RE_ENTRY ]] || continue
    key=${BASH_REMATCH[2]} rest=${BASH_REMATCH[4]}
    L_PRE[i]="${BASH_REMATCH[1]}${key}${BASH_REMATCH[3]}"
    val=${rest%%#*}
    post=${rest:${#val}}
    t=${val%"${val##*[![:space:]]}"}
    post="${val:${#t}}${post}"
    val=$t
    L_KEY[i]=$key L_VAL[i]=$val L_POST[i]=$post

    upper=${key^^} norm=""
    case $upper in
      TERM|COLORTERM)         kind=term ;;
      COLOR|OPTIONS|EIGHTBIT) kind=obsolete ;;
      .*)                     kind=pattern norm="*$key" ;;
      \*)                     kind=other ;;
      \**)                    kind=pattern norm=$key ;;
      *)
        if [[ $upper =~ $RE_WORD && -n ${TYPE_CODE[$upper]:-} ]]; then
          kind=type norm=${TYPE_CODE[$upper]}
        else
          kind=unknown
        fi ;;
    esac
    L_KIND[i]=$kind L_NORM[i]=$norm

    if [[ $kind == term ]]; then
      (( prev_term )) || scope=""
      scope+="${scope:+, }$val"
      prev_term=1
      if [[ $state != S ]]; then
        if [[ $upper == TERM ]]; then subject=$term; else subject=${COLORTERM:-}; fi
        # The value is a glob pattern, exactly as in dircolors (fnmatch).
        # shellcheck disable=SC2053
        if [[ -n $val && $subject == $val ]]; then state=S; else state=N; fi
      fi
      L_SCOPE[i]=$scope
      cur=0 pend_line=0
      continue
    fi

    prev_term=0
    [[ $state == S ]] && state=Y
    [[ $state == N ]] && L_ACTIVE[i]=0
    [[ $state != G ]] && L_SCOPE[i]=$scope

    case $kind in
      pattern)
        if (( pend_line )); then
          cur=${#SEC_TITLE[@]}
          SEC_TITLE[cur]=$pend_title SEC_LINE[cur]=$pend_line
          section_category "$pend_title"
          SEC_CAT[cur]=$RET
          pend_line=0
        fi
        L_SEC[i]=$cur
        [[ -n ${PAT_LINES[$norm]:-} ]] || PAT_ORDER+=("$norm")
        PAT_LINES[$norm]+=" $i"
        lower=${norm,,}
        [[ " ${LPAT[$lower]:-} " == *" $norm "* ]] || LPAT[$lower]+=" $norm"
        LAST_COLOUR_LINE=$i ;;
      type)
        TYPE_LINES[$norm]+=" $i"
        LAST_COLOUR_LINE=$i
        cur=0 pend_line=0 ;;
      *)
        cur=0 pend_line=0 ;;
    esac
  done
}

# effective LINES -> RET: value of the last active definition, RET2: its line.
# "Last one wins" is how ls reads LS_COLORS.
effective() {
  local i
  RET="" RET2=0
  for i in $1; do
    if (( L_ACTIVE[i] )) && [[ -n ${L_VAL[i]} ]]; then RET=${L_VAL[i]} RET2=$i; fi
  done
}

# entry_category PATTERN SECTION -> RET: curated category, else the section's.
entry_category() {
  RET=${CUR_CAT[${1,,}]:-}
  [[ -n $RET ]] || RET=${SEC_CAT[$2]:-}
}

# ---------------------------------------------------------------------------
# SGR codes
# ---------------------------------------------------------------------------

SGR_FG="" SGR_BG="" SGR_ATTRS="" SGR_EXTRA="" SGR_BAD="" SGR_UNKNOWN=""
SGR_EXT=0 SGR_PAD=1 SGR_ZERO=0

# sgr_parse VALUE: split a colour value into foreground, background,
# attributes (1 bold, 2 dim, 4 underline, 5 blink, 7 reverse) and the rest.
sgr_parse() {
  local v=$1 n tok i a b c
  local -a toks=()
  SGR_FG="" SGR_BG="" SGR_ATTRS=" " SGR_EXTRA="" SGR_BAD="" SGR_UNKNOWN=""
  SGR_EXT=0 SGR_PAD=1 SGR_ZERO=0
  if [[ -z $v || $v == \;* || $v == *\; || $v == *\;\;* ]]; then
    SGR_BAD=${v:-empty}
    return
  fi
  [[ ";$v;" =~ \;[1-9]\; ]] && SGR_PAD=0
  IFS=';' read -r -a toks <<<"$v"
  for (( i = 0; i < ${#toks[@]}; i++ )); do
    tok=${toks[i]}
    if [[ ! $tok =~ $RE_NUM ]] || (( ${#tok} > 3 )); then
      SGR_BAD+="${SGR_BAD:+ }$tok"
      continue
    fi
    n=$(( 10#$tok ))
    case $n in
      38|48)
        a=${toks[i+1]:-} b=""
        if [[ $a == 5 || $a == 05 ]] && [[ ${toks[i+2]:-} =~ $RE_NUM ]] && (( 10#${toks[i+2]} <= 255 )); then
          b="$tok;$a;${toks[i+2]}"
          (( i += 2 ))
        elif [[ $a == 2 || $a == 02 ]]; then
          b="$tok;$a"
          for c in 2 3 4; do
            if [[ ${toks[i+c]:-} =~ $RE_NUM ]] && (( 10#${toks[i+c]} <= 255 )); then
              b+=";${toks[i+c]}"
            else
              b=""
              break
            fi
          done
          [[ -n $b ]] && (( i += 4 ))
        fi
        if [[ -z $b ]]; then
          SGR_BAD+="${SGR_BAD:+ }$tok"
        else
          SGR_EXT=1
          if (( n == 38 )); then SGR_FG=$b; else SGR_BG=$b; fi
        fi ;;
      0) SGR_ZERO=1 ;;
      1|2|4|5|7) [[ $SGR_ATTRS == *" $n "* ]] || SGR_ATTRS+="$n " ;;
      3|6|8|9|2[1-9]|39|49) SGR_EXTRA+="${SGR_EXTRA:+;}$tok" ;;
      3[0-7]|9[0-7]) SGR_FG=$tok ;;
      4[0-7]|10[0-7]) SGR_BG=$tok ;;
      *) SGR_UNKNOWN+="${SGR_UNKNOWN:+ }$tok" ;;
    esac
  done
}

# sgr_compose FG BG ATTRS EXTRA PAD ZERO -> RET: a value from its parts.
sgr_compose() {
  local fg=$1 bg=$2 attrs=$3 extra=$4 pad=$5 zero=$6 out="" a
  for a in 1 2 4 5 7; do
    if [[ $attrs == *" $a "* ]]; then
      if (( pad )); then out+="${out:+;}0$a"; else out+="${out:+;}$a"; fi
    fi
  done
  [[ -n $extra ]] && out+="${out:+;}$extra"
  # Keep a leading "00" when the original value had one and nothing else
  # would come before the colour.
  if [[ -z $out ]] && (( zero )) && [[ -n $fg$bg ]]; then
    if (( pad )); then out="00"; else out="0"; fi
  fi
  [[ -n $fg ]] && out+="${out:+;}$fg"
  [[ -n $bg ]] && out+="${out:+;}$bg"
  if [[ -z $out ]]; then
    if (( pad )); then out="00"; else out="0"; fi
  fi
  RET=$out
}

# ---------------------------------------------------------------------------
# Reading, editing and writing the document
# ---------------------------------------------------------------------------

# read_file PATH: load the file into SRC/ORIG and parse it.
read_file() {
  local -a file_lines=()
  if ! mapfile -t file_lines <"$1"; then
    err "cannot read $1"
    return 1
  fi
  FILE_EOL=1
  if [[ -s $1 && -n $(tail -c 1 -- "$1") ]]; then FILE_EOL=0; fi
  SRC=("" "${file_lines[@]}")
  N=${#file_lines[@]}
  ORIG=("${SRC[@]}")
  DEL=() INS=()
  parse
}

# set_value LINE VALUE: change the value on one line and nothing else on it.
set_value() {
  local i=$1
  SRC[i]="${L_PRE[i]}$2${L_POST[i]}"
  L_VAL[i]=$2
}

# Structural edits are queued, then applied in one pass by doc_rebuild.
delete_line()  { DEL[$1]=1; }
insert_after() { INS[$1]+="$2$NL"; }   # line 0 inserts at the top

doc_rebuild() {
  local i l
  local -a doc=("") extra=()
  for (( i = 0; i <= N; i++ )); do
    if (( i > 0 )) && [[ -z ${DEL[i]:-} ]]; then doc+=("${SRC[i]}"); fi
    if [[ -n ${INS[i]:-} ]]; then
      mapfile -t extra <<<"${INS[i]%"$NL"}"
      for l in "${extra[@]}"; do doc+=("$l"); done
    fi
  done
  SRC=("${doc[@]}")
  N=$(( ${#SRC[@]} - 1 ))
  DEL=() INS=()
  parse
}

# doc_changed: true when SRC differs from the text on disk.
doc_changed() {
  local i
  (( ${#SRC[@]} == ${#ORIG[@]} )) || return 0
  for (( i = 1; i <= N; i++ )); do
    [[ ${SRC[i]} == "${ORIG[i]}" ]] || return 0
  done
  return 1
}

doc_print() {
  local i
  for (( i = 1; i <= N; i++ )); do
    if (( i == N && ! FILE_EOL )); then
      printf '%s' "${SRC[i]}"
    else
      printf '%s\n' "${SRC[i]}"
    fi
  done
}

# save_file: back up once per run, then replace the file atomically.
# Returns 0 written, 1 nothing to write, 2 failed.
save_file() {
  local stamp bak dir n=0 i
  local -a now=()
  doc_changed || return 1
  if (( OPT_DRY )); then
    printf 'Dry run: %s was not changed.\n' "$FILE"
    return 1
  fi
  # Refuse to overwrite edits made by someone else since the file was read.
  mapfile -t now <"$FILE_REAL" || { err "cannot read $FILE_REAL"; return 2; }
  if (( ${#now[@]} != ${#ORIG[@]} - 1 )); then n=1; fi
  for (( i = 0; i < ${#now[@]} && ! n; i++ )); do
    [[ ${now[i]} == "${ORIG[i+1]}" ]] || n=1
  done
  if (( n )); then
    err "$FILE changed on disk while it was open here. Nothing was written."
    return 2
  fi
  dir=${FILE_REAL%/*}
  if [[ -z $BACKUP_PATH ]]; then
    stamp=$(date +%Y%m%d-%H%M%S)
    bak="$FILE_REAL.bak-$stamp"
    n=1
    while [[ -e $bak ]]; do n=$(( n + 1 )); bak="$FILE_REAL.bak-$stamp-$n"; done
    if ! cp -p -- "$FILE_REAL" "$bak"; then
      err "could not create the backup $bak. Nothing was written."
      return 2
    fi
    BACKUP_PATH=$bak
  fi
  if ! TMP_FILE=$(mktemp "$dir/.lscc.XXXXXX"); then
    err "could not create a temporary file in $dir. Nothing was written."
    return 2
  fi
  # cp -p first so the temporary file carries the mode of the original.
  if cp -p -- "$FILE_REAL" "$TMP_FILE" && doc_print >"$TMP_FILE" && mv -f -- "$TMP_FILE" "$FILE_REAL"; then
    TMP_FILE=""
    ORIG=("${SRC[@]}")
    return 0
  fi
  rm -f -- "$TMP_FILE"
  TMP_FILE=""
  err "writing $FILE_REAL failed. The file is unchanged; backup: $BACKUP_PATH"
  return 2
}

# ---------------------------------------------------------------------------
# Diff between the text on disk (ORIG) and the document (SRC)
# ---------------------------------------------------------------------------

declare -a DIFF=()   # entries "K a b": K is = - or +, a/b are line numbers
DIFF_ADDED=0 DIFF_REMOVED=0

make_diff() {
  local n=$(( ${#ORIG[@]} - 1 )) m=$N s=0 e=0 i j an bn w k x y
  local -A ids=()
  local -a ia=() ib=() tbl=()
  DIFF=() DIFF_ADDED=0 DIFF_REMOVED=0
  while (( s < n && s < m )) && [[ ${ORIG[s+1]} == "${SRC[s+1]}" ]]; do (( s++ )); done
  while (( e < n - s && e < m - s )) && [[ ${ORIG[n-e]} == "${SRC[m-e]}" ]]; do (( e++ )); done
  an=$(( n - s - e )) bn=$(( m - s - e ))
  for (( i = 1; i <= s; i++ )); do DIFF+=("= $i $i"); done

  if (( an * bn > 4000000 )); then
    # Too large for the table: show the middle as replaced wholesale.
    for (( i = 1; i <= an; i++ )); do DIFF+=("- $(( s + i )) 0"); done
    for (( j = 1; j <= bn; j++ )); do DIFF+=("+ 0 $(( s + j ))"); done
  elif (( an > 0 || bn > 0 )); then
    # Map lines to numbers once, then run a plain LCS on the numbers.
    k=0
    for (( i = 0; i < an; i++ )); do
      x="=${ORIG[s+1+i]}"
      [[ -n ${ids[$x]:-} ]] || ids[$x]=$(( ++k ))
      ia[i]=${ids[$x]}
    done
    for (( j = 0; j < bn; j++ )); do
      x="=${SRC[s+1+j]}"
      [[ -n ${ids[$x]:-} ]] || ids[$x]=$(( ++k ))
      ib[j]=${ids[$x]}
    done
    w=$(( bn + 1 ))
    for (( j = 0; j <= bn; j++ )); do tbl[an*w+j]=0; done
    for (( i = an - 1; i >= 0; i-- )); do
      tbl[i*w+bn]=0
      for (( j = bn - 1; j >= 0; j-- )); do
        if (( ia[i] == ib[j] )); then
          tbl[i*w+j]=$(( tbl[(i+1)*w+j+1] + 1 ))
        else
          x=${tbl[(i+1)*w+j]} y=${tbl[i*w+j+1]}
          tbl[i*w+j]=$(( x > y ? x : y ))
        fi
      done
    done
    i=0 j=0
    while (( i < an || j < bn )); do
      if (( i < an && j < bn && ia[i] == ib[j] )); then
        DIFF+=("= $(( s + i + 1 )) $(( s + j + 1 ))")
        (( i++, j++ ))
      elif (( j >= bn || ( i < an && tbl[(i+1)*w+j] >= tbl[i*w+j+1] ) )); then
        DIFF+=("- $(( s + i + 1 )) 0")
        (( i++ ))
      else
        DIFF+=("+ 0 $(( s + j + 1 ))")
        (( j++ ))
      fi
    done
  fi
  for (( i = 1; i <= e; i++ )); do DIFF+=("= $(( n - e + i )) $(( m - e + i ))"); done
  for x in "${DIFF[@]}"; do
    case $x in
      -*) (( DIFF_REMOVED++ )) ;;
      +*) (( DIFF_ADDED++ )) ;;
    esac
  done
}

# print_diff: show the pending changes with two lines of context.
print_diff() {
  local idx k a b show last=-1 total
  local -a near=()
  make_diff
  total=${#DIFF[@]}
  if (( DIFF_ADDED == 0 && DIFF_REMOVED == 0 )); then
    printf 'No changes.\n'
    return 1
  fi
  for (( idx = 0; idx < total; idx++ )); do
    if [[ ${DIFF[idx]} != =* ]]; then
      for (( k = idx - 2; k <= idx + 2; k++ )); do
        (( k >= 0 && k < total )) && near[k]=1
      done
    fi
  done
  for (( idx = 0; idx < total; idx++ )); do
    [[ -n ${near[idx]:-} ]] || continue
    read -r k a b <<<"${DIFF[idx]}"
    if (( last >= 0 && idx != last + 1 )) || (( last < 0 )); then
      show=$a
      (( show )) || show=$b
      printf '%s@@ line %s @@%s\n' "$C_C" "$show" "$C_0"
    fi
    last=$idx
    case $k in
      =) printf '  %4s  %s\n' "$a" "${ORIG[a]}" ;;
      -) printf '%s- %4s  %s%s\n' "$C_R" "$a" "${ORIG[a]}" "$C_0" ;;
      +) printf '%s+ %4s  %s%s\n' "$C_G" "$b" "${SRC[b]}" "$C_0" ;;
    esac
  done
  printf '%s%d line(s) removed, %d line(s) added.%s\n' "$C_B" "$DIFF_REMOVED" "$DIFF_ADDED" "$C_0"
  return 0
}

# ---------------------------------------------------------------------------
# Config file discovery
# ---------------------------------------------------------------------------

sample_config() {
  cat <<'SAMPLE'
# dircolors configuration: the colours of `ls --color`.
#
# Load it from your shell start-up file:
#   eval "$(dircolors -b ~/.config/dircolors)"
#
# Every line is KEY VALUE. A value is a list of codes joined by ";".
#   attributes: 00 none, 01 bold, 02 dim, 04 underline, 07 reverse
#   text:       30 black, 31 red, 32 green, 33 yellow,
#               34 blue, 35 magenta, 36 cyan, 37 white
#   background: 40 to 47, in the same order as the text colours

# file types
RESET 0
DIR 01;34
LINK 01;36
ORPHAN 01;31
MISSING 02;31
FIFO 33
SOCK 01;35
BLK 01;33
CHR 33
EXEC 01;32
SETUID 37;41
SETGID 30;43
STICKY 37;44
OTHER_WRITABLE 34;42
STICKY_OTHER_WRITABLE 30;42
MULTIHARDLINK 00
CAPABILITY 00

# executables
.exe 01;32
.bat 01;32
.cmd 01;32
.appimage 01;32

# archives
.tar 31
.gz 31
.xz 31
.zip 31
.7z 31
.deb 31

# images
.jpg 35
.jpeg 35
.png 35
.gif 35
.svg 35
.webp 35

# audio
.mp3 36
.flac 36
.ogg 36
.wav 36

# video
.mp4 01;35
.mkv 01;35
.webm 01;35
.avi 01;35

# documents
.pdf 34
.txt 34
.md 34
.odt 34
.csv 34

# source code
.c 32
.h 32
.py 32
.js 32
.sh 32
.html 32

# config files
.json 33
.yml 33
.toml 33
.ini 33
.conf 33

# backup and temporary files
.bak 02;37
.tmp 02;37
.swp 02;37
*~ 02;37
SAMPLE
}

# find_config: set FILE to the first existing default location.
find_config() {
  local x=${XDG_CONFIG_HOME:-$HOME/.config} f
  for f in "$x/dircolors" "$x/.dir_colors" "$HOME/.dir_colors" "$HOME/.dircolors"; do
    if [[ -f $f ]]; then FILE=$f; return 0; fi
  done
  return 1
}

# offer_sample: no config exists; create one from the built-in sample if the
# user agrees.
offer_sample() {
  local x=${XDG_CONFIG_HOME:-$HOME/.config} target answer
  target="$x/dircolors"
  err "no dircolors file found in the usual places:"
  err "  $x/dircolors, $x/.dir_colors, $HOME/.dir_colors, $HOME/.dircolors"
  if [[ ! -t 0 || ! -t 1 ]]; then
    err "Pass a file as argument, or create one with: $PROG sample > $target"
    exit 1
  fi
  printf 'Create %s from the built-in sample? [y/N] ' "$target"
  read -r answer || answer=""
  if [[ $answer != [yY]* ]]; then exit 1; fi
  if ! mkdir -p -- "$x" || ! sample_config >"$target"; then
    err "could not write $target"
    exit 1
  fi
  printf 'Created %s. To use it, add this line to your shell start-up file:\n' "$target"
  # The command substitution is text for the user to copy, not to be run here.
  # shellcheck disable=SC2016
  printf '  eval "$(dircolors -b %s)"\n\n' "$target"
  FILE=$target
}

load_config() {
  if [[ -z $FILE ]]; then
    find_config || offer_sample
  fi
  if [[ -d $FILE ]]; then die "$FILE is a directory"; fi
  if [[ ! -e $FILE ]]; then die "$FILE does not exist"; fi
  if [[ ! -r $FILE ]]; then die "$FILE is not readable"; fi
  resolve_path "$FILE"
  FILE_REAL=$RET
  read_file "$FILE_REAL" || exit 1
}

# ---------------------------------------------------------------------------
# The system database (dircolors --print-database)
# ---------------------------------------------------------------------------

declare -A DB_VAL=() DB_CAT=() DB_TYPE=()
declare -a DB_ORDER=()
DB_LOADED=0

# load_db: read the database of the installed dircolors. LSCC_DATABASE names
# a file to read instead (used by the tests).
load_db() {
  local line key val t cat="" upper
  (( DB_LOADED )) && return
  DB_LOADED=1
  detect_tools
  while IFS= read -r line; do
    if [[ $line =~ $RE_COMMENT ]]; then
      t=${line#"${line%%[!#+[:space:]]*}"}
      t=${t%"${t##*[![:space:]:#]}"}
      if [[ $t =~ $RE_ALNUM && ! $t =~ $RE_COMMENTED ]]; then
        section_category "$t"
        cat=$RET
      fi
      continue
    fi
    [[ $line =~ $RE_ENTRY ]] || continue
    key=${BASH_REMATCH[2]} val=${BASH_REMATCH[4]}
    val=${val%%#*}
    val=${val%"${val##*[![:space:]]}"}
    [[ -n $val ]] || continue
    case $key in
      .*|\*?*)
        norm_pattern "$key"
        key=${RET,,}
        [[ -n ${DB_VAL[$key]:-} ]] || DB_ORDER+=("$key")
        DB_VAL[$key]=$val DB_CAT[$key]=$cat ;;
      *)
        upper=${key^^}
        if [[ $upper =~ $RE_WORD && -n ${TYPE_CODE[$upper]:-} ]]; then
          DB_TYPE[${TYPE_CODE[$upper]}]=$val
        fi ;;
    esac
  done < <(if [[ -n ${LSCC_DATABASE:-} ]]; then cat -- "$LSCC_DATABASE"; else "$DC" --print-database 2>/dev/null; fi)
}

# ---------------------------------------------------------------------------
# Missing entries
# ---------------------------------------------------------------------------

declare -A CAT_MAJ=()      # category -> the value most of its entries have
declare -A CAT_MAJ_N=() CAT_TOTAL=()   # how many entries have it, out of how many
declare -a O_PAT=() O_LINE=() O_VAL=() O_CAT=()   # entries that stand out
TWIN_CONVENTION=0          # 1 when the file writes upper-case twins as a rule
declare -a M_PAT=() M_CAT=() M_SRC=() M_VAL=() M_WHY=()   # missing patterns
declare -a MT_CODE=() MT_VAL=()                           # missing file types
declare -A SCAN_COUNT=()   # pattern -> number of files found by --scan
declare -a SCAN_EXT=()

# compute_majorities: the colour that more than half of the entries of a
# category have. New entries of that category get the same colour.
compute_majorities() {
  local -A tally=() sum=() spelt=()
  local p cat val k lowers=0 twins=0
  CAT_MAJ=() CAT_MAJ_N=() CAT_TOTAL=()
  for p in "${PAT_ORDER[@]}"; do
    effective "${PAT_LINES[$p]}"
    (( RET2 )) || continue
    val=$RET
    entry_category "$p" "${L_SEC[RET2]}"
    cat=$RET
    if [[ -n $cat ]]; then
      # 00;34 and 34 are the same colour: count them together, and keep
      # the spelling that came first as the one to propose
      plain_colour "$val"
      sum[$cat]=$(( ${sum[$cat]:-0} + 1 ))
      tally[$cat $RET]=$(( ${tally[$cat $RET]:-0} + 1 ))
      [[ -n ${spelt[$cat $RET]:-} ]] || spelt[$cat $RET]=$val
    fi
    if [[ $p == \*.* && $p == "${p,,}" && $p == *[a-z]* ]]; then
      lowers=$(( lowers + 1 ))
      [[ -n ${PAT_LINES[${p^^}]:-} ]] && twins=$(( twins + 1 ))
    fi
  done
  for k in "${!tally[@]}"; do
    cat=${k%% *}
    if (( ${tally[$k]} * 2 > ${sum[$cat]} )); then
      CAT_MAJ[$cat]=${spelt[$k]} CAT_MAJ_N[$cat]=${tally[$k]} CAT_TOTAL[$cat]=${sum[$cat]}
    fi
  done
  TWIN_CONVENTION=0
  if (( twins > 0 && twins * 2 >= lowers )); then TWIN_CONVENTION=1; fi
}

# plain_colour VALUE -> RET: VALUE without a leading reset, so that 00;34
# and 34 compare as the same colour.
plain_colour() {
  RET=$1
  RET=${RET#00;}
  RET=${RET#0;}
}

# find_outliers: entries whose colour differs from the colour that nearly
# all entries of their category have (at least 80 % of at least 5).
# Needs compute_majorities to have run.
find_outliers() {
  local p lower cat val line maj
  O_PAT=() O_LINE=() O_VAL=() O_CAT=()
  for p in "${PAT_ORDER[@]}"; do
    effective "${PAT_LINES[$p]}"
    (( RET2 )) || continue
    val=$RET line=$RET2
    entry_category "$p" "${L_SEC[line]}"
    cat=$RET
    [[ -n $cat && -n ${CAT_MAJ[$cat]:-} ]] || continue
    (( ${CAT_TOTAL[$cat]} >= 5 && ${CAT_MAJ_N[$cat]} * 100 >= ${CAT_TOTAL[$cat]} * 80 )) || continue
    plain_colour "${CAT_MAJ[$cat]}"
    maj=$RET
    plain_colour "$val"
    [[ $RET == "$maj" ]] && continue
    # a case pair is reported once, on its lower-case spelling
    lower=${p,,}
    if (( ! OPT_CASE )) && [[ $p != "$lower" && -n ${PAT_LINES[$lower]:-} ]]; then
      effective "${PAT_LINES[$lower]}"
      plain_colour "$RET"
      [[ $RET == "$maj" ]] || continue
    fi
    O_PAT+=("$p") O_LINE+=("$line") O_VAL+=("$val") O_CAT+=("$cat")
  done
}

# scan_walk DIR: count the extensions of the files below DIR.
scan_walk() {
  local f name ext
  for f in "$1"/* "$1"/.[!.]*; do
    if [[ -L $f ]]; then
      continue
    elif [[ -d $f ]]; then
      case ${f##*/} in
        .git|node_modules) ;;
        *) scan_walk "$f" ;;
      esac
    elif [[ -f $f ]]; then
      name=${f##*/}
      [[ $name == ?*.* ]] || continue
      ext=".${name##*.}"
      [[ $ext =~ ^\.[A-Za-z0-9_+-]{1,12}$ ]] || continue
      ext="*${ext,,}"
      SCAN_COUNT[$ext]=$(( ${SCAN_COUNT[$ext]:-0} + 1 ))
    fi
  done
}

# scan_dir DIR: SCAN_EXT becomes the extensions below DIR that no pattern of
# the config matches.
scan_dir() {
  local p q suffix covered restore
  SCAN_COUNT=() SCAN_EXT=()
  [[ -d $1 ]] || die "--scan: $1 is not a directory"
  restore=$(shopt -p nullglob)
  shopt -s nullglob
  scan_walk "${1%/}"
  eval "$restore"
  for p in "${!SCAN_COUNT[@]}"; do
    covered=0
    for q in "${PAT_ORDER[@]}"; do
      suffix=${q#\*}
      if [[ "x${p#\*}" == *"${suffix,,}" ]]; then covered=1; break; fi
    done
    (( covered )) || SCAN_EXT+=("$p")
  done
  if (( ${#SCAN_EXT[@]} )); then
    mapfile -t SCAN_EXT < <(printf '%s\n' "${SCAN_EXT[@]}" | LC_ALL=C sort)
  fi
}

# find_missing: fill M_* with patterns worth adding and MT_* with file types
# that are not set. Three sources: the curated table, the system database
# and, with --scan, the extensions that really occur.
find_missing() {
  local -A src=()
  local -a order=() words=() cand=() from=()
  local cat w p val why code i
  M_PAT=() M_CAT=() M_SRC=() M_VAL=() M_WHY=() MT_CODE=() MT_VAL=()
  load_db
  compute_majorities
  for cat in $CAT_ORDER; do
    read -r -a words <<<"${CAT_SUGGEST[$cat]}"
    for w in "${words[@]}"; do
      norm_pattern "$w"
      cand+=("$RET") from+=(curated)
    done
  done
  for p in "${DB_ORDER[@]}"; do cand+=("$p") from+=(database); done
  for p in "${SCAN_EXT[@]}"; do cand+=("$p") from+=(scan); done
  for i in "${!cand[@]}"; do
    p=${cand[i]}
    [[ -n ${LPAT[$p]:-} ]] && continue
    [[ -n ${src[$p]:-} ]] || order+=("$p")
    src[$p]+="${src[$p]:+, }${from[i]}"
  done
  for p in "${order[@]}"; do
    cat=${CUR_CAT[$p]:-${DB_CAT[$p]:-}}
    [[ -n $cat ]] || cat=other
    val="" why="no colour to propose"
    if [[ -n ${CAT_MAJ[$cat]:-} ]]; then
      val=${CAT_MAJ[$cat]} why="most of your $cat entries have this colour"
    elif [[ -n ${DB_VAL[$p]:-} ]]; then
      val=${DB_VAL[$p]} why="value from the system database"
    fi
    M_PAT+=("$p") M_CAT+=("$cat") M_SRC+=("${src[$p]}") M_VAL+=("$val") M_WHY+=("$why")
  done
  for code in $TYPES_EXPECTED; do
    [[ -n ${TYPE_LINES[$code]:-} ]] && continue
    MT_CODE+=("$code") MT_VAL+=("${DB_TYPE[$code]:-}")
  done
}

# pattern_key PATTERN -> RET: the pattern as it is written in a config file.
pattern_key() {
  case $1 in
    \*.*) RET=${1#\*} ;;
    *)    RET=$1 ;;
  esac
}

# ---------------------------------------------------------------------------
# check
# ---------------------------------------------------------------------------

# add_finding SEVERITY ID LINE WHAT WHY FIX
add_finding() {
  [[ ",$OPT_IGNORE," == *",$2,"* ]] && return
  F_SEV+=("$1") F_ID+=("$2") F_LINE+=("$3") F_WHAT+=("$4") F_WHY+=("$5") F_FIX+=("$6")
}

# describe_lines LINES -> RET: "line 215 (00;34, documents), line 269 (...)".
describe_lines() {
  local i out=""
  for i in $1; do
    out+="${out:+, }line $i (${L_VAL[i]:-no value}"
    if [[ ${L_KIND[i]} == pattern ]]; then out+=", ${SEC_TITLE[${L_SEC[i]}]}"; fi
    out+=")"
  done
  RET=$out
}

# twin_groups: REDUNDANT_TWINS lists the lines of case twins that repeat the
# colour of their lower-case entry; TWIN_DIFF lists pairs that disagree.
declare -a REDUNDANT_TWINS=() TWIN_DIFF=()
twin_groups() {
  local p q lower keep keepval same vals i v lines
  local -a spell=()
  REDUNDANT_TWINS=() TWIN_DIFF=()
  for p in "${PAT_ORDER[@]}"; do
    lower=${p,,}
    read -r -a spell <<<"${LPAT[$lower]}"
    (( ${#spell[@]} > 1 )) || continue
    [[ ${spell[0]} == "$p" ]] || continue          # once per group
    keep=$p
    [[ -n ${PAT_LINES[$lower]:-} ]] && keep=$lower
    effective "${PAT_LINES[$keep]}"
    keepval=$RET same=1 vals=""
    for q in "${spell[@]}"; do
      effective "${PAT_LINES[$q]}"
      v=$RET
      pattern_key "$q"
      vals+="${vals:+, }$RET $v"
      [[ $v == "$keepval" ]] || same=0
    done
    if (( same )); then
      for q in "${spell[@]}"; do
        [[ $q == "$keep" ]] && continue
        for i in ${PAT_LINES[$q]}; do REDUNDANT_TWINS+=("$i"); done
      done
    else
      lines=${PAT_LINES[$keep]# }
      TWIN_DIFF+=("${lines%% *} $vals")
    fi
  done
}

# flush_mismatch TERM: report the run of lines MM_FIRST..MM_LAST that the
# current TERM switches off, and start over.
MM_FIRST=0 MM_LAST=0 MM_N=0 MM_SCOPE=""
flush_mismatch() {
  local x=$MM_SCOPE
  (( MM_FIRST )) || return
  (( ${#x} > 60 )) && x="${x:0:57}..."
  add_finding warning term-mismatch "$MM_FIRST" \
    "lines $MM_FIRST to $MM_LAST ($MM_N colour lines) only apply when TERM matches: $x" \
    "Your TERM is \"$1\", so ls never sees these lines." \
    "fix does not change them; check with --term NAME how another terminal fares."
  MM_FIRST=0
}

run_checks() {
  local i kind key val code p lines first last n cat sec list why fix sev x total
  local term=${OPT_TERM:-${TERM:-}}
  F_SEV=() F_ID=() F_LINE=() F_WHAT=() F_WHY=() F_FIX=()

  # --- line by line -------------------------------------------------------
  for (( i = 1; i <= N; i++ )); do
    kind=${L_KIND[i]} key=${L_KEY[i]} val=${L_VAL[i]}
    case $kind in
      blank|comment|other) continue ;;
    esac
    if [[ -z $val ]]; then
      add_finding error novalue "$i" "$key has no value" \
        "dircolors rejects the whole file because of this line, so no colours are set at all." \
        "fix does not change it; give it a colour or delete the line by hand."
      continue
    fi
    case $kind in
      obsolete)
        add_finding info obsolete "$i" "$key is an obsolete keyword" \
          "dircolors ignores it, so the line does nothing." \
          "fix offers to remove it."
        continue ;;
      unknown)
        (( L_ACTIVE[i] )) && add_finding error unknown-keyword "$i" "$key is not a dircolors keyword" \
          "The line has no effect, and some dircolors versions reject the whole file because of it." \
          "fix does not change it; correct or delete the line by hand."
        continue ;;
      term) continue ;;
    esac
    # pattern or type from here on
    [[ $kind == type && " $TYPES_RAW " == *" ${L_NORM[i]} "* ]] && continue
    [[ $kind == type && ${L_NORM[i]} == ln && $val == target ]] && continue
    sgr_parse "$val"
    if [[ -n $SGR_BAD ]]; then
      add_finding warning bad-sgr "$i" "$key has a malformed colour code: $val" \
        "ls sends it to the terminal as it is, which shows no colour or garbage." \
        "fix does not change it; pick a colour in edit."
      continue
    fi
    if [[ -n $SGR_UNKNOWN ]]; then
      add_finding warning unknown-sgr "$i" "$key uses unknown code(s): $SGR_UNKNOWN (in $val)" \
        "Terminals ignore codes they do not know, so the entry may show no colour." \
        "fix does not change it; pick a colour in edit."
    fi
    if [[ $SGR_FG == 30 || $SGR_FG == "38;5;0" || $SGR_FG == "38;5;16" ]] \
      && [[ -z $SGR_BG && $SGR_ATTRS != *" 7 "* ]]; then
      add_finding warning invisible "$i" "$key is black text without a background ($val)" \
        "The name is invisible on a dark terminal." \
        "fix does not change it; pick a colour in edit."
    fi
    if [[ ";$SGR_EXTRA;" =~ \;0?8\; ]]; then
      add_finding warning invisible "$i" "$key uses concealed text ($val)" \
        "The name is hidden on terminals that support the code." \
        "fix does not change it; pick a colour in edit."
    fi
    if [[ $SGR_ATTRS == *" 5 "* || ";$SGR_EXTRA;" =~ \;0?6\; ]]; then
      add_finding info blink "$i" "$key uses blink ($val)" \
        "Most terminals ignore blink, so the entry shows without it." \
        "fix does not change it; pick a colour in edit."
    fi
    if (( SGR_EXT && ! OPT_256 )); then
      add_finding warning colour256 "$i" "$key uses a 256-colour or 24-bit code ($val)" \
        "Terminals limited to 16 colours show it wrong or not at all." \
        "fix does not change it; pass --256 if your terminal supports these codes."
    fi
    # sections that contradict the type of an entry
    if [[ $kind == pattern ]]; then
      p=${L_NORM[i]}
      cat=${CUR_CAT[${p,,}]:-} sec=${SEC_CAT[${L_SEC[i]}]}
      if [[ -n $cat && -n $sec && $cat != "$sec" ]]; then
        # report a case pair once, on its lower-case spelling
        if (( OPT_CASE )) || [[ $p == "${p,,}" || -z ${PAT_LINES[${p,,}]:-} ]]; then
          add_finding warning wrong-section "$i" \
            "$key belongs to \"$cat\" but sits in the section \"${SEC_TITLE[${L_SEC[i]}]}\"" \
            "It is coloured like the wrong group of files, which makes listings misleading." \
            "fix offers to move it when you let it reorganise the sections."
        fi
      fi
    fi
  done

  # --- duplicates ---------------------------------------------------------
  for p in "${PAT_ORDER[@]}" $TYPE_CODES; do
    lines=${PAT_LINES[$p]:-}
    [[ -n $lines ]] || lines=${TYPE_LINES[$p]:-}
    [[ $lines == " "*" "* ]] || continue
    n=0 x="" sev=info sec="" cat=0
    for i in $lines; do
      n=$(( n + 1 ))
      [[ -n $x && ${L_VAL[i]} != "$x" ]] && sev=warning
      x=${L_VAL[i]}
      [[ -n $sec && $sec != "${L_SEC[i]}" ]] && cat=1
      sec=${L_SEC[i]}
    done
    first=${lines# }
    first=${first%% *}
    effective "$lines"
    last=$RET2
    describe_lines "$lines"
    why="ls uses the last definition, so line $last is in effect"
    if [[ $sev == warning ]]; then
      why+=" and the differing values before it are dead."
    else
      why+="; the values are the same, so the extra lines are only clutter."
    fi
    (( cat )) && why+=" The definitions sit in different sections."
    add_finding "$sev" duplicate "$first" "${L_KEY[first]} is defined $n times: $RET" "$why" \
      "fix lets you pick the definition to keep (default: the last) and removes the others."
  done

  # --- case twins ---------------------------------------------------------
  if (( ! OPT_CASE )); then
    twin_groups
    for x in "${TWIN_DIFF[@]}"; do
      add_finding warning twin-differs "${x%% *}" "case twins have different colours: ${x#* }" \
        "That is rarely intended, and other spellings of the extension then get no colour at all." \
        "fix does not change it; edit shows the pair together so you can align it."
    done
    if (( LS_NOCASE && ${#REDUNDANT_TWINS[@]} )); then
      list=""
      for i in "${REDUNDANT_TWINS[@]:0:6}"; do list+="${list:+ }${L_KEY[i]}"; done
      (( ${#REDUNDANT_TWINS[@]} > 6 )) && list+=" ..."
      add_finding info twins "${REDUNDANT_TWINS[0]}" \
        "${#REDUNDANT_TWINS[@]} case twins repeat their lower-case entry ($list)" \
        "This ls matches extensions without regard to case, so the twins are redundant." \
        "fix offers to remove them."
    fi
  fi

  # --- TERM lines ---------------------------------------------------------
  first=0 last=0 n=0
  for (( i = LAST_COLOUR_LINE + 1; i <= N; i++ )); do
    [[ ${L_KIND[i]} == term ]] || continue
    (( first )) || first=$i
    last=$i n=$(( n + 1 ))
  done
  if (( n )); then
    x="line $first is a TERM line"
    (( n > 1 )) && x="lines $first to $last: $n TERM/COLORTERM lines"
    add_finding info term-noeffect "$first" "$x after the last colour line" \
      "TERM lines only restrict the colour lines that follow them, and none follow, so they do nothing." \
      "fix offers to remove them."
  fi
  MM_FIRST=0 MM_LAST=0 MM_N=0 MM_SCOPE=""
  for (( i = 1; i <= N; i++ )); do
    case ${L_KIND[i]} in
      blank|comment|term|other) continue ;;
    esac
    if (( L_ACTIVE[i] )); then
      flush_mismatch "$term"
    else
      [[ ${L_SCOPE[i]} == "$MM_SCOPE" ]] || flush_mismatch "$term"
      if (( ! MM_FIRST )); then MM_FIRST=$i MM_SCOPE=${L_SCOPE[i]} MM_N=0; fi
      MM_LAST=$i MM_N=$(( MM_N + 1 ))
    fi
  done
  flush_mismatch "$term"

  # --- missing file types and entries -------------------------------------
  find_missing
  find_outliers
  for i in "${!O_PAT[@]}"; do
    cat=${O_CAT[i]}
    pattern_key "${O_PAT[i]}"
    add_finding info outlier "${O_LINE[i]}" \
      "$RET is ${O_VAL[i]}, but ${CAT_MAJ_N[$cat]} of your ${CAT_TOTAL[$cat]} \"$cat\" entries are ${CAT_MAJ[$cat]}" \
      "It stands out in listings; that can be on purpose, but it is often a leftover." \
      "fix offers to change it to ${CAT_MAJ[$cat]}."
  done
  if (( ${#MT_CODE[@]} )); then
    list=""
    for code in "${MT_CODE[@]}"; do list+="${list:+ }${TYPE_NAME[$code]}"; done
    add_finding info missing-type 0 "file types that are not set: $list" \
      "ls falls back to its built-in colours for them, which may not fit the rest of your scheme." \
      "fix offers to add them with the values of the system database."
  fi
  for cat in $CAT_ORDER other; do
    list="" n=0 total=0
    for i in "${!M_PAT[@]}"; do
      [[ ${M_CAT[i]} == "$cat" ]] || continue
      pattern_key "${M_PAT[i]}"
      x=${M_SRC[i]}
      x=${x//curated/c}
      x=${x//database/d}
      x=${x//scan/s}
      x=${x//, /}
      list+="${list:+ }${RET}[$x]"
      total=$(( total + 1 ))
      [[ -n ${M_VAL[i]} ]] && n=$(( n + 1 ))
    done
    (( total )) || continue
    if [[ -n ${CAT_MAJ[$cat]:-} ]]; then
      fix="fix offers to add them as ${CAT_MAJ[$cat]}, the colour most of your $cat entries have."
    elif (( n == total )); then
      fix="fix offers to add them with the values of the system database."
    elif (( n )); then
      fix="fix offers to add the $n that have a value in the system database; for the others there is no colour to propose."
    else
      fix="fix proposes nothing: your $cat entries have no majority colour and the system database has no value."
    fi
    add_finding info missing 0 "$total \"$cat\" patterns have no colour: $list" \
      "Files with these names are listed in the default colour." "$fix"
  done
}

# wrap INDENT TEXT [FIRST_PREFIX FIRST_SUFFIX]: print TEXT wrapped to the
# terminal width. The optional prefix and suffix decorate the first line.
wrap() {
  local indent=$1 width=$(( COLS - ${#1} )) line="" word pre=${3:-} post=${4:-}
  local -a words=()
  (( width < 30 )) && width=30
  read -r -a words <<<"$2"
  for word in "${words[@]}"; do
    if [[ -n $line ]] && (( ${#line} + 1 + ${#word} > width )); then
      printf '%s%s%s%s\n' "$pre" "$indent" "$line" "$post"
      pre="" post="" indent=${indent//?/ }
      line=$word
    else
      line+="${line:+ }$word"
    fi
  done
  [[ -n $line ]] && printf '%s%s%s%s\n' "$pre" "$indent" "$line" "$post"
}

# findings_order: the indices of the findings sorted by line number; findings
# about the whole file come last.
findings_order() {
  local i n
  for i in "${!F_SEV[@]}"; do
    n=${F_LINE[i]}
    (( n )) || n=9999999
    printf '%s %s\n' "$n" "$i"
  done | LC_ALL=C sort -s -n -k1,1
}

# print_findings: grouped by severity. Returns 1 when there are findings.
print_findings() {
  local sev title colour i n where shown=0 nerr=0 nwarn=0 ninfo=0 legend=0
  local -a order=()
  mapfile -t order < <(findings_order)
  for sev in error warning info; do
    n=0
    for i in "${!F_SEV[@]}"; do [[ ${F_SEV[i]} == "$sev" ]] && n=$(( n + 1 )); done
    (( n )) || continue
    case $sev in
      error)   title="Errors" colour=$C_R nerr=$n ;;
      warning) title="Warnings" colour=$C_Y nwarn=$n ;;
      *)       title="Notes" colour=$C_C ninfo=$n ;;
    esac
    (( shown )) && printf '\n'
    shown=1
    printf '%s%s%s (%d)%s\n' "$C_B" "$colour" "$title" "$n" "$C_0"
    for i in "${order[@]#* }"; do
      [[ ${F_SEV[i]} == "$sev" ]] || continue
      where="         "
      (( F_LINE[i] )) && printf -v where 'line %-4s' "${F_LINE[i]}"
      [[ ${F_ID[i]} == missing ]] && legend=1
      wrap "  $where " "${F_WHAT[i]}" "$C_B" "$C_0"
      wrap "            " "${F_WHY[i]}"
      wrap "            " "${F_FIX[i]}" "$C_D" "$C_0"
    done
  done
  if (( ! shown )); then
    printf '%sNo problems found%s in %s\n' "$C_G" "$C_0" "$FILE"
    return 0
  fi
  if (( legend )); then
    printf '\n%sSources of missing patterns: [c] built-in table, [d] dircolors --print-database, [s] --scan%s\n' "$C_D" "$C_0"
  fi
  printf '\n%d error(s), %d warning(s), %d note(s) in %s\n' "$nerr" "$nwarn" "$ninfo" "$FILE"
  return 1
}

help_check() {
  cat <<EOF
Usage: $PROG check [OPTIONS] [FILE]

Report problems in a dircolors file, grouped by severity. The exit status
is 0 when nothing was found and 1 otherwise, so it can be used in scripts.

Options:
  --256              do not report 256-colour and 24-bit codes
  --case-sensitive   treat .deb and .DEB as two separate entries
  --scan DIR         also suggest the extensions that occur under DIR and
                     get no colour
  --term NAME        judge TERM lines as if \$TERM were NAME
  --ignore LIST      skip kinds of findings, separated by commas:
                     novalue unknown-keyword bad-sgr unknown-sgr invisible
                     blink colour256 obsolete duplicate twin-differs twins
                     wrong-section outlier term-noeffect term-mismatch
                     missing-type missing
EOF
}

# prepare_checks: everything check, preview and fix need before run_checks.
prepare_checks() {
  detect_tools
  probe_nocase
  if [[ -n $OPT_SCAN ]]; then scan_dir "$OPT_SCAN"; fi
}

cmd_check() {
  load_config
  term_size
  [[ -t 1 ]] || COLS=${COLUMNS:-100}
  prepare_checks
  run_checks
  print_findings
}

# ---------------------------------------------------------------------------
# preview
# ---------------------------------------------------------------------------

declare -a PV_SKIPPED=()      # samples that could not be created
declare -a PV_SEC_NAMES=()    # per section: newline-separated sample names
declare -a PV_SEC_PATS=()     # per section: newline-separated patterns
declare -A PV_PAINTED=()      # "n:NAME" -> the name as ls printed it
PV_SOCK="" PV_CHR="" PV_BLK=""
LS_COLOUR_ARG="--color=never"

# load_ls_colours: set LS_COLORS from the file exactly as a shell would,
# through "dircolors -b". Returns 1 when dircolors rejects the file.
load_ls_colours() {
  local out errors term=${OPT_TERM:-${TERM:-dumb}}
  errors="$TMP_DIR/.dircolors-errors"
  if ! out=$(TERM=$term "$DC" -b "$FILE_REAL" 2>"$errors"); then
    printf '%s%s rejects this file, so a shell gets no colours from it:%s\n' "$C_R" "$DC" "$C_0"
    while IFS= read -r out; do printf '  %s\n' "$out"; done <"$errors"
    rm -f -- "$errors"
    return 1
  fi
  rm -f -- "$errors"
  LS_COLORS=""
  eval "$out"
  export LS_COLORS
  if [[ -z $LS_COLORS ]]; then
    printf '%sWith TERM=%s this file sets no colours at all.%s\n' "$C_Y" "$term" "$C_0"
  fi
  return 0
}

# make_type_samples: one sample per file type in $TMP_DIR/types. Anything
# that cannot be created here is skipped and listed afterwards.
make_type_samples() {
  local t="$TMP_DIR/types" f restore
  PV_SKIPPED=() PV_SOCK="" PV_CHR="" PV_BLK=""
  mkdir -- "$t" || return 1
  : >"$t/file"
  mkdir -- "$t/dir" 2>/dev/null || PV_SKIPPED+=(dir)
  ln -s file "$t/link" 2>/dev/null || PV_SKIPPED+=(link)
  ln -s nowhere "$t/orphan" 2>/dev/null || PV_SKIPPED+=(orphan)
  mkfifo -- "$t/fifo" 2>/dev/null || PV_SKIPPED+=(fifo)
  { : >"$t/executable" && chmod 755 -- "$t/executable"; } 2>/dev/null || PV_SKIPPED+=(executable)
  : >"$t/setuid"
  chmod 4644 -- "$t/setuid" 2>/dev/null
  [[ -u "$t/setuid" ]] || { rm -f -- "$t/setuid"; PV_SKIPPED+=(setuid); }
  : >"$t/setgid"
  chmod 2644 -- "$t/setgid" 2>/dev/null
  [[ -g "$t/setgid" ]] || { rm -f -- "$t/setgid"; PV_SKIPPED+=(setgid); }
  mkdir -- "$t/other_writable" "$t/sticky" "$t/sticky_other_writable" 2>/dev/null
  chmod 0777 -- "$t/other_writable" 2>/dev/null || PV_SKIPPED+=(other_writable)
  chmod 1755 -- "$t/sticky" 2>/dev/null
  [[ -k "$t/sticky" ]] || { rmdir -- "$t/sticky" 2>/dev/null; PV_SKIPPED+=(sticky); }
  chmod 1777 -- "$t/sticky_other_writable" 2>/dev/null
  [[ -k "$t/sticky_other_writable" ]] || {
    rmdir -- "$t/sticky_other_writable" 2>/dev/null
    PV_SKIPPED+=(sticky_other_writable)
  }
  : >"$t/multihardlink"
  ln -- "$t/multihardlink" "$t/.multihardlink-twin" 2>/dev/null || {
    rm -f -- "$t/multihardlink"
    PV_SKIPPED+=(multihardlink)
  }
  # Sockets and device nodes cannot be made here (bash has no bind(), mknod
  # needs root), so existing ones are borrowed for the listing.
  restore=$(shopt -p nullglob)
  shopt -s nullglob
  for f in /dev/log /run/systemd/notify /run/systemd/journal/socket \
    /run/dbus/system_bus_socket "${XDG_RUNTIME_DIR:-/nonexistent}/bus" \
    /var/run/docker.sock /tmp/.X11-unix/X* /run/*.sock /run/*/*.sock /run/*/*; do
    if [[ -S $f ]]; then PV_SOCK=$f; break; fi
  done
  for f in /dev/null /dev/zero /dev/tty; do
    if [[ -c $f ]]; then PV_CHR=$f; break; fi
  done
  for f in /dev/sd? /dev/vd? /dev/nvme?n? /dev/loop? /dev/dm-? /dev/ram? /dev/disk?; do
    if [[ -b $f ]]; then PV_BLK=$f; break; fi
  done
  eval "$restore"
  [[ -n $PV_SOCK ]] || PV_SKIPPED+=(socket)
  [[ -n $PV_CHR ]] || PV_SKIPPED+=(char_device)
  [[ -n $PV_BLK ]] || PV_SKIPPED+=(block_device)
}

# make_pattern_samples: one empty file per pattern, in a directory per section.
make_pattern_samples() {
  local p lines first sec dir name n
  PV_SEC_NAMES=() PV_SEC_PATS=()
  for p in "${PAT_ORDER[@]}"; do
    lines=${PAT_LINES[$p]# }
    first=${lines%% *}
    sec=${L_SEC[first]}
    sample_name "$p"
    name=$RET
    if [[ -z $name || $name == */* || $name == . || $name == .. ]]; then
      PV_SKIPPED+=("$p")
      continue
    fi
    dir="$TMP_DIR/s$sec"
    [[ -d $dir ]] || mkdir -- "$dir" || continue
    # On a case-insensitive file system .deb and .DEB would collide.
    n=1
    while [[ -e "$dir/$name" ]]; do
      n=$(( n + 1 ))
      name="$n-${name#[0-9]*-}"
    done
    if : 2>/dev/null >"$dir/$name"; then
      PV_SEC_NAMES[sec]+="$name$NL"
      PV_SEC_PATS[sec]+="$p$NL"
    else
      PV_SKIPPED+=("$p")
    fi
  done
}

# paint_names DIR NAME...: ask ls for the coloured form of each name in DIR
# and remember it in PV_PAINTED.
paint_names() {
  local dir=$1 line
  shift
  (( $# )) || return
  while IFS= read -r line; do
    line=${line#"${ESC}[0m"}
    strip_sgr "$line"
    PV_PAINTED[n:$RET]=$line
  done < <(cd "$dir" && "$LS" -1 -d "$LS_COLOUR_ARG" -- "$@" 2>/dev/null)
}

# code_row PAINTED PLAIN LABEL CODE: one line of the --codes listing.
code_row() {
  local pad=$(( 26 - ${#2} ))
  (( pad < 1 )) && pad=1
  printf '  %s%*s %s%-24s %s%s\n' "$1" "$pad" "" "$C_D" "$3" "$4" "$C_0"
}

preview_types() {
  local t="$TMP_DIR/types" code name value line
  local -a extra=()
  printf '\n%sfile types%s\n' "$C_B" "$C_0"
  [[ -n $PV_CHR ]] && extra+=("$PV_CHR")
  [[ -n $PV_BLK ]] && extra+=("$PV_BLK")
  [[ -n $PV_SOCK ]] && extra+=("$PV_SOCK")
  if (( OPT_CODES )); then
    PV_PAINTED=()
    paint_names "$t" file dir link orphan fifo executable setuid setgid sticky \
      other_writable sticky_other_writable multihardlink "${extra[@]}"
    for code in $TYPES_SHOWN; do
      case $code in
        fi) name="file" ;;
        ln) name="link" ;;
        or) name=orphan ;;
        pi) name=fifo ;;
        so) name=$PV_SOCK ;;
        bd) name=$PV_BLK ;;
        cd) name=$PV_CHR ;;
        *)  name=${TYPE_SAMPLE[$code]} ;;
      esac
      [[ -n $name && -n ${PV_PAINTED[n:$name]:-} ]] || continue
      effective "${TYPE_LINES[$code]:-}"
      value=${RET:-(not set, ls default)}
      code_row "${PV_PAINTED[n:$name]}" "$name" "${TYPE_NAME[$code]}" "$value"
    done
  else
    (cd "$t" && "$LS" -C -w "$COLS" "$LS_COLOUR_ARG")
    if (( ${#extra[@]} )); then
      "$LS" -d -C -w "$COLS" "$LS_COLOUR_ARG" -- "${extra[@]}" 2>/dev/null
    fi
  fi
  if [[ -L "$t/orphan" ]]; then
    effective "${TYPE_LINES[mi]:-}"
    printf '%s  the target of a broken link (MISSING %s):%s\n' "$C_D" "${RET:-not set}" "$C_0"
    # A fixed time stamp marks where the name starts in the long listing.
    line=$(cd "$t" && "$LS" -l --time-style=+LSCC "$LS_COLOUR_ARG" orphan 2>/dev/null)
    printf '  %s\n' "${line#* LSCC }"
  fi
}

preview_sections() {
  local sec dir name p i
  local -a names=() pats=()
  for sec in "${!SEC_TITLE[@]}"; do
    [[ -n ${PV_SEC_NAMES[sec]:-} ]] || continue
    dir="$TMP_DIR/s$sec"
    printf '\n%s%s%s\n' "$C_B" "${SEC_TITLE[sec]}" "$C_0"
    if (( OPT_CODES )); then
      mapfile -t names <<<"${PV_SEC_NAMES[sec]%"$NL"}"
      mapfile -t pats <<<"${PV_SEC_PATS[sec]%"$NL"}"
      PV_PAINTED=()
      paint_names "$dir" "${names[@]}"
      for i in "${!names[@]}"; do
        name=${names[i]} p=${pats[i]}
        effective "${PAT_LINES[$p]}"
        code_row "${PV_PAINTED[n:$name]:-$name}" "$name" "$p" "${RET:-(no active definition)}"
      done
    else
      (cd "$dir" && "$LS" -C -w "$COLS" "$LS_COLOUR_ARG")
    fi
  done
}

help_preview() {
  cat <<EOF
Usage: $PROG preview [OPTIONS] [FILE]

Create a temporary directory with one sample per entry of the file and list
it with the real ls, with the colours loaded through "dircolors -b" the way
a shell does it. The output is grouped by the section comments of the file
and followed by the findings of check.

Options:
  -c, --codes        one entry per line, with its pattern and colour code
  -k, --keep         keep the sample directory and print its path
  --256, --case-sensitive, --scan DIR, --term NAME, --ignore LIST
                     as for check
  --colour WHEN      auto (default) colours only on a terminal; use
                     "always" to keep the colours in a pipe
EOF
}

cmd_preview() {
  local version
  load_config
  term_size
  [[ -t 1 ]] || COLS=${COLUMNS:-80}
  prepare_checks
  (( USE_COLOUR )) && LS_COLOUR_ARG="--color=always"
  TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/lscc-preview.XXXXXX") || exit 1
  version=$("$LS" --version 2>/dev/null | head -n 1)
  printf '%sfile:%s %s   %sTERM:%s %s   %sls:%s %s\n' "$C_B" "$C_0" "$FILE" \
    "$C_B" "$C_0" "${OPT_TERM:-${TERM:-}}" "$C_B" "$C_0" "$version"
  if ! load_ls_colours; then
    printf '\n'
    run_checks
    print_findings
    exit 1
  fi
  make_type_samples
  make_pattern_samples
  preview_types
  preview_sections
  if (( ${#PV_SKIPPED[@]} )); then
    printf '\n%sNot shown, because no sample could be created or found: %s%s\n' \
      "$C_D" "${PV_SKIPPED[*]}" "$C_0"
  fi
  printf '\n%sFindings of check%s\n' "$C_B" "$C_0"
  run_checks
  print_findings
  return 0
}

# ---------------------------------------------------------------------------
# fix
# ---------------------------------------------------------------------------

ASK_EOF=0                 # 1 once standard input has run dry
ST_HPRE="# " ST_HPOST="" ST_SEP=" "   # how the file writes headings and entries
declare -a REORG=() REORG_MOVES=() REORG_FLIPS=()
declare -A REORG_TGT=() REORG_RANK=()   # pattern -> target section, section -> rank

# ask PROMPT: read one line into REPLY. At end of input every further
# question is answered with "" (which always means: do nothing).
ask() {
  REPLY=""
  if (( ASK_EOF )); then return 1; fi
  printf '%s ' "$1"
  if ! IFS= read -r REPLY; then
    REPLY="" ASK_EOF=1
    printf '\n'
    return 1
  fi
  [[ -t 0 ]] || printf '%s\n' "$REPLY"
  REPLY=${REPLY#"${REPLY%%[![:space:]]*}"}
  REPLY=${REPLY%"${REPLY##*[![:space:]]}"}
  return 0
}

# confirm PROMPT: true only on an explicit y.
confirm() {
  ask "$1 [y/N]"
  [[ $REPLY == [yY] || $REPLY == [yY][eE][sS] ]]
}

step() { printf '\n%sStep %s of 5: %s%s\n' "$C_B" "$1" "$2" "$C_0"; }

# refresh: apply queued edits and bring the findings up to date.
refresh() {
  doc_rebuild
  run_checks
}

# style_detect: copy the way the file writes section headings and separates
# key and value, so that new lines look like the existing ones.
style_detect() {
  local s raw title i
  ST_HPRE="# " ST_HPOST="" ST_SEP=" "
  for s in "${!SEC_TITLE[@]}"; do
    (( s > 0 )) || continue
    raw=${SRC[${SEC_LINE[s]}]} title=${SEC_TITLE[s]}
    ST_HPRE=${raw%%"$title"*}
    ST_HPOST=${raw#*"$title"}
    break
  done
  for (( i = 1; i <= N; i++ )); do
    if [[ ${L_KIND[i]} == pattern && -n ${L_VAL[i]} ]]; then
      s=${L_PRE[i]}
      s=${s#"${s%%[![:space:]]*}"}
      ST_SEP=${s#"${L_KEY[i]}"}
      break
    fi
  done
  [[ -n $ST_SEP ]] || ST_SEP=" "
}

# --- step 1: duplicates ----------------------------------------------------

fix_duplicates() {
  local -a keys=() pick=()
  local p lines i k last name all=0 choice
  for p in "${PAT_ORDER[@]}"; do
    [[ ${PAT_LINES[$p]} == " "*" "* ]] && keys+=("$p")
  done
  for p in $TYPE_CODES; do
    [[ ${TYPE_LINES[$p]:-} == " "*" "* ]] && keys+=("$p")
  done
  step 1 "duplicates"
  if (( ! ${#keys[@]} )); then
    printf '  Nothing is defined twice.\n'
    return
  fi
  printf '  %d keys are defined more than once. Pick the definition to keep;\n' "${#keys[@]}"
  printf '  the others are removed. ls already uses the last one.\n'
  for p in "${keys[@]}"; do
    lines=${PAT_LINES[$p]:-}
    if [[ -n $lines ]]; then
      sample_name "$p"
      name=$RET
    else
      lines=${TYPE_LINES[$p]}
      name=${TYPE_SAMPLE[$p]:-sample}
    fi
    effective "$lines"
    last=$RET2
    k=0 pick=()
    printf '\n'
    for i in $lines; do
      k=$(( k + 1 ))
      pick[k]=$i
      paint "${L_VAL[i]}" "$name"
      printf '    %d) line %-4s %-10s %-10s %s' "$k" "$i" "${L_KEY[i]}" "${L_VAL[i]}" "$RET"
      [[ ${L_KIND[i]} == pattern ]] && printf '  %s(%s)%s' "$C_D" "${SEC_TITLE[${L_SEC[i]}]}" "$C_0"
      (( i == last )) && printf '  <- in effect'
      printf '\n'
    done
    choice=""
    if (( all )); then
      choice=$k
    else
      while :; do
        ask "  Keep which? [1-$k, Enter = $k, s = skip, a = keep the last for all the rest, n = skip all the rest]" || break
        case $REPLY in
          "") choice=$k; break ;;
          s)  break ;;
          a)  all=1 choice=$k; break ;;
          n)  break ;;
          *)
            if [[ $REPLY =~ $RE_NUM ]] && (( REPLY >= 1 && REPLY <= k )); then
              choice=$REPLY
              break
            fi
            printf '  Please answer with a number from 1 to %d, s, a or n.\n' "$k" ;;
        esac
      done
      if (( ASK_EOF )) || [[ $REPLY == n ]]; then break; fi
    fi
    [[ -n $choice ]] || continue
    for (( i = 1; i <= k; i++ )); do
      (( i == choice )) || delete_line "${pick[i]}"
    done
    printf '  Keeping line %s.\n' "${pick[choice]}"
  done
  refresh
}

# --- step 2: lines that do nothing -------------------------------------------

# delete_block FIRST LAST: queue the lines FIRST..LAST for removal. A short
# comment that stands directly above them and belongs to nothing else (blank
# line before it, blank line or end of file after LAST) goes with them.
delete_block() {
  local first=$1 last=$2 a i
  for (( i = first; i <= last; i++ )); do delete_line "$i"; done
  a=$first
  while (( a > 1 )) && [[ ${L_KIND[a-1]} == comment ]]; do a=$(( a - 1 )); done
  (( a < first && first - a <= 3 )) || return 0
  (( a == 1 )) || [[ ${L_KIND[a-1]} == blank ]] || return 0
  (( last == N )) || [[ ${L_KIND[last+1]} == blank ]] || return 0
  for (( i = a; i < first; i++ )); do delete_line "$i"; done
  # one of the two blank lines around the block goes as well
  if (( last < N )); then delete_line "$(( last + 1 ))"; elif (( a > 1 )); then delete_line "$(( a - 1 ))"; fi
}

fix_cleanup() {
  local -a obsolete=() dead=()
  local i list="" any=0 last
  for (( i = 1; i <= N; i++ )); do
    case ${L_KIND[i]} in
      obsolete) obsolete+=("$i"); list+="${list:+, }${L_KEY[i]}" ;;
      term)     (( i > LAST_COLOUR_LINE )) && dead+=("$i") ;;
    esac
  done
  step 2 "lines that do nothing"
  if (( ${#obsolete[@]} )); then
    any=1
    printf '  %d obsolete keyword lines (%s): dircolors ignores them.\n' "${#obsolete[@]}" "$list"
    if confirm "  Remove them, and the comment directly above each?"; then
      for i in "${obsolete[@]}"; do delete_block "$i" "$i"; done
    fi
  fi
  if (( ${#dead[@]} )); then
    any=1
    printf '  %d TERM lines (lines %s to %s) come after the last colour line, so they restrict nothing.\n' \
      "${#dead[@]}" "${dead[0]}" "${dead[${#dead[@]}-1]}"
    if confirm "  Remove them, and the comment directly above them?"; then
      # blank lines and comments between the TERM lines stay
      last=${dead[0]}
      for i in "${dead[@]}"; do
        (( i == last + 1 )) && last=$i
      done
      delete_block "${dead[0]}" "$last"
      for i in "${dead[@]}"; do (( i > last )) && delete_line "$i"; done
    fi
  fi
  if (( LS_NOCASE && ! OPT_CASE && ${#REDUNDANT_TWINS[@]} )); then
    any=1
    list=""
    for i in "${REDUNDANT_TWINS[@]:0:8}"; do list+="${list:+ }${L_KEY[i]}"; done
    (( ${#REDUNDANT_TWINS[@]} > 8 )) && list+=" ..."
    printf '  %d case twins (%s) repeat the colour of their lower-case entry.\n' "${#REDUNDANT_TWINS[@]}" "$list"
    printf '  Your ls matches extensions without regard to case, so they are redundant.\n'
    if confirm "  Remove them?"; then
      for i in "${REDUNDANT_TWINS[@]}"; do delete_line "$i"; done
    fi
  fi
  (( any )) || printf '  Nothing to clean up.\n'
  refresh
}

# --- step 3: colours that stand out -----------------------------------------

# recolour INDEX: give outlier INDEX the colour of its category, on every
# line that defines it (and on its case twins, unless they are separate).
recolour() {
  local p=${O_PAT[$1]} maj=${CAT_MAJ[${O_CAT[$1]}]} q i
  local -a spell=()
  if (( OPT_CASE )); then spell=("$p"); else read -r -a spell <<<"${LPAT[${p,,}]}"; fi
  for q in "${spell[@]}"; do
    for i in ${PAT_LINES[$q]}; do
      [[ -n ${L_VAL[i]} ]] && set_value "$i" "$maj"
    done
  done
}

fix_outliers() {
  local i cat key old new n=0
  step 3 "colours that stand out"
  if (( ! ${#O_PAT[@]} )); then
    printf '  No entry stands out from its category.\n'
    return
  fi
  printf '  These entries differ from the colour nearly all entries of their category have:\n'
  for i in "${!O_PAT[@]}"; do
    cat=${O_CAT[i]}
    pattern_key "${O_PAT[i]}"
    key=$RET
    sample_name "${O_PAT[i]}"
    paint "${O_VAL[i]}" "$RET"
    old=$RET
    sample_name "${O_PAT[i]}"
    paint "${CAT_MAJ[$cat]}" "$RET"
    new=$RET
    printf '    line %-4s %-10s %-9s %s  ->  %-9s %s  %s(%s of %s %s entries)%s\n' "${O_LINE[i]}" "$key" \
      "${O_VAL[i]}" "$old" "${CAT_MAJ[$cat]}" "$new" "$C_D" "${CAT_MAJ_N[$cat]}" "${CAT_TOTAL[$cat]}" "$cat" "$C_0"
  done
  ask "  Change them? [a = all, e = choose per entry, Enter = none]"
  case $REPLY in
    a|A)
      for i in "${!O_PAT[@]}"; do recolour "$i"; n=$(( n + 1 )); done ;;
    e|E)
      for i in "${!O_PAT[@]}"; do
        pattern_key "${O_PAT[i]}"
        ask "    $RET: ${O_VAL[i]} -> ${CAT_MAJ[${O_CAT[i]}]}? [y/N, q = stop asking]"
        if [[ $REPLY == [qQ] ]] || (( ASK_EOF )); then break; fi
        if [[ $REPLY == [yY] ]]; then recolour "$i"; n=$(( n + 1 )); fi
      done ;;
  esac
  (( n )) && printf '  %d entries recoloured.\n' "$n"
  refresh
}

# --- step 4: missing entries -------------------------------------------------

# add_missing_types: queue the file type lines the user accepted.
add_missing_types() {
  local i code pos=0 text="" list=""
  local -a have=()
  for i in "${!MT_CODE[@]}"; do
    [[ -n ${MT_VAL[i]} ]] || continue
    have+=("$i")
    paint "${MT_VAL[i]}" "${TYPE_SAMPLE[${MT_CODE[i]}]}"
    list+="${list:+   }${TYPE_NAME[${MT_CODE[i]}]} ${MT_VAL[i]} $RET"
  done
  if (( ! ${#MT_CODE[@]} )); then return; fi
  if (( ! ${#have[@]} )); then
    printf '  %d file types are not set, but the system database has no value for them.\n' "${#MT_CODE[@]}"
    return
  fi
  printf '  File types that are not set, with the values of the system database:\n    %s\n' "$list"
  confirm "  Add them?" || return
  for code in "${!TYPE_LINES[@]}"; do
    for i in ${TYPE_LINES[$code]}; do (( i > pos )) && pos=$i; done
  done
  for i in "${have[@]}"; do
    text+="${TYPE_NAME[${MT_CODE[i]}]}${ST_SEP}${MT_VAL[i]}$NL"
  done
  if (( pos == 0 )); then
    # No file type lines yet: put them in front of the first pattern section.
    for (( i = 1; i <= N; i++ )); do
      [[ ${L_KIND[i]} == pattern ]] && break
    done
    pos=$(( i - 1 ))
    while (( pos > 0 )) && [[ ${L_KIND[pos]} == comment ]]; do pos=$(( pos - 1 )); done
    text+=$NL
  fi
  insert_after "$pos" "${text%"$NL"}"
}

# queue_missing INDEX...: queue the chosen missing patterns for insertion,
# each at the end of the section of its category.
queue_missing() {
  local -A newsec=()
  local i s cat pos key line last=0 added=0
  for (( i = 1; i <= N; i++ )); do
    case ${L_KIND[i]} in
      pattern|type) [[ -z ${L_SCOPE[i]} ]] && last=$i ;;
    esac
  done
  (( last )) || last=$N
  for i in "$@"; do
    [[ -n ${M_VAL[i]} ]] || continue
    cat=${M_CAT[i]} pos=0
    for s in "${!SEC_TITLE[@]}"; do
      if (( s > 0 )) && [[ ${SEC_CAT[s]} == "$cat" ]]; then pos=$s; break; fi
    done
    pattern_key "${M_PAT[i]}"
    key=$RET
    line="$key$ST_SEP${M_VAL[i]}"
    if (( TWIN_CONVENTION && ! OPT_CASE )) && [[ ${M_PAT[i]} == \*.* && $key != "${key^^}" ]]; then
      line+="$NL${key^^}$ST_SEP${M_VAL[i]}"
    fi
    added=$(( added + 1 ))
    if (( pos )); then
      # after the last pattern of the existing section
      s=$pos pos=0
      for (( key = 1; key <= N; key++ )); do
        [[ ${L_KIND[key]} == pattern && ${L_SEC[key]} == "$s" ]] && pos=$key
      done
      insert_after "$pos" "$line"
    else
      newsec[$cat]+="$line$NL"
    fi
  done
  for cat in $CAT_ORDER other; do
    [[ -n ${newsec[$cat]:-} ]] || continue
    insert_after "$last" "$NL$ST_HPRE$cat$ST_HPOST$NL${newsec[$cat]%"$NL"}"
  done
  printf '  %d entries queued.\n' "$added"
}

fix_missing() {
  local -a chosen=() cats=()
  local cat i n none line tag stop=0
  step 4 "missing entries"
  style_detect
  if (( ! ${#MT_CODE[@]} && ! ${#M_PAT[@]} )); then
    printf '  Nothing is missing.\n'
    return
  fi
  add_missing_types
  if (( ${#M_PAT[@]} )); then
    printf '\n  Patterns without a colour, shown in the colour they would get.\n'
    printf '  %sSources: [c] built-in table, [d] dircolors --print-database, [s] --scan%s\n' "$C_D" "$C_0"
    for cat in $CAT_ORDER other; do
      line="" none="" n=0
      for i in "${!M_PAT[@]}"; do
        [[ ${M_CAT[i]} == "$cat" ]] || continue
        pattern_key "${M_PAT[i]}"
        tag=${M_SRC[i]}
        tag=${tag//curated/c}
        tag=${tag//database/d}
        tag=${tag//scan/s}
        tag=${tag//, /}
        if [[ -n ${M_VAL[i]} ]]; then
          n=$(( n + 1 ))
          paint "${M_VAL[i]}" "$RET"
          line+="$RET${C_D}[$tag]$C_0 "
        else
          none+="${RET}[$tag] "
        fi
      done
      [[ -n $line$none ]] || continue
      if (( n )); then
        cats+=("$cat")
        if [[ -n ${CAT_MAJ[$cat]:-} ]]; then
          printf '\n  %s%s%s as %s, the colour most of your %s entries have:\n' "$C_B" "$cat" "$C_0" "${CAT_MAJ[$cat]}" "$cat"
        else
          printf '\n  %s%s%s with the values of the system database:\n' "$C_B" "$cat" "$C_0"
        fi
        printf '    %s\n' "$line"
      else
        printf '\n  %s%s%s\n' "$C_B" "$cat" "$C_0"
      fi
      if [[ -n $none ]]; then
        printf '    %sno colour to propose (no majority among your %s entries, nothing in the database):%s\n' "$C_D" "$cat" "$C_0"
        printf '    %s%s%s\n' "$C_D" "$none" "$C_0"
      fi
    done
    if (( ${#cats[@]} )); then
      printf '\n'
      ask "  Add them? [a = all, c = choose per category, e = choose per entry, Enter = none]"
      case $REPLY in
        a|A)
          for i in "${!M_PAT[@]}"; do [[ -n ${M_VAL[i]} ]] && chosen+=("$i"); done ;;
        c|C)
          for cat in "${cats[@]}"; do
            ask "    $cat? [y/N, q = stop asking]"
            [[ $REPLY == [qQ] ]] && break
            (( ASK_EOF )) && break
            [[ $REPLY == [yY] ]] || continue
            for i in "${!M_PAT[@]}"; do
              [[ ${M_CAT[i]} == "$cat" && -n ${M_VAL[i]} ]] && chosen+=("$i")
            done
          done ;;
        e|E)
          for cat in "${cats[@]}"; do
            for i in "${!M_PAT[@]}"; do
              [[ ${M_CAT[i]} == "$cat" && -n ${M_VAL[i]} ]] || continue
              pattern_key "${M_PAT[i]}"
              paint "${M_VAL[i]}" "$RET"
              tag=${SCAN_COUNT[${M_PAT[i]}]:-}
              [[ -n $tag ]] && tag=", $tag file(s) found"
              ask "    $RET  ${M_VAL[i]}  (${M_WHY[i]}; source: ${M_SRC[i]}$tag)? [y/N, q = stop asking]"
              if [[ $REPLY == [qQ] ]] || (( ASK_EOF )); then stop=1; break; fi
              [[ $REPLY == [yY] ]] && chosen+=("$i")
            done
            (( stop )) && break
          done ;;
      esac
      if (( ${#chosen[@]} )); then queue_missing "${chosen[@]}"; fi
    fi
  fi
  refresh
}

# --- step 5: reorganise ------------------------------------------------------

# reorg_keys: one sort key per movable pattern line: section rank, the
# pattern it extends (or itself), pattern, spelling, line number.
reorg_keys() {
  local i k p lp lit root spec q variant
  for (( i = 1; i <= N; i++ )); do
    [[ ${L_KIND[i]} == pattern && -z ${L_SCOPE[i]} ]] || continue
    p=${L_NORM[i]} lp=${p,,}
    lit=${lp#\*} root=$lp spec=0
    for (( k = 1; k < ${#lit}; k++ )); do
      q="*${lit:k}"
      if [[ -n ${LPAT[$q]:-} && ${REORG_TGT[$q]:-} == "${REORG_TGT[$lp]}" ]]; then root=$q spec=1; fi
    done
    variant=1
    [[ $p == "$lp" ]] && variant=0
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "${REORG_RANK[${REORG_TGT[$lp]}]}" "$root" "$spec" "$lp" "$variant" "$i"
  done
}

# build_reorganised: REORG becomes the document with its pattern lines
# grouped by category and sorted inside each section. Only pattern lines
# that apply to every terminal move; everything else stays where it is.
build_reorganised() {
  local -A has=() sec_for_cat=() newcat=() hdr=()
  local -a order=() final=() sorted=() doc=("") drop=() newpos=()
  local i s cat tok lp lit k p q first=0 lastcat=-1 r cur="" emitted=0 rest=0
  local key heading a b va vb name
  REORG=() REORG_MOVES=() REORG_FLIPS=() REORG_TGT=() REORG_RANK=()
  style_detect

  for (( i = 1; i <= N; i++ )); do
    [[ ${L_KIND[i]} == pattern && -z ${L_SCOPE[i]} ]] && has[${L_SEC[i]}]=1
  done
  (( ${#has[@]} )) || return 1
  for s in "${!SEC_TITLE[@]}"; do
    [[ -n ${has[$s]:-} ]] || continue
    (( s > 0 )) || continue
    order+=("$s")
    cat=${SEC_CAT[s]}
    if [[ -n $cat ]]; then
      lastcat=$(( ${#order[@]} - 1 ))
      [[ -n ${sec_for_cat[$cat]:-} ]] || sec_for_cat[$cat]=$s
    fi
  done

  # where every pattern goes
  for (( i = 1; i <= N; i++ )); do
    [[ ${L_KIND[i]} == pattern && -z ${L_SCOPE[i]} ]] || continue
    lp=${L_NORM[i],,}
    cat=${CUR_CAT[$lp]:-}
    if [[ -n $cat ]]; then
      tok=${sec_for_cat[$cat]:-}
      if [[ -z $tok ]]; then tok="new:$cat"; newcat[$cat]=1; fi
    else
      tok=${L_SEC[i]}
    fi
    REORG_TGT[$lp]=$tok
    if [[ $tok != "${L_SEC[i]}" ]]; then
      if [[ $tok == new:* ]]; then name=${tok#new:}; else name=${SEC_TITLE[tok]}; fi
      REORG_MOVES+=("${L_KEY[i]} -> $name")
    fi
  done

  # output order of the sections: the existing ones in place, new category
  # sections after the last section that has a category, the rest last
  for i in "${!order[@]}"; do
    final+=("${order[i]}")
    if (( i == lastcat )); then
      for cat in $CAT_ORDER; do [[ -n ${newcat[$cat]:-} ]] && final+=("new:$cat"); done
    fi
  done
  if (( lastcat < 0 )); then
    for cat in $CAT_ORDER; do [[ -n ${newcat[$cat]:-} ]] && final+=("new:$cat"); done
  fi
  final+=(0)
  for i in "${!final[@]}"; do REORG_RANK[${final[i]}]=$i; done

  # what leaves its place: pattern lines, the comment block above a section
  # and comments inside it, and the blank lines that follow
  for s in "${order[@]}"; do
    a=${SEC_LINE[s]} b=0
    while (( a > 1 )) && [[ ${L_KIND[a-1]} == comment ]]; do a=$(( a - 1 )); done
    for (( i = N; i >= 1; i-- )); do
      if [[ ${L_KIND[i]} == pattern && ${L_SEC[i]} == "$s" ]]; then b=$i; break; fi
    done
    for (( i = a; i <= b; i++ )); do
      drop[i]=1
      [[ ${L_KIND[i]} == comment ]] && hdr[$s]+="${SRC[i]}$NL"
    done
  done
  for (( i = 1; i <= N; i++ )); do
    if [[ ${L_KIND[i]} == pattern && -z ${L_SCOPE[i]} ]]; then drop[i]=1; fi
    if [[ ${L_KIND[i]} == blank && -n ${drop[i-1]:-} ]]; then drop[i]=1; fi
    if (( ! first )) && [[ -n ${drop[i]:-} ]]; then first=$i; fi
  done
  for (( i = first; i <= N; i++ )); do [[ -z ${drop[i]:-} ]] && rest=1; done

  # sort: by section, then by pattern without regard to case, lower case
  # first, original order last. A pattern that extends another one of the
  # same section (.tar.gz and .gz) follows it, because ls lets the later
  # line win and the longer pattern should.
  mapfile -t sorted < <(reorg_keys | LC_ALL=C sort -t "$TAB" -k1,1n -k2,2 -k3,3n -k4,4 -k5,5n -k6,6n)

  for (( i = 1; i <= N; i++ )); do
    if (( i == first )); then
      for key in "${sorted[@]}"; do
        r=${key%%"$TAB"*}
        tok=${final[r]}
        if [[ $tok != "$cur" ]]; then
          (( emitted )) && doc+=("")
          cur=$tok emitted=1
          heading=""
          case $tok in
            new:*) heading="$ST_HPRE${tok#new:}$ST_HPOST" ;;
            0)     (( ${#REORG_RANK[@]} > 1 && ${#sorted[@]} > 0 )) && [[ ${sorted[0]%%"$TAB"*} != "$r" ]] && heading="${ST_HPRE}other$ST_HPOST" ;;
            *)     heading=${hdr[$tok]%"$NL"} ;;
          esac
          if [[ -n $heading ]]; then
            while IFS= read -r q; do doc+=("$q"); done <<<"$heading"
          fi
        fi
        k=${key##*"$TAB"}
        doc+=("${SRC[k]}")
        newpos[k]=${#doc[@]}
      done
      (( rest )) && doc+=("")
    fi
    [[ -n ${drop[i]:-} ]] || doc+=("${SRC[i]}")
  done
  REORG=("${doc[@]}")

  # would the new order change which of two overlapping patterns wins?
  for p in "${PAT_ORDER[@]}"; do
    lp=${p,,}
    [[ $p == "$lp" || -z ${PAT_LINES[$lp]:-} ]] || continue
    lit=${lp#\*}
    for (( k = 1; k < ${#lit}; k++ )); do
      q="*${lit:k}"
      [[ -n ${LPAT[$q]:-} ]] || continue
      read -r q _ <<<"${LPAT[$q]}"
      effective "${PAT_LINES[$p]}"
      a=$RET2 va=$RET
      effective "${PAT_LINES[$q]}"
      b=$RET2 vb=$RET
      (( a && b )) || continue
      [[ -n ${newpos[a]:-} && -n ${newpos[b]:-} && $va != "$vb" ]] || continue
      if (( (a > b) != (newpos[a] > newpos[b]) )); then
        sample_name "$p"
        if (( a > b )); then
          REORG_FLIPS+=("$RET: now $va, would become $vb")
        else
          REORG_FLIPS+=("$RET: now $vb, would become $va")
        fi
      fi
    done
  done
  return 0
}

fix_reorganise() {
  local i same=1 x
  step 5 "reorganise the sections"
  if ! build_reorganised; then
    printf '  There are no pattern lines to reorganise.\n'
    return
  fi
  (( ${#REORG[@]} == ${#SRC[@]} )) || same=0
  for (( i = 1; i < ${#REORG[@]} && same; i++ )); do
    [[ ${REORG[i]} == "${SRC[i]}" ]] || same=0
  done
  if (( same )); then
    printf '  The sections are already in order.\n'
    return
  fi
  printf '  This groups the patterns by category, sorts them inside each section and puts\n'
  printf '  case twins next to each other. Comments and all other lines stay where they are.\n'
  if (( ${#REORG_MOVES[@]} )); then
    printf '  %d entries move to another section:\n' "${#REORG_MOVES[@]}"
    for x in "${REORG_MOVES[@]:0:12}"; do printf '    %s\n' "$x"; done
    (( ${#REORG_MOVES[@]} > 12 )) && printf '    ... and %d more\n' "$(( ${#REORG_MOVES[@]} - 12 ))"
  fi
  if (( ${#REORG_FLIPS[@]} )); then
    printf '  %sThe new order changes the colour of %d names, because a shorter pattern would then win:%s\n' \
      "$C_Y" "${#REORG_FLIPS[@]}" "$C_0"
    for x in "${REORG_FLIPS[@]}"; do printf '    %s\n' "$x"; done
  fi
  if confirm "  Reorganise?"; then
    SRC=("${REORG[@]}")
    N=$(( ${#SRC[@]} - 1 ))
    DEL=() INS=()
    parse
  fi
}

# --- finish ------------------------------------------------------------------

# verify_doc: refuse a result that dircolors would reject although it accepted
# the file before. Returns 1 when the document must not be written.
verify_doc() {
  local dir tmp ok=0
  dir=$(mktemp -d "${TMPDIR:-/tmp}/lscc-verify.XXXXXX") || return 0
  tmp="$dir/new"
  doc_print >"$tmp"
  if TERM=xterm "$DC" -b "$FILE_REAL" >/dev/null 2>&1 && ! TERM=xterm "$DC" -b "$tmp" >/dev/null 2>&1; then
    ok=1
  fi
  rm -rf -- "$dir"
  return "$ok"
}

# review_and_save: show the diff, ask once, back up and write.
# Returns 0 written, 1 not written.
review_and_save() {
  printf '\n%sChanges to %s%s\n' "$C_B" "$FILE" "$C_0"
  print_diff || return 1
  if (( OPT_DRY )); then
    printf 'Dry run: nothing was written.\n'
    return 1
  fi
  if ! verify_doc; then
    err "dircolors would reject the result, so nothing was written. Please report this as a bug."
    return 1
  fi
  if ! confirm "Write these changes to $FILE?"; then
    printf 'Nothing was written.\n'
    return 1
  fi
  save_file || return 1
  printf 'Written. Backup of the old file: %s\n' "$BACKUP_PATH"
  # The command substitution is text for the user to copy, not to be run here.
  # shellcheck disable=SC2016
  printf 'Load the new colours with: eval "$(%s -b %s)"\n' "$DC" "$FILE"
  return 0
}

help_fix() {
  cat <<EOF
Usage: $PROG fix [OPTIONS] [FILE]

Walk through the findings of check and repair them. Every step asks first,
and nothing is written until you have seen the complete diff and confirmed.

  1. duplicates       pick the definition to keep (Enter keeps the last
                      one, which is what ls uses already)
  2. dead lines       obsolete keywords, TERM lines without effect and,
                      where ls ignores case, redundant upper-case twins
  3. odd colours      entries that differ from the colour nearly all
                      entries of their category have; change all, some
                      or none
  4. missing entries  add common patterns in the colour most entries of
                      their category have; accept all, per category or
                      per entry
  5. reorganise       group patterns by category and sort the sections

Before writing, a backup named FILE.bak-DATE-TIME is created next to the
file.

Options:
  -n, --dry-run      show what would change, write nothing
  --scan DIR         also propose the extensions that occur under DIR
  --256, --case-sensitive, --term NAME
                     as for check
EOF
}

cmd_fix() {
  load_config
  term_size
  [[ -t 1 ]] || COLS=${COLUMNS:-100}
  prepare_checks
  run_checks
  printf '%sfix:%s %s' "$C_B" "$C_0" "$FILE"
  (( OPT_DRY )) && printf '  (dry run, nothing will be written)'
  printf '\n'
  fix_duplicates
  fix_cleanup
  fix_outliers
  fix_missing
  fix_reorganise
  review_and_save
  return 0
}

# ---------------------------------------------------------------------------
# edit: the full-screen editor
# ---------------------------------------------------------------------------

# Entries of the list. A case pair (.deb / .DEB) is one entry unless
# --case-sensitive is on; an entry knows every line that defines it.
declare -a E_LABEL=() E_NAME=() E_LINES=() E_SEC=()
declare -a ROW_KIND=() ROW_REF=()    # visible rows: h heading (group), e entry
declare -a ST=()                     # staged values by line number
declare -a UNDO=()                   # one record per change
declare -a EV_LIST=()                # distinct values of the entry at hand
EV_EFF="" EV_MOD=0
T_CUR=0 T_TOP=0 T_FILTER="" T_MSG="" RESIZED=0 INTR=0 KEY=""
T_RAW=0            # x: show codes instead of descriptions
T_FOCUS=list       # list or picker: what the keys go to
T_CTX=list         # which key hints the last row shows
T_LAYOUT=list LIST_DIM=0
COLOUR_NAMES=(black red green yellow blue magenta cyan white)

# Picker state.
declare -a FG_CELLS=() BG_CELLS=()
declare -A PV=()                     # entry -> the value the open picker shows
FG_B=1 BG_B=1 PK_START="" PK_FIELD=0 PK_FG=0 PK_BG=0 PK_AT=0
PK_ATTRS=" " PK_EXTRA="" PK_PAD=1 PK_ZERO=0 PK_RAW="" PK_TOUCHED=0
PK_REF=0 PK_OLD=""                   # the entry in the picker, and its value before

tui_start() {
  STTY_SAVED=$(stty -g 2>/dev/null </dev/tty)
  stty -echo 2>/dev/null </dev/tty
  TUI_ACTIVE=1
  printf '%s' "${ESC}[?1049h${ESC}[?25l"
  screen_reset
}

# Frames are built as text in which ROW_AT, a row number and ROW_TXT start
# each screen row. emit_frame compares every row with what is on screen
# (FRAME) and sends only the rows that changed, so an unchanged screen costs
# nothing and the terminal never shows a half-drawn frame.
ROW_AT=$'\001'
ROW_TXT=$'\002'
declare -a FRAME=()

# screen_reset: forget what is on screen and clear it; the next frame is
# drawn in full.
screen_reset() {
  FRAME=()
  printf '%s' "${ESC}[0m${ESC}[2J"
}

emit_frame() {
  local out="" seg y text
  local -a segs=()
  IFS=$ROW_AT read -r -d '' -a segs <<<"$1"
  for seg in "${segs[@]}"; do
    [[ $seg == *"$ROW_TXT"* ]] || continue
    y=${seg%%"$ROW_TXT"*}
    text=${seg#*"$ROW_TXT"}
    text=${text%"$NL"}
    # a row that was never drawn compares unequal even to an empty one
    if [[ ${FRAME[y]-$ROW_AT} != "$text" ]]; then
      out+="${ESC}[${y};1H${text}${ESC}[0m${ESC}[K"
      FRAME[y]=$text
    fi
  done
  # 2026 is "synchronised output": terminals that know it show the update
  # in one go, the others ignore the request
  [[ -n $out ]] && printf '%s' "${ESC}[?2026h${out}${ESC}[?2026l"
}

tui_suspend() {
  printf '%s' "${ESC}[0m${ESC}[?25h${ESC}[?1049l"
  [[ -n $STTY_SAVED ]] && stty "$STTY_SAVED" 2>/dev/null </dev/tty
  TUI_ACTIVE=0
}

# read_key TIMEOUT: wait for a key and name it in KEY. Returns 1 on timeout.
read_key() {
  local c="" d="" seq="" rc
  KEY=""
  IFS= read -rsn1 -t "$1" c
  rc=$?
  if (( rc > 128 )); then return 1; fi
  if (( rc != 0 )); then KEY=eof; return 0; fi
  case $c in
    "")      KEY=enter ;;
    "$TAB")  KEY=tab ;;
    " ")     KEY=space ;;
    $'\177'|$'\b') KEY=backspace ;;
    "$ESC")
      if ! IFS= read -rsn1 -t 0.05 d; then KEY=esc; return 0; fi
      if [[ $d != "[" && $d != O ]]; then KEY=esc; return 0; fi
      while IFS= read -rsn1 -t 0.05 d; do
        seq+=$d
        [[ $d == [A-Za-z~] ]] && break
      done
      case $seq in
        A) KEY=up ;;
        B) KEY=down ;;
        C) KEY=right ;;
        D) KEY=left ;;
        H|1~|7~) KEY=home ;;
        F|4~|8~) KEY=end ;;
        5~) KEY=pgup ;;
        6~) KEY=pgdn ;;
        Z) KEY=backtab ;;
        *) KEY=unknown ;;
      esac ;;
    *) KEY=$c ;;
  esac
  return 0
}

# line_input PROMPT INITIAL -> RET: a one-line text field on the message row.
# Returns 1 when cancelled with Esc.
line_input() {
  local text=$2
  unset "FRAME[$(( ROWS - 1 ))]"
  while :; do
    printf '%s' "${ESC}[$(( ROWS - 1 ));1H${ESC}[K${C_B}$1${C_0}${text}${ESC}[?25h"
    if ! read_key 0.5; then
      if (( ! INTR )); then continue; fi
      KEY=esc
    fi
    case $KEY in
      enter)     break ;;
      esc|eof)   printf '%s' "${ESC}[?25l"; RET=""; return 1 ;;
      backspace) text=${text%?} ;;
      space)     text+=" " ;;
      ?)         text+=$KEY ;;
    esac
  done
  printf '%s' "${ESC}[?25l"
  RET=$text
  return 0
}

# --- the list ----------------------------------------------------------------

build_entries() {
  local -A seen=()
  local -a spell=()
  local i q code p lower lines label name first
  E_LABEL=() E_NAME=() E_LINES=() E_SEC=()
  for (( i = 1; i <= N; i++ )); do
    [[ ${L_KIND[i]} == type && -n ${L_VAL[i]} ]] || continue
    code=${L_NORM[i]}
    [[ " $TYPES_RAW " == *" $code "* ]] && continue
    [[ -n ${seen[t$code]:-} ]] && continue
    seen[t$code]=1
    lines=""
    for q in ${TYPE_LINES[$code]}; do [[ -n ${L_VAL[q]} ]] && lines+=" $q"; done
    E_LABEL+=("${TYPE_NAME[$code]}") E_NAME+=("${TYPE_SAMPLE[$code]:-sample}")
    E_LINES+=("$lines") E_SEC+=("file types")
  done
  for p in "${PAT_ORDER[@]}"; do
    if (( OPT_CASE )); then
      spell=("$p")
    else
      lower=${p,,}
      [[ -n ${seen[p$lower]:-} ]] && continue
      seen[p$lower]=1
      read -r -a spell <<<"${LPAT[$lower]}"
    fi
    lines="" label="" name=${spell[0]}
    for q in "${spell[@]}"; do
      for i in ${PAT_LINES[$q]}; do [[ -n ${L_VAL[i]} ]] && lines+=" $i"; done
      pattern_key "$q"
      label+="${label:+ / }$RET"
      [[ $q == "${q,,}" ]] && name=$q
    done
    [[ -n $lines ]] || continue
    sample_name "$name"
    first=${lines# }
    first=${first%% *}
    E_LABEL+=("$label") E_NAME+=("$RET") E_LINES+=("$lines")
    E_SEC+=("${SEC_TITLE[${L_SEC[first]}]}")
  done
  map_findings
}

# --- groups, folding and the rows of the list --------------------------------
#
# The entries are shown in groups: the sections of the file. A group is a
# heading row that can be folded away, followed by its entries.
declare -a G_TITLE=() G_ENTRIES=() G_N=() G_MAJ=() G_DIFF=() G_WARN=()
declare -a E_GRP=() E_ORD=() E_WARN=()
declare -A FOLD=() FOLD_F=()         # fold state by view and title; _F while a filter is on
T_VIEW=section T_FOLD_DEFAULT=0 T_TOTAL=0 GW_TITLE=8
CUR_ID=""                            # what the cursor is on: e:ENTRY or h:TITLE

# map_findings: E_WARN = what check has to say about each entry. The findings
# are those of the file as it was last read or saved.
map_findings() {
  local i f line
  local -A at=()
  E_WARN=()
  for i in "${!E_LINES[@]}"; do
    for line in ${E_LINES[i]}; do at[$line]=$i; done
  done
  for f in "${!F_LINE[@]}"; do
    i=${at[${F_LINE[f]}]:-}
    [[ -n $i ]] || continue
    E_WARN[i]="${E_WARN[i]:+${E_WARN[i]}; }${F_WHAT[f]}"
  done
}

build_groups() {
  local i key g hay needle=${T_FILTER,,}
  local -A at=()
  G_TITLE=() G_ENTRIES=() E_GRP=() E_ORD=() T_TOTAL=0 GW_TITLE=8
  for i in "${!E_LABEL[@]}"; do
    if [[ -n $needle ]]; then
      hay="${E_LABEL[i]} ${E_NAME[i]} ${E_SEC[i]}"
      [[ ${hay,,} == *"$needle"* ]] || continue
    fi
    key=${E_SEC[i]:-other entries}
    if [[ -z ${at[k$key]+x} ]]; then
      at[k$key]=${#G_TITLE[@]}
      G_TITLE+=("$key") G_ENTRIES+=("")
      (( ${#key} > GW_TITLE )) && GW_TITLE=${#key}
    fi
    g=${at[k$key]}
    G_ENTRIES[g]+=" $i"
    E_GRP[i]=$g
    T_TOTAL=$(( T_TOTAL + 1 ))
    E_ORD[i]=$T_TOTAL
  done
  (( GW_TITLE > 28 )) && GW_TITLE=28
}

# summarise GROUP: the colour most entries of the group have (G_MAJ), how
# many have another one (G_DIFF), and how many check complains about.
summarise() {
  local g=$1 i key best="" bestn=0 total=0 warn=0
  local -A tally=() spelt=()
  for i in ${G_ENTRIES[g]}; do
    entry_values "$i"
    plain_colour "$EV_EFF"
    key=k$RET
    tally[$key]=$(( ${tally[$key]:-0} + 1 ))
    [[ -n ${spelt[$key]+x} ]] || spelt[$key]=$EV_EFF
    if (( ${tally[$key]} > bestn )); then bestn=${tally[$key]} best=$key; fi
    total=$(( total + 1 ))
    [[ -n ${E_WARN[i]:-} ]] && warn=$(( warn + 1 ))
  done
  G_N[g]=$total G_MAJ[g]=${spelt[$best]:-} G_DIFF[g]=$(( total - bestn )) G_WARN[g]=$warn
}

# is_folded GROUP. A search starts with every group that matches unfolded.
is_folded() {
  local key="$T_VIEW/${G_TITLE[$1]}"
  if [[ -n $T_FILTER ]]; then
    (( ${FOLD_F[$key]:-0} ))
  else
    (( ${FOLD[$key]:-$T_FOLD_DEFAULT} ))
  fi
}

# set_fold GROUP 0|1
set_fold() {
  local key="$T_VIEW/${G_TITLE[$1]}"
  if [[ -n $T_FILTER ]]; then FOLD_F[$key]=$2; else FOLD[$key]=$2; fi
}

# fold_all 0|1
fold_all() {
  local g
  for g in "${!G_TITLE[@]}"; do set_fold "$g" "$1"; done
}

# toggle_fold: fold or unfold the group the cursor is in; the cursor ends up
# on its heading.
toggle_fold() {
  local g
  cursor_group || return
  g=$RET
  if is_folded "$g"; then set_fold "$g" 0; else set_fold "$g" 1; fi
  CUR_ID="h:${G_TITLE[g]}"
  build_rows
}

# cursor_group -> RET: the group of the row the cursor is on.
cursor_group() {
  local ref=${ROW_REF[T_CUR]:-}
  case ${ROW_KIND[T_CUR]:-} in
    h) RET=$ref ;;
    e) RET=${E_GRP[ref]} ;;
    *) return 1 ;;
  esac
}

build_rows() {
  local g i
  build_groups
  ROW_KIND=() ROW_REF=()
  for g in "${!G_TITLE[@]}"; do
    summarise "$g"
    ROW_KIND+=(h) ROW_REF+=("$g")
    is_folded "$g" && continue
    for i in ${G_ENTRIES[g]}; do ROW_KIND+=(e) ROW_REF+=("$i"); done
  done
  place_cursor
}

# place_cursor: put the cursor back on what CUR_ID names. An entry that is
# folded away is replaced by its heading. Without a CUR_ID the cursor goes to
# the first entry on screen.
place_cursor() {
  local r n=${#ROW_KIND[@]} want=$CUR_ID g
  T_CUR=0
  (( n )) || return
  if [[ -z $want ]]; then
    [[ ${ROW_KIND[1]:-} == e ]] && T_CUR=1
    T_TOP=0
  fi
  if [[ $want == e:* ]]; then
    for (( r = 0; r < n; r++ )); do
      if [[ ${ROW_KIND[r]} == e && ${ROW_REF[r]} == "${want#e:}" ]]; then T_CUR=$r; return; fi
    done
    g=${E_GRP[${want#e:}]:-}
    [[ -n $g ]] && want="h:${G_TITLE[g]}"
  fi
  if [[ $want == h:* ]]; then
    for (( r = 0; r < n; r++ )); do
      if [[ ${ROW_KIND[r]} == h && ${G_TITLE[${ROW_REF[r]}]} == "${want#h:}" ]]; then T_CUR=$r; break; fi
    done
  fi
  remember_cursor
}

remember_cursor() {
  local ref=${ROW_REF[T_CUR]:-}
  case ${ROW_KIND[T_CUR]:-} in
    e) CUR_ID="e:$ref" ;;
    h) CUR_ID="h:${G_TITLE[ref]}" ;;
    *) CUR_ID="" ;;
  esac
}

# entry_values INDEX: EV_LIST = the distinct values of the entry right now,
# EV_EFF = the one ls uses (last line), EV_MOD = 1 when it differs from the
# file. "Right now" includes what an open picker shows (PV).
entry_values() {
  local i v last=0
  EV_LIST=() EV_EFF="" EV_MOD=0
  for i in ${E_LINES[$1]}; do
    v=${PV[$1]-${ST[i]-${L_VAL[i]}}}
    [[ $v != "${L_VAL[i]}" ]] && EV_MOD=1
    [[ " ${EV_LIST[*]} " == *" $v "* ]] || EV_LIST+=("$v")
    if (( i > last )); then last=$i EV_EFF=$v; fi
  done
}

# move_cursor DELTA: move by DELTA rows; headings are rows like any other.
move_cursor() {
  local total=${#ROW_KIND[@]}
  (( total )) || return
  T_CUR=$(( T_CUR + $1 ))
  (( T_CUR >= total )) && T_CUR=$(( total - 1 ))
  (( T_CUR < 0 )) && T_CUR=0
  remember_cursor
}

# --- glyphs ------------------------------------------------------------------

# Every character the editor draws with is named here, once for UTF-8
# terminals and once in plain ASCII, so the layout code is the same for both.
# The locale decides (LC_ALL, then LC_CTYPE, then LANG); --ascii forces ASCII.
# Not every glyph is used by every layout.
# shellcheck disable=SC2034
setup_glyphs() {
  local utf=0
  case ${LC_ALL:-${LC_CTYPE:-${LANG:-}}} in
    *[Uu][Tt][Ff]8*|*[Uu][Tt][Ff]-8*) utf=1 ;;
  esac
  (( OPT_ASCII )) && utf=0
  if (( utf )); then
    GL_H="─" GL_V="│" GL_TEE="┬" GL_FOOT="┴" GL_CUR="▌" GL_OPEN="▾" GL_SHUT="▸"
    GL_SW="██" GL_WARN="!" GL_DOT="·" GL_TO="→" PK_MARK="▐▌" GL_SAVED="••"
    GL_K_MOVE="↑↓" GL_K_ARROWS="↑↓←→" GL_K_LEFT="←" GL_K_RIGHT="→" GL_K_ENTER="⏎" GL_K_SPACE="␣"
  else
    GL_H="-" GL_V="|" GL_TEE="+" GL_FOOT="+" GL_CUR=">" GL_OPEN="-" GL_SHUT="+"
    GL_SW="##" GL_WARN="!" GL_DOT="-" GL_TO="->" PK_MARK="<>" GL_SAVED=".."
    GL_K_MOVE="up/down" GL_K_ARROWS="arrows" GL_K_LEFT="left" GL_K_RIGHT="right" GL_K_ENTER="Enter" GL_K_SPACE="Space"
  fi
}
setup_glyphs

# --- colours in words --------------------------------------------------------

declare -A V_DESC=() V_HARD=()

# describe_colour VALUE -> RET: a name for a foreground or background code.
describe_colour() {
  local v=$1 r g b
  case $v in
    "")            RET="default" ;;
    3[0-7]|4[0-7]) RET=${COLOUR_NAMES[${v:1:1}]} ;;
    9[0-7])        RET="bright ${COLOUR_NAMES[${v:1:1}]}" ;;
    10[0-7])       RET="bright ${COLOUR_NAMES[${v:2:1}]}" ;;
    [34]8\;*(0)5\;*) RET="colour $(( 10#${v##*;} ))" ;;
    [34]8\;*(0)2\;*)
      b=${v##*;} g=${v%;*}
      r=${g%;*} g=${g##*;}
      r=${r##*;}
      printf -v RET '#%02x%02x%02x' "$(( 10#$r ))" "$(( 10#$g ))" "$(( 10#$b ))" ;;
    *)             RET="code $v" ;;
  esac
}

# describe_value VALUE -> RET: the value in words, such as "red, bold" or
# "bright blue on black". Kept in V_DESC, as rows ask again on every redraw.
describe_value() {
  local v=$1 out="" a tok
  local -a toks=()
  if [[ -n ${V_DESC[k$v]+x} ]]; then RET=${V_DESC[k$v]}; return; fi
  sgr_parse "$v"
  if [[ -n $SGR_BAD ]]; then
    out="not a valid code: ${v:-empty}"
  else
    if [[ -n $SGR_FG ]]; then describe_colour "$SGR_FG"; out=$RET; fi
    if [[ -n $SGR_BG ]]; then describe_colour "$SGR_BG"; out="${out:-default} on $RET"; fi
    for a in 1:bold 2:dim 4:underline 5:blink 7:reverse; do
      [[ $SGR_ATTRS == *" ${a%%:*} "* ]] && out+="${out:+, }${a#*:}"
    done
    IFS=';' read -r -a toks <<<"$SGR_EXTRA"
    for tok in "${toks[@]}" $SGR_UNKNOWN; do
      case $(( 10#$tok )) in
        3)  a="italic" ;;
        6)  a="rapid blink" ;;
        8)  a="concealed" ;;
        9)  a="struck out" ;;
        21) a="double underline" ;;
        *)  a="code $tok" ;;
      esac
      out+="${out:+, }$a"
    done
    [[ -n $out ]] || out="default"
  fi
  V_DESC[k$v]=$out
  RET=$out
}

# hard_to_read VALUE: true when a name in this colour is likely to be hard to
# read: black or the background's own colour as foreground, concealed, dim,
# or nothing but blink.
hard_to_read() {
  local v=$1 r=1 same
  if [[ -n ${V_HARD[k$v]+x} ]]; then return "${V_HARD[k$v]}"; fi
  sgr_parse "$v"
  if [[ -z $SGR_BAD ]]; then
    if [[ -z $SGR_BG && $SGR_ATTRS != *" 7 "* ]]; then
      case $SGR_FG in 30|"38;5;0"|"38;5;16"|"38;2;0;0;0") r=0 ;; esac
    fi
    if [[ -n $SGR_FG && -n $SGR_BG ]]; then
      case $SGR_FG in
        3[0-7]) same="4${SGR_FG:1}" ;;
        9[0-7]) same="10${SGR_FG:1}" ;;
        *)      same="48${SGR_FG:2}" ;;
      esac
      [[ $same == "$SGR_BG" ]] && r=0
    fi
    [[ $SGR_ATTRS == *" 2 "* ]] && r=0
    [[ ";$SGR_EXTRA;" == *";8;"* || ";$SGR_EXTRA;" == *";08;"* ]] && r=0
    [[ -z $SGR_FG$SGR_BG$SGR_EXTRA && $SGR_ATTRS == " 5 " ]] && r=0
  fi
  V_HARD[k$v]=$r
  return "$r"
}

# --- the parts of the screen -------------------------------------------------
#
# The render functions only build text. Each takes the size it may use and
# never looks at the terminal, so the tests can call them with any state.
# Widths are counted while a row is put together, in characters.

# spaces N -> RET
spaces() {
  local n=$1
  (( n < 0 )) && n=0
  printf -v RET '%*s' "$n" ""
}

# rule W -> RET: a horizontal line.
rule() {
  spaces "$1"
  RET=${RET// /$GL_H}
}

# render_header W -> RET: tool and file on the left, the state on the right.
render_header() {
  local w=$1 left right tail plain n=${#ST[@]} room
  left=" $PROG $GL_DOT $FILE"
  if (( OPT_256 )); then right="256 colours"; else right="16 colours"; fi
  if (( OPT_CASE )); then right+=" $GL_DOT pairs apart"; else right+=" $GL_DOT pairs joined"; fi
  (( OPT_DRY )) && right+=" $GL_DOT dry run"
  [[ -n $T_FILTER ]] && right+=" $GL_DOT filtered"
  right+=" $GL_DOT "
  tail="$n unsaved"
  # on a narrow screen the file name matters more than the settings
  (( ${#left} + ${#right} + ${#tail} + 3 > w )) && right=""
  plain="$right$tail "
  room=$(( w - ${#plain} - 2 ))
  (( room < 0 )) && room=0
  left=${left:0:room}
  spaces "$(( w - ${#left} - ${#plain} ))"
  if (( n )); then tail="${C_B}${C_Y}$tail${C_0}"; else tail="${C_D}$tail${C_0}"; fi
  RET="${C_B}$left${C_0}$RET${C_D}$right${C_0}$tail "
}

# render_footer W CONTEXT POSITION -> RET: the keys that work right now, the
# key bright and its meaning dim, and the position in the list on the right.
render_footer() {
  local w=$1 pos=$3 out=" " len=1 h k l add room
  local -a hints=()
  case $2 in
    picker) hints=("$GL_K_ARROWS|choose" "Tab|next field" "$GL_K_SPACE|toggle" "$GL_K_ENTER|accept"
                   "Esc q|cancel" "?|help" "e|type a code" "r|reset") ;;
    prompt) hints=("$GL_K_ENTER|apply" "Esc|cancel") ;;
    help)   hints=("$GL_K_MOVE|scroll" "any other key|back") ;;
    *)      hints=("$GL_K_MOVE|move" "$GL_K_ENTER|edit" "$GL_K_SPACE|fold" "?|help" "/|search" "u|undo"
                   "s|save" "q|quit" "x|codes" "z Z|fold all, none" "c|case pairs") ;;
  esac
  room=$(( w - ${#pos} - 2 ))
  for h in "${hints[@]}"; do
    k=${h%%|*} l=${h#*|}
    add=$(( ${#k} + ${#l} + 4 ))
    (( len + add > room )) && break
    out+="${C_B}$k${C_0} ${C_D}$l${C_0}   "
    len=$(( len + add ))
  done
  (( ${#pos} + 1 > w )) && pos=""
  spaces "$(( w - len - ${#pos} - 1 ))"
  RET="$out$RET${C_D}$pos${C_0} "
}

# row_text REF LIMIT -> RET text, RET2 its width: what stands behind the
# pattern of an entry. Needs entry_values to have run for the entry.
row_text() {
  local limit=$2 v plain="" out=""
  (( limit < 0 )) && limit=0
  if (( EV_MOD )); then
    if (( T_RAW )); then RET=$EV_EFF; else describe_value "$EV_EFF"; fi
    plain="* $GL_TO $RET"
    out="${C_B}${C_Y}*${C_0} ${C_D}$GL_TO${C_0} $RET"
  else
    for v in "${EV_LIST[@]}"; do
      if (( T_RAW )); then RET=$v; else describe_value "$v"; fi
      plain+="${plain:+ | }$RET"
    done
    out="${C_D}$plain${C_0}"
    if (( ${#EV_LIST[@]} > 1 )); then plain+="  differs" out+="  ${C_Y}differs${C_0}"; fi
  fi
  if (( ${#plain} > limit )); then
    plain=${plain:0:limit}
    out="${C_D}$plain${C_0}"
  fi
  RET=$out RET2=${#plain}
}

# render_list W H: the list as H rows of at most W characters, in LP_TXT,
# with the width of each row in LP_LEN.
declare -a LP_TXT=() LP_LEN=()
render_list() {
  local w=$1 h=$2 r idx kind ref wn=22 wl=20 wt name label cell clen extra gutter pad1 pad2
  local mark warn plain tail limit
  LP_TXT=() LP_LEN=()
  (( w < 70 )) && wn=16 wl=14
  if (( w < 44 )); then
    # no room for the colour in words: sample and pattern share the pane
    wn=14 wl=$(( w - 23 ))
    (( wl < 0 )) && wl=0
  fi
  wt=$GW_TITLE
  (( wt > w - 12 )) && wt=$(( w - 12 > 0 ? w - 12 : 0 ))
  (( T_CUR < T_TOP )) && T_TOP=$T_CUR
  (( T_CUR >= T_TOP + h )) && T_TOP=$(( T_CUR - h + 1 ))
  # keep the heading of the first visible entry on screen
  (( T_TOP > 0 )) && [[ ${ROW_KIND[T_TOP-1]:-} == h && $T_CUR -eq $T_TOP ]] && T_TOP=$(( T_TOP - 1 ))
  (( T_TOP < 0 )) && T_TOP=0
  for (( r = 0; r < h; r++ )); do
    idx=$(( T_TOP + r ))
    LP_TXT[r]="" LP_LEN[r]=0
    (( idx < ${#ROW_KIND[@]} )) || continue
    kind=${ROW_KIND[idx]} ref=${ROW_REF[idx]}
    # the cursor is a bar in the margin and a brighter text; reverse video
    # would be mistaken for the colour of an entry
    if (( idx != T_CUR )); then gutter=" "
    elif (( LIST_DIM )); then gutter="${C_D}$GL_CUR${C_0}"
    else gutter="${C_B}${C_C}$GL_CUR${C_0}"
    fi
    if [[ $kind == h ]]; then
      # fold marker, title, number of entries, what colour they have
      if is_folded "$ref"; then mark=$GL_SHUT; else mark=$GL_OPEN; fi
      name=${G_TITLE[ref]:0:wt}
      spaces "$(( wt - ${#name} ))"; pad1=$RET
      printf -v cell '%4d' "${G_N[ref]}"
      if (( T_RAW )); then RET=${G_MAJ[ref]}; else describe_value "${G_MAJ[ref]}"; fi
      plain=$RET tail="${C_D}$RET${C_0}"
      if (( G_DIFF[ref] )); then
        plain+="  (${G_DIFF[ref]} differ)" tail+="  ${C_Y}(${G_DIFF[ref]} differ)${C_0}"
      fi
      if (( G_WARN[ref] )); then
        plain+="  $GL_WARN ${G_WARN[ref]}" tail+="  ${C_Y}$GL_WARN ${G_WARN[ref]}${C_0}"
      fi
      limit=$(( w - wt - 12 ))
      (( limit < 0 )) && limit=0
      if (( ${#plain} > limit )); then plain=${plain:0:limit} tail="${C_D}$plain${C_0}"; fi
      if (( idx == T_CUR && ! LIST_DIM )); then name="${C_B}${C_C}$name${C_0}"
      elif (( LIST_DIM )); then name="${C_D}$name${C_0}"
      else name="${C_B}$name${C_0}"
      fi
      LP_TXT[r]="$gutter$mark $name$pad1  ${C_D}$cell${C_0}   $tail"
      LP_LEN[r]=$(( wt + 12 + ${#plain} ))
      continue
    fi
    entry_values "$ref"
    name=${E_NAME[ref]:0:wn} label=${E_LABEL[ref]:0:wl}
    paint "$EV_EFF" "$name"
    cell=$RET clen=${#name}
    # a name that can hardly be read in its colour is repeated in plain text
    if hard_to_read "$EV_EFF" && (( clen + 2 < wn )); then
      extra=${E_NAME[ref]:0:$(( wn - clen - 1 ))}
      cell+=" ${C_D}$extra${C_0}" clen=$(( clen + 1 + ${#extra} ))
    fi
    spaces "$(( wn - clen ))"; pad1=$RET
    spaces "$(( wl - ${#label} ))"; pad2=$RET
    row_text "$ref" "$(( w - wn - wl - 9 ))"
    (( idx == T_CUR && ! LIST_DIM )) && label="${C_B}$label${C_0}"
    (( LIST_DIM )) && label="${C_D}$label${C_0}"
    warn=" "
    [[ -n ${E_WARN[ref]:-} ]] && warn="${C_Y}$GL_WARN${C_0}"
    LP_TXT[r]="$gutter  $warn $cell$pad1  $label$pad2  $RET"
    # shellcheck disable=SC2034
    LP_LEN[r]=$(( wn + wl + 9 + RET2 ))
  done
}

# info_line W -> RET: the row above the key hints: a message, what check says
# about the row under the cursor, or the filter.
info_line() {
  local w=$1 ref=${ROW_REF[T_CUR]:-} text=""
  (( w > 1 )) || { RET=""; return; }
  if [[ -n $T_MSG ]]; then
    RET=" ${T_MSG:0:$(( w - 1 ))}"
    return
  fi
  case ${ROW_KIND[T_CUR]:-} in
    e) text=${E_WARN[ref]:-} ;;
    h) (( ${G_WARN[ref]:-0} )) && text="check has findings for ${G_WARN[ref]} of these entries; unfold to see them" ;;
  esac
  if [[ -n $text ]]; then
    text="$GL_WARN $text"
    RET=" ${C_Y}${text:0:$(( w - 1 ))}${C_0}"
  elif [[ -n $T_FILTER ]]; then
    RET=" ${C_D}filter:${C_0} ${T_FILTER:0:$(( w - 24 > 0 ? w - 24 : 0 ))}  ${C_D}(Esc clears)${C_0}"
  else
    RET=""
  fi
}

# The layout follows the size of the terminal on every frame, so a resize
# switches between them even while the picker is open:
#   list    the list alone
#   split   the list on the left, the picker on the right (wide terminals)
#   full    the picker alone (narrower terminals)
#   small   a note that the terminal is too small
# The list pane is never wider than LIST_W, so on a wide screen the picker
# sits next to the list instead of at the far edge. The picker pane grows
# to PANE_R_256 with --256, where a cube row of 36 cells fits.
SPLIT_COLS=100 MIN_COLS=40 MIN_ROWS=10 PANE_R=44 PANE_R_256=80 LIST_W=78
layout() {
  T_LAYOUT=list
  if (( COLS < MIN_COLS || ROWS < MIN_ROWS )); then
    T_LAYOUT="small"
  elif [[ $T_FOCUS == picker ]]; then
    # a short picker scrolls to keep the field with the focus in view
    if (( COLS >= SPLIT_COLS )); then T_LAYOUT="split"; else T_LAYOUT="full"; fi
  fi
}

# compose_frame -> RET: the whole screen as frame text for emit_frame.
# Row 1 header, row 2 a rule, then the panes, a rule, the message row and
# the key hints.
compose_frame() {
  local buf r h=$(( ROWS - 5 )) pos="" lw rw lrule rrule line
  (( h < 1 )) && h=1
  layout
  if [[ $T_LAYOUT == small ]]; then
    local -a lines=()
    buf=""
    wrap_words "The terminal is too small for the editor." "$(( COLS - 2 ))"
    lines=("${WRAP[@]}" "")
    wrap_words "Please make it at least $MIN_COLS columns wide and $MIN_ROWS rows high (it is $COLS x $ROWS now)." "$(( COLS - 2 ))"
    lines+=("${WRAP[@]}" "")
    if [[ $T_FOCUS == picker ]]; then wrap_words "Esc closes the colour picker." "$(( COLS - 2 ))"
    else wrap_words "q quits." "$(( COLS - 2 ))"
    fi
    WRAP=("${lines[@]}" "${WRAP[@]}")
    for (( r = 1; r <= ROWS; r++ )); do
      buf+="${ROW_AT}${r}${ROW_TXT}"
      (( r >= 2 && r - 2 < ${#WRAP[@]} )) && buf+=" ${WRAP[r-2]:0:$(( COLS - 1 > 0 ? COLS - 1 : 0 ))}"
    done
    RET=$buf
    return
  fi
  render_header "$COLS"
  buf="${ROW_AT}1${ROW_TXT}$RET"
  case $T_LAYOUT in
    split)
      lw=$(( COLS - PANE_R - 1 ))
      (( lw > LIST_W )) && lw=$LIST_W
      rw=$(( COLS - lw - 1 ))
      if (( OPT_256 )); then (( rw > PANE_R_256 )) && rw=$PANE_R_256
      else (( rw > PANE_R )) && rw=$PANE_R
      fi
      LIST_DIM=1
      render_list "$lw" "$h"
      LIST_DIM=0
      render_picker "$rw" "$h"
      # every rule has the same colour; the focus shows in the bright
      # labels of the picker and the dimmed cursor of the list
      rule "$lw"; lrule="${C_D}$RET${C_0}"
      # the rules run on to the edge of the screen when the panes end earlier
      rule "$(( COLS - lw - 1 ))"; rrule="${C_D}$RET${C_0}"
      buf+="${ROW_AT}2${ROW_TXT}$lrule${C_D}$GL_TEE${C_0}$rrule"
      for (( r = 0; r < h; r++ )); do
        spaces "$(( lw - LP_LEN[r] ))"
        buf+="${ROW_AT}$(( r + 3 ))${ROW_TXT}${LP_TXT[r]}${C_0}$RET${C_D}$GL_V${C_0}${RP_TXT[r]:-}"
      done
      buf+="${ROW_AT}$(( ROWS - 2 ))${ROW_TXT}$lrule${C_D}$GL_FOOT${C_0}$rrule" ;;
    full)
      rule "$COLS"; line="${C_D}$RET${C_0}"
      buf+="${ROW_AT}2${ROW_TXT}$line"
      render_picker "$COLS" "$h"
      for (( r = 0; r < h; r++ )); do buf+="${ROW_AT}$(( r + 3 ))${ROW_TXT}${RP_TXT[r]:-}"; done
      buf+="${ROW_AT}$(( ROWS - 2 ))${ROW_TXT}$line" ;;
    *)
      rule "$COLS"; line="${C_D}$RET${C_0}"
      buf+="${ROW_AT}2${ROW_TXT}$line"
      render_list "$COLS" "$h"
      for (( r = 0; r < h; r++ )); do buf+="${ROW_AT}$(( r + 3 ))${ROW_TXT}${LP_TXT[r]}"; done
      buf+="${ROW_AT}$(( ROWS - 2 ))${ROW_TXT}$line" ;;
  esac
  info_line "$COLS"
  buf+="${ROW_AT}$(( ROWS - 1 ))${ROW_TXT}$RET"
  case ${ROW_KIND[T_CUR]:-} in
    e) pos="${E_ORD[${ROW_REF[T_CUR]}]}/$T_TOTAL" ;;
    h) pos="$T_TOTAL entries" ;;
  esac
  [[ $T_FOCUS == picker ]] && pos=""
  render_footer "$COLS" "$T_CTX" "$pos"
  buf+="${ROW_AT}${ROWS}${ROW_TXT}$RET"
  RET=$buf
}

draw_screen() {
  compose_frame
  emit_frame "$RET"
}

# --- the colour picker -------------------------------------------------------

# swatch VALUE STATE -> RET: a two-character cell showing the colour. STATE 1
# is the cell under the picker's cursor, 2 the colour that is in the file.
swatch() {
  local v=$1 bg n light=0 text="  "
  case $v in
    "")
      case $2 in
        1) RET="${ESC}[7mdf${ESC}[0m" ;;
        2) RET="${C_B}${C_U}df${C_0}" ;;
        *) RET="${C_D}df${C_0}" ;;
      esac
      return ;;
    3[0-7])  bg="4${v:1:1}"; n=${v:1:1} ;;
    4[0-7])  bg=$v; n=${v:1:1} ;;
    9[0-7])  bg="10${v:1:1}"; n=$(( ${v:1:1} + 8 )) ;;
    10[0-7]) bg=$v; n=$(( ${v:2:1} + 8 )) ;;
    [34]8\;5\;*) n=$(( 10#${v##*;} )); bg="48;5;$n" ;;
    *)       bg="48;${v#*;}"; n=0 ;;
  esac
  # dark text on light colours, light text on dark ones
  if (( n < 16 )); then
    case $n in 7|10|11|14|15) light=1 ;; esac
  elif (( n < 232 )); then
    (( ((n - 16) / 36) * 2 + (((n - 16) / 6) % 6) * 5 + (n - 16) % 6 >= 20 )) && light=1
  else
    (( n >= 244 )) && light=1
  fi
  case $2 in
    1) text=$PK_MARK ;;
    2) text=$GL_SAVED ;;
  esac
  if (( ! USE_COLOUR )); then
    RET=$text
    [[ $text == "  " ]] && RET=$GL_SW
  elif (( light )); then
    RET="${ESC}[${bg};30m${text}${ESC}[0m"
  else
    RET="${ESC}[${bg};97m${text}${ESC}[0m"
  fi
}

# picker_cells FG BG: the choices for foreground and background: default,
# the 8 normal and the 8 bright colours, then with --256 the rest of the 256.
# A value that the palette does not offer (a 256-colour code in 16-colour
# mode, say) gets a cell of its own in front, so it is shown and kept unless
# changed. FG_B and BG_B count the cells in front of the 16 colours.
picker_cells() {
  local fg=$1 bg=$2 n i
  FG_CELLS=("") BG_CELLS=("")
  for (( n = 0; n < 8; n++ )); do FG_CELLS+=("3$n"); BG_CELLS+=("4$n"); done
  for (( n = 0; n < 8; n++ )); do FG_CELLS+=("9$n"); BG_CELLS+=("10$n"); done
  FG_B=1 BG_B=1
  if (( OPT_256 )); then
    for (( n = 16; n < 256; n++ )); do FG_CELLS+=("38;5;$n"); BG_CELLS+=("48;5;$n"); done
  fi
  PK_FG=-1 PK_BG=-1
  for i in "${!FG_CELLS[@]}"; do [[ ${FG_CELLS[i]} == "$fg" ]] && PK_FG=$i; done
  for i in "${!BG_CELLS[@]}"; do [[ ${BG_CELLS[i]} == "$bg" ]] && PK_BG=$i; done
  if (( PK_FG < 0 )); then FG_CELLS=("$fg" "${FG_CELLS[@]}"); FG_B=2 PK_FG=0; fi
  if (( PK_BG < 0 )); then BG_CELLS=("$bg" "${BG_CELLS[@]}"); BG_B=2 PK_BG=0; fi
}

# The palette of a field is drawn in rows: row 0 holds the cells in front
# (default, and an unusual value) and the 8 normal colours, row 1 the 8 bright
# colours under them. With --256 the colour cube follows, PK_CW cells a row
# (36 when there is room, otherwise 18), then the 24 greys.

# grid_rows_n B -> RET: how many rows the palette has.
grid_rows_n() {
  if (( OPT_256 )); then RET=$(( 2 + 216 / PK_CW + 24 / (PK_CW * 2 / 3) )); else RET=2; fi
}

# grid_start ROW B -> RET first index of the row, RET2 its length, RET3 the
# number of empty cells in front of it.
grid_start() {
  local r=$1 b=$2 cube=$(( 216 / PK_CW )) gw=$(( PK_CW * 2 / 3 ))
  if (( r == 0 )); then
    RET=0 RET2=$(( b + 8 )) RET3=0
  elif (( r == 1 )); then
    RET=$(( b + 8 )) RET2=8 RET3=$b
  elif (( r < 2 + cube )); then
    RET=$(( b + 16 + (r - 2) * PK_CW )) RET2=$PK_CW RET3=0
  else
    RET=$(( b + 16 + 216 + (r - 2 - cube) * gw )) RET2=$gw RET3=0
  fi
}

# grid_row INDEX B -> RET row, RET2 column within the row.
grid_row() {
  local i=$1 b=$2 cube=$(( 216 / PK_CW )) gw=$(( PK_CW * 2 / 3 ))
  if (( i < b + 8 )); then
    RET=0 RET2=$i
  elif (( i < b + 16 )); then
    RET=1 RET2=$(( i - b - 8 ))
  elif (( i < b + 16 + 216 )); then
    RET=$(( 2 + (i - b - 16) / PK_CW )) RET2=$(( (i - b - 16) % PK_CW ))
  else
    RET=$(( 2 + cube + (i - b - 232) / gw )) RET2=$(( (i - b - 232) % gw ))
  fi
}

# picker_value -> RET: the value the picker stands for at the moment.
picker_value() {
  if [[ -n $PK_RAW ]]; then RET=$PK_RAW; return; fi
  sgr_compose "${FG_CELLS[PK_FG]}" "${BG_CELLS[PK_BG]}" "$PK_ATTRS" "$PK_EXTRA" "$PK_PAD" "$PK_ZERO"
}

# picker_move DY DX: move inside the grid of the focused field; leaving it at
# the top or bottom goes to the neighbouring field. Up and down keep the
# column on screen.
picker_move() {
  local dy=$1 dx=$2 idx b ncells row col vis
  PK_RAW=""
  if (( PK_FIELD == 2 )); then
    PK_AT=$(( PK_AT + dx ))
    (( PK_AT < 0 )) && PK_AT=0
    (( PK_AT > 4 )) && PK_AT=4
    (( dy < 0 )) && PK_FIELD=1
    return
  fi
  if (( PK_FIELD == 0 )); then
    idx=$PK_FG b=$FG_B ncells=${#FG_CELLS[@]}
  else
    idx=$PK_BG b=$BG_B ncells=${#BG_CELLS[@]}
  fi
  if (( dx )); then
    idx=$(( idx + dx ))
    (( idx < 0 )) && idx=0
    (( idx >= ncells )) && idx=$(( ncells - 1 ))
  else
    grid_row "$idx" "$b"
    row=$(( RET + dy )) col=$RET2
    grid_start "$RET" "$b"
    vis=$(( RET3 + col ))
    grid_rows_n "$b"
    if (( row < 0 )); then
      (( PK_FIELD > 0 )) && PK_FIELD=$(( PK_FIELD - 1 ))
      return
    elif (( row >= RET )); then
      PK_FIELD=$(( PK_FIELD + 1 ))
      return
    fi
    grid_start "$row" "$b"
    col=$(( vis - RET3 ))
    (( col < 0 )) && col=0
    (( col >= RET2 )) && col=$(( RET2 - 1 ))
    idx=$(( RET + col ))
  fi
  PK_TOUCHED=1
  if (( PK_FIELD == 0 )); then PK_FG=$idx; else PK_BG=$idx; fi
}

# rp_add TEXT [OPTIONAL]: add a row to the picker. Optional rows go when the
# pane is short: spacing (1) first, from the bottom up, then notes (2).
# A known WIDTH saves measuring the row later, which is slow for the rows
# of the palette with an escape sequence for every cell.
rp_add() {
  RP_TXT+=("$1")
  RP_OPT+=("${2:-0}")
  RP_W+=("${3:--1}")
}

# wrap_words TEXT W -> WRAP: TEXT broken into lines of at most W characters.
declare -a WRAP=()
wrap_words() {
  local w=$2 line="" word
  local -a words=()
  WRAP=()
  (( w < 10 )) && w=10
  read -r -a words <<<"$1"
  for word in "${words[@]}"; do
    if [[ -n $line ]] && (( ${#line} + 1 + ${#word} > w )); then
      WRAP+=("$line")
      line=""
    fi
    line+="${line:+ }${word:0:w}"
  done
  [[ -n $line ]] && WRAP+=("$line")
}

# strip_paint VALUE BG TEXT -> RET: TEXT in the colour VALUE on a strip of
# background BG, roughly as it looks on a dark or a light terminal.
strip_paint() {
  local code
  sgr_parse "$1"
  if (( ! USE_COLOUR )) || [[ -n $SGR_BAD ]]; then RET=" $3 "; return; fi
  sgr_compose "$SGR_FG" "${SGR_BG:-$2}" "$SGR_ATTRS" "$SGR_EXTRA" 0 0
  code=$RET
  RET="${ESC}[0;${2}m ${ESC}[0;${code}m$3${ESC}[0;${2}m ${ESC}[0m"
}

# field_rows FIELD W: the label and the palette rows of a field.
field_rows() {
  local field=$1 w=$2 idx b saved rows r i line first last name len
  local -a cells=()
  if (( field == 0 )); then
    cells=("${FG_CELLS[@]}") idx=$PK_FG b=$FG_B saved=$PK_SFG name="Foreground"
  else
    cells=("${BG_CELLS[@]}") idx=$PK_BG b=$BG_B saved=$PK_SBG name="Background"
  fi
  describe_colour "${cells[idx]}"
  if (( PK_FIELD == field )); then
    rp_add "  ${C_B}${C_C}$name${C_0}   ${C_B}$RET${C_0}"
  else
    rp_add "  ${C_D}$name${C_0}   $RET"
  fi
  (( PK_FIELD == field )) && RP_FOCUS=${#RP_TXT[@]}
  # the large palette is only unfolded for the field that has the focus
  rows=2
  if (( OPT_256 && PK_FIELD == field )); then grid_rows_n "$b"; rows=$RET; fi
  for (( r = 0; r < rows; r++ )); do
    grid_start "$r" "$b"
    first=$RET last=$(( RET + RET2 ))
    if (( r < 2 )); then spaces "$(( 3 + RET3 * 3 ))"; else spaces 3; fi
    line=$RET
    len=${#line}
    for (( i = first; i < last && i < ${#cells[@]}; i++ )); do
      if (( r < 2 )); then len=$(( len + 3 )); else len=$(( len + 2 )); fi
      if (( i == idx )); then swatch "${cells[i]}" 1
      elif (( i == saved )); then swatch "${cells[i]}" 2
      else swatch "${cells[i]}" 0
      fi
      line+=$RET
      (( r < 2 )) && line+=" "
    done
    # keep the row of the cursor in view when the pane has to scroll
    (( PK_FIELD == field && i > idx && idx >= first )) && RP_FOCUS=${#RP_TXT[@]}
    rp_add "$line" 0 "$len"
  done
  rp_add "" 1
}

# render_picker W H: the picker as rows in RP_TXT, at most W wide and, when
# it has to, cut down to H rows around the field that has the focus.
declare -a RP_TXT=() RP_OPT=() RP_W=() RP_LEN=()
PK_CW=36 PK_SFG=-1 PK_SBG=-1 PK_FILE="" RP_FOCUS=0
render_picker() {
  local w=$1 h=$2 ref=$PK_REF value title sec pad i line len nw name names=(bold dim underline reverse blink) codes=(1 2 4 7 5)
  local -a keep=() keepw=()
  RP_TXT=() RP_OPT=() RP_W=() RP_LEN=() RP_FOCUS=0
  if (( w >= 76 )); then PK_CW=36; else PK_CW=18; fi
  picker_value
  value=$RET
  # what is being edited, and where it lives
  title=${E_LABEL[ref]} sec=${E_SEC[ref]}
  (( ${#sec} > w / 3 )) && sec=${sec:0:$(( w / 3 ))}
  (( ${#title} > w - ${#sec} - 5 )) && title=${title:0:$(( w - ${#sec} - 5 > 0 ? w - ${#sec} - 5 : 0 ))}
  spaces "$(( w - ${#title} - ${#sec} - 3 ))"
  rp_add "  ${C_B}$title${C_0}$RET${C_D}$sec${C_0} "
  rp_add "" 1
  # the sample on a dark and on a light strip, now and before
  name=${E_NAME[ref]}
  nw=$(( (w - 12) / 2 ))
  (( nw < 4 )) && nw=4
  name=${name:0:nw}
  strip_paint "$value" 40 "$name"; line="  ${C_B}new${C_0}  $RET "
  strip_paint "$value" 107 "$name"; line+="$RET  ${C_D}$value${C_0}"
  rp_add "$line"
  strip_paint "$PK_START" 40 "$name"; line="  ${C_D}was${C_0}  $RET "
  strip_paint "$PK_START" 107 "$name"; line+="$RET  ${C_D}${PK_OLD}${C_0}"
  rp_add "$line"
  wrap_words "The strips are an approximation: your terminal's own background is what counts." "$(( w - 4 ))"
  for line in "${WRAP[@]}"; do rp_add "  ${C_D}$line${C_0}" 2; done
  if [[ $PK_OLD == *"|"* ]]; then
    wrap_words "The spellings of this entry have different colours; accepting sets all of them." "$(( w - 4 ))"
    for line in "${WRAP[@]}"; do rp_add "  ${C_Y}$line${C_0}"; done
  fi
  rp_add "" 1
  field_rows 0 "$w"
  field_rows 1 "$w"
  # the switches, as many to a row as fit
  if (( PK_FIELD == 2 )); then
    rp_add "  ${C_B}${C_C}Attributes${C_0}"
    RP_FOCUS=${#RP_TXT[@]}
  else
    rp_add "  ${C_D}Attributes${C_0}"
  fi
  line="  " len=2
  for i in 0 1 2 3 4; do
    title="[ ] ${names[i]}"
    [[ $PK_ATTRS == *" ${codes[i]} "* ]] && title="[x] ${names[i]}"
    if (( len + ${#title} + 1 > w && len > 2 )); then rp_add "$line"; line="  " len=2; fi
    if (( PK_FIELD == 2 && PK_AT == i )); then
      line+=" ${C_B}${C_C}$title${C_0} "
    else
      line+=" $title "
    fi
    len=$(( len + ${#title} + 2 ))
  done
  rp_add "$line"
  if [[ -n $PK_EXTRA ]]; then rp_add "  ${C_D}other codes kept: $PK_EXTRA${C_0}"; fi
  # too long for the pane: drop the spacing and the notes first
  local level n=${#RP_TXT[@]}
  for level in 1 2; do
    for (( i = ${#RP_OPT[@]} - 1; i >= 0 && n > h; i-- )); do
      if (( RP_OPT[i] == level )); then RP_OPT[i]=-1; n=$(( n - 1 )); fi
    done
  done
  if (( n < ${#RP_TXT[@]} )); then
    keep=() keepw=()
    pad=$RP_FOCUS
    for i in "${!RP_TXT[@]}"; do
      if (( RP_OPT[i] < 0 )); then
        (( i < RP_FOCUS )) && pad=$(( pad - 1 ))
        continue
      fi
      keep+=("${RP_TXT[i]}") keepw+=("${RP_W[i]}")
    done
    RP_TXT=("${keep[@]}") RP_W=("${keepw[@]}") RP_FOCUS=$pad
  fi
  # still too long: show the part around the focus
  if (( ${#RP_TXT[@]} > h )); then
    i=$(( RP_FOCUS - h + 3 ))
    (( i > ${#RP_TXT[@]} - h )) && i=$(( ${#RP_TXT[@]} - h ))
    (( i < 0 )) && i=0
    RP_TXT=("${RP_TXT[@]:i:h}") RP_W=("${RP_W[@]:i:h}")
  fi
  for i in "${!RP_TXT[@]}"; do
    if (( RP_W[i] >= 0 && RP_W[i] <= w )); then
      # shellcheck disable=SC2034
      RP_LEN[i]=${RP_W[i]}
      continue
    fi
    fit_row "${RP_TXT[i]}" "$w"
    # shellcheck disable=SC2034
    RP_TXT[i]=$RET RP_LEN[i]=$RET2
  done
}

# fit_row TEXT W -> RET text cut to W characters on screen, RET2 its width.
RE_SGR_AT="^(${ESC}\\[[0-9;]*m)"
fit_row() {
  local t=$1 w=$2 out="" n=0
  strip_sgr "$t"
  if (( ${#RET} <= w )); then RET2=${#RET} RET=$t; return; fi
  while [[ -n $t ]] && (( n < w )); do
    if [[ $t =~ $RE_SGR_AT ]]; then
      out+=${BASH_REMATCH[1]}
      t=${t:${#BASH_REMATCH[1]}}
    else
      out+=${t:0:1}
      t=${t:1}
      n=$(( n + 1 ))
    fi
  done
  RET="$out${C_0}" RET2=$n
}

# picker_load VALUE: set the picker to show VALUE.
picker_load() {
  sgr_parse "$1"
  PK_RAW="" PK_TOUCHED=0
  if [[ -n $SGR_BAD ]]; then
    # nothing sensible to show for a malformed code: start from scratch
    PK_ATTRS=" " PK_EXTRA="" PK_PAD=1 PK_ZERO=0
    picker_cells "" ""
  else
    PK_ATTRS=$SGR_ATTRS PK_EXTRA=$SGR_EXTRA PK_PAD=$SGR_PAD PK_ZERO=$SGR_ZERO
    picker_cells "$SGR_FG" "$SGR_BG"
  fi
  # the colours that are in the file get a mark of their own
  local i
  PK_SFG=-1 PK_SBG=-1
  sgr_parse "$PK_FILE"
  if [[ -z $SGR_BAD ]]; then
    for i in "${!FG_CELLS[@]}"; do [[ ${FG_CELLS[i]} == "$SGR_FG" ]] && PK_SFG=$i; done
    for i in "${!BG_CELLS[@]}"; do [[ ${BG_CELLS[i]} == "$SGR_BG" ]] && PK_SBG=$i; done
  fi
}

# file_value ENTRY -> RET: the value the entry has in the file, without the
# staged changes.
file_value() {
  local i last=0
  RET=""
  for i in ${E_LINES[$1]}; do
    if (( i > last )); then last=$i RET=${L_VAL[i]}; fi
  done
}

# preview_set: show what the picker stands for in the list while it is open.
preview_set() {
  PV=()
  if (( PK_TOUCHED )); then
    picker_value
    PV[$PK_REF]=$RET
  fi
  summarise "${E_GRP[PK_REF]}"
}

# open_picker ENTRY: edit one entry. Stages the result on Enter.
open_picker() {
  local ref=$1 old v i record="" codes=(1 2 4 7 5) a dirty=1
  entry_values "$ref"
  PK_START=$EV_EFF
  old=$PK_START
  (( ${#EV_LIST[@]} > 1 )) && old=$(IFS='|'; printf '%s' "${EV_LIST[*]}")
  old=${old//|/ | }
  file_value "$ref"
  PK_FILE=$RET
  PK_REF=$ref PK_OLD=$old
  picker_load "$PK_START"
  PK_FIELD=0 PK_AT=0 T_MSG=""
  T_FOCUS=picker T_CTX=picker
  while :; do
    if (( dirty )); then
      preview_set
      draw_screen
      T_MSG="" dirty=0
    fi
    if ! read_key 0.25; then
      if (( RESIZED )); then RESIZED=0; term_size; screen_reset; dirty=1; fi
      # Ctrl-C closes the picker; the list then asks whether to quit
      if (( ! INTR )); then continue; fi
      KEY=esc
    fi
    dirty=1
    case $KEY in
      \?)     show_help ;;
      up|k)    picker_move -1 0 ;;
      down|j)  picker_move 1 0 ;;
      left|h)  picker_move 0 -1 ;;
      right|l) picker_move 0 1 ;;
      tab)     PK_FIELD=$(( (PK_FIELD + 1) % 3 )) ;;
      backtab) PK_FIELD=$(( (PK_FIELD + 2) % 3 )) ;;
      space)
        if (( PK_FIELD == 2 )); then
          a=${codes[PK_AT]}
          PK_RAW="" PK_TOUCHED=1
          if [[ $PK_ATTRS == *" $a "* ]]; then PK_ATTRS=${PK_ATTRS/" $a "/ }; else PK_ATTRS+="$a "; fi
        fi ;;
      r)
        # back to the colour in the file
        picker_load "$PK_FILE"
        [[ $PK_FILE != "$PK_START" ]] && PK_TOUCHED=1 ;;
      e)
        T_CTX=prompt
        draw_screen
        T_CTX=picker
        picker_value
        if line_input " SGR code (numbers joined by ;): " "$RET"; then
          sgr_parse "$RET"
          if [[ -n $SGR_BAD ]]; then
            T_MSG="${C_R}Not a valid code: $RET${C_0}"
          else
            v=$RET
            picker_load "$v"
            PK_RAW=$v PK_TOUCHED=1
          fi
        fi ;;
      enter) break ;;
      esc|q|eof) PV=(); T_FOCUS=list T_CTX=list; build_rows; return 1 ;;
    esac
  done
  PV=()
  T_FOCUS=list T_CTX=list
  if (( ! PK_TOUCHED )); then build_rows; return 1; fi
  picker_value
  v=$RET
  for i in ${E_LINES[ref]}; do
    if [[ -n ${ST[i]+x} ]]; then record+="$i=V${ST[i]}$NL"; else record+="$i=U$NL"; fi
    if [[ $v == "${L_VAL[i]}" ]]; then unset "ST[$i]"; else ST[i]=$v; fi
  done
  UNDO+=("${record%"$NL"}")
  build_rows
  describe_value "$v"
  T_MSG="${E_LABEL[ref]} set to $RET ($v)"
  return 0
}

undo_last() {
  local n=${#UNDO[@]} line i
  if (( ! n )); then T_MSG="Nothing to undo."; return; fi
  while IFS= read -r line; do
    i=${line%%=*}
    if [[ ${line#*=} == U ]]; then unset "ST[$i]"; else ST[i]=${line#*=V}; fi
  done <<<"${UNDO[n-1]}"
  unset "UNDO[$(( n - 1 ))]"
  build_rows
  T_MSG="Undone."
}

# save_staged: leave the full screen, show the diff, ask, write, come back.
save_staged() {
  local i
  if (( ! ${#ST[@]} )); then T_MSG="Nothing to save."; return; fi
  for i in "${!ST[@]}"; do set_value "$i" "${ST[i]}"; done
  tui_suspend
  trap 'exit 130' INT
  if review_and_save; then
    read_file "$FILE_REAL"
    ST=() UNDO=()
    run_checks
    build_entries
    T_MSG="Saved. Backup: $BACKUP_PATH"
  else
    # not written: put the document back, the changes stay staged
    SRC=("${ORIG[@]}")
    N=$(( ${#SRC[@]} - 1 ))
    parse
    T_MSG="Not saved; your changes are still staged."
  fi
  printf '\nPress Enter to return to the editor. '
  IFS= read -r i
  trap 'INTR=1' INT
  tui_start
  term_size
  build_rows
}

# help_lines -> HELP: the text of the help screen, with the same key symbols
# as the hints in the last row.
declare -a HELP=()
help_lines() {
  local m=$GL_K_MOVE a=$GL_K_ARROWS l=$GL_K_LEFT r=$GL_K_RIGHT n=$GL_K_ENTER sp=$GL_K_SPACE
  HELP=()
  # hk KEYS TEXT: one line, the keys padded in characters (printf would
  # count the bytes of the arrow symbols)
  hk() { spaces "$(( 22 - ${#1} ))"; HELP+=("  $1$RET $2"); }
  HELP+=("Keys in the list")
  hk "$m, j k" "move one row"
  hk "PgUp PgDn" "move one page"
  hk "Home End, g G" "first or last row"
  hk "$n, l, $r" "edit the colour of the entry"
  hk "$sp" "fold or unfold the section ($n does the same on a heading)"
  hk "l, $r on a heading" "unfold it, or go to its first entry when it is open"
  hk "h, $l" "fold the section on a heading, or go to the heading from an entry"
  hk "z / Z" "fold every section / unfold every section"
  hk "/" "search (pattern, sample name or section); Esc clears"
  hk "x" "show the codes instead of the colours in words"
  hk "c" "join or separate case pairs such as .deb / .DEB"
  hk "u" "undo the last change"
  hk "s" "review the changes and save them"
  hk "q, Ctrl-C" "quit (asks when there are unsaved changes)"
  hk "?" "this help"
  HELP+=("" "Keys in the colour picker")
  hk "$a, h j k l" "choose a colour or an attribute"
  hk "Tab / Shift-Tab" "next / previous field (foreground, background, attributes)"
  hk "$sp" "switch an attribute on or off"
  hk "e" "type an SGR code by hand"
  hk "r" "back to the colour in the file"
  hk "$n" "accept"
  hk "Esc, q" "cancel"
  hk "?" "this help"
  HELP+=(""
    "The list shows the colour under the picker's cursor while you choose. From"
    "$SPLIT_COLS columns on, the picker opens beside the list, otherwise in its place."
    ""
    "Nothing is written until you press s, look at the diff and confirm."
    "A backup is made next to the file before the first write."
  )
}

# show_help: the help screen; it scrolls when the terminal is short.
show_help() {
  local buf y line top=0 h=$(( ROWS - 5 )) n i ctx=$T_CTX
  help_lines
  n=${#HELP[@]}
  (( h < 1 )) && h=1
  T_CTX=help
  while :; do
    (( top > n - h )) && top=$(( n - h ))
    (( top < 0 )) && top=0
    render_header "$COLS"
    buf="${ROW_AT}1${ROW_TXT}$RET"
    rule "$COLS"
    line="${C_D}$RET${C_0}"
    buf+="${ROW_AT}2${ROW_TXT}$line${ROW_AT}$(( ROWS - 2 ))${ROW_TXT}$line${ROW_AT}$(( ROWS - 1 ))${ROW_TXT}"
    for (( y = 0; y < h; y++ )); do
      i=$(( top + y ))
      buf+="${ROW_AT}$(( y + 3 ))${ROW_TXT}"
      (( i < n )) && buf+="  ${HELP[i]:0:$(( COLS - 2 > 0 ? COLS - 2 : 0 ))}"
    done
    if (( n > h )); then line="$(( top + 1 ))-$(( top + h < n ? top + h : n ))/$n"; else line=""; fi
    render_footer "$COLS" help "$line"
    buf+="${ROW_AT}${ROWS}${ROW_TXT}$RET"
    emit_frame "$buf"
    while ! read_key 0.5; do
      if (( RESIZED )); then RESIZED=0; term_size; screen_reset; h=$(( ROWS - 5 )); (( h < 1 )) && h=1; continue 2; fi
      (( INTR )) && break 2
    done
    case $KEY in
      up|k)   top=$(( top - 1 )) ;;
      down|j) top=$(( top + 1 )) ;;
      pgup)   top=$(( top - h )) ;;
      pgdn)   top=$(( top + h )) ;;
      *)      break ;;
    esac
  done
  T_CTX=$ctx
}

help_edit() {
  cat <<EOF
Usage: $PROG edit [OPTIONS] [FILE]

Change the colours of existing entries in a full-screen editor. Every entry
is shown with a sample name in its current colour. Colours are picked from a
palette and bold, dim, underline, reverse and blink are switched on and off;
nobody has to type a code.

Options:
  --256              offer the 256-colour palette in the picker
  --case-sensitive   list .deb and .DEB as two entries (key c switches)
  -n, --dry-run      review changes as usual, but never write
  --ascii            draw with ASCII characters only (the default when the
                     locale is not UTF-8)

Keys: arrows or h/j/k/l to move, Enter to edit, Space to fold a section,
z / Z to fold or unfold all, / to search, x to switch between colours in
words and codes, c for case pairs, u to undo, s to save, q to quit, ? for
the full list.

edit only changes entries that exist. Adding entries and reorganising the
file is the job of fix.
EOF
}

cmd_edit() {
  local page
  if [[ ! -t 0 || ! -t 1 ]]; then
    die "edit needs a terminal for input and output"
  fi
  load_config
  prepare_checks
  run_checks
  OPT_COLOUR=always
  setup_colour
  setup_glyphs
  build_entries
  if (( ! ${#E_LABEL[@]} )); then
    err "$FILE has no entries to edit. Add some with: $PROG fix"
    exit 1
  fi
  term_size
  build_groups
  # a file that does not fit on one screen starts as a list of its sections
  (( ${#E_LABEL[@]} + ${#G_TITLE[@]} > ROWS - 5 )) && T_FOLD_DEFAULT=1
  CUR_ID=""
  build_rows
  tui_start
  trap 'RESIZED=1' WINCH
  trap 'INTR=1' INT
  draw_screen
  while :; do
    # Ctrl-C, also when it came while the picker, a prompt or the help
    # was open, is handled like q
    if (( INTR )); then
      KEY=quit
    elif ! read_key 0.25; then
      if (( RESIZED )); then RESIZED=0; term_size; screen_reset; draw_screen; fi
      continue
    fi
    T_MSG=""
    page=$(( ROWS - 6 ))
    (( page < 1 )) && page=1
    case $KEY in
      up|k)    move_cursor -1 ;;
      down|j)  move_cursor 1 ;;
      pgup)    move_cursor "-$page" ;;
      pgdn)    move_cursor "$page" ;;
      home|g)  T_CUR=0; T_TOP=0; move_cursor 0 ;;
      end|G)   move_cursor "${#ROW_KIND[@]}" ;;
      enter)
        case ${ROW_KIND[T_CUR]:-} in
          e) open_picker "${ROW_REF[T_CUR]}" ;;
          h) toggle_fold ;;
        esac ;;
      l|right)
        # on a heading: unfold, then step into the group
        case ${ROW_KIND[T_CUR]:-} in
          e) open_picker "${ROW_REF[T_CUR]}" ;;
          h) if is_folded "${ROW_REF[T_CUR]}"; then toggle_fold; else move_cursor 1; fi ;;
        esac ;;
      h|left)
        # on a heading: fold; on an entry: back to its heading
        case ${ROW_KIND[T_CUR]:-} in
          e) cursor_group && CUR_ID="h:${G_TITLE[RET]}" && place_cursor ;;
          h) is_folded "${ROW_REF[T_CUR]}" || toggle_fold ;;
        esac ;;
      space)   toggle_fold ;;
      z)       cursor_group && CUR_ID="h:${G_TITLE[RET]}"; fold_all 1; build_rows ;;
      Z)       fold_all 0; build_rows ;;
      /)
        T_CTX=prompt
        draw_screen
        T_CTX=list
        if line_input " search: " "$T_FILTER"; then
          T_FILTER=$RET
          FOLD_F=() CUR_ID=""
          build_rows
          (( ${#ROW_KIND[@]} )) || T_MSG="No entry matches \"$T_FILTER\". Esc clears the filter."
        fi ;;
      esc)
        if [[ -n $T_FILTER ]]; then T_FILTER=""; build_rows; fi ;;
      c)
        if (( OPT_CASE )); then OPT_CASE=0; else OPT_CASE=1; fi
        build_entries
        CUR_ID=""
        build_rows ;;
      x) T_RAW=$(( ! T_RAW )) ;;
      u) undo_last ;;
      s) save_staged ;;
      \?) show_help ;;
      q|quit|eof)
        # q and Ctrl-C ask when there are unsaved changes; Ctrl-C once
        # more at the question quits
        INTR=0
        if (( ${#ST[@]} )) && [[ $KEY != eof ]]; then
          printf '%s' "${ESC}[$(( ROWS - 1 ));1H${ESC}[K ${C_Y}${#ST[@]} unsaved changes. Quit without saving? [y/N]${C_0} "
          unset "FRAME[$(( ROWS - 1 ))]"
          while ! read_key 0.5; do
            if (( INTR )); then KEY=y; break; fi
          done
          INTR=0
          [[ $KEY == y || $KEY == Y ]] && break
        else
          break
        fi ;;
    esac
    (( RESIZED )) && { RESIZED=0; term_size; screen_reset; }
    draw_screen
  done
  return 0
}

# ===== commands =====

# ---------------------------------------------------------------------------
# Command line
# ---------------------------------------------------------------------------

usage() {
  cat <<EOF
$PROG $VERSION - preview, check and edit a dircolors file

Usage: $PROG COMMAND [OPTIONS] [FILE]

Commands:
  preview   list one sample per entry with the real ls, then run check
  check     report problems in the file (exit status 1 when there are any)
  edit      change colours in a full-screen editor
  fix       walk through the problems found by check and repair them
  sample    print the built-in sample config
  help      show this help, or the help of a command: $PROG help edit

FILE defaults to the first that exists of:
  \$XDG_CONFIG_HOME/dircolors, \$XDG_CONFIG_HOME/.dir_colors,
  ~/.dir_colors, ~/.dircolors

Options for every command:
  --256               allow 256-colour codes (38;5;N and 48;5;N)
  --case-sensitive    treat .deb and .DEB as two separate entries
  --term NAME         judge TERM lines as if \$TERM were NAME
  --colour WHEN       colour the output: auto (default), always, never
  --no-colour         the same as --colour never
  -h, --help          show help
  -V, --version       show the version

Every option with "colour" in its name also accepts the spelling "color".
Each command has more options: $PROG help COMMAND
EOF
}

main() {
  local cmd="" arg
  local -a positional=()
  while (( $# )); do
    arg=$1
    shift
    case $arg in
      -h|--help)    positional+=("--help") ;;
      -V|--version) printf '%s %s\n' "$PROG" "$VERSION"; exit 0 ;;
      --256)        OPT_256=1 ;;
      --case-sensitive) OPT_CASE=1 ;;
      -n|--dry-run) OPT_DRY=1 ;;
      --ascii)      OPT_ASCII=1 ;;
      -k|--keep)    OPT_KEEP=1 ;;
      -c|--codes)   OPT_CODES=1 ;;
      --scan)       (( $# )) || die "--scan needs a directory"; OPT_SCAN=$1; shift ;;
      --scan=*)     OPT_SCAN=${arg#*=} ;;
      --term)       (( $# )) || die "--term needs a name"; OPT_TERM=$1; shift ;;
      --term=*)     OPT_TERM=${arg#*=} ;;
      --ignore)     (( $# )) || die "--ignore needs a list"; OPT_IGNORE=$1; shift ;;
      --ignore=*)   OPT_IGNORE=${arg#*=} ;;
      --colour|--color)
        (( $# )) || die "$arg needs auto, always or never"; OPT_COLOUR=$1; shift ;;
      --colour=*|--color=*) OPT_COLOUR=${arg#*=} ;;
      --no-colour|--no-color) OPT_COLOUR=never ;;
      --)           while (( $# )); do positional+=("$1"); shift; done ;;
      -?*)          die "unknown option: $arg (try $PROG --help)" ;;
      *)
        if [[ -z $cmd ]]; then cmd=$arg; else positional+=("$arg"); fi ;;
    esac
  done
  case $OPT_COLOUR in
    auto|always|never) ;;
    *) die "--colour takes auto, always or never" ;;
  esac
  setup_colour
  install_traps

  local want_help=0
  local -a files=()
  for arg in "${positional[@]}"; do
    if [[ $arg == --help ]]; then want_help=1; else files+=("$arg"); fi
  done
  if [[ $cmd == help ]]; then
    want_help=1 cmd=${files[0]:-}
    files=()
  fi
  if (( want_help )); then
    case $cmd in
      check) help_check ;;
      preview) help_preview ;;
      fix)   help_fix ;;
      edit)  help_edit ;;
      *)     usage ;;
    esac
    exit 0
  fi
  (( ${#files[@]} > 1 )) && die "only one file can be given"
  FILE=${files[0]:-}

  case $cmd in
    "")      usage; exit 2 ;;
    sample)  sample_config ;;
    check)   cmd_check ;;
    preview) cmd_preview ;;
    fix)     cmd_fix ;;
    edit)    cmd_edit ;;
    *)       die "unknown command: $cmd (try $PROG --help)" ;;
  esac
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
  main "$@"
fi
