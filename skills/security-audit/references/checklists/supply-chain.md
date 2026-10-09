# 依存関係とサプライチェーンのチェックリスト（OWASP A03 / LLM03）

★ = 一般に見落とされがちな項目。

## 既知の脆弱性

- [ ] `pnpm audit --prod`（または `npm audit --omit=dev`）で critical / high を確認した
  - ★ `dependencies` に開発ツール（例: `eslint-config-next`）が入っていると、本番の依存として数えられる。本番で動くものと区別して報告する
- [ ] OSV-Scanner でも確認した。★ OSV は既知の脆弱性に加えて **悪意あるパッケージ（`MAL-` で始まる ID）** を収録している
- [ ] 直接依存だけでなく、SDK 経由の依存（例: `dify-client` → `axios`）も修正版に解決されている（lockfile で確認）

## 悪意ある版（乗っ取られた公開）への備え

- [ ] ★ pnpm の `minimumReleaseAge` を設定している（公開から一定時間たっていない版を入れない。pnpm 11 では既定で 1440 分）
  - 悪意ある版の多くは数時間以内に見つかって取り下げられる（例: 2026年3月の axios 1.14.1 / 0.30.4 は約3時間で削除）
- [ ] ★ インストール時スクリプトを許可制にしている（pnpm の `allowBuilds` / `onlyBuiltDependencies`）
- [ ] lockfile をコミットし、CI では `--frozen-lockfile` でインストールしている
- [ ] Dependabot のアラート（とセキュリティアップデート）を有効にしている

## ツール自体の信頼

- [ ] ★ スキャナや CI で使うツールも攻撃される前提で、版を固定し、公式のチェックサムと照合している
  - 2026年3月、Trivy のリリース（v0.69.4）と、`trivy-action`（76個中75個のタグ）・`setup-trivy` のタグが改ざんされた
- [ ] GitHub Actions は commit SHA で固定している（`checklists/ci-github-actions.md`）
- [ ] コンテナのベースイメージをダイジェスト（`@sha256:...`）で固定している

## 使っていない依存

- [ ] 使われていないパッケージや、`public/` にベンダリングされたライブラリ（エディタ一式など）を削除した
  - 呼び出し元 0 件だけで判断せず、動的 import、文字列でのパス参照、設定、CI、Dockerfile も確認する
