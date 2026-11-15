# shellcheck shell=bash
# ntfy (ntfy.sh or a self-hosted server), JSON publishing.

notify_ntfy_label() { printf 'ntfy (push to your phone, no account needed)'; }

notify_ntfy_help() {
  cat <<'EOF'
ntfy: install the ntfy app and subscribe to a topic. On the public server the
topic name is the only protection, so pick a long random one. A self-hosted
server can also require an access token.
EOF
}

notify_ntfy_fields() {
  printf '%s\n' \
    'server|Server URL|0|https://ntfy.sh|' \
    'topic|Topic|1||' \
    'token|Access token|1||opt'
}

notify_ntfy_send() {
  local ch=$1 prio tag payload token server
  local -a extra=('header = "Content-Type: application/json"')
  case "$N_LEVEL" in
    success) prio=3 tag=white_check_mark ;;
    warning) prio=4 tag=warning ;;
    critical) prio=5 tag=rotating_light ;;
    *) prio=3 tag=information_source ;;
  esac
  payload=$(mktmp)
  printf '{"topic":"%s","title":"%s","message":"%s","priority":%s,"tags":["%s"]}' \
    "$(json_escape "$(nget "$ch" topic)")" "$(json_escape "$N_TITLE")" \
    "$(json_escape "${N_BODY:-$N_TITLE}"$'\n'"$(notify_footer)")" "$prio" "$tag" >"$payload"
  token=$(nget "$ch" token)
  if [ -n "$token" ]; then extra+=("header = \"Authorization: Bearer $(curlq "$token")\""); fi
  server=$(nget "$ch" server https://ntfy.sh)
  notify_http "${server%/}/" "$payload" "${extra[@]}"
}
