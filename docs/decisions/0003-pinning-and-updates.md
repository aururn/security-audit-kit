# 0003 ツールの固定と更新の方法

- 状態: 採用
- 日付: 2026-09-30

## 背景

スキャナや CI のツール自体がサプライチェーン攻撃の標的になる。

- 2026年3月、Trivy のリリースと、`trivy-action` / `setup-trivy` のタグが改ざんされた
- 同じ月に、axios の npm パッケージが乗っ取られた

一方で、固定したまま放置すると、ツールも検出ルールも古くなる。

## 決定

固定：

| 対象 | 固定の方法 |
| --- | --- |
| バイナリ（gitleaks、osv-scanner、actionlint） | 版と、リリースに添付された公式チェックサムの SHA-256（amd64・arm64 それぞれ） |
| Python のツール（semgrep、zizmor） | `requirements.in` で直接の版を固定し、推移的な依存まで `requirements.txt` にハッシュ付きで固定。`pip install --require-hashes` |
| ベースイメージ | ダイジェスト |
| GitHub Actions | commit SHA |

更新：

| 対象 | 仕組み |
| --- | --- |
| バイナリ・Python のツール | `scripts/update-tools.sh`。チェックサムは公式のファイルから取る（ダウンロードしたものを自分で計算した値は使わない）。週1回の `pin-freshness` ワークフローが `--check` を実行し、古ければ失敗して所有者に通知する |
| ベースイメージ・Actions | Dependabot |

`update-tools.sh` と `pin-freshness` は、公開から 7 日以上（`COOLDOWN_DAYS`）経った版だけを更新の候補にする。乗っ取られたリリースは数時間〜数日で取り下げられることが多く（例: 2026年3月の axios 1.14.1 / 0.30.4 は約3時間で削除）、待つことで取り込みを避ける。Dependabot のベースイメージと Actions の cooldown（7日）と同じ考え方。cooldown 中の新しい版は知らせるが採用せず、`--check` も失敗させない。

更新したら、必ずイメージを作り直し、カナリア（[0005](0005-canary-test.md)）を通す。

## 結果

- 改ざんされた版を「最新だから」と自動で取り込むことはない。更新は人が差分を見てからコミットする
- Python の依存は、公開後に差し替えられても、ハッシュが合わずインストールに失敗する
