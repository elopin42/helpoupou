# shellcheck shell=bash
# doctor: thresholds, skipped checks, production hygiene.

test_healthy_machine_passes() {
  run "$HP" env
  run "$HP" doctor
  assert_rc 0
  assert_out 'RAM: 4000 MB available'
  assert_out 'disk /: 50% used'
  assert_out 'all good'
}

test_low_ram_warns_and_names_the_culprits() {
  meminfo 8000 100 2000
  run "$HP" doctor
  assert_rc 0
  assert_out 'RAM is low: 100 MB'
  assert_out 'bigcontainer'
}

test_ram_threshold_comes_from_project_config() {
  echo 'RAM_MIN_MB=5000' >>helpoupou.conf
  run "$HP" doctor
  assert_out 'threshold 5000 MB'
}

test_no_swap_on_a_small_machine_warns() {
  meminfo 2000 1500 0
  run "$HP" doctor
  assert_out 'no swap'
}

test_disk_warns_then_fails() {
  echo 90 >"$STUB_DIR/disk-pct"
  run "$HP" doctor
  assert_rc 0
  assert_out 'filling up: 90%'
  echo 97 >"$STUB_DIR/disk-pct"
  run "$HP" doctor
  assert_fails
  assert_out 'is full: 97%'
}

test_full_disk_blocks_up_unless_forced() {
  echo 97 >"$STUB_DIR/disk-pct"
  run "$HP" up
  assert_fails
  assert_out '--force'
  assert_file_lacks "$STUB_DIR/calls" ' up -d'
  run "$HP" --force up
  assert_rc 0
  assert_file_has "$STUB_DIR/calls" ' up -d'
}

test_docker_down_fails_and_skips_dependent_checks() {
  touch "$STUB_DIR/docker-down"
  run "$HP" doctor
  assert_fails
  assert_out 'docker daemon not reachable'
  assert_out 'skipped: ports: docker is not available'
  assert_out 'RAM: 4000 MB'
}

_ports_config() {
  printf 'services:\n  web:\n    ports:\n      - mode: ingress\n        target: 80\n        published: "8080"\n' >"$STUB_DIR/compose-config"
  echo 8080 >"$STUB_DIR/ports"
}

test_port_held_by_another_container_fails() {
  _ports_config
  echo 'aaa111 otherproject-web-1' >"$STUB_DIR/port-holder"
  run "$HP" doctor
  assert_fails
  assert_out "port 8080 is already used by container 'otherproject-web-1'"
}

test_port_held_by_a_host_program_fails() {
  _ports_config
  run "$HP" doctor
  assert_fails
  assert_out 'port 8080 is already used by another program'
}

test_port_held_by_our_own_container_is_fine() {
  _ports_config
  echo 'aaa111 myapp-web-1' >"$STUB_DIR/port-holder"
  echo 'aaa111' >"$STUB_DIR/own-ids"
  run "$HP" doctor
  assert_rc 0
  assert_no_out 'port 8080'
}

_prod_env() {
  cp .env.example .env
  sed -i 's/^SITE_HOST=.*/SITE_HOST=app.example.org/' .env
  HELPOUPOU_MODE=prod run "$HP" env
  export HELPOUPOU_MODE=prod
}

test_prod_memory_limits_missing_and_oversubscribed() {
  _prod_env
  meminfo 1000 800 2000
  cat >"$STUB_DIR/compose-config" <<'EOF'
name: myapp
services:
  db:
    image: example
    mem_limit: "805306368"
  web:
    deploy:
      resources:
        limits:
          memory: "536870912"
        reservations:
          memory: "1"
    image: example
  worker:
    image: example
volumes:
  data: {}
EOF
  run "$HP" doctor
  assert_out 'without a memory limit'
  assert_out 'worker'
  assert_out 'add up to 1280 MB but this machine has 1000 MB'
}

test_prod_stale_secret_is_a_failure() {
  cp .env.example .env
  echo myapp_pgdata >"$STUB_DIR/volumes"
  HELPOUPOU_MODE=prod run "$HP" doctor
  assert_fails
  assert_out 'still at their example value in production:'
  assert_out 'POSTGRES_PASSWORD'
}

test_prod_hygiene_warnings() {
  _prod_env
  touch "$HELPOUPOU_REBOOT_FILE"
  echo 'myapp-backup.service loaded failed failed' >"$STUB_DIR/failed-units"
  echo 'passwordauthentication yes' >"$STUB_DIR/sshd"
  git init -q . && echo x >untracked.conf
  run "$HP" doctor
  assert_rc 0
  assert_out 'a reboot is pending'
  assert_out 'failed systemd unit(s): myapp-backup.service'
  assert_out 'SSH still accepts passwords'
  assert_out 'no SSH key in'
  assert_out 'uncommitted or untracked file(s) in the deployed checkout'
  assert_out 'no notification channel configured'
}

test_prod_ssh_settings_skipped_when_unreadable() {
  _prod_env
  run "$HP" doctor
  assert_out 'skipped: SSH settings'
}

test_dev_does_not_run_server_hygiene() {
  touch "$HELPOUPOU_REBOOT_FILE"
  run "$HP" doctor
  assert_no_out 'reboot'
  assert_no_out 'notification channel'
}
