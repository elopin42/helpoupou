# shellcheck shell=bash
# Docker Compose wrapper, project hooks and the lifecycle commands.

declare -ga DC=()

# Builds the DC command array for the current MODE.
compose_prepare() {
  local files profiles f p
  local -a list=()
  if [ "$MODE" = prod ]; then
    files=$(cfg COMPOSE_PROD)
    profiles=$(cfg COMPOSE_PROD_PROFILES)
  else
    files=$(cfg COMPOSE_DEV)
    profiles=$(cfg COMPOSE_DEV_PROFILES)
  fi
  DC=(docker compose)
  read -ra list <<<"$profiles"
  for p in "${list[@]+"${list[@]}"}"; do DC+=(--profile "$p"); done
  read -ra list <<<"$files"
  for f in "${list[@]+"${list[@]}"}"; do
    [ -f "$f" ] || die "compose file not found: $f (COMPOSE_${MODE^^} in helpoupou.conf)"
    DC+=(-f "$f")
  done
}

# Hooks are executables in .helpoupou/hooks/. Missing = skipped, failing = abort.
run_hook() {
  local name=$1 file=".helpoupou/hooks/$1" rc=0
  [ -e "$file" ] || return 0
  if [ ! -x "$file" ]; then
    warn "hook $file is not executable: skipped (chmod +x to enable it)"
    return 0
  fi
  note "hook: $name"
  HELPOUPOU_MODE=$MODE HELPOUPOU_PROJECT=$(cfg PROJECT_NAME) HELPOUPOU_COMPOSE="${DC[*]}" \
    "./$file" || rc=$?
  if [ "$rc" != 0 ]; then
    fail "hook $name failed (exit $rc)"
    exit "$rc"
  fi
}

print_urls() {
  local urls u
  local -a list=()
  if [ "$MODE" = prod ]; then urls=$(cfg URLS_PROD); else urls=$(cfg URLS_DEV); fi
  read -ra list <<<"$urls"
  for u in "${list[@]+"${list[@]}"}"; do printf '    %s\n' "$u"; done
}

cmd_up() {
  local first_boot=0 vol
  compose_prepare
  h1 "$(cfg PROJECT_NAME) - $MODE"

  env_bootstrap
  if [ "$MODE" = prod ]; then env_domain_guard; fi

  DR_QUIET=1
  if ! doctor_run; then
    if [ "$FORCE" = 1 ]; then
      warn "doctor reported failures: continuing because of --force"
    else
      die "not started: fix the failures above, or re-run with --force"
    fi
  fi

  vol=$(cfg DB_VOLUME)
  if [ -n "$vol" ] && ! volume_exists "$vol"; then first_boot=1; fi

  run_hook pre-up
  note "building images"
  "${DC[@]}" build
  note "starting services"
  if [ "$MODE" = prod ]; then
    # --wait: success means every service is running AND healthy, not merely
    # that containers were created.
    "${DC[@]}" up -d --wait --wait-timeout 180 --remove-orphans
  else
    "${DC[@]}" up -d
  fi
  if [ "$first_boot" = 1 ]; then run_hook first-boot; fi
  run_hook post-up

  "${DC[@]}" ps
  registry_add "$PROJECT_DIR"
  printf '\n'
  ok "$(cfg PROJECT_NAME) is up ($MODE)"
  print_urls
}

cmd_down() {
  compose_prepare
  run_hook pre-down
  "${DC[@]}" down --remove-orphans
  ok "stopped (volumes kept)"
}

cmd_restart() {
  compose_prepare
  "${DC[@]}" restart
  "${DC[@]}" ps
}

cmd_build() {
  compose_prepare
  "${DC[@]}" build
}

cmd_ps() {
  compose_prepare
  "${DC[@]}" ps
}

cmd_logs() {
  local svc=${1:-$(cfg LOG_SERVICE)}
  compose_prepare
  if [ -n "$svc" ]; then
    "${DC[@]}" logs -f --tail=200 "$svc"
  else
    "${DC[@]}" logs -f --tail=200
  fi
}

cmd_shell() {
  local svc=${1:-$(cfg SHELL_SERVICE)}
  [ -n "$svc" ] || die "which service? Use 'helpoupou shell <service>' or set SHELL_SERVICE in helpoupou.conf"
  compose_prepare
  "${DC[@]}" exec "$svc" sh -c 'if command -v bash >/dev/null 2>&1; then exec bash; else exec sh; fi'
}

# Dev asks y/N. Prod requires typing the project name: --yes does not skip it.
cmd_clean() {
  local name answer=''
  name=$(cfg PROJECT_NAME)
  compose_prepare
  if [ "$MODE" = prod ]; then
    have_tty || die "input required: confirmation to delete PRODUCTION data (no terminal attached). This command is never run unattended in prod."
    warn "PRODUCTION: this deletes every volume of '$name' (database, uploads, certificates)."
    printf "  Type the project name to confirm: " >&2
    IFS= read -r answer || true
    [ "$answer" = "$name" ] || die "aborted: nothing was deleted"
  else
    ask_yn answer "Delete the containers AND volumes of '$name' (all local data)?" n
    [ "$answer" = y ] || die "aborted: nothing was deleted"
  fi
  "${DC[@]}" down -v --remove-orphans
  ok "containers and volumes removed"
}
