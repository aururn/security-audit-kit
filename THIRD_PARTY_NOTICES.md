# サードパーティの License

このリポジトリのファイルは Apache License 2.0 です（[LICENSE](LICENSE)、[NOTICE](NOTICE)）。

以下は、このリポジトリには **含まれていません**。`docker/Dockerfile` がイメージのビルド時にダウンロードするか、
スクリプトが実行時に取得するもので、それぞれの License に従います。

## スキャナのイメージにビルド時に入るもの

| ソフトウェア | 入れ方 | License |
| --- | --- | --- |
| gitleaks | GitHub のリリース | MIT |
| osv-scanner | GitHub のリリース | Apache-2.0 |
| actionlint | GitHub のリリース | MIT |
| Semgrep（CLI） | PyPI | LGPL-2.1 |
| zizmor | PyPI | MIT |
| Semgrep と zizmor の推移的な依存 | PyPI（[`docker/requirements.txt`](docker/requirements.txt)） | 各パッケージによる |
| Semgrep のルール（p/default ほか） | semgrep.dev のレジストリ | Semgrep Rules License v1.0 |
| shellcheck | Debian のパッケージ | GPL-3.0 |
| git | Debian のパッケージ | GPL-2.0 |
| jq | Debian のパッケージ | MIT |
| curl、ca-certificates | Debian のパッケージ | curl License、MPL-2.0 ほか |
| Python（ベースイメージ `python:3.13-slim`） | Docker Hub | PSF-2.0 と Debian の各パッケージの License |

## 実行時に取得するもの

| ソフトウェア | 使う場所 | License |
| --- | --- | --- |
| OWASP ZAP（`ghcr.io/zaproxy/zaproxy`） | `scripts/dast-baseline.sh` | Apache-2.0 |

## ビルドしたイメージを配布する場合

このリポジトリは、ビルド済みのイメージを配布しません。`scripts/run-scan.sh` が利用者の手元で
イメージをビルドするため、通常の使い方では、下に挙げる再配布の条件はどれも関係しません。

ビルドしたイメージを他の人に配布する（コンテナレジストリで公開する、など）場合にだけ、次に注意してください。

- **shellcheck（GPL-3.0）、git（GPL-2.0）、Semgrep（LGPL-2.1）**：配布する人は、対応するソースコードを
  入手できるようにする義務を負う
- **Semgrep のルール**：Semgrep Rules License v1.0 に再配布の条件がある。イメージをレジストリに公開するなど、
  再配布にあたることをする前に、条件を確認する（[#5](https://github.com/aururn/security-audit-kit/issues/5)）
- 推移的な依存を含めた一覧が必要なら、イメージから SBOM を作成する
