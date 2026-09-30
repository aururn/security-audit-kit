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

```sh
git fetch --all
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
