# 保守

## ツールの版を上げる

```sh
scripts/update-tools.sh --check   # 古い版があるかだけを確かめる（あれば終了コード 1）
scripts/update-tools.sh           # 版とチェックサムを更新する（差分を確認してからコミット）
tests/run-canary.sh               # 更新後、全ツールが検出できることを確かめる
```

- チェックサムは、各リリースに添付された公式のファイルから取ります
- 週1回の `Pin freshness` ワークフローが `--check` を実行し、古い版があれば失敗して通知します
- ベースイメージのダイジェストと Actions の SHA は Dependabot が更新します（公開から7日待つ cooldown 付き）

## 入れた skills を新しくする

plugin として入れた場合は、次の 2 行で新しくします。plugin は版を固定していないので、コミットごとに新しい版が届きます（[0007](decisions/0007-plugin-distribution.md)）。

```sh
claude plugin marketplace update security-audit-kit
claude plugin update security-audit-kit@security-audit-kit
```

`scripts/install-skills.sh` で入れた場合は、入れた各 skill にキットのコミットと clone の場所（`.kit-version`）が記録されています。

```sh
scripts/install-skills.sh --check   # 入れた skill が、今のキットより古いコミット由来かを調べる
scripts/install-skills.sh --force    # 古いものを入れ直す
```

キットを `git pull` した後に `--check` で確かめ、古ければ `--force` で入れ直します。

## テスト

```sh
tests/run-canary.sh
```

各スキャナが必ず検出する種（偽の鍵、脆弱な版の lockfile、危険なワークフロー、危険なコード）を仕込んだ使い捨てのリポジトリを作り、5つのツールすべてが1件以上検出することを確かめます。偽の鍵は実行のたびに生成し、リポジトリには残しません（[0005](decisions/0005-canary-test.md)）。

CI（amd64・arm64）は、これに加えて次を確かめます。

- キット自身をスキャンして、全ツールが0件
- shellcheck
- `tests/test-dast-guard.sh`：`dast-baseline.sh` がローカル以外（`http://localhost:1@evil.example` のように、ローカルに見えるだけのものを含む）を拒否すること、WARN のある結果を「問題なし」と表示しないこと。docker を偽物に差し替えて動かすので、ZAP は要りません

## 既知の制限

- Semgrep のルールはイメージのビルド時点のものです。取り込みから `SEMGREP_RULES_MAX_AGE_DAYS`（既定 30）日より古いと、スキャン結果の note に経過日数が出ます。新しいルールにするには、イメージを作り直します（キャッシュを無視するなら `docker build --no-cache docker/`）（[#4](https://github.com/aururn/security-audit-kit/issues/4)）
- Windows / macOS の Docker Desktop では、コンテナは root で動きます。対象は読み取り専用で、capability も外しています（[#6](https://github.com/aururn/security-audit-kit/issues/6)）

ほかの課題は [Issues](https://github.com/aururn/security-audit-kit/issues) にあります。
