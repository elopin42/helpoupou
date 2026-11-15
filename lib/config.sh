# shellcheck shell=bash
# Project config: helpoupou.conf is PARSED, never sourced. Nothing in it is
# ever executed or expanded.

CONFIG_KEYS=" PROJECT_NAME COMPOSE_DEV COMPOSE_PROD COMPOSE_DEV_PROFILES COMPOSE_PROD_PROFILES ENV_FILE ENV_EXAMPLE SECRETS DB_VOLUME DOMAIN_KEY PROD_ENV_OVERRIDES URLS_DEV URLS_PROD SHELL_SERVICE LOG_SERVICE RAM_MIN_MB DISK_WARN_PCT "

declare -gA CFG=()

find_project_dir() {
  local d=${1:-$PWD}
  while :; do
    if [ -f "$d/helpoupou.conf" ]; then
      printf '%s' "$d"
      return 0
    fi
    [ "$d" = / ] && return 1
    d=$(dirname "$d")
  done
}

config_load() {
  local file=$1 line key val n=0
  local re_skip='^[[:space:]]*(#.*)?$'
  local re_kv='^[[:space:]]*([A-Z_][A-Z0-9_]*)[[:space:]]*=[[:space:]]*(.*)$'
  CFG=()
  while IFS= read -r line || [ -n "$line" ]; do
    n=$((n + 1))
    line=${line%$'\r'}
    [[ "$line" =~ $re_skip ]] && continue
    if [[ "$line" =~ $re_kv ]]; then
      key=${BASH_REMATCH[1]}
      val=${BASH_REMATCH[2]}
      val=${val%"${val##*[![:space:]]}"}
      case "$val" in
        \"*\") val=${val#\"} val=${val%\"} ;;
        \'*\') val=${val#\'} val=${val%\'} ;;
      esac
      if [[ "$CONFIG_KEYS" == *" $key "* ]]; then
        CFG[$key]=$val
      else
        warn "helpoupou.conf:$n: unknown key '$key' ignored"
      fi
    else
      warn "helpoupou.conf:$n: line ignored (expected KEY=value)"
    fi
  done <"$file"
}

cfg() { printf '%s' "${CFG[$1]:-${2:-}}"; }

_project_load() {
  PROJECT_DIR=$1
  cd "$PROJECT_DIR"
  config_load "$PROJECT_DIR/helpoupou.conf"
  [ -n "${CFG[PROJECT_NAME]:-}" ] || CFG[PROJECT_NAME]=$(basename "$PROJECT_DIR")
  [[ "${CFG[PROJECT_NAME]}" =~ ^[A-Za-z0-9][A-Za-z0-9_.-]*$ ]] ||
    die "PROJECT_NAME '${CFG[PROJECT_NAME]}' is invalid (letters, digits, _ . - only)"
}

project_require() {
  local d
  d=$(find_project_dir) ||
    die "no helpoupou.conf here or in a parent directory. Run 'helpoupou init' in your project."
  _project_load "$d"
}

project_load_optional() {
  local d
  if d=$(find_project_dir); then _project_load "$d"; fi
}
