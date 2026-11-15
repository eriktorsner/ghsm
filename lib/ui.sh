# Terminal output. Skill commands call these helpers; they do not format data.

UI_RED=""
UI_GREEN=""
UI_YELLOW=""
UI_DIM=""
UI_RESET=""

# Preserve the real stderr so verbose lines stay visible when a caller
# captures a command's own stderr.
if [[ -z "${_GHSM_FD3:-}" ]]; then
  exec 3>&2
  _GHSM_FD3=1
fi

ui_configure_color() {
  local mode="${GHSM_COLOR:-auto}"
  local enable=0
  UI_RED=""
  UI_GREEN=""
  UI_YELLOW=""
  UI_DIM=""
  UI_RESET=""
  case "$mode" in
    always) enable=1 ;;
    never) enable=0 ;;
    *)
      if [[ -t 2 && -z "${NO_COLOR:-}" ]]; then
        enable=1
      fi
      ;;
  esac
  if [[ "$enable" -eq 1 ]]; then
    UI_RED=$'\033[31m'
    UI_GREEN=$'\033[32m'
    UI_YELLOW=$'\033[33m'
    UI_DIM=$'\033[2m'
    UI_RESET=$'\033[0m'
  fi
}

ui_json_mode() {
  [[ "${GHSM_JSON:-0}" == "1" ]]
}

ui_error() {
  printf '%sghsm:%s %s\n' "$UI_RED" "$UI_RESET" "$*" >&2
}

ui_warn() {
  printf '%sghsm:%s %s\n' "$UI_YELLOW" "$UI_RESET" "$*" >&2
}

ui_info() {
  if [[ "${GHSM_QUIET:-0}" == "1" ]]; then
    return 0
  fi
  printf '%s\n' "$*" >&2
}

ui_verbose() {
  if [[ "${GHSM_VERBOSE:-0}" != "1" ]]; then
    return 0
  fi
  printf '%s%s%s\n' "$UI_DIM" "$*" "$UI_RESET" >&3
}

# Collapse a multi-line command error into one short line for JSON and summaries.
ui_one_line() {
  local text="$1"
  text="$(printf '%s' "$text" | tr '\n' ' ' | sed 's/[[:space:]]\{1,\}/ /g; s/^ //; s/ $//')"
  if [[ ${#text} -gt 400 ]]; then
    text="${text:0:400}"
  fi
  printf '%s\n' "$text"
}
