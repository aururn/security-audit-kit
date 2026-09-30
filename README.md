# security-audit-kit

AI コーディングエージェント（Claude Code / Codex）と一緒に、Web アプリの**脆弱性**と**課金の暴走**を調べて直すためのキットです。

主な対象は、LLM や SaaS の API を中継する **Next.js / Node のアプリ**です。

| 入っているもの | 役割 |
| --- | --- |
| [`AGENTS.md`](AGENTS.md) / [`CLAUDE.md`](CLAUDE.md) | エージェントが守るルール（原則・重大度・禁止事項） |
| [`skills/`](skills/) | 監査・公開前の秘密情報検査・修正の進め方・課金の確認の手順 |
| [`checklists/`](checklists/) | カテゴリ別の確認項目（★ = 見落とされがち） |
| [`docker/`](docker/) + [`scripts/`](scripts/) | 版とチェックサムを固定したスキャナのコンテナ |
| [`templates/`](templates/) | Issue / PR の本文テンプレート |

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
| semgrep | 1.178.0 | SAST（default / owasp-top-ten / typescript / react / nextjs / nodejsscan） |
| zizmor | 1.30.1 | GitHub Actions の危険な設定 |
| actionlint | 1.7.12 | GitHub Actions の構文・型の誤り |

出力は `summary.txt`（件数の要約）と、ツールごとの JSON / テキストです。

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

- すべてのツールを版で固定し、リリースに添付された公式のチェックサムと照合してからインストールする
- ベースイメージはダイジェストで固定する
- このリポジトリ自身の CI も、Actions を commit SHA で固定する。キット自身をキットでスキャンし、検出があれば失敗させる
- スキャン対象は読み取り専用でマウントし、すべての capability を外し、権限の昇格を禁止する
- Windows / macOS の Docker Desktop では root、Linux では呼び出し元の uid でコンテナを動かす（どちらでもレポートを書き込めるようにするため）
- Semgrep は `--metrics=off` で動かす。ルールはレジストリから取得するが、コードや利用状況は送らない

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

入れなかったもの：

- **Trivy**：この範囲（Node アプリのソースと lockfile）では osv-scanner・zizmor と役割が重なる。コンテナイメージや IaC を検査する必要が出たら、版とチェックサムを固定して追加する（2026年3月にリリースと GitHub Action のタグが改ざんされた経緯があるため、特に注意）
- **TruffleHog の検証モード**：見つけた鍵が有効かを確かめるために、その鍵を発行元の API に送る。秘密情報をどこかへ送る処理は、利用者の判断なしに行わない
- **コードをアップロードする SaaS 型のスキャナ**：非公開のコードを外部に送るため

</details>

<details>
<summary><b>ツールの版を上げるとき</b></summary>

1. 新しいリリースに添付されたチェックサムファイル（`*_checksums.txt` / `*SHA256SUMS`）から値を取る
2. [`docker/Dockerfile`](docker/Dockerfile) の `ARG`（版と SHA-256）を更新する
3. `scripts/run-scan.sh . ./reports` でキット自身をスキャンし、CI が通ることを確かめる

</details>

---

## 既知の制限

- スキャナのバイナリは x86_64（amd64）版だけ。Apple Silicon ではエミュレーションになる
- ツールの版を自動で更新する仕組みはまだない
- キット自体の検出力を確かめるテスト（脆弱性を仕込んだリポジトリにかける）はまだない

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
