# shellcheck shell=bash
# Generic JSON webhook: the escape hatch for any service not listed here.

notify_webhook_label() { printf 'Generic webhook (JSON POST to any URL)'; }

notify_webhook_help() {
  cat <<'EOF'
Webhook: helpoupou sends a JSON POST with the fields title, body, level,
project, host and timestamp. Works with any automation tool that accepts one.
EOF
}

notify_webhook_fields() {
  printf '%s\n' 'url|URL|1||' 'token|Bearer token|1||opt'
}

notify_webhook_send() {
  local ch=$1 payload token
  local -a extra=('header = "Content-Type: application/json"')
  payload=$(mktmp)
  printf '{"title":"%s","body":"%s","level":"%s","project":"%s","host":"%s","timestamp":%s}' \
    "$(json_escape "$N_TITLE")" "$(json_escape "$N_BODY")" "$N_LEVEL" \
    "$(json_escape "$N_PROJECT")" "$(json_escape "$N_HOST")" "$(date +%s)" >"$payload"
  token=$(nget "$ch" token)
  if [ -n "$token" ]; then extra+=("header = \"Authorization: Bearer $(curlq "$token")\""); fi
  notify_http "$(nget "$ch" url)" "$payload" "${extra[@]}"
}
