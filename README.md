# Aqua Bubble Tycoon（あわあわアクアタイクーン）

泡を集めてコインを稼ぎ、島を解放して転生（リバース）を重ねる、Roblox向けシミュレーター／タイクーン系ゲームのMVPです。
マップ・UI・看板はすべてコードで自動生成するので、Roblox Studioで空のプレイスにスクリプトを同期するだけで遊べます。外部アセット・他人のモデルは使っていません。

## 遊び方

1. 泡（青い球）に触るとコインがもらえる
2. 画面右上の **SHOP** で「泡の価値」「移動速度」「磁石」をアップグレード
3. スポーン前のポータルで **サンゴ礁（500コイン）→ 深海（5,000コイン）** を解放。奥ほど泡の価値が高い
4. **10,000コイン** でリバースすると、コインとレベルはリセットされる代わりに獲得量に永久倍率 **+50%** が付く（コストは回ごとに3倍）

データ（コイン・泡数・リバース回数・レベル・解放済みゾーン）は DataStore に自動保存されます（120秒ごとのオートセーブ＋退出時保存）。

## 収益化の仕組み（すでにコード組み込み済み）

お金に関わる処理はすべてサーバー側で検証しています。公開後にIDを差し替えるだけで有効になります。

| 種類 | 内容 | コード側 |
|---|---|---|
| ゲームパス | コイン2倍 | `Config.GamePasses.DoubleCoins` |
| ゲームパス | 磁石（自動回収）の範囲2倍 | `Config.GamePasses.AutoCollect` |
| ゲームパス | VIP（速度+8） | `Config.GamePasses.Vip` |
| 開発者製品（消費型） | コイン 1,000 | `Config.Products.CoinsSmall` |
| 開発者製品（消費型） | コイン 15,000 | `Config.Products.CoinsLarge` |

※ ガチャ等のランダム課金は入れていません（Robloxの有料ランダムアイテム方針に触れやすいため）。中身が固定で分かる課金だけにしています。

### 現金化（DevEx）についての正直な目安

- Robuxを現金に替える DevEx は **30,000 Earned Robux 以上** が最低ラインで、換算レートは標準 **$0.0038 / Robux（30,000 Robux ≒ $114）** です（2025-09-05 改定、要ID認証・税務フォーム等）。
- つまり「公開すれば稼げる」ではなく、まず **30,000 Robux分の売上** が最初の目標です。ゲームパス価格の目安: コイン2倍 199 Robux / 磁石2倍 149 Robux / コインパック 49〜399 Robux 程度から始めて、実績を見て調整してください。
- 収益はプレイヤー数次第で保証はありません。このリポジトリは「遊べる土台＋課金の配線」までを用意したもので、集客（サムネイル・タイトル・アップデート・SNS告知）が売上を決めます。

## Roblox Studioへの取り込み方

> **初めての方は [docs/SETUP_JP.md](docs/SETUP_JP.md) の手順書を上から順にやってください。** この下は要約です。



### 方法A: Rojo（推奨・このリポジトリの前提）

1. PCに [Roblox Studio](https://create.roblox.com/) をインストールし、自分のRobloxアカウントでログインする
2. [Rojo](https://rojo.space/) をインストールする（`aftman install` または Rojo の配布ページから）。Studio側にも Rojo プラグインを入れる
3. このリポジトリを clone し、フォルダで `rojo serve` を実行
4. Studioで新規プレイス（Baseplate）を開き、Rojoプラグインの **Connect** を押すとスクリプトが同期される
5. 再生ボタンで遊べることを確認する

### 方法B: 手コピ（Rojoなし）

1. Studioで新規プレイスを開く
2. `src/shared/Config.luau` → ReplicatedStorage に Folder「Shared」を作り、その中に ModuleScript「Config」として貼る
3. `src/server/` の2ファイル → ServerScriptService に Folder「Server」を作り、`Main.server.luau` は Script、`WorldBuilder.luau` は ModuleScript として貼る
4. `src/client/Main.client.luau` → StarterPlayer > StarterPlayerScripts に Folder「Client」を作り、LocalScript として貼る

### データ保存を有効にする

Studioの **Game Settings > Security > Enable Studio Access to API Services** をONにしてください（OFFだと保存が失敗し、出力に警告が出ますがゲーム自体は動きます）。

## 公開と課金を有効にする手順

1. Studioの **File > Publish to Roblox** で自分のアカウントに公開し、Creator Hub でゲームページを開く
2. ゲームを **Public** に設定する
3. Creator Hub の **Monetization > Passes** でゲームパスを3つ作成し、各IDを `src/shared/Config.luau` の `Config.GamePasses` に貼る
4. **Monetization > Developer Products** でコインパックを2つ作成し、IDを `Config.Products` に貼る
5. 変更を Rojo で同期し、再度 Publish する
6. 別アカウント（またはログアウト状態）で実際に購入テストをして、コイン付与とパス反映を確認する

> Robloxアカウントのログインは本人確認が要るため、パスワードはチャットに書かず、Studio / ブラウザの公式ログイン画面で本人が入力してください。

## 構成

```
default.project.json   Rojoのプレイス構成
src/shared/Config.luau 設定・バランス・課金ID（ここだけ触れば調整できる）
src/server/Main.server.luau      データ保存・泡回収・ポータル・ショップ検証・領収処理
src/server/WorldBuilder.luau     マップ自動生成（島・看板・ポータル・スポーン）
src/client/Main.client.luau      HUDとSHOP画面
docs/DESIGN.md         企画・バランス・今後の拡張案
```

## 今後の拡張候補（売上に効く順）

1. デイリーボーナスとプレイ時間報酬（継続率）
2. ペット（固定価格のショップ制、ランダム排出にしない）
3. 期間限定イベントゾーンと限定パス
4. ランキング看板（リバース回数・泡数のサーバー内／全体ランキング）
5. サムネイルとタイトルのA/Bテスト、英語圏向けの説明文

## ライセンス

作者: TenmaSaito（AQUARIUS）。学習・個人開発用。
