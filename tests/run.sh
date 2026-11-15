#!/usr/bin/env bash
# Dependency-free test runner. Every test_* function of tests/test_*.sh runs
# in its own subshell and sandbox, with docker/curl/ss/... replaced by the
# doubles in tests/stubs: nothing real is contacted, no Docker is needed.
#
#   tests/run.sh            run everything
#   tests/run.sh notify     run the files whose name contains "notify"
set -uo pipefail

TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd "$TESTS_DIR/.." && pwd)
HP="$ROOT/bin/helpoupou"
export ROOT HP

OUT='' RC=0

sandbox() {
  T=$(mktemp -d)
  mkdir -p "$T/home" "$T/proj" "$T/stub"
  export HOME="$T/home" XDG_CONFIG_HOME="$T/cfg" XDG_STATE_HOME="$T/state"
  export STUB_DIR="$T/stub" PATH="$TESTS_DIR/stubs:$PATH"
  export HELPOUPOU_MODE=dev HELPOUPOU_NO_SLEEP=1 NO_COLOR=1 TERM=dumb
  export HELPOUPOU_MEMINFO="$T/meminfo" HELPOUPOU_REBOOT_FILE="$T/reboot-required"
  unset HELPOUPOU_YES HELPOUPOU_ASSUME_TTY HELPOUPOU_CONFIG_DIR HELPOUPOU_STATE_DIR SSH_CONNECTION
  meminfo 8000 4000 2000
  cd "$T/proj" || exit 1
  cat >helpoupou.conf <<'EOF'
PROJECT_NAME=myapp
COMPOSE_DEV=compose.yml
COMPOSE_PROD=compose.yml
SECRETS=SECRET_KEY:40 POSTGRES_PASSWORD:24:db
DB_VOLUME=myapp_pgdata
DOMAIN_KEY=SITE_HOST
PROD_ENV_OVERRIDES=DEBUG=0
URLS_DEV=http://localhost:8000
EOF
  printf 'services:\n  web:\n    image: example\n' >compose.yml
  printf 'SITE_HOST=example.com\nDEBUG=1\nSECRET_KEY=change-me\nPOSTGRES_PASSWORD=example\nAPI_TOKEN=\n' >.env.example
}

meminfo() { # total available swap, in MB
  printf 'MemTotal: %d kB\nMemAvailable: %d kB\nSwapTotal: %d kB\n' \
    $(($1 * 1024)) $(($2 * 1024)) $(($3 * 1024)) >"$HELPOUPOU_MEMINFO"
}

run() {
  OUT=$("$@" 2>&1 </dev/null)
  RC=$?
}

# run_in "stdin text" command...: as if a person typed the answers.
run_in() {
  local input=$1
  shift
  OUT=$(printf '%b' "$input" | HELPOUPOU_ASSUME_TTY=1 "$@" 2>&1)
  RC=$?
}

_fail() {
  printf '      %s\n' "$*"
  printf '      --- output (exit %s) ---\n' "$RC"
  printf '%s\n' "$OUT" | sed 's/^/      | /'
  exit 1
}

assert_rc() { [ "$RC" = "$1" ] || _fail "expected exit $1, got $RC"; }
assert_fails() { [ "$RC" != 0 ] || _fail "expected a failure, got exit 0"; }
assert_out() { [[ "$OUT" == *"$1"* ]] || _fail "output does not contain: $1"; }
assert_no_out() { [[ "$OUT" != *"$1"* ]] || _fail "output must not contain: $1"; }
assert_file_has() { grep -qF -- "$2" "$1" 2>/dev/null || _fail "$1 does not contain: $2"; }
assert_file_lacks() { ! grep -qF -- "$2" "$1" 2>/dev/null || _fail "$1 must not contain: $2"; }
assert_eq() { [ "$1" = "$2" ] || _fail "expected '$2', got '$1'"; }

pass=0 failed=0
for file in "$TESTS_DIR"/test_*.sh; do
  [[ "$file" == *"${1:-}"* ]] || continue
  printf '%s\n' "$(basename "$file")"
  # shellcheck source=/dev/null
  . "$file"
  for t in $(declare -F | awk '{ print $3 }' | grep '^test_'); do
    if (
      sandbox
      "$t"
    ); then
      pass=$((pass + 1))
      printf '  ok   %s\n' "$t"
    else
      failed=$((failed + 1))
      printf '  FAIL %s\n' "$t"
    fi
    unset -f "$t"
  done
done

printf '\n%d passed, %d failed\n' "$pass" "$failed"
[ "$failed" -eq 0 ]
