---
name: security-audit
description: Audit a web app (especially Next.js / Node apps that proxy to LLM or SaaS APIs) for exploitable vulnerabilities and runaway-cost risks, verifying findings by reproduction rather than code reading alone. Use when the user asks to check a repo or deployment for vulnerabilities, "is this safe?", a security audit, a pre-launch review, or to look for problems like the Vercel/AI-crawler billing incident. Produces a severity-ranked report with evidence and a list of items that can only be checked in dashboards. Does not fix anything by itself; use security-fix-workflow for fixes.
---

# Security audit

Find vulnerabilities that are actually exploitable, prove them, and report them with evidence.
Code reading produces candidates; reproduction produces findings.

Read `AGENTS.md` of this kit first (principles, severity, prohibitions). Checklists live in
`checklists/` of this kit; this skill says when to apply which.

## 0. Scope and threat model (write it down before scanning)

Answer in the report:

- What is reachable without authentication? (pages, `/api/*`, Server Actions, static files)
- Who pays per request? (hosting transfer/functions, LLM tokens, third-party APIs)
- Where are secrets used, and can any reach the browser? (`NEXT_PUBLIC_*`, client bundles)
- Is the app embedded (iframe) on another site? Which origins are legitimate?
- Which repository and branch actually deploys to production? (Do not assume. A fork or a
  mirror may be the real deploy source.)
- Is the repository public? If so, findings go to a private channel (see AGENTS.md).

## 1. Map the entry points

- Route handlers, API routes, Server Actions, Middleware, webhooks, cron endpoints
- Upload endpoints, anything that proxies to an upstream API with a server-side key
- What the page does on load (SSR fetches, self-fetch to its own public URL, cache headers)
- Everything under `public/` (size, whether it is used at all)

Useful greps: `export async function (GET|POST|PUT|DELETE)`, `'use server'`, `process.env`,
`dangerouslySetInnerHTML`, `postMessage(`, `fetch(`, `NextResponse.json(.*error`.

## 2. Automated scans

Run the container (see `README.md`): secrets in full history (gitleaks), dependencies incl.
known-malicious packages (osv-scanner), SAST (semgrep), GitHub Actions (zizmor, actionlint).

```sh
scripts/run-scan.sh /path/to/target ./reports
```

Triage every hit. Typical false positives: minified vendor code, build output (`.next/`,
`dist/`), test fixtures with fake keys. Confirm build output is gitignored and never committed
before dismissing it. `pnpm audit --prod` counts dependencies declared in `dependencies`
even if they are dev tools (e.g. `eslint-config-next`); report them as such, not as runtime risk.

## 3. Manual review by category

Apply the checklists that match the stack:

| Area | Checklist |
| --- | --- |
| API routes, auth, CSRF, input, errors, cookies, headers, iframe | `checklists/web-api.md` |
| Next.js / React specifics | `checklists/nextjs-react.md` |
| LLM / chatbot apps | `checklists/llm-app.md` |
| Billing and abuse | `checklists/cost-and-abuse.md` |
| Dependencies and install-time code | `checklists/supply-chain.md` |
| CI / GitHub Actions | `checklists/ci-github-actions.md` |
| Secrets and publishing a repo | `checklists/secrets-and-publishing.md` |

Trace data from the request to the sensitive sink. Pay special attention to SDKs that build
upstream URLs by string concatenation (IDs from the URL path joined without encoding let `..`
and `%2F` redirect an API-key-bearing request to another upstream path).

## 4. Reproduce locally

Never probe production with attacks. Instead:

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

For browser-side behaviour (XSS through markdown, link and image handling), render the real
component or library with hostile input and inspect the output HTML.

## 5. Production, read-only

Allowed: `GET` of pages and static files, response headers, cookie attributes, `robots.txt`,
sizes of large assets, requests that are rejected before reaching any paid upstream.
Not allowed: anything that triggers LLM calls, writes data, or scans aggressively.

```sh
curl -s -D - -o /dev/null https://example.app/            # headers, cache status
curl -s -o /dev/null -w '%{http_code} %{size_download}\n' https://example.app/some/large.js
```

## 6. Report

For each finding: severity, location (`file:line`), what an attacker does, evidence
(what you reproduced and how), fix direction. Keep three lists separate:

1. Verified findings (reproduced)
2. Candidates not reproduced (and why)
3. Cannot be checked from code (dashboards: spend limits, rate limits, WAF/bot rules,
   LLM provider caps, deploy source) — ask the user

Also list what was checked and found fine, so the reader knows the coverage.
