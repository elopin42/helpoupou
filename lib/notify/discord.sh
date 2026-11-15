# shellcheck shell=bash
# Discord incoming webhook.

notify_discord_label() { printf 'Discord (webhook)'; }

notify_discord_help() {
  cat <<'EOF'
Discord: in your server, open the channel settings > Integrations > Webhooks,
create a webhook and copy its URL. Anyone holding that URL can post there.
EOF
}

notify_discord_fields() {
  printf '%s\n' 'url|Webhook URL|1||'
}

notify_discord_send() {
  local ch=$1 color payload
  case "$N_LEVEL" in
    success) color=3066993 ;;
    warning) color=15105570 ;;
    critical) color=15158332 ;;
    *) color=3447003 ;;
  esac
  payload=$(mktmp)
  # Embed limits: title 256, description 4096.
  printf '{"embeds":[{"title":"%s","description":"%s","color":%s,"footer":{"text":"%s"}}]}' \
    "$(json_escape "${N_TITLE:0:250}")" "$(json_escape "${N_BODY:0:4000}")" "$color" \
    "$(json_escape "$(notify_footer)")" >"$payload"
  notify_http "$(nget "$ch" url)" "$payload" 'header = "Content-Type: application/json"'
}
