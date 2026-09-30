# security-audit-kit

Web アプリ（特に、LLM や SaaS の API を中継する Next.js / Node のアプリ）の脆弱性と
「課金の暴走」を、AI コーディングエージェントと一緒に調べて直すためのキットです。

- エージェント向けのルール（`AGENTS.md` が正本、`CLAUDE.md` はそれを読み込む）
- Claude Code / Codex 共通の skills（監査・公開前の秘密情報検査・修正の進め方・課金の確認）
- 見落とされがちな項目に印を付けたチェックリスト
- 版とチェックサムを固定したスキャナのコンテナと実行スクリプト
- Issue / PR のテンプレート

実際のアプリの監査と修正（CSRF、パストラバーサル、エラー応答からの情報漏洩、LLM 出力経由の
情報持ち出し、課金の暴走など）で役に立った手順と、そこで分かった落とし穴を一般化してまとめています。

## 中身

```text
AGENTS.md                     エージェント共通のルール（原則・重大度・禁止事項）
CLAUDE.md                     AGENTS.md を読み込み、Claude Code 固有の補足を足す
skills/
  security-audit/             監査の手順。偽の上流サーバー（fake-upstream.mjs）付き
  pre-publish-secret-scan/    リポジトリを公開する・公開側へ push する前の秘密情報の検査
  security-fix-workflow/      1 Issue = 1 PR、テストの検出力確認、独立レビュー、並列レーン
  cost-abuse-review/          課金の暴走（AI クローラ、動的レンダリング、認証なしの LLM 呼び出し）
checklists/                   カテゴリ別の確認項目（★ = 見落とされがち）
docker/                       スキャナのイメージ（Dockerfile と scan.sh）
scripts/
  run-scan.sh                 イメージをビルドし、対象リポジトリを読み取り専用でスキャン
  dast-baseline.sh            OWASP ZAP の受動スキャン（ローカル / 自分の検証環境だけ）
  install-skills.sh           skills を ~/.claude/skills と ~/.codex/skills に入れる
templates/                    Issue / PR の本文テンプレート
```

## 使い方

### 1. skills を入れる

```sh
scripts/install-skills.sh          # 同名の skill があれば飛ばす
scripts/install-skills.sh --force  # 上書きする
```

エージェントには「このリポジトリを監査して」「公開前に秘密情報を確認して」のように頼めば、
対応する skill が使われます。skills 本文は英語、チェックリストと README は日本語です。

### 2. スキャナを動かす（Docker が必要）

```sh
scripts/run-scan.sh /path/to/target ./reports
cat reports/summary.txt
```

| ツール | 版 | 見るもの |
| --- | --- | --- |
| gitleaks | 8.30.1 | git の全履歴・全ブランチの秘密情報（値は伏せて出力） |
| osv-scanner | 2.6.0 | lockfile の既知の脆弱性と、悪意あるパッケージ（`MAL-`） |
| semgrep | 1.178.0 | SAST（default / owasp-top-ten / typescript / react / nextjs / nodejsscan） |
| zizmor | 1.30.1 | GitHub Actions の危険な設定（タグ参照、`pull_request_target`、権限など） |
| actionlint | 1.7.12 | GitHub Actions の構文・型の誤り |

- 対象は読み取り専用でマウントし、コンテナはすべての capability を外して動かします
- Semgrep はルールをレジストリから取得しますが、`--metrics=off` でコードや利用状況は送りません
- 結果はすべて「候補」です。誤検出（圧縮済みのベンダーコード、`.next/` などのビルド成果物）を
  根拠付きで除外してから報告します（`skills/security-audit`）
- Windows の Docker Desktop では、フォルダのマウントが遅いため Semgrep に数分かかります

### 3. 動的スキャン（任意）

```sh
scripts/dast-baseline.sh http://localhost:3000 ./reports
```

ローカルか、自分が管理する検証環境にだけ向けてください。ローカル以外のホストは、
`DAST_I_OWN_THIS_TARGET=1` を付けない限り実行を拒否します。本番には向けないでください。

### 4. ダッシュボードで確認すること

コードからは確認できません。監査の報告でも「未確認」として別枠にします。

- ホスティングの支出上限と自動停止（Vercel Spend Management）
- WAF のレート制限、Bot Protection / AI Bots のマネージドルールセット
- LLM・上流プロバイダの月間上限とアラート
- 本番がどのリポジトリ・ブランチからデプロイされているか
- Dependabot のアラートとセキュリティアップデート

## ツールの選び方

| 使うもの | 理由 |
| --- | --- |
| コンテナ内の5つ | ローカルで完結し、コードを外部に送らない。役割が重ならない |
| `pnpm audit --prod` | パッケージマネージャに入っているので、コンテナの外で手早く確認できる |
| `/security-review`（Claude Code 組み込み） | 修正の差分全体を、修正同士の組み合わせも含めて見直す |
| `codex review --base <branch>` | 実装したエージェントとは別の独立レビュー。PR ごとに使う |
| Dependabot | 単発の検査ではなく、今後出る脆弱性を継続して通知する |

入れなかったもの:

- **Trivy**：この範囲（Node アプリのソースと lockfile）では osv-scanner・zizmor と役割が重なる。
  コンテナイメージや IaC を検査する必要が出たら、版とチェックサムを固定して追加する
  （2026年3月にリリースと GitHub Action のタグが改ざんされた経緯があるため、特に注意）
- **TruffleHog の検証モード**：見つけた鍵が有効かを確かめるために、その鍵を発行元の API に送る。
  秘密情報をどこかへ送る処理は、利用者の判断なしに行わない
- **コードをアップロードする SaaS 型のスキャナ**：非公開のコードを外部に送るため

## 安全のための設計

- すべてのツールを版で固定し、リリースに添付された公式のチェックサムと照合してからインストールする
- ベースイメージはダイジェストで固定する
- このリポジトリ自身の CI も、Actions を commit SHA で固定する
- スキャナは対象を書き換えない（読み取り専用マウント）

版を上げるときは、新しいリリースのチェックサムファイルから値を取り直し、`docker/Dockerfile` の
`ARG` を更新します。

## 見落とされがちな確認事項（抜粋）

詳細と確認方法は `checklists/` にあります。

- SDK が URL のパスに ID をエンコードせずに連結していると、`..` や `%2F` で API キー付きの
  リクエストを別のパスへ向けられる（Next.js はルートパラメータの `%2F` をデコードする）
- `SameSite=None` の Cookie ＋ 送信元チェックなし ＝ CSRF。`request.json()` は Content-Type を見ない
- エラー応答に `error.message` を入れると、内部アドレスがそのまま利用者に返る
- LLM の出力を Markdown で描画すると、既定では外部画像を読み込む。会話の内容を URL に載せて外へ送られる
- LLM を呼ぶのはチャット本体だけとは限らない（会話名の自動生成、要約など）
- ルートレイアウトで `cookies()` / `headers()` を読むと全ページが動的レンダリングになり、
  クローラの巡回がそのまま課金になる
- `public/` に置いたまま使っていない大きなファイルは、配信されるたびに転送量がかかる
- 修正したつもりのテストが、実は別の検証で弾かれて通っていることがある。
  修正を一時的に無効にしてテストが落ちることを確かめる
- 公開リポジトリに修正前の脆弱性の詳細を書かない。本番がどのリポジトリからデプロイされるかを確かめる
- スキャナや CI のツール自体が乗っ取られることがある（Trivy、axios の事例）

## 出典

- [OWASP Top 10:2025](https://owasp.org/Top10/2025/)
- [OWASP Top 10 for LLM Applications 2025](https://genai.owasp.org/resource/owasp-top-10-for-llm-applications-2025/)
- [CVE-2025-55182（React2Shell）の Next.js のアドバイザリ](https://github.com/vercel/next.js/security/advisories/GHSA-9qr9-h5gf-34mp)
- [Trivy のサプライチェーン攻撃（Palo Alto Networks）](https://www.paloaltonetworks.com/blog/cloud-security/trivy-supply-chain-attack/)
- [axios の npm パッケージ乗っ取り（Microsoft Security Blog）](https://www.microsoft.com/en-us/security/blog/2026/04/01/mitigating-the-axios-npm-supply-chain-compromise/)
- [pnpm: Mitigating supply chain attacks（minimumReleaseAge など）](https://pnpm.io/supply-chain-security)
- [OpenSSF: Detecting Malicious Packages Using the OSV API](https://openssf.org/blog/2026/05/20/detecting-malicious-packages-using-the-osv-api/)
- [zizmor](https://github.com/zizmorcore/zizmor)
- [Vercel: Bot Management](https://vercel.com/docs/bot-management) / [WAF Managed Rulesets](https://vercel.com/docs/vercel-firewall/vercel-waf/managed-rulesets)
