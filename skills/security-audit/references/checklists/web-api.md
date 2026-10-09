# Web API・サーバー処理のチェックリスト

★ = 一般に見落とされがちな項目。各項目は「確認方法」まで実行して判定する。

## 認証・認可（OWASP A01 / A07）

- [ ] 認証なしで呼べる API を一覧にした。それぞれ「誰が呼んでよいか」を決めた
  - 確認: ルートハンドラ・Server Actions・Webhook を grep し、先頭で何を検査しているか読む
- [ ] ★ 利用者を区別する値（セッション ID、user ID）をクライアントが自由に決められない
  - 例: Cookie の値をそのまま上流 API の `user` に使うと、他人の値を推測・入手した人がその人の履歴を読める。UUID なら推測は困難だが、取得経路（XSS、ログ）を塞ぐ
- [ ] オブジェクトの ID（会話 ID、メッセージ ID など）で他人のデータを操作できない
  - 確認: 上流（DB・SaaS）側が所有者で絞り込んでいるか。絞り込みを上流任せにしている場合は、その前提を記録する
- [ ] ★ Webhook の受け口が、送信元の署名を検証している（Stripe、GitHub など）
  - 署名ヘッダ（例: `Stripe-Signature`、`X-Hub-Signature-256`）を、生の本文と共有鍵で検証する。パース後の本文で検証しない。タイムスタンプを見て再送（replay）を弾く
  - 確認: 署名を外した、または古いタイムスタンプのリクエストが拒否される
- [ ] ★ cron・内部用・管理用のエンドポイントが、認証なしで叩けない
  - Vercel Cron は `Authorization: Bearer $CRON_SECRET` を送る。これを検証する。`/api/internal/*` や seed・migration の口が公開されていないか
  - 確認: secret なしで叩いて拒否されるか。LLM など有料の上流を呼ぶ cron は特に重要（`checklists/cost-and-abuse.md`）

## CSRF・クロスオリジン（A01）

- [ ] ★ `SameSite=None` の Cookie（iframe 埋め込みで必要になる）を使う場合、状態を変える API に送信元チェックがある
  - 確認方法: 他オリジンの `Origin` と `Sec-Fetch-Site: cross-site` を付けたリクエストが拒否される
  - 推奨: `Sec-Fetch-Site` が `same-origin` / `none` 以外を拒否し、無い場合は `Origin` のホストと、ブラウザがアクセスしたホスト（`X-Forwarded-Host` → `Host`）を比べる。`request.url` はプロキシ配下で内部アドレスになることがある
- [ ] ★ `request.json()` は Content-Type を見ない。`text/plain` の単純リクエスト（プリフライトなし）でも JSON として読まれることを前提に考える
- [ ] CORS ヘッダを付けていない、または必要なオリジンだけに限定している

## 入力の検証（A05）

- [ ] ★ URL のパスに入る値（ID）の形式を検証している
  - SDK が ID をエンコードせずに上流 URL へ連結していると、`..` や `%2F` で API キー付きのリクエストを別のパスへ向けられる。Next.js はルートパラメータの `%2F` を `/` にデコードし、WHATWG URL は `..` を正規化する
  - 確認: 偽の上流サーバー（`skills/security-audit/fake-upstream.mjs`）で、届いたパスを記録する
- [ ] 本文は「許可した項目だけ」を組み立てて上流に渡す（受け取ったオブジェクトをそのまま転送しない）
  - 上流側がアプリ設定で検証している値（変数の型・長さ）まで二重に絞ると、正当な画面操作を壊しやすい。サーバー側は形式と量（キー、件数、全体サイズ）を守り、中身は上流の設定に任せる判断もある。その場合は理由を残す
- [ ] ★ 利用者が選べてはいけない動作モードを固定している（例: `response_mode`、`stream`、使うモデル名）
- [ ] 外部 URL を受け取る項目（画像 URL、Webhook 先）はスキームを http(s) に限定し、内部アドレスを上流に取りに行かせない（SSRF、A01 に統合）
- [ ] ★ DB クエリに利用者の値を文字列連結で入れていない（SQL / NoSQL インジェクション）
  - パラメータ化クエリか ORM のバインドを使う。NoSQL では、JSON の値に `$gt` などの演算子オブジェクトが入り込まないよう型を検証する（`{ "password": { "$ne": null } }` 対策）
  - 確認: 値に `' OR 1=1 --` や `{"$ne":null}` を入れて、そのまま解釈されないか
- [ ] ★ ファイルアップロードを、拡張子ではなく中身（magic number）で種別を確かめ、サイズ・枚数の上限がある
  - 保存名は自分で決める（利用者の名前をそのまま使わない。`..` や NUL を含めない）。実行可能な場所に置かない。画像なら再エンコードして埋め込みを落とす
  - 確認: 偽装した拡張子、巨大ファイル、`../` 入りの名前が弾かれるか
- [ ] ★ リダイレクト先（`?next=`、`returnTo` など）を検証している（open redirect）
  - 相対パスだけ許す、または許可リストのホストだけ。`//evil.example` や `https:evil` のような形も弾く
  - 確認: `?next=//evil.example` が自サイト内に正規化されるか拒否されるか
- [ ] 壊れた JSON や想定外の型は 400 で返す（未処理例外にしない）

## エラー処理と情報漏洩（A10 / A09）

- [ ] ★ エラー応答に `error.message`・スタック・上流の URL・内部アドレス（例: `connect ECONNREFUSED 10.x.x.x:port`）を入れていない
  - 確認: 上流を止めて、または 500 を返させて API を叩き、応答本文を見る
- [ ] axios などのエラーオブジェクト（リクエスト設定に Authorization ヘッダを含む）を、応答やログにそのまま出していない
- [ ] すべてのルートで例外を処理し、決まった形の JSON を返す（HTML のエラーページや 200 のエラー文を返さない）
- [ ] ★ エラー時のステータスが画面側の処理と噛み合っている（例: 上流の 401 をそのまま返すと、画面側のラッパーが「ログインが必要」と解釈して処理が止まる）

## Cookie とヘッダ（A02）

- [ ] セッション Cookie に `HttpOnly`・`Secure`・明示的な `Path=/` が付いている
- [ ] `X-Content-Type-Options: nosniff`、`Referrer-Policy` を付けている。`X-Powered-By` を外している
- [ ] ★ CSP の `script-src` を絞っている（`unsafe-inline` / `unsafe-eval` を避け、nonce か hash を使う）
  - XSS の被害を抑える多層防御。`default-src` だけでなく `script-src` を見る。Next.js は nonce を middleware で付けられる
  - 確認: 本番の応答ヘッダ（または meta）に CSP があり、`script-src` に `unsafe-inline` が無いか
- [ ] ★ 埋め込みを許すサイトを CSP `frame-ancestors` で限定している（または限定しない理由を記録している）
  - 限定しないと、どのサイトでも埋め込めてしまう（クリックジャッキング、他人のサイトでの利用による課金）
  - `X-Frame-Options: DENY` は埋め込みを前提とするアプリでは使えない
- [ ] `window.postMessage` の送信先を `'*'` にしていない。受信側は `event.origin` を検証している

## 静的ファイルと公開範囲

- [ ] ★ `public/` に使われていない大きなファイル（エディタ一式、動画、データ）が残っていない
- [ ] 開発用のページ（プレビュー、デバッグ）が本番で 404 になる
- [ ] `robots.txt` が意図どおり（検索に載せないアプリなら全拒否）

## 本番での読み取り確認（攻撃はしない）

```sh
curl -s -D - -o /dev/null https://<host>/                               # ヘッダ、キャッシュ状態
curl -s -D - -o /dev/null https://<host>/api/<cheap-endpoint>            # Set-Cookie の属性
curl -s -w ' %{http_code}\n' -H 'Origin: https://evil.example' -H 'Sec-Fetch-Site: cross-site' https://<host>/api/<cheap-endpoint>   # 403 になるか
```
