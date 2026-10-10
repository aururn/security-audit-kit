# チェックリスト

カテゴリ別の確認項目です。★ は、一般に見落とされがちな項目です。各項目は「確認方法」まで実行して判定します。

`web-api.md` と `ai-generated-code.md` は言語やフレームワークに依存しないので、どのアプリにも当てます。ほかは、使っている技術に合わせて選びます。

| ファイル | 内容 |
| --- | --- |
| [web-api.md](web-api.md) | 認可、CSRF、入力の検証、エラー応答、Cookie、ヘッダ、iframe 埋め込み |
| [ai-generated-code.md](ai-generated-code.md) | AI が書いたコードに多いミス（画面だけの権限、Supabase・Firebase の設定、実在しないパッケージ、仮の実装の残り） |
| [llm-app.md](llm-app.md) | OWASP Top 10 for LLM 2025 を、実装の確認項目に落としたもの |
| [nextjs-react.md](nextjs-react.md) | 既知の重大な CVE、秘密情報の境界、描画とキャッシュ、設定 |
| [cost-and-abuse.md](cost-and-abuse.md) | 課金の暴走（クローラ、動的レンダリング、大きな静的ファイル、上限） |
| [supply-chain.md](supply-chain.md) | 既知の脆弱性、悪意ある版、インストール時スクリプト、ツール自体の信頼 |
| [ci-github-actions.md](ci-github-actions.md) | Actions の固定、危険なトリガー、権限 |
| [secrets-and-publishing.md](secrets-and-publishing.md) | 秘密情報、公開・非公開の扱い、漏れたときの対応 |

## 見落とされがちな項目の例

- SDK が ID をエンコードせずに URL に連結していると、`..` や `%2F` で、API キー付きのリクエストを別のパスへ向けられる
- `SameSite=None` の Cookie と、送信元チェックなしの組み合わせは CSRF になる。`request.json()` は Content-Type を見ない
- エラー応答に `error.message` を入れると、内部アドレスがそのまま利用者に返る
- LLM の出力を Markdown で描画すると、既定では外部画像を読み込む。会話の内容を URL に載せて外へ送られる
- LLM を呼ぶのはチャット本体だけとは限らない（会話名の自動生成、要約など）
- AI が書いたアプリは、権限を「画面に出さない」だけで済ませがち。API を直接呼ぶと通る
- Supabase の RLS が無効なテーブルは、ブラウザに置いた公開鍵だけで読み書きできる
- ルートレイアウトで `cookies()` / `headers()` を読むと、全ページが動的レンダリングになる。クローラの巡回がそのまま課金になる
- `public/` に置いたまま使っていない大きなファイルは、配信されるたびに転送量がかかる
- 直したつもりのテストが、実は別の検証で弾かれて通っていることがある。修正を一時的に外して、落ちるか確かめる
- 本番がどのリポジトリからデプロイされているかを確かめる（フォークが本番の配信元のことがある）
- スキャナや CI のツール自体が乗っ取られることがある（2026年の Trivy、axios）

## コードからは確認できないこと

ダッシュボードで確認します。監査の報告では「未確認」として別枠にします。

- [ ] ホスティングの支出上限と自動停止（Vercel Spend Management）
- [ ] WAF のレート制限、Bot Protection / AI Bots のマネージドルールセット
- [ ] LLM・上流プロバイダの月間上限とアラート
- [ ] 本番がどのリポジトリ・ブランチからデプロイされているか
- [ ] Dependabot のアラートとセキュリティアップデート

## 参考資料

- [OWASP Top 10:2025](https://owasp.org/Top10/2025/)
- [OWASP Top 10 for LLM Applications 2025](https://genai.owasp.org/resource/owasp-top-10-for-llm-applications-2025/)
- [CVE-2025-55182（React2Shell）の Next.js のアドバイザリ](https://github.com/vercel/next.js/security/advisories/GHSA-9qr9-h5gf-34mp)
- [Trivy のサプライチェーン攻撃（Palo Alto Networks）](https://www.paloaltonetworks.com/blog/cloud-security/trivy-supply-chain-attack/)
- [axios の npm パッケージ乗っ取り（Microsoft Security Blog）](https://www.microsoft.com/en-us/security/blog/2026/04/01/mitigating-the-axios-npm-supply-chain-compromise/)
- [pnpm: Mitigating supply chain attacks](https://pnpm.io/supply-chain-security)
- [OpenSSF: Detecting Malicious Packages Using the OSV API](https://openssf.org/blog/2026/05/20/detecting-malicious-packages-using-the-osv-api/)
- [Vercel: Bot Management](https://vercel.com/docs/bot-management) / [WAF Managed Rulesets](https://vercel.com/docs/vercel-firewall/vercel-waf/managed-rulesets)
