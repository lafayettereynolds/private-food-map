import SwiftUI

struct DiscoveryView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView {
                Label("发现", systemImage: "globe.asia.australia")
            } description: {
                Text("这里以后会展示基于真实数据的发现内容。当前版本不会生成虚构餐厅或推荐。")
            }
            .navigationTitle("发现")
        }
    }
}
