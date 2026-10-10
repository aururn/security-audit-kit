# AI が書いたコードのチェックリスト

AI（コーディングエージェント、Lovable・Bolt・v0 などのアプリ生成ツール）が書いたコードに多いミスです。
言語やフレームワークに依存しない項目なので、専用のチェックリストがないアプリにも当てます。
★ = 一般に見落とされがちな項目。各項目は「確認」まで実行して判定する。

鍵やパスワードが一致しうる grep は、`-o`（一致した部分だけ）か `-l`（ファイル名だけ）を付けて、値を画面やログに出さない（`AGENTS.md` の禁止事項）。

## 権限の検査が画面側だけ

- [ ] ★ 管理画面や他人のデータを、画面で隠しているだけでなく、API 側でも拒否している
  - AI は「ボタンを出さない」「ページに入れない」で権限を実装しがち。API を直接呼べば通る
  - 確認: ローカルで、一般ユーザーのセッションから管理用・他人用の API を `curl` で直接呼び、403 / 404 になるか
- [ ] ★ 利用者の ID・ロール・プランを、リクエストの本文や `localStorage` から読んでいない。サーバー側のセッションから取る
  - 確認: `userId`、`role`、`isAdmin`、`plan` を本文で受け取っている箇所を grep する

## BaaS の設定（Supabase、Firebase）

ブラウザに置いた公開鍵で、データベースを直接読み書きできる構成です。守りはデータベース側の規則だけになります。

- [ ] ★ Supabase：公開されるスキーマ（既定は `public`）の全テーブルで RLS（Row Level Security）が有効
  - 確認: マイグレーションに `enable row level security` がテーブルごとにあるか。DB に接続できれば `select tablename, rowsecurity from pg_tables where schemaname = 'public';`
  - 確認（利用者の承認を取ってから。行の中身は取らない）: `curl -s -I "$SUPABASE_URL/rest/v1/<table>?select=*" -H "apikey: <anon key>" -H "Prefer: count=exact"`。HEAD なので本文は返らない。`Content-Range` の `/` の後の件数が 0 でなければ、ログインなしで読める
- [ ] Supabase：ポリシーが `using (true)` や `with check (true)` で、全員に読み書きを許していない。所有者を `auth.uid()` で絞っている
- [ ] ★ Supabase：公開されるスキーマの関数を、ブラウザの鍵で `rpc` から呼べない。呼べるなら、関数の中で `auth.uid()` と権限を確かめている
  - Postgres の関数は、既定で誰でも実行できる（`PUBLIC`）。公開されるスキーマの関数は `POST /rest/v1/rpc/<関数名>` で呼べる。`security definer` の関数は所有者の権限で動く。所有者が `BYPASSRLS` を持つか、`FORCE ROW LEVEL SECURITY` のないテーブルの所有者なら、RLS は効かない（マイグレーションで作った関数の所有者は、多くの場合 `postgres` で、`BYPASSRLS` を持つ）。引数で渡した利用者 ID や組織 ID をそのまま信じる関数は、他人として操作できる
  - 確認: サーバーだけが呼ぶ関数は、マイグレーションで実行権を取り消しているか。関数ごとの `revoke all on function ... from public, anon, authenticated;` でも、スキーマ全体の `revoke ... on all functions in schema` と `alter default privileges` でもよい
  - 確認（ブラウザから呼べる関数。承認したローカルの範囲だけで）: ログインなしで呼んだときと、利用者 A のセッションで利用者 B の ID を渡したときに、`rpc` を実際に呼び、B のデータが返らず、変わらないことを確かめる（拒否でも空の結果でもよい。誰に返してもよい公開の関数は除く）。コードを読むだけでは足りない。`auth.uid() is not null` は、ログインしているかしか確かめておらず、渡した ID がその人のものかは確かめていない
- [ ] ★ Supabase：`service_role` キー（新しい形式では `sb_secret_`）がクライアントのコードや公開される環境変数にない
  - 確認: `grep -rnoE "service_role|sb_secret_|SERVICE_ROLE" --include=*.{js,jsx,ts,tsx,vue,svelte} .`（`-o` なので接頭辞だけが出る）で、サーバー専用のファイル以外に出てこないか
- [ ] ★ Supabase：サーバーが DB に直接つなぐ場合（Drizzle、Prisma、`pg` など）、そのロールで RLS が効く
  - Supabase が最初から用意する `postgres` ロールは、superuser ではないが `BYPASSRLS` を持ち、多くのテーブルの所有者でもある。その接続文字列で動かすと、ポリシーは 1 つも効かない。`FORCE ROW LEVEL SECURITY` は所有者には効くが、`BYPASSRLS` を持つロールには効かない
  - テーブルの所有者も、`FORCE ROW LEVEL SECURITY` がなければポリシーをすり抜ける。マイグレーションをアプリと同じ接続で流すと、独自に作ったロールでも所有者になる
  - 確認: アプリが使う接続文字列のユーザー名を確かめる（値は出さない。`DATABASE_URL` のユーザー部分が `postgres` か `postgres.<project ref>` なら危ない）。DB に接続できれば、そのロールで次の 2 つを実行する。1 つ目が `false`・`false` で、2 つ目が 0 行なら、このロールで直接読むテーブルにはポリシーが効く
    - `select rolsuper, rolbypassrls from pg_roles where rolname = current_user;`
    - `select c.oid::regclass from pg_class c where c.relkind in ('r', 'p') and c.relrowsecurity and not c.relforcerowsecurity and pg_has_role(current_user, c.relowner, 'USAGE');`（そのロールが所有者で、ポリシーをすり抜けるテーブル）
  - ビュー（`security_invoker` のないもの。`postgres` が作ったビューは既定でこれ）と `security definer` の関数は、所有者の権限で動く。所有者が `postgres` なら、そこを通る読み書きはポリシーをすり抜ける。アプリがこれらを通すなら、アプリと同じロールと経路で他のテナントの行を読もうとして、返らないことを確かめる
  - 本番の接続文字列はコードからは分からない。「RLS で分離している」と README に書いてあっても、未確認として利用者に確認を依頼する
- [ ] Supabase：Storage のバケットが意図せず public になっていない
- [ ] ★ Firebase（Firestore・Storage）：`firestore.rules`・`storage.rules` に `allow read, write: if true` や、テストモードの `request.time < timestamp.date(...)` が残っていない
  - テストモードの規則は、期限まで誰でも読み書きできる
- [ ] Firebase（Firestore・Storage）：利用者ごとのデータを `request.auth != null` だけで許していない（ログインした全員が全員分を読める）。`request.auth.uid` と所有者の項目を比べている
- [ ] ★ Firebase（Realtime Database）：`database.rules.json` に `".read": true`・`".write": true` や、テストモードの `"now < <期限の時刻>"` が残っていない。利用者ごとのデータは `auth != null` だけでなく、`auth.uid === $uid` のように所有者と比べている
  - Realtime Database の規則は JSON で、`.read`・`.write` と `auth`・`now` を使う。Firestore の `allow` や `request.auth` の書き方を探しても見つからない
- [ ] リポジトリの規則と、実際にデプロイされている規則が同じか（ダッシュボード。未確認として利用者に確認を依頼する）

## クライアントに入った鍵

- [ ] ★ ブラウザに出る環境変数に秘密の鍵がない
  - 接頭辞: `NEXT_PUBLIC_`、`VITE_`、`EXPO_PUBLIC_`、`REACT_APP_`、`NUXT_PUBLIC_`、`PUBLIC_`（SvelteKit）
  - 秘密の鍵の例: `sk-`（OpenAI など）、`sk_live_`（Stripe）、`sb_secret_`、AWS の `AKIA`
  - 確認: `grep -rhoE "^(NEXT_PUBLIC|VITE|EXPO_PUBLIC|REACT_APP|NUXT_PUBLIC|PUBLIC)_[A-Z0-9_]+" .env* 2>/dev/null` で変数名だけを一覧にし、名前と使われ方から秘密の鍵でないか確かめる。ビルド済みの JS は `grep -rlE "sk-|sk_live_|sb_secret_|AKIA" .next/static dist build 2>/dev/null`（ファイル名だけ）
- [ ] LLM や有料 API を、ブラウザから鍵付きで直接呼んでいない。サーバーを経由している

## 実在しない・似た名前のパッケージ

AI は実在しないパッケージ名を提案することがあり、その名前を先に登録して悪意あるコードを置く攻撃（slopsquatting）があります。

- [ ] ★ 依存に、AI が作った名前や、有名なパッケージに似せた名前がない
  - 確認: 見慣れない依存ごとに `npm view <name> repository.url time.created`（PyPI は `https://pypi.org/pypi/<name>/json`）。作られたばかり、リポジトリがない、名前が有名なものと 1 字違い、は疑う
- [ ] lockfile の取得元（`resolved`）が、想定したレジストリだけ

## 残ったままの仮の実装

- [ ] ★ 常に成功を返す検証や、決め打ちの値が残っていない
  - 例: 常に `true` を返す `verifyToken`、`isAdmin = true`、決め打ちのユーザーやパスワード、`?debug=1` や `x-test-user` ヘッダで認証を飛ばす口
  - 確認: `grep -rliE "(TODO|FIXME|HACK|XXX).*(auth|valid|secur|permission|rate|admin)" --exclude-dir=node_modules .`（ファイル名だけ。該当箇所は開いて読む）、`grep -rnoE "return true|isAdmin\s*=\s*true|password\s*[:=]\s*['\"]" --exclude-dir=node_modules .`（`-o` なので、パスワードの値は出ない）
- [ ] seed 用・デバッグ用のエンドポイント（`/api/seed`、`/api/reset`、`/api/debug`、`/api/test`）が本番で使えない
- [ ] 本文・トークン・パスワード・プロンプトをそのままログに出していない（`console.log(req.body)` など）

## 外された検証

- [ ] TLS の検証を外していない：`rejectUnauthorized: false`、`NODE_TLS_REJECT_UNAUTHORIZED=0`、`verify=False`（Python）
- [ ] JWT を `decode` だけで信じていない。`verify` で署名と期限を確かめている
- [ ] CORS で、全オリジン（`*` や Origin のそのままの反射）と credentials を組み合わせていない
- [ ] 認証・認可・入力検証のまわりで、例外を握りつぶしていない（`catch {}` の後に処理を続ける）
- [ ] 型や lint の検査を、`@ts-ignore`・`as any`・`eslint-disable` で、リクエストの本文や認可の箇所だけ外していない

## クライアントの値をそのまま信じる

- [ ] ★ 金額・通貨・数量・プラン・割引を、クライアントから送られた値で決めていない。サーバー側の価格表から決める
  - 確認: 決済の作成（Stripe の Checkout Session など）に渡す金額の出どころを追う。負の数量や 0 円が通らないか
- [ ] ファイルの種類を、クライアントの `Content-Type` や拡張子だけで判定していない（`web-api.md` のアップロード）

## 弱い乱数と自作の暗号

- [ ] トークン・招待コード・パスワード再設定のコードに `Math.random()` を使っていない（`crypto.randomUUID()`、`crypto.randomBytes` などを使う）
- [ ] パスワードを MD5・SHA-1・SHA-256 の 1 回だけで保存していない（bcrypt、scrypt、Argon2 を使う）

## テスト

- [ ] ★ 認可のテストに「他人のデータは拒否される」「ログインなしは拒否される」がある。成功する経路だけのテストになっていない
- [ ] テストが、確かめたい関数そのものをモックしていない（`AGENTS.md` 基本原則 3：修正を外してテストが落ちるか確かめる）

## 事例から

- 2025 年、Lovable で作られたアプリのうち公開ショーケースの 1,645 件を調べたところ、約 1 割の 170 件で、Supabase のテーブルが公開鍵だけで読み書きできた。RLS が有効になっていなかった（CVE-2025-48757）
- 16 の LLM に Python と JavaScript のコードを書かせた研究では、提案されたパッケージのうち実在しないものが、商用のモデルで約 5%、オープンなモデルで約 22% あった。同じ指示で同じ名前が繰り返し出るため、攻撃者が先に登録できる（USENIX Security 2025）

## 参考資料

- [CVE-2025-48757（NVD）](https://nvd.nist.gov/vuln/detail/CVE-2025-48757)
- [We Have a Package for You! A Comprehensive Analysis of Package Hallucinations by Code Generating LLMs（USENIX Security 2025）](https://arxiv.org/abs/2406.10279)
- [Supabase: Row Level Security](https://supabase.com/docs/guides/database/postgres/row-level-security)
- [Firebase: Fix insecure rules](https://firebase.google.com/docs/rules/insecure-rules)
