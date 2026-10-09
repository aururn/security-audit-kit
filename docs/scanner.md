# スキャナ

```sh
scripts/run-scan.sh <対象ディレクトリ> [レポートの出力先]
```

Docker のイメージをビルドし、対象を読み取り専用でマウントしてスキャンします。イメージは linux/amd64 と linux/arm64（Apple Silicon）の両方で動きます。

## ツール

| ツール | 版 | 見るもの |
| --- | --- | --- |
| [gitleaks](https://github.com/gitleaks/gitleaks) | 8.30.1 | git の全履歴・全ブランチの秘密情報（値は伏せて出力） |
| [osv-scanner](https://github.com/google/osv-scanner) | 2.6.0 | lockfile の既知の脆弱性と、悪意あるパッケージ（`MAL-`） |
| [semgrep](https://github.com/semgrep/semgrep) | 1.179.0 | SAST。ルールセット default / owasp-top-ten / typescript / react / nodejsscan をビルド時に取り込む |
| [zizmor](https://github.com/zizmorcore/zizmor) | 1.30.1 | GitHub Actions の危険な設定 |
| [actionlint](https://github.com/rhysd/actionlint) | 1.7.12 | GitHub Actions の構文・型の誤り、信頼できない入力のスクリプトへの埋め込み |

外部に送るのは、osv-scanner が脆弱性の照合のために OSV の API に送るパッケージ名と版だけです。コードは送りません。

## 出力

| ファイル | 内容 |
| --- | --- |
| `summary.json` | ツールごとの `status`（`ok` / `skipped` / `error`）、`count`、`note`（補足。浅い clone などの注意もここに出る） |
| `summary.txt` | 同じ内容を人が読む形で |
| `gitleaks.json`、`osv.json`、`semgrep.json`、`zizmor.json`、`actionlint.json` | 各ツールの結果 |

いずれかのツールが `error` になると、`run-scan.sh` は終了コード 2 で終わります。

> [!IMPORTANT]
> 結果はすべて「候補」です。圧縮済みのベンダーコードや `.next/` などのビルド成果物の誤検出は、根拠を添えて除外してから報告してください（[`skills/security-audit`](../skills/security-audit/SKILL.md)）。

> [!NOTE]
> Windows の Docker Desktop ではフォルダのマウントが遅く、大きなリポジトリでは Semgrep に数分かかることがあります。

## 動的スキャン（任意）

```sh
scripts/dast-baseline.sh http://localhost:3000 ./reports
```

OWASP ZAP の受動スキャンです。

> [!WARNING]
> ローカルか、自分が管理する検証環境にだけ向けてください。ローカル以外のホストは、`DAST_I_OWN_THIS_TARGET=1` を付けない限り実行を拒否します。

## コンテナの外で併用するもの

| 使うもの | 用途 |
| --- | --- |
| `pnpm audit --prod` | 依存の既知の脆弱性を手早く確認する |
| `/security-review`（Claude Code 組み込み） | 修正の差分全体を、修正同士の組み合わせも含めて見直す |
| `codex review --base <branch>` | 実装したエージェントとは別の独立レビュー。PR ごとに使う |
| Dependabot | 今後出る脆弱性を継続して通知する |

入れなかったツール（Trivy、TruffleHog の検証モード、SaaS 型のスキャナ）とその理由は [0002](decisions/0002-tool-selection.md) にあります。

## 安全のための設計

- バイナリは版と公式チェックサム（amd64・arm64）で、Python のツールは推移的な依存までハッシュ付きで、ベースイメージはダイジェストで固定する（[0003](decisions/0003-pinning-and-updates.md)）
- Semgrep のルールはビルド時に取り込み、空のルールセットがあればビルドを失敗させる。スキャン時にネットワークを使わず、同じイメージなら同じ結果になる（[0004](decisions/0004-semgrep-rules-baked.md)）
- スキャン対象は読み取り専用でマウントし、すべての capability を外し、権限の昇格を禁止する（[0001](decisions/0001-container-user.md)）
- CI は amd64 と arm64 の両方で、キット自身が0件であることと、カナリアを全ツールが検出することを確かめる（[0005](decisions/0005-canary-test.md)）
