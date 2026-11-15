# Runtime prerequisites. gh may be replaced in tests via GHSM_GH.

deps_require() {
  local missing=0
  if [[ -z "${GHSM_GH:-}" ]] && ! command -v gh >/dev/null 2>&1; then
    ui_error "GitHub CLI (gh) is required. Install it from https://cli.github.com/"
    missing=1
  fi
  if ! command -v jq >/dev/null 2>&1; then
    ui_error "jq is required. Install it with your system package manager."
    missing=1
  fi
  if [[ "$missing" -ne 0 ]]; then
    exit 3
  fi
}
