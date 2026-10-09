---
name: cost-abuse-review
description: Check a deployed web app for ways traffic can run up a bill - unauthenticated endpoints that call paid APIs (LLM tokens), dynamic pages with no caching, large public assets, missing robots rules, AI crawlers, and missing spend limits or rate limits. Use when the user worries about unexpected hosting or LLM bills (for example Vercel Fast Data Transfer or AI bot traffic), before launching a prototype publicly, or when leaving a demo site online.
---

# Cost and abuse review

Bill = cost per request x number of requests. Crawlers and scripts supply the second factor for
free; the review is about the first factor and about caps.

## 1. Cost per request

- Does the landing page render dynamically on every request? (`Cache-Control: no-store`,
  `x-vercel-cache: MISS`, the build output marks the route dynamic.) Why? Reading cookies or
  headers in the root layout makes every page dynamic.
- Does server rendering fetch its own public URL or a large dataset each time?
- Large files under `public/` (`find public -size +500k`) and whether anything uses them. Measure
  in production: `curl -s -o /dev/null -w '%{http_code} %{size_download}' <url>`.
- Endpoints reachable without authentication that call paid upstreams (LLM chat, title
  generation, embeddings, file processing). One `curl` loop means unbounded token spend.

## 2. Number of requests

- `robots.txt` present and appropriate (an embed-only app can disallow everything).
- AI crawlers: hosting WAF bot rules (on Vercel: the Bot Protection and AI Bots managed rulesets).
- Rate limits per IP or session on paid endpoints (a WAF rate limit, or a shared store; in-memory
  counters do not work across serverless instances).
- Cross-site use: can other sites embed the app (no `frame-ancestors`) or call its API from a
  browser (no Origin check)? Their visitors then spend your quota.

## 3. Caps and alerts (dashboard-only; ask the user)

- Hosting spend limit with automatic pause (Vercel Spend Management).
- LLM or upstream provider monthly caps and alerts.
- Usage alerts that reach a human.

## 4. Old deployments

- Stale demo or prototype deployments still public? Preview URLs protected?
- Which repository deploys production? Forks and mirrors can be the deploy source.

Report per item: current state (measured), risk, fix, and whether it needs code or a dashboard.
See `references/checklists/cost-and-abuse.md` for the full list.
