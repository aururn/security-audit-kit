// Tests for the helpers the security-audit skill starts during a local reproduction:
// fake-upstream.mjs must never write the Authorization value to its log, and attacker-page.mjs
// must refuse any target other than a local app and any path that would leave the target origin.
// They run the scripts as child processes, as the skill does. No browser and no network beyond
// loopback. Run: node --test tests/
import { spawn } from 'node:child_process'
import { mkdtempSync, readFileSync, rmSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { dirname, join } from 'node:path'
import { after, describe, test } from 'node:test'
import assert from 'node:assert/strict'
import { fileURLToPath } from 'node:url'

const SKILL = join(dirname(fileURLToPath(import.meta.url)), '..', 'skills', 'security-audit')
const FAKE_UPSTREAM = join(SKILL, 'fake-upstream.mjs')
const ATTACKER_PAGE = join(SKILL, 'attacker-page.mjs')

// A port per server, away from common dev ports. Collisions only make a test fail, never pass.
let nextPort = 41000 + Math.floor(Math.random() * 2000) * 10
const freshPort = () => (nextPort += 1)

/** Runs a script that is expected to exit on its own; resolves with its exit code and output. */
function runToExit(script, args) {
  return new Promise((resolve, reject) => {
    const child = spawn(process.execPath, [script, ...args], { stdio: ['ignore', 'pipe', 'pipe'] })
    let out = ''
    child.stdout.on('data', (c) => { out += c })
    child.stderr.on('data', (c) => { out += c })
    const timer = setTimeout(() => { child.kill(); reject(new Error(`still running: ${args.join(' ')}`)) }, 10_000)
    child.on('exit', (code) => { clearTimeout(timer); resolve({ code, out }) })
  })
}

/** Starts a server script and resolves once it prints its ready line. */
function startServer(script, args, ready) {
  return new Promise((resolve, reject) => {
    const child = spawn(process.execPath, [script, ...args], { stdio: ['ignore', 'pipe', 'pipe'] })
    let out = ''
    const timer = setTimeout(() => { child.kill(); reject(new Error(`not ready: ${out}`)) }, 10_000)
    child.stdout.on('data', (c) => {
      out += c
      if (out.includes(ready)) { clearTimeout(timer); resolve(child) }
    })
    child.stderr.on('data', (c) => { out += c })
    child.on('exit', (code) => { clearTimeout(timer); reject(new Error(`exited ${code}: ${out}`)) })
  })
}

const children = []
after(() => { for (const c of children) c.kill() })

describe('fake-upstream.mjs', () => {
  const dir = mkdtempSync(join(tmpdir(), 'fake-upstream-'))
  after(() => rmSync(dir, { recursive: true, force: true }))

  test('logs that Authorization was sent, never its value', async () => {
    const log = join(dir, 'upstream.log')
    const port = freshPort()
    children.push(await startServer(FAKE_UPSTREAM, [log, String(port)], 'fake upstream on'))
    const secret = 'sk-test-' + 'a1b2c3d4e5f6'
    const res = await fetch(`http://127.0.0.1:${port}/v1/chat-messages?user=u1`, {
      method: 'POST',
      headers: { Authorization: `Bearer ${secret}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ query: 'hi' }),
    })
    assert.equal(res.status, 200)
    await fetch(`http://127.0.0.1:${port}/v1/files`)
    const lines = readFileSync(log, 'utf8').trim().split('\n')
    assert.equal(lines.length, 2)
    assert.match(lines[0], /POST \/v1\/chat-messages\?user=u1 auth=present body=\{"query":"hi"\}/)
    assert.match(lines[1], /GET \/v1\/files auth=none body=$/)
    assert.ok(!readFileSync(log, 'utf8').includes(secret), 'the Authorization value must not be logged')
  })

  test('answers with the given error status', async () => {
    const port = freshPort()
    children.push(await startServer(FAKE_UPSTREAM, [join(dir, 'error.log'), String(port), '500'], 'fake upstream on'))
    const res = await fetch(`http://127.0.0.1:${port}/v1/chat-messages`, { method: 'POST', body: '{}' })
    assert.equal(res.status, 500)
    assert.deepEqual(await res.json(), { code: 'upstream_error', message: 'simulated failure' })
  })

  test('needs a log file', async () => {
    const { code } = await runToExit(FAKE_UPSTREAM, [])
    assert.equal(code, 1)
  })
})

describe('attacker-page.mjs: targets', () => {
  // Every one of these must be refused before a server starts.
  const refused = [
    'https://example.com',
    'http://localhost:1@evil.example',
    'http://user:pass@localhost:3000',
    'http://127.0.0.2:3000',
    'http://localhost.evil.example',
    'ftp://localhost/',
    'file:///etc/passwd',
    'not a url',
  ]
  for (const target of refused) {
    test(`refuses ${target}`, async () => {
      const { code, out } = await runToExit(ATTACKER_PAGE, [target, String(freshPort())])
      assert.equal(code, 2, out)
    })
  }

  test('needs a target', async () => {
    const { code } = await runToExit(ATTACKER_PAGE, [])
    assert.equal(code, 1)
  })
})

describe('attacker-page.mjs: pages', () => {
  const port = freshPort()
  // localhost target -> pages are served for 127.0.0.1, the other loopback name.
  const base = `http://127.0.0.1:${port}`
  const target = 'http://localhost:3999'
  const ready = startServer(ATTACKER_PAGE, [target, String(port)], 'attacker pages for').then((c) => {
    children.push(c)
    return c
  })

  const get = async (path) => {
    await ready
    const res = await fetch(base + path)
    return { status: res.status, body: await res.text() }
  }

  test('frames a path on the target origin', async () => {
    const { status, body } = await get('/frame?path=/settings')
    assert.equal(status, 200)
    assert.ok(body.includes(`"url":"${target}/settings"`), body)
  })

  // Paths that would point the page somewhere other than the target origin.
  const leaving = ['//evil.example/', '/\\evil.example', 'https://evil.example/', 'evil.example', '']
  for (const path of leaving) {
    test(`refuses path ${JSON.stringify(path)}`, async () => {
      const { status } = await get(`/frame?path=${encodeURIComponent(path)}`)
      // An empty path falls back to "/", which is on the target origin.
      assert.equal(status, path === '' ? 200 : 404)
    })
  }

  test('refuses an unknown page', async () => {
    const { status } = await get('/nope?path=/')
    assert.equal(status, 404)
  })

  test('a query value cannot close the script tag', async () => {
    const body = JSON.stringify({ message: '</script><b id="x">' })
    const res = await get(`/form?path=/api/x&body=${encodeURIComponent(body)}`)
    assert.equal(res.status, 200)
    assert.ok(!res.body.includes('</script><b'), 'raw "</script>" from the query reached the page')
    assert.ok(res.body.includes('\\u003c/script>'))
  })

  test('keeps serving after a malformed request', async () => {
    await get('/frame?path=%E0%A4%A')
    const { status } = await get('/frame?path=/')
    assert.equal(status, 200)
  })
})
