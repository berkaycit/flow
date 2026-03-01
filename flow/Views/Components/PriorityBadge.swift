import SwiftUI

struct PriorityBadge: View {
    let priority: Priority

    var body: some View {
        RoundedRectangle(cornerRadius: 1.5)
            .fill(priority.color.opacity(0.85))
            .frame(width: 3, height: 40)
    }
}
