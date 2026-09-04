import Foundation

enum TasteMapHybridRuntimeConfiguration {
    static var current: TasteMapHybridRuntimeMode {
#if DEBUG && TASTEMAP_QA
        return .hybridDevelopment
#elseif DEBUG
        if ProcessInfo.processInfo.arguments.contains("--tastemap-hybrid-development") {
            return .hybridDevelopment
        }
        return .nativePrimary
#else
        return .nativePrimary
#endif
    }
}
