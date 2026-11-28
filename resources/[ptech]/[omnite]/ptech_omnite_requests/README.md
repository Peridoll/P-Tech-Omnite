# P-Tech Omnite Requests

Configurable request and delivery boards for FiveM roleplay servers using Qbox.

## Install

1. Copy `ptech_omnite_requests` into the server's resources directory.
2. Configure board locations, permissions, form fields, delivery items, and rewards in `config/config.lua`.
3. Add `ensure ptech_omnite_requests` after `qbx_core`, `ox_lib`, `ox_target`, `oxmysql`, and `ox_inventory` in `server.cfg`.

## Current features

- General and job boards with separate view, post, accept, deliver, and manage permissions.
- Accepted missions with one assignee per request and individual acceptance records.
- Delivery missions with a maximum total quantity and payment per delivered item.
- Server-side permission, distance, inventory, and quantity validation.
- MySQL persistence for missions and individual acceptance records.

Board coordinates, access rules, inventory item names, and payment values must be configured for the target server.

## ゲーム内のボード設置・権限変更

工具箱の「依頼ボード管理」から現在地に一般／ジョブボードを登録します。管理者権限（`omnite.seating.admin`、`admin`、`god`のいずれか）と工具箱の所持が必要です。一般利用者は工具箱不要でox_targetから開きます。

閲覧・投稿・受注・納品・依頼管理について、誰でも許可、JOBごとの最低階級、個別の市民IDを設定できます。JOBは`ambulance:0,police:2`、市民IDはカンマ区切りで入力します。すべての許可を空にすると、その操作は誰にも許可しません。JOBと市民IDはどちらかに一致すれば許可します。設置後もボードの近くで名前・位置・権限を編集できます。Configに書いたgang制限と勤務必須条件は編集時も保持します。

設置は`ptech_omnite_request_boards`に保存し、再起動なしで反映します。インスタンスごとにターゲットを分離し、サーバーでも距離・インスタンス・操作権限を確認します。削除時は配置だけを無効にし、投稿・受注履歴は保持します。Config由来の配置を削除した場合も再起動で復活しません。

「Config形式で出力」は現在のインスタンスのボードを`Config.Boards`用のLuaテーブルとしてコピーします。納品品目は`Config.DefaultDeliveryItems`を新規設置時に使用します。既存ボードの`deliveryItems`・`fields`・支払方法などは編集時も維持します。納品品目・フォーム・通貨の詳細設定はConfigで行います。DBに同じIDがある場合はDBの内容を優先します。

## 受注型・納品型

新規受注型は1依頼につき1人です。複数枠を送信してもサーバーで1に固定します。旧版で複数人が受注済みの依頼は、その記録を保持して追加受注を停止します。納品型は依頼ごとの上限まで納品し、数量に応じて報酬を支給します。同じ依頼の受注・完了・納品・取消はサーバーで直列処理します。

受注型の自動報酬、完了確認の追加フロー、辞退、期限、スマホ連携は確定仕様として確認できていないため追加していません。従来の完了操作は維持しています。

## 検証

`ptech_omnite_toolbox/dev/tests/placements.cjs`で、設置・権限・個人指定・古い編集・DB失敗・インスタンス分離・再起動復元・削除・Config構文・1人受注・ターゲット同期をモックで検証しています。実MySQL・FiveMは実機未検証です。
