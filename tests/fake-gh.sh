#!/usr/bin/env bash
# Test double for gh. Records argv and returns canned skill output.
set -euo pipefail

log="${GH_FAKE_LOG:-/dev/null}"
{
  printf 'CMD'
  local_i=0
  for arg in "$@"; do
    printf '\nARG %s' "$arg"
    local_i=$((local_i + 1))
  done
  printf '\nEND\n'
} >> "$log"

cmd=""
if [[ "${1:-}" == "skill" ]]; then
  cmd="${2:-}"
fi

for arg in "$@"; do
  if [[ -n "${GH_FAKE_FAIL_ON:-}" && "$arg" == "$GH_FAKE_FAIL_ON" ]]; then
    printf 'cannot install %s\n' "$arg" >&2
    exit 1
  fi
done

case "$cmd" in
  list)
    if [[ -n "${GH_FAKE_LIST:-}" && -f "$GH_FAKE_LIST" ]]; then
      cat "$GH_FAKE_LIST"
    else
      printf '[]\n'
    fi
    ;;
  install)
    dir=""
    prev=""
    for arg in "$@"; do
      if [[ "$prev" == "--dir" ]]; then
        dir="$arg"
      fi
      prev="$arg"
    done
    spec="${4:-}"
    name="${spec%%@*}"
    if [[ -n "$dir" && -n "$name" && "$name" != -* ]]; then
      mkdir -p "${dir}/${name}"
      printf '%s\n' '---' "name: ${name##*/}" '---' > "${dir}/${name}/SKILL.md"
    fi
    exit 0
    ;;
  update)
    if [[ -n "${GH_FAKE_UPDATE_OUTPUT:-}" ]]; then
      printf '%s\n' "$GH_FAKE_UPDATE_OUTPUT" >&2
    else
      printf '%s\n' "All skills are up to date." >&2
    fi
    exit "${GH_FAKE_UPDATE_CODE:-0}"
    ;;
  *)
    printf 'fake gh: unexpected command: %s\n' "$*" >&2
    exit 1
    ;;
esac
