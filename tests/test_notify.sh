# shellcheck shell=bash
# Notifications: endpoints, escaping, secrets out of argv, routing, retries.

NASTY='say "hi" <b> & co \ back
second line'

_channel() { # name provider min_level key=value...
  local name=$1 provider=$2 min=$3 kv
  shift 3
  mkdir -p "$XDG_CONFIG_HOME/helpoupou"
  {
    printf '[%s]\nprovider=%s\nmin_level=%s\n' "$name" "$provider" "$min"
    for kv in "$@"; do printf '%s\n' "$kv"; done
  } >>"$XDG_CONFIG_HOME/helpoupou/notify.conf"
}

_send() { run "$HP" notify send --level "${1:-info}" --title 'Disk "full" <now>' --body "$NASTY"; }

# Every secret must reach curl through stdin, never through its arguments.
_assert_secret_not_in_argv() {
  assert_file_lacks "$STUB_DIR/curl.argv" "$1"
  assert_file_has "$STUB_DIR/curl.stdin" "$1"
  assert_file_has "$STUB_DIR/curl.argv" '--config -'
}

test_telegram() {
  _channel tg telegram info token=SECRET-TG-TOKEN chat_id=4242
  _send
  assert_rc 0
  assert_file_has "$STUB_DIR/curl.stdin" 'url = "https://api.telegram.org/botSECRET-TG-TOKEN/sendMessage"'
  _assert_secret_not_in_argv SECRET-TG-TOKEN
  assert_file_has "$STUB_DIR/curl.payload" '"chat_id":"4242"'
  assert_file_has "$STUB_DIR/curl.payload" '<b>Disk \"full\" &lt;now&gt;</b>'
  assert_file_has "$STUB_DIR/curl.payload" 'say \"hi\" &lt;b&gt; &amp; co \\ back\nsecond line'
  assert_file_has "$STUB_DIR/curl.payload" 'myapp @ '
  assert_eq "$(wc -l <"$STUB_DIR/curl.payload")" 1
}

test_discord() {
  _channel dc discord info url=https://discord.example/api/webhooks/SECRET-HOOK
  _send critical
  assert_rc 0
  _assert_secret_not_in_argv SECRET-HOOK
  assert_file_has "$STUB_DIR/curl.payload" '"title":"Disk \"full\" <now>"'
  assert_file_has "$STUB_DIR/curl.payload" '"description":"say \"hi\" <b> & co \\ back\nsecond line"'
  assert_file_has "$STUB_DIR/curl.payload" '"color":15158332'
}

test_ntfy_with_token_and_priority() {
  _channel push ntfy info server=https://ntfy.example/ topic=SECRET-TOPIC token=SECRET-NTFY
  _send warning
  assert_rc 0
  assert_file_has "$STUB_DIR/curl.stdin" 'url = "https://ntfy.example/"'
  assert_file_has "$STUB_DIR/curl.stdin" 'Authorization: Bearer SECRET-NTFY'
  _assert_secret_not_in_argv SECRET-NTFY
  assert_file_lacks "$STUB_DIR/curl.argv" SECRET-TOPIC
  assert_file_has "$STUB_DIR/curl.payload" '"topic":"SECRET-TOPIC"'
  assert_file_has "$STUB_DIR/curl.payload" '"priority":4'
  assert_file_has "$STUB_DIR/curl.payload" 'say \"hi\" <b> & co \\ back\nsecond line'
}

test_slack() {
  _channel sl slack info url=https://hooks.slack.example/services/SECRET-SLACK
  _send
  assert_rc 0
  _assert_secret_not_in_argv SECRET-SLACK
  assert_file_has "$STUB_DIR/curl.payload" '*Disk \"full\" &lt;now&gt;*'
  assert_file_has "$STUB_DIR/curl.payload" '&lt;b&gt; &amp; co \\ back\nsecond line'
}

test_webhook() {
  _channel wh webhook info url=https://hooks.example/in token=SECRET-BEARER
  _send success
  assert_rc 0
  _assert_secret_not_in_argv SECRET-BEARER
  assert_file_has "$STUB_DIR/curl.payload" '"title":"Disk \"full\" <now>","body":"say \"hi\" <b> & co \\ back\nsecond line","level":"success","project":"myapp"'
}

test_whatsapp_free_text() {
  _channel wa whatsapp info phone_id=111222 token=SECRET-WA to='+33 6 00 00 00 00'
  _send
  assert_rc 0
  assert_file_has "$STUB_DIR/curl.stdin" 'url = "https://graph.facebook.com/v21.0/111222/messages"'
  _assert_secret_not_in_argv SECRET-WA
  assert_file_has "$STUB_DIR/curl.payload" '"to":"33600000000","type":"text"'
  assert_file_has "$STUB_DIR/curl.payload" 'say \"hi\" <b> & co \\ back\nsecond line'
}

test_whatsapp_template_parameters_are_single_line() {
  _channel wa whatsapp info phone_id=111222 token=SECRET-WA to=33600000000 template=server_alert template_lang=fr
  _send
  assert_rc 0
  assert_file_has "$STUB_DIR/curl.payload" '"type":"template","template":{"name":"server_alert","language":{"code":"fr"}'
  assert_file_has "$STUB_DIR/curl.payload" 'co \\ back | second line'
  assert_file_lacks "$STUB_DIR/curl.payload" '\n'
}

test_email() {
  _channel mail email info host=smtp.example.com port=587 user=bot@example.com password=SECRET-SMTP from=bot@example.com to=me@example.com
  _send
  assert_rc 0
  assert_file_has "$STUB_DIR/curl.stdin" 'url = "smtp://smtp.example.com:587"'
  assert_file_has "$STUB_DIR/curl.stdin" 'ssl-reqd'
  assert_file_has "$STUB_DIR/curl.stdin" 'mail-rcpt = "me@example.com"'
  _assert_secret_not_in_argv SECRET-SMTP
  assert_file_has "$STUB_DIR/curl.payload" 'Subject: =?UTF-8?B?'
  assert_file_has "$STUB_DIR/curl.payload" 'say "hi" <b> & co \ back'
}

test_email_port_465_uses_implicit_tls() {
  _channel mail email info host=smtp.example.com port=465 from=bot@example.com to=me@example.com
  _send
  assert_rc 0
  assert_file_has "$STUB_DIR/curl.stdin" 'url = "smtps://smtp.example.com:465"'
  assert_file_lacks "$STUB_DIR/curl.stdin" 'ssl-reqd'
}

test_minimum_level_routes_messages() {
  _channel all ntfy info topic=topic-all
  _channel urgent telegram critical token=tok chat_id=1
  _send warning
  assert_rc 0
  assert_eq "$(wc -l <"$STUB_DIR/curl.argv")" 1
  assert_file_has "$STUB_DIR/curl.payload" 'topic-all'
  _send critical
  assert_eq "$(wc -l <"$STUB_DIR/curl.argv")" 3
}

test_one_failing_channel_does_not_stop_the_others() {
  _channel first telegram info token=BROKEN chat_id=1
  _channel second ntfy info topic=topic-ok
  echo BROKEN >"$STUB_DIR/curl.fail-match"
  _send
  assert_fails
  assert_out "channel 'first' failed: HTTP 400"
  assert_file_has "$STUB_DIR/curl.payload" 'topic-ok'
  assert_file_has "$XDG_STATE_HOME/helpoupou/notify/first" ' fail'
  assert_file_has "$XDG_STATE_HOME/helpoupou/notify/second" ' ok'
}

test_rate_limit_is_retried_once() {
  _channel push ntfy info topic=t
  printf '429\n200\n' >"$STUB_DIR/curl.codes"
  _send
  assert_rc 0
  assert_eq "$(wc -l <"$STUB_DIR/curl.argv")" 2
}

test_server_error_is_retried_once_then_reported() {
  _channel push ntfy info topic=t
  printf '500\n500\n200\n' >"$STUB_DIR/curl.codes"
  _send
  assert_fails
  assert_eq "$(wc -l <"$STUB_DIR/curl.argv")" 2
}

test_client_error_is_not_retried() {
  _channel push ntfy info topic=t
  printf '403\n200\n' >"$STUB_DIR/curl.codes"
  _send
  assert_fails
  assert_eq "$(wc -l <"$STUB_DIR/curl.argv")" 1
}

test_send_without_channel_says_so() {
  _send
  assert_fails
  assert_out 'no channel is configured'
}

test_setup_saves_after_a_successful_test_and_masks_secrets() {
  run_in 'alerts\nSECRET-TG-TOKEN-123\n4242\n2\n' "$HP" notify setup --provider telegram
  assert_rc 0
  assert_out 'test message sent'
  local conf="$XDG_CONFIG_HOME/helpoupou/notify.conf"
  assert_eq "$(stat -c %a "$conf")" 600
  assert_file_has "$conf" '[alerts]'
  assert_file_has "$conf" 'token=SECRET-TG-TOKEN-123'
  assert_file_has "$conf" 'min_level=warning'
  assert_no_out 'SECRET-TG-TOKEN-123'
  run "$HP" notify list
  assert_out 'alerts'
  assert_out '****-123'
  assert_no_out 'SECRET-TG-TOKEN-123'
}

test_setup_does_not_save_when_the_test_fails() {
  echo BADTOKEN >"$STUB_DIR/curl.fail-match"
  run_in 'alerts\nBADTOKEN\n4242\n1\nn\n' "$HP" notify setup --provider telegram
  assert_fails
  assert_out 'channel not saved'
  [ ! -f "$XDG_CONFIG_HOME/helpoupou/notify.conf" ] || _fail "channel was saved"
}

test_setup_without_terminal_reads_the_environment() {
  HELPOUPOU_NOTIFY_URL=https://discord.example/hook run "$HP" --yes notify setup --provider discord --name ops
  assert_rc 0
  assert_file_has "$XDG_CONFIG_HOME/helpoupou/notify.conf" '[ops]'
  run "$HP" notify setup --provider discord --name ops2
  assert_fails
  assert_out 'HELPOUPOU_NOTIFY_URL'
}

test_setup_replaces_a_channel_of_the_same_name_and_remove_deletes_it() {
  _channel ops discord info url=https://discord.example/old
  HELPOUPOU_NOTIFY_URL=https://discord.example/new run "$HP" --yes notify setup --provider discord --name ops
  assert_rc 0
  assert_eq "$(grep -c '^\[ops\]$' "$XDG_CONFIG_HOME/helpoupou/notify.conf")" 1
  assert_file_lacks "$XDG_CONFIG_HOME/helpoupou/notify.conf" 'old'
  run "$HP" notify remove ops
  assert_file_lacks "$XDG_CONFIG_HOME/helpoupou/notify.conf" '[ops]'
}

test_project_channels_override_machine_channels() {
  _channel machine ntfy info topic=machine-topic
  mkdir -p .helpoupou
  printf '[proj]\nprovider=ntfy\nmin_level=info\ntopic=project-topic\n' >.helpoupou/notify.conf
  _send
  assert_rc 0
  assert_file_has "$STUB_DIR/curl.payload" 'project-topic'
  assert_file_lacks "$STUB_DIR/curl.payload" 'machine-topic'
}

test_doctor_reports_a_silent_channel_in_prod() {
  _channel first telegram info token=BROKEN chat_id=1
  echo BROKEN >"$STUB_DIR/curl.fail-match"
  _send
  HELPOUPOU_MODE=prod run "$HP" doctor
  assert_out "notification channel 'first': the last delivery FAILED"
}
