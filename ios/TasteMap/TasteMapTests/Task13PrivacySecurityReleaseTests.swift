import Foundation
import Testing
@testable import TasteMap

@Suite("Task 13 Privacy, Security, and Release Configuration")
struct Task13PrivacySecurityReleaseTests {
    @Test("Main privacy manifest declares current data flows and required API reasons")
    func mainPrivacyManifest() throws {
        let manifest = try propertyList(at: repositoryRoot
            .appending(path: "ios/TasteMap/TasteMap/PrivacyInfo.xcprivacy"))

        #expect(manifest["NSPrivacyTracking"] as? Bool == false)
        #expect((manifest["NSPrivacyTrackingDomains"] as? [Any])?.isEmpty == true)
        let collected = try #require(manifest["NSPrivacyCollectedDataTypes"] as? [[String: Any]])
        let collectedTypes = Set(collected.compactMap { $0["NSPrivacyCollectedDataType"] as? String })
        #expect(collectedTypes == [
            "NSPrivacyCollectedDataTypeName",
            "NSPrivacyCollectedDataTypeEmailAddress",
            "NSPrivacyCollectedDataTypeUserID",
            "NSPrivacyCollectedDataTypePurchaseHistory",
            "NSPrivacyCollectedDataTypePhotosorVideos",
            "NSPrivacyCollectedDataTypeOtherUserContent",
            "NSPrivacyCollectedDataTypePreciseLocation",
            "NSPrivacyCollectedDataTypeCoarseLocation",
            "NSPrivacyCollectedDataTypeContacts",
            "NSPrivacyCollectedDataTypeProductInteraction",
        ])
        #expect(collected.allSatisfy { $0["NSPrivacyCollectedDataTypeLinked"] as? Bool == true })
        #expect(collected.allSatisfy { $0["NSPrivacyCollectedDataTypeTracking"] as? Bool == false })

        let accessed = try #require(manifest["NSPrivacyAccessedAPITypes"] as? [[String: Any]])
        #expect(accessed.count == 2)
        let reasons = Dictionary(uniqueKeysWithValues: accessed.compactMap { item -> (String, [String])? in
            guard let type = item["NSPrivacyAccessedAPIType"] as? String,
                  let reasons = item["NSPrivacyAccessedAPITypeReasons"] as? [String] else { return nil }
            return (type, reasons)
        })
        #expect(reasons == [
            "NSPrivacyAccessedAPICategoryFileTimestamp": ["C617.1"],
            "NSPrivacyAccessedAPICategoryUserDefaults": ["CA92.1"],
        ])
        for entry in collected {
            let type = try #require(entry["NSPrivacyCollectedDataType"] as? String)
            let purposes = try #require(entry["NSPrivacyCollectedDataTypePurposes"] as? [String])
            let personalized = !["NSPrivacyCollectedDataTypeName", "NSPrivacyCollectedDataTypeEmailAddress",
                                 "NSPrivacyCollectedDataTypePhotosorVideos"].contains(type)
            #expect(Set(purposes) == Set(["NSPrivacyCollectedDataTypePurposeAppFunctionality"]
                + (personalized ? ["NSPrivacyCollectedDataTypePurposeProductPersonalization"] : [])))
        }
    }

    @Test("Share extension privacy manifest is explicit and has no undeclared collection")
    func shareExtensionPrivacyManifest() throws {
        let manifest = try propertyList(at: repositoryRoot
            .appending(path: "ios/TasteMap/TasteMapShareExtension/PrivacyInfo.xcprivacy"))
        #expect(manifest["NSPrivacyTracking"] as? Bool == false)
        #expect((manifest["NSPrivacyTrackingDomains"] as? [Any])?.isEmpty == true)
        #expect((manifest["NSPrivacyCollectedDataTypes"] as? [Any])?.isEmpty == true)
        #expect((manifest["NSPrivacyAccessedAPITypes"] as? [Any])?.isEmpty == true)
    }

    @Test("Production legal configuration fails closed without real URLs")
    func productionLegalConfigurationFailsClosed() {
        let missing = ReleaseConfiguration.resolve(environment: .production, values: [:])
        #expect(missing.legalLinks == .empty)
        #expect(missing.releaseValidationIssues.count == 3)
        #expect(missing.releaseValidationIssues.contains(.missingPrivacyPolicy))
        #expect(missing.releaseValidationIssues.contains(.missingTermsOfService))
        #expect(missing.releaseValidationIssues.contains(.missingSupport))

        let malformed = ReleaseConfiguration.resolve(environment: .production, values: [
            ReleaseConfiguration.productionPrivacyKey: "http://example.invalid/privacy",
            ReleaseConfiguration.productionTermsKey: "not a URL",
            ReleaseConfiguration.productionSupportKey: "https://user:password@example.invalid/help",
        ])
        #expect(malformed.legalLinks == .empty)
        #expect(malformed.releaseValidationIssues.contains(
            .invalidURL(key: ReleaseConfiguration.productionPrivacyKey)
        ))
        #expect(malformed.releaseValidationIssues.contains(
            .invalidURL(key: ReleaseConfiguration.productionTermsKey)
        ))
        #expect(malformed.releaseValidationIssues.contains(
            .invalidURL(key: ReleaseConfiguration.productionSupportKey)
        ))
    }

    @Test("Permission descriptions match only the capabilities the app actually requests")
    func permissionDescriptions() throws {
        let project = try String(contentsOf: repositoryRoot
            .appending(path: "ios/TasteMap/TasteMap.xcodeproj/project.pbxproj"), encoding: .utf8)
        #expect(project.contains("INFOPLIST_KEY_NSLocationWhenInUseUsageDescription"))
        #expect(project.contains("show nearby restaurants and your position on the map"))
        #expect(project.contains("INFOPLIST_KEY_NSPhotoLibraryAddUsageDescription"))
        #expect(project.contains("adds the dining analysis and memory posters you choose to save"))
        #expect(project.contains("INFOPLIST_KEY_NSCameraUsageDescription"))
        #expect(project.contains("only when you choose to photograph a dining visit or dish"))
        #expect(!project.contains("INFOPLIST_KEY_NSPhotoLibraryUsageDescription"))
        #expect(!project.contains("INFOPLIST_KEY_NSMicrophoneUsageDescription"))
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // TasteMapTests
            .deletingLastPathComponent() // ios/TasteMap
            .deletingLastPathComponent() // ios
            .deletingLastPathComponent() // repository root
    }

    private func propertyList(at url: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: url)
        return try #require(
            PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        )
    }
}
