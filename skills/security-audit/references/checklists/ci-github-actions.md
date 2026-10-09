# CI / GitHub Actions のチェックリスト

`zizmor`（静的解析）と `actionlint`（構文と型の検査）で機械的に拾える項目が多い。
★ = 一般に見落とされがちな項目。

- [ ] ★ サードパーティの Action を、タグではなく commit SHA で固定している（zizmor: `unpinned-uses`）
  - タグは書き換えられる。2026年3月に `trivy-action` などのタグがまとめて書き換えられた
- [ ] `pull_request_target` と `workflow_run` を使っていない。使うなら、PR のコードを書き込み権限付きで実行しない（zizmor: `dangerous-triggers`）
- [ ] `permissions:` をワークフローの先頭で最小（例: `contents: read`）にしている（zizmor: `excessive-permissions`）
- [ ] `actions/checkout` に `persist-credentials: false`（zizmor: `artipacked`）
- [ ] `run:` の中に `${{ github.event.* }}` などの信頼できない値を直接埋め込んでいない。環境変数を経由する（zizmor: `template-injection`）
- [ ] ★ アップロードする成果物（テストレポート、トレース）に秘密情報が入っていない。テストはダミーの認証情報で動く
- [ ] フォークからの PR ではシークレットを使わない
- [ ] CI の検証内容が、ローカルで実行する検証と一致している（lint を warning 0 で落とす、型チェック、単体、E2E）
