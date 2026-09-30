// Minimal upstream stand-in for reproducing what an app forwards to a paid API.
// Usage: node fake-upstream.mjs <logfile> [port=4329] [status=200]
// Logs one line per request: method, path+query, whether Authorization was sent, body (first 500 chars).
// It never prints the Authorization value itself.
import { appendFileSync } from 'node:fs'
import { createServer } from 'node:http'
import process from 'node:process'

const [logFile, port = '4329', status = '200'] = process.argv.slice(2)
if (!logFile) {
  console.error('usage: node fake-upstream.mjs <logfile> [port] [status]')
  process.exit(1)
}

createServer(async (req, res) => {
  let body = ''
  for await (const chunk of req) { body += chunk }
  const auth = req.headers.authorization ? 'present' : 'none'
  appendFileSync(logFile, `${new Date().toISOString()} ${req.method} ${req.url} auth=${auth} body=${body.slice(0, 500)}\n`)
  const code = Number(status)
  res.writeHead(code, { 'Content-Type': 'application/json' })
  res.end(JSON.stringify(code < 400 ? { result: 'success' } : { code: 'upstream_error', message: 'simulated failure' }))
}).listen(Number(port), '127.0.0.1', () => console.log(`fake upstream on http://127.0.0.1:${port} (status ${status})`))
