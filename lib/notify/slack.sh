# shellcheck shell=bash
# Slack incoming webhook.

notify_slack_label() { printf 'Slack (webhook)'; }

notify_slack_help() {
  cat <<'EOF'
Slack: create an app at api.slack.com/apps, enable "Incoming Webhooks", add a
webhook to the channel you want and copy its URL.
EOF
}

notify_slack_fields() {
  printf '%s\n' 'url|Webhook URL|1||'
}

notify_slack_send() {
  local ch=$1 text payload
  # Slack's own escaping rules: only & < > are special.
  text="$(notify_icon) *$(html_escape "$N_TITLE")*"
  if [ -n "$N_BODY" ]; then text+=$'\n'"$(html_escape "${N_BODY:0:3500}")"; fi
  text+=$'\n'"_$(html_escape "$(notify_footer)")_"
  payload=$(mktmp)
  printf '{"text":"%s"}' "$(json_escape "$text")" >"$payload"
  notify_http "$(nget "$ch" url)" "$payload" 'header = "Content-Type: application/json"'
}
