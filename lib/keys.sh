# shellcheck shell=bash
# Hardware security keys (FIDO2, e.g. YubiKey) as SSH keys.
#
# The private part never leaves the device: the file written next to the .pub
# is only a handle, useless without the physical key. Keys are created as
# "resident" so `helpoupou key import` can rebuild those handles on any new
# machine from the device itself.
#
# Public keys are copied to $CONF_DIR/keys/<name>.pub: that registry is what
# `key push` installs on servers and `key github` uploads.

SSH_DIR=${HELPOUPOU_SSH_DIR:-$HOME/.ssh}
KEYS_DIR="$CONF_DIR/keys"

_keys_require_fido_ssh() {
  ssh -Q key 2>/dev/null | grep -qx 'sk-ssh-ed25519@openssh.com' ||
    die "this OpenSSH cannot use security keys (needs OpenSSH 8.2 or newer with FIDO2 support)"
}

# 0 = a key is plugged in, 1 = none found, 2 = cannot tell.
_fido_present() {
  if command -v fido2-token >/dev/null 2>&1; then
    [ -n "$(fido2-token -L 2>/dev/null)" ]
    return
  fi
  if compgen -G '/sys/bus/usb/devices/*/idVendor' >/dev/null; then
    grep -qsx 1050 /sys/bus/usb/devices/*/idVendor && return 0
  fi
  return 2
}

_fido_require_present() {
  local rc=0
  _fido_present || rc=$?
  if [ "$rc" = 1 ]; then die "no security key detected: plug it in and try again"; fi
}

_keys_names() {
  local f
  [ -d "$KEYS_DIR" ] || return 0
  for f in "$KEYS_DIR"/*.pub; do
    if [ -f "$f" ]; then basename "$f" .pub; fi
  done
}

_keys_count() { _keys_names | wc -l; }

_key_check_name() {
  [[ "$1" =~ ^[A-Za-z0-9_-]+$ ]] || die "key name '$1' is invalid (letters, digits, _ and - only)"
}

_key_register() { # name pubfile
  grep -q '^sk-' "$2" || die "$2 is not a security-key public key (it should start with sk-)"
  machine_dirs
  mkdir -p "$KEYS_DIR"
  cp "$2" "$KEYS_DIR/$1.pub"
}

# Makes ssh offer the key: an IdentityFile line in a file helpoupou owns,
# included at the top of ~/.ssh/config (asked before touching that file).
_ssh_config_link() {
  local identity=$1 managed="$SSH_DIR/helpoupou.conf" config="$SSH_DIR/config" add tmp
  [ -f "$identity" ] || return 0
  if [ ! -f "$managed" ]; then
    printf '# Managed by helpoupou: security keys offered to every host.\n' >"$managed"
    chmod 600 "$managed"
  fi
  grep -qxF "IdentityFile $identity" "$managed" || printf 'IdentityFile %s\n' "$identity" >>"$managed"
  if grep -qsE '^[[:space:]]*Include[[:space:]].*helpoupou\.conf' "$config"; then return 0; fi
  ask_yn add "Add 'Include $managed' at the top of $config so ssh uses this key everywhere?" y
  if [ "$add" != y ]; then
    note "skipped: use the key with  ssh -i $identity ..."
    return 0
  fi
  tmp=$(mktemp "$config.XXXXXX")
  chmod 600 "$tmp"
  {
    printf 'Include %s\n\n' "$managed"
    if [ -f "$config" ]; then cat "$config"; fi
  } >"$tmp"
  mv "$tmp" "$config"
  ok "$config updated"
}

_key_next_steps() {
  local n
  n=$(_keys_count)
  if [ "$n" -lt 2 ]; then
    warn "only $n key registered: register a second one before locking any server, or losing this one locks you out"
  fi
  note "next: helpoupou key push user@server   (install your keys on a server)"
  note "      helpoupou key github             (use them for GitHub)"
}

key_setup() {
  local name=${1:-} file pin
  local -a opts
  need_tty "a touch on the security key" "Run this on your workstation, in a terminal"
  _keys_require_fido_ssh
  _fido_require_present
  [ -n "$name" ] || ask name "Name for this key (for example: primary, backup, spare)" "key$(($(_keys_count) + 1))"
  _key_check_name "$name"
  file="$SSH_DIR/id_ed25519_sk_$name"
  [ ! -e "$file" ] || die "$file already exists (register it with: helpoupou key adopt $file.pub)"
  ask_yn pin "Ask for the key's PIN at every use, not only a touch? (recommended)" y

  opts=(-t ed25519-sk -O resident -O application=ssh:helpoupou -O "user=$name" -C "helpoupou-$name" -N '' -f "$file")
  if [ "$pin" = y ]; then opts+=(-O verify-required); fi
  mkdir -p "$SSH_DIR"
  chmod 700 "$SSH_DIR"
  note "Enter the key's PIN if asked, then touch the key when it blinks."
  ssh-keygen "${opts[@]}" ||
    die "the key was not created. If this security key has no PIN yet, set one first (ykman fido access change-pin, or fido2-token -S <device>) and retry."
  _key_register "$name" "$file.pub"
  _ssh_config_link "$file"
  ok "security key '$name' is ready"
  _key_next_steps
}

# Rebuilds the key handles on this machine from the device (resident keys).
key_import() {
  local dir pub base name count=0
  need_tty "a touch on the security key" "Run this on your workstation, in a terminal"
  _keys_require_fido_ssh
  _fido_require_present
  dir=$(mktemp -d -p "$HELPOUPOU_TMP")
  note "Enter the key's PIN and touch it. When asked for a passphrase, press Enter twice (the file is only a handle)."
  (cd "$dir" && ssh-keygen -K) || die "nothing could be read from the security key"
  mkdir -p "$SSH_DIR"
  chmod 700 "$SSH_DIR"
  for pub in "$dir"/*.pub; do
    [ -f "$pub" ] || continue
    base=$(basename "$pub" .pub)
    name=${base#id_ed25519_sk_rk}
    name=${name#_}
    ask name "Name for the key found on the device" "${name:-key$(($(_keys_count) + 1))}"
    _key_check_name "$name"
    install -m 600 "${pub%.pub}" "$SSH_DIR/id_ed25519_sk_$name"
    install -m 644 "$pub" "$SSH_DIR/id_ed25519_sk_$name.pub"
    _key_register "$name" "$pub"
    _ssh_config_link "$SSH_DIR/id_ed25519_sk_$name"
    ok "security key '$name' imported"
    count=$((count + 1))
  done
  [ "$count" -gt 0 ] || die "no resident SSH key on this device (create one with: helpoupou key setup)"
}

# Registers a security key that was created outside helpoupou.
key_adopt() {
  local pub=${1:-} name
  [ -f "$pub" ] || die "usage: helpoupou key adopt FILE.pub"
  name=$(basename "$pub" .pub)
  name=${name#id_ed25519_sk}
  name=${name#id_ecdsa_sk}
  name=${name#_}
  ask name "Name for this key" "${2:-${name:-key$(($(_keys_count) + 1))}}"
  _key_check_name "$name"
  _key_register "$name" "$pub"
  _ssh_config_link "${pub%.pub}"
  ok "security key '$name' registered"
  _key_next_steps
}

key_list() {
  local name f found=0
  while IFS= read -r name; do
    found=1
    printf '  %s%-12s%s %s\n' "$C_BOLD" "$name" "$C_OFF" \
      "$(ssh-keygen -lf "$KEYS_DIR/$name.pub" 2>/dev/null | awk '{ print $2, $NF }')"
  done < <(_keys_names)
  [ "$found" = 1 ] || note "no security key registered yet (helpoupou key setup)"
  for f in "$SSH_DIR"/*_sk*.pub; do
    [ -f "$f" ] || continue
    if ! cat "$KEYS_DIR"/*.pub 2>/dev/null | grep -qxF "$(cat "$f")"; then
      note "found but not registered: $f  (helpoupou key adopt $f)"
    fi
  done
}

# Installs every registered public key on a server, without duplicates.
key_push() {
  local target=${1:-} n total
  [ -n "$target" ] || die "usage: helpoupou key push user@server"
  n=$(_keys_count)
  [ "$n" -gt 0 ] || die "no security key registered yet (helpoupou key setup)"
  if [ "$n" -lt 2 ]; then
    warn "only one key registered: add a second before hardening that server"
  fi
  note "installing $n key(s) on $target (you may be asked for the server password one last time)"
  # shellcheck disable=SC2016 # expanded by the remote shell, not here
  total=$(cat "$KEYS_DIR"/*.pub | ssh "$target" '
    umask 077
    mkdir -p "$HOME/.ssh"
    touch "$HOME/.ssh/authorized_keys"
    while IFS= read -r k; do
      [ -n "$k" ] || continue
      grep -qxF "$k" "$HOME/.ssh/authorized_keys" || printf "%s\n" "$k" >>"$HOME/.ssh/authorized_keys"
    done
    grep -c . "$HOME/.ssh/authorized_keys"
  ') || die "could not install the keys on $target"
  ok "$target now accepts $total key(s)"
  if have_tty; then
    note "checking that a key login really works (touch the key)"
    if ssh -o PreferredAuthentications=publickey -o PasswordAuthentication=no "$target" true; then
      ok "key login works. On the server, run: helpoupou ssh harden"
    else
      warn "key login did not work yet: do NOT disable passwords on $target"
    fi
  fi
}

key_github() {
  local name sign first='' failed=0
  command -v gh >/dev/null 2>&1 || die "the GitHub CLI (gh) is required for this"
  [ "$(_keys_count)" -gt 0 ] || die "no security key registered yet (helpoupou key setup)"
  while IFS= read -r name; do
    [ -n "$first" ] || first=$name
    if gh ssh-key add "$KEYS_DIR/$name.pub" --title "helpoupou-$name" --type authentication; then
      ok "'$name' can now log in to GitHub"
    else
      failed=1
    fi
  done < <(_keys_names)
  if [ "$failed" = 1 ]; then
    warn "some keys were refused. If it is a permission problem: gh auth refresh -h github.com -s admin:public_key,admin:ssh_signing_key"
  fi
  ask_yn sign "Also sign your git commits with '$first'? (one touch per commit)" n
  [ "$sign" = y ] || return 0
  [ -f "$SSH_DIR/id_ed25519_sk_$first" ] ||
    die "the handle $SSH_DIR/id_ed25519_sk_$first is not on this machine (helpoupou key import)"
  gh ssh-key add "$KEYS_DIR/$first.pub" --title "helpoupou-$first-signing" --type signing ||
    warn "GitHub refused the signing key (see the gh auth refresh hint above)"
  git config --global gpg.format ssh
  git config --global user.signingkey "$SSH_DIR/id_ed25519_sk_$first"
  git config --global commit.gpgsign true
  ok "commits are now signed with '$first'"
}

cmd_key() {
  local sub=${1:-list}
  [ $# -gt 0 ] && shift
  case "$sub" in
    setup) key_setup "$@" ;;
    import) key_import ;;
    adopt) key_adopt "$@" ;;
    list) key_list ;;
    push) key_push "$@" ;;
    github) key_github ;;
    *) die "unknown: key $sub (setup, import, adopt, list, push, github)" ;;
  esac
}
