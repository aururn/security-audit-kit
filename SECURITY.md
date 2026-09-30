# セキュリティポリシー

## 脆弱性の報告

このキット自体（スキャナのコンテナ、スクリプト、skills の手順）に脆弱性を見つけた場合は、
**公開の Issue ではなく**、GitHub の [Private vulnerability reporting](https://github.com/aururn/security-audit-kit/security/advisories/new)
から非公開で報告してください。

報告に含めてほしいこと:

- 影響を受けるファイルと版（コミット SHA）
- 再現手順
- 想定される影響（例: スキャン対象のリポジトリに書き込める、秘密情報が出力される、検査が黙って無効になる）

## 対象

- `docker/`（スキャナのイメージ、`scan.sh`）
- `scripts/`
- `skills/` と `AGENTS.md` の手順のうち、それに従うと利用者に不利益が出るもの
  （秘密情報を外部に送る、本番に攻撃的なリクエストを送る、など）

各スキャナ（gitleaks、osv-scanner、semgrep、zizmor、actionlint）自体の脆弱性は、それぞれの開発元に報告してください。

## 対応

- 固定しているツールに重大な脆弱性やサプライチェーン攻撃が報告された場合は、
  `scripts/update-tools.sh` で版を上げるか、影響のない版に固定し直します
- 修正は非公開で準備し、修正を公開してから詳細を開示します
