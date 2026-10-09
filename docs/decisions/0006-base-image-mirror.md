# 0006 ベースイメージを Docker Hub のミラーから取る

- 状態: 採用
- 日付: 2026-10-10

## 背景

スキャナのイメージのベース（`python:3.13-slim`）を Docker Hub から取っていた。GitHub Actions の runner は IP を共有しているため、認証なしの取得が Docker Hub の制限（`429 Too Many Requests`）にかかり、変更と関係なく CI が失敗するようになった（#40）。利用者のリポジトリの CI でスキャナを動かす場合も同じことが起きる。

## 決定

- ベースイメージを Google の Docker Hub ミラー `mirror.gcr.io/library/python` から取る
- ダイジェストは変えない。ダイジェストは中身のハッシュなので、Docker Hub から取ったものと同じイメージであることが保証される
- Docker Hub へのログインは使わない。利用者ごとに秘密情報が必要になるため

## 結果

- CI と利用者の環境のどちらでも、Docker Hub の制限にかからない
- Dependabot は、ミラーのタグ一覧（`/v2/library/python/tags/list`）からダイジェストの更新を提案する。ミラーが Docker Hub より遅れて新しい版を載せることはあるが、Dependabot の cooldown（7 日）より短い
- ミラーが使えなくなったら、`FROM` を `python:3.13-slim@sha256:...`（Docker Hub）に戻す。ダイジェストはそのまま使える
