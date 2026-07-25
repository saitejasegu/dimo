import SwiftUI

struct EmailDetailSheet: View {
  var detail: EmailUIEmailDetail
  var onClose: () -> Void

  var body: some View {
    NavigationStack {
      ScrollView {
        EmailDetailContent(detail: detail)
          .padding(.horizontal, 20)
          .padding(.vertical, 16)
      }
      .background(Theme.canvas.ignoresSafeArea())
      .navigationTitle("Email")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Done", action: onClose)
            .font(DimoFont.body(14, weight: .semibold))
            .foregroundStyle(Theme.green)
        }
      }
    }
    .presentationDetents([.medium, .large])
    .presentationDragIndicator(.visible)
    .presentationBackground(Theme.canvas)
  }
}
