# Release checks and self-update. Skill syncing lives in skills.sh.

# 0 when versions are equal, 1 when the first is newer, 2 when the second is newer.
upd_version_cmp() {
  local a b
  a="$(upd_normalize_version "$1")"
  b="$(upd_normalize_version "$2")"
  if [[ "$a" == "$b" ]]; then
    return 0
  fi
  local -a aa=() bb=()
  local i=0 len an bn
  IFS=. read -r -a aa <<< "$a"
  IFS=. read -r -a bb <<< "$b"
  len=${#aa[@]}
  if [[ ${#bb[@]} -gt "$len" ]]; then
    len=${#bb[@]}
  fi
  while [[ "$i" -lt "$len" ]]; do
    an=0
    bn=0
    if [[ "$i" -lt ${#aa[@]} ]]; then
      an="$(upd_numeric_component "${aa[$i]}")"
    fi
    if [[ "$i" -lt ${#bb[@]} ]]; then
      bn="$(upd_numeric_component "${bb[$i]}")"
    fi
    if [[ "$an" -gt "$bn" ]]; then
      return 1
    fi
    if [[ "$an" -lt "$bn" ]]; then
      return 2
    fi
    i=$((i + 1))
  done
  return 0
}

upd_normalize_version() {
  local v="$1"
  v="${v#v}"
  v="${v%%-*}"
  printf '%s\n' "$v"
}

# Bash 3.2 treats 010 as octal. Strip leading zeros before arithmetic.
upd_numeric_component() {
  local x="$1"
  if [[ ! "$x" =~ ^[0-9]+$ ]]; then
    printf '0\n'
    return 0
  fi
  while [[ "$x" == 0* && ${#x} -gt 1 ]]; do
    x="${x#0}"
  done
  printf '%s\n' "$x"
}

upd_cache_dir() {
  if [[ -n "${GHSM_CACHE_DIR:-}" ]]; then
    printf '%s\n' "${GHSM_CACHE_DIR}"
    return 0
  fi
  if [[ "$(uname -s)" == "Darwin" ]]; then
    printf '%s\n' "${HOME}/Library/Caches/ghsm"
  else
    printf '%s\n' "${XDG_CACHE_HOME:-${HOME}/.cache}/ghsm"
  fi
}

upd_cache_file() {
  printf '%s\n' "$(upd_cache_dir)/update-check.json"
}

upd_interval() {
  printf '%s\n' "${GHSM_UPDATE_INTERVAL:-86400}"
}

upd_failure_interval() {
  printf '%s\n' "${GHSM_UPDATE_FAILURE_INTERVAL:-3600}"
}

upd_latest_api_url() {
  printf '%s\n' "https://api.github.com/repos/${GHSM_REPO}/releases/latest"
}

# Prints the latest tag (for example v0.2.0) or returns non-zero.
upd_fetch_latest_tag() {
  local body tag
  body="$(util_mktemp_file)"
  util_http_get "$(upd_latest_api_url)" "$body" || return 1
  tag="$(jq -r '.tag_name // empty' "$body" 2>/dev/null || true)"
  if [[ -z "$tag" || "$tag" == "null" ]]; then
    return 1
  fi
  printf '%s\n' "$tag"
}

upd_write_cache() {
  local file="$1" ok="$2" latest="$3" available="$4"
  local dir tmp now
  dir="$(dirname "$file")"
  mkdir -p "$dir" || return 1
  now="$(date +%s)"
  tmp="$(mktemp "${dir}/update-check.XXXXXX")"
  jq -n \
    --argjson checked_at "$now" \
    --argjson ok "$ok" \
    --arg current "$GHSM_VERSION" \
    --arg latest "$latest" \
    --argjson update_available "$available" \
    '{checked_at:$checked_at, ok:$ok, current:$current, latest:$latest, update_available:$update_available}' \
    > "$tmp" || {
      rm -f "$tmp"
      return 1
    }
  mv "$tmp" "$file"
}

upd_refresh_cache() {
  local dir file lock
  if ! command -v jq >/dev/null 2>&1; then
    return 0
  fi
  if [[ -z "${GHSM_CURL:-}" ]] && ! command -v curl >/dev/null 2>&1; then
    return 0
  fi
  dir="$(upd_cache_dir)"
  mkdir -p "$dir" || return 0
  file="${dir}/update-check.json"
  lock="${dir}/update-check.lock"
  if ! util_acquire_lock_nowait "$lock"; then
    return 0
  fi
  upd_refresh_cache_locked "$file" || true
  util_release_lock
  return 0
}

upd_refresh_cache_locked() {
  local file="$1" tag latest cmp available
  if ! tag="$(upd_fetch_latest_tag)"; then
    upd_write_cache "$file" false "" false || true
    return 0
  fi
  latest="$(upd_normalize_version "$tag")"
  available=false
  cmp=0
  upd_version_cmp "$latest" "$GHSM_VERSION" || cmp=$?
  if [[ "$cmp" -eq 1 ]]; then
    available=true
  fi
  upd_write_cache "$file" true "$latest" "$available" || true
  return 0
}

upd_cache_is_fresh() {
  local file="$1"
  local checked ok current now age interval
  [[ -f "$file" ]] || return 1
  checked="$(jq -r '.checked_at // empty' "$file" 2>/dev/null || true)"
  ok="$(jq -r '.ok // empty' "$file" 2>/dev/null || true)"
  current="$(jq -r '.current // empty' "$file" 2>/dev/null || true)"
  [[ "$checked" =~ ^[0-9]+$ ]] || return 1
  [[ "$current" == "$GHSM_VERSION" ]] || return 1
  now="$(date +%s)"
  age=$((now - checked))
  if [[ "$ok" == "true" ]]; then
    interval="$(upd_interval)"
  else
    interval="$(upd_failure_interval)"
  fi
  [[ "$age" -lt "$interval" ]]
}

upd_notify_from_cache() {
  local file="$1"
  local ok available latest
  [[ "${GHSM_QUIET:-0}" == "1" ]] && return 0
  [[ -f "$file" ]] || return 0
  ok="$(jq -r '.ok // empty' "$file" 2>/dev/null || true)"
  available="$(jq -r '.update_available // empty' "$file" 2>/dev/null || true)"
  latest="$(jq -r '.latest // empty' "$file" 2>/dev/null || true)"
  if [[ "$ok" == "true" && "$available" == "true" && -n "$latest" && "$latest" != "$GHSM_VERSION" ]]; then
    printf 'ghsm %s is available (you have %s). Run: ghsm self-update\n' \
      "$latest" "$GHSM_VERSION" >&2
  fi
}

upd_spawn_refresh() {
  local bash_bin="${BASH:-/bin/bash}"
  local script="${GHSM_ROOT}/lib/refresh.sh"
  [[ -f "$script" ]] || return 0
  nohup "$bash_bin" "$script" </dev/null >/dev/null 2>&1 &
  disown "$!" 2>/dev/null || true
  return 0
}

upd_maybe_notify() {
  local file
  if [[ "${GHSM_NO_UPDATE_CHECK:-}" == "1" ]]; then
    return 0
  fi
  file="$(upd_cache_file)"
  if upd_cache_is_fresh "$file"; then
    upd_notify_from_cache "$file" || true
    return 0
  fi
  if [[ -f "$file" ]]; then
    upd_notify_from_cache "$file" || true
  fi
  upd_spawn_refresh || true
  return 0
}

upd_print_check() {
  local tag latest cmp available
  if ! tag="$(upd_fetch_latest_tag)"; then
    ui_error "could not read the latest ghsm release from GitHub"
    return 1
  fi
  latest="$(upd_normalize_version "$tag")"
  available=false
  cmp=0
  upd_version_cmp "$latest" "$GHSM_VERSION" || cmp=$?
  if [[ "$cmp" -eq 1 ]]; then
    available=true
  fi
  if ui_json_mode; then
    jq -nc \
      --arg current "$GHSM_VERSION" \
      --arg latest "$latest" \
      --argjson update_available "$available" \
      '{current:$current, latest:$latest, update_available:$update_available}'
  elif [[ "$available" == true ]]; then
    printf 'ghsm %s is available (you have %s)\n' "$latest" "$GHSM_VERSION"
  else
    printf 'ghsm %s is up to date\n' "$GHSM_VERSION"
  fi
  return 0
}

upd_cmd_self_update() {
  local check=0 force=0 prefix=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help)
        cli_help_self_update
        return 0
        ;;
      --check) check=1; shift ;;
      --force) force=1; shift ;;
      --prefix)
        if [[ $# -lt 2 ]]; then
          ui_error "--prefix requires a directory"
          return 2
        fi
        prefix="$2"
        shift 2
        ;;
      *)
        ui_error "unknown argument for self-update: $1"
        return 2
        ;;
    esac
  done
  if [[ "$check" -eq 1 && "$force" -eq 1 ]]; then
    ui_error "use either --check or --force"
    return 2
  fi
  if [[ "$check" -eq 1 ]]; then
    upd_print_check
    return
  fi
  local installer="${GHSM_ROOT}/install.sh"
  if [[ ! -f "$installer" ]]; then
    ui_error "installer not found at ${installer}"
    return 1
  fi
  local -a args=(--version latest)
  if [[ -n "$prefix" ]]; then
    args+=(--prefix "$prefix")
  elif [[ -n "${GHSM_PREFIX:-}" ]]; then
    args+=(--prefix "$GHSM_PREFIX")
  fi
  if [[ "$force" -eq 1 ]]; then
    args+=(--force)
  fi
  "${BASH:-/bin/bash}" "$installer" ${args[@]+"${args[@]}"}
}
