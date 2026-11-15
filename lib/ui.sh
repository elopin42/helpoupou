# shellcheck shell=bash
# Terminal output, prompts, the menu selector and small shared helpers.

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ] && [ "${TERM:-dumb}" != "dumb" ]; then
  C_BOLD=$'\e[1m' C_DIM=$'\e[2m' C_GRN=$'\e[32m' C_RED=$'\e[31m'
  C_YEL=$'\e[33m' C_CYA=$'\e[36m' C_OFF=$'\e[0m'
else
  C_BOLD='' C_DIM='' C_GRN='' C_RED='' C_YEL='' C_CYA='' C_OFF=''
fi

h1() { printf '\n%s== %s ==%s\n' "$C_BOLD" "$*" "$C_OFF"; }
ok() { printf '  %s✔%s %s\n' "$C_GRN" "$C_OFF" "$*"; }
warn() { printf '  %s⚠%s %s\n' "$C_YEL" "$C_OFF" "$*" >&2; }
fail() { printf '  %s✗%s %s\n' "$C_RED" "$C_OFF" "$*" >&2; }
note() { printf '  %s%s%s\n' "$C_DIM" "$*" "$C_OFF"; }
die() {
  printf '%s✗ %s%s\n' "$C_RED" "$*" "$C_OFF" >&2
  exit 1
}

# ---- temp files: one private directory per run, removed on exit ------------

tmp_init() {
  HELPOUPOU_TMP=$(mktemp -d)
  chmod 700 "$HELPOUPOU_TMP"
  trap 'rm -rf "$HELPOUPOU_TMP"' EXIT
}
mktmp() { mktemp -p "$HELPOUPOU_TMP"; }

# ---- prompts ----------------------------------------------------------------
# No terminal means no question: commands fail with a message naming what is
# missing instead of hanging. HELPOUPOU_ASSUME_TTY=1 lets tests feed stdin.

have_tty() {
  [ "${HELPOUPOU_ASSUME_TTY:-0}" = 1 ] || { [ -t 0 ] && [ -t 1 ]; }
}

need_tty() {
  have_tty || die "input required: $1 (no terminal attached)${2:+. $2}"
}

# ask VAR "question" [default] [hint shown when there is no terminal]
ask() {
  local __var=$1 __q=$2 __def=${3:-} __in=''
  if [ "$HELPOUPOU_YES" = 1 ]; then
    printf -v "$__var" '%s' "$__def"
    return 0
  fi
  need_tty "$__q" "${4:-}"
  if [ -n "$__def" ]; then
    printf '  %s [%s]: ' "$__q" "$__def" >&2
  else
    printf '  %s: ' "$__q" >&2
  fi
  IFS= read -r __in || true
  printf -v "$__var" '%s' "${__in:-$__def}"
}

# ask_secret VAR "question" [hint]: hidden input, never defaulted.
ask_secret() {
  local __var=$1 __q=$2 __in=''
  need_tty "$__q" "${3:-}"
  printf '  %s (hidden): ' "$__q" >&2
  IFS= read -rs __in || true
  printf '\n' >&2
  printf -v "$__var" '%s' "$__in"
}

# ask_yn VAR "question" [y|n]: sets VAR to y or n.
ask_yn() {
  local __var=$1 __q=$2 __def=${3:-y} __in='' __label
  if [ "$HELPOUPOU_YES" = 1 ]; then
    printf -v "$__var" '%s' "$__def"
    return 0
  fi
  need_tty "$__q"
  if [ "$__def" = y ]; then __label='Y/n'; else __label='y/N'; fi
  while :; do
    printf '  %s [%s]: ' "$__q" "$__label" >&2
    if [ -t 0 ]; then
      # One key press, no Enter needed.
      IFS= read -rsn1 __in || __in=$__def
      printf '%s\n' "$__in" >&2
    else
      IFS= read -r __in || __in=$__def
    fi
    case "${__in:-$__def}" in
      [Yy]*)
        printf -v "$__var" y
        return 0
        ;;
      [Nn]*)
        printf -v "$__var" n
        return 0
        ;;
    esac
  done
}

# ui_select "title" item...: sets UI_CHOICE (0-based). Returns 1 when the user
# quits. Arrow keys on a real terminal, numbered list otherwise.
ui_select() {
  local title=$1
  shift
  local -a items=("$@")
  local n=${#items[@]} cur=0 key rest i
  UI_CHOICE=-1
  need_tty "$title"
  printf '\n%s%s%s\n' "$C_BOLD" "$title" "$C_OFF"

  if ! { [ -t 0 ] && [ -t 1 ]; } || [ "${TERM:-dumb}" = dumb ] || [ "${HELPOUPOU_PLAIN_MENU:-0}" = 1 ]; then
    for i in "${!items[@]}"; do printf '  %2d) %s\n' "$((i + 1))" "${items[$i]}"; done
    while :; do
      printf '  Choice (q to quit): ' >&2
      IFS= read -r key || return 1
      case "$key" in
        q | Q | '') return 1 ;;
      esac
      if [[ "$key" =~ ^[0-9]+$ ]] && [ "$key" -ge 1 ] && [ "$key" -le "$n" ]; then
        UI_CHOICE=$((key - 1))
        return 0
      fi
    done
  fi

  note "arrows or j/k to move, Enter to choose, q to quit"
  while :; do
    for i in "${!items[@]}"; do
      if [ "$i" = "$cur" ]; then
        printf '\r\e[K %s❯ %s%s\n' "$C_CYA" "${items[$i]}" "$C_OFF"
      else
        printf '\r\e[K   %s\n' "${items[$i]}"
      fi
    done
    IFS= read -rsn1 key || return 1
    case "$key" in
      $'\e')
        rest=''
        IFS= read -rsn2 -t 0.05 rest || true
        case "$rest" in
          '[A') cur=$(((cur - 1 + n) % n)) ;;
          '[B') cur=$(((cur + 1) % n)) ;;
          '') return 1 ;;
        esac
        ;;
      k) cur=$(((cur - 1 + n) % n)) ;;
      j) cur=$(((cur + 1) % n)) ;;
      q | Q) return 1 ;;
      '') break ;;
    esac
    printf '\e[%dA' "$n"
  done
  UI_CHOICE=$cur
}

# ---- string helpers ---------------------------------------------------------

json_escape() {
  local s=$1
  s=${s//\\/\\\\}
  s=${s//\"/\\\"}
  s=${s//$'\n'/\\n}
  s=${s//$'\r'/\\r}
  s=${s//$'\t'/\\t}
  printf '%s' "$s" | tr -d '\000-\037'
}

html_escape() {
  local s=$1
  # Quoted replacements: bash >= 5.2 treats a bare & as "the matched text".
  s=${s//&/"&amp;"}
  s=${s//</"&lt;"}
  s=${s//>/"&gt;"}
  printf '%s' "$s"
}

# Value quoted for a curl config file (read with `curl --config -`).
curlq() {
  local s=$1
  s=${s//\\/\\\\}
  s=${s//\"/\\\"}
  printf '%s' "$s"
}

# 536870912, 512m, 1g, 300M ... -> megabytes (integer). Empty on garbage.
to_mb() {
  local v=${1,,}
  v=${v%b}
  case "$v" in
    *[!0-9kmg]* | '') return 0 ;;
    *k) printf '%d' $((${v%k} / 1024)) ;;
    *m) printf '%d' "${v%m}" ;;
    *g) printf '%d' $((${v%g} * 1024)) ;;
    *) printf '%d' $((v / 1048576)) ;;
  esac
}
