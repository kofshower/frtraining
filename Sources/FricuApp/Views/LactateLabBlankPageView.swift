import SwiftUI

struct LactateLabBlankPageView: View {
    var body: some View {
        ContentUnavailableView(
            "空白页",
            systemImage: "square.dashed",
            description: Text("用于后续 UI 重建。")
        )
    }
}
