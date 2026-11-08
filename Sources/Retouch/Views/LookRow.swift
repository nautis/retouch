import RetouchCore
import SwiftUI

/// A RAW look with its one-line description, for the Camera Raw picker.
struct LookRow: View {
    let look: RawLook

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(look.title)
            Text(look.blurb)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}
