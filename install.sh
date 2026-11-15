#!/usr/bin/env bash
# Install ghsm into ~/.local without root.
# Safe to run more than once. Does not use the caller's working directory.
set -euo pipefail

GHSM_REPO="${GHSM_REPO:-eriktorsner/ghsm}"

INSTALL_WORK=""
INSTALL_STAGE=""

install_cleanup() {
  if [[ -n "${INSTALL_WORK:-}" ]]; then
    rm -rf "$INSTALL_WORK"
    INSTALL_WORK=""
  fi
  if [[ -n "${INSTALL_STAGE:-}" ]]; then
    rm -rf "$INSTALL_STAGE"
    INSTALL_STAGE=""
  fi
  return 0
}

install_die() {
  printf 'ghsm: %s\n' "$*" >&2
  exit 1
}

install_usage() {
  cat <<'EOF'
Usage:
  install.sh [--version TAG] [--prefix DIR] [--bin-dir DIR] [--from-source DIR] [--force]

Install ghsm for the current user.

  --version       Release tag to install (default: latest). "v1.2.3" or "1.2.3".
  --prefix        Install prefix (default: ~/.local). The executable is placed in
                  PREFIX/bin and program files in PREFIX/share/ghsm.
  --bin-dir       Directory for the executable symlink (default: PREFIX/bin).
  --from-source   Copy a local checkout instead of downloading a release.
  --force         Reinstall even when that version is already present.

Environment:
  GHSM_VERSION    Same as --version
  GHSM_PREFIX     Same as --prefix
  GHSM_BIN_DIR    Same as --bin-dir
  GHSM_REPO       GitHub repository (default: eriktorsner/ghsm)

Examples:
  curl -fsSL https://raw.githubusercontent.com/eriktorsner/ghsm/main/install.sh | bash
  curl -fsSL https://raw.githubusercontent.com/eriktorsner/ghsm/main/install.sh | bash -s -- --version v0.1.0
  ./install.sh --from-source .
EOF
}

install_http_get() {
  local url="$1" dest="$2"
  if [[ -n "${GHSM_CURL:-}" ]]; then
    "$GHSM_CURL" "$url" "$dest"
    return
  fi
  command curl -fsSL --retry 3 --retry-delay 1 --max-time "${GHSM_HTTP_TIMEOUT:-60}" \
    -A "ghsm-installer" \
    -H "Accept: application/vnd.github+json" \
    -o "$dest" \
    "$url"
}

install_sha256() {
  local file="$1" hash
  if command -v shasum >/dev/null 2>&1; then
    hash="$(shasum -a 256 "$file" | awk '{print $1}')"
  elif command -v sha256sum >/dev/null 2>&1; then
    hash="$(sha256sum "$file" | awk '{print $1}')"
  else
    install_die "shasum or sha256sum is required to verify the download"
  fi
  printf '%s\n' "$hash" | tr '[:upper:]' '[:lower:]'
}

install_absdir() {
  local dir="$1"
  mkdir -p "$dir"
  (cd "$dir" && pwd)
}

install_normalize_tag() {
  local tag="$1"
  if [[ "$tag" == "latest" || -z "$tag" ]]; then
    printf 'latest\n'
    return 0
  fi
  if [[ "$tag" =~ ^[0-9] ]]; then
    tag="v${tag}"
  fi
  if [[ ! "$tag" =~ ^v[A-Za-z0-9._+-]+$ || "$tag" == *..* || "$tag" == */* ]]; then
    install_die "invalid version: ${tag}"
  fi
  printf '%s\n' "$tag"
}

install_version_number() {
  local tag="$1"
  tag="${tag#v}"
  printf '%s\n' "$tag"
}

install_installed_version() {
  local share="$1" file line
  file="${share}/lib/version.sh"
  [[ -f "$file" ]] || return 1
  line="$(sed -n 's/^GHSM_VERSION="\([^"]*\)".*/\1/p' "$file" | head -n 1)"
  [[ -n "$line" ]] || return 1
  printf '%s\n' "$line"
}

install_resolve_latest_tag() {
  local body tag
  body="$(mktemp "${TMPDIR:-/tmp}/ghsm-release.XXXXXX")"
  if ! install_http_get "https://api.github.com/repos/${GHSM_REPO}/releases/latest" "$body"; then
    rm -f "$body"
    install_die "could not read the latest release of ${GHSM_REPO}"
  fi
  tag="$(jq -r '.tag_name // empty' "$body" 2>/dev/null || true)"
  rm -f "$body"
  if [[ -z "$tag" || "$tag" == "null" ]]; then
    install_die "the latest release of ${GHSM_REPO} has no tag"
  fi
  printf '%s\n' "$tag"
}

install_expected_hash() {
  local file="$1" base="$2" line hash name
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -z "$line" || "$line" == \#* ]] && continue
    hash="${line%% *}"
    name="${line##* }"
    name="${name#\*}"
    if [[ "$name" == "$base" ]]; then
      printf '%s\n' "$hash" | tr '[:upper:]' '[:lower:]'
      return 0
    fi
  done < "$file"
  return 1
}

install_prereqs() {
  local missing=0
  if ! command -v jq >/dev/null 2>&1; then
    printf 'ghsm: jq is required. Install it with your system package manager.\n' >&2
    missing=1
  fi
  if ! command -v gh >/dev/null 2>&1; then
    printf 'ghsm: GitHub CLI (gh) is required. Install it from https://cli.github.com/\n' >&2
    missing=1
  fi
  if [[ "$missing" -ne 0 ]]; then
    exit 3
  fi
}

install_bin_on_path() {
  local bin_dir="$1" target part resolved
  target="$(cd "$bin_dir" && pwd)"
  local IFS=:
  local -a parts=()
  read -r -a parts <<< "${PATH}"
  for part in ${parts[@]+"${parts[@]}"}; do
    [[ -z "$part" || ! -d "$part" ]] && continue
    resolved="$(cd "$part" && pwd 2>/dev/null || true)"
    if [[ -n "$resolved" && "$resolved" == "$target" ]]; then
      return 0
    fi
  done
  return 1
}

install_shell_rc() {
  local shell_name
  shell_name="$(basename "${SHELL:-bash}")"
  case "$shell_name" in
    zsh) printf '%s\n' "${ZDOTDIR:-$HOME}/.zshrc" ;;
    bash)
      if [[ "$(uname -s)" == "Darwin" ]]; then
        printf '%s\n' "${HOME}/.bash_profile"
      else
        printf '%s\n' "${HOME}/.bashrc"
      fi
      ;;
    *) printf '%s\n' "${HOME}/.profile" ;;
  esac
}

install_path_block() {
  local bin_dir="$1"
  cat <<EOF
# >>> ghsm >>>
case ":\${PATH}:" in
  *":${bin_dir}:"*) ;;
  *) export PATH="${bin_dir}:\${PATH}" ;;
esac
# <<< ghsm <<<
EOF
}

install_configure_path() {
  local bin_dir="$1"
  local target rc
  target="$(cd "$bin_dir" && pwd)"
  if install_bin_on_path "$target"; then
    return 0
  fi
  case "$target" in
    *\"*|*\'*|*$'\n'*|*\`*)
      printf 'ghsm: %s is not on PATH. Add it manually.\n' "$target" >&2
      return 0
      ;;
  esac
  rc="$(install_shell_rc)"
  mkdir -p "$(dirname "$rc")"
  if [[ -f "$rc" ]] && grep -F '# >>> ghsm >>>' "$rc" >/dev/null 2>&1; then
    printf 'PATH is configured in %s. Open a new terminal, or run:\n\n  export PATH="%s:$PATH"\n' "$rc" "$target"
    return 0
  fi
  {
    if [[ -s "$rc" ]]; then
      printf '\n'
    fi
    install_path_block "$target"
  } >> "$rc"
  printf 'Added %s to PATH in %s.\nOpen a new terminal, or run:\n\n  export PATH="%s:$PATH"\n' "$target" "$rc" "$target"
}

install_place_tree() {
  local src="$1" share="$2" bin_dir="$3" stage
  [[ -f "${src}/bin/ghsm" ]] || install_die "release archive is missing bin/ghsm"
  [[ -d "${src}/lib" ]] || install_die "release archive is missing lib/"
  stage="$(mktemp -d "${TMPDIR:-/tmp}/ghsm-stage.XXXXXX")"
  INSTALL_STAGE="$stage"
  cp -R "${src}/bin" "${src}/lib" "$stage/"
  if [[ -f "${src}/install.sh" ]]; then
    cp "${src}/install.sh" "${stage}/install.sh"
    chmod 755 "${stage}/install.sh"
  fi
  chmod 755 "${stage}/bin/ghsm" "${stage}/lib/refresh.sh"
  mkdir -p "$share" "$bin_dir"
  rm -rf "${share}/bin" "${share}/lib" "${share}/install.sh"
  mv "${stage}/bin" "${stage}/lib" "$share/"
  if [[ -f "${stage}/install.sh" ]]; then
    mv "${stage}/install.sh" "${share}/install.sh"
  fi
  rm -rf "$stage"
  INSTALL_STAGE=""
  ln -sfn "${share}/bin/ghsm" "${bin_dir}/ghsm"
}

install_download_release() {
  local tag="$1" work="$2"
  local tarball="${work}/ghsm.tar.gz"
  local sums="${work}/checksums.txt"
  local base="https://github.com/${GHSM_REPO}/releases/download/${tag}"
  install_http_get "${base}/ghsm.tar.gz" "$tarball" \
    || install_die "could not download ${tag}/ghsm.tar.gz"
  install_http_get "${base}/checksums.txt" "$sums" \
    || install_die "could not download ${tag}/checksums.txt"
  local expected actual
  expected="$(install_expected_hash "$sums" "ghsm.tar.gz")" \
    || install_die "checksums.txt has no entry for ghsm.tar.gz"
  [[ "$expected" =~ ^[0-9a-f]{64}$ ]] || install_die "checksum for ghsm.tar.gz is not a sha256"
  actual="$(install_sha256 "$tarball")"
  if [[ "$actual" != "$expected" ]]; then
    install_die "checksum mismatch for ghsm.tar.gz"
  fi
  tar -xzf "$tarball" -C "$work"
  [[ -d "${work}/ghsm" ]] || install_die "archive does not contain a ghsm directory"
  printf '%s\n' "${work}/ghsm"
}

install_main() {
  local version="${GHSM_VERSION:-}"
  local prefix="${GHSM_PREFIX:-${HOME}/.local}"
  local bin_dir="${GHSM_BIN_DIR:-}"
  local from_source=""
  local force=0

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help)
        install_usage
        return 0
        ;;
      --version)
        [[ $# -ge 2 ]] || install_die "--version requires a tag"
        version="$2"
        shift 2
        ;;
      --prefix)
        [[ $# -ge 2 ]] || install_die "--prefix requires a directory"
        prefix="$2"
        shift 2
        ;;
      --bin-dir)
        [[ $# -ge 2 ]] || install_die "--bin-dir requires a directory"
        bin_dir="$2"
        shift 2
        ;;
      --from-source)
        [[ $# -ge 2 ]] || install_die "--from-source requires a directory"
        from_source="$2"
        shift 2
        ;;
      --force)
        force=1
        shift
        ;;
      *)
        install_die "unknown argument: $1"
        ;;
    esac
  done

  if [[ -n "$from_source" && -n "$version" ]]; then
    install_die "use either --from-source or --version"
  fi
  [[ -n "${HOME:-}" ]] || install_die "HOME is not set"

  install_prereqs

  if [[ -z "${GHSM_CURL:-}" && -z "$from_source" ]] && ! command -v curl >/dev/null 2>&1; then
    install_die "curl is required to download a release"
  fi

  prefix="$(install_absdir "$prefix")"
  if [[ -z "$bin_dir" ]]; then
    bin_dir="${prefix}/bin"
  fi
  bin_dir="$(install_absdir "$bin_dir")"
  local share="${prefix}/share/ghsm"

  local src="" tag="" number=""
  if [[ -n "$from_source" ]]; then
    src="$(cd "$from_source" && pwd)" || install_die "source directory not found: ${from_source}"
    number="$(install_installed_version "$src" || true)"
  else
    tag="$(install_normalize_tag "$version")"
    if [[ "$tag" == "latest" ]]; then
      tag="$(install_resolve_latest_tag)"
    fi
    number="$(install_version_number "$tag")"
    local installed=""
    installed="$(install_installed_version "$share" || true)"
    if [[ "$force" -eq 0 && -n "$installed" && "$installed" == "$number" && -x "${share}/bin/ghsm" ]]; then
      ln -sfn "${share}/bin/ghsm" "${bin_dir}/ghsm"
      printf 'ghsm %s is already installed at %s\n' "$number" "${bin_dir}/ghsm"
      install_configure_path "$bin_dir"
      return 0
    fi
  fi

  INSTALL_WORK="$(mktemp -d "${TMPDIR:-/tmp}/ghsm-install.XXXXXX")"
  trap install_cleanup EXIT

  if [[ -z "$from_source" ]]; then
    src="$(install_download_release "$tag" "$INSTALL_WORK")"
    number="$(install_installed_version "$src" || true)"
  fi

  install_place_tree "$src" "$share" "$bin_dir"
  if [[ -z "$number" ]]; then
    number="$(install_installed_version "$share" || true)"
  fi
  printf 'Installed ghsm %s to %s\n' "${number:-unknown}" "${bin_dir}/ghsm"
  install_configure_path "$bin_dir"
}

if [[ -z "${BASH_SOURCE[0]:-}" || "${BASH_SOURCE[0]}" == "$0" ]]; then
  install_main "$@"
fi
