# shellcheck shell=bash
# Safe SSH hardening on a server: keys only, no passwords.
#
# The whole point is to make locking yourself out impossible:
#   1. refuse unless at least two keys are installed (one can be lost);
#   2. refuse unless THIS session is proven to have logged in with a key;
#   3. validate the configuration before applying it, and check the result;
#   4. arm an automatic rollback, cancelled only by `helpoupou ssh confirm`
#      run from a NEW session, which itself proves a key login still works.

SSHD_DROPIN_DIR=${HELPOUPOU_SSHD_DROPIN_DIR:-/etc/ssh/sshd_config.d}
# sshd keeps the FIRST value it reads: "00-" sorts before distribution files.
SSHD_DROPIN="$SSHD_DROPIN_DIR/00-helpoupou.conf"
SSH_ROLLBACK_UNIT=helpoupou-ssh-rollback
SSH_ROLLBACK_MINUTES=10

_sudo() {
  if [ "$(id -u)" = 0 ]; then "$@"; else sudo "$@"; fi
}

_sshd_setting() { # prints the effective value of one sshd setting
  PATH="$PATH:/usr/sbin:/sbin" _sudo sshd -T 2>/dev/null | awk -v k="$1" 'tolower($1) == k { print tolower($2); exit }'
}

_authorized_keys() {
  grep -vE '^[[:space:]]*(#|$)' "$HOME/.ssh/authorized_keys" 2>/dev/null || true
}

_authorized_count() { _authorized_keys | grep -c . || true; }

_ssh_reload() {
  _sudo systemctl reload ssh 2>/dev/null || _sudo systemctl reload sshd
}

_ssh_rollback_pending() {
  systemctl is-active --quiet "$SSH_ROLLBACK_UNIT.timer" 2>/dev/null
}

# True when the server log shows that the current connection (same client
# address and port) was accepted with a public key.
_session_used_key() {
  local ip port _rest log
  [ -n "${SSH_CONNECTION:-}" ] || return 1
  read -r ip port _rest <<<"$SSH_CONNECTION"
  # Either source may be missing on a given system: read both, fail on neither.
  log=$(
    _sudo journalctl -u ssh -u sshd --since '-24h' --no-pager 2>/dev/null || true
    _sudo cat /var/log/auth.log 2>/dev/null || true
  )
  grep -qF "Accepted publickey for $(id -un) from $ip port $port " <<<"$log"
}

ssh_status() {
  local n pw
  n=$(_authorized_count)
  pw=$(_sshd_setting passwordauthentication)
  h1 "SSH access - $(id -un)@$(uname -n)"
  printf '  keys installed for this account : %s (%s security key(s))\n' "$n" "$(_authorized_keys | grep -c '^sk-' || true)"
  printf '  password login                  : %s\n' "${pw:-unknown (needs root)}"
  printf '  root login                      : %s\n' "$(_sshd_setting permitrootlogin)"
  if [ -f "$SSHD_DROPIN" ]; then
    printf '  hardened by helpoupou           : yes\n'
  else
    printf '  hardened by helpoupou           : no\n'
  fi
  if _ssh_rollback_pending; then
    warn "hardening is NOT confirmed yet: it will be undone automatically. Log in from a new terminal and run: helpoupou ssh confirm"
  fi
}

ssh_harden() {
  local single=0 noproof=0 n go tmp
  while [ $# -gt 0 ]; do
    case "$1" in
      --allow-single-key) single=1 ;;
      --no-login-proof) noproof=1 ;;
      *) die "unknown option for ssh harden: $1" ;;
    esac
    shift
  done
  [ -d "$SSHD_DROPIN_DIR" ] ||
    die "$SSHD_DROPIN_DIR does not exist: this system's sshd does not use drop-in files, harden it by hand"

  n=$(_authorized_count)
  [ "$n" -gt 0 ] || die "no SSH key installed for $(id -un): from your workstation run 'helpoupou key push $(id -un)@this-server' first. Nothing was changed."
  if [ "$n" -lt 2 ] && [ "$single" != 1 ]; then
    die "only one SSH key is installed: lose it and you are locked out. Install a second one, or accept the risk with --allow-single-key. Nothing was changed."
  fi

  if [ "$noproof" != 1 ] && ! _session_used_key; then
    die "cannot confirm that this session logged in with a key. Reconnect with your key (ssh -o PreferredAuthentications=publickey ...) and run this again. Nothing was changed."
  fi

  if [ "$(_sshd_setting passwordauthentication)" = no ] && ! _ssh_rollback_pending; then
    ok "SSH already refuses passwords: nothing to do"
    return 0
  fi

  ask_yn go "Disable SSH password logins on this server now? ($n key(s) installed)" y
  [ "$go" = y ] || die "aborted: nothing was changed"

  tmp=$(mktmp)
  cat >"$tmp" <<EOF
# Managed by helpoupou. Undo with: helpoupou ssh unharden
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin prohibit-password
PubkeyAuthentication yes
EOF
  _sudo install -m 644 "$tmp" "$SSHD_DROPIN"
  if ! PATH="$PATH:/usr/sbin:/sbin" _sudo sshd -t; then
    _sudo rm -f "$SSHD_DROPIN"
    die "sshd rejected the new configuration: it was removed, SSH is unchanged"
  fi
  if [ "$(_sshd_setting passwordauthentication)" != no ]; then
    _sudo rm -f "$SSHD_DROPIN"
    die "another sshd configuration file still enables passwords: change removed, SSH is unchanged"
  fi

  machine_dirs
  printf '%s\n' "${SSH_CONNECTION:-local}" >"$STATE_DIR/ssh-harden-session"
  _sudo systemctl stop "$SSH_ROLLBACK_UNIT.timer" "$SSH_ROLLBACK_UNIT.service" 2>/dev/null || true
  _sudo systemctl reset-failed "$SSH_ROLLBACK_UNIT.service" 2>/dev/null || true
  if _sudo systemd-run --quiet --unit "$SSH_ROLLBACK_UNIT" --on-active="${SSH_ROLLBACK_MINUTES}min" \
    /bin/sh -c "rm -f '$SSHD_DROPIN'; systemctl reload ssh 2>/dev/null || systemctl reload sshd"; then
    _ssh_reload
    ok "passwords are disabled"
    warn "NOT FINAL YET. Keep this session open, then:"
    note "  1. open a NEW terminal and log in to this server with your key"
    note "  2. there, run: helpoupou ssh confirm"
    note "Without that, the change is undone automatically in $SSH_ROLLBACK_MINUTES minutes."
  else
    _ssh_reload
    ok "passwords are disabled"
    warn "no automatic rollback could be armed. Keep this session open and test a NEW login now; undo with: helpoupou ssh unharden"
  fi
}

ssh_confirm() {
  if ! _ssh_rollback_pending; then
    note "nothing to confirm"
    return 0
  fi
  if [ "$(cat "$STATE_DIR/ssh-harden-session" 2>/dev/null)" = "${SSH_CONNECTION:-local}" ]; then
    die "this is the session that hardened SSH: it proves nothing. Open a NEW terminal, log in with your key, and run 'helpoupou ssh confirm' there."
  fi
  _sudo systemctl stop "$SSH_ROLLBACK_UNIT.timer"
  ok "confirmed: SSH hardening is now permanent"
}

ssh_unharden() {
  _sudo systemctl stop "$SSH_ROLLBACK_UNIT.timer" 2>/dev/null || true
  if [ ! -f "$SSHD_DROPIN" ]; then
    note "helpoupou did not harden SSH here: nothing to undo"
    return 0
  fi
  _sudo rm -f "$SSHD_DROPIN"
  _ssh_reload
  ok "helpoupou's SSH settings were removed"
}

cmd_ssh() {
  local sub=${1:-status}
  [ $# -gt 0 ] && shift
  case "$sub" in
    status) ssh_status ;;
    harden) ssh_harden "$@" ;;
    confirm) ssh_confirm ;;
    unharden) ssh_unharden ;;
    *) die "unknown: ssh $sub (status, harden, confirm, unharden)" ;;
  esac
}
