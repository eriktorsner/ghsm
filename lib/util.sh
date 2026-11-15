# Filesystem, process, and HTTP helpers shared by the CLI. No skill policy.

if [[ -z "${_GHSM_UTIL_READY:-}" ]]; then
  _GHSM_UTIL_READY=1
  UTIL_TMP_FILES=()
  UTIL_HELD_LOCK=""
fi

: "${GHSM_REPO:=eriktorsner/ghsm}"

util_cleanup() {
  local item
  for item in ${UTIL_TMP_FILES[@]+"${UTIL_TMP_FILES[@]}"}; do
    rm -f "$item"
  done
  if [[ -n "${UTIL_HELD_LOCK:-}" ]]; then
    rmdir "$UTIL_HELD_LOCK" 2>/dev/null || true
    UTIL_HELD_LOCK=""
  fi
  return 0
}

util_mktemp_file() {
  local f
  f="$(mktemp "${TMPDIR:-/tmp}/ghsm.XXXXXX")"
  UTIL_TMP_FILES+=("$f")
  printf '%s\n' "$f"
}

util_mtime() {
  local target="$1" m
  if m="$(stat -f %m "$target" 2>/dev/null)"; then
    printf '%s\n' "$m"
    return 0
  fi
  if m="$(stat -c %Y "$target" 2>/dev/null)"; then
    printf '%s\n' "$m"
    return 0
  fi
  return 1
}

# Acquire a mkdir-based lock. Waits briefly, and breaks a lock older than 30s.
util_acquire_lock() {
  local lock="$1"
  local now m i=0
  while true; do
    if mkdir "$lock" 2>/dev/null; then
      UTIL_HELD_LOCK="$lock"
      return 0
    fi
    m="$(util_mtime "$lock" 2>/dev/null || true)"
    if [[ -n "$m" ]]; then
      now="$(date +%s)"
      if [[ "$((now - m))" -gt 30 ]]; then
        rmdir "$lock" 2>/dev/null || true
        continue
      fi
    fi
    i=$((i + 1))
    if [[ "$i" -gt 50 ]]; then
      return 1
    fi
    sleep 0.1
  done
}

util_acquire_lock_nowait() {
  local lock="$1"
  local now m
  if mkdir "$lock" 2>/dev/null; then
    UTIL_HELD_LOCK="$lock"
    return 0
  fi
  m="$(util_mtime "$lock" 2>/dev/null || true)"
  if [[ -n "$m" ]]; then
    now="$(date +%s)"
    if [[ "$((now - m))" -gt 120 ]]; then
      rmdir "$lock" 2>/dev/null || true
      if mkdir "$lock" 2>/dev/null; then
        UTIL_HELD_LOCK="$lock"
        return 0
      fi
    fi
  fi
  return 1
}

util_release_lock() {
  if [[ -n "${UTIL_HELD_LOCK:-}" ]]; then
    rmdir "$UTIL_HELD_LOCK" 2>/dev/null || true
    UTIL_HELD_LOCK=""
  fi
}

util_project_root() {
  local dir=""
  if [[ -n "${GHSM_PROJECT_ROOT:-}" ]]; then
    dir="${GHSM_PROJECT_ROOT}"
  else
    if command -v git >/dev/null 2>&1; then
      dir="$(git rev-parse --show-toplevel 2>/dev/null || true)"
    fi
    if [[ -z "$dir" ]]; then
      dir="$(pwd)"
    fi
  fi
  (cd "$dir" && pwd)
}

util_http_get() {
  local url="$1" dest="$2"
  if [[ -n "${GHSM_CURL:-}" ]]; then
    "$GHSM_CURL" "$url" "$dest"
    return
  fi
  command curl -fsSL --retry 3 --retry-delay 1 --max-time "${GHSM_HTTP_TIMEOUT:-20}" \
    -A "ghsm/${GHSM_VERSION}" \
    -H "Accept: application/vnd.github+json" \
    -o "$dest" \
    "$url"
}
