# shellcheck shell=bash
# Security keys and SSH hardening.

_keys() { echo "$XDG_CONFIG_HOME/helpoupou/keys"; }

test_key_setup_creates_a_resident_key_and_wires_ssh() {
  run_in 'primary\ny\ny\n' "$HP" key setup
  assert_rc 0
  assert_file_has "$STUB_DIR/calls" '-t ed25519-sk -O resident -O application=ssh:helpoupou -O user=primary'
  assert_file_has "$STUB_DIR/calls" '-O verify-required'
  assert_file_has "$(_keys)/primary.pub" 'sk-ssh-ed25519@openssh.com'
  assert_file_has "$HOME/.ssh/helpoupou.conf" "IdentityFile $HOME/.ssh/id_ed25519_sk_primary"
  assert_eq "$(head -1 "$HOME/.ssh/config")" "Include $HOME/.ssh/helpoupou.conf"
  assert_out 'only 1 key registered'
}

test_key_setup_keeps_existing_ssh_config() {
  mkdir -p "$HOME/.ssh" && printf 'Host old\n  User me\n' >"$HOME/.ssh/config"
  run_in 'primary\ny\ny\n' "$HP" key setup
  assert_rc 0
  assert_file_has "$HOME/.ssh/config" 'Host old'
  run_in 'backup\ny\n' "$HP" key setup
  assert_rc 0
  assert_eq "$(grep -c '^Include' "$HOME/.ssh/config")" 1
  assert_eq "$(grep -c '^IdentityFile' "$HOME/.ssh/helpoupou.conf")" 2
  assert_no_out 'only 1 key'
}

test_key_setup_needs_a_terminal_and_a_plugged_key() {
  run "$HP" key setup primary
  assert_fails
  assert_out 'no terminal attached'
  touch "$STUB_DIR/no-key-plugged"
  run_in 'y\n' "$HP" key setup primary
  assert_fails
  assert_out 'no security key detected'
}

test_key_setup_explains_a_missing_pin() {
  touch "$STUB_DIR/keygen-fails"
  run_in 'y\n' "$HP" key setup primary
  assert_fails
  assert_out 'set one first'
  [ ! -e "$(_keys)/primary.pub" ] || _fail "a failed key was registered"
}

test_key_setup_refuses_an_openssh_without_fido() {
  touch "$STUB_DIR/no-fido-ssh"
  run_in 'y\n' "$HP" key setup primary
  assert_fails
  assert_out 'cannot use security keys'
}

test_key_import_rebuilds_handles_from_the_device() {
  run_in '\ny\n' "$HP" key import
  assert_rc 0
  assert_file_has "$(_keys)/spare.pub" 'AAAAresidentspare'
  assert_eq "$(stat -c %a "$HOME/.ssh/id_ed25519_sk_spare")" 600
}

test_key_adopt_refuses_a_plain_key() {
  echo 'ssh-ed25519 AAAAplain me' >"$T/plain.pub"
  run_in 'plain\n' "$HP" key adopt "$T/plain.pub"
  assert_fails
  assert_out 'not a security-key public key'
}

test_key_push_installs_every_key_and_tests_the_login() {
  run_in 'primary\ny\ny\n' "$HP" key setup
  run_in 'backup\ny\n' "$HP" key setup
  run_in '' "$HP" key push deploy@server.example.com
  assert_rc 0
  assert_eq "$(grep -c '^sk-' "$STUB_DIR/remote-authorized_keys")" 2
  assert_out 'now accepts 2 key(s)'
  assert_out 'key login works'
}

test_key_push_warns_when_the_key_login_fails() {
  run_in 'primary\ny\ny\n' "$HP" key setup
  echo 255 >"$STUB_DIR/ssh-key-login-rc"
  run_in '' "$HP" key push deploy@server.example.com
  assert_out 'do NOT disable passwords'
}

test_key_github_uploads_and_signing_is_opt_in() {
  run_in 'primary\ny\ny\n' "$HP" key setup
  run_in 'n\n' "$HP" key github
  assert_rc 0
  assert_file_has "$STUB_DIR/calls" "gh ssh-key add $(_keys)/primary.pub --title helpoupou-primary --type authentication"
  assert_file_lacks "$STUB_DIR/calls" '--type signing'
}

# ---- server side ------------------------------------------------------------

_server() { # number of authorized keys
  export HELPOUPOU_SSHD_DROPIN_DIR="$T/sshd_config.d" SSH_CONNECTION='203.0.113.7 50123 198.51.100.1 22'
  mkdir -p "$HELPOUPOU_SSHD_DROPIN_DIR" "$HOME/.ssh"
  touch "$STUB_DIR/sudo-ok"
  echo 'passwordauthentication yes' >"$STUB_DIR/sshd"
  local i
  for ((i = 0; i < $1; i++)); do echo "sk-ssh-ed25519@openssh.com AAAA$i key$i" >>"$HOME/.ssh/authorized_keys"; done
  echo "sshd[1]: Accepted publickey for $(id -un) from 203.0.113.7 port 50123 ssh2: ED25519-SK SHA256:x" >"$STUB_DIR/journal"
}

_dropin() { echo "$T/sshd_config.d/00-helpoupou.conf"; }

test_harden_refuses_without_any_key() {
  _server 0
  run "$HP" --yes ssh harden
  assert_fails
  assert_out 'no SSH key installed'
  [ ! -e "$(_dropin)" ] || _fail "ssh was changed"
}

test_harden_refuses_a_single_key_unless_told() {
  _server 1
  run "$HP" --yes ssh harden
  assert_fails
  assert_out 'only one SSH key'
  [ ! -e "$(_dropin)" ] || _fail "ssh was changed"
  run "$HP" --yes ssh harden --allow-single-key
  assert_rc 0
}

test_harden_refuses_when_the_session_used_a_password() {
  _server 2
  echo "sshd[1]: Accepted password for $(id -un) from 203.0.113.7 port 50123 ssh2" >"$STUB_DIR/journal"
  run "$HP" --yes ssh harden
  assert_fails
  assert_out 'cannot confirm that this session logged in with a key'
  [ ! -e "$(_dropin)" ] || _fail "ssh was changed"
}

test_harden_refuses_a_key_login_from_another_connection() {
  _server 2
  echo "sshd[1]: Accepted publickey for $(id -un) from 203.0.113.7 port 40000 ssh2" >"$STUB_DIR/journal"
  run "$HP" --yes ssh harden
  assert_fails
  [ ! -e "$(_dropin)" ] || _fail "ssh was changed"
}

test_harden_applies_and_arms_a_rollback() {
  _server 2
  run "$HP" --yes ssh harden
  assert_rc 0
  assert_file_has "$(_dropin)" 'PasswordAuthentication no'
  assert_file_has "$STUB_DIR/calls" 'systemd-run --quiet --unit helpoupou-ssh-rollback --on-active=10min'
  assert_file_has "$STUB_DIR/calls" 'systemctl reload ssh'
  assert_out 'NOT FINAL YET'
  # the rollback must be armed before sshd is reloaded
  assert_eq "$(grep -nE '^systemd-run|reload ssh' "$STUB_DIR/calls" | head -1 | cut -d: -f2 | cut -d' ' -f1)" systemd-run
}

test_harden_reverts_when_sshd_rejects_the_config() {
  _server 2
  echo 1 >"$STUB_DIR/sshd-t-rc"
  run "$HP" --yes ssh harden
  assert_fails
  assert_out 'SSH is unchanged'
  [ ! -e "$(_dropin)" ] || _fail "broken config left in place"
  assert_file_lacks "$STUB_DIR/calls" 'reload'
}

test_harden_reverts_when_another_file_still_allows_passwords() {
  _server 2
  touch "$STUB_DIR/sshd-overridden"
  run "$HP" --yes ssh harden
  assert_fails
  assert_out 'another sshd configuration file'
  [ ! -e "$(_dropin)" ] || _fail "useless config left in place"
}

test_confirm_must_come_from_a_new_session() {
  _server 2
  run "$HP" --yes ssh harden
  run "$HP" ssh confirm
  assert_fails
  assert_out 'Open a NEW terminal'
  [ -f "$STUB_DIR/rollback-armed" ] || _fail "rollback was cancelled by the old session"
  SSH_CONNECTION='203.0.113.7 50999 198.51.100.1 22' run "$HP" ssh confirm
  assert_rc 0
  assert_out 'now permanent'
  [ ! -f "$STUB_DIR/rollback-armed" ] || _fail "rollback still armed"
}

test_doctor_flags_unconfirmed_hardening_and_single_key() {
  _server 1
  run "$HP" --yes ssh harden --allow-single-key
  HELPOUPOU_MODE=prod run "$HP" doctor
  assert_out 'SSH hardening is not confirmed'
  assert_out 'only one SSH key'
  assert_out 'SSH accepts keys only'
}

test_unharden_removes_the_settings() {
  _server 2
  run "$HP" --yes ssh harden
  run "$HP" ssh unharden
  assert_rc 0
  [ ! -e "$(_dropin)" ] || _fail "settings still there"
}
