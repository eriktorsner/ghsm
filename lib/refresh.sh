#!/usr/bin/env bash
# Detached release check. The CLI starts this and does not wait for it.
set -euo pipefail

source="${BASH_SOURCE[0]}"
root="$(cd "$(dirname "$source")/.." && pwd)"

# shellcheck disable=SC1091
source "${root}/lib/version.sh"
# shellcheck disable=SC1091
source "${root}/lib/ui.sh"
# shellcheck disable=SC1091
source "${root}/lib/util.sh"
# shellcheck disable=SC1091
source "${root}/lib/self_update.sh"

export GHSM_ROOT="$root"
upd_refresh_cache
exit 0
