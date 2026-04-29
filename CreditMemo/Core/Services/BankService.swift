import Foundation
import SwiftData

/// 引き落とし口座の削除処理
@MainActor
enum BankService {
    static func delete(_ bank: E8bank, context: ModelContext) throws {
        let cards = Array(bank.e1cards)
        var touchedRecords: [E3record] = []

        for card in cards {
            // 先に口座参照を外す
            card.e8bank = nil
            touchedRecords.append(contentsOf: card.e3records)
        }

        // 口座参照が外れた状態で請求を組み直し、口座未選択の payment へ寄せる
        for record in touchedRecords {
            RecordService.rebuildBilling(for: record, context: context)
        }

        // 古い payment や孤児データを整理する
        RecordService.cleanupOrphanBilling(context: context)

        // 最後に口座本体を削除する
        context.delete(bank)

        if context.hasChanges {
            try context.save()
        }
    }
}
