# shellcheck shell=bash
# WhatsApp through the Meta WhatsApp Cloud API.
#
# Constraint to know before choosing it: free-form text is only delivered
# within 24 hours after the recipient last wrote to the business number.
# Outside that window Meta only lets pre-approved templates through. With a
# template configured, the title and body are sent as its {{1}} and {{2}}.

notify_whatsapp_label() { printf 'WhatsApp (advanced: Meta Cloud API, see docs/NOTIFICATIONS.md)'; }

notify_whatsapp_help() {
  cat <<'EOF'
WhatsApp needs a Meta developer app with the WhatsApp product: it gives you a
phone number id and an access token. Plain text only arrives within 24 h after
you last wrote to that number; for alerts at any time, create and get approved
a message template with two body variables, and give its name here.
EOF
}

notify_whatsapp_fields() {
  printf '%s\n' \
    'phone_id|Phone number id|0||' \
    'token|Access token|1||' \
    'to|Recipient number (digits, with country code)|0||' \
    'template|Approved template name|0||opt' \
    'template_lang|Template language code|0|en|opt' \
    'api_version|Graph API version|0|v21.0|opt'
}

# Template parameters accept neither newlines, tabs nor runs of spaces.
_whatsapp_param() {
  local s=$1
  s=${s//$'\n'/ | }
  s=${s//$'\t'/ }
  while [[ "$s" == *'    '* ]]; do s=${s//    /   }; done
  printf '%s' "${s:0:900}"
}

notify_whatsapp_send() {
  local ch=$1 payload to tpl text
  to=$(nget "$ch" to | tr -dc '0-9')
  tpl=$(nget "$ch" template)
  payload=$(mktmp)
  if [ -n "$tpl" ]; then
    printf '{"messaging_product":"whatsapp","to":"%s","type":"template","template":{"name":"%s","language":{"code":"%s"},"components":[{"type":"body","parameters":[{"type":"text","text":"%s"},{"type":"text","text":"%s"}]}]}}' \
      "$to" "$(json_escape "$tpl")" "$(json_escape "$(nget "$ch" template_lang en)")" \
      "$(json_escape "$(_whatsapp_param "$N_TITLE")")" \
      "$(json_escape "$(_whatsapp_param "${N_BODY:-$(notify_footer)}")")" >"$payload"
  else
    text="$(notify_icon) *$N_TITLE*"
    if [ -n "$N_BODY" ]; then text+=$'\n'"${N_BODY:0:3500}"; fi
    text+=$'\n'"_$(notify_footer)_"
    printf '{"messaging_product":"whatsapp","to":"%s","type":"text","text":{"body":"%s"}}' \
      "$to" "$(json_escape "$text")" >"$payload"
  fi
  notify_http "https://graph.facebook.com/$(nget "$ch" api_version v21.0)/$(nget "$ch" phone_id)/messages" \
    "$payload" 'header = "Content-Type: application/json"' \
    "header = \"Authorization: Bearer $(curlq "$(nget "$ch" token)")\""
}
