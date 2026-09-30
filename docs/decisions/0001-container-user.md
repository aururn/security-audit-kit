# 0001 スキャナのコンテナを動かすユーザー

- 状態: 採用
- 日付: 2026-09-30

## 背景

最初は、コンテナ内に一般ユーザー（uid 10001）を作って動かしていた。しかし、レポートを書き出すバインドマウントに書き込めなかった。

- Windows / macOS の Docker Desktop：バインドマウント先に、一般ユーザーでは書き込めない
- Linux（GitHub Actions を含む）：レポートのディレクトリはホストのユーザー（例: uid 1001）の持ち物。すべての capability を外した root は、ファイル所有者の権限を越えられない（`CAP_DAC_OVERRIDE` が無い）ため書き込めない

どちらの失敗も、スキャン結果が「0件」に見える形で表に出た。

## 決定

- イメージの既定は root とする（Docker Desktop で書き込めるようにするため）
- Linux では、`scripts/run-scan.sh` が呼び出し元の uid / gid（`--user "$(id -u):$(id -g)"`）と `HOME=/tmp` を渡す
- どちらの場合も、次の3点で権限を絞る
  - スキャン対象は読み取り専用でマウントする
  - `--cap-drop ALL` で全 capability を外す
  - `--security-opt no-new-privileges` で権限の昇格を禁止する
- Semgrep の `missing-user` の指摘は、この理由を書いたうえで `nosemgrep` で抑える

## 結果

- どの OS でもレポートを書き出せる
- root で動くのは Docker Desktop の場合だけで、そのときも対象には書き込めず、capability も持たない
- 書き込みの失敗は、スキャナの `error` として `summary.json` に出る。CI はそれを失敗として扱う（[0005](0005-canary-test.md)）
