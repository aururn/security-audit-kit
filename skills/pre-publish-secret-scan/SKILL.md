---
name: pre-publish-secret-scan
description: Scan a repository's full git history and working tree for secrets before it becomes public or before private history is pushed to a public remote (making a repo public, pushing to a public fork, open-sourcing, mirroring). Use when the user is about to publish code, change repo visibility, or push a private branch history to a public repository. Blocks the publish until every hit is triaged.
---

# Pre-publish secret scan

Once history is public it cannot be taken back: forks, caches and scrapers keep it.
Scan everything that will be published, triage every hit, and only then push.

## 1. Decide what will be published

- The branch and all commits reachable from it (`git rev-list --count <public>/main..main`)
- Tags and other branches, if they will be pushed too
- GitHub-side content is not part of git (issues, PR bodies, wikis): check it separately if the
  repository itself changes visibility

## 2. Scan with values redacted

Use the kit's scanner: its gitleaks is pinned and checksum-verified. Use the first of these that
contains `scripts/run-scan.sh` as `KIT`:

1. `${CLAUDE_PLUGIN_ROOT}` (installed as a Claude Code plugin; skip this if it still reads
   literally as `${...}`)
2. Two directories above this skill's directory (a clone of the kit)
3. The path on the third line of `.kit-version` in this skill's directory (`install-skills.sh`)
4. None of these: `git clone --depth 1 https://github.com/aururn/security-audit-kit.git "${TMPDIR:-/tmp}/security-audit-kit"`

```sh
git fetch --all
SCAN_WORKTREE=1 bash "$KIT/scripts/run-scan.sh" . "${TMPDIR:-/tmp}/pre-publish-reports"
```

In `summary.txt`, `gitleaks` covers every commit on every ref and `gitleaks-worktree` covers the
files on disk, including gitignored ones such as `.env.local`.

- Do not publish until `gitleaks` is `ok`. A "SHALLOW clone" note means older history was not
  scanned: run `git fetch --unshallow` and scan again.
- `skipped` with "linked worktree or submodule" means this directory's git data is outside what the
  container can see (`git worktree add`, or a submodule). Scan the history from a mirror clone,
  which holds every ref and needs no outside directory. In that report, read only `gitleaks`;
  the other tools have nothing to scan in a bare repository.
  ```sh
  git clone -q --mirror . "${TMPDIR:-/tmp}/publish-mirror.git"
  bash "$KIT/scripts/run-scan.sh" "${TMPDIR:-/tmp}/publish-mirror.git" "${TMPDIR:-/tmp}/publish-mirror-reports"
  ```
- `gitleaks-worktree` skips build output and dependencies (`node_modules/`, `.next/`, `dist/`,
  `build/`). Only commits are published, and the history scan reads every committed file,
  including those directories. So commit everything you will publish first, then scan. If you
  commit again afterwards, scan again.

If `docker version` fails, ask the user to install or start Docker Desktop. If they decline and
`gitleaks` is installed locally, run it directly and say in the report that an unpinned local
gitleaks was used:

```sh
gitleaks git . --log-opts="--all" --redact --no-banner --report-format json --report-path gitleaks-history.json
gitleaks dir . --redact --no-banner --report-format json --report-path gitleaks-dir.json
```

Never print secret values in the report, chat, issues or logs. Summarise rule, file, line, commit.

## 3. Triage each hit

| Pattern | Usually | Confirm by |
| --- | --- | --- |
| Minified vendor bundles (`public/vs/**`, `*.min.js`) | false positive (identifier looks random) | read the matched token context |
| Build output (`.next/`, `dist/`, caches) | local random keys, never committed | `git check-ignore -v <path>`, and `git log --all --oneline -- <dir>` prints nothing |
| Test fixtures (`ci-test-key`, `example`) | fake | the value is used only by tests and fixtures |
| `generic-api-key` on an empty `NAME=` line (often `.env.example`) whose `StartLine` and `EndLine` differ | false positive only if line `EndLine` is a separate setting (`OTHER_NAME=...`) whose value is not a credential; the rule read that line as the value | nothing follows `=` on `StartLine`, and `sed -n '<EndLine>p' <file> \| grep -oE '^[A-Za-z_][A-Za-z0-9_.-]*='` prints another setting's `NAME=` (it prints nothing for a line without a name, so no value is shown). If line `EndLine` is a bare or indented value (an INI or YAML continuation), it is the value of `NAME`: treat the hit as real |
| `.env*` other than `.env.example` | real | `git ls-files` filtered for `.env` |

Also check what gitleaks does not know about:

- Service-specific key formats used by the project (for example Dify `app-...`, internal tokens)
- Private URLs, customer names and personal data in commit messages and docs

## 4. If something real is found

1. Treat the secret as leaked: ask the user to rotate or revoke it first. Rotation is what
   actually protects; rewriting history does not undo copies that already exist.
2. Only with explicit user approval, rewrite history (`git filter-repo`) and force-push.
3. Re-scan after the rewrite.

## 5. Push safely

- Verify the git identity and the GitHub account the user expects.
- Confirm the push is a fast-forward (`git merge-base --is-ancestor <public>/main main`);
  never force-push to publish.
- After pushing, check what the deploy pipeline did (a public fork may be the production
  deploy source) and verify production with read-only requests.
