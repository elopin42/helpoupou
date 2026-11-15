# shellcheck shell=bash
# E-mail over SMTP, sent by curl.

notify_email_label() { printf 'E-mail (SMTP)'; }

notify_email_help() {
  cat <<'EOF'
E-mail: use the SMTP settings of your mail provider. Port 587 uses STARTTLS,
port 465 uses TLS from the start. Many providers require an app password.
EOF
}

notify_email_fields() {
  printf '%s\n' \
    'host|SMTP server|0||' \
    'port|Port (587 or 465)|0|587|' \
    'user|SMTP user|0||opt' \
    'password|SMTP password|1||opt' \
    'from|From address|0||' \
    'to|To address|0||'
}

notify_email_send() {
  local ch=$1 msg host port user from to scheme=smtp
  local -a extra=()
  host=$(nget "$ch" host)
  port=$(nget "$ch" port 587)
  user=$(nget "$ch" user)
  from=$(nget "$ch" from)
  to=$(nget "$ch" to)
  msg=$(mktmp)
  {
    printf 'From: %s\nTo: %s\n' "$from" "$to"
    printf 'Subject: =?UTF-8?B?%s?=\n' "$(printf '%s' "$(notify_icon) $N_TITLE" | base64 -w0)"
    printf 'Date: %s\nMIME-Version: 1.0\n' "$(date -R)"
    printf 'Content-Type: text/plain; charset=UTF-8\nContent-Transfer-Encoding: 8bit\n\n'
    printf '%s\n\n-- \n%s\n' "${N_BODY:-$N_TITLE}" "$(notify_footer)"
  } >"$msg"
  if [ "$port" = 465 ]; then scheme=smtps; else extra+=('ssl-reqd'); fi
  extra+=(
    "upload-file = \"$(curlq "$msg")\""
    "mail-from = \"$(curlq "$from")\""
    "mail-rcpt = \"$(curlq "$to")\""
    'crlf'
  )
  if [ -n "$user" ]; then extra+=("user = \"$(curlq "$user:$(nget "$ch" password)")\""); fi
  notify_http "$scheme://$host:$port" '' "${extra[@]}"
}
