---
name: security-audit
description: Audit a web app (especially Next.js / Node apps that proxy to LLM or SaaS APIs) for exploitable vulnerabilities and runaway-cost risks, verifying findings by reproduction rather than code reading alone. Use when the user asks to check a repo or deployment for vulnerabilities, "is this safe?", a security audit, a pre-launch review, or to look for problems like the Vercel/AI-crawler billing incident. Produces a severity-ranked report with evidence and a list of items that can only be checked in dashboards. Does not fix anything by itself; use security-fix-workflow for fixes.
---

# Security audit

Find vulnerabilities that are actually exploitable, prove them, and report them with evidence.
Code reading produces candidates; reproduction produces findings.

Read `references/principles.md` first (principles, severity, prohibitions; a copy of the kit's
`AGENTS.md`). Checklists live in `references/checklists/`; this skill says when to apply which.

## Find the kit

The scanner lives in the kit, not in this skill directory. Use the first of these that contains
`scripts/run-scan.sh` as `KIT`:

1. `${CLAUDE_PLUGIN_ROOT}` (installed as a Claude Code plugin; skip this if it still reads
   literally as `${...}`)
2. Two directories above this skill's directory (you are reading this from a clone of the kit)
3. The path on the third line of `.kit-version` in this skill's directory (installed with
   `scripts/install-skills.sh`)
4. None of these: clone the kit to a temporary directory. Do not install anything into the
   user's environment.
   ```sh
   git clone --depth 1 https://github.com/aururn/security-audit-kit.git "${TMPDIR:-/tmp}/security-audit-kit"
   ```

## Target

- **A local directory** (by default, the repository you are working in): audit it in place and do
  not modify it during the audit.
- **A GitHub URL**: clone it with full history (no `--depth`), so the secret scan covers every
  commit. For a private repository, use the user's own access (`gh repo clone`).
- **A running app URL with no source**: only black-box checks are possible: read-only requests
  (step 5) and, for localhost or a staging host the user owns, the DAST baseline
  (`KIT/docs/scanner.md`). State in the report that the code was not reviewed.

## 0. Scope and threat model (write it down before scanning)

Answer in the report:

- What is reachable without authentication? (pages, `/api/*`, Server Actions, static files)
- Who pays per request? (hosting transfer/functions, LLM tokens, third-party APIs)
- Where are secrets used, and can any reach the browser? (`NEXT_PUBLIC_*`, client bundles)
- Is the app embedded (iframe) on another site? Which origins are legitimate?
- Which repository and branch actually deploys to production? (Do not assume. A fork or a
  mirror may be the real deploy source.)
- Is the repository public? If so, findings go to a private channel (see `references/principles.md`).

Then fill in `references/templates/scope.md`: the target commit, the URLs where dynamic tests
are allowed (localhost or a staging host the user owns), the URLs that get read-only requests
only (production), and what will not be done. Show it to the user and get their approval
before step 4. Steps 4 and 5, the DAST baseline and any browser check go only to the URLs it
lists. If the user changes the scope later, update the file and get approval again. Keep the
file with the report, not in the target repository.

## 1. Map the entry points

- Route handlers, API routes, Server Actions, Middleware, webhooks, cron endpoints
- Upload endpoints, anything that proxies to an upstream API with a server-side key
- What the page does on load (SSR fetches, self-fetch to its own public URL, cache headers)
- Everything under `public/` (size, whether it is used at all)

Useful greps: `export async function (GET|POST|PUT|DELETE)`, `'use server'`, `process.env`,
`dangerouslySetInnerHTML`, `postMessage(`, `fetch(`, `NextResponse.json(.*error`.

Write the entry points down as a table, one row per entry point, and keep it in the report:

| Location | Method and path | Auth required | Input validated | Paid upstream | Checked |
| --- | --- | --- | --- | --- | --- |
| `app/api/chat/route.ts:12` | `POST /api/chat` | no | length only | LLM | reproduced (finding 1) |

Every row ends as `reproduced`, `checked, fine`, or `not checked (reason)`. The report's coverage
is this table, not a summary of it, so a reader can see what was not looked at.

## 2. Automated scans

Run the kit's scanner container: secrets in full history (gitleaks), dependencies incl.
known-malicious packages (osv-scanner), SAST (semgrep), GitHub Actions (zizmor, actionlint).
Write the reports outside the target, so they are never committed. The first run builds the
image, which takes a few minutes. Details: `KIT/docs/scanner.md`.

```sh
bash "$KIT/scripts/run-scan.sh" /path/to/target "${TMPDIR:-/tmp}/security-audit-reports"
```

Read `summary.txt` first. A tool with `error` did not scan; a `note` says what was not covered
(shallow clone, ignore files in the target, files semgrep could not parse, stale rules). Carry
both into the report's coverage.

If `docker version` fails, Docker is missing or not running. Ask the user to install or start
Docker Desktop, because the scan needs it. If they decline, continue with steps 3 to 6 and put
"automated scans not run (no Docker)" at the top of the report's coverage. Do not substitute
scanners downloaded on the spot: they are not pinned or verified.

Triage every hit. Typical false positives: minified vendor code, build output (`.next/`,
`dist/`), test fixtures with fake keys. Confirm build output is gitignored and never committed
before dismissing it. `pnpm audit --prod` counts dependencies declared in `dependencies`
even if they are dev tools (e.g. `eslint-config-next`); report them as such, not as runtime risk.

## 3. Manual review by category

Always apply `web-api.md` and `ai-generated-code.md`: they do not depend on the language or
framework. Add the others that match the stack. For a stack with no checklist of its own
(Python, Ruby, Go, PHP, mobile backends), apply those two plus the stack-independent ones
(supply chain, CI, secrets, cost), and say in the report that no stack-specific checklist was
applied.

| Area | Checklist |
| --- | --- |
| API routes, auth, CSRF, input, errors, cookies, headers, iframe | `references/checklists/web-api.md` |
| Mistakes typical of AI-written code: UI-only authorization, Supabase/Firebase rules, keys in the client, hallucinated packages, leftover stubs | `references/checklists/ai-generated-code.md` |
| Next.js / React specifics | `references/checklists/nextjs-react.md` |
| LLM / chatbot apps | `references/checklists/llm-app.md` |
| Billing and abuse | `references/checklists/cost-and-abuse.md` |
| Dependencies and install-time code | `references/checklists/supply-chain.md` |
| CI / GitHub Actions | `references/checklists/ci-github-actions.md` |
| Secrets and publishing a repo | `references/checklists/secrets-and-publishing.md` |

Trace data from the request to the sensitive sink. Pay special attention to SDKs that build
upstream URLs by string concatenation (IDs from the URL path joined without encoding let `..`
and `%2F` redirect an API-key-bearing request to another upstream path).

## 4. Reproduce locally

Only against the URLs the approved scope allows for dynamic tests. Never probe production
with attacks. Instead:

1. Start `fake-upstream.mjs` (in this skill directory). It logs method, path, whether an
   Authorization header was present, and the body; it can also answer with an error status.
   ```sh
   node fake-upstream.mjs ./upstream.log 4329        # always 200
   node fake-upstream.mjs ./upstream.log 4329 500    # always 500 (error paths)
   ```
2. Run the app pointing its upstream base URL at `http://127.0.0.1:4329/...` with a fake key.
3. Send the suspicious requests with `curl` and read `upstream.log`: what actually arrived,
   at which path, with which credentials.
4. For error paths, check both the HTTP response (internal addresses, stack traces) and the
   server log (API keys, Authorization headers).

### In a browser

XSS, CSRF with cookies and framing only show in a real browser. Use Playwright (`npx playwright`)
or a browser-automation tool you have, against the local app only.

- **XSS**: render the real component with hostile input (markdown, links, images, HTML). Use a
  payload that leaves a mark instead of `alert()`, such as
  `<img src=x onerror="document.title='XSS-1'">`, so no dialog blocks the browser. Then read
  `document.title` and the rendered HTML.
- **Clickjacking, CSRF, cross-site API calls**: start `attacker-page.mjs` (in this skill
  directory). It serves its pages from the other loopback name (`localhost` and `127.0.0.1`), so
  the browser treats them as another site and applies SameSite and CORS as for a real attacker.
  ```sh
  node attacker-page.mjs http://localhost:3000 4330
  ```
  - `/frame?path=/`: the app in an iframe. Take a screenshot: an unprotected app renders inside
    the frame; a protected one (`frame-ancestors` or `X-Frame-Options`) shows the browser's
    refused-frame page. The page cannot tell the two apart itself, because the frame is cross-site
  - `/form?path=/api/x&body={"message":"hi"}`: a cross-site `text/plain` POST whose body parses
    as JSON (the form's `=` goes at the end of the last string field, so no field is added).
    Read the app's log or `upstream.log`: was it processed with the user's cookies? If the session
    cookie has no SameSite attribute, run it again with `&top=1` (a top-level navigation): some
    browser versions send such cookies on a top-level cross-site POST for two minutes after they
    are set (Lax+POST), never on one into an iframe. Report which browser and version you used
  - `/fetch?path=/api/x&method=POST&body=...`: a credentialed cross-site fetch

  Log in to the app first in the same browser profile, so its cookies are sent as they would be
  for a real user. Chromium may block frames between loopback addresses (Local Network Access);
  for the test only, start it with `--disable-features=LocalNetworkAccessChecks`.

## 5. Production, read-only

Only the URLs the approved scope lists as read-only. Allowed: `GET` of pages and static files, response headers, cookie attributes, `robots.txt`,
sizes of large assets, requests that are rejected before reaching any paid upstream.
Not allowed: anything that triggers LLM calls, writes data, or scans aggressively.

```sh
curl -s -D - -o /dev/null https://example.app/            # headers, cache status
curl -s -o /dev/null -w '%{http_code} %{size_download}\n' https://example.app/some/large.js
```

## 6. Report

Follow the report style in `references/principles.md` (報告の書式): lead with the single most
severe finding and its fix, no preamble, no closing pleasantries.

For each finding: severity, location (`file:line`), what an attacker does, evidence
(what you reproduced and how), fix direction. Keep three lists separate:

1. Verified findings (reproduced)
2. Candidates not reproduced (and why)
3. Cannot be checked from code (dashboards: spend limits, rate limits, WAF/bot rules,
   LLM provider caps, deploy source) — ask the user

Add the coverage: the entry-point table from step 1, and which automated scans ran (with their
notes) and which did not. That is how the reader knows what was checked and found fine, and what
was not looked at.
