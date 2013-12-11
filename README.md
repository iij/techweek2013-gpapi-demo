IIJ Technical WEEK 2013 GIO API サンプル
========================================

[IIJ TechnicalWEEK 2013](http://www.iij.ad.jp/news/seminar/2013/techweek.html?i=iw01b131001)
のデモで利用したオートスケールのサンプルコードです。

# できること

- 仮想サーバの追加、SSH 公開鍵の追加、起動
- 仮想サーバのクローニング、起動、FW+LB 配下への追加
- 仮想サーバの品目変更
- FW+LB オプションの追加、プール、および仮想サービスの設定
- FW+LB オプションの品目変更

# Getting started

## 動作環境

-   Ruby 1.9.3+
-   [Bundler](http://bundler.io/)

## Bundler を使ったインストール

*あらかじめ Git および Bundler gem をインストールしておく必要があります。*

このレポジトリをクローンし、レポジトリのディレクトリ内で `bundle install` します。

~~~~
$ git clone https://github.com/iij/techweek2013-gpapi-demo.git
$ cd techweek2013-gpapi-demo
$ bundle install --path vendor/bundle
~~~~

## 設定

### 基本的な設定

このプログラムは、デフォルトではカレントディレクトリ内の `config.yml` から、
API のアクセスキーとシークレットキー、クローニング元 VM のサービスコード、
FW+LB オプションの初期設定内容などを読み込みます。
このファイルは YAML 形式で記述する必要があります。

このレポジトリ内の [./config.yml](config.yml) に設定例があります。

各設定項目の内訳は:

|項目名                               |説明                                                         |
|-------------------------------------|-------------------------------------------------------------|
|gp_service_code                      |仮想マシンや FW+LB が属する GP のサービスコード (gpXXXXXXXX) |
|credentials.access_key               |アクセスキーID                                               |
|credentials.secret_key               |シークレットキー                                             |
|ssh_public_key                       |仮想マシン新規構築時に設定する SSH 公開鍵                    |
|source_vm                            |クローン元 VM のサービスコード (gcXXXXXXXX)                  |
|lb.virtual_servers                   |FW+LB 仮想サービスの設定                                     |
|lb.virtual_servers.[].name           |FW+LB 仮想サービスの名前                                     |
|lb.virtual_servers.[].protocol       |FW+LB 仮想サービスのプロトコル                               |
|lb.virtual_servers.[].port           |FW+LB 仮想サービスのポート                                   |
|lb.virtual_servers.[].pool           |FW+LB 仮想サービスが利用するプール                           |
|lb.virtual_servers.[].traffic_ip_list|FW+LB 仮想サービスが仕様する LB グローバルアドレスのリスト   |
|lb.pools                             |FW+LB プールの設定                                           |
|lb.pools.[].name                     |FW+LB プールの名前                                           |
|lb.pools.[].port                     |FW+LB プール内の各ノードのポート                             |
|lb.pools.[].roles                    |FW+LB プールに追加するノードの role (vmstore.yml 内に記録)   |

### 仮想サーバの role

`gp_service_code` で指定された GP サービスコード内にある仮想マシンのうち、
FW+LB プール内に追加される仮想マシンを判別するために、このスクリプトでは role 概念を導入しています。
仮想マシンの追加・クローニングをする際に、新しく追加される仮想マシンの role を指定すると、
`vmstore.yml` に仮想マシンの role の情報が記録されます。デフォルトでは `vmstore.yml` はカレントディレクトリ内に生成されます。
既存の仮想マシンの role 変更などは、下記 Usage を参照してください。

## Usage

Bundler を使ってインストールした場合には、実行する際に `bundle exec` を利用する必要があります。

-   仮想マシンの状態を取得する

    ~~~~
    $ bundle exec bin/gp_manage vm status [--update]
    ~~~~

    -   オプション
        -   `--update`: キャッシュを更新する

-   新規に仮想マシンを作成する

    ~~~~
    $ bundle exec bin/gp_manage vm add <VM TYPE> <OS> <ROLE> <NUM>
    ~~~~

    -   パラメータ
        -   VM TYPE: 仮想サーバの品目 (V10 など)
        -   OS: 仮想サーバの OS (CentOS6_64_U など)
        -   ROLE: 仮想サーバの role
        -   NUM: 契約数
    -   オプション
        -   `--disk1`, `--disk2`: 追加ディスクオプションの品目 (100, 300, 500, HS300)
        -   `location_l`: ロケーション L に作成する仮想サーバ数
        -   `location_r`: ロケーション R に作成する仮想サーバ数
        -   `--start`: 契約追加完了を待ち、SSH 公開鍵登録と仮想マシンの起動を行なう

    ~~~~
    $ bundle exec bin/gp_manage vm add V40 CentOS6_64_U web 2 --location_l=1 --disk1=HS300 --start
    ~~~~

-   既存の仮想サーバをクローニングして、新しい仮想サーバを作成する

    ~~~~
    $ bundle exec bin/gp_manage vm clone <NUM> <VM TYPE> <ROLE>
    ~~~~

    -   パラメータ
        -   VM TYPE: 仮想サーバの品目 (V10 など)
        -   ROLE: 仮想サーバの role
        -   NUM: 契約数
    -   オプション
        -   `--wait`: 契約追加完了を待つ
        -   `--start`: 契約追加完了を待ち、仮想マシンの起動を行なう
        -   `--attach_fwlb`: 仮想マシンを FW+LB オプション配下に接続する

-   仮想マシン品目変更

    仮想マシンの品目変更を行ないます。仮想マシンが FW+LB プール内に登録されている場合は、
    品目変更中は FW+LB プールからノードを削除し、品目変更完了後にプールに再びノードを追加します。

    ~~~~
    $ bundle exec bin/gp_manage vm change_type <GC_SERVICE_CODE> <VM TYPE>
    ~~~~

    -   パラメータ
        -   GC_SERVICE_CODE: 品目変更を行なう仮想サーバの gc サービスコード
        -   VM TYPE: 変更後の仮想サーバの品目 (V10 など)

-   FW+LB オプション追加

    ~~~~
    $ bundle exec bin/gp_manage lb add <LB TYPE>
    ~~~~

    -   パラメータ
        -   LB TYPE: FW+LB オプションの品目 (B100M, S100M など)
    -   オプション
        -   `--clustered`: 冗長化あり (指定しない場合は冗長化なし)
        -   `--init`: 構築完了後、FW+LB の仮想サービスおよびプールの設定を行なう

-   FW+LB オプション設定更新

    config.yml 内の設定および role 指定にもとづき、FW+LB オプションの仮想サービス
    およびプールの設定を行なう

    ~~~~
    $ bundle exec bin/gp_manage lb update_setting [GL_SERVICE_CODE]
    ~~~~

    -   パラメータ
        -   GL_SERVICE_CODE: 設定更新を行なう FW+LB の gl サービスコード (省略した場合は gp 内の全ての FW+LB において設定更新を行なう)

-   FW+LB の設定を取得する

    ~~~~
    $ bundle exec bin/gp_manage vm info [--update]
    ~~~~

    -   オプション
        -   `--update`: キャッシュを更新する

-   FW+LB オプション品目変更

    ~~~~
    $ bundle exec bin/gp_manage lb change_type <GL_SERVICE_CODE> <LB TYPE>
    ~~~~

    -   パラメータ
        -   GL_SERVICE_CODE: 品目変更を行なう FW+LB オプションの gl サービスコード
        -   LB TYPE: 変更後の FW+LB オプションの品目 (B100M, S100M など)

