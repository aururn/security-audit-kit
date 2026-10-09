# Next.js / React のチェックリスト

★ = 一般に見落とされがちな項目。

## 版と既知の重大な脆弱性

- [ ] Next.js と React が、既知の重大な脆弱性の修正版以上である（`pnpm audit --prod` と OSV で確認）
  - 例: CVE-2025-55182（React2Shell。React Server Components の Flight プロトコルの逆シリアル化による認証なし RCE、CVSS 10）。Next.js 15.x/16.x の App Router が影響を受けた
  - 例: CVE-2025-29927 以降、Middleware / Proxy のバイパスが繰り返し見つかっている
- [ ] ★ 認可やボット遮断を **Middleware だけ** に任せていない。ルートハンドラ側でも検査する（Middleware はバイパスの前例が多い）
- [ ] Middleware を入れるなら、その前に Next.js を最新のパッチ版へ上げる

## 秘密情報の境界

- [ ] サーバー専用の値を読むモジュールが `import 'server-only'` している（クライアントから import するとビルドエラーになる）
- [ ] `NEXT_PUBLIC_` が付いた環境変数に秘密情報がない。旧名から移行した場合、旧名がどこから読まれているか確認した
- [ ] Server Actions が意図せず公開されていない（`'use server'` の関数は外部から呼べる API と同じ扱い）

## 描画とキャッシュ

- [ ] ★ ルートレイアウトで `cookies()` / `headers()` を読むと全ページが動的レンダリングになる。意図しているか確認した（課金に直結。`checklists/cost-and-abuse.md`）
- [ ] 本番のトップページの `Cache-Control` と `x-vercel-cache` を見た
- [ ] SSR で自分自身の公開 URL を fetch していない（1リクエストごとに往復と転送が増える）
- [ ] `dangerouslySetInnerHTML` の入力は、すべてエスケープ済みか、信頼できる固定値だけ
- [ ] `next/image` の `remotePatterns` を必要なホストに限定している（画像最適化は脆弱性の前例がある）

## 設定（`next.config.js`）

- [ ] `poweredByHeader: false`
- [ ] `headers()` で `X-Content-Type-Options`、`Referrer-Policy`、（埋め込み方針に応じて）CSP `frame-ancestors`
- [ ] ★ `typescript.ignoreBuildErrors` / `eslint.ignoreDuringBuilds` を有効にしていない（型エラーで検出できる誤りを本番に出さない）
- [ ] 開発用ページは `NODE_ENV !== 'development'` で `notFound()` している

## テストで押さえておくこと

- [ ] iframe に埋め込んだ状態の E2E がある（送信元チェックを入れると、埋め込み時の正当な呼び出しを誤って拒否しやすい）
  - Playwright でループバック同士（`localhost` と `127.0.0.1`）の埋め込みを試す場合、Chromium の Local Network Access 制限で iframe がブロックされる（`net::ERR_BLOCKED_BY_LOCAL_NETWORK_ACCESS_CHECKS`）。テストの spec に限って `--disable-features=LocalNetworkAccessChecks` を付ける
- [ ] ★ ESLint が `playwright-report/` などテストの生成物を検査対象に含めていない（失敗後にローカルの lint が大量に落ちる）
