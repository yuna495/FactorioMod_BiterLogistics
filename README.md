# Biter Logistics

Biter Logistics は、物流巣、バイター補給巣、運搬バイターで地上アイテム輸送を行う Factorio 2.0 mod です。

## 主な要素

- 物流巣: `Supply` または `Request` として動作する貨物コンテナ
- バイター補給巣: 運搬バイターの所属先と食料保管場所
- 運搬バイター: Supply 巣、Request 巣、補給巣の間を移動する unit
- バイター物流制御器: `Circuit Request` 用の専用 constant combinator

## 運搬バイターの野生化

運搬バイターは以下の条件でプレイヤーの管理から外れ、enemy force の野生バイターになります。

- 実ダメージを受けた場合: 即時
- 食料だけが不足して有効な配送を開始できない状態が、同じ運搬バイターで 3 回続いた場合
- 有効な目的地へ継続的に到達できない route failure が、同じ運搬バイター / 同じ目的地 / 同じ移動状態で 3 回続いた場合

飢餓と route failure は別々に数えます。どちらも 600 tick 未満の連続発生は追加カウントしません。

野生化した運搬バイターは Carrier item として返却されません。保持していた cargo は runtime-global setting `biter-logistics-feral-cargo-behavior` に従い、地面へ落とすか破棄されます。初期値は `drop` です。

生成される野生バイターは、現在の enemy evolution factor と base `biter-spawner` の出現設定を元に選ばれます。生成後は元の位置周辺へ攻撃命令を持ちます。

## 注意

`SPEC.md` が実装仕様の正です。挙動を変更する場合は、先に `SPEC.md` を更新してください。
