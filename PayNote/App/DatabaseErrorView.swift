import SwiftUI

struct DatabaseErrorView: View {
    let error: Error?
    let onReset: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.orange)

            Text("error.db.title")
                .font(.title2.bold())

            Text("error.db.message")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal)

            if let error {
                Text(error.localizedDescription)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal)
            }

            Button(role: .destructive, action: onReset) {
                Text("error.db.reset")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .padding(.horizontal, 40)
        }
        .padding()
    }
}
