# shellcheck shell=bash
# Env file handling: read/write single keys, generate secrets, prod guards.
# Values are never printed; messages name keys only.

# env_get FILE KEY: raw value of the first KEY= line (empty if absent).
env_get() {
  [ -f "$1" ] || return 0
  local line
  line=$(grep -m1 -E "^$2=" "$1" || true)
  line=${line#*=}
  printf '%s' "${line%$'\r'}"
}

env_has() { [ -f "$1" ] && grep -q -E "^$2=" "$1"; }

# env_set FILE KEY VALUE: replace the KEY line in place, or append it. The
# value travels through the environment, not argv, and is written verbatim.
env_set() {
  local file=$1 tmp
  tmp=$(mktemp "${file}.XXXXXX")
  chmod 600 "$tmp"
  K=$2 V=$3 awk '
    BEGIN { k = ENVIRON["K"]; v = ENVIRON["V"]; done = 0 }
    index($0, k "=") == 1 && !done { print k "=" v; done = 1; next }
    { print }
    END { if (!done) print k "=" v }
  ' "$file" >"$tmp"
  mv "$tmp" "$file"
}

unquote() {
  local v=$1
  case "$v" in
    \"*\") v=${v#\"} v=${v%\"} ;;
    \'*\') v=${v#\'} v=${v%\'} ;;
  esac
  printf '%s' "$v"
}

# rand_string LENGTH: [A-Za-z0-9] only, safe in a DSN, a shell and an env file.
rand_string() {
  local out=''
  while [ "${#out}" -lt "$1" ]; do
    out+=$(openssl rand -base64 48 | tr -dc 'A-Za-z0-9')
  done
  printf '%s' "${out:0:$1}"
}

volume_exists() { [ -n "$1" ] && docker volume inspect "$1" >/dev/null 2>&1; }

# A secret needs generating when it is empty or still the example's value.
_secret_is_stale() {
  local cur ex
  cur=$(env_get "$1" "$3")
  ex=$(env_get "$2" "$3")
  [ -z "$cur" ] || { [ -n "$ex" ] && [ "$cur" = "$ex" ]; }
}

env_generate_secrets() {
  local envf=$1 ex=$2 entry key len flag vol
  local -a entries=()
  vol=$(cfg DB_VOLUME)
  read -ra entries <<<"$(cfg SECRETS)"
  for entry in "${entries[@]+"${entries[@]}"}"; do
    IFS=: read -r key len flag <<<"$entry"
    [[ "$key" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] && [[ "$len" =~ ^[0-9]+$ ]] ||
      die "SECRETS entry '$entry' is invalid (expected KEY:length or KEY:length:db)"
    _secret_is_stale "$envf" "$ex" "$key" || continue
    if [ "$flag" = db ] && volume_exists "$vol"; then
      warn "$key is empty or still the example value, but the database volume '$vol' already exists: not regenerated (it would lock the app out of its data)"
      continue
    fi
    env_set "$envf" "$key" "$(rand_string "$len")"
    ok "$key generated"
  done
}

env_apply_prod_overrides() {
  local envf=$1 pair
  local -a pairs=()
  read -ra pairs <<<"$(cfg PROD_ENV_OVERRIDES)"
  for pair in "${pairs[@]+"${pairs[@]}"}"; do
    [[ "$pair" == *=* ]] || die "PROD_ENV_OVERRIDES entry '$pair' is invalid (expected KEY=value)"
    [ "$(env_get "$envf" "${pair%%=*}")" = "${pair#*=}" ] && continue
    env_set "$envf" "${pair%%=*}" "${pair#*=}"
    ok "${pair%%=*} forced for production"
  done
}

# Creates the env file from the example if needed, locks its mode, generates
# secrets, and in prod applies the forced values. Safe to re-run.
env_bootstrap() {
  local envf ex
  envf=$(cfg ENV_FILE .env)
  ex=$(cfg ENV_EXAMPLE .env.example)
  if [ ! -f "$envf" ]; then
    if [ -f "$ex" ]; then
      cp "$ex" "$envf"
      ok "$envf created from $ex"
    elif [ -n "$(cfg SECRETS)$(cfg PROD_ENV_OVERRIDES)" ]; then
      : >"$envf"
      ok "$envf created (empty: no $ex found)"
    else
      return 0
    fi
  fi
  chmod 600 "$envf"
  env_generate_secrets "$envf" "$ex"
  if [ "$MODE" = prod ]; then env_apply_prod_overrides "$envf"; fi
}

# Production must never start on the hostname copied from the example file.
env_domain_guard() {
  local key envf ex host tmpl
  key=$(cfg DOMAIN_KEY)
  [ -n "$key" ] || return 0
  [ "${HELPOUPOU_ALLOW_TEMPLATE_DOMAIN:-0}" = 1 ] && return 0
  envf=$(cfg ENV_FILE .env)
  ex=$(cfg ENV_EXAMPLE .env.example)
  host=$(unquote "$(env_get "$envf" "$key")")
  tmpl=$(unquote "$(env_get "$ex" "$key")")
  [ -n "$host" ] ||
    die "$key is empty in $envf: set the public hostname before starting production."
  if [ -n "$tmpl" ] && [ "$host" = "$tmpl" ]; then
    die "$key in $envf is still the example value: set the real public hostname (override: HELPOUPOU_ALLOW_TEMPLATE_DOMAIN=1)."
  fi
}

# Prints the names of secrets still stale. Returns 0 when there is none.
env_stale_secrets() {
  local envf ex entry found=1
  local -a entries=()
  envf=$(cfg ENV_FILE .env)
  ex=$(cfg ENV_EXAMPLE .env.example)
  read -ra entries <<<"$(cfg SECRETS)"
  for entry in "${entries[@]+"${entries[@]}"}"; do
    if _secret_is_stale "$envf" "$ex" "${entry%%:*}"; then
      printf '%s\n' "${entry%%:*}"
      found=0
    fi
  done
  return $((1 - found))
}

# Prints the keys present in the example but absent from the env file.
env_missing_keys() {
  local envf ex key
  envf=$(cfg ENV_FILE .env)
  ex=$(cfg ENV_EXAMPLE .env.example)
  [ -f "$ex" ] || return 0
  while IFS= read -r key; do
    env_has "$envf" "$key" || printf '%s\n' "$key"
  done < <(grep -oE '^[A-Za-z_][A-Za-z0-9_]*=' "$ex" | tr -d '=')
}

cmd_env() {
  case "${1:-}" in
    '') env_bootstrap ;;
    check)
      # shellcheck disable=SC2086 # key names are split into one line each on purpose
      local envf missing stale rc=0
      envf=$(cfg ENV_FILE .env)
      [ -f "$envf" ] || die "$envf does not exist yet (run: helpoupou env)"
      missing=$(env_missing_keys)
      stale=$(env_stale_secrets || true)
      if [ -n "$missing" ]; then
        warn "keys in the example but missing from $envf:"
        printf '      %s\n' $missing
        rc=1
      fi
      if [ -n "$stale" ]; then
        warn "secrets empty or still at their example value:"
        printf '      %s\n' $stale
        rc=1
      fi
      [ "$rc" = 0 ] && ok "$envf is complete"
      return "$rc"
      ;;
    *) die "unknown: env $1 (expected nothing or 'check')" ;;
  esac
}
