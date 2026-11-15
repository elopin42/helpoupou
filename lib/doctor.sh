# shellcheck shell=bash
# doctor: a list of small independent checks. Each one reports through `dr`
# and returns; a check that cannot run reports "skip" with the reason. Checks
# are called with `|| true`, so an unexpected error in one never stops the
# report (that is why this file does not rely on `set -e`).

DR_QUIET=0
DR_WARN=0
DR_FAIL=0
DOCKER_OK=0

dr() {
  local kind=$1
  shift
  case "$kind" in
    ok) [ "$DR_QUIET" = 1 ] || ok "$*" ;;
    skip) [ "$DR_QUIET" = 1 ] || note "- skipped: $*" ;;
    info) [ "$DR_QUIET" = 1 ] || note "  $*" ;;
    warn)
      DR_WARN=$((DR_WARN + 1))
      warn "$*"
      ;;
    fail)
      DR_FAIL=$((DR_FAIL + 1))
      fail "$*"
      ;;
  esac
}

_meminfo_mb() {
  awk -v k="$1:" '$1 == k { print int($2 / 1024) }' "${HELPOUPOU_MEMINFO:-/proc/meminfo}" 2>/dev/null
}

_threshold() { # _threshold CONFIG_KEY ENV_VALUE DEFAULT
  local v=${CFG[$1]:-${2:-$3}}
  [[ "$v" =~ ^[0-9]+$ ]] || v=$3
  printf '%s' "$v"
}

# ---- machine ----------------------------------------------------------------

check_docker() {
  DOCKER_OK=0
  command -v docker >/dev/null 2>&1 || {
    dr fail "docker is not installed"
    return
  }
  docker compose version >/dev/null 2>&1 || {
    dr fail "the docker compose v2 plugin is missing"
    return
  }
  docker info >/dev/null 2>&1 || {
    dr fail "docker daemon not reachable by $(id -un) (is it running? is the user in the docker group?)"
    return
  }
  DOCKER_OK=1
  dr ok "docker and compose are available"
}

check_ram() {
  local avail min dir
  avail=$(_meminfo_mb MemAvailable)
  [ -n "$avail" ] || {
    dr skip "RAM: cannot read memory information"
    return
  }
  min=$(_threshold RAM_MIN_MB "${HELPOUPOU_RAM_MIN_MB:-}" 400)
  if [ "$avail" -ge "$min" ]; then
    dr ok "RAM: $avail MB available"
    return
  fi
  dr warn "RAM is low: $avail MB available (threshold $min MB)"
  [ "$DOCKER_OK" = 1 ] || return
  note "biggest containers right now:"
  docker stats --no-stream --format '{{.MemPerc}}\t{{.Name}}\t{{.MemUsage}}' 2>/dev/null |
    sort -rn | head -5 | awk -F'\t' '{ printf "      %-32s %s\n", $2, $3 }'
  while IFS= read -r dir; do
    if [ -n "$(docker ps -q --filter "label=com.docker.compose.project.working_dir=$dir" 2>/dev/null)" ]; then
      note "running helpoupou project: $dir  (stop it with: helpoupou -C $dir down)"
    fi
  done < <(registry_list)
}

check_swap() {
  local total swap
  total=$(_meminfo_mb MemTotal)
  swap=$(_meminfo_mb SwapTotal)
  [ -n "$total" ] || return
  if [ "$total" -lt 4000 ] && [ "${swap:-0}" -eq 0 ]; then
    dr warn "no swap and only $total MB of RAM: one memory spike can kill a service"
  fi
}

_disk_pct() { df --output=pcent "$1" 2>/dev/null | tail -1 | tr -dc '0-9'; }

_check_disk_path() {
  local label=$1 path=$2 pct warnp
  pct=$(_disk_pct "$path")
  [ -n "$pct" ] || {
    dr skip "disk: cannot read usage of $path"
    return
  }
  warnp=$(_threshold DISK_WARN_PCT "${HELPOUPOU_DISK_WARN_PCT:-}" 85)
  if [ "$pct" -ge 95 ]; then
    dr fail "disk $label is full: $pct% used"
  elif [ "$pct" -ge "$warnp" ]; then
    dr warn "disk $label is filling up: $pct% used (threshold $warnp%)"
  else
    dr ok "disk $label: $pct% used"
  fi
}

check_disk() {
  local root line
  _check_disk_path / /
  [ "$DOCKER_OK" = 1 ] || return
  root=$(docker info --format '{{.DockerRootDir}}' 2>/dev/null)
  if [ -n "$root" ] && [ -d "$root" ] &&
    [ "$(df --output=source "$root" 2>/dev/null | tail -1)" != "$(df --output=source / 2>/dev/null | tail -1)" ]; then
    _check_disk_path "$root" "$root"
  fi
  [ "$DR_QUIET" = 1 ] && return
  while IFS= read -r line; do
    dr info "docker reclaimable - $line"
  done < <(docker system df --format '{{.Type}}: {{.Reclaimable}}' 2>/dev/null)
  dr info "free it with: docker system prune (add -a for unused images)"
}

# ---- project ----------------------------------------------------------------

check_env() {
  local envf ex stale n
  envf=$(cfg ENV_FILE .env)
  ex=$(cfg ENV_EXAMPLE .env.example)
  if [ ! -f "$envf" ]; then
    if [ -f "$ex" ]; then
      dr warn "$envf does not exist yet (created by: helpoupou up)"
    fi
    return
  fi
  n=$(env_missing_keys | wc -l)
  if [ "$n" -gt 0 ]; then
    dr warn "$n key(s) of $ex are missing from $envf (see: helpoupou env check)"
  fi
  stale=$(env_stale_secrets | tr '\n' ' ')
  if [ "$MODE" = prod ]; then
    if [ "$(stat -c %a "$envf" 2>/dev/null)" != 600 ]; then
      dr warn "$envf is readable by others (fix: chmod 600 $envf)"
    fi
    if [ -n "$stale" ]; then
      dr fail "secrets empty or still at their example value in production: $stale"
      return
    fi
  elif [ -n "$stale" ]; then
    dr warn "secrets not generated yet: $stale(run: helpoupou env)"
    return
  fi
  dr ok "$envf looks complete"
}

check_ports() {
  local conf bound own port holder
  [ "$DOCKER_OK" = 1 ] || {
    dr skip "ports: docker is not available"
    return
  }
  command -v ss >/dev/null 2>&1 || {
    dr skip "ports: 'ss' is not installed (package iproute2)"
    return
  }
  conf=$("${DC[@]}" config 2>/dev/null) || {
    dr skip "ports: the compose configuration is not valid yet"
    return
  }
  bound=$(ss -ltnH 2>/dev/null | awk '{ n = split($4, a, ":"); print a[n] }' | sort -u)
  own=$("${DC[@]}" ps -q 2>/dev/null)
  while IFS= read -r port; do
    [ -n "$port" ] || continue
    grep -qx "$port" <<<"$bound" || continue
    holder=$(docker ps --no-trunc --filter "publish=$port" --format '{{.ID}} {{.Names}}' 2>/dev/null | head -1)
    if [ -n "$holder" ] && grep -qx "${holder%% *}" <<<"$own"; then continue; fi
    if [ -n "$holder" ]; then
      dr fail "port $port is already used by container '${holder#* }'"
    else
      dr fail "port $port is already used by another program (see: sudo ss -ltnp | grep :$port)"
    fi
  done < <(grep -oE 'published: "?[0-9]+' <<<"$conf" | tr -dc '0-9\n' | sort -u)
}

# Prints "service limit" per service ("-" when none) from `compose config`.
_compose_mem_limits() {
  awk '
    /^services:/ { insvc = 1; next }
    /^[^ #]/ { insvc = 0 }
    !insvc { next }
    /^  [^ ]+:[ ]*$/ { if (svc != "") print svc, lim; svc = $1; sub(/:$/, "", svc); lim = "-"; inlim = 0; next }
    /^    mem_limit:/ { v = $2; gsub(/"/, "", v); lim = v; next }
    /^        limits:/ { inlim = 1; next }
    /^        [^ ]/ { inlim = 0 }
    inlim && /^          memory:/ { v = $2; gsub(/"/, "", v); lim = v }
    END { if (svc != "") print svc, lim }
  '
}

check_mem_limits() {
  local conf svc lim mb sum=0 total nolimit=''
  [ "$DOCKER_OK" = 1 ] || return
  conf=$("${DC[@]}" config 2>/dev/null) || return
  while read -r svc lim; do
    [ -n "$svc" ] || continue
    mb=$(to_mb "$lim")
    if [ -z "$mb" ] || [ "$mb" -eq 0 ]; then
      nolimit+="$svc "
    else
      sum=$((sum + mb))
    fi
  done < <(_compose_mem_limits <<<"$conf")
  total=$(_meminfo_mb MemTotal)
  if [ -n "$nolimit" ]; then
    dr warn "services without a memory limit (one leak can take the whole server down): $nolimit"
  fi
  if [ -n "$total" ] && [ "$sum" -gt "$total" ]; then
    dr warn "memory limits add up to $sum MB but this machine has $total MB"
  elif [ "$sum" -gt 0 ]; then
    dr ok "memory limits add up to $sum MB, this machine has $total MB"
  fi
}

# ---- production hygiene -----------------------------------------------------

check_git() {
  local changes n
  git rev-parse --git-dir >/dev/null 2>&1 || return
  changes=$(git status --porcelain 2>/dev/null)
  [ -n "$changes" ] || {
    dr ok "deployed checkout matches git"
    return
  }
  n=$(wc -l <<<"$changes")
  dr warn "$n uncommitted or untracked file(s) in the deployed checkout: deployment config living outside git is lost on the next checkout"
  head -5 <<<"$changes" | sed 's/^/      /' >&2
}

check_reboot() {
  if [ -f "${HELPOUPOU_REBOOT_FILE:-/var/run/reboot-required}" ]; then
    dr warn "a reboot is pending (kernel or library update installed)"
  fi
}

check_units() {
  local failed
  command -v systemctl >/dev/null 2>&1 || {
    dr skip "systemd units: systemctl not available"
    return
  }
  failed=$(systemctl --failed --no-legend --plain 2>/dev/null | awk 'NF { print $1 }' | tr '\n' ' ')
  if [ -n "$failed" ]; then
    dr warn "failed systemd unit(s): $failed"
  else
    dr ok "no failed systemd unit"
  fi
}

check_ssh() {
  local out keys=0 file="$HOME/.ssh/authorized_keys"
  if [ -f "$file" ]; then keys=$(grep -cvE '^[[:space:]]*(#|$)' "$file" || true); fi
  if [ "$keys" -eq 0 ]; then
    dr warn "no SSH key in $file: this account can only be reached with a password"
  elif [ "$keys" -eq 1 ]; then
    dr warn "only one SSH key in $file: lose it and you are locked out (add a backup: helpoupou key push)"
  fi
  if _ssh_rollback_pending; then
    dr warn "SSH hardening is not confirmed and will be undone: log in from a new terminal and run 'helpoupou ssh confirm'"
  fi
  out=$(PATH="$PATH:/usr/sbin:/sbin" sshd -T 2>/dev/null || sudo -n sshd -T 2>/dev/null || true)
  if [ -z "$out" ]; then
    dr skip "SSH settings: cannot read the sshd configuration (needs root)"
    return
  fi
  if grep -qi '^passwordauthentication yes' <<<"$out"; then
    dr warn "SSH still accepts passwords (once your keys are installed: helpoupou ssh harden)"
  else
    dr ok "SSH accepts keys only"
  fi
}

check_notify() {
  local ch state
  notify_load
  if [ "${#NCH_NAMES[@]}" -eq 0 ]; then
    dr warn "no notification channel configured: alerts would reach nobody (run: helpoupou notify setup)"
    return
  fi
  for ch in "${NCH_NAMES[@]}"; do
    state=$(cat "$STATE_DIR/notify/$ch" 2>/dev/null || true)
    case "$state" in
      *' fail') dr warn "notification channel '$ch': the last delivery FAILED (run: helpoupou notify test $ch)" ;;
      *' ok') dr ok "notification channel '$ch': last delivery ok" ;;
      *) dr warn "notification channel '$ch' has never been used (run: helpoupou notify test $ch)" ;;
    esac
  done
}

# ---- runner -----------------------------------------------------------------

# Returns 1 when at least one check failed.
doctor_run() {
  local c
  local -a checks=(check_docker check_ram check_swap check_disk)
  DR_WARN=0 DR_FAIL=0
  if [ -n "$PROJECT_DIR" ]; then
    [ "${#DC[@]}" -gt 0 ] || compose_prepare
    checks+=(check_env check_ports)
    if [ "$MODE" = prod ]; then checks+=(check_mem_limits check_git); fi
  fi
  if [ "$MODE" = prod ]; then checks+=(check_reboot check_units check_ssh check_notify); fi

  [ "$DR_QUIET" = 1 ] || h1 "doctor - ${CFG[PROJECT_NAME]:-this machine} ($MODE)"
  for c in "${checks[@]}"; do "$c" || true; done
  if [ "$DR_QUIET" != 1 ]; then
    printf '\n'
    if [ "$DR_FAIL" -gt 0 ]; then
      fail "$DR_FAIL failure(s), $DR_WARN warning(s)"
    elif [ "$DR_WARN" -gt 0 ]; then
      warn "$DR_WARN warning(s), no failure"
    else
      ok "all good"
    fi
  fi
  [ "$DR_FAIL" -eq 0 ]
}
