import CoreLocation
import AVFoundation
import Foundation
import Photos
import Testing
@testable import TasteMap

struct SettingsFoundationTests {
    @Test("Development and Production legal links resolve independently")
    func environmentSpecificLegalLinks() {
        let values = [
            ReleaseConfiguration.developmentPrivacyKey: "https://dev.example.test/privacy",
            ReleaseConfiguration.developmentTermsKey: "https://dev.example.test/terms",
            ReleaseConfiguration.developmentSupportKey: "https://dev.example.test/support",
            ReleaseConfiguration.productionPrivacyKey: "https://www.example.test/privacy",
            ReleaseConfiguration.productionTermsKey: "https://www.example.test/terms",
            ReleaseConfiguration.productionSupportKey: "https://www.example.test/support",
        ]
        let development = ReleaseConfiguration.resolve(environment: .development, values: values)
        let production = ReleaseConfiguration.resolve(environment: .production, values: values)

        #expect(development.legalLinks.privacyPolicyURL?.host == "dev.example.test")
        #expect(production.legalLinks.privacyPolicyURL?.host == "www.example.test")
        #expect(development.releaseValidationIssues.isEmpty)
        #expect(production.releaseValidationIssues.isEmpty)
    }

    @Test("Malformed and insecure legal URLs are rejected")
    func malformedLegalURLs() {
        let configuration = ReleaseConfiguration.resolve(
            environment: .production,
            values: [
                ReleaseConfiguration.productionPrivacyKey: "not a URL",
                ReleaseConfiguration.productionTermsKey: "http://example.test/terms",
            ]
        )

        #expect(configuration.legalLinks.privacyPolicyURL == nil)
        #expect(configuration.legalLinks.termsOfServiceURL == nil)
        #expect(configuration.releaseValidationIssues.contains(
            .invalidURL(key: ReleaseConfiguration.productionPrivacyKey)
        ))
        #expect(configuration.releaseValidationIssues.contains(
            .invalidURL(key: ReleaseConfiguration.productionTermsKey)
        ))
    }

    @Test("Production validation reports missing required legal links while Development can start")
    func missingLegalLinks() {
        let development = ReleaseConfiguration(environment: .development, legalLinks: .empty)
        let production = ReleaseConfiguration(environment: .production, legalLinks: .empty)

        #expect(development.releaseValidationIssues.isEmpty)
        #expect(production.releaseValidationIssues.contains(.missingPrivacyPolicy))
        #expect(production.releaseValidationIssues.contains(.missingTermsOfService))
        #expect(production.releaseValidationIssues.contains(.missingSupport))
    }

    @Test("Release availability exposes only implemented or configured settings")
    func releaseAvailability() {
        let availability = SettingsFeatureAvailability(
            releaseConfiguration: ReleaseConfiguration(environment: .production, legalLinks: .empty)
        )

        #expect(availability.isVisible(.exportBackup))
        #expect(availability.isVisible(.importData))
        #expect(!availability.isVisible(.restoreBackup))
        #expect(!availability.isVisible(.migrateLegacyWebData))
        #expect(availability.isVisible(.deleteAccount))
        #expect(!availability.isVisible(.privacyPolicy))
        #expect(!availability.isVisible(.termsOfService))
        #expect(!availability.isVisible(.support))
        #expect(!availability.isVisible(.clearCache))
        #expect(!availability.isVisible(.manageSubscription))
    }

    @Test("Development Preview keeps completed import visible while exposing future architecture")
    func developmentArchitectureAvailability() {
        let availability = SettingsFeatureAvailability(
            releaseConfiguration: ReleaseConfiguration(environment: .development, legalLinks: .empty),
            exposesFutureArchitecture: true
        )

        #expect(availability.state(for: .importData) == .implemented)
        #expect(availability.isVisible(.importData))
        #expect(availability.isVisible(.importData, includeDevelopmentOnly: true))
        #expect(availability.state(for: .deleteAccount) == .implemented)
    }

    @Test("Import and account deletion are Release features while Restore and Legacy Claim stay hidden")
    func importFlowAvailability() {
        let development = SettingsFeatureAvailability(
            releaseConfiguration: ReleaseConfiguration(environment: .development, legalLinks: .empty)
        )
        let production = SettingsFeatureAvailability(
            releaseConfiguration: ReleaseConfiguration(environment: .production, legalLinks: .empty)
        )

        #expect(development.state(for: .importData) == .implemented)
        #expect(development.isVisible(.importData))
        #expect(production.isVisible(.importData))
        #expect(!development.isVisible(.restoreBackup))
        #expect(!development.isVisible(.migrateLegacyWebData))
        #expect(development.isVisible(.deleteAccount))
        #expect(production.isVisible(.deleteAccount))
    }

    @Test("Configured legal and subscription capabilities become available without fake values")
    func configuredAvailability() {
        let configuration = ReleaseConfiguration(
            environment: .production,
            legalLinks: LegalLinks(
                privacyPolicyURL: URL(string: "https://example.test/privacy"),
                termsOfServiceURL: URL(string: "https://example.test/terms"),
                supportURL: URL(string: "https://example.test/support")
            )
        )
        let availability = SettingsFeatureAvailability(
            releaseConfiguration: configuration,
            purchaseCapabilities: [.manageSubscription]
        )

        #expect(availability.isVisible(.privacyPolicy))
        #expect(availability.isVisible(.termsOfService))
        #expect(availability.isVisible(.support))
        #expect(availability.isVisible(.manageSubscription))
    }

    @Test("Location permission maps every system state without requesting authorization")
    func locationPermissionMapping() {
        #expect(CLAuthorizationStatus.authorizedWhenInUse.settingsPermissionState == .allowed)
        #expect(CLAuthorizationStatus.authorizedAlways.settingsPermissionState == .allowed)
        #expect(CLAuthorizationStatus.denied.settingsPermissionState == .denied)
        #expect(CLAuthorizationStatus.restricted.settingsPermissionState == .restricted)
        #expect(CLAuthorizationStatus.notDetermined.settingsPermissionState == .notDetermined)
    }

    @Test("Photo add-only permission maps allowed, limited, denied, and undecided states")
    func photoPermissionMapping() {
        #expect(PHAuthorizationStatus.authorized.settingsPermissionState == .allowed)
        #expect(PHAuthorizationStatus.limited.settingsPermissionState == .limited)
        #expect(PHAuthorizationStatus.denied.settingsPermissionState == .denied)
        #expect(PHAuthorizationStatus.restricted.settingsPermissionState == .restricted)
        #expect(PHAuthorizationStatus.notDetermined.settingsPermissionState == .notDetermined)
    }

    @Test("Every decided permission can be adjusted including previously allowed permissions")
    func openSettingsAvailability() {
        #expect(SettingsPermissionState.denied.canOpenSystemSettings)
        #expect(SettingsPermissionState.restricted.canOpenSystemSettings)
        #expect(SettingsPermissionState.limited.canOpenSystemSettings)
        #expect(SettingsPermissionState.allowed.canOpenSystemSettings)
        #expect(!SettingsPermissionState.notDetermined.canOpenSystemSettings)
    }

    @Test("Camera settings share the same status semantics as the permissions bridge")
    func cameraPermissionMapping() {
        #expect(AVAuthorizationStatus.authorized.settingsPermissionState == .allowed)
        #expect(AVAuthorizationStatus.denied.settingsPermissionState == .denied)
        #expect(AVAuthorizationStatus.restricted.settingsPermissionState == .restricted)
        #expect(AVAuthorizationStatus.notDetermined.settingsPermissionState == .notDetermined)
    }

    @MainActor
    @Test("Settings shortcuts open only the requested profile fields while full edit retains all fields")
    func profileEditorDestinations() {
        #expect(ProfileEditorDestination.all.editsIdentity)
        #expect(ProfileEditorDestination.all.editsVisibility)
        #expect(ProfileEditorDestination.displayName.editsIdentity)
        #expect(!ProfileEditorDestination.displayName.editsVisibility)
        #expect(!ProfileEditorDestination.visibility.editsIdentity)
        #expect(ProfileEditorDestination.visibility.editsVisibility)
        #expect(ProfileEditorDestination.displayName.title == "修改显示名称")
        #expect(ProfileEditorDestination.visibility.title == "主页可见范围")
    }

    @Test("Storage inspection is read-only and separates original, display, and thumbnail bytes")
    func storageInspectionDoesNotDeleteBusinessPhotos() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("settings-storage-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let originals = root.appendingPathComponent(LocalPhotoFileVariant.original.rawValue)
        let displays = root.appendingPathComponent(LocalPhotoFileVariant.display.rawValue)
        let thumbnails = root.appendingPathComponent(LocalPhotoFileVariant.thumbnail.rawValue)
        try FileManager.default.createDirectory(at: originals, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: displays, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: thumbnails, withIntermediateDirectories: true)
        let original = originals.appendingPathComponent("unique-original.jpg")
        let display = displays.appendingPathComponent("display.jpg")
        let thumbnail = thumbnails.appendingPathComponent("thumbnail.jpg")
        try Data(repeating: 1, count: 101).write(to: original)
        try Data(repeating: 2, count: 52).write(to: display)
        try Data(repeating: 3, count: 17).write(to: thumbnail)

        let snapshot = try await SettingsStorageInspector(photoRootURL: root).snapshot()

        #expect(snapshot.originalPhotoBytes == 101)
        #expect(snapshot.displayPhotoBytes == 52)
        #expect(snapshot.thumbnailPhotoBytes == 17)
        #expect(snapshot.totalPhotoBytes == 170)
        #expect(FileManager.default.fileExists(atPath: original.path))
        #expect(FileManager.default.fileExists(atPath: display.path))
        #expect(FileManager.default.fileExists(atPath: thumbnail.path))
    }

    @Test("Missing photo storage reports an empty snapshot without creating or deleting files")
    func missingStorageIsEmpty() async throws {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("missing-settings-storage-\(UUID().uuidString)")
        let snapshot = try await SettingsStorageInspector(photoRootURL: missing).snapshot()
        #expect(snapshot == .empty)
        #expect(!FileManager.default.fileExists(atPath: missing.path))
    }

    @Test("App version and build are read from Bundle values")
    func appVersionInfo() {
        let info = AppVersionInfo(infoDictionary: [
            "CFBundleDisplayName": "Taste Map",
            "CFBundleShortVersionString": "1.2.3",
            "CFBundleVersion": "456",
        ])
        #expect(info.displayName == "Taste Map")
        #expect(info.version == "1.2.3")
        #expect(info.build == "456")
    }

    @Test("Missing Bundle version values degrade safely instead of hardcoding a release number")
    func missingAppVersionInfo() {
        let info = AppVersionInfo(infoDictionary: [:])
        #expect(info.displayName == "Taste Map")
        #expect(info.version == "—")
        #expect(info.build == "—")
    }
}
