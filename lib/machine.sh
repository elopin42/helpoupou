# shellcheck shell=bash
# Machine-level state: dev/prod mode and the registry of known projects.

CONF_DIR=${HELPOUPOU_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/helpoupou}
STATE_DIR=${HELPOUPOU_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/helpoupou}

machine_dirs() {
  mkdir -p "$CONF_DIR" "$STATE_DIR"
  chmod 700 "$CONF_DIR" "$STATE_DIR"
}

machine_get() { env_get "$CONF_DIR/machine.conf" "$1"; }

machine_set() {
  machine_dirs
  [ -f "$CONF_DIR/machine.conf" ] || : >"$CONF_DIR/machine.conf"
  env_set "$CONF_DIR/machine.conf" "$1" "$2"
}

# A remote shell with no graphical session looks like a server.
mode_guess() {
  if [ -n "${SSH_CONNECTION:-}" ] && [ -z "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]; then
    printf 'prod'
  else
    printf 'dev'
  fi
}

mode_validate() {
  case "$1" in
    dev | prod) ;;
    *) die "invalid mode '$1' (expected dev or prod)" ;;
  esac
}

# Sets MODE. Order: --mode flag, HELPOUPOU_MODE, machine.conf, then ask once.
mode_resolve() {
  local m=${MODE_FLAG:-${HELPOUPOU_MODE:-}}
  [ -n "$m" ] || m=$(machine_get MODE)
  if [ -z "$m" ]; then
    if ! have_tty && [ "$HELPOUPOU_YES" != 1 ]; then
      die "machine mode is not set and there is no terminal to ask. Run 'helpoupou mode dev' or 'helpoupou mode prod' once, or set HELPOUPOU_MODE."
    fi
    m=$(mode_guess)
    if [ "$HELPOUPOU_YES" != 1 ]; then
      ui_select "First run on this machine. What is it? (my guess: $m)" \
        "Dev workstation (my computer)" "Production server" ||
        die "machine mode not chosen"
      if [ "$UI_CHOICE" = 1 ]; then m=prod; else m=dev; fi
    fi
    machine_set MODE "$m"
    ok "this machine is remembered as '$m' (change with: helpoupou mode dev|prod)"
  fi
  mode_validate "$m"
  MODE=$m
}

cmd_mode() {
  if [ $# -eq 0 ]; then
    local m
    m=$(machine_get MODE)
    printf '%s\n' "${m:-not set (guess: $(mode_guess))}"
    return 0
  fi
  mode_validate "$1"
  machine_set MODE "$1"
  ok "machine mode set to '$1'"
}

# ---- project registry -------------------------------------------------------

registry_add() {
  local dir=$1 file="$CONF_DIR/projects"
  machine_dirs
  [ -f "$file" ] || : >"$file"
  grep -qxF "$dir" "$file" || printf '%s\n' "$dir" >>"$file"
}

# Prints the registered project directories that still exist, pruning the rest.
registry_list() {
  local file="$CONF_DIR/projects" dir tmp
  [ -f "$file" ] || return 0
  tmp=$(mktmp)
  while IFS= read -r dir; do
    if [ -n "$dir" ] && [ -f "$dir/helpoupou.conf" ]; then printf '%s\n' "$dir"; fi
  done <"$file" >"$tmp"
  cat "$tmp" >"$file"
  cat "$tmp"
}
