# shellcheck shell=bash
# Notifications: a plain message model (title, body, level, project, host)
# delivered to any number of channels. Each provider lives in one file under
# lib/notify/ and defines three functions:
#
#   notify_<p>_help     2-3 lines: where to get the credentials
#   notify_<p>_fields   one "key|Label|secret(0/1)|default|opt" line per setting
#   notify_<p>_send CH  deliver N_TITLE / N_BODY / N_LEVEL; return 0 on success
#
# Secrets go to curl through stdin (--config -), never through argv.

NOTIFY_PROVIDERS=(telegram discord ntfy slack email webhook whatsapp)

declare -gA NCH=()
declare -ga NCH_NAMES=()
N_TITLE='' N_BODY='' N_LEVEL=info N_PROJECT='' N_HOST=''
NOTIFY_ERR=''

notify_conf_path() {
  if [ -n "$PROJECT_DIR" ] && [ -f "$PROJECT_DIR/.helpoupou/notify.conf" ]; then
    printf '%s' "$PROJECT_DIR/.helpoupou/notify.conf"
  else
    printf '%s' "$CONF_DIR/notify.conf"
  fi
}

# Format: [channel-name] sections holding key=value lines.
notify_load() {
  local file line sec=''
  local re_sec='^\[([A-Za-z0-9_-]+)\]$' re_kv='^([a-z_]+)=(.*)$'
  NCH=()
  NCH_NAMES=()
  file=$(notify_conf_path)
  [ -f "$file" ] || return 0
  while IFS= read -r line || [ -n "$line" ]; do
    line=${line%$'\r'}
    if [[ "$line" =~ $re_sec ]]; then
      sec=${BASH_REMATCH[1]}
      NCH_NAMES+=("$sec")
    elif [ -n "$sec" ] && [[ "$line" =~ $re_kv ]]; then
      NCH["$sec.${BASH_REMATCH[1]}"]=${BASH_REMATCH[2]}
    fi
  done <"$file"
}

nget() { printf '%s' "${NCH[$1.$2]:-${3:-}}"; }

_level_rank() {
  case "$1" in
    info | success) printf 0 ;;
    warning) printf 1 ;;
    critical) printf 2 ;;
    *) return 1 ;;
  esac
}

notify_icon() {
  case "$N_LEVEL" in
    success) printf '✅' ;;
    warning) printf '⚠️' ;;
    critical) printf '🔴' ;;
    *) printf 'ℹ️' ;;
  esac
}

notify_footer() { printf '%s' "${N_PROJECT:+$N_PROJECT @ }$N_HOST"; }

_nsleep() { [ "${HELPOUPOU_NO_SLEEP:-0}" = 1 ] || sleep "$1"; }

# notify_http URL PAYLOAD_FILE [curl-config-line...]
# One retry: after Retry-After on 429, after 2 s on a network error or 5xx.
notify_http() {
  local url=$1 payload=$2 attempt code wait out hdr l
  shift 2
  out=$(mktmp)
  hdr=$(mktmp)
  for attempt in 1 2; do
    code=$(
      {
        printf 'url = "%s"\n' "$(curlq "$url")"
        if [ -n "$payload" ]; then printf 'data-binary = "@%s"\n' "$(curlq "$payload")"; fi
        for l in "$@"; do printf '%s\n' "$l"; done
      } | curl -sS --max-time "${HELPOUPOU_HTTP_TIMEOUT:-15}" -o "$out" -D "$hdr" -w '%{http_code}' --config - 2>/dev/null
    ) || code=${code:-000}
    case "$code" in
      2??) return 0 ;;
      429)
        wait=$(awk 'tolower($1) == "retry-after:" { print int($2) }' "$hdr" 2>/dev/null | tail -1)
        [[ "$wait" =~ ^[0-9]+$ ]] || wait=2
        [ "$wait" -le 30 ] || wait=30
        ;;
      5?? | 000) wait=2 ;;
      *) break ;;
    esac
    [ "$attempt" = 1 ] && _nsleep "$wait"
  done
  NOTIFY_ERR="HTTP $code $(head -c 200 "$out" 2>/dev/null | tr -d '\n')"
  return 1
}

# Sends the current N_* message to one channel and records the outcome.
notify_send_channel() {
  local ch=$1 provider rc=0
  provider=$(nget "$ch" provider)
  NOTIFY_ERR=''
  if declare -F "notify_${provider}_send" >/dev/null; then
    "notify_${provider}_send" "$ch" || rc=1
  else
    NOTIFY_ERR="unknown provider '$provider'"
    rc=1
  fi
  mkdir -p "$STATE_DIR/notify"
  if [ "$rc" = 0 ]; then
    printf '%s ok\n' "$(date +%s)" >"$STATE_DIR/notify/$ch"
  else
    printf '%s fail\n' "$(date +%s)" >"$STATE_DIR/notify/$ch"
    warn "notification channel '$ch' failed: $NOTIFY_ERR"
  fi
  return "$rc"
}

_notify_message() {
  N_LEVEL=$1 N_TITLE=$2 N_BODY=$3
  N_PROJECT=${CFG[PROJECT_NAME]:-}
  N_HOST=$(uname -n)
}

# notify_dispatch LEVEL TITLE BODY
# 0 = delivered everywhere, 1 = at least one channel failed, 2 = no channel
# took the message. A failing channel never stops the others. Callers that
# only want to alert should use: notify_dispatch ... || true
notify_dispatch() {
  local ch rank min rc=0 sent=0
  rank=$(_level_rank "$1") || die "invalid level '$1' (info, success, warning, critical)"
  _notify_message "$1" "$2" "${3:-}"
  notify_load
  for ch in "${NCH_NAMES[@]+"${NCH_NAMES[@]}"}"; do
    min=$(_level_rank "$(nget "$ch" min_level info)" || printf 0)
    [ "$rank" -ge "$min" ] || continue
    sent=$((sent + 1))
    notify_send_channel "$ch" || rc=1
  done
  [ "$sent" -gt 0 ] || return 2
  return "$rc"
}

# ---- config file ------------------------------------------------------------

_notify_remove_section() {
  local file=$1 name=$2 tmp
  [ -f "$file" ] || return 0
  tmp=$(mktemp "${file}.XXXXXX")
  chmod 600 "$tmp"
  awk -v s="[$name]" '
    /^\[/ { skip = ($0 == s) }
    !skip { print }
  ' "$file" >"$tmp"
  mv "$tmp" "$file"
}

_notify_save() {
  local file=$1 name=$2 provider key _rest
  provider=$(nget "$name" provider)
  mkdir -p "$(dirname "$file")"
  _notify_remove_section "$file" "$name"
  (
    umask 077
    {
      printf '[%s]\nprovider=%s\nmin_level=%s\n' "$name" "$provider" "$(nget "$name" min_level info)"
      while IFS='|' read -r key _rest; do
        if [ -n "$(nget "$name" "$key")" ]; then printf '%s=%s\n' "$key" "$(nget "$name" "$key")"; fi
      done < <("notify_${provider}_fields")
    } >>"$file"
  )
  chmod 600 "$file"
}

# ---- commands ---------------------------------------------------------------

notify_setup() {
  local provider='' name='' min='' notest=0 project=0 file
  local key label secret def opt val envname keep i
  local -a labels=()
  while [ $# -gt 0 ]; do
    case "$1" in
      --provider) provider=${2:-} && shift 2 ;;
      --name) name=${2:-} && shift 2 ;;
      --min-level) min=${2:-} && shift 2 ;;
      --no-test) notest=1 && shift ;;
      --project) project=1 && shift ;;
      *) die "unknown option for notify setup: $1" ;;
    esac
  done

  if [ -z "$provider" ]; then
    for i in "${NOTIFY_PROVIDERS[@]}"; do labels+=("$("notify_${i}_label")"); done
    ui_select "Which service should receive the notifications?" "${labels[@]}" || return 0
    provider=${NOTIFY_PROVIDERS[$UI_CHOICE]}
  fi
  declare -F "notify_${provider}_send" >/dev/null ||
    die "unknown provider '$provider' (available: ${NOTIFY_PROVIDERS[*]})"

  printf '\n'
  "notify_${provider}_help" | sed 's/^/  /'
  printf '\n'
  [ -n "$name" ] || ask name "Name for this channel" "$provider"
  [[ "$name" =~ ^[A-Za-z0-9_-]+$ ]] || die "channel name '$name' is invalid (letters, digits, _ and - only)"

  notify_load
  NCH["$name.provider"]=$provider
  while IFS='|' read -r key label secret def opt <&3; do
    envname="HELPOUPOU_NOTIFY_${key^^}"
    if [ -n "${!envname:-}" ]; then
      val=${!envname}
    elif [ "$secret" = 1 ]; then
      ask_secret val "$label" "Set $envname to provide it without a terminal"
    else
      ask val "$label${opt:+ (optional)}" "$def" "Set $envname to provide it without a terminal"
    fi
    [[ "$val" != *$'\n'* ]] || die "$label must be a single line"
    [ -n "$val" ] || [ "$opt" = opt ] || die "$label is required"
    NCH["$name.$key"]=$val
  done 3< <("notify_${provider}_fields")

  [ -n "$min" ] || ask min "Minimum level sent to this channel (info, warning, critical)" info
  _level_rank "$min" >/dev/null || die "invalid level '$min' (info, success, warning, critical)"
  NCH["$name.min_level"]=$min

  if [ "$notest" = 0 ]; then
    _notify_message success "helpoupou test" "This channel works. You will receive alerts here."
    if notify_send_channel "$name"; then
      ok "test message sent: check that you received it"
    else
      ask_yn keep "The test failed. Save this channel anyway?" n
      [ "$keep" = y ] || die "channel not saved"
    fi
  fi

  if [ "$project" = 1 ]; then
    [ -n "$PROJECT_DIR" ] || die "--project needs to run inside a project"
    file="$PROJECT_DIR/.helpoupou/notify.conf"
  else
    machine_dirs
    file="$CONF_DIR/notify.conf"
  fi
  _notify_save "$file" "$name"
  ok "channel '$name' saved in $file"
}

_mask() {
  local v=$1
  if [ "${#v}" -gt 8 ]; then printf '****%s' "${v: -4}"; else printf '****'; fi
}

notify_list() {
  local ch provider key label secret _rest val state
  notify_load
  if [ "${#NCH_NAMES[@]}" -eq 0 ]; then
    note "no notification channel yet (add one with: helpoupou notify setup)"
    return 0
  fi
  for ch in "${NCH_NAMES[@]}"; do
    provider=$(nget "$ch" provider)
    state=$(cat "$STATE_DIR/notify/$ch" 2>/dev/null || true)
    printf '%s%s%s  provider=%s  min_level=%s  last=%s\n' "$C_BOLD" "$ch" "$C_OFF" \
      "$provider" "$(nget "$ch" min_level info)" "${state##* }"
    declare -F "notify_${provider}_fields" >/dev/null || continue
    while IFS='|' read -r key label secret _rest; do
      val=$(nget "$ch" "$key")
      [ -n "$val" ] || continue
      if [ "$secret" = 1 ]; then val=$(_mask "$val"); fi
      printf '    %-12s %s\n' "$key" "$val"
    done < <("notify_${provider}_fields")
  done
}

notify_test() {
  local ch rc=0 found=0
  notify_load
  [ "${#NCH_NAMES[@]}" -gt 0 ] || die "no notification channel configured (run: helpoupou notify setup)"
  _notify_message success "helpoupou test" "This channel works. You will receive alerts here."
  for ch in "${NCH_NAMES[@]}"; do
    [ -z "${1:-}" ] || [ "$ch" = "$1" ] || continue
    found=1
    if notify_send_channel "$ch"; then ok "$ch: sent"; else rc=1; fi
  done
  [ "$found" = 1 ] || die "no channel named '$1'"
  return "$rc"
}

notify_send_cli() {
  local level=info title='' body='' rc=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --level) level=${2:-} && shift 2 ;;
      --title) title=${2:-} && shift 2 ;;
      --body) body=${2:-} && shift 2 ;;
      *) die "unknown option for notify send: $1" ;;
    esac
  done
  [ -n "$title" ] || die "notify send needs --title"
  if [ "$body" = - ]; then body=$(cat); fi
  notify_dispatch "$level" "$title" "$body" || rc=$?
  case "$rc" in
    0) ok "sent" ;;
    2) die "nothing sent: no channel is configured for level '$level'" ;;
    *) die "at least one channel failed" ;;
  esac
}

cmd_notify() {
  local sub=${1:-list}
  [ $# -gt 0 ] && shift
  case "$sub" in
    setup) notify_setup "$@" ;;
    list) notify_list ;;
    test) notify_test "$@" ;;
    send) notify_send_cli "$@" ;;
    remove)
      [ -n "${1:-}" ] || die "usage: helpoupou notify remove NAME"
      _notify_remove_section "$(notify_conf_path)" "$1"
      rm -f "$STATE_DIR/notify/$1"
      ok "channel '$1' removed"
      ;;
    *) die "unknown: notify $sub (setup, list, test, send, remove)" ;;
  esac
}
