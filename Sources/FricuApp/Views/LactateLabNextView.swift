import SwiftUI

struct LactateLabNextView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("乳酸实验室 · Next")
                .font(.title2.bold())

            ContentUnavailableView(
                "页面已清空",
                systemImage: "square.and.pencil",
                description: Text("该页面已重置，等待新的设计稿。")
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
