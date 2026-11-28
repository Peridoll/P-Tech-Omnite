# Development notes

## 2026-11-28 人除けの低級・高級エリア

人除けの設定画面へ低級／高級の選択を追加しました。`tier='low'`は従来どおり自然発生NPCの生成を抑止します。`tier='high'`は同じ生成抑止に加え、1秒ごとに範囲内の自然発生NPCと、そのNPCが乗る車両を除去します。どちらも通常は不可視で出入り自由です。既存の人除けでtier未保存の場合は低級として配信し、保存時に明示します。サーバーで値を検証し、既存のpayloadへ保存するためSQL追加は不要です。

削除対象はpopulation type 1～5、非mission entityに限定します。プレイヤー、スクリプト生成NPC、ミッション車両、無人車両は除外します。車両は本体も範囲内の場合のみ、全座席にプレイヤーや保護対象NPCがいないことを確認します。車と全乗員のネットワーク制御権が揃うまでは削除せず、次回に再試行します。乗員の削除を確認してから車両本体を削除します。範囲は従来と同じXY円形で、高さ制限はありません。

変更：`main/client/circles.lua`・`main/server/circles.lua`、既存のcircle client／server試験、README・本資料。`node dev/tests/run.cjs`通過。低級互換、高級の保存・配信・復元、不正値拒否、歩行者とNPC同乗車の削除、プレイヤー同乗車・設置NPC・ミッション車・無人車の除外、境界・無効化・インスタンス分離、制御権取得後の再試行、高級から低級への切替をモックで確認しました。FiveM実機・実DB・複数人での削除同期は未検証です。

## 2026-11-28 ジョブ共有スタッシュの設置

工具箱にジョブ共有スタッシュ管理を追加しました。管理者・工具箱所持者が現在地へ配置し、JOB・最低階級・名前・容量・有効状態を編集できます。スタッシュのRegisterStashはowner=false、groups={[job]=minGrade}とし、設置ID単位で全メンバーが同じ中身を共有します。複数の設置地点の中身は独立します。判定は現在のJOBで、Duty条件は設けていません。

配置は`ptech_omnite_job_stashes`に自動作成・保存します。中身の保存はox_inventoryに任せ、名前や位置の変更でも同じIDを登録し直します。最低階級・近接・インスタンス・有効状態をopenInventory／swapItemsフックでも確認し、資格変更後の継続操作を防ぎます。JOB変更時はサーバー側のプレイヤーインベントリのopen IDで対象画面だけを確認し、権限がなくなった場合に閉じます。

設定変更・削除を直列化し、その間はスタッシュ操作を拒否します。現在のアイテム重量と最大使用スロットを確認して、安全でない容量縮小を拒否します。中身がある配置の削除は拒否します。設定変更時は現在の閲覧者を閉じ、削除後・リソース停止中は登録済みスタッシュのgroupsを空にして、フック解除後も通常の開き方で再利用できないようにします。再起動時はDBのJOB設定を復元します。

変更：`main/client/job_stashes.lua`・`main/server/job_stashes.lua`、Config・manifest・工具箱メニュー、`dev/tests/job_stashes.cjs`とserver／client fixture、既存メニュー試験、package.json、README・本資料。

`node dev/tests/job_stashes.cjs`と`node dev/tests/run.cjs`通過。非管理者・工具箱なし・不正JOB・不正容量・保存失敗、同JOBの複数人で共有IDを利用できること、別JOB／階級不足／遠距離／別インスタンスの拒否、JOB変更後の画面と転送権限、疎なスロット配置を含む縮小拒否、移設・編集・再登録時の中身維持、削除済みID・停止時のアクセス拒否、再起動復元をモックで確認しました。FiveM・実DBでの複数人利用と中身の永続化は実機未検証です。

## 2026-11-27 接近時のショップ再取得

既存の一覧取得はログイン・ジョブ変更・管理操作に依存し、初回取得の失敗やログイン用インスタンスからの切替後に、自力で一覧を取り戻せない状態がありました。クライアントで接近時の再取得と15秒の定期同期、失敗時5秒の再試行を追加しました。接近リクエストの最短間隔は3秒です。ショップ一覧が空でも定期同期を継続します。

サーバーは2秒ごとにプレイヤーのrouting bucketを確認し、初回発見・変更時に対応する一覧を配信します。NPCの読み込みはショップごとの独立スレッドへ分離し、モデル待機が他のNPCの生成・消失検知を止めないようにしました。読込中の削除・状態更新・範囲外移動・ログアウト／停止はtokenで中止します。

一覧の内容が同じ場合は既存の設定オブジェクトとNPCを保持し、再取得で不要にNPCを消したり読込中のモデルを中止したりしません。生存中のNPCが非表示なら再表示します。自動同期だけは失敗通知を抑え、通常の管理操作ではエラーを通知します。`Config.ShopStreaming`に距離・同期／再試行間隔・モデル待ち時間を追加し、省略時の既定値も設けました。

変更は`main/client/shops.lua`・`main/server/shops.lua`・Config、既存ショップ試験とREADME・本資料です。`node dev/shops.cjs resources/ox_inventory`通過。初回同期失敗からの自動回復、未配信ショップの定期取得、接近による再取得、同一データ更新でのNPC維持、遅い別モデルを待つ間の生成・再生成、非表示解除、インスタンス往復時の一覧配信をモックで検証しました。FiveM実機での複数人表示は未検証です。

## 2026-11-27 ショップNPCの座標固定

新規設置・明示移設は、編集入力完了時のプレイヤー原点座標を高さ減算なしで採取し、`coordinateMode='origin'`をpayloadへ保存します。既存のmode省略データは従来の「原点から1m引いた保存座標」として扱い、描画時だけZを1m戻します。既存DB座標の一括書換えは行いません。位置を変更しない設定編集では保存位置・向き・coordinateModeを維持します。

CreatePed後にSetEntityCoordsNoOffset・SetEntityHeadingで指定位置へ明示的に合わせて固定します。監視中に位置が2cmを超えて変化、または向きが0.5度を超えて変化した場合も保存位置へ戻します。生成時の自動補正に依存せず、再生成・押されなどの後でも同じ位置へ揃えるための修正です。報告されたずれの実機上の直接原因すべてを特定したものではありません。

変更：`main/client/shops.lua`・`main/server/shops.lua`、既存ショップのclient／server／lifecycle試験、README・本資料。`node dev/shops.cjs resources/ox_inventory`は通過しました。生成時の位置補正を模擬した後の固定、後からの移動・回転の復元、旧座標と新座標の扱い、高さ補正が累積しないこと、移設時の採取、設定変更時の座標維持をモックで確認しました。FiveM実機・MLOごとの実際の立ち位置は未検証です。

## 2026-11-27 宝箱NPCと報酬スタッシュ

確定仕様：各キャラクターが各NPCから1回、再起動後も受取済みを保持。NPC専用スタッシュで配布する品目・数量を指定します。スタッシュは1人分の見本として使い、受取で消費しません。

`main/server/treasure.lua`・`main/client/treasure.lua`を追加し、Config・manifest・工具箱メニューへ接続しました。管理者はNPCの配置・移動・モデル・有効状態を編集でき、近くで専用スタッシュを開けます。openInventory／swapItemsのフックで管理者・工具箱・距離・インスタンスを再検証します。NPCはmission entityとして保護し、消失・死亡時にターゲットとともに再生成します。

新規テーブルは`ptech_omnite_treasures`（配置）と`ptech_omnite_treasure_claims`（NPC ID＋citizenidの複合主キー）です。初回受取時に報酬セットをスナップショット保存し、次に渡す品目の位置とready／giving／paid状態を記録します。キャラクターごとの処理ロックとDBの一意制約で同時受取を防ぎ、位置・報酬変更で履歴をリセットしません。

受取前にセット全体の重量・必要スロットを調べ、各品目の配布直前にも容量を確認します。DB待ちの前後でcitizenid・距離・インスタンスを確認し、sourceの再利用や移動で別人へ渡さないようにします。通常の容量不足・AddItemのfalse返却は未配布分から再試行できます。

各品目の配布前にgivingを永続化し、配布成功後に進捗を保存します。配布中の例外や進捗保存失敗で結果が不明な品目はgivingを残し、自動再配布を止めます。管理者の確認画面で、記録と実際の所持品・ログを照合したうえで渡し済み／未配布として解決できます。DBとox_inventoryの保存は別であり、プロセス強制終了時の両方への完全な原子性を保証する実装ではありません。

NPC削除時はスタッシュが空で未完了記録がないことを要求し、アイテムと進行中の報酬を保護します。削除しても受取済み履歴を残します。報酬の通常メタデータは維持し、シリアル・武器登録名・コンテナIDは新規発行させます。

`node dev/tests/treasure.cjs`・`node dev/tests/run.cjs`通過。管理権限・スタッシュ保護・距離・別インスタンス・空報酬・合計重量／スロット不足・DB待ち中の容量変化・多重クリック・別キャラクター・NPC編集後の受取済み維持・部分配布からの再開・進捗保存失敗・確認操作・配置と受取済みの再起動復元・NPC消失再生成をモックで確認しました。FiveM・実DBは実機未検証です。

## 2026-11-27 ショップNPC消失後の復旧

確認済みの不具合：`entities[id]`に削除済みpedのハンドルが残ると、再生成条件を満たせず、近距離でもNPCが戻りませんでした。NPCが消される直接の原因は実機ログがなく未確定です。

`main/client/shops.lua`で存在・死亡状態を確認し、残ったハンドルとターゲットを解除して再生成するよう修正しました。生成時にscriptHostPed・mission entity・無敵・ダメージ無効・ラグドール無効・位置固定を設定します。モデル読込後にも現在のショップ設定・ログアウト・距離を再確認し、古い配置を生成しません。

ショップごとの処理をpcallで保護し、CreatePed失敗・ターゲット設定例外でも監視ループを停止しません。部分生成されたNPCは解除して再試行し、同じ失敗のログを毎回繰り返さないようにしています。ログアウト時の片付け、後着の古い一覧応答による配置復活の防止も追加しました。遠方での片付け・接近時の生成は維持しています。

`dev/tests/shop_lifecycle_spec.lua`を追加し、`dev/shops.cjs`へ統合しました。削除・死亡後の再生成とターゲット再登録、保護設定、距離による片付け／再生成、モデル／生成／ターゲット失敗からの復旧、読込中の削除、別ショップの継続、古い一覧応答、ログアウト／再ログイン／停止時の後始末をモックで確認しました。既存ショップ試験と実ox_inventory価格登録試験も通過しています。FiveM実機は未検証です。

## 2026-11-27 管理者向け車両複製

工具箱に「乗車中の車を複製」を追加しました。サーバーで管理者・工具箱・現在の乗車車両・同一インスタンス・出現座標・距離上限を検証し、元車のモデルと種類から`CreateVehicleServerSetter`で生成します。クライアントから任意のモデルを指定して生成するAPIにはしていません。

車両プロパティをox_libで取得・適用し、実際のModKit、改造スロット0〜49、トグル17〜22、通常／ルーフリバリー（0も含む）、エクストラ0〜20を追加反映します。標準プロパティに含まれる塗装・ホイール・ネオン・車両状態も取得します。リソース固有のエンジンスワップ・handling・独自statebag・インベントリ・所有権は複製しません。

複製先は元車の近くに生成し、同じrouting bucketを設定します。別ナンバーを割り当て、稼働中車両のナンバーと衝突しないことを確認します。所有権DBは変更しません。qbx_vehiclekeysが起動していれば、完了時に実行者へ鍵を付与します。

サーバー生成からクライアントの改造反映完了までをsourceに紐付けたtokenで管理します。二重実行・連続実行を抑止し、異なるtokenでの完了／中断を拒否します。反映失敗・鍵付与例外・権限喪失・インスタンス移動・切断・未完了タイムアウト・リソース停止で、未完了の複製先を削除します。完了済み車両はこの失敗時清掃の対象に含めません。

変更箇所：`main/client/vehicle_clone.lua`・`main/server/vehicle_clone.lua`、既存Config・manifest・工具箱メニュー、`dev/tests/vehicle_clone.cjs`とサーバー／クライアントfixture、工具箱メニュー試験、package.json、README・本資料です。

`node dev/tests/vehicle_clone.cjs`と`node dev/tests/run.cjs`通過。非管理者・工具箱なし・未乗車・別インスタンス・不正座標・生成失敗・二重実行・クールダウン・token不一致・鍵付与・権限喪失・切断／停止／期限切れ清掃、改造値・キット・色・リバリー0・エクストラ・別ナンバー・制御取得失敗・改造反映失敗後の再試行をモックで確認しました。FiveM実機、実際のox_libの版ごとの差、追加車両の改造キットと他プレイヤーへの同期は実機未検証です。

参照：[ox_lib VehicleProperties](https://overextended.dev/docs/ox_lib/VehicleProperties/Client)、[Cfx CreateVehicleServerSetter](https://github.com/citizenfx/fivem/blob/master/ext/native-decls/server/CreateVehicleServerSetter.md)、[qbx_vehiclekeys GiveKeys](https://docs.qbox.re/resources/qbx_vehiclekeys/exports/server)。

## 2026-11-27 マップブリップ管理

ミニマップ常時表示はブリップごとの`minimap`チェックで選択します。未チェック・旧データの未指定は全体マップのみ、チェックありは全体マップとミニマップへ距離制限なしで表示します。入力UIの「近くにいる時だけ表示する」はこのチェックに置き換えました。DBのpayload・Config出力へ保存し、SQLスキーマ変更は不要です。

描画は`SetBlipDisplay`の4（全体マップ）／2（両方）を使い分け、`SetBlipAsShortRange`はチェックありでfalseとします。旧`shortRange`は読込互換性のため保持しますが、描画には`minimap`を優先します。[Cfx native定義](https://github.com/citizenfx/natives/blob/master/HUD/SetBlipDisplay.md)で表示IDを確認しました。チェックのON／OFF、入力・保存・Config出力、再起動復元、旧DBデータの未チェック扱いをモックで検証しました。実機未検証です。

工具箱の管理者メニューにマップブリップ管理を追加しました。現在地への配置、名前・アイコンID・色ID・倍率・ミニマップ常時表示・有効状態の編集、現在地への移設、削除、Config出力に対応します。配置位置はサーバーの実際のプレイヤー座標を採取します。

変更箇所は`main/client/map_blips.lua`・`main/server/map_blips.lua`、`main/client/placement.lua`、`config.lua`、`fxmanifest.lua`、既存の工具箱・配置テストとREADME・本資料です。既存の他モジュールの配置は変更しません。

新規テーブル`ptech_omnite_map_blips`を自動作成します。CREATE権限と従来のoxmysql・ox_lib・ox_inventory・OneSyncが必要です。管理操作はadminと工具箱所持をサーバーで再確認します。入力値・古いrevision・インスタンス・設置数を検証し、同時変更を直列化します。DBへの保存に失敗した際は表示状態を更新しません。Config由来の配置も削除記録を残し、再起動で復活しないようにします。

表示はインスタンスごとに配信します。再取得中に新しい配信を受けた場合は古い取得結果で上書きしません。状態更新・ログアウト・リソース停止時に既存のブリップを解除し、二重表示を防止します。

`node dev/tests/run.cjs`と`node dev/tests/placements.cjs`は通過しました。管理者／工具箱認証、値検証、サーバー座標の採取、上限、別インスタンス、古い編集、DB失敗、復元、削除記録、名前・アイコン・色・倍率・近距離表示のnative呼び出し、設定フォーム、Config構文、無効状態・ログアウト・停止時の非表示をモックで確認しています。FiveM・実DBは実機未検証です。

## 2026-11-27 サークルの種類分離

- 表示仕様：スターターの有効範囲は常時表示し、一度入ったプレイヤーの範囲外移動は従来の警告・連れ戻しで制限します。人除けは設定中のプレビューだけを表示し、通常の地図範囲・中心マーカー・ターゲットを生成しません。人除けはプレイヤーの出入りを制限しません。非編集中の不可視、編集中の可視、保存後のプレビュー解除をモック試験で確認しました。

- 既存サークルをスターター（`kind='starter'`）、追加の人除けを`kind='npc_repellent'`として保存・配信します。旧データのkind省略はスターターとして読み込みます。既存の設置名は保持します。
- 管理一覧に種類別の設置入口と種類表示を追加しました。人除けの設定は名前・半径・中心・低級／高級・有効状態です。スターターと人除けの相互変換は行いません。
- 人除けはクライアントの`populationPedCreating`を使用し、有効範囲内のNPC生成を`CancelEvent()`で中止します。判定は既存と同じXY円形（境界を含む、高さ制限なし）。配信状態をインスタンスごとに分離します。
- 低級は既存・侵入NPCを削除しません。高級は上記「人除けの低級・高級エリア」の条件で削除します。スクリプト生成NPCは対象外です。スターターの連れ戻し、キャラ設定、顔コード、脱出は人除けで実行しません。
- 変更ファイル：`main/client/circles.lua`、`main/server/circles.lua`、既存の`dev/tests/circle_client_spec.lua`・`circle_server_spec.lua`、README・本資料。既存テーブルのpayloadへ種類を保存するため、SQLスキーマ変更・追加依存はありません。
- `node dev/tests/run.cjs`通過。人除けのDB保存・復元・削除・管理権限・種類検証、範囲内／境界／範囲外・無効・別インスタンスの生成判定、専用設定画面、スターター機能との分離をモックで確認しました。FiveM・実DBは実機未検証です。
- API確認元：[Cfx公式 populationPedCreating](https://docs.fivem.net/docs/scripting-reference/events/list/populationPedCreating/)。自然発生NPC生成前のイベントとキャンセル対応を確認しました。

## 2026-11-26 確定仕様の本実装

今回の対象はOmniteの未実装部分です。既存のショップ・配達などの作業中の変更を維持し、Git管理操作は行っていません。

| 項目 | 現在の状態 |
|---|---|
| 椅子・ベッド、CSV入出力、テレポーター、サークル、初期キャラ設定・顔コード | 既存実装を維持。既存モック試験通過 |
| 一般ショップ、店舗別配達 | 既存実装を維持。ショップ・配達・会計・演出の既存モック試験通過 |
| ATM | prop配置・編集・削除・DB復元・Config出力を追加 |
| 依頼ボード | 一般／ジョブのゲーム内設置・移動・権限変更・個人指定・DB復元・Config出力を追加 |
| 受注型依頼 | 新規は1件1人。旧複数人受注は履歴を保持し追加受注停止。同一依頼の変更を直列化 |
| ガレージ | 工具箱への組み込み対象外。既存リソースは変更しない |

### 変更箇所・依存

Toolboxの`main/client/atms.lua`・`main/server/atms.lua`、Config・manifest・工具箱メニューを更新しました。Requestsは`main/client/boards.lua`・`main/server/boards.lua`を追加し、既存の依頼処理・共有処理・Config・manifestを更新しています。

必須依存は従来と同じqbx_core・ox_lib・ox_target・ox_inventory・oxmysql・OneSyncです。DBユーザーにはCREATE権限が必要です。新規テーブルは`ptech_omnite_atms`・`ptech_omnite_request_boards`で、自動作成します。配置の削除記録も保持し、Config由来の配置が再起動で復活することを防ぎます。DBに同じIDがある場合はDBを優先します。Config出力は現在のインスタンスが対象です。

### 試験結果

ATM管理が開かない報告に対し、入口でクライアント処理が未読込の際に無反応だった箇所を修正しました。未読込・コールバック接続失敗・画面処理例外を通知とF8の`[Omnite ATM]`ログへ表示し、DB初期化失敗時はサーバーログへ例外内容も残します。実機での発生原因はログ待ちで未確定です。入口の正常呼び出し・未読込・例外と、コールバック失敗のモック試験を追加しています。

- `node dev/tests/run.cjs`：椅子・ベッド・CSV・テレポーター・サークル・工具箱操作のモック試験通過。
- `node dev/tests/placements.cjs`：ATM／ボードの管理者・工具箱・値検証・インスタンス分離・古い編集・DB失敗・再起動復元・削除、単独受注、クライアントのprop／ターゲット同期・停止時清掃を確認。
- `node dev/shops.cjs <ox_inventoryのパス>`：既存ショップのサーバー・クライアント・価格固定の試験通過。
- Deliveryの`dev/run.cjs`・`dev/gameplay.cjs`：既存試験通過。
- 既存NUIの`dev/tests/nui_spec.cjs`：ローカルのjsdomパッケージが不完全なため起動不可。今回NUIのHTML・JavaScriptは変更していません。

Luaはluaparseの5.3構文解析とFengariのモック実行で確認しています。実MySQL接続とFiveMは実機未検証です。ATMと銀行の連携、実際の位置・向き、複数人での受注・納品、インスタンス切替・サーバー再起動は実機確認が必要です。

### 未確定・対象外

受注型の自動報酬・追加の完了確認・辞退・期限・スマホ連携は確定仕様として確認できていないため、新たな仕様を追加していません。既存の完了操作を維持しています。ガレージ管理は工具箱へ組み込みません。

以下は初期バージョンの記録です。

> This document describes the original 0.0.1 tooling. For the current 0.2.0-dev dependencies, DB placement, ownership, patient beds, and installation, see README.md. The framework-independent installation described in older versions is no longer applicable.

## Resource layout

```text
ptech_omnite_toolbox/
├── config.lua                             # Target, seating, styles, chair models, and fixed seats
├── install/
│   └── items.lua                          # ox_inventory item entry
├── main/
│   ├── client/                            # Seating and placement clients
│   ├── nui/                               # Clipboard copy panel
│   └── server/                            # Seat ownership and DB placement
├── dev/
│   ├── tests/                             # Lua syntax and server behavior checks
│   ├── README.md                          # Current installation and usage
│   └── DEVELOPMENT.md                     # Original tooling notes
├── fxmanifest.lua
└── package.json                           # Test command and development dependencies
```

## Current behavior and assumptions

- `ox_target` provides the sit interaction for registered chair models and fixed MLO seats.
- A seat is reserved on the server before the sitting scenario starts. Each seat has one owner at a time.
- The server checks that a player is near the requested seat. It releases the reservation when the player stands up or disconnects.
- The stand key defaults to `X`. The style key defaults to `G` and cycles through the configured styles while seated.
- Sitting blocks movement and attacks while leaving camera, voice, phone, and inventory controls available.
- Style scenarios can have independent position and heading offsets. Chair models and fixed seats can restrict which style IDs they support.
- Fixed seat IDs must be unique. A model seat is keyed by its model hash and world coordinates.

## Values needed from the target server

1. **MLO seats:** add coordinate entries to `Config.FixedSeats` for chairs that are not exposed as separate objects.
2. **Custom chair props:** add model names and tune their offsets in `Config.ChairModels`.
3. **Seat alignment:** check the sitting position, facing direction, and exit movement for each target model, MLO, and style.
4. **Style fit:** remove styles that do not fit a particular chair by setting its `styles` list.
5. **Resource order:** start `ox_target` before `ptech_omnite_toolbox`.

These values can remain provisional while the resource structure and interaction flow are organized.

## Coordinate recorder

The ID is a unique label for the fixed seat, such as `pillbox_waiting_01`. It is used in configuration and lock state; it is not an object/model ID. Both commands accept an optional ID. If omitted, the resource generates an ID such as `seat_123456`; rename it to a location-based name when convenient.

The quick recorder captures the current player position and heading as one `Config.FixedSeats` entry. The result opens a copy panel. Click **コピー** to put the line on the clipboard, then paste it into `Config.FixedSeats`. If clipboard access is blocked, the line remains selectable in the panel.

1. Set `Config.SeatRecorder.enabled = true` in the resource-root `config.lua` and restart the resource.
2. Add these ACE permissions for administrators in `server.cfg`:

   ```cfg
   add_ace group.admin command.omnite_seatrecord allow
   add_ace group.admin command.omnite_seatsetup allow
   add_ace group.admin command.omnite_seatdebug allow
   add_ace group.admin command.omnite_seatghost allow
   ```

3. Stand at the desired position and face the direction players should face. Run `/omnite_seatrecord [id]`; omit the ID to generate one automatically.
4. Copy the generated line from the panel into `Config.FixedSeats`.

## Interactive seat setup

Run `/omnite_seatsetup [id]` while standing at the approximate seat location and facing the desired direction. The current style starts playing as a preview. The ID can be omitted and renamed in the generated line later.

| Input | Adjustment |
| --- | --- |
| Arrow keys | Move forward/back/left/right |
| `E` / `Q` | Raise/lower the seat point |
| `C` / `Z` | Turn the facing direction |
| `G` | Preview the next sitting style |
| `Shift` + adjustment key | Use the coarser step size |
| `Enter` | Open the generated fixed-seat line for clipboard copy |
| `Esc` | Cancel setup |

Movement uses `Config.SeatRecorder.fineStep`; holding Shift uses `coarseStep`. Rotation uses `headingStep`. When setup completes, copy the generated line into `Config.FixedSeats`. Seat setup is disabled by default and ACE-restricted when enabled.

## Seat debug mode

Run `/omnite_seatdebug` to toggle the ACE-restricted marker view. It displays configured chair-model objects and fixed MLO seats within `Config.SeatDebug.markerDistance`. Labels show a model name or fixed-seat ID and whether the seat lock is occupied.

Run `/omnite_seatghost` to toggle the separate ACE-restricted object pass-through mode. It temporarily disables collision with nearby object entities, including unregistered chair props, so an administrator can move through them while recording or adjusting a seat. Nearby decorative props are also pass-through while this mode is on. Run the command again to turn it off. The mode is disabled by default and cannot be toggled while sitting or adjusting a seat.

## Deferred implementation

- Verify the registered GTA chair models and their default offsets in the live server.
- Confirm the three default sitting scenarios, style offsets, and key bindings in-game.
- Add confirmed MLO seat coordinates and adjust model-specific offsets after in-game checks.
- Run multi-player checks for seat contention, disconnect cleanup, and standing up.
