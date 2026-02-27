import SwiftUI

struct LactateLabNextView: View {
    var body: some View {
        ContentUnavailableView(
            "Next 页面已清空",
            systemImage: "arrow.right.circle",
            description: Text("该页面已重置，等待新的设计稿。")
        )
    }
}
