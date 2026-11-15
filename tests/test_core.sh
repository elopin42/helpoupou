# shellcheck shell=bash
# Config parsing, env file, secrets, production guards, hooks, no-terminal.

test_config_is_parsed_not_executed() {
  # shellcheck disable=SC2016 # the literal $(...) is the point of the test
  printf 'URLS_DEV=$(touch %s/pwned)\nPROJECT_NAME="quoted-name"\n' "$T" >helpoupou.conf
  printf 'COMPOSE_DEV=compose.yml\n' >>helpoupou.conf
  run "$HP" up
  assert_rc 0
  [ ! -e "$T/pwned" ] || _fail "config value was executed"
  assert_out 'quoted-name'
  assert_out '$(touch'
}

test_config_warns_on_unknown_key_and_bad_line() {
  printf 'NOPE=1\nthis is not a setting\n' >>helpoupou.conf
  run "$HP" ps
  assert_rc 0
  assert_out "unknown key 'NOPE'"
  assert_out 'line ignored'
}

test_no_project_is_a_clear_error() {
  cd "$T/home" || exit 1
  run "$HP" up
  assert_fails
  assert_out 'helpoupou init'
}

test_up_creates_env_with_secrets_mode_600() {
  run "$HP" up
  assert_rc 0
  assert_eq "$(stat -c %a .env)" 600
  assert_file_lacks .env 'SECRET_KEY=change-me'
  assert_eq "$(grep -c '^SECRET_KEY=[A-Za-z0-9]\{40\}$' .env)" 1
  assert_eq "$(grep -c '^POSTGRES_PASSWORD=[A-Za-z0-9]\{24\}$' .env)" 1
  assert_file_has .env 'DEBUG=1'
  assert_out 'http://localhost:8000'
}

test_secrets_are_generated_once() {
  run "$HP" env
  local before
  before=$(cat .env)
  run "$HP" env
  assert_rc 0
  assert_eq "$(cat .env)" "$before"
}

test_secret_values_never_printed() {
  run "$HP" env
  assert_no_out "$(grep '^SECRET_KEY=' .env | cut -d= -f2)"
  assert_out 'SECRET_KEY generated'
}

test_db_secret_not_regenerated_when_volume_exists() {
  echo myapp_pgdata >"$STUB_DIR/volumes"
  run "$HP" env
  assert_rc 0
  assert_file_has .env 'POSTGRES_PASSWORD=example'
  assert_out 'not regenerated'
  assert_file_lacks .env 'SECRET_KEY=change-me'
}

test_user_value_is_never_rewritten() {
  printf 'SECRET_KEY=mine\nPOSTGRES_PASSWORD=mine-too\n' >.env
  run "$HP" env
  assert_file_has .env 'SECRET_KEY=mine'
  assert_file_has .env 'POSTGRES_PASSWORD=mine-too'
}

test_env_check_lists_names_only() {
  printf 'SITE_HOST=example.com\nSECRET_KEY=change-me\nPOSTGRES_PASSWORD=real-value-xyz\n' >.env
  run "$HP" env check
  assert_fails
  assert_out 'API_TOKEN'
  assert_out 'DEBUG'
  assert_out 'SECRET_KEY'
  assert_no_out 'real-value-xyz'
  assert_no_out 'change-me'
}

test_prod_refuses_example_domain() {
  run "$HP" --mode prod up
  assert_fails
  assert_out 'SITE_HOST'
  assert_out 'example value'
  assert_file_lacks "$STUB_DIR/calls" ' up '
}

test_prod_domain_guard_override_and_forced_values() {
  HELPOUPOU_ALLOW_TEMPLATE_DOMAIN=1 run "$HP" --mode prod up
  assert_rc 0
  assert_file_has .env 'DEBUG=0'
  assert_file_has "$STUB_DIR/calls" 'up -d --wait --wait-timeout 180 --remove-orphans'
}

test_prod_starts_with_a_real_domain() {
  cp .env.example .env
  sed -i 's/^SITE_HOST=.*/SITE_HOST=app.example.org/' .env
  run "$HP" --mode prod up
  assert_rc 0
}

_hook() {
  mkdir -p .helpoupou/hooks
  printf '#!/usr/bin/env bash\necho "hook %s $HELPOUPOU_MODE $HELPOUPOU_PROJECT" >>"$STUB_DIR/calls"\nexit %s\n' "$1" "${2:-0}" >".helpoupou/hooks/$1"
  chmod +x ".helpoupou/hooks/$1"
}

test_hooks_run_in_order_with_first_boot() {
  _hook pre-up
  _hook first-boot
  _hook post-up
  run "$HP" up
  assert_rc 0
  local order
  order=$(grep -nE 'hook |compose .* (build|up)' "$STUB_DIR/calls" | cut -d: -f2- | awk '{ print ($1 == "hook") ? $2 : $NF }' | tr '\n' ' ')
  assert_eq "$order" 'pre-up build -d first-boot post-up '
  assert_file_has "$STUB_DIR/calls" 'hook pre-up dev myapp'
}

test_first_boot_hook_skipped_when_volume_exists() {
  echo myapp_pgdata >"$STUB_DIR/volumes"
  _hook first-boot
  _hook post-up
  run "$HP" up
  assert_rc 0
  assert_file_lacks "$STUB_DIR/calls" 'hook first-boot'
  assert_file_has "$STUB_DIR/calls" 'hook post-up'
}

test_failing_hook_aborts_with_its_exit_code() {
  _hook pre-up 7
  run "$HP" up
  assert_rc 7
  assert_out 'hook pre-up failed'
  assert_file_lacks "$STUB_DIR/calls" ' up -d'
}

test_mode_unknown_without_terminal_fails_fast() {
  unset HELPOUPOU_MODE
  run "$HP" up
  assert_fails
  assert_out 'helpoupou mode dev'
}

test_mode_is_asked_once_then_remembered() {
  unset HELPOUPOU_MODE
  run_in '2\n' "$HP" doctor
  assert_out "remembered as 'prod'"
  run "$HP" mode
  assert_out 'prod'
}

test_menu_without_terminal_points_to_subcommands() {
  run "$HP"
  assert_fails
  assert_out 'helpoupou help'
}

test_prod_clean_refuses_without_terminal_even_with_yes() {
  run "$HP" --mode prod --yes clean
  assert_fails
  assert_file_lacks "$STUB_DIR/calls" 'down -v'
}

test_prod_clean_needs_the_project_name() {
  run_in 'yes\n' "$HP" --mode prod clean
  assert_fails
  assert_file_lacks "$STUB_DIR/calls" 'down -v'
  run_in 'myapp\n' "$HP" --mode prod clean
  assert_rc 0
  assert_file_has "$STUB_DIR/calls" 'down -v'
}

test_dev_clean_defaults_to_no() {
  run_in '\n' "$HP" clean
  assert_fails
  assert_file_lacks "$STUB_DIR/calls" 'down -v'
}

test_init_writes_config_and_shim() {
  rm helpoupou.conf
  printf 'services: {}\n' >compose.prod.yml
  run "$HP" --yes init
  assert_rc 0
  assert_file_has helpoupou.conf 'COMPOSE_DEV=compose.yml'
  assert_file_has helpoupou.conf 'COMPOSE_PROD=compose.yml compose.prod.yml'
  assert_file_has helpoupou.conf 'SECRETS=SECRET_KEY:64 POSTGRES_PASSWORD:32:db'
  assert_file_has .gitignore '.helpoupou/notify.conf'
  assert_file_has Makefile 'helpoupou --mode prod up'
  assert_file_has "$XDG_CONFIG_HOME/helpoupou/projects" "$T/proj"
}

test_init_never_overwrites_a_makefile_silently() {
  rm helpoupou.conf
  echo 'mine:' >Makefile
  run "$HP" --yes init
  assert_rc 0
  assert_eq "$(cat Makefile)" 'mine:'
}
