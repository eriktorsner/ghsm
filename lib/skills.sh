# Project skill manifest. This file is the gh skill wrapper.
# CLI parsing, help, and self-update live elsewhere.

SKILLS_DIR_REL=".agent/skills"
SKILLS_MANIFEST_NAME="skills.json"

skills_run_gh() {
  if [[ "${GHSM_VERBOSE:-0}" == "1" ]]; then
    ui_verbose "gh $(printf '%q ' "$@")"
  fi
  if [[ -n "${GHSM_GH:-}" ]]; then
    "$GHSM_GH" "$@"
    return
  fi
  command gh "$@"
}

skills_valid_repo() {
  local repo="$1"
  [[ "$repo" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]]
}

skills_valid_skill() {
  local skill="$1"
  [[ "$skill" =~ ^[A-Za-z0-9_./-]+$ ]] || return 1
  [[ "$skill" != *..* && "$skill" != /* && "$skill" != */ && "$skill" != "." ]]
}

skills_valid_ref() {
  local ref="$1"
  [[ -z "$ref" ]] && return 0
  [[ "$ref" =~ ^[A-Za-z0-9_./+-]+$ ]]
}

# Sets SKILLS_PARSED_NAME and SKILLS_PARSED_REF. Splits on the first @.
skills_parse_spec() {
  local spec="$1"
  case "$spec" in
    *@*)
      SKILLS_PARSED_NAME="${spec%%@*}"
      SKILLS_PARSED_REF="${spec#*@}"
      ;;
    *)
      SKILLS_PARSED_NAME="$spec"
      SKILLS_PARSED_REF=""
      ;;
  esac
  skills_valid_skill "$SKILLS_PARSED_NAME" || return 1
  skills_valid_ref "$SKILLS_PARSED_REF" || return 1
}

# Absolute paths are used as given. Relative paths are resolved from the
# working directory, so one repository can keep several manifests.
skills_resolve_manifest_path() {
  local given="$1" dir base
  if [[ -z "$given" ]]; then
    ui_error "usage: --manifest PATH"
    return 2
  fi
  case "$given" in
    /*) ;;
    *) given="$(pwd)/${given}" ;;
  esac
  dir="$(dirname "$given")"
  base="$(basename "$given")"
  if [[ "$base" == "." || "$base" == ".." ]]; then
    ui_error "manifest path must be a file"
    return 2
  fi
  if [[ ! -d "$dir" ]]; then
    ui_error "manifest directory does not exist: ${dir}"
    return 1
  fi
  dir="$(cd "$dir" && pwd)" || return 1
  SKILLS_MANIFEST="${dir}/${base}"
}

skills_project_paths() {
  SKILLS_ROOT="$(util_project_root)" || return 1
  SKILLS_DEST="${SKILLS_ROOT}/${SKILLS_DIR_REL}"
  if [[ -n "${GHSM_MANIFEST:-}" ]]; then
    skills_resolve_manifest_path "$GHSM_MANIFEST" || return 1
  else
    SKILLS_MANIFEST="${SKILLS_ROOT}/${SKILLS_MANIFEST_NAME}"
  fi
}

skills_validate_manifest() {
  local file="$1" err
  if ! err="$(jq -e '
    type == "object"
    and (.skills | type == "array")
    and all(.skills[]?;
      (.repo | type == "string")
      and (.skill | type == "string")
      and ((.ref // "") | type == "string")
    )
  ' "$file" >/dev/null 2>&1)"; then
    ui_error "skills.json at ${file} is not valid. Expected {\"version\":1,\"skills\":[{\"repo\":\"owner/name\",\"skill\":\"name\"}]}"
    return 1
  fi
  local bad
  bad="$(jq -r '
    .skills[]
    | select(
        (.repo | test("^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$") | not)
        or (.skill | test("^[A-Za-z0-9_./-]+$") | not)
        or (.skill | test("(^/)|(^\\.)|(\\.\\.)") )
        or ((.ref // "") | test("^[A-Za-z0-9_./+-]*$") | not)
      )
    | "\(.repo) \(.skill)"
  ' "$file")"
  if [[ -n "$bad" ]]; then
    ui_error "skills.json contains an invalid skill entry: ${bad}"
    return 1
  fi
  return 0
}

skills_install_spec() {
  local skill="$1" ref="$2"
  if [[ -n "$ref" ]]; then
    printf '%s@%s\n' "$skill" "$ref"
  else
    printf '%s\n' "$skill"
  fi
}

# Print one installed-skill JSON object, or nothing when it is not installed.
skills_find_installed() {
  local list_json="$1" repo="$2" skill="$3" base
  base="$(basename "$skill")"
  printf '%s' "$list_json" | jq -c \
    --arg repo "$repo" \
    --arg skill "$skill" \
    --arg base "$base" '
      [ .[] | select(
          (
            ((.sourceURL // "") | contains($repo))
            and (
              .skillName == $skill
              or .skillName == $base
              or ((.sourceURL // "") | contains($skill))
            )
          )
          or (
            (.sourceURL // "") == ""
            and (.skillName == $skill or .skillName == $base)
          )
        )
      ] | .[0] // empty
    '
}

skills_list_installed_json() {
  local dest="$1" err raw
  if [[ ! -d "$dest" ]]; then
    printf '[]\n'
    return 0
  fi
  err="$(util_mktemp_file)"
  if ! raw="$(skills_run_gh skill list --dir "$dest" --json skillName,sourceURL,version,pinned,path 2>"$err")"; then
    ui_warn "could not list installed skills with gh"
    if [[ "${GHSM_VERBOSE:-0}" == "1" ]]; then
      cat "$err" >&2
    fi
    printf '[]\n'
    return 0
  fi
  if ! printf '%s' "$raw" | jq -e 'type == "array"' >/dev/null 2>&1; then
    ui_warn "gh skill list returned unexpected output"
    printf '[]\n'
    return 0
  fi
  printf '%s\n' "$raw"
}

skills_record_result() {
  local file="$1" repo="$2" skill="$3" operation="$4" status="$5" error="$6"
  jq -nc \
    --arg repo "$repo" \
    --arg skill "$skill" \
    --arg operation "$operation" \
    --arg status "$status" \
    --arg error "$error" \
    '{repo:$repo, skill:$skill, operation:$operation, status:$status, error:$error}' >> "$file"
}

skills_emit_results() {
  local ndjson="$1"
  local failed=0
  if ui_json_mode; then
    if [[ ! -s "$ndjson" ]]; then
      printf '%s\n' '{"results":[]}'
    else
      jq -sc '{results:.}' "$ndjson"
    fi
  elif [[ ! -s "$ndjson" ]]; then
    ui_info "No skills to process."
  else
    jq -r '
      . as $row
      | [ (if $row.status == "ok" then $row.operation else $row.status end), $row.repo, $row.skill, ($row.error // "") ]
      | map(select(length > 0))
      | join("  ")
    ' "$ndjson"
    failed="$(jq -s '[.[] | select(.status == "failed")] | length' "$ndjson")"
    local ok_n
    ok_n="$(jq -s '[.[] | select(.status == "ok")] | length' "$ndjson")"
    if [[ "${GHSM_QUIET:-0}" != "1" ]]; then
      if [[ "$failed" == "0" ]]; then
        ui_info "${ok_n} skill(s) processed"
      else
        ui_warn "${ok_n} succeeded, ${failed} failed"
      fi
    fi
  fi
  if [[ -s "$ndjson" ]]; then
    failed="$(jq -s '[.[] | select(.status == "failed")] | length' "$ndjson")"
  else
    failed=0
  fi
  if [[ "$failed" != "0" ]]; then
    return 5
  fi
  return 0
}

skills_selected_rows() {
  local manifest="$1"
  shift
  local names_json="[]"
  local name
  for name in "$@"; do
    names_json="$(printf '%s' "$names_json" | jq --arg name "$name" '. + [$name]')"
  done
  jq -c --argjson names "$names_json" '
    .skills
    | if ($names | length) == 0 then .
      else map(select(
          .skill as $s
          | ($names | index($s)) != null
            or ($names | index($s | split("/") | last)) != null
        ))
      end
  ' "$manifest"
}

skills_missing_names() {
  local manifest="$1"
  shift
  local name found missing=""
  for name in "$@"; do
    found="$(jq -r --arg name "$name" '
      [ .skills[]
        | select(.skill == $name or ((.skill | split("/") | last) == $name))
      ] | length
    ' "$manifest")"
    if [[ "$found" == "0" ]]; then
      missing="${missing}${name}"$'\n'
    fi
  done
  printf '%s' "$missing"
}

skills_cmd_update() {
  local check=0 force=0
  local -a only=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help)
        cli_help_update
        return 0
        ;;
      --check) check=1; shift ;;
      --force) force=1; shift ;;
      --)
        shift
        while [[ $# -gt 0 ]]; do
          only+=("$1")
          shift
        done
        ;;
      -*)
        ui_error "unknown flag for update: $1"
        return 2
        ;;
      *)
        only+=("$1")
        shift
        ;;
    esac
  done
  if [[ "$check" -eq 1 && "$force" -eq 1 ]]; then
    ui_error "use either --check or --force"
    return 2
  fi
  deps_require
  skills_project_paths || return 1
  if [[ ! -f "$SKILLS_MANIFEST" ]]; then
    ui_error "manifest not found at ${SKILLS_MANIFEST}. Add one with: ghsm add OWNER/REPO SKILL"
    return 1
  fi
  skills_validate_manifest "$SKILLS_MANIFEST" || return 1

  if [[ ${#only[@]} -gt 0 ]]; then
    local missing
    missing="$(skills_missing_names "$SKILLS_MANIFEST" "${only[@]}")"
    if [[ -n "$missing" ]]; then
      ui_error "not in skills.json: $(printf '%s' "$missing" | tr '\n' ' ')"
      return 4
    fi
  fi

  local rows
  if [[ ${#only[@]} -gt 0 ]]; then
    rows="$(skills_selected_rows "$SKILLS_MANIFEST" "${only[@]}")"
  else
    rows="$(jq -c '.skills' "$SKILLS_MANIFEST")"
  fi

  local list_json
  list_json="$(skills_list_installed_json "$SKILLS_DEST")"
  local ndjson
  ndjson="$(util_mktemp_file)"

  local row repo skill ref spec installed name operation status err_text gh_out gh_code
  local count
  count="$(printf '%s' "$rows" | jq 'length')"
  if [[ "$count" == "0" ]]; then
    skills_emit_results "$ndjson"
    return
  fi

  local i=0
  while [[ "$i" -lt "$count" ]]; do
    row="$(printf '%s' "$rows" | jq -c ".[$i]")"
    repo="$(printf '%s' "$row" | jq -r '.repo')"
    skill="$(printf '%s' "$row" | jq -r '.skill')"
    ref="$(printf '%s' "$row" | jq -r '.ref // ""')"
    spec="$(skills_install_spec "$skill" "$ref")"
    installed="$(skills_find_installed "$list_json" "$repo" "$skill")"
    name=""
    if [[ -n "$installed" ]]; then
      name="$(printf '%s' "$installed" | jq -r '.skillName')"
    fi
    operation=""
    status="ok"
    err_text=""
    gh_out=""
    gh_code=0

    if [[ "$check" -eq 1 ]]; then
      if [[ -z "$installed" ]]; then
        operation="would-install"
      elif [[ -n "$ref" ]]; then
        operation="pinned"
      else
        gh_out="$(skills_run_gh skill update "$name" --dir "$SKILLS_DEST" --dry-run 2>&1)" && gh_code=0 || gh_code=$?
        if [[ "$gh_code" -ne 0 ]]; then
          operation="check"
          status="failed"
          err_text="$(ui_one_line "$gh_out")"
        elif [[ "$gh_out" == *"update(s) available"* ]]; then
          operation="update-available"
        elif [[ "$gh_out" == *"is pinned"* ]]; then
          operation="pinned"
        else
          operation="up-to-date"
        fi
      fi
    elif [[ "$force" -eq 1 || -n "$ref" || -z "$installed" ]]; then
      mkdir -p "$SKILLS_DEST"
      operation="install"
      gh_out="$(skills_run_gh skill install "$repo" "$spec" --dir "$SKILLS_DEST" --force 2>&1)" && gh_code=0 || gh_code=$?
      if [[ "$gh_code" -ne 0 ]]; then
        status="failed"
        err_text="$(ui_one_line "$gh_out")"
      fi
    else
      operation="update"
      gh_out="$(skills_run_gh skill update "$name" --dir "$SKILLS_DEST" --all 2>&1)" && gh_code=0 || gh_code=$?
      if [[ "$gh_code" -ne 0 ]]; then
        status="failed"
        err_text="$(ui_one_line "$gh_out")"
      elif [[ "$gh_out" == *"is pinned"* ]]; then
        operation="skipped-pinned"
      fi
    fi

    skills_record_result "$ndjson" "$repo" "$skill" "$operation" "$status" "$err_text"
    i=$((i + 1))
  done

  skills_emit_results "$ndjson"
}

skills_manifest_upsert() {
  local manifest="$1" repo="$2" skill="$3" ref="$4"
  local dir tmp status=0
  dir="$(dirname "$manifest")"
  mkdir -p "$dir"
  tmp="$(mktemp "${dir}/skills.json.XXXXXX")"
  if [[ -f "$manifest" ]]; then
    jq --arg repo "$repo" --arg skill "$skill" --arg ref "$ref" '
      .version = (.version // 1)
      | .skills = (
          [ (.skills // [])[] | select(.repo != $repo or .skill != $skill) ]
          + [ if $ref == "" then {repo:$repo, skill:$skill} else {repo:$repo, skill:$skill, ref:$ref} end ]
        )
    ' "$manifest" > "$tmp" || status=$?
  else
    jq -n --arg repo "$repo" --arg skill "$skill" --arg ref "$ref" '
      {
        version: 1,
        skills: [ if $ref == "" then {repo:$repo, skill:$skill} else {repo:$repo, skill:$skill, ref:$ref} end ]
      }
    ' > "$tmp" || status=$?
  fi
  if [[ "$status" -ne 0 ]]; then
    rm -f "$tmp"
    return "$status"
  fi
  mv "$tmp" "$manifest"
}

skills_manifest_remove() {
  local manifest="$1" repo="$2" skill="$3"
  local dir tmp status=0
  dir="$(dirname "$manifest")"
  tmp="$(mktemp "${dir}/skills.json.XXXXXX")"
  jq --arg repo "$repo" --arg skill "$skill" '
    .skills = [ (.skills // [])[] | select(.repo != $repo or .skill != $skill) ]
  ' "$manifest" > "$tmp" || status=$?
  if [[ "$status" -ne 0 ]]; then
    rm -f "$tmp"
    return "$status"
  fi
  mv "$tmp" "$manifest"
}

skills_cmd_add() {
  local repo="" spec=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help)
        cli_help_add
        return 0
        ;;
      --)
        shift
        break
        ;;
      -*)
        ui_error "unknown flag for add: $1"
        return 2
        ;;
      *)
        if [[ -z "$repo" ]]; then
          repo="$1"
        elif [[ -z "$spec" ]]; then
          spec="$1"
        else
          ui_error "unexpected argument: $1"
          return 2
        fi
        shift
        ;;
    esac
  done
  while [[ $# -gt 0 ]]; do
    if [[ -z "$repo" ]]; then
      repo="$1"
    elif [[ -z "$spec" ]]; then
      spec="$1"
    else
      ui_error "unexpected argument: $1"
      return 2
    fi
    shift
  done
  if [[ -z "$repo" || -z "$spec" ]]; then
    ui_error "usage: ghsm add OWNER/REPO SKILL[@REF]"
    return 2
  fi
  if ! skills_valid_repo "$repo"; then
    ui_error "repository must look like owner/name"
    return 2
  fi
  if ! skills_parse_spec "$spec"; then
    ui_error "invalid skill. Use a name or path, optionally pinned as skill@ref"
    return 2
  fi
  local skill="$SKILLS_PARSED_NAME" ref="$SKILLS_PARSED_REF"
  deps_require
  skills_project_paths || return 1
  if [[ -f "$SKILLS_MANIFEST" ]]; then
    skills_validate_manifest "$SKILLS_MANIFEST" || return 1
  fi
  mkdir -p "$SKILLS_DEST"
  local gh_out gh_code=0 install_spec
  install_spec="$(skills_install_spec "$skill" "$ref")"
  gh_out="$(skills_run_gh skill install "$repo" "$install_spec" --dir "$SKILLS_DEST" --force 2>&1)" && gh_code=0 || gh_code=$?
  if [[ "$gh_code" -ne 0 ]]; then
    ui_error "gh skill install failed: $(ui_one_line "$gh_out")"
    return 1
  fi
  local lock="${SKILLS_ROOT}/.skills.json.lock"
  if ! util_acquire_lock "$lock"; then
    ui_error "installed ${skill} but could not lock skills.json"
    return 1
  fi
  local status=0
  skills_manifest_upsert "$SKILLS_MANIFEST" "$repo" "$skill" "$ref" || status=$?
  util_release_lock
  if [[ "$status" -ne 0 ]]; then
    ui_error "installed ${skill} but could not update skills.json"
    return 1
  fi
  if ui_json_mode; then
    jq -nc --arg repo "$repo" --arg skill "$skill" --arg ref "$ref" \
      '{repo:$repo, skill:$skill, ref:$ref, status:"ok"}'
  else
    printf 'added  %s  %s\n' "$repo" "$install_spec"
  fi
}

skills_safe_remove_dir() {
  local dest="$1" path="$2"
  [[ -n "$path" ]] || return 0
  [[ -e "$path" || -L "$path" ]] || return 0
  [[ -d "$dest" ]] || {
    ui_error "skills directory does not exist: ${dest}"
    return 1
  }
  local dest_real path_real
  dest_real="$(cd "$dest" && pwd)"
  if [[ -L "$path" ]]; then
    ui_error "refusing to remove symlink ${path}"
    return 1
  fi
  if [[ ! -d "$path" ]]; then
    ui_error "refusing to remove non-directory ${path}"
    return 1
  fi
  path_real="$(cd "$path" && pwd)"
  case "$path_real" in
    "$dest_real"/*) ;;
    *)
      ui_error "refusing to remove ${path_real} outside ${dest_real}"
      return 1
      ;;
  esac
  rm -rf "$path_real"
}

skills_cmd_remove() {
  local repo="" name=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help)
        cli_help_remove
        return 0
        ;;
      --)
        shift
        break
        ;;
      -*)
        ui_error "unknown flag for remove: $1"
        return 2
        ;;
      *)
        if [[ -z "$name" ]]; then
          name="$1"
        elif [[ -z "$repo" ]]; then
          repo="$name"
          name="$1"
        else
          ui_error "unexpected argument: $1"
          return 2
        fi
        shift
        ;;
    esac
  done
  while [[ $# -gt 0 ]]; do
    if [[ -z "$name" ]]; then
      name="$1"
    elif [[ -z "$repo" ]]; then
      repo="$name"
      name="$1"
    else
      ui_error "unexpected argument: $1"
      return 2
    fi
    shift
  done
  if [[ -z "$name" ]]; then
    ui_error "usage: ghsm remove SKILL    or    ghsm remove OWNER/REPO SKILL"
    return 2
  fi
  if [[ -n "$repo" ]] && ! skills_valid_repo "$repo"; then
    ui_error "repository must look like owner/name"
    return 2
  fi
  deps_require
  skills_project_paths || return 1

  local matches="[]"
  if [[ -f "$SKILLS_MANIFEST" ]]; then
    skills_validate_manifest "$SKILLS_MANIFEST" || return 1
    matches="$(jq -c --arg repo "$repo" --arg name "$name" '
      [ .skills[]
        | select(
            ($repo == "" or .repo == $repo)
            and (.skill == $name or ((.skill | split("/") | last) == $name))
          )
      ]
    ' "$SKILLS_MANIFEST")"
  fi
  local match_count
  match_count="$(printf '%s' "$matches" | jq 'length')"
  if [[ "$match_count" -gt 1 ]]; then
    ui_error "multiple skills match ${name}. Re-run with the repository:"
    printf '%s' "$matches" | jq -r '.[] | "  ghsm remove \(.repo) \(.skill)"' >&2
    return 2
  fi

  local list_json entry skill_name skill_repo skill_path
  list_json="$(skills_list_installed_json "$SKILLS_DEST")"
  entry=""
  skill_name=""
  skill_repo="$repo"
  if [[ "$match_count" -eq 1 ]]; then
    skill_repo="$(printf '%s' "$matches" | jq -r '.[0].repo')"
    skill_name="$(printf '%s' "$matches" | jq -r '.[0].skill')"
    entry="$(skills_find_installed "$list_json" "$skill_repo" "$skill_name")"
  else
    entry="$(printf '%s' "$list_json" | jq -c --arg name "$name" '
      [ .[] | select(.skillName == $name or (.path | split("/") | last) == $name) ] | .[0] // empty
    ')"
    skill_name="$name"
  fi

  if [[ "$match_count" -eq 0 && -z "$entry" ]]; then
    ui_error "skill not found: ${name}"
    return 4
  fi

  if [[ -n "$entry" ]]; then
    skill_path="$(printf '%s' "$entry" | jq -r '.path // ""')"
    skills_safe_remove_dir "$SKILLS_DEST" "$skill_path" || return 1
  else
    local base candidate
    base="$(basename "$skill_name")"
    for candidate in "${SKILLS_DEST}/${skill_name}" "${SKILLS_DEST}/${base}"; do
      if [[ -d "$candidate" ]]; then
        skills_safe_remove_dir "$SKILLS_DEST" "$candidate" || return 1
      fi
    done
  fi

  if [[ "$match_count" -eq 1 ]]; then
    local lock="${SKILLS_ROOT}/.skills.json.lock"
    if ! util_acquire_lock "$lock"; then
      ui_error "removed the skill directory but could not lock skills.json"
      return 1
    fi
    local status=0
    skills_manifest_remove "$SKILLS_MANIFEST" "$skill_repo" "$skill_name" || status=$?
    util_release_lock
    if [[ "$status" -ne 0 ]]; then
      ui_error "removed the skill directory but could not update skills.json"
      return 1
    fi
  fi

  if ui_json_mode; then
    jq -nc --arg repo "$skill_repo" --arg skill "$skill_name" \
      '{removed:[{repo:$repo, skill:$skill}]}'
  else
    if [[ -n "$skill_repo" ]]; then
      printf 'removed  %s  %s\n' "$skill_repo" "$skill_name"
    else
      printf 'removed  %s\n' "$skill_name"
    fi
  fi
}

skills_cmd_list() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help)
        cli_help_list
        return 0
        ;;
      --)
        shift
        break
        ;;
      -*)
        ui_error "unknown flag for list: $1"
        return 2
        ;;
      *)
        ui_error "unexpected argument: $1"
        return 2
        ;;
    esac
  done
  if [[ $# -gt 0 ]]; then
    ui_error "unexpected argument: $1"
    return 2
  fi
  deps_require
  skills_project_paths || return 1
  local declared='{"skills":[]}'
  if [[ -f "$SKILLS_MANIFEST" ]]; then
    skills_validate_manifest "$SKILLS_MANIFEST" || return 1
    declared="$(jq -c '{skills:(.skills // [])}' "$SKILLS_MANIFEST")"
  fi
  local installed
  installed="$(skills_list_installed_json "$SKILLS_DEST")"
  local rendered
  rendered="$(printf '%s' "$installed" | jq -c --argjson declared "$declared" '
    [ .[] | . as $s
      | ($s.skillName) as $name
      | (
          [ $declared.skills[]
            | select(.skill == $name or ((.skill | split("/") | last) == $name))
          ] | .[0] // {}
        ) as $m
      | {
          name: $name,
          path: ($s.path // ""),
          source_url: ($s.sourceURL // ""),
          repo: (
            if ($s.sourceURL // "") | contains("github.com/") then
              ($s.sourceURL | split("github.com/")[1] | split("/")[0:2] | join("/"))
            elif ($m.repo // "") != "" then
              $m.repo
            else
              ""
            end
          ),
          version: ($s.version // ""),
          ref: ($m.ref // ""),
          pinned: ($s.pinned // false),
          in_manifest: (($m.repo // "") != "")
        }
    ]
    | sort_by(.name)
  ')"
  if ui_json_mode; then
    jq -nc --argjson skills "$rendered" '{skills:$skills}'
    return 0
  fi
  local count
  count="$(printf '%s' "$rendered" | jq 'length')"
  if [[ "$count" == "0" ]]; then
    printf 'No skills installed in %s\n' "$SKILLS_DEST"
    return 0
  fi
  printf '%-24s %-28s %-16s %s\n' "NAME" "REPO" "VERSION" "MANIFEST"
  printf '%s' "$rendered" | jq -r '.[] | [.name, .repo, (if .version != "" then .version elif .ref != "" then .ref else "-" end), (if .in_manifest then "yes" else "no" end)] | @tsv' \
    | while IFS="$(printf '\t')" read -r name repo version manifest; do
        printf '%-24s %-28s %-16s %s\n' "$name" "$repo" "$version" "$manifest"
      done
}
