# ghsm

`ghsm` installs and updates agent skills for a project. The project keeps a `skills.json` manifest. The command applies that manifest with [`gh skill`](https://cli.github.com/manual/gh_skill) into `.agent/skills`.

It is a Bash program. It runs on macOS and Linux, including the Bash 3.2 that ships with macOS. It needs the GitHub CLI (`gh`) and `jq`.

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/eriktorsner/ghsm/main/install.sh | bash
```

A specific release:

```bash
curl -fsSL https://raw.githubusercontent.com/eriktorsner/ghsm/main/install.sh | bash -s -- --version v0.1.0
```

The installer puts the executable on `~/.local/bin` and the program files in `~/.local/share/ghsm`. It creates those directories, checks that the download matches the release checksum, and can be run again safely. It does not use sudo. When `~/.local/bin` is missing from `PATH`, it appends one marked block to the current shell's rc file (`.zshrc` on zsh, `.bash_profile` on macOS bash, `.bashrc` on other bash). Running it again does not add a second block.

From a checkout, without a GitHub release:

```bash
./install.sh --from-source .
```

## Skills manifest

`skills.json` lives at the git repository root:

```json
{
  "version": 1,
  "skills": [
    {"repo": "owner/name", "skill": "git-commit"},
    {"repo": "owner/name", "skill": "code-review", "ref": "v1.2.0"}
  ]
}
```

`repo` is a GitHub `owner/name`. `skill` is a skill name or a path inside that repository. `ref` pins a tag or commit. Without `ref`, `gh skill` uses the latest release and then the default branch.

The default file is `skills.json` at the repository root. Pass another path when one repository needs more than one list. `-m` / `--manifest` overrides `GHSM_MANIFEST`. A relative path is resolved from the working directory. Skills from every manifest install into that repository's `.agent/skills`.

```bash
ghsm --manifest teams/review.json update
GHSM_MANIFEST=teams/docs.json ghsm add owner/name docs-review
```

```bash
ghsm add owner/name git-commit
ghsm add owner/name code-review@v1.2.0
ghsm update
ghsm update --check
ghsm update --force
ghsm list
ghsm remove code-review
```

`update` walks the manifest. `update --check` reports what would change. `update --force` reinstalls every selected skill. `list` reads `.agent/skills`. `remove` deletes that directory and the manifest entry.

`--json` prints a JSON object on stdout. `-q` hides notices. `-v` prints the `gh` command.

Exit codes: `0` success, `1` runtime error, `2` usage error, `3` missing `gh` or `jq`, `4` skill not found, `5` one or more skills failed.

## Updating ghsm itself

`update` syncs project skills. `self-update` replaces this command from GitHub Releases:

```bash
ghsm self-update --check
ghsm self-update
ghsm self-update --force
```

Other commands check for a new release in the background. The check is cached for a day, and a network failure does not affect the command. On macOS the cache is `~/Library/Caches/ghsm`. On Linux it is `${XDG_CACHE_HOME:-~/.cache}/ghsm`.

```bash
export GHSM_NO_UPDATE_CHECK=1
```

## Development

```bash
/bin/bash tests/run.sh
```

`scripts/package.sh` builds `dist/ghsm.tar.gz` and `dist/checksums.txt`. A tag `vX.Y.Z` whose version matches `lib/version.sh` publishes those files as a GitHub Release.
