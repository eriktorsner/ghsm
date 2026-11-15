#!/usr/bin/env bash
# Test double for the installer HTTP client. Usage: fake-curl URL DEST
set -euo pipefail

url="${1:-}"
dest="${2:-}"
[[ -n "$url" && -n "$dest" ]] || exit 2
printf '%s\n' "$url" >> "${GH_FAKE_CURL_LOG:-/dev/null}"

case "$url" in
  */releases/latest)
    [[ -n "${GH_FAKE_API:-}" ]] || exit 1
    cp "$GH_FAKE_API" "$dest"
    ;;
  */ghsm.tar.gz)
    [[ -n "${GH_FAKE_TARBALL:-}" ]] || exit 1
    cp "$GH_FAKE_TARBALL" "$dest"
    ;;
  */checksums.txt)
    [[ -n "${GH_FAKE_SUMS:-}" ]] || exit 1
    cp "$GH_FAKE_SUMS" "$dest"
    ;;
  *)
    printf 'fake curl: unexpected url %s\n' "$url" >&2
    exit 1
    ;;
esac
