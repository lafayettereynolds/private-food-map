import CoreLocation
import Foundation
import Photos

nonisolated enum SettingsPermissionState: String, Equatable, Sendable {
    case allowed
    case limited
    case denied
    case restricted
    case notDetermined

    var title: String {
        switch self {
        case .allowed: "已允许"
        case .limited: "有限访问"
        case .denied: "已拒绝"
        case .restricted: "受系统限制"
        case .notDetermined: "尚未请求"
        }
    }

    var canOpenSystemSettings: Bool {
        self == .denied || self == .restricted || self == .limited
    }
}

nonisolated struct SettingsPermissionSnapshot: Equatable, Sendable {
    let location: SettingsPermissionState
    let photoAddOnly: SettingsPermissionState

    @MainActor
    static func live(locationStatus: CLAuthorizationStatus) -> SettingsPermissionSnapshot {
        SettingsPermissionSnapshot(
            location: locationStatus.settingsPermissionState,
            photoAddOnly: PHPhotoLibrary.authorizationStatus(for: .addOnly).settingsPermissionState
        )
    }
}

nonisolated extension CLAuthorizationStatus {
    var settingsPermissionState: SettingsPermissionState {
        switch self {
        case .authorizedAlways, .authorizedWhenInUse: .allowed
        case .denied: .denied
        case .restricted: .restricted
        case .notDetermined: .notDetermined
        @unknown default: .restricted
        }
    }
}

nonisolated extension PHAuthorizationStatus {
    var settingsPermissionState: SettingsPermissionState {
        switch self {
        case .authorized: .allowed
        case .limited: .limited
        case .denied: .denied
        case .restricted: .restricted
        case .notDetermined: .notDetermined
        @unknown default: .restricted
        }
    }
}
