# security-audit-kit

AI コーディングエージェント（Claude Code / Codex）と一緒に、Web アプリの**脆弱性**と**課金の暴走**を調べて直すためのキットです。

[![CI](https://github.com/aururn/security-audit-kit/actions/workflows/ci.yml/badge.svg)](https://github.com/aururn/security-audit-kit/actions/workflows/ci.yml)

| 対象 | 対象外（ほかのツールと組み合わせる） |
| --- | --- |
| LLM や SaaS の API を中継する **Next.js / Node のアプリ**のソースと lockfile、GitHub Actions、Vercel などへのデプロイ | コンテナイメージ・IaC の検査、Python / Go などほかの言語のアプリ、ネイティブアプリ、本番への侵入テスト |

| 入っているもの | 役割 |
| --- | --- |
| [`AGENTS.md`](AGENTS.md) / [`CLAUDE.md`](CLAUDE.md) | エージェントが守るルール（原則・重大度・禁止事項） |
| [`skills/`](skills/) | 監査・公開前の秘密情報検査・修正の進め方・課金の確認の手順 |
| [`checklists/`](checklists/) | カテゴリ別の確認項目（★ = 見落とされがち） |
| [`docker/`](docker/) + [`scripts/`](scripts/) | 版とチェックサムを固定したスキャナのコンテナ |
| [`tests/`](tests/) | キットの検出力を確かめるカナリアのテスト |
| [`templates/`](templates/) | Issue / PR の本文テンプレート |
| [`docs/decisions/`](docs/decisions/) | 見直す可能性のある判断の記録 |

---

## クイックスタート

```sh
git clone https://github.com/aururn/security-audit-kit.git
cd security-audit-kit

# 1. skills を Claude Code と Codex に入れる
scripts/install-skills.sh

# 2. 対象リポジトリをスキャンする（Docker が必要）
scripts/run-scan.sh /path/to/your-app ./reports
cat reports/summary.txt
```

あとはエージェントに頼むだけです。

> 「このリポジトリの脆弱性を調べて」 → `security-audit`
> 「公開する前に秘密情報がないか確認して」 → `pre-publish-secret-scan`
> 「見つかった脆弱性を Issue と PR で直して」 → `security-fix-workflow`
> 「高額請求にならないか確認して」 → `cost-abuse-review`

---

## skills

| skill | いつ使うか | やること |
| --- | --- | --- |
| [`security-audit`](skills/security-audit/SKILL.md) | 監査・公開前のレビュー | 脅威モデル → 入口の洗い出し → スキャン → 手作業のレビュー → ローカルで再現 → 報告 |
| [`pre-publish-secret-scan`](skills/pre-publish-secret-scan/SKILL.md) | リポジトリの公開、公開側への push の前 | 全履歴の秘密情報の検査、誤検出の見分け方、安全な push |
| [`security-fix-workflow`](skills/security-fix-workflow/SKILL.md) | 見つかった脆弱性を直す | 1 Issue = 1 PR、テストの検出力の確認、独立レビュー、並列で進めるときの分け方 |
| [`cost-abuse-review`](skills/cost-abuse-review/SKILL.md) | 高額請求が心配なとき、試作を公開する前 | 1リクエストのコスト × 回数 × 上限の確認 |

`security-audit` には、アプリが上流 API に何を送ったかを記録する偽のサーバー（[`fake-upstream.mjs`](skills/security-audit/fake-upstream.mjs)）が付いています。

skills の本文は英語、それ以外は日本語です。

---

## チェックリスト

| ファイル | 内容 |
| --- | --- |
| [`web-api.md`](checklists/web-api.md) | 認可、CSRF、入力の検証、エラー応答、Cookie、ヘッダ、iframe 埋め込み |
| [`llm-app.md`](checklists/llm-app.md) | OWASP Top 10 for LLM 2025 を実装の確認項目に落としたもの |
| [`nextjs-react.md`](checklists/nextjs-react.md) | 既知の重大な CVE、秘密情報の境界、描画とキャッシュ、設定 |
| [`cost-and-abuse.md`](checklists/cost-and-abuse.md) | 課金の暴走（クローラ、動的レンダリング、大きな静的ファイル、上限） |
| [`supply-chain.md`](checklists/supply-chain.md) | 既知の脆弱性、悪意ある版、インストール時スクリプト、ツール自体の信頼 |
| [`ci-github-actions.md`](checklists/ci-github-actions.md) | Actions の固定、危険なトリガー、権限 |
| [`secrets-and-publishing.md`](checklists/secrets-and-publishing.md) | 秘密情報、公開・非公開の扱い、漏れたときの対応 |

<details>
<summary><b>見落とされがちな項目の例</b></summary>

- SDK が ID をエンコードせずに URL に連結していると、`..` や `%2F` で、API キー付きのリクエストを別のパスへ向けられる
- `SameSite=None` の Cookie ＋ 送信元チェックなし ＝ CSRF。`request.json()` は Content-Type を見ない
- エラー応答に `error.message` を入れると、内部アドレスがそのまま利用者に返る
- LLM の出力を Markdown で描画すると、既定では外部画像を読み込む。会話の内容を URL に載せて外へ送られる
- LLM を呼ぶのはチャット本体だけとは限らない（会話名の自動生成、要約など）
- ルートレイアウトで `cookies()` / `headers()` を読むと、全ページが動的レンダリングになる。クローラの巡回がそのまま課金になる
- `public/` に置いたまま使っていない大きなファイルは、配信されるたびに転送量がかかる
- 直したつもりのテストが、実は別の検証で弾かれて通っていることがある。修正を一時的に外して落ちるか確かめる
- 本番がどのリポジトリからデプロイされているかを確かめる（フォークが本番の配信元のことがある）
- スキャナや CI のツール自体が乗っ取られることがある（2026年の Trivy、axios）

</details>

---

## スキャナ

```sh
scripts/run-scan.sh <対象ディレクトリ> [レポートの出力先]
```

| ツール | 版 | 見るもの |
| --- | --- | --- |
| gitleaks | 8.30.1 | git の全履歴・全ブランチの秘密情報（値は伏せて出力） |
| osv-scanner | 2.6.0 | lockfile の既知の脆弱性と、悪意あるパッケージ（`MAL-`） |
| semgrep | 1.178.0 | SAST。ルールセット default / owasp-top-ten / typescript / react / nodejsscan をイメージのビルド時に取り込む |
| zizmor | 1.30.1 | GitHub Actions の危険な設定 |
| actionlint | 1.7.12 | GitHub Actions の構文・型の誤り、信頼できない入力のスクリプトへの埋め込み |

イメージは linux/amd64 と linux/arm64（Apple Silicon）の両方で動きます。

出力は `summary.json`（ツールごとの状態と件数）、`summary.txt`（同じ内容を人が読む形で）、ツールごとの JSON です。
いずれかのツールが `error` になった場合、`run-scan.sh` は終了コード 2 で終わります。

> [!IMPORTANT]
> 結果はすべて「候補」です。圧縮済みのベンダーコードや `.next/` などのビルド成果物の誤検出は、根拠を添えて除外してから報告してください。

> [!NOTE]
> Windows の Docker Desktop では、フォルダのマウントが遅いため、Semgrep に数分かかります。

### 動的スキャン（任意）

```sh
scripts/dast-baseline.sh http://localhost:3000 ./reports
```

OWASP ZAP の受動スキャンです。

> [!WARNING]
> ローカルか、自分が管理する検証環境にだけ向けてください。ローカル以外のホストは、`DAST_I_OWN_THIS_TARGET=1` を付けない限り実行を拒否します。

---

## コードからは確認できないこと

ダッシュボードで確認してください。監査の報告では「未確認」として別枠にします。

- [ ] ホスティングの支出上限と自動停止（Vercel Spend Management）
- [ ] WAF のレート制限、Bot Protection / AI Bots のマネージドルールセット
- [ ] LLM・上流プロバイダの月間上限とアラート
- [ ] 本番がどのリポジトリ・ブランチからデプロイされているか
- [ ] Dependabot のアラートとセキュリティアップデート

---

## 設計

<details>
<summary><b>安全のための設計</b></summary>

- バイナリは版と公式チェックサム（amd64・arm64）で、Python のツールは推移的な依存までハッシュ付きで、ベースイメージはダイジェストで固定する（[0003](docs/decisions/0003-pinning-and-updates.md)）
- Semgrep のルールはビルド時に取り込み、空のルールセットがあればビルドを失敗させる。スキャン時にネットワークを使わず、同じイメージなら同じ結果になる（[0004](docs/decisions/0004-semgrep-rules-baked.md)）
- スキャン対象は読み取り専用でマウントし、すべての capability を外し、権限の昇格を禁止する（[0001](docs/decisions/0001-container-user.md)）
- CI は amd64 と arm64 の両方で、キット自身が0件であることと、カナリアを全ツールが検出することを確かめる（[0005](docs/decisions/0005-canary-test.md)）
- このリポジトリの Actions は commit SHA で固定する

</details>

<details>
<summary><b>ツールの選び方（入れたもの・入れなかったもの）</b></summary>

| 使うもの | 理由 |
| --- | --- |
| コンテナ内の5つ | ローカルで完結し、コードを外部に送らない。役割が重ならない |
| `pnpm audit --prod` | パッケージマネージャに入っているので、コンテナの外で手早く確認できる |
| `/security-review`（Claude Code 組み込み） | 修正の差分全体を、修正同士の組み合わせも含めて見直す |
| `codex review --base <branch>` | 実装したエージェントとは別の独立レビュー。PR ごとに使う |
| Dependabot | 単発の検査ではなく、今後出る脆弱性を継続して通知する |

入れなかったもの（Trivy、TruffleHog の検証モード、SaaS 型スキャナ）と、その理由は [0002](docs/decisions/0002-tool-selection.md) にあります。

</details>

---

## ツールの版を上げる

```sh
scripts/update-tools.sh --check   # 古い版があるかだけを確かめる（あれば終了コード 1）
scripts/update-tools.sh           # 版とチェックサムを更新する（差分を確認してからコミット）
tests/run-canary.sh               # 更新後、全ツールが検出できることを確かめる
```

- チェックサムは、各リリースに添付された公式のファイルから取ります
- 週1回の `Pin freshness` ワークフローが `--check` を実行し、古い版があれば失敗して通知します
- ベースイメージのダイジェストと Actions の SHA は Dependabot が更新します

---

## 既知の制限

- Semgrep のルールはイメージのビルド時点のものです。新しいルールを使うには、イメージを作り直します
- Windows / macOS の Docker Desktop では、コンテナは root で動きます（対象は読み取り専用、capability なし）
- スキャナのイメージに入る `pyjwt` 2.13.0 に既知の脆弱性があります。Semgrep 1.178.0 が 2.13 系を要求しているため上げられず、理由と期限（2026-12-31）を付けて [`docker/osv-scanner.toml`](docker/osv-scanner.toml) で受け入れています（スキャナはネットワークを使わず、JWT を検証しないため影響しません）
- LICENSE はまだありません

## 脆弱性の報告

このキット自体の脆弱性は、[SECURITY.md](SECURITY.md) の手順で非公開で報告してください。

---

## 参考資料

- [OWASP Top 10:2025](https://owasp.org/Top10/2025/)
- [OWASP Top 10 for LLM Applications 2025](https://genai.owasp.org/resource/owasp-top-10-for-llm-applications-2025/)
- [CVE-2025-55182（React2Shell）の Next.js のアドバイザリ](https://github.com/vercel/next.js/security/advisories/GHSA-9qr9-h5gf-34mp)
- [Trivy のサプライチェーン攻撃（Palo Alto Networks）](https://www.paloaltonetworks.com/blog/cloud-security/trivy-supply-chain-attack/)
- [axios の npm パッケージ乗っ取り（Microsoft Security Blog）](https://www.microsoft.com/en-us/security/blog/2026/04/01/mitigating-the-axios-npm-supply-chain-compromise/)
- [pnpm: Mitigating supply chain attacks](https://pnpm.io/supply-chain-security)
- [OpenSSF: Detecting Malicious Packages Using the OSV API](https://openssf.org/blog/2026/05/20/detecting-malicious-packages-using-the-osv-api/)
- [zizmor](https://github.com/zizmorcore/zizmor)
- [Vercel: Bot Management](https://vercel.com/docs/bot-management) / [WAF Managed Rulesets](https://vercel.com/docs/vercel-firewall/vercel-waf/managed-rulesets)
