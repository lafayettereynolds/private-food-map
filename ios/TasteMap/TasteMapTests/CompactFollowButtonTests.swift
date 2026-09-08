import SwiftUI
import Testing
import UIKit
@testable import TasteMap

@Suite("Compact follow action")
struct CompactFollowButtonTests {
    @MainActor
    @Test("Ready and pending actions retain compact centered geometry and a 44pt target")
    func layoutKeepsItsTargetAndPendingWidth() {
        for scheme in [ColorScheme.light, .dark] {
            var sizes: [CGSize] = []
            for pending in [false, true] {
                let host = UIHostingController(rootView:
                    TasteMapCompactFollowButton(userName: "测试用户", isPending: pending, action: {})
                        .environment(\.colorScheme, scheme)
                        .environment(\.dynamicTypeSize, .large)
                )
                let size = host.sizeThatFits(in: CGSize(width: 320, height: 100))
                #expect(abs(size.width - 64) < 1)
                #expect(size.height >= 44)
                sizes.append(size)
            }
            #expect(sizes[0] == sizes[1])
        }
    }

    @MainActor
    @Test("Accessibility type grows naturally rather than truncating the title")
    func largeTypeRemainsReadable() {
        let host = UIHostingController(rootView:
            TasteMapCompactFollowButton(userName: "很长的显示名称", isPending: false, action: {})
                .environment(\.dynamicTypeSize, .accessibility3)
        )
        let size = host.sizeThatFits(in: CGSize(width: 320, height: 200))
        #expect(size.width > TasteMapDesignTokens.FollowAction.minimumWidth)
        #expect(size.height >= TasteMapDesignTokens.Control.minimumHitTarget)
    }
}
