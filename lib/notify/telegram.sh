# shellcheck shell=bash
# Telegram Bot API.

notify_telegram_label() { printf 'Telegram (bot)'; }

notify_telegram_help() {
  cat <<'EOF'
Telegram: talk to @BotFather, send /newbot and copy the token it gives you.
Then write any message to your new bot and open
https://api.telegram.org/bot<TOKEN>/getUpdates to read your chat id.
EOF
}

notify_telegram_fields() {
  printf '%s\n' 'token|Bot token|1||' 'chat_id|Chat id|0||'
}

notify_telegram_send() {
  local ch=$1 text payload
  text="$(notify_icon) <b>$(html_escape "$N_TITLE")</b>"
  # Telegram refuses messages over 4096 characters.
  if [ -n "$N_BODY" ]; then text+=$'\n'"$(html_escape "${N_BODY:0:3500}")"; fi
  text+=$'\n'"<i>$(html_escape "$(notify_footer)")</i>"
  payload=$(mktmp)
  printf '{"chat_id":"%s","parse_mode":"HTML","disable_web_page_preview":true,"text":"%s"}' \
    "$(json_escape "$(nget "$ch" chat_id)")" "$(json_escape "$text")" >"$payload"
  notify_http "https://api.telegram.org/bot$(nget "$ch" token)/sendMessage" "$payload" \
    'header = "Content-Type: application/json"'
}
