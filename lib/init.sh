# shellcheck shell=bash
# `helpoupou init`: detect what the project has and write helpoupou.conf.

_first_existing() {
  local f
  for f in "$@"; do
    if [ -f "$f" ]; then
      printf '%s' "$f"
      return 0
    fi
  done
}

# Proposes the secrets helpoupou can safely generate: framework secret keys
# and database passwords. Third-party credentials are never touched.
_detect_secrets() {
  local key out=''
  [ -f "$1" ] || return 0
  while IFS= read -r key; do
    case "$key" in
      *POSTGRES*PASSWORD* | *MYSQL*PASSWORD* | *MARIADB*PASSWORD* | DB_PASSWORD | *_DB_PASSWORD) out+="$key:32:db " ;;
      *SECRET_KEY*) out+="$key:64 " ;;
    esac
  done < <(grep -oE '^[A-Z_][A-Z0-9_]*=' "$1" | tr -d '=')
  printf '%s' "${out% }"
}

cmd_init() {
  local conf="$PWD/helpoupou.conf" name base devov prodf dev prod ex secrets overlay mk
  if [ -f "$conf" ] && [ "$FORCE" != 1 ]; then
    die "helpoupou.conf already exists here (use --force to rewrite it)"
  fi

  base=$(_first_existing compose.yml compose.yaml docker-compose.yml docker-compose.yaml)
  devov=$(_first_existing compose.dev.yml compose.dev.yaml docker-compose.dev.yml docker-compose.dev.yaml)
  prodf=$(_first_existing compose.prod.yml compose.prod.yaml docker-compose.prod.yml docker-compose.prod.yaml)
  [ -n "$base$prodf" ] || die "no compose file found in $PWD: helpoupou manages Docker Compose projects"

  h1 "helpoupou init"
  name=$(basename "$PWD" | tr -c 'A-Za-z0-9_.\n-' '-')
  ask name "Project name" "$name"
  [[ "$name" =~ ^[A-Za-z0-9][A-Za-z0-9_.-]*$ ]] || die "project name '$name' is invalid (letters, digits, _ . - only)"

  dev="$base${devov:+ $devov}"
  prod=$base
  if [ -n "$prodf" ]; then
    prod=$prodf
    if [ -n "$base" ]; then
      ask_yn overlay "Is $prodf applied ON TOP of $base? (no = it is a complete file on its own)" y
      if [ "$overlay" = y ]; then prod="$base $prodf"; fi
    fi
  fi
  [ -n "$dev" ] || dev=$prod

  ex=$(_first_existing .env.example .env.sample .env.dist)
  secrets=$(_detect_secrets "${ex:-.env.example}")

  cat >"$conf" <<EOF
# helpoupou project config. This file is parsed, never executed.
# Every key is documented in docs/CONFIG.md of the helpoupou repository.

PROJECT_NAME=$name

# Compose files per mode, space-separated.
COMPOSE_DEV=$dev
COMPOSE_PROD=$prod

ENV_FILE=.env
ENV_EXAMPLE=${ex:-.env.example}

# Secrets generated when empty or still at their example value: KEY:length.
# Add :db for a database password (never regenerated once DB_VOLUME exists).
SECRETS=$secrets

# Docker volume of the database: its absence means "first boot".
DB_VOLUME=

# Env variable holding the public hostname (prod refuses the example value).
DOMAIN_KEY=

# KEY=value pairs forced into the env file in prod, e.g. DEBUG=0
PROD_ENV_OVERRIDES=

# Printed after a start.
URLS_DEV=http://localhost
URLS_PROD=

SHELL_SERVICE=
LOG_SERVICE=
EOF
  ok "helpoupou.conf written"
  if [ -n "$secrets" ]; then note "secrets helpoupou will generate: $secrets"; fi
  note "review DB_VOLUME and DOMAIN_KEY in helpoupou.conf: they could not be detected"

  if ! grep -qxF '.helpoupou/notify.conf' .gitignore 2>/dev/null; then
    printf '%s\n' '.helpoupou/notify.conf' >>.gitignore
    ok ".helpoupou/notify.conf added to .gitignore"
  fi

  if [ -f Makefile ]; then
    ask_yn mk "A Makefile already exists. Replace it with the helpoupou shim? (kept as Makefile.bak)" n
    if [ "$mk" = y ]; then cp Makefile Makefile.bak; fi
  else
    ask_yn mk "Write a small Makefile so 'make dev' and 'make prod' call helpoupou?" y
  fi
  if [ "$mk" = y ]; then
    cp "$HELPOUPOU_ROOT/templates/Makefile" Makefile
    ok "Makefile written"
  fi

  registry_add "$PWD"
  printf '\n'
  ok "done. Next: run 'helpoupou' here to open the menu"
}
