---
name: security-fix-workflow
description: Fix verified vulnerabilities as small, independently reviewed changes - one issue and one pull request per rule, tests proven by breaking the fix, an independent review (codex review or /security-review), CI, then merge - optionally in parallel lanes. Use when the user asks to fix findings from a security audit, harden an app, or work through a list of vulnerabilities with issues and PRs.
---

# Security fix workflow

Each fix is one rule, one issue, one PR. Small PRs make reviews meaningful and reverts cheap.

## Where to file

- If the repository is public, file issues and PRs in a private repository (or a GitHub
  Security Advisory with a temporary private fork) until the fix ships. Publish afterwards.
- Check which repository deploys to production before promising that a merge fixes production.

## Per fix

1. **Issue** (the plan): summary, background, actual behaviour, required behaviour as brief
   Given-When-Then, test design (rule or risk, owning test layer, representative scenarios,
   upper-layer wiring, reason if not automated), non-scope, files, acceptance criteria,
   verification steps, risk and rollback. Template: `templates/issue-security.md`.
   Do not paste copy-ready exploit payloads.
2. **Branch** from the latest base: `fix/issue-<n>-<slug>`.
3. **Implement** the smallest change that enforces the rule. Put the decision logic in a pure
   function so it can be unit-tested without the framework.
4. **Test at the owning layer**, plus the one wiring test that proves the route or page uses it.
5. **Prove the tests.** Temporarily disable the fix — keep it type-correct, otherwise the build
   fails and proves nothing — confirm the relevant tests fail, restore, confirm they pass.
   If a test still passes with the fix disabled, its data is rejected by some other rule; change
   the test data so only the rule under test rejects it.
6. **Check legitimate flows** the rule might block: what the real UI sends, including restored
   state, uploads, iframe embeds and long inputs. Independent reviews often catch these.
7. **PR** (the result): actual behaviour, differences from the issue, final test design, and only
   results actually run on the current head. Exactly one `Closes #<n>`. Template:
   `templates/pull_request.md`.
8. **Independent review**: `codex review --base <base>` or `/security-review`. Fix P0/P1 and valid
   P2, push, and review again until clean. Record every review round in the PR.
9. **CI** on the current head must pass. Then merge (`gh pr merge --merge --delete-branch`) only if
   the user has authorised merging.
10. **Verify the issue closed.** If the PR's `closingIssuesReferences` was empty, close the issue
    manually with a reference to the PR.

## Parallel lanes

- Split by files touched. Routes that share helpers belong to one lane; independent concerns
  (headers, robots, cookies, dead-code removal, UI escaping) can run in parallel.
- When two lanes need the same file, keep the shared change in one lane and leave a thin
  compatibility shim; remove it in a follow-up once both have merged.
- Tests that bind fixed ports (E2E) run locally in one lane only; other lanes rely on CI.
- Before merging lane PRs, check mergeability against the latest base and that the changed file
  sets do not overlap (`git merge-tree --write-tree <base> <branch>`).

## Decisions that are not yours

Ask before choosing allowed origins or domains (iframe embedding, link and image allowlists),
changing behaviour users can see (limits, blocked content), publishing to a public repository,
rotating secrets, or touching dashboards. Record the decision in the issue.
