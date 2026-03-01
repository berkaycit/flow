import SwiftUI

struct PriorityBadge: View {
    let priority: Priority

    var body: some View {
        Circle()
            .fill(priority.color)
            .frame(width: 10, height: 10)
    }
}
