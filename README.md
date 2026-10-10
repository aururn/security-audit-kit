# security-audit-kit

[![CI](https://github.com/aururn/security-audit-kit/actions/workflows/ci.yml/badge.svg)](https://github.com/aururn/security-audit-kit/actions/workflows/ci.yml)
[![License](https://img.shields.io/github/license/aururn/security-audit-kit)](LICENSE)

Claude Code や Codex と一緒に、Web アプリの脆弱性と課金の暴走を見つけて直すためのキットです。

コードを読むだけで終わらせず、手元で再現して確かめ、1 件ずつ直すための手順（skills）、チェックリスト、スキャナのコンテナをまとめています。
LLM や SaaS の API を中継する Next.js / Node のアプリが主な対象です。コンテナイメージ、IaC、ほかの言語のアプリは対象外です。

## 使い始める

Docker が必要です。Windows では Git Bash で実行します。

いちばん手軽なのは、エージェントにこのリポジトリの URL を貼って頼む方法です。エージェントは [AGENTS.md](AGENTS.md) の「このキットの URL を渡されたとき」に従います。

```text
https://github.com/aururn/security-audit-kit を使って、このリポジトリの脆弱性を調べて
```

Claude Code では plugin として入れると、URL を貼らずに使えます。

```sh
claude plugin marketplace add aururn/security-audit-kit
claude plugin install security-audit-kit@security-audit-kit
```

Codex で使う場合や、手元で直接スキャンする場合は clone します。

```sh
git clone https://github.com/aururn/security-audit-kit.git
cd security-audit-kit
scripts/install-skills.sh                        # skills を Claude Code と Codex に入れる
scripts/run-scan.sh /path/to/your-app ./reports  # 対象をスキャンする
```

GitHub Actions で PR ごとにスキャンする方法は、[スキャナ](docs/scanner.md)の「GitHub Actions で PR ごとに回す」にあります。

入れた後は、エージェントに頼むだけです。

```text
このリポジトリの脆弱性を調べて          # security-audit
公開する前に秘密情報がないか確認して    # pre-publish-secret-scan
見つかった脆弱性を Issue と PR で直して  # security-fix-workflow
高額請求にならないか確認して            # cost-abuse-review
```

## Highlights

- **入れなくても使える。** URL を貼れば、エージェントがキットを一時的に取得して手順に従います。利用者の環境には何も入れません。
- **読むだけで終わらせない。** 疑わしい箇所は、偽の上流サーバーを立てて手元で再現してから報告します。
- **本番には攻撃しない。** 本番に送るのは読み取りのリクエストだけです。動的スキャンはローカルか検証環境に限ります。
- **課金の暴走も見る。** 認証なしで呼べる LLM の API、キャッシュのないページ、AI クローラの巡回による請求も確かめます。
- **スキャナも疑う。** gitleaks、osv-scanner、semgrep、zizmor、actionlint を、版とチェックサムで固定したコンテナで動かします。
- **黙って 0 件にならない。** 各スキャナが必ず検出する種（カナリア）を、CI で毎回検出させます。

## Documentation

- [スキャナ](docs/scanner.md)：ツールと版、出力の読み方、動的スキャン
- [チェックリスト](checklists/)：カテゴリ別の確認項目と、コードからは確認できないこと
- [エージェントが守る原則](AGENTS.md)：本番に攻撃しない、脆弱性の詳細を公開の場所に書かない、など
- [保守](docs/maintenance.md)：ツールの版の上げ方、テスト、既知の制限
- [判断の記録](docs/decisions/)
- [サードパーティの License](THIRD_PARTY_NOTICES.md)
- [このキットの脆弱性の報告](SECURITY.md)

## License

[Apache License 2.0](LICENSE)
