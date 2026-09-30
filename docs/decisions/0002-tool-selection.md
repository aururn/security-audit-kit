# 0002 入れるツールと入れないツール

- 状態: 採用
- 日付: 2026-09-30

## 背景

対象は、LLM や SaaS の API を中継する Next.js / Node のアプリのソースと lockfile、GitHub Actions。
次の3つを満たすツールを選びたい。

- コードを外部に送らない。外部に送るのは、依存の照合に必要なパッケージ名と版（osv-scanner → OSV の API）だけ
- 役割が重ならない
- 版とチェックサムで固定できる

## 決定

入れる：

| ツール | 役割 |
| --- | --- |
| gitleaks | git の全履歴の秘密情報 |
| osv-scanner | 依存の既知の脆弱性と、悪意あるパッケージ（`MAL-`）。`pnpm audit` に無い情報源を補う |
| semgrep | SAST |
| zizmor | GitHub Actions の危険な設定 |
| actionlint | GitHub Actions の構文・型の誤りと、信頼できない入力のスクリプトへの埋め込み |

入れない：

| ツール | 理由 |
| --- | --- |
| Trivy | この範囲では osv-scanner・zizmor と役割が重なる。コンテナイメージや IaC を検査する必要が出たら、版とチェックサムを固定して追加する（2026年3月にリリースと GitHub Action のタグが改ざんされた経緯がある） |
| TruffleHog の検証モード | 見つけた鍵が有効かを確かめるために、鍵を発行元の API に送る。秘密情報を外部に送る処理は、利用者の判断なしに行わない |
| コードをアップロードする SaaS 型スキャナ | 非公開のコードを外部に送るため |
| OWASP ZAP（コンテナへの同梱） | 大きく、用途も違う（動的検査）。`scripts/dast-baseline.sh` から別のイメージとして、ダイジェストを固定して呼ぶ |

コンテナの外で併用するもの：`pnpm audit --prod`、`/security-review`、`codex review`、Dependabot（README を参照）。

## 結果

対象がコンテナイメージや IaC、Python・Go のアプリに広がったら、この記録を見直す。
