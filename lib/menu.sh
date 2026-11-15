# shellcheck shell=bash
# The interactive menu. Every entry maps to a subcommand of the CLI.

_menu_health() {
  local ram disk up=''
  ram=$(_meminfo_mb MemAvailable)
  disk=$(_disk_pct /)
  if [ -n "$PROJECT_DIR" ] && command -v docker >/dev/null 2>&1; then
    up=$(docker ps -q --filter "label=com.docker.compose.project.working_dir=$PROJECT_DIR" 2>/dev/null | wc -l)
  fi
  printf 'RAM %s MB free · disk %s%% used%s' "${ram:-?}" "${disk:-?}" "${up:+ · $up container(s) up}"
}

# Runs one action in a subshell so a failure returns to the menu.
_menu_run() {
  local rc=0
  ("$@") || rc=$?
  if [ "$rc" != 0 ]; then warn "finished with an error (exit $rc)"; fi
  printf '\n  Press Enter to go back to the menu ' >&2
  IFS= read -r _ || true
}

_menu_notify() {
  local -a items=("Add a channel" "List channels" "Send a test message" "Back")
  ui_select "Notifications" "${items[@]}" || return 0
  case "$UI_CHOICE" in
    0) notify_setup ;;
    1) notify_list ;;
    2) notify_test ;;
  esac
}

_menu_access() {
  local -a items
  if [ "$MODE" = prod ]; then
    items=("Show SSH status" "Harden SSH (keys only, no passwords)" "Confirm the hardening" "Back")
    ui_select "Access to this server" "${items[@]}" || return 0
    case "$UI_CHOICE" in
      0) ssh_status ;;
      1) ssh_harden ;;
      2) ssh_confirm ;;
    esac
  else
    local target=''
    items=("Register a security key (YubiKey...)" "Import the keys stored on a security key"
      "List my security keys" "Install my keys on a server" "Use my keys for GitHub" "Back")
    ui_select "Security keys" "${items[@]}" || return 0
    case "$UI_CHOICE" in
      0) key_setup ;;
      1) key_import ;;
      2) key_list ;;
      3)
        ask target "Server (user@host)"
        key_push "$target"
        ;;
      4) key_github ;;
    esac
  fi
}

_menu_pick_project() {
  local -a dirs=() items=()
  local d
  while IFS= read -r d; do
    dirs+=("$d")
    items+=("$(basename "$d")  ($d)")
  done < <(registry_list)
  items+=("Check this machine (doctor)" "Notifications" "Security keys and SSH access"
    "Set up the project in this directory (init)" "Quit")
  local n=${#dirs[@]}
  ui_select "helpoupou - no project here. Pick one:" "${items[@]}" || exit 0
  if [ "$UI_CHOICE" -lt "$n" ]; then
    _project_load "${dirs[$UI_CHOICE]}"
    return 0
  fi
  case $((UI_CHOICE - n)) in
    0) _menu_run doctor_run ;;
    1) _menu_run _menu_notify ;;
    2) _menu_run _menu_access ;;
    3) cmd_init ;;
  esac
  exit 0
}

cmd_menu() {
  local -a labels actions
  need_tty "a menu choice" "Use a subcommand instead: helpoupou help"
  project_load_optional
  mode_resolve
  if [ -z "$PROJECT_DIR" ]; then _menu_pick_project; fi

  while :; do
    if [ "$MODE" = prod ]; then
      labels=("Deploy / redeploy" "Status" "Logs" "Health check (doctor)" "Restart services"
        "Open a shell" "Check the env file" "Notifications" "SSH access" "Stop the stack" "Quit")
      actions=(cmd_up cmd_ps cmd_logs doctor_run cmd_restart
        cmd_shell "cmd_env check" _menu_notify _menu_access cmd_down quit)
    else
      labels=("Start" "Stop" "Restart services" "Status" "Logs" "Open a shell"
        "Health check (doctor)" "Check the env file" "Notifications" "Security keys"
        "Delete containers and data (clean)" "Quit")
      actions=(cmd_up cmd_down cmd_restart cmd_ps cmd_logs cmd_shell
        doctor_run "cmd_env check" _menu_notify _menu_access cmd_clean quit)
    fi
    ui_select "$(cfg PROJECT_NAME) · $MODE · $(_menu_health)" "${labels[@]}" || return 0
    [ "${actions[$UI_CHOICE]}" = quit ] && return 0
    DR_QUIET=0
    # shellcheck disable=SC2086 # "cmd_env check" is split into command + argument on purpose
    _menu_run ${actions[$UI_CHOICE]}
  done
}
