import SwiftUI

struct LactateLabView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("乳酸实验室")
                .font(.title2.bold())

            ContentUnavailableView(
                "页面已清空",
                systemImage: "paintbrush.pointed",
                description: Text("乳酸实验室代码已重置，可从这里重新设计 UI。")
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding()
    }
}
