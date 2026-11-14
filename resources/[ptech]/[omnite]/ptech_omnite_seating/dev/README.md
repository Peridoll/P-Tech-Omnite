# P-Tech Omnite Seating 0.2.0-dev

既存MLOの椅子・ベッドに利用位置を登録するリソースです。家具そのものは生成・移動しません。

## 導入

1. OneSyncを有効にし、`ox_lib`、`ox_target`、`oxmysql`、`ox_inventory`、`qbx_core`を先に起動します。
2. リソース直下の`install/items.lua`の項目を`ox_inventory/data/items.lua`のreturnテーブルへ追加します。ファイル自体を置き換えないでください。
3. `server.cfg`に`ensure ptech_omnite_seating`を追加します。初回起動時に`ptech_omnite_seating`テーブルを作成するため、DBユーザーにCREATE権限が必要です。
4. 管理者に`add_ace group.admin omnite.seating.admin allow`を設定します。
5. 管理者またはサーバーコンソールから`omnite_seatgive <プレイヤーID>`でツールを1個配布します。ショップ・クラフト・通常ドロップには登録しません。

アイテムは消費せず、登録・編集・削除時にサーバーで所持を再確認します。他の管理リソースからアイテムを生成できる権限は、その管理リソース側で管理してください。

## 配置と利用

ツールを使用、または所持した状態で`/omnite_seating`を実行します。MLO管理名・席名・種類を入力し、視点先をEで選びます。名前は半角英数字・`_`・`-`を使用し、席名は省略すると自動生成します。

半透明の自分の姿勢を見ながら調整します。

| 操作 | キー |
| --- | --- |
| 前後・左右 | 矢印 |
| 上下 | E / Q |
| 向き | Z / C |
| 椅子の姿勢 | G |
| 粗調整 | Shiftを押しながら |
| DBへ確定保存 | Enter |
| 中止 | Esc |

DB保存成功後に接続中プレイヤーへ反映し、再起動後も復元します。失敗時は有効化せず、調整画面を維持します。登録地点はプレイヤーから8m以内です。

登録済みの椅子はox_targetから座り、ベッドは「横になる」で利用します。Xで解除、椅子はGで姿勢変更できます。1席1人で、同じ位置を別IDで登録しても重なって利用できません。移動・攻撃を制限し、スマホ・インベントリ用の入力は開放しますが、各リソースとの併用は実機確認が必要です。

メニューから近くの自分の席を編集・削除できます。管理者は他の所有者の席も操作できます。患者用ベッドの編集・削除にもEMS条件を適用します。使用中の席は変更できません。

## ベッドとMediora

- 椅子・通常ベッドの登録はツール所持者が利用できます。
- 患者用ベッドの登録は、ツールを持ち、`ptech_mediora_medical`が起動しているEMSだけが利用できます。
- JOB名は`Config.Placement.emsJobs`で指定します。グレード・出勤状態は条件に含めません。
- EMSは患者用ベッドのターゲットから、近くの患者IDを選んで移動を要求できます。EMS・患者・ベッドの距離、同一インスタンス、空席状態をサーバーで確認します。
- 死亡・ラグドール・拘束など、通常の着席を開始できない状態は移動を断り、占有を解除します。蘇生やMediora/Wasabiの死亡状態は変更しません。意識不明患者への適用は、それらの状態管理と連携する追加調整・実機確認が必要です。

Medioraサーバーコードから利用できる連携口もあります。

```lua
local beds = exports.ptech_omnite_seating:GetPatientBeds()
local result = exports.ptech_omnite_seating:PlacePatientInBed(emsSource, patientSource, bedId)
-- result.ok / result.message
```

`PlacePatientInBed`は`Config.Placement.medicalResource`からの呼び出しだけを受け付けます。ベッド一覧が変わったらサーバーのローカルイベント`ptech_omnite_seating:server:patientBedsChanged`を通知します。Mediora既存ファイルはこの更新では変更しません。

## MLO単位のConfig出力

管理者メニューからMLO管理名を指定してConfig形式をクリップボードへ出力できます。空欄は全件です。DBの内容を自動削除したり、設定ファイルを自動上書きしたりはしません。

出力は`Config.FixedSeats`用です。既存設定がある場合は必要な行を追加してください。移行時はDBをバックアップしたうえで対象DB席を整理し、同じ席をDBとConfigへ二重登録しないでください。Configはリソース再起動時に読み込みます。

## 管理用の従来コマンド

`/omnite_seatdebug`は近くの登録席を表示し、`/omnite_seatghost`は近くのオブジェクトを貫通します。どちらもサーバーACE制限付きです。新配置モード中は選択対象だけを一時的に貫通します。全オブジェクトの走査は管理用デバッグ・貫通モード中だけ動作します。

```cfg
add_ace group.admin command.omnite_seatdebug allow
add_ace group.admin command.omnite_seatghost allow
```

旧`omnite_seatrecord`・`omnite_seatsetup`は`Config.SeatRecorder.enabled`がtrueの場合だけ有効で、それぞれの`command.<名前>` ACEが必要です。DB保存を使う場合は新ツールを使ってください。

## 検証

リソース直下（`package.json`のある場所）で`npm install --ignore-scripts`後、`npm test`で`dev/tests/run.cjs`を実行し、Lua構文と、疑似サーバー上のDB失敗・所有権・EMS・距離・座席競合・再起動復元を確認できます。検証用依存ライブラリはFiveM実行時には不要です。

今回の自動確認は通過しています。実MySQL・FiveM・MLO上の位置、NUI、ベッド姿勢、他のアニメーションとの干渉は未検証です。ゲーム内で配置→2人同時着席→編集→再起動→復元→Config出力の順に確認してください。
