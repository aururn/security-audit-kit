// Cross-site "attacker" pages for checking a LOCAL app from another site, in a real browser:
// clickjacking (is the app framed?), CSRF (does a cross-site form post get processed?) and
// cross-site API calls (does a credentialed fetch from another site get through?).
// Usage: node attacker-page.mjs <target-origin> [port=4330]
//   /frame?path=/        the target page in an iframe
//   /form?path=/api/x&body={"message":"hi"}[&top=1]
//                        auto-submits a cross-site POST with a text/plain body that parses as JSON
//                        (no preflight; request.json() and many parsers accept it). The form's
//                        "=" goes inside the last string field, so no extra field is added.
//                        top=1 submits as a top-level navigation instead of into an iframe: some
//                        browser versions send cookies without a SameSite attribute only that way
//                        (Lax+POST, for two minutes after the cookie is set)
//   /fetch?path=/api/x&method=POST&body={...}
//                        a credentialed fetch; shows whether the response was readable
// The pages are served from the other loopback name (localhost <-> 127.0.0.1), so the browser
// treats them as a different site and applies SameSite and CORS as it would for a real attacker.
// Only localhost / 127.0.0.1 / [::1] targets are accepted. Watch the app's own log (or
// fake-upstream.mjs) to see whether a request was processed: a cross-site response is often
// unreadable even when the request went through.
import { createServer } from 'node:http'
import process from 'node:process'

const [targetArg, portArg = '4330'] = process.argv.slice(2)
if (!targetArg) {
  console.error('usage: node attacker-page.mjs <target-origin> [port]')
  process.exit(1)
}

let target
try {
  target = new URL(targetArg)
} catch {
  console.error('target must be an absolute URL such as http://localhost:3000')
  process.exit(2)
}
const LOCAL = new Set(['localhost', '127.0.0.1', '[::1]'])
if (!['http:', 'https:'].includes(target.protocol) || target.username || target.password || !LOCAL.has(target.hostname)) {
  console.error('Refusing: only http(s)://localhost, 127.0.0.1 or [::1] targets, without user@ (point it at your local app)')
  process.exit(2)
}
const origin = target.origin
const port = Number(portArg)
// The other loopback name makes the attacker a different site from the target.
const attackerHost = target.hostname === 'localhost' ? '127.0.0.1' : 'localhost'

// resolve(path): a URL on the target origin, or null for anything that would leave it.
function resolve(path) {
  if (typeof path !== 'string' || !path.startsWith('/') || path.startsWith('//')) return null
  const u = new URL(path, origin)
  return u.origin === origin ? u.href : null
}

function page(title, config, script) {
  // Config goes in as JSON with "<" escaped, so a query value cannot close the script tag.
  const data = JSON.stringify(config).replace(/</g, '\\u003c')
  return `<!doctype html><meta charset="utf-8"><title>${title}</title>
<body style="font-family:sans-serif"><h1>${title}</h1><pre id="out"></pre>
<script>const C = ${data}; const out = (s) => { document.getElementById('out').textContent += s + '\\n'; console.log('[attacker-page] ' + s) };
${script}</script></body>`
}

const pages = {
  '/frame': (url) => page('frame', { url }, `
out('framing ' + C.url + ' — take a screenshot: an unprotected app renders below; a protected one shows the browser refused-frame page')
const f = document.createElement('iframe'); f.src = C.url; f.width = 1000; f.height = 700
f.onload = () => out('iframe load event fired (it fires for refused frames too, so look at the frame)')
document.body.appendChild(f)`),
  '/form': (url, q) => page('form', { url, body: q.get('body') || '{"probe":"csrf"}', top: q.get('top') === '1' }, `
let obj; try { obj = JSON.parse(C.body) } catch { out('body must be a JSON object'); throw new Error('bad body') }
if (obj === null || typeof obj !== 'object' || Array.isArray(obj)) { out('body must be a JSON object'); throw new Error('bad body') }
// text/plain form trick: the browser sends name + "=" + value. Move a top-level string field to
// the end and split there, so the "=" lands at the end of its value ({"message":"hi","stream":false}
// -> {"stream":false,"message":"hi="}) and no field is added: a strict schema then has no unrelated
// reason to reject the probe. The JSON is built by hand so a "__proto__" key stays a plain field.
const entries = Object.entries(obj)
const i = entries.map(([, v]) => typeof v).lastIndexOf('string')
let head, tail = '"}'
if (i >= 0) {
  const ordered = entries.filter((_, j) => j !== i).concat([entries[i]])
  const json = '{' + ordered.map(([k, v]) => JSON.stringify(k) + ':' + JSON.stringify(v)).join(',') + '}'
  head = json.slice(0, -2)
  out('the "=" goes at the end of the string field ' + JSON.stringify(entries[i][0]))
} else {
  const json = JSON.stringify(obj)
  head = json.slice(0, -1) + (json === '{}' ? '' : ',') + '"_pad":"'
  out('no string field to carry the "=": added "_pad". If the API rejects unknown fields, report that a schema-valid CSRF probe could not be built for this endpoint')
}
const form = document.createElement('form'); form.method = 'POST'; form.action = C.url; form.enctype = 'text/plain'
const input = document.createElement('input'); input.type = 'hidden'; input.name = head; input.value = tail; form.appendChild(input)
if (!C.top) {
  const frame = document.createElement('iframe'); frame.name = 'result'; frame.width = 1000; frame.height = 300
  document.body.appendChild(frame); form.target = 'result'
}
document.body.appendChild(form)
out('POST ' + C.url + ' (text/plain, ' + (C.top ? 'top-level navigation' : 'into an iframe') + ') body: ' + head + '=' + tail)
out('check the app log: was it processed with the user\\'s cookies?' + (C.top ? '' : ' If the cookie has no SameSite attribute, try top=1 too (some browsers send it only on a top-level POST).'))
form.submit()`),
  '/fetch': (url, q) => page('fetch', { url, method: (q.get('method') || 'GET').toUpperCase(), body: q.get('body') }, `
const init = { method: C.method, credentials: 'include', mode: 'cors' }
if (C.body !== null && C.method !== 'GET' && C.method !== 'HEAD') { init.body = C.body; init.headers = { 'Content-Type': 'text/plain' } }
out(C.method + ' ' + C.url + ' with credentials')
fetch(C.url, init).then(async (r) => out('response readable: status ' + r.status + ', ' + (await r.text()).slice(0, 300)))
  .catch((e) => out('response not readable (' + e.message + '). The request may still have been sent: check the app log.'))`),
}

createServer((req, res) => {
  const u = new URL(req.url, `http://${attackerHost}:${port}`)
  const make = pages[u.pathname]
  const url = resolve(u.searchParams.get('path') || '/')
  if (!make || !url) {
    res.writeHead(404, { 'Content-Type': 'text/plain' })
    res.end('pages: /frame?path=/  /form?path=/api/x&body={...}  /fetch?path=/api/x&method=POST&body=...  (path must start with /)\n')
    return
  }
  res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8', 'Cache-Control': 'no-store' })
  res.end(make(url, u.searchParams))
}).listen(port, '127.0.0.1', () => {
  console.log(`attacker pages for ${origin}: open http://${attackerHost}:${port}/frame?path=/ (also /form, /fetch)`)
})
