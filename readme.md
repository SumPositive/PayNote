# PayNote / クレメモ 開発メモ

この `readme.md` は利用者向けではなく、開発者向けの設計メモです。

## アプリ前提

- 対象は、**後日口座から引き落とされる決済**です。
- 即時に残高や現金が動く決済は対象外です。
- 旧アプリからの migration を正式対応とし、**現行 SwiftData ストアからの自動移行は前提にしません**。

## データ構造の考え方

### 正本

- `E3record`
  - ユーザーが入力する決済明細の正本です。
  - 利用日、金額、決済手段、決済ラベル、タグなどを持ちます。

### 派生

- `E6part`
  - `E3record` から派生する支払パーツです。
  - 旧データ互換のためモデルは残しています。
- `E2invoice`
  - カード単位の請求です。
  - 実質的には `日付 + カード + 状態` 単位です。
- `E7payment`
  - 口座引き落とし単位の集計です。
  - 実質的には `日付 + 口座 + 状態` 単位です。

### 状態表現

- `paid / unpaid` は保存 `Bool` ではなく、**所属リレーション**で表します。
- `E2invoice`
  - `e1paid != nil` なら済み
  - `e1unpaid != nil` なら未払
- `E7payment`
  - `e8paid != nil` なら済み
  - `e8unpaid != nil` なら未払
- `isPaid` は UI や集計用の **計算プロパティ** として扱います。

### 親モデル

- `E1card`
  - `e2paids / e2unpaids` を持ちます。
- `E8bank`
  - `e7paids / e7unpaids` を持ちます。

## この構造の狙い

- 旧アプリの `paid / unpaid` 付け替え方式を維持する
- 未払一覧 / 済み一覧を高速に引けるようにする
- `引き落とし状況` 画面で必要な単位である `日付 + 口座` に `E7payment` を合わせる
- 画面側の仮想グルーピングや補正を減らす

## 留意点

- `E3record` を編集して `E1card.e8bank` が変わると、既存の `E2invoice / E7payment` の再配置が必要です。
- `E7payment` は日付だけで一意ではありません。必ず **口座** と **状態** を含めて扱う必要があります。
- `E2invoice` も `日付 + カード + 状態` を前提に扱います。
- `sumAmount` や `sumNoCheck` は派生集計値です。正本ではありません。
- 画面表示の都合で永続モデルを増やさず、まず永続モデルの責務を明確に保ちます。

## トランザクション方針

SwiftData には DB トリガやストアドプロシージャーはないため、更新責務は `RecordService` に集約します。

### 基本原則

- 1 回のユーザー操作 = 1 回のサービス呼び出し = 1 回の `context.save()`
- View から `E2invoice` や `E7payment` を直接更新しない
- 派生データの再構築や所属移動は、必ずサービス層でまとめて行う
- 途中で `context.save()` しない

### 主な処理単位

- `save(record)`
  - `E3record` の保存
  - `E6part` の再構築
  - `E2invoice / E7payment` の再配置
  - 集計値更新
  - 最後に `context.save()`
- `delete(record)`
  - `E3record` の削除
  - 関連 `E6part` の削除
  - 空になった `E2invoice / E7payment` の掃除
  - 集計値更新
  - 最後に `context.save()`
- `move invoice / payment paid state`
  - `paid / unpaid` 所属の付け替え
  - 必要に応じた繰り返し明細の生成
  - 集計値更新
  - 最後に `context.save()`

### 実装上の注意

- `willSave` / `didSave` に業務ロジックを分散させない
- 派生値はサービス層で明示的に再計算する
- 旧データ互換のためモデルに残っている要素と、新規運用で使う要素を混同しない

## migration 方針

- 対応対象は **旧アプリ Core Data** のみです。
- 旧 `payment` はそのまま移さず、**旧 invoice から `日付 + 口座 + 状態` の `E7payment` を再構成**します。
- 現行 SwiftData ストアの自動移行は前提にしません。

## 開発環境

- Swift 6
- SwiftUI
- SwiftData
- iOS 18 以降
