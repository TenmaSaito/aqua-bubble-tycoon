# セットアップ手順書（Windows想定・上から順にやればOK）

cloneしただけではまだゲームは動きません。**Roblox Studio にコードを取り込んで、再生 → 公開** するのが残りの作業です。
やり方は2通りあります。おすすめは **方法A（Rojo）** です。

---

## 0. 先に確認： Roblox Studio は入っているか

- 入っていない場合: https://create.roblox.com/ から Roblox Studio をダウンロードしてインストールし、**自分のRobloxアカウントでログイン**してください（これが「Robloxアカウントでログインする」工程です。パスワードはStudioの画面でだけ入力してください）。
- 入っている場合: Studioを起動してログイン済みかだけ確認してください。

---

## 方法A: Rojo で取り込む（推奨）

### A-1. Rojo を入れる
1. https://github.com/rojo-rbx/rojo/releases を開き、最新版の **Rojo-*-Windows.zip**（またはインストーラ）をダウンロードして展開する
   - 中の `rojo.exe` を、cloneした `aqua-bubble-tycoon` フォルダの中に置くと楽です
   - Studio用プラグインは、後で `rojo plugin install` でも入ります（A-3）

### A-2. Studio で空のプレイスを作る
1. Roblox Studio を起動 → **New** → **Baseplate** を選ぶ
2. この時点では何も置かなくてOK（マップはコードが自動生成します）

### A-3. Rojo を起動して接続する
1. Windowsでコマンドプロンプト（またはPowerShell）を開く
2. cloneしたフォルダへ移動する。例:
   ```
   cd C:\Users\あなたの名前\aqua-bubble-tycoon
   ```
3. プラグインを入れる（初回だけ）:
   ```
   rojo plugin install
   ```
4. 同期サーバーを起動する（このウィンドウは開いたままにする）:
   ```
   rojo serve
   ```
   `Rojo server listening` のような表示が出ればOK
5. Studioに戻り、上部メニュー **Plugins** タブ → **Rojo** ボタン → **Connect** を押す
6. 「変更を受け入れるか」の確認が出たら承認する
7. Studio左側の **Explorer** に次の3つが入っていれば成功です:
   - ReplicatedStorage > Shared > Config
   - ServerScriptService > Server > Main / WorldBuilder
   - StarterPlayer > StarterPlayerScripts > Client > Main

### A-4. データ保存を有効にする
1. Studio左上の **ファイル** → **ゲーム設定**（ホームタブにも「ゲーム設定」ボタンがある）
2. 左メニューの **セキュリティ** → **「StudioのAPIサービスへのアクセスを有効化」** を **ON**
3. **保存** を押す
   - 初回は先に「基本情報」の入力と保存を求められることがある。その場合は画面の指示どおり保存してから戻る

### A-5. 再生して確認する
1. **F5**（または Play ボタン）を押す
2. 海と島、看板、青い泡が出てくれば成功です
3. チェック項目:
   - [ ] 泡に触ると画面左上の Coins が増える
   - [ ] SHOPボタンでパネルが開き、アップグレードが買える
   - [ ] スポーン前のポータルに近づくと移動／解放の表示が出る
4. 止めるときは **Shift+F5**（Stop）

> エラーが出たら、Studio下部の **View タブ → Output** に赤文字で表示されます。その文面のスクショを むぎ に送れば直します。

---

## 方法B: Rojoなしで手コピする

1. Studioで Baseplate を開く
2. **Explorer** で以下を作る（「+」ボタンから Folder / ModuleScript / Script / LocalScript を追加し、名前を正確に付ける）:

   | 置き場所 | 種類 | 名前 | 中身に貼るファイル |
   |---|---|---|---|
   | ReplicatedStorage の中に Folder | Folder | `Shared` | ― |
   | Shared の中 | ModuleScript | `Config` | `src/shared/Config.luau` |
   | ServerScriptService の中に Folder | Folder | `Server` | ― |
   | Server の中 | Script | `Main` | `src/server/Main.server.luau` |
   | Server の中 | ModuleScript | `WorldBuilder` | `src/server/WorldBuilder.luau` |
   | StarterPlayer > StarterPlayerScripts の中に Folder | Folder | `Client` | ― |
   | Client の中 | LocalScript | `Main` | `src/client/Main.client.luau` |

3. 各ファイルの全文をコピーして、対応するスクリプトの中身を丸ごと置き換える
4. あとは A-4（API Services ON）→ A-5（再生）と同じ

---

## 公開する（誰でも遊べるようにする）

1. Studioで **File → Publish to Roblox As...** → 名前に `Aqua Bubble Tycoon` と入れて Create
2. もう一度 **File → Publish to Roblox** を押して最新を反映
3. https://create.roblox.com/ の自分のゲームページで、公開設定を **Public** にする

## 課金を有効にする（公開の後）

1. Creator Hub（create.roblox.com）でこのゲームを開く
2. **Monetization → Passes** でゲームパスを3つ作る（例: コイン2倍 199 Robux / 磁石範囲2倍 149 Robux / VIP 99 Robux）。作るとそれぞれ数字の **ID** が発行される
3. **Monetization → Developer Products** でコインパックを2つ作る（例: 1,000コイン 49 Robux / 15,000コイン 399 Robux）
4. `src/shared/Config.luau` を開き、`0` になっている場所に各IDを貼る
   - `Config.GamePasses.DoubleCoins` / `AutoCollect` / `Vip`
   - `Config.Products.CoinsSmall.Id` / `CoinsLarge.Id`
5. 方法Aなら `rojo serve` で再同期、方法Bなら Config を再コピ → Studioで再度 **Publish**
6. 別のRobloxアカウントで開いて、SHOPの課金ボタンが「ID未設定」から「Robuxで買う」に変わっているか確認する

## 詰まりやすい場所

- **Explorerが表示されていない**: View タブ → Explorer をON
- **Connectしても何も入らない**: `rojo serve` のウィンドウが閉じていないか、フォルダがclone先かを確認
- **保存の警告が出る**: A-4 の API Services が OFF のままです（ゲーム自体は動きます）
- **泡が出ない / 画面が真っ暗**: Output の赤文字エラーを確認してスクショを送ってください
