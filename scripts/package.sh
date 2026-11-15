#!/usr/bin/env bash
# Build dist/ghsm.tar.gz and dist/checksums.txt from this checkout.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
out="${1:-${root}/dist}"
version="$(sed -n 's/^GHSM_VERSION="\([^"]*\)".*/\1/p' "${root}/lib/version.sh" | head -n 1)"
[[ -n "$version" ]] || {
  printf 'package: version.sh has no GHSM_VERSION\n' >&2
  exit 1
}

stage="$(mktemp -d "${TMPDIR:-/tmp}/ghsm-package.XXXXXX")"
cleanup() {
  rm -rf "$stage"
}
trap cleanup EXIT

dest="${stage}/ghsm"
mkdir -p "$dest"
cp -R "${root}/bin" "${root}/lib" "$dest/"
cp "${root}/install.sh" "${dest}/install.sh"
chmod 755 "${dest}/bin/ghsm" "${dest}/install.sh" "${dest}/lib/refresh.sh"

mkdir -p "$out"
out="$(cd "$out" && pwd)"
tar -C "$stage" -czf "${out}/ghsm.tar.gz" ghsm

hash=""
if command -v shasum >/dev/null 2>&1; then
  hash="$(shasum -a 256 "${out}/ghsm.tar.gz" | awk '{print $1}')"
elif command -v sha256sum >/dev/null 2>&1; then
  hash="$(sha256sum "${out}/ghsm.tar.gz" | awk '{print $1}')"
else
  printf 'package: shasum or sha256sum is required\n' >&2
  exit 1
fi
printf '%s  %s\n' "$hash" "ghsm.tar.gz" > "${out}/checksums.txt"
printf 'packaged ghsm %s\n' "$version"
