# shellcheck shell=bash
# The interactive interface: `helpoupou` with no argument. Everything is
# reachable from here by picking entries; nothing has to be typed except
# values only the user knows (a token, a new server address).

SERVICE=''

_menu_health() {
  local ram disk up=''
  ram=$(_meminfo_mb MemAvailable)
  disk=$(_disk_pct /)
  if [ -n "$PROJECT_DIR" ] && command -v docker >/dev/null 2>&1; then
    up=$(docker ps -q --filter "label=com.docker.compose.project.working_dir=$PROJECT_DIR" 2>/dev/null | wc -l)
  fi
  printf 'RAM %s MB free · disk %s%% used%s' "${ram:-?}" "${disk:-?}" "${up:+ · $up container(s) running}"
}

_menu_header() {
  local kind='dev workstation'
  if [ "$MODE" = prod ]; then kind='production server'; fi
  if [ -t 1 ] && [ "${TERM:-dumb}" != dumb ]; then printf '\e[2J\e[H'; fi
  printf '%s helpoupou %s%s %s· %s · %s%s\n' "$C_BOLD" "$(cat "$HELPOUPOU_ROOT/VERSION" 2>/dev/null)" "$C_OFF" \
    "$C_DIM" "$kind" "$(uname -n)" "$C_OFF"
  if [ -n "$PROJECT_DIR" ]; then
    printf ' project %s%s%s %s(%s)%s\n' "$C_CYA" "$(cfg PROJECT_NAME)" "$C_OFF" "$C_DIM" "$PROJECT_DIR" "$C_OFF"
  else
    printf ' %sno project in this directory%s\n' "$C_DIM" "$C_OFF"
  fi
  printf ' %s%s%s\n' "$C_DIM" "$(_menu_health)" "$C_OFF"
}

_menu_pause() {
  printf '\n  %sPress Enter to go back%s ' "$C_DIM" "$C_OFF" >&2
  IFS= read -r _ || true
}

# Runs one action in a subshell: a failure or Ctrl-C comes back to the menu.
_menu_run() {
  local rc=0
  printf '\n'
  ("$@") || rc=$?
  if [ "$rc" != 0 ] && [ "$rc" != 130 ]; then warn "finished with an error (exit $rc)"; fi
  _menu_pause
}

# ---- pickers ----------------------------------------------------------------

# Sets SERVICE. With "all" as first argument, offers every service at once.
_pick_service() {
  local -a list=() items=()
  SERVICE=''
  compose_prepare
  mapfile -t list < <("${DC[@]}" config --services 2>/dev/null)
  if [ "${#list[@]}" -eq 0 ]; then return 0; fi
  if [ "${1:-}" = all ]; then items=("All services"); fi
  items+=("${list[@]}")
  if [ "${#items[@]}" -eq 1 ]; then
    SERVICE=${items[0]}
    return 0
  fi
  ui_select "Which service?" "${items[@]}" || return 1
  SERVICE=${items[$UI_CHOICE]}
  if [ "$SERVICE" = "All services" ]; then SERVICE=''; fi
}

_menu_logs() {
  _pick_service all || return 0
  note "Ctrl-C stops following the logs"
  cmd_logs ${SERVICE:+"$SERVICE"}
}

_menu_shell() {
  _pick_service || return 0
  cmd_shell ${SERVICE:+"$SERVICE"}
}

# Servers already used, plus the hosts of ~/.ssh/config. Sets TARGET.
_pick_server() {
  local -a items=()
  local line file="$CONF_DIR/servers"
  TARGET=''
  while IFS= read -r line; do
    if [ -n "$line" ]; then items+=("$line"); fi
  done < <(
    {
      cat "$file" 2>/dev/null
      awk 'tolower($1) == "host" { for (i = 2; i <= NF; i++) if ($i !~ /[*?!]/) print $i }' "$SSH_DIR/config" 2>/dev/null
    } | awk 'NF && !seen[$0]++'
  )
  items+=("Another server (type its address)")
  ui_select "Which server?" "${items[@]}" || return 1
  if [ "$UI_CHOICE" -lt $((${#items[@]} - 1)) ]; then
    TARGET=${items[$UI_CHOICE]}
    return 0
  fi
  ask TARGET "Server address (user@host)"
  [ -n "$TARGET" ] || return 1
  machine_dirs
  grep -qxF "$TARGET" "$file" 2>/dev/null || printf '%s\n' "$TARGET" >>"$file"
}

# ---- sub-menus --------------------------------------------------------------

_menu_notify() {
  local -a items=("Add a channel" "Show my channels" "Send a test message" "Remove a channel" "Back")
  while :; do
    _menu_header
    ui_select "Notifications" "${items[@]}" || return 0
    case "$UI_CHOICE" in
      0) _menu_run notify_setup ;;
      1) _menu_run notify_list ;;
      2) _menu_run notify_test ;;
      3) _menu_run _menu_notify_remove ;;
      *) return 0 ;;
    esac
  done
}

_menu_notify_remove() {
  notify_load
  if [ "${#NCH_NAMES[@]}" -eq 0 ]; then
    note "no channel to remove"
    return 0
  fi
  ui_select "Remove which channel?" "${NCH_NAMES[@]}" || return 0
  cmd_notify remove "${NCH_NAMES[$UI_CHOICE]}"
}

_menu_key_adopt() {
  local -a found=()
  local f
  for f in "$SSH_DIR"/*_sk*.pub; do
    [ -f "$f" ] || continue
    if ! cat "$KEYS_DIR"/*.pub 2>/dev/null | grep -qxF "$(cat "$f")"; then found+=("$f"); fi
  done
  if [ "${#found[@]}" -eq 0 ]; then
    note "no unregistered security key found in $SSH_DIR"
    return 0
  fi
  ui_select "Which existing key do you want to use?" "${found[@]}" || return 0
  key_adopt "${found[$UI_CHOICE]}"
}

_menu_key_push() {
  _pick_server || return 0
  key_push "$TARGET"
}

_menu_keys() {
  local -a items=("Create a key on a new security key" "Use a security key already set up on this computer"
    "Import the keys stored on a security key" "Show my security keys"
    "Install my keys on a server" "Use my keys for GitHub" "Back")
  while :; do
    _menu_header
    ui_select "Security keys (YubiKey...)" "${items[@]}" || return 0
    case "$UI_CHOICE" in
      0) _menu_run key_setup ;;
      1) _menu_run _menu_key_adopt ;;
      2) _menu_run key_import ;;
      3) _menu_run key_list ;;
      4) _menu_run _menu_key_push ;;
      5) _menu_run key_github ;;
      *) return 0 ;;
    esac
  done
}

_menu_ssh() {
  local -a items=("Show how this server accepts logins" "Turn SSH passwords off (keys only)"
    "Confirm the change (from a new session)" "Undo: allow passwords again" "Back")
  while :; do
    _menu_header
    ui_select "SSH access to this server" "${items[@]}" || return 0
    case "$UI_CHOICE" in
      0) _menu_run ssh_status ;;
      1) _menu_run ssh_harden ;;
      2) _menu_run ssh_confirm ;;
      3) _menu_run ssh_unharden ;;
      *) return 0 ;;
    esac
  done
}

_menu_access() {
  if [ "$MODE" = prod ]; then _menu_ssh; else _menu_keys; fi
}

_menu_mode() {
  ui_select "What is this machine?" "Dev workstation (my computer)" "Production server" || return 0
  if [ "$UI_CHOICE" = 1 ]; then MODE=prod; else MODE=dev; fi
  MODE_FLAG=$MODE
  machine_set MODE "$MODE"
  DC=()
}

_menu_switch_project() {
  local -a dirs=() items=()
  local d
  while IFS= read -r d; do
    dirs+=("$d")
    items+=("$(basename "$d")  ($d)")
  done < <(registry_list)
  if [ "${#dirs[@]}" -eq 0 ]; then
    note "no other project known on this machine yet"
    _menu_pause
    return 0
  fi
  ui_select "Open which project?" "${items[@]}" || return 0
  _project_load "${dirs[$UI_CHOICE]}"
  DC=()
}

_menu_more() {
  local -a labels=() actions=()
  if [ -n "$PROJECT_DIR" ]; then
    labels+=("Check the env file")
    actions+=("run:cmd_env check")
    if [ "$MODE" = prod ]; then
      labels+=("Stop the stack")
      actions+=("run:cmd_down")
    else
      labels+=("Delete containers and data")
      actions+=("run:cmd_clean")
    fi
  fi
  labels+=("Open another project" "Change what this machine is (dev / prod)" "Update helpoupou" "Back")
  actions+=("_menu_switch_project" "_menu_mode" "run:cmd_self_update" "back")
  _menu_header
  ui_select "More" "${labels[@]}" || return 0
  _menu_dispatch "${actions[$UI_CHOICE]}"
}

# "run:<command>" runs in a protected subshell; anything else changes the
# menu's own state (project, mode) and must run in this shell.
_menu_dispatch() {
  local action=$1
  case "$action" in
    back | quit) return 0 ;;
    run:*)
      DR_QUIET=0
      # shellcheck disable=SC2086 # "cmd_env check" is command + argument on purpose
      _menu_run ${action#run:}
      ;;
    *) "$action" ;;
  esac
}

_menu_init() {
  cmd_init
  project_load_optional
  _menu_pause
}

cmd_menu() {
  local -a labels actions
  local has_compose
  need_tty "a menu choice" "Use a subcommand instead: helpoupou help"
  project_load_optional
  mode_resolve
  # Ctrl-C ends the running action (logs, shell...), never the menu itself.
  trap ':' INT

  while :; do
    labels=()
    actions=()
    if [ -n "$PROJECT_DIR" ]; then
      if [ "$MODE" = prod ]; then
        labels+=("Deploy / redeploy" "Status" "Logs" "Health check" "Restart the services" "Open a shell")
        actions+=("run:cmd_up" "run:cmd_ps" "run:_menu_logs" "run:doctor_run" "run:cmd_restart" "run:_menu_shell")
      else
        labels+=("Start" "Stop" "Restart the services" "Status" "Logs" "Open a shell" "Health check")
        actions+=("run:cmd_up" "run:cmd_down" "run:cmd_restart" "run:cmd_ps" "run:_menu_logs" "run:_menu_shell" "run:doctor_run")
      fi
    else
      has_compose=$(_first_existing compose.yml compose.yaml docker-compose.yml docker-compose.yaml \
        compose.prod.yml docker-compose.prod.yml)
      if [ -n "$has_compose" ]; then
        labels+=("Set up helpoupou for the project in this directory")
        actions+=("_menu_init")
      fi
      labels+=("Open one of my projects" "Health check of this machine")
      actions+=("_menu_switch_project" "run:doctor_run")
    fi
    labels+=("Notifications  ›")
    actions+=("_menu_notify")
    if [ "$MODE" = prod ]; then labels+=("SSH access  ›"); else labels+=("Security keys  ›"); fi
    actions+=("_menu_access")
    labels+=("More  ›" "Quit")
    actions+=("_menu_more" "quit")

    _menu_header
    ui_select "What do you want to do?" "${labels[@]}" || return 0
    [ "${actions[$UI_CHOICE]}" = quit ] && return 0
    _menu_dispatch "${actions[$UI_CHOICE]}"
  done
}
