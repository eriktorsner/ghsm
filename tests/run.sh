#!/usr/bin/env bash
# ghsm tests. Run with macOS /bin/bash (3.2) when it is available.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BASH_BIN="${BASH_BIN:-/bin/bash}"
BIN="${ROOT}/bin/ghsm"
PASS=0
FAIL=0

ok() {
  PASS=$((PASS + 1))
  printf 'ok  %s\n' "$1"
}

bad() {
  FAIL=$((FAIL + 1))
  printf 'FAIL %s\n' "$1" >&2
  if [[ -n "${2:-}" ]]; then
    printf '%s\n' "$2" >&2
  fi
}

assert_eq() {
  local name="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    ok "$name"
  else
    bad "$name" "expected [${expected}] actual [${actual}]"
  fi
}

assert_contains() {
  local name="$1" haystack="$2" needle="$3"
  if [[ "$haystack" == *"$needle"* ]]; then
    ok "$name"
  else
    bad "$name" "missing [${needle}] in [${haystack}]"
  fi
}

assert_not_contains() {
  local name="$1" haystack="$2" needle="$3"
  if [[ "$haystack" == *"$needle"* ]]; then
    bad "$name" "unexpected [${needle}] in [${haystack}]"
  else
    ok "$name"
  fi
}

run_tool() {
  TOOL_STDOUT=""
  TOOL_STDERR=""
  TOOL_CODE=0
  local out err
  out="$(mktemp)"
  err="$(mktemp)"
  set +e
  env GHSM_NO_UPDATE_CHECK=1 "$BASH_BIN" "$BIN" "$@" >"$out" 2>"$err"
  TOOL_CODE=$?
  set -e
  TOOL_STDOUT="$(cat "$out")"
  TOOL_STDERR="$(cat "$err")"
  rm -f "$out" "$err"
}

new_project() {
  local base
  base="$(mktemp -d "${TMPDIR:-/tmp}/ghsm-test.XXXXXX")"
  base="$(cd "$base" && pwd)"
  PROJECT="${base}/my project"
  mkdir -p "$PROJECT"
  export GHSM_PROJECT_ROOT="$PROJECT"
  export GHSM_GH="${ROOT}/tests/fake-gh.sh"
  export GH_FAKE_LOG="${base}/gh.log"
  : > "$GH_FAKE_LOG"
  unset GH_FAKE_LIST GH_FAKE_UPDATE_OUTPUT GH_FAKE_UPDATE_CODE GH_FAKE_FAIL_ON || true
  unset GHSM_MANIFEST || true
  TEST_BASE="$base"
}

syntax_check() {
  local f
  for f in \
    "$ROOT/bin/ghsm" \
    "$ROOT/install.sh" \
    "$ROOT/scripts/package.sh" \
    "$ROOT/lib/refresh.sh" \
    "$ROOT/lib/ui.sh" \
    "$ROOT/lib/util.sh" \
    "$ROOT/lib/deps.sh" \
    "$ROOT/lib/self_update.sh" \
    "$ROOT/lib/skills.sh" \
    "$ROOT/lib/cli.sh" \
    "$ROOT/tests/fake-gh.sh" \
    "$ROOT/tests/fake-curl.sh" \
    "$ROOT/tests/run.sh"
  do
    if "$BASH_BIN" -n "$f"; then
      ok "syntax ${f#"$ROOT"/}"
    else
      bad "syntax ${f#"$ROOT"/}"
    fi
  done
}

test_version_and_help() {
  run_tool --version
  assert_eq "version status" "0" "$TOOL_CODE"
  assert_eq "version text" "ghsm 0.1.0" "$TOOL_STDOUT"
  run_tool --json --version
  assert_contains "version json" "$TOOL_STDOUT" '"version":"0.1.0"'
  run_tool --help
  assert_eq "help status" "0" "$TOOL_CODE"
  assert_contains "help mentions update" "$TOOL_STDOUT" "ghsm update"
  assert_contains "help mentions manifest" "$TOOL_STDOUT" "--manifest"
  run_tool
  assert_eq "missing command" "2" "$TOOL_CODE"
  run_tool nosuch
  assert_eq "unknown command" "2" "$TOOL_CODE"
  run_tool help update
  assert_contains "help update" "$TOOL_STDOUT" "--check"
  run_tool update --help
  assert_contains "update help flag" "$TOOL_STDOUT" "--force"
  run_tool completion bash
  assert_contains "bash completion" "$TOOL_STDOUT" "complete -F _ghsm ghsm"
  run_tool completion zsh
  assert_eq "zsh completion status" "0" "$TOOL_CODE"
}

test_version_compare() {
  local out
  out="$(
    # shellcheck disable=SC1091
    source "$ROOT/lib/version.sh"
    # shellcheck disable=SC1091
    source "$ROOT/lib/ui.sh"
    # shellcheck disable=SC1091
    source "$ROOT/lib/util.sh"
    # shellcheck disable=SC1091
    source "$ROOT/lib/self_update.sh"
    cmp_one() {
      local code=0
      upd_version_cmp "$1" "$2" || code=$?
      printf '%s\n' "$code"
    }
    cmp_one 1.2.3 1.2.3
    cmp_one v1.0.0 1.0.0
    cmp_one 1.2.9 1.2.10
    cmp_one 1.2.10 1.2.9
    cmp_one 1.2 1.2.0
    cmp_one 1.2 1.2.1
    cmp_one 2.0.0 1.9.9
    cmp_one 1.010 1.10
  )"
  local line1 line2 line3 line4 line5 line6 line7 line8
  line1="$(printf '%s\n' "$out" | sed -n '1p')"
  line2="$(printf '%s\n' "$out" | sed -n '2p')"
  line3="$(printf '%s\n' "$out" | sed -n '3p')"
  line4="$(printf '%s\n' "$out" | sed -n '4p')"
  line5="$(printf '%s\n' "$out" | sed -n '5p')"
  line6="$(printf '%s\n' "$out" | sed -n '6p')"
  line7="$(printf '%s\n' "$out" | sed -n '7p')"
  line8="$(printf '%s\n' "$out" | sed -n '8p')"
  assert_eq "cmp equal" "0" "$line1"
  assert_eq "cmp v prefix" "0" "$line2"
  assert_eq "cmp 1.2.9 < 1.2.10" "2" "$line3"
  assert_eq "cmp 1.2.10 > 1.2.9" "1" "$line4"
  assert_eq "cmp 1.2 == 1.2.0" "0" "$line5"
  assert_eq "cmp 1.2 < 1.2.1" "2" "$line6"
  assert_eq "cmp major" "1" "$line7"
  assert_eq "cmp leading zeros" "0" "$line8"
}

test_missing_dependency() {
  local jq_bin base bindir code out err
  jq_bin="$(command -v jq)"
  base="$(mktemp -d)"
  bindir="${base}/bin"
  mkdir -p "$bindir" "${base}/project"
  ln -s "$jq_bin" "${bindir}/jq"
  out="$(mktemp)"
  err="$(mktemp)"
  set +e
  env -i \
    HOME="$HOME" \
    PATH="${bindir}:/usr/bin:/bin" \
    GHSM_NO_UPDATE_CHECK=1 \
    GHSM_PROJECT_ROOT="${base}/project" \
    "$BASH_BIN" "$BIN" list >"$out" 2>"$err"
  code=$?
  set -e
  assert_eq "missing gh status" "3" "$code"
  assert_contains "missing gh message" "$(cat "$err")" "GitHub CLI"
  rm -rf "$base" "$out" "$err"
}

test_add_update_list_remove() {
  new_project
  run_tool update
  assert_eq "update without manifest" "1" "$TOOL_CODE"
  assert_contains "update missing message" "$TOOL_STDERR" "manifest not found"

  run_tool add
  assert_eq "add usage" "2" "$TOOL_CODE"

  run_tool add 'acme/skills' 'demo skill'
  assert_eq "add rejects spaces" "2" "$TOOL_CODE"

  run_tool add acme/skills demo
  assert_eq "add status" "0" "$TOOL_CODE"
  assert_contains "add output" "$TOOL_STDOUT" "added  acme/skills  demo"
  assert_contains "add recorded repo" "$(cat "$PROJECT/skills.json")" "acme/skills"
  assert_contains "add recorded skill" "$(cat "$PROJECT/skills.json")" "demo"
  assert_contains "add called gh" "$(cat "$GH_FAKE_LOG")" "ARG ${PROJECT}/.agent/skills"

  run_tool add acme/skills 'demo@v1.2.0'
  assert_eq "add pin status" "0" "$TOOL_CODE"
  local count
  count="$(jq '.skills | length' "$PROJECT/skills.json")"
  assert_eq "add is idempotent" "1" "$count"
  assert_contains "add stores ref" "$(cat "$PROJECT/skills.json")" "v1.2.0"
  assert_contains "add pin arg" "$(cat "$GH_FAKE_LOG")" "ARG demo@v1.2.0"

  mkdir -p "${PROJECT}/.agent/skills/demo"
  printf '%s\n' '---' 'name: demo' '---' > "${PROJECT}/.agent/skills/demo/SKILL.md"
  jq -n --arg path "${PROJECT}/.agent/skills/demo" \
    '[{skillName:"demo", sourceURL:"https://github.com/acme/skills/tree/main/demo", version:"v1.2.0", pinned:true, path:$path}]' \
    > "${TEST_BASE}/list.json"
  export GH_FAKE_LIST="${TEST_BASE}/list.json"

  run_tool list
  assert_eq "list status" "0" "$TOOL_CODE"
  assert_contains "list name" "$TOOL_STDOUT" "demo"
  assert_contains "list repo" "$TOOL_STDOUT" "acme/skills"
  run_tool --json list
  assert_contains "list json manifest" "$TOOL_STDOUT" '"in_manifest":true'

  export GH_FAKE_UPDATE_OUTPUT="1 update(s) available"
  run_tool update --check
  assert_eq "check status" "0" "$TOOL_CODE"
  assert_contains "check pinned" "$TOOL_STDOUT" "pinned  acme/skills  demo"

  jq 'del(.skills[0].ref)' "$PROJECT/skills.json" > "${TEST_BASE}/manifest.json"
  mv "${TEST_BASE}/manifest.json" "$PROJECT/skills.json"
  jq '.[0].pinned = false' "$GH_FAKE_LIST" > "${TEST_BASE}/list2.json"
  mv "${TEST_BASE}/list2.json" "$GH_FAKE_LIST"
  : > "$GH_FAKE_LOG"
  run_tool update
  assert_eq "update status" "0" "$TOOL_CODE"
  assert_contains "update uses gh update" "$(cat "$GH_FAKE_LOG")" "ARG update"
  assert_contains "update passes --all" "$(cat "$GH_FAKE_LOG")" "ARG --all"

  : > "$GH_FAKE_LOG"
  run_tool update --force
  assert_contains "force reinstalls" "$(cat "$GH_FAKE_LOG")" "ARG install"

  run_tool update --check --force
  assert_eq "check and force" "2" "$TOOL_CODE"

  printf '%s\n' '{"version":1,"skills":[{"repo":"acme/skills","skill":"demo"},{"repo":"acme/skills","skill":"FAILME"}]}' \
    > "$PROJECT/skills.json"
  export GH_FAKE_FAIL_ON="FAILME"
  unset GH_FAKE_LIST || true
  run_tool update
  assert_eq "partial failure" "5" "$TOOL_CODE"
  assert_contains "partial json not required" "$TOOL_STDOUT" "failed  acme/skills  FAILME"
  unset GH_FAKE_FAIL_ON || true

  printf '%s\n' '{"version":1,"skills":[{"repo":"acme/skills","skill":"demo"}]}' > "$PROJECT/skills.json"
  export GH_FAKE_LIST="${TEST_BASE}/list.json"
  jq -n --arg path "${PROJECT}/.agent/skills/demo" \
    '[{skillName:"demo", sourceURL:"https://github.com/acme/skills", version:"", pinned:false, path:$path}]' \
    > "$GH_FAKE_LIST"
  run_tool remove demo
  assert_eq "remove status" "0" "$TOOL_CODE"
  assert_contains "remove output" "$TOOL_STDOUT" "removed  acme/skills  demo"
  if [[ ! -d "${PROJECT}/.agent/skills/demo" ]]; then
    ok "remove deletes directory"
  else
    bad "remove deletes directory"
  fi
  count="$(jq '.skills | length' "$PROJECT/skills.json")"
  assert_eq "remove drops manifest entry" "0" "$count"

  printf '[]\n' > "$GH_FAKE_LIST"
  run_tool remove demo
  assert_eq "remove missing" "4" "$TOOL_CODE"

  mkdir -p "${TEST_BASE}/outside"
  printf 'keep\n' > "${TEST_BASE}/outside/file"
  printf '%s\n' '{"version":1,"skills":[{"repo":"acme/skills","skill":"demo"}]}' > "$PROJECT/skills.json"
  jq -n --arg path "${TEST_BASE}/outside" \
    '[{skillName:"demo", sourceURL:"https://github.com/acme/skills", version:"", pinned:false, path:$path}]' \
    > "$GH_FAKE_LIST"
  run_tool remove demo
  assert_eq "refuse outside status" "1" "$TOOL_CODE"
  assert_contains "refuse outside message" "$TOOL_STDERR" "refusing to remove"
  assert_contains "canary remains" "$(cat "${TEST_BASE}/outside/file")" "keep"
  assert_eq "manifest unchanged after refuse" "1" "$(jq '.skills | length' "$PROJECT/skills.json")"

  rm -rf "$TEST_BASE"
  unset GHSM_PROJECT_ROOT GHSM_GH GH_FAKE_LOG GH_FAKE_LIST || true
}

test_custom_manifest() {
  new_project
  mkdir -p "${PROJECT}/teams"
  run_tool --manifest "${PROJECT}/teams/review.json" add acme/skills demo
  assert_eq "custom manifest add" "0" "$TOOL_CODE"
  assert_contains "custom manifest records skill" "$(cat "${PROJECT}/teams/review.json")" "demo"
  if [[ ! -e "${PROJECT}/skills.json" ]]; then
    ok "custom manifest leaves default file alone"
  else
    bad "custom manifest leaves default file alone"
  fi

  run_tool --manifest "${PROJECT}/teams/docs.json" add acme/skills writer
  assert_eq "second manifest add" "0" "$TOOL_CODE"
  assert_eq "first manifest unchanged" "1" "$(jq '.skills | length' "${PROJECT}/teams/review.json")"
  assert_contains "second manifest skill" "$(cat "${PROJECT}/teams/docs.json")" "writer"
  assert_not_contains "first manifest stays separate" "$(cat "${PROJECT}/teams/review.json")" "writer"

  export GHSM_MANIFEST="${PROJECT}/teams/review.json"
  run_tool update --check
  assert_eq "env manifest check" "0" "$TOOL_CODE"
  assert_contains "env manifest selects demo" "$TOOL_STDOUT" "demo"
  assert_not_contains "env manifest ignores other file" "$TOOL_STDOUT" "writer"

  run_tool --manifest "${PROJECT}/teams/docs.json" update --check
  assert_eq "flag overrides env" "0" "$TOOL_CODE"
  assert_contains "flag selects writer" "$TOOL_STDOUT" "writer"
  assert_not_contains "flag ignores env file" "$TOOL_STDOUT" "demo"
  unset GHSM_MANIFEST || true

  local out err code
  out="$(mktemp)"
  err="$(mktemp)"
  set +e
  (
    cd "$PROJECT"
    env GHSM_NO_UPDATE_CHECK=1 \
      GHSM_PROJECT_ROOT="$PROJECT" \
      GHSM_GH="${ROOT}/tests/fake-gh.sh" \
      GH_FAKE_LOG="${TEST_BASE}/rel.log" \
      "$BASH_BIN" "$BIN" -m teams/review.json list >"$out" 2>"$err"
  )
  code=$?
  set -e
  assert_eq "relative manifest status" "0" "$code"
  rm -f "$out" "$err"

  run_tool --manifest "${PROJECT}/missing/review.json" add acme/skills demo
  assert_eq "missing manifest directory" "1" "$TOOL_CODE"
  assert_contains "missing directory message" "$TOOL_STDERR" "manifest directory does not exist"

  run_tool --manifest
  assert_eq "manifest flag needs a path" "2" "$TOOL_CODE"

  rm -rf "$TEST_BASE"
  unset GHSM_PROJECT_ROOT GHSM_GH GHSM_MANIFEST GH_FAKE_LOG GH_FAKE_LIST || true
}

test_invalid_manifest_and_git_root() {
  new_project
  printf 'not-json\n' > "$PROJECT/skills.json"
  run_tool list
  assert_eq "invalid manifest" "1" "$TOOL_CODE"
  rm -rf "$TEST_BASE"
  unset GHSM_PROJECT_ROOT || true

  local base repo
  base="$(mktemp -d)"
  repo="${base}/repo"
  mkdir -p "${repo}/nested dir"
  git -C "$repo" init -q
  printf '%s\n' '{"version":1,"skills":[]}' > "${repo}/skills.json"
  local out err code
  out="$(mktemp)"
  err="$(mktemp)"
  set +e
  (
    cd "${repo}/nested dir"
    env -u GHSM_PROJECT_ROOT \
      GHSM_NO_UPDATE_CHECK=1 \
      GHSM_GH="${ROOT}/tests/fake-gh.sh" \
      GH_FAKE_LOG="${base}/gh.log" \
      "$BASH_BIN" "$BIN" list >"$out" 2>"$err"
  )
  code=$?
  set -e
  assert_eq "git root list status" "0" "$code"
  assert_contains "git root path" "$(cat "$out")" "${repo}/.agent/skills"
  rm -rf "$base" "$out" "$err"
  unset GHSM_GH GH_FAKE_LOG || true
}

test_update_notice_does_not_block() {
  local base cache now
  base="$(mktemp -d)"
  cache="${base}/cache"
  mkdir -p "$cache"
  now="$(date +%s)"
  jq -n --argjson now "$now" \
    '{checked_at:$now, ok:true, current:"0.1.0", latest:"9.9.9", update_available:true}' \
    > "${cache}/update-check.json"
  printf '%s\n' '#!/bin/bash' 'echo called >> "$GH_FAKE_CURL_LOG"' 'exit 1' > "${base}/curl"
  chmod +x "${base}/curl"
  : > "${base}/curl.log"
  local out err code start end elapsed
  out="$(mktemp)"
  err="$(mktemp)"
  start="$(date +%s)"
  set +e
  env -u GHSM_NO_UPDATE_CHECK \
    GHSM_CACHE_DIR="$cache" \
    GHSM_CURL="${base}/curl" \
    GH_FAKE_CURL_LOG="${base}/curl.log" \
    "$BASH_BIN" "$BIN" --version >"$out" 2>"$err"
  code=$?
  set -e
  end="$(date +%s)"
  elapsed=$((end - start))
  assert_eq "notice command status" "0" "$code"
  assert_contains "notice text" "$(cat "$err")" "9.9.9 is available"
  assert_eq "fresh cache skips network" "" "$(cat "${base}/curl.log")"
  if [[ "$elapsed" -lt 2 ]]; then
    ok "version returns without waiting"
  else
    bad "version returns without waiting" "elapsed ${elapsed}s"
  fi

  printf 'not-json\n' > "${cache}/update-check.json"
  cat > "${base}/curl" <<'EOF'
#!/bin/bash
exit 1
EOF
  chmod +x "${base}/curl"
  set +e
  env -u GHSM_NO_UPDATE_CHECK \
    GHSM_CACHE_DIR="$cache" \
    GHSM_CURL="${base}/curl" \
    "$BASH_BIN" "$BIN" --version >"$out" 2>"$err"
  code=$?
  set -e
  assert_eq "corrupt cache still runs" "0" "$code"

  (
    # shellcheck disable=SC1091
    source "$ROOT/lib/version.sh"
    # shellcheck disable=SC1091
    source "$ROOT/lib/ui.sh"
    # shellcheck disable=SC1091
    source "$ROOT/lib/util.sh"
    # shellcheck disable=SC1091
    source "$ROOT/lib/self_update.sh"
    export GHSM_CACHE_DIR="${base}/refresh-cache"
    export GHSM_CURL="${base}/curl"
    mkdir -p "$GHSM_CACHE_DIR"
    upd_refresh_cache
    jq -e '.ok == false' "${GHSM_CACHE_DIR}/update-check.json" >/dev/null
  )
  assert_eq "failed refresh writes cache" "0" "$?"

  rm -rf "$base" "$out" "$err"
}

test_self_update_check() {
  local base api out err code
  base="$(mktemp -d)"
  api="${base}/api.json"
  printf '%s\n' '{"tag_name":"v0.2.0"}' > "$api"
  cat > "${base}/curl" <<EOF
#!/bin/bash
cp "$api" "\$2"
exit 0
EOF
  chmod +x "${base}/curl"
  out="$(mktemp)"
  err="$(mktemp)"
  set +e
  env GHSM_NO_UPDATE_CHECK=1 GHSM_CURL="${base}/curl" \
    "$BASH_BIN" "$BIN" self-update --check >"$out" 2>"$err"
  code=$?
  set -e
  assert_eq "self-update check status" "0" "$code"
  assert_contains "self-update check text" "$(cat "$out")" "0.2.0 is available"
  set +e
  env GHSM_NO_UPDATE_CHECK=1 GHSM_CURL="${base}/curl" GHSM_JSON=1 \
    "$BASH_BIN" "$BIN" --json self-update --check >"$out" 2>"$err"
  code=$?
  set -e
  assert_contains "self-update check json" "$(cat "$out")" '"update_available":true'
  printf '%s\n' '#!/bin/bash' 'exit 1' > "${base}/curl"
  chmod +x "${base}/curl"
  set +e
  env GHSM_NO_UPDATE_CHECK=1 GHSM_CURL="${base}/curl" \
    "$BASH_BIN" "$BIN" self-update --check >"$out" 2>"$err"
  code=$?
  set -e
  assert_eq "self-update check failure" "1" "$code"
  rm -rf "$base" "$out" "$err"
}

test_installer() {
  local base home prefix rc count
  base="$(mktemp -d)"
  home="${base}/home"
  prefix="${base}/local dir"
  mkdir -p "$home"
  env \
    HOME="$home" \
    SHELL="/bin/zsh" \
    ZDOTDIR="$home" \
    "$BASH_BIN" "$ROOT/install.sh" --from-source "$ROOT" --prefix "$prefix" >"${base}/out" 2>"${base}/err"
  assert_eq "from-source status" "0" "$?"
  assert_contains "from-source message" "$(cat "${base}/out")" "Installed ghsm"
  env HOME="$home" "$prefix/bin/ghsm" --version >"${base}/ver" 2>"${base}/verr"
  assert_eq "installed version" "ghsm 0.1.0" "$(cat "${base}/ver")"
  rc="${home}/.zshrc"
  count="$(grep -c '# >>> ghsm >>>' "$rc")"
  assert_eq "path block once" "1" "$count"
  env \
    HOME="$home" \
    SHELL="/bin/zsh" \
    ZDOTDIR="$home" \
    "$BASH_BIN" "$ROOT/install.sh" --from-source "$ROOT" --prefix "$prefix" >"${base}/out2" 2>"${base}/err2"
  count="$(grep -c '# >>> ghsm >>>' "$rc")"
  assert_eq "path block stays once" "1" "$count"

  local onpath_home onpath_prefix
  onpath_home="${base}/home-onpath"
  onpath_prefix="${base}/onpath"
  mkdir -p "$onpath_home"
  env \
    HOME="$onpath_home" \
    SHELL="/bin/zsh" \
    ZDOTDIR="$onpath_home" \
    PATH="${onpath_prefix}/bin:${PATH}" \
    "$BASH_BIN" "$ROOT/install.sh" --from-source "$ROOT" --prefix "$onpath_prefix" >/dev/null
  if [[ -f "${onpath_home}/.zshrc" ]]; then
    bad "skip path edit when present" "$(cat "${onpath_home}/.zshrc")"
  else
    ok "skip path edit when present"
  fi

  local dist api
  dist="${base}/dist"
  "$BASH_BIN" "$ROOT/scripts/package.sh" "$dist" >/dev/null
  api="${base}/api.json"
  printf '%s\n' '{"tag_name":"v0.1.0"}' > "$api"
  local release_home release_prefix log
  release_home="${base}/home-release"
  release_prefix="${base}/release prefix"
  log="${base}/curl.log"
  mkdir -p "$release_home"
  : > "$log"
  env \
    HOME="$release_home" \
    SHELL="/bin/bash" \
    GHSM_CURL="${ROOT}/tests/fake-curl.sh" \
    GH_FAKE_CURL_LOG="$log" \
    GH_FAKE_API="$api" \
    GH_FAKE_TARBALL="${dist}/ghsm.tar.gz" \
    GH_FAKE_SUMS="${dist}/checksums.txt" \
    "$BASH_BIN" "$ROOT/install.sh" --prefix "$release_prefix" >"${base}/rel.out" 2>"${base}/rel.err"
  assert_eq "release install status" "0" "$?"
  assert_contains "release install message" "$(cat "${base}/rel.out")" "Installed ghsm 0.1.0"
  env \
    HOME="$release_home" \
    SHELL="/bin/bash" \
    GHSM_CURL="${ROOT}/tests/fake-curl.sh" \
    GH_FAKE_CURL_LOG="$log" \
    GH_FAKE_API="$api" \
    GH_FAKE_TARBALL="${dist}/ghsm.tar.gz" \
    GH_FAKE_SUMS="${dist}/checksums.txt" \
    "$BASH_BIN" "$ROOT/install.sh" --prefix "$release_prefix" >"${base}/rel2.out"
  assert_contains "second install skips download" "$(cat "${base}/rel2.out")" "already installed"
  local tarball_hits
  tarball_hits="$(grep -c 'ghsm.tar.gz' "$log" || true)"
  assert_eq "tarball downloaded once" "1" "$tarball_hits"

  printf '%s\n' '0000000000000000000000000000000000000000000000000000000000000000  ghsm.tar.gz' \
    > "${base}/bad-sums.txt"
  local bad_prefix bad_code
  bad_prefix="${base}/bad"
  set +e
  env \
    HOME="$release_home" \
    SHELL="/bin/bash" \
    GHSM_CURL="${ROOT}/tests/fake-curl.sh" \
    GH_FAKE_CURL_LOG="${base}/bad.log" \
    GH_FAKE_API="$api" \
    GH_FAKE_TARBALL="${dist}/ghsm.tar.gz" \
    GH_FAKE_SUMS="${base}/bad-sums.txt" \
    "$BASH_BIN" "$ROOT/install.sh" --prefix "$bad_prefix" --force >"${base}/bad.out" 2>"${base}/bad.err"
  bad_code=$?
  set -e
  assert_eq "checksum mismatch status" "1" "$bad_code"
  assert_contains "checksum mismatch message" "$(cat "${base}/bad.err")" "checksum mismatch"
  if [[ -e "${bad_prefix}/bin/ghsm" ]]; then
    bad "checksum mismatch installs nothing"
  else
    ok "checksum mismatch installs nothing"
  fi

  local su_home su_prefix
  su_home="${base}/su-home"
  su_prefix="${base}/su prefix"
  mkdir -p "$su_home"
  : > "${base}/su.log"
  set +e
  env \
    HOME="$su_home" \
    SHELL="/bin/zsh" \
    ZDOTDIR="$su_home" \
    GHSM_NO_UPDATE_CHECK=1 \
    GHSM_CURL="${ROOT}/tests/fake-curl.sh" \
    GH_FAKE_CURL_LOG="${base}/su.log" \
    GH_FAKE_API="$api" \
    GH_FAKE_TARBALL="${dist}/ghsm.tar.gz" \
    GH_FAKE_SUMS="${dist}/checksums.txt" \
    "$BASH_BIN" "$BIN" self-update --prefix "$su_prefix" >"${base}/su.out" 2>"${base}/su.err"
  code=$?
  set -e
  assert_eq "self-update status" "0" "$code"
  assert_contains "self-update installed" "$(cat "${base}/su.out")" "Installed ghsm 0.1.0"
  env HOME="$su_home" "${su_prefix}/bin/ghsm" --version >"${base}/su.ver"
  assert_eq "self-updated binary" "ghsm 0.1.0" "$(cat "${base}/su.ver")"

  rm -rf "$base"
}

syntax_check
test_version_and_help
test_version_compare
test_missing_dependency
test_add_update_list_remove
test_custom_manifest
test_invalid_manifest_and_git_root
test_update_notice_does_not_block
test_self_update_check
test_installer

printf '\n%s passed, %s failed\n' "$PASS" "$FAIL"
if [[ "$FAIL" -ne 0 ]]; then
  exit 1
fi
