import Foundation

enum TasteMapHybridRuntimeConfiguration {
    static var current: TasteMapHybridRuntimeMode {
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--tastemap-hybrid-development") {
            return .hybridDevelopment
        }
#endif
        return .nativePrimary
    }
}
