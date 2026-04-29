import Foundation
import SwiftData

/// 決済手段の削除処理
@MainActor
enum CardService {
    static func delete(_ card: E1card, context: ModelContext) throws {
        let cardID = card.id
        let recordDesc = FetchDescriptor<E3record>(
            predicate: #Predicate<E3record> { $0.e1card?.id == cardID }
        )
        // 履歴は消さず、決済手段だけ未選択へ戻す
        let records = (try? context.fetch(recordDesc)) ?? []

        for record in records {
            // 先に参照を外してから請求を未選択決済として再構築する
            record.e1card = nil
            RecordService.rebuildBilling(for: record, context: context)
        }

        // 参照先が消えたあとの孤児データを整理する
        RecordService.cleanupOrphanBilling(context: context)
        // まず履歴側の nullify を確定させる
        if context.hasChanges {
            try context.save()
        }

        // 履歴側の参照が確定したあとで決済手段本体を削除する
        context.delete(card)

        if context.hasChanges {
            try context.save()
        }
    }
}
