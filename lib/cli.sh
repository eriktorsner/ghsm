# Command routing, help, and global flags.

cli_help_general() {
  cat <<EOF
ghsm ${GHSM_VERSION}
Install and update agent skills recorded in a project's skills.json.

Usage:
  ghsm <command> [flags]

Commands:
  update           Install or update every skill in skills.json
  add              Install a GitHub skill and record it in skills.json
  remove           Remove a skill from .agents/skills and from skills.json
  list             List skills installed in this project
  self-update      Update the ghsm command from GitHub Releases
  completion       Print a shell completion script
  help             Show help for a command

Global flags:
  -h, --help       Show help
  -V, --version    Show the ghsm version
  -q, --quiet      Suppress notices
  -v, --verbose    Show the underlying gh commands
  -m, --manifest   Read and write this manifest instead of skills.json
      --json       Print machine-readable JSON on stdout
      --color      Colorize stderr
      --no-color   Disable color

Project files:
  skills.json      Default manifest at the git repository root
  .agents/skills   Directory skills are installed into
  .claude/skills   Relative symlinks to those directories, for Claude Code

A repository can keep more than one manifest. Pass -m or set GHSM_MANIFEST.
The flag wins when both are set. A relative path is resolved from the
working directory. Every manifest installs into the same .agents/skills.

Environment:
  GHSM_MANIFEST=PATH       Same as --manifest
  GHSM_NO_UPDATE_CHECK=1   Skip the periodic release check
  GHSM_JSON=1              Same as --json
  GHSM_QUIET=1             Same as --quiet
  NO_COLOR                      Disable color

Exit codes:
  0  Success
  1  Runtime error
  2  Usage error
  3  Missing gh or jq
  4  Skill not found
  5  One or more skills failed

Examples:
  ghsm update
  ghsm --manifest teams/review.json update
  ghsm list --json

Run ghsm help <command> for command details.
EOF
}

cli_help_update() {
  cat <<'EOF'
Usage:
  ghsm update [skill...] [--check | --force]

Install or update the skills listed in skills.json. Each entry is applied
with gh skill into the project's .agents/skills directory. Each installed
skill also gets a relative symlink at .claude/skills/<name>.

  --check    Report what would change. Do not write files.
  --force    Reinstall every selected skill.

With skill names, only those manifest entries are processed. A name matches
the skill field or the last path component of that field.

Pinned entries (those with a ref) are installed at that ref. Entries without
a ref follow the latest release, then the repository's default branch.

skills.json:
  {
    "version": 1,
    "skills": [
      {"repo": "owner/name", "skill": "git-commit"},
      {"repo": "owner/name", "skill": "code-review", "ref": "v1.2.0"}
    ]
  }

Examples:
  ghsm update
  ghsm update --check
  ghsm update --force code-review
  ghsm update --json
EOF
}

cli_help_add() {
  cat <<'EOF'
Usage:
  ghsm add OWNER/REPO SKILL[@REF]

Install one skill with gh skill and append it to skills.json. Repeating the
command updates the recorded ref and reinstalls the skill.

Examples:
  ghsm add cli/cli gh-skill
  ghsm add owner/skills code-review@v1.2.0
  ghsm add owner/skills skills/review --json
EOF
}

cli_help_remove() {
  cat <<'EOF'
Usage:
  ghsm remove SKILL
  ghsm remove OWNER/REPO SKILL

Delete the installed skill directory under .agents/skills, delete the Claude
symlink when ghsm created it, and drop the matching skills.json entry. A real
directory at the Claude path is left alone. When several repositories record
the same skill name, pass the repository as well.

Examples:
  ghsm remove code-review
  ghsm remove owner/skills code-review
EOF
}

cli_help_list() {
  cat <<'EOF'
Usage:
  ghsm list

List skills installed in the project's .agents/skills directory. The MANIFEST
column shows whether skills.json also records that skill.

Examples:
  ghsm list
  ghsm list --json
EOF
}

cli_help_self_update() {
  cat <<'EOF'
Usage:
  ghsm self-update [--check | --force] [--prefix DIR]

Download a GitHub Release of ghsm, verify its checksum, and install it.
The ordinary update command syncs project skills and does not replace this
command.

  --check     Compare the running version with the latest release.
  --force     Reinstall even when the version is already current.
  --prefix    Install under DIR (default: ~/.local).

A release check also runs in the background on other commands. It caches the
result for a day and never blocks the command. Set GHSM_NO_UPDATE_CHECK=1
to disable that check. On macOS the cache is ~/Library/Caches/ghsm. On
Linux it is ${XDG_CACHE_HOME:-~/.cache}/ghsm.

Examples:
  ghsm self-update --check
  ghsm self-update
  ghsm self-update --force
EOF
}

cli_help_completion() {
  cat <<'EOF'
Usage:
  ghsm completion bash
  ghsm completion zsh

Print a completion script. Save it or source it from your shell rc file.
EOF
}

cli_completion_bash() {
  cat <<'EOF'
_ghsm() {
  local cur
  COMPREPLY=()
  cur="${COMP_WORDS[COMP_CWORD]}"
  if [[ ${COMP_CWORD} -eq 1 ]]; then
    COMPREPLY=( $(compgen -W "update add remove list self-update completion help" -- "$cur") )
    return 0
  fi
  case "${COMP_WORDS[1]}" in
    update|self-update)
      COMPREPLY=( $(compgen -W "--check --force --help --json" -- "$cur") )
      ;;
    add|remove|list|completion|help)
      COMPREPLY=( $(compgen -W "--help --json" -- "$cur") )
      ;;
  esac
}
complete -F _ghsm ghsm
EOF
}

cli_completion_zsh() {
  cat <<'EOF'
#compdef ghsm
_ghsm() {
  local -a commands
  commands=(
    'update:Install or update skills from skills.json'
    'add:Install a skill and record it'
    'remove:Remove a skill'
    'list:List installed skills'
    'self-update:Update ghsm itself'
    'completion:Print a completion script'
    'help:Show help'
  )
  if (( CURRENT == 2 )); then
    _describe 'command' commands
  fi
}
compdef _ghsm ghsm
EOF
}

cli_cmd_completion() {
  local shell_name="${1:-}"
  if [[ $# -gt 1 ]]; then
    ui_error "usage: ghsm completion bash|zsh"
    return 2
  fi
  case "$shell_name" in
    bash) cli_completion_bash ;;
    zsh) cli_completion_zsh ;;
    *)
      ui_error "usage: ghsm completion bash|zsh"
      return 2
      ;;
  esac
}

cli_cmd_help() {
  local topic="${1:-}"
  if [[ $# -gt 1 ]]; then
    ui_error "usage: ghsm help [command]"
    return 2
  fi
  case "$topic" in
    ""|ghsm) cli_help_general ;;
    update) cli_help_update ;;
    add) cli_help_add ;;
    remove|rm) cli_help_remove ;;
    list|ls) cli_help_list ;;
    self-update) cli_help_self_update ;;
    completion) cli_help_completion ;;
    *)
      ui_error "unknown help topic: ${topic}"
      return 2
      ;;
  esac
}

cli_cmd_version() {
  if ui_json_mode; then
    jq -nc --arg version "$GHSM_VERSION" '{version:$version}'
  else
    printf 'ghsm %s\n' "$GHSM_VERSION"
  fi
}

cli_main() {
  if [[ "${GHSM_JSON:-}" == "1" ]]; then
    GHSM_JSON=1
  else
    GHSM_JSON=0
  fi
  if [[ "${GHSM_QUIET:-}" == "1" ]]; then
    GHSM_QUIET=1
  else
    GHSM_QUIET=0
  fi
  if [[ "${GHSM_VERBOSE:-}" == "1" ]]; then
    GHSM_VERBOSE=1
  else
    GHSM_VERBOSE=0
  fi
  if [[ -n "${NO_COLOR:-}" ]]; then
    GHSM_COLOR=never
  else
    GHSM_COLOR="${GHSM_COLOR:-auto}"
  fi

  local command="" help_for=""
  local -a positionals=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --json) GHSM_JSON=1; shift ;;
      -q|--quiet) GHSM_QUIET=1; shift ;;
      -v|--verbose) GHSM_VERBOSE=1; shift ;;
      --no-color) GHSM_COLOR=never; shift ;;
      --color) GHSM_COLOR=always; shift ;;
      -m|--manifest)
        if [[ $# -lt 2 || -z "${2:-}" || "$2" == -* ]]; then
          ui_error "usage: --manifest PATH"
          return 2
        fi
        GHSM_MANIFEST="$2"
        shift 2
        ;;
      --manifest=*)
        GHSM_MANIFEST="${1#--manifest=}"
        if [[ -z "$GHSM_MANIFEST" ]]; then
          ui_error "usage: --manifest PATH"
          return 2
        fi
        shift
        ;;
      -V|--version)
        command="version"
        shift
        ;;
      -h|--help)
        if [[ -z "$command" ]]; then
          command="help"
        else
          help_for="$command"
          command="help"
        fi
        shift
        ;;
      --)
        shift
        while [[ $# -gt 0 ]]; do
          positionals+=("$1")
          shift
        done
        ;;
      -*)
        positionals+=("$1")
        shift
        ;;
      *)
        if [[ -z "$command" ]]; then
          command="$1"
        else
          positionals+=("$1")
        fi
        shift
        ;;
    esac
  done

  ui_configure_color

  case "$command" in
    self-update) ;;
    *) upd_maybe_notify || true ;;
  esac

  case "$command" in
    "")
      ui_error "a command is required"
      cli_help_general
      return 2
      ;;
    help)
      if [[ -n "$help_for" ]]; then
        cli_cmd_help "$help_for"
      else
        cli_cmd_help ${positionals[@]+"${positionals[@]}"}
      fi
      ;;
    version)
      if [[ ${#positionals[@]} -gt 0 ]]; then
        ui_error "unknown argument: ${positionals[0]}"
        return 2
      fi
      cli_cmd_version
      ;;
    update)
      skills_cmd_update ${positionals[@]+"${positionals[@]}"}
      ;;
    add)
      skills_cmd_add ${positionals[@]+"${positionals[@]}"}
      ;;
    remove|rm)
      skills_cmd_remove ${positionals[@]+"${positionals[@]}"}
      ;;
    list|ls)
      skills_cmd_list ${positionals[@]+"${positionals[@]}"}
      ;;
    self-update)
      upd_cmd_self_update ${positionals[@]+"${positionals[@]}"}
      ;;
    completion)
      cli_cmd_completion ${positionals[@]+"${positionals[@]}"}
      ;;
    *)
      ui_error "unknown command: ${command}"
      cli_help_general >&2
      return 2
      ;;
  esac
}
