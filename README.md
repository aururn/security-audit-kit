<div align="center">

# security-audit-kit

**AI エージェントと一緒に、Web アプリの脆弱性と課金の暴走を見つけて直すためのキット**

[![CI](https://github.com/aururn/security-audit-kit/actions/workflows/ci.yml/badge.svg)](https://github.com/aururn/security-audit-kit/actions/workflows/ci.yml)
[![License](https://img.shields.io/github/license/aururn/security-audit-kit)](LICENSE)
![Platforms](https://img.shields.io/badge/platform-amd64%20%7C%20arm64-blue)
![Agents](https://img.shields.io/badge/agents-Claude%20Code%20%7C%20Codex-orange)

[クイックスタート](#クイックスタート) · [使い方](#使い方) · [チェックリスト](checklists/) · [ドキュメント](#ドキュメント)

</div>

---

Claude Code や Codex に「このアプリの脆弱性を調べて」と頼んだときに、**読むだけで終わらせず、手元で再現して確かめ、1件ずつ直す**ための手順・チェックリスト・スキャナのセットです。
LLM や SaaS の API を中継する **Next.js / Node のアプリ**を主な対象にしています。

たとえば、こんな問題を見つけて直します。

- 🔓 他のサイトから利用者になりすまして API を呼べる（CSRF）
- 🔀 ID に `..` や `%2F` を混ぜると、API キー付きのリクエストが別のパスへ届く
- 🕳️ エラー応答に、内部のアドレスがそのまま出る
- 🖼️ LLM の回答に仕込まれた外部画像から、会話の内容が外へ送られる
- 💸 AI クローラの巡回や、認証なしで呼べる LLM の API で、請求額が跳ね上がる
- 📦 乗っ取られた依存パッケージや、書き換えられた GitHub Actions のタグ

## クイックスタート

Docker が必要です。

```sh
git clone https://github.com/aururn/security-audit-kit.git
cd security-audit-kit

scripts/install-skills.sh                        # skills を Claude Code と Codex に入れる
scripts/run-scan.sh /path/to/your-app ./reports  # 対象をスキャンする
```

```text
tool         status   count  note
gitleaks     ok       1      secrets in git history  [t=1s]
osv-scanner  ok       5      vulnerability entries (incl. MAL-*)  [t=2s]
semgrep      ok       12     SAST findings  [t=34s]
zizmor       ok       5      workflow findings  [t=35s]
actionlint   ok       1      workflow errors  [t=35s]
```

<sub>（↑ 脆弱性を仕込んだテスト用のリポジトリをスキャンした実際の出力）</sub>

## 使い方

skills を入れたら、エージェントに頼むだけです。

| こう頼むと | 使われる skill | やること |
| --- | --- | --- |
| 「このリポジトリの脆弱性を調べて」 | [`security-audit`](skills/security-audit/SKILL.md) | 脅威モデル → スキャン → 手作業のレビュー → ローカルで再現 → 報告 |
| 「公開する前に秘密情報がないか確認して」 | [`pre-publish-secret-scan`](skills/pre-publish-secret-scan/SKILL.md) | 全履歴の秘密情報を検査し、誤検出を見分けてから安全に push |
| 「見つかった脆弱性を Issue と PR で直して」 | [`security-fix-workflow`](skills/security-fix-workflow/SKILL.md) | 1 Issue = 1 PR、テストを壊して検出力を確認、独立レビュー |
| 「高額請求にならないか確認して」 | [`cost-abuse-review`](skills/cost-abuse-review/SKILL.md) | 1リクエストのコスト × 回数 × 上限を確認 |

エージェントが守る原則（本番には攻撃しない、脆弱性の詳細を公開の場所に書かない、など）は [`AGENTS.md`](AGENTS.md) にあります。

## 中身

```text
AGENTS.md / CLAUDE.md   エージェントが守るルール
skills/                 監査・公開前の検査・修正・課金の確認の手順（Claude Code / Codex 共通）
checklists/             カテゴリ別の確認項目（★ = 見落とされがち）
docker/  scripts/       版とチェックサムを固定したスキャナ
tests/                  キットの検出力を確かめるカナリア
templates/              Issue / PR の本文テンプレート
docs/                   スキャナの詳細、保守、判断の記録
```

## 対象範囲

| 対象 | 対象外（ほかのツールと組み合わせる） |
| --- | --- |
| Next.js / Node のアプリのソースと lockfile、GitHub Actions、Vercel などへのデプロイ | コンテナイメージ・IaC、ほかの言語のアプリ、本番への侵入テスト |

## ドキュメント

- [スキャナ](docs/scanner.md) — ツールと版、出力の読み方、動的スキャン、安全のための設計
- [チェックリスト](checklists/) — 見落とされがちな項目と、コードからは確認できないこと
- [保守](docs/maintenance.md) — ツールの版の上げ方、テスト、既知の制限
- [判断の記録](docs/decisions/) — なぜこのツールを選んだか、なぜこう作ったか

## セキュリティ

このキット自体の脆弱性は、[SECURITY.md](SECURITY.md) の手順で非公開で報告してください。

## ライセンス

[Apache License 2.0](LICENSE)。スキャナのイメージに入るツールはそれぞれのライセンスに従います（[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)）。
