import SwiftUI
import SwiftData

enum RecordEditMode {
    case addNew
    case edit(E3record)
}

struct RecordEditView: View {
    let mode: RecordEditMode

    var body: some View {
        Text("record.edit.stub")
            .navigationTitle(
                mode == .addNew
                    ? LocalizedStringKey("record.edit.title.add")
                    : LocalizedStringKey("record.edit.title.edit")
            )
            .navigationBarTitleDisplayMode(.inline)
    }
}

extension RecordEditMode: Equatable {
    static func == (lhs: RecordEditMode, rhs: RecordEditMode) -> Bool {
        switch (lhs, rhs) {
        case (.addNew, .addNew): true
        case (.edit(let a), .edit(let b)): a.id == b.id
        default: false
        }
    }
}
