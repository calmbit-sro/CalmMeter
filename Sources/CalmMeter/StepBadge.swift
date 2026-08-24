import SwiftUI

/// Numbered circle that labels a step in the sign-in and welcome flows.
struct StepBadge: View {
    let number: Int

    init(_ number: Int) { self.number = number }

    var body: some View {
        Text("\(number)")
            .font(.system(size: 11, weight: .bold))
            .frame(width: 18, height: 18)
            .background(Circle().fill(Color.accentColor.opacity(0.2)))
    }
}
