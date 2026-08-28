//
//  TasteMapUITests.swift
//  TasteMapUITests
//
//  Created by Lafayette on 2026/8/27.
//

import XCTest

final class TasteMapUITests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
        XCUIDevice.shared.orientation = .portrait
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    @MainActor
    func testMapHomeLaunchesWithoutBlockingOnLocation() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.buttons["地图"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["发现"].exists)
        XCTAssertTrue(app.buttons["我的"].exists)
        XCTAssertTrue(app.buttons["添加餐厅"].exists)
        XCTAssertTrue(app.segmentedControls.buttons["去过"].exists)
        XCTAssertTrue(app.segmentedControls.buttons["想吃"].exists)

        app.buttons["添加餐厅"].tap()
        XCTAssertTrue(app.navigationBars["搜索餐厅"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.searchFields["餐厅名称或地址"].exists)
    }

    @MainActor
    func testBottomNavigationSwitchesBetweenThreeMainTabs() throws {
        let app = XCUIApplication()
        app.launch()

        app.buttons["发现"].tap()
        XCTAssertTrue(app.navigationBars["发现"].waitForExistence(timeout: 5))

        app.buttons["我的"].tap()
        XCTAssertTrue(app.navigationBars["我的"].waitForExistence(timeout: 5))

        app.buttons["地图"].tap()
        XCTAssertTrue(app.segmentedControls.buttons["去过"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testP3AProfileEditAndRestartPersistence() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-p1d-persistent-offline-fixture",
            "-p1d-reset-persistent-offline-fixture",
        ]
        app.launchEnvironment = [
            "TASTEMAP_P1D_UI_TEST": "1",
            "TASTEMAP_P1D_RESET": "1",
            "TASTEMAP_P3A_PROFILE_UI_TEST": "1",
        ]
        app.launch()

        app.buttons["我的"].tap()
        XCTAssertTrue(app.navigationBars["我的"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["P3-A 初始用户"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["profile-edit-button"].exists)
        app.buttons["profile-edit-button"].tap()
        XCTAssertTrue(app.navigationBars["编辑资料"].waitForExistence(timeout: 5))

        let name = app.textFields["profile-display-name"]
        name.tap()
        name.clearAndType("离线美食家 🍜")
        let city = app.textFields["profile-city"]
        city.tap()
        city.clearAndType("上海")
        let bio = app.textFields["profile-bio"]
        bio.tap()
        bio.clearAndType("每一顿都值得认真记录")
        let otter = app.buttons["profile-avatar-preset-otter"]
        scrollUntilVisible(otter, in: app)
        otter.tap()
        app.buttons["profile-save-button"].tap()

        XCTAssertTrue(app.staticTexts["离线美食家 🍜"].waitForExistence(timeout: 5))
        let savedBio = app.staticTexts["profile-bio-text"]
        XCTAssertTrue(savedBio.waitForExistence(timeout: 5))
        XCTAssertEqual(savedBio.label, "每一顿都值得认真记录")
        XCTAssertEqual(app.staticTexts["profile-city-text"].label, "上海")

        app.terminate()
        app.launchArguments = ["-p1d-persistent-offline-fixture"]
        app.launchEnvironment = [
            "TASTEMAP_P1D_UI_TEST": "1",
            "TASTEMAP_P3A_PROFILE_UI_TEST": "1",
        ]
        app.launch()
        app.buttons["我的"].tap()
        XCTAssertTrue(app.staticTexts["离线美食家 🍜"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["profile-bio-text"].label, "每一顿都值得认真记录")
        XCTAssertEqual(app.staticTexts["profile-city-text"].label, "上海")
        XCTAssertTrue(app.buttons["profile-edit-button"].exists)
    }

    @MainActor
    func testP3BSocialEntryOpensNativeSearchWithoutExposingPrivateIdentityFields() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-p1d-persistent-offline-fixture",
            "-p1d-reset-persistent-offline-fixture",
        ]
        app.launchEnvironment = [
            "TASTEMAP_P1D_UI_TEST": "1",
            "TASTEMAP_P1D_RESET": "1",
            "TASTEMAP_P3A_PROFILE_UI_TEST": "1",
        ]
        app.launch()

        app.buttons["我的"].tap()
        let entry = app.buttons["profile-social-entry"]
        XCTAssertTrue(entry.waitForExistence(timeout: 5))
        entry.tap()
        XCTAssertTrue(app.navigationBars["好友与关注"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.segmentedControls.buttons["找人"].exists)
        XCTAssertTrue(app.segmentedControls.buttons["好友"].exists)
        XCTAssertTrue(app.segmentedControls.buttons["请求"].exists)
        XCTAssertTrue(app.segmentedControls.buttons["关注"].exists)
        XCTAssertTrue(app.textFields["social-search-field"].exists)
        let privacyMessage = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "邮箱和 Apple 登录信息不能用于找人")
        ).firstMatch
        XCTAssertTrue(privacyMessage.waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["private-ui-fixture@example.test"].exists)
    }

    @MainActor
    func testWantToGoRestaurantOpensDetailInformationCenter() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-p1b-restaurant-detail-fixture"]
        app.launch()

        app.segmentedControls.buttons["想吃"].tap()
        let card = app.buttons["restaurant-card-11111111-2222-3333-4444-555555555555"]
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        card.tap()

        XCTAssertTrue(app.navigationBars["餐厅详情"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.otherElements["restaurant-detail-header"].exists)
        XCTAssertTrue(app.staticTexts["P1-B 想吃餐厅"].exists)
        XCTAssertTrue(app.staticTexts["restaurant-status-wantToGo"].exists)
        XCTAssertTrue(app.buttons["open-in-apple-maps"].exists)
        XCTAssertTrue(app.buttons["restaurant-detail-add-visit"].exists)
        XCTAssertTrue(app.buttons["编辑"].exists)
    }

    @MainActor
    func testP1CMinimalVisitUsesCompleteNativeEditor() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-p1b-restaurant-detail-fixture"]
        app.launch()

        app.segmentedControls.buttons["想吃"].tap()
        let card = app.buttons["restaurant-card-11111111-2222-3333-4444-555555555555"]
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        card.tap()
        let addVisit = app.buttons["restaurant-detail-add-visit"]
        XCTAssertTrue(addVisit.waitForExistence(timeout: 5))
        addVisit.tap()

        XCTAssertTrue(app.navigationBars["新增到访"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["visit-editor-date"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["visit-editor-dining-mode"].exists)
        XCTAssertTrue(app.textFields["visit-editor-party-size"].exists)
        let spend = app.textFields["visit-editor-spend"]
        scrollUntilVisible(spend, in: app)
        XCTAssertTrue(spend.exists)
        let note = app.descendants(matching: .any)["visit-editor-note"]
        scrollUntilVisible(note, in: app)
        XCTAssertTrue(note.waitForExistence(timeout: 2))

        app.buttons["visit-editor-save"].tap()
        XCTAssertTrue(app.staticTexts["restaurant-status-visited"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["restaurant-detail-add-visit"].exists)
    }

    @MainActor
    func testP1DOfflineCreateEditDeleteFlow() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-p1d-persistent-offline-fixture",
            "-p1d-reset-persistent-offline-fixture",
        ]
        app.launchEnvironment = [
            "TASTEMAP_P1D_UI_TEST": "1",
            "TASTEMAP_P1D_RESET": "1",
        ]
        app.launch()

        openP1DDetail(in: app, tab: "想吃")
        addCompleteVisit(in: app)
        addMinimalVisit(in: app)

        XCTAssertTrue(app.staticTexts["2 条"].waitForExistence(timeout: 5))
        app.swipeUp()
        let completeVisit = app.staticTexts["第 1 次"]
        XCTAssertTrue(completeVisit.waitForExistence(timeout: 3))
        completeVisit.tap()
        XCTAssertTrue(app.navigationBars["编辑到访"].waitForExistence(timeout: 5))
        let editedNote = app.descendants(matching: .any)["visit-editor-note"]
        scrollUntilVisible(editedNote, in: app)
        XCTAssertTrue(editedNote.waitForExistence(timeout: 3))
        editedNote.tap()
        editedNote.typeText(" 已编辑")
        app.buttons["visit-editor-save"].tap()
        app.swipeUp()
        let persistedNote = app.staticTexts["visit-history-note"]
        XCTAssertTrue(persistedNote.waitForExistence(timeout: 5))
        XCTAssertEqual(persistedNote.label, "已编辑完整离线记录")

        let minimalVisit = app.staticTexts["第 2 次"]
        XCTAssertTrue(minimalVisit.waitForExistence(timeout: 3))
        minimalVisit.tap()
        XCTAssertTrue(app.navigationBars["编辑到访"].waitForExistence(timeout: 5))
        let deleteButton = app.buttons["visit-editor-delete"]
        scrollUntilVisible(deleteButton, in: app)
        XCTAssertTrue(deleteButton.waitForExistence(timeout: 2))
        deleteButton.tap()
        XCTAssertTrue(app.buttons["删除到访记录"].waitForExistence(timeout: 2))
        app.buttons["删除到访记录"].tap()
        XCTAssertTrue(app.staticTexts["1 条"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["visit-history-note"].label, "已编辑完整离线记录")
        XCTAssertTrue(app.staticTexts["2 人"].exists)
        XCTAssertFalse(app.staticTexts["2 条"].exists)
    }

    @MainActor
    func testP2BVisitPhotoAppearsLocallyAndCanBeDeleted() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-p1d-persistent-offline-fixture",
            "-p1d-reset-persistent-offline-fixture",
        ]
        app.launchEnvironment = [
            "TASTEMAP_P1D_UI_TEST": "1",
            "TASTEMAP_P1D_RESET": "1",
            "TASTEMAP_P2B_UI_TEST": "1",
        ]
        app.launch()

        app.segmentedControls.buttons["想吃"].tap()
        let card = app.buttons["restaurant-card-11111111-2222-3333-4444-555555555555"]
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        card.tap()
        app.buttons["restaurant-detail-add-visit"].tap()
        XCTAssertTrue(app.navigationBars["新增到访"].waitForExistence(timeout: 5))
        let photoPicker = app.buttons["visit-photo-picker"]
        scrollUntilVisible(photoPicker, in: app)
        XCTAssertTrue(photoPicker.waitForExistence(timeout: 3))
        let importButton = app.buttons["visit-photo-ui-test-import"]
        scrollUntilVisible(importButton, in: app)
        XCTAssertTrue(importButton.waitForExistence(timeout: 3))
        for _ in 0..<10 {
            scrollUntilVisible(importButton, in: app)
            importButton.tap()
            XCTAssertTrue(app.staticTexts["本机"].waitForExistence(timeout: 5))
        }
        XCTAssertTrue(app.staticTexts["10/10"].waitForExistence(timeout: 5))
        app.buttons["visit-editor-save"].tap()

        app.terminate()
        app.launchArguments = ["-p1d-persistent-offline-fixture"]
        app.launchEnvironment = [
            "TASTEMAP_P1D_UI_TEST": "1",
            "TASTEMAP_P2B_UI_TEST": "1",
        ]
        app.launch()
        let markers = app.otherElements.matching(
            NSPredicate(format: "label == 'P1-D 离线验收餐厅'")
        )
        XCTAssertTrue(markers.firstMatch.waitForExistence(timeout: 5))
        markers.element(boundBy: max(0, markers.count - 1)).tap()
        XCTAssertTrue(app.navigationBars["餐厅详情"].waitForExistence(timeout: 5))
        app.swipeUp()
        XCTAssertTrue(app.staticTexts["10 张"].waitForExistence(timeout: 5))
        let photo = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH 'restaurant-photo-'")
        ).firstMatch
        XCTAssertTrue(photo.waitForExistence(timeout: 5))
        // The horizontal gallery can be partially under the compact navigation bar
        // after the preceding vertical swipe. Tap its visible lower area explicitly.
        photo.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85)).tap()
        XCTAssertTrue(app.navigationBars["1 / 10"].waitForExistence(timeout: 5))
        app.buttons["完成"].tap()

        app.swipeUp()
        let firstVisit = app.staticTexts["第 1 次"]
        XCTAssertTrue(firstVisit.waitForExistence(timeout: 5))
        firstVisit.tap()
        XCTAssertTrue(app.navigationBars["编辑到访"].waitForExistence(timeout: 5))
        for _ in 0..<10 {
            let deletePhoto = app.buttons["删除照片"].firstMatch
            scrollUntilVisible(deletePhoto, in: app)
            XCTAssertTrue(deletePhoto.waitForExistence(timeout: 5))
            deletePhoto.tap()
        }
        app.buttons["visit-editor-save"].tap()
        XCTAssertTrue(app.staticTexts["尚未添加"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testP2GFullRichVisitOfflineRestart() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-p1d-persistent-offline-fixture",
            "-p1d-reset-persistent-offline-fixture",
        ]
        app.launchEnvironment = [
            "TASTEMAP_P1D_UI_TEST": "1",
            "TASTEMAP_P1D_RESET": "1",
            "TASTEMAP_P2B_UI_TEST": "1",
        ]
        app.launch()

        openP1DDetail(in: app, tab: "想吃")
        app.buttons["restaurant-detail-add-visit"].tap()
        XCTAssertTrue(app.navigationBars["新增到访"].waitForExistence(timeout: 5))
        app.segmentedControls.buttons["外卖"].tap()
        app.textFields["visit-editor-party-size"].tap()
        app.textFields["visit-editor-party-size"].typeText("3")

        let companionEntry = app.buttons["visit-editor-companions"]
        scrollUntilVisible(companionEntry, in: app)
        companionEntry.tap()
        addDirectoryName("P2-G 饭搭子", field: "companion-new-name", button: "companion-add", in: app)
        app.buttons["完成"].tap()
        let sourceEntry = app.buttons["visit-editor-recommendation-source"]
        scrollUntilVisible(sourceEntry, in: app)
        sourceEntry.tap()
        addDirectoryName("P2-G 推荐来源", field: "source-new-name", button: "source-add", in: app)
        app.buttons["完成"].tap()

        let context = app.descendants(matching: .any)["visit-editor-dining-context"]
        scrollUntilVisible(context, in: app)
        context.tap()
        selectPicker("visit-editor-queue-duration", option: "无需排队", in: app)
        let friends = app.buttons["visit-editor-dining-occasions-friends"]
        scrollUntilVisible(friends, in: app)
        friends.tap()

        let overall = app.buttons["4.5 星"]
        scrollUntilVisible(overall, in: app)
        overall.tap()
        let details = app.descendants(matching: .any)["visit-detailed-ratings"]
        scrollUntilVisible(details, in: app)
        details.tap()
        let value = app.buttons["性价比 5.0 星"]
        scrollUntilVisible(value, in: app)
        value.tap()
        let environment = app.buttons["环境 4.0 星"]
        scrollUntilVisible(environment, in: app)
        environment.tap()
        let service = app.buttons["服务 3.5 星"]
        scrollUntilVisible(service, in: app)
        service.tap()

        let importButton = app.buttons["visit-photo-ui-test-import"]
        scrollUntilVisible(importButton, in: app)
        importButton.tap()
        XCTAssertTrue(app.staticTexts["本机"].waitForExistence(timeout: 5))
        openDishManager(in: app)
        app.buttons["visit-dish-add-new"].tap()
        XCTAssertTrue(app.navigationBars["新菜品"].waitForExistence(timeout: 5))
        app.textFields["dish-name"].tap()
        app.textFields["dish-name"].typeText("P2-G 招牌菜")
        app.buttons["菜品 4.5 星"].tap()
        app.textFields["dish-price"].tap()
        app.textFields["dish-price"].typeText("88")
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'dish-photo-'")).firstMatch.tap()
        app.buttons["dish-save"].tap()
        app.buttons["dish-manager-done"].tap()

        let spend = app.textFields["visit-editor-spend"]
        scrollUntilVisible(spend, in: app)
        spend.tap()
        spend.typeText("128")
        let note = app.descendants(matching: .any)["visit-editor-note"]
        scrollUntilVisible(note, in: app)
        note.tap()
        note.typeText("P2-G 完整离线记录")
        selectPicker("visit-editor-visibility", option: "公开", in: app)
        app.buttons["visit-editor-save"].tap()

        XCTAssertTrue(app.staticTexts["restaurant-status-visited"].waitForExistence(timeout: 5))
        scrollUntilVisible(app.staticTexts["P2-G 招牌菜"], in: app)
        XCTAssertTrue(app.staticTexts["P2-G 招牌菜"].exists)
        let companions = app.staticTexts["visit-history-companions"]
        scrollUntilVisible(companions, in: app)
        XCTAssertTrue(companions.label.contains("P2-G 饭搭子"))
        XCTAssertTrue(app.staticTexts["visit-history-recommendation-source"].label.contains("P2-G 推荐来源"))
        XCTAssertTrue(app.descendants(matching: .any)["restaurant-detailed-rating-value"].exists)
        XCTAssertTrue(app.staticTexts["1 张"].exists)

        app.terminate()
        app.launchArguments = ["-p1d-persistent-offline-fixture"]
        app.launchEnvironment = [
            "TASTEMAP_P1D_UI_TEST": "1",
            "TASTEMAP_P2B_UI_TEST": "1",
        ]
        app.launch()
        let markers = app.otherElements.matching(NSPredicate(format: "label == 'P1-D 离线验收餐厅'"))
        XCTAssertTrue(markers.firstMatch.waitForExistence(timeout: 5))
        markers.element(boundBy: max(0, markers.count - 1)).tap()
        XCTAssertTrue(app.navigationBars["餐厅详情"].waitForExistence(timeout: 5))
        scrollUntilVisible(app.staticTexts["P2-G 招牌菜"], in: app)
        XCTAssertTrue(app.staticTexts["P2-G 招牌菜"].exists)
        scrollUntilVisible(app.staticTexts["P2-G 完整离线记录"], in: app)
        XCTAssertTrue(app.staticTexts["P2-G 完整离线记录"].exists)
        XCTAssertTrue(app.staticTexts["visit-history-companions"].label.contains("P2-G 饭搭子"))
        XCTAssertTrue(app.staticTexts["visit-history-recommendation-source"].label.contains("P2-G 推荐来源"))
    }

    @MainActor
    func testP2GMigratesPersistedP1StoreWithoutReset() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["TASTEMAP_P2G_MIGRATION_UI_TEST"] == "1"
                || FileManager.default.fileExists(
                    atPath: "/tmp/tastemap-p2g-migration-ui-test.enabled"
                ),
            "Run only after the P1 fixture app has created its persistent store."
        )
        let app = XCUIApplication()
        app.launchArguments = ["-p1d-persistent-offline-fixture"]
        app.launchEnvironment = ["TASTEMAP_P1D_UI_TEST": "1"]
        app.launch()

        let markers = app.otherElements.matching(NSPredicate(format: "label == 'P1-D 离线验收餐厅'"))
        XCTAssertTrue(markers.firstMatch.waitForExistence(timeout: 8))
        markers.element(boundBy: max(0, markers.count - 1)).tap()
        XCTAssertTrue(app.navigationBars["餐厅详情"].waitForExistence(timeout: 5))
        scrollUntilVisible(app.staticTexts["已编辑完整离线记录"], in: app)
        XCTAssertTrue(app.staticTexts["已编辑完整离线记录"].exists)
        XCTAssertTrue(app.staticTexts["1 条"].exists)
        XCTAssertTrue(app.staticTexts["2 人"].exists)
    }

    @MainActor
    func testP2BUploadFailureShowsRetryWithoutNetworkAccess() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-p1d-persistent-offline-fixture",
            "-p1d-reset-persistent-offline-fixture",
        ]
        app.launchEnvironment = [
            "TASTEMAP_P1D_UI_TEST": "1",
            "TASTEMAP_P1D_RESET": "1",
            "TASTEMAP_P2B_UPLOAD_FAILURE_UI_TEST": "1",
        ]
        app.launch()

        let markers = app.otherElements.matching(
            NSPredicate(format: "label == 'P1-D 离线验收餐厅'")
        )
        XCTAssertTrue(markers.firstMatch.waitForExistence(timeout: 5))
        markers.element(boundBy: max(0, markers.count - 1)).tap()
        XCTAssertTrue(app.navigationBars["餐厅详情"].waitForExistence(timeout: 5))
        app.swipeUp()
        XCTAssertTrue(app.staticTexts["上传失败"].waitForExistence(timeout: 5))
        let retry = app.buttons["重试"]
        XCTAssertTrue(retry.waitForExistence(timeout: 5))
        retry.tap()
        XCTAssertTrue(app.staticTexts["等待上传"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testP2CDishCreatePhotoReuseEditRemoveAndRestart() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-p1d-persistent-offline-fixture",
            "-p1d-reset-persistent-offline-fixture",
        ]
        app.launchEnvironment = [
            "TASTEMAP_P1D_UI_TEST": "1",
            "TASTEMAP_P1D_RESET": "1",
            "TASTEMAP_P2B_UI_TEST": "1",
        ]
        app.launch()

        openP1DDetail(in: app, tab: "想吃")
        app.buttons["restaurant-detail-add-visit"].tap()
        XCTAssertTrue(app.navigationBars["新增到访"].waitForExistence(timeout: 5))
        let importButton = app.buttons["visit-photo-ui-test-import"]
        scrollUntilVisible(importButton, in: app)
        XCTAssertTrue(importButton.waitForExistence(timeout: 3))
        importButton.tap()
        XCTAssertTrue(app.staticTexts["本机"].waitForExistence(timeout: 5))
        openDishManager(in: app)
        app.buttons["visit-dish-add-new"].tap()
        XCTAssertTrue(app.navigationBars["新菜品"].waitForExistence(timeout: 5))
        app.textFields["dish-name"].tap()
        app.textFields["dish-name"].typeText("招牌牛肉")
        app.buttons["菜品 4.5 星"].tap()
        app.textFields["dish-price"].tap()
        app.textFields["dish-price"].typeText("88")
        let photo = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH 'dish-photo-'")
        ).firstMatch
        XCTAssertTrue(photo.waitForExistence(timeout: 5))
        photo.tap()
        app.buttons["dish-save"].tap()
        XCTAssertTrue(app.staticTexts["招牌牛肉"].waitForExistence(timeout: 5))
        app.buttons["dish-manager-done"].tap()
        app.buttons["visit-editor-save"].tap()
        XCTAssertTrue(app.navigationBars["餐厅详情"].waitForExistence(timeout: 5))
        scrollUntilVisible(app.staticTexts["招牌牛肉"], in: app)
        XCTAssertTrue(app.staticTexts["招牌牛肉"].exists)
        app.terminate()
        app.launchArguments = ["-p1d-persistent-offline-fixture"]
        app.launchEnvironment = [
            "TASTEMAP_P1D_UI_TEST": "1",
            "TASTEMAP_P2B_UI_TEST": "1",
        ]
        app.launch()
        let markers = app.otherElements.matching(
            NSPredicate(format: "label == 'P1-D 离线验收餐厅'")
        )
        XCTAssertTrue(markers.firstMatch.waitForExistence(timeout: 5))
        markers.element(boundBy: max(0, markers.count - 1)).tap()
        XCTAssertTrue(app.navigationBars["餐厅详情"].waitForExistence(timeout: 5))
        scrollUntilVisible(app.staticTexts["招牌牛肉"], in: app)
        XCTAssertTrue(app.staticTexts["招牌牛肉"].exists)

        app.buttons["restaurant-detail-add-visit"].tap()
        openDishManager(in: app)
        let existing = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH 'existing-dish-'")
        ).firstMatch
        XCTAssertTrue(existing.waitForExistence(timeout: 5))
        existing.tap()
        let edit = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH 'visit-dish-edit-'")
        ).firstMatch
        XCTAssertTrue(edit.waitForExistence(timeout: 5))
        edit.tap()
        let note = app.descendants(matching: .any)["dish-note"]
        XCTAssertTrue(note.waitForExistence(timeout: 5))
        note.tap()
        note.typeText("再次到访依然稳定")
        app.buttons["dish-save"].tap()
        app.buttons["dish-manager-done"].tap()
        app.buttons["visit-editor-save"].tap()
        let twice = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS '吃过 2 次'")
        ).firstMatch
        scrollUntilVisible(twice, in: app)
        XCTAssertTrue(twice.exists)
        let dishDetail = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH 'restaurant-dish-'")
        ).firstMatch
        XCTAssertTrue(dishDetail.waitForExistence(timeout: 5))
        dishDetail.tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS '再次到访依然稳定'")
        ).firstMatch.waitForExistence(timeout: 5))
        app.buttons["完成"].tap()

        scrollUntilVisible(app.staticTexts["第 2 次"], in: app)
        app.staticTexts["第 2 次"].tap()
        openDishManager(in: app)
        let remove = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH 'visit-dish-remove-'")
        ).firstMatch
        XCTAssertTrue(remove.waitForExistence(timeout: 5))
        remove.tap()
        app.buttons["dish-manager-done"].tap()
        app.buttons["visit-editor-save"].tap()
        let once = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS '吃过 1 次'")
        ).firstMatch
        scrollUntilVisible(once, in: app)
        XCTAssertTrue(once.exists)
        XCTAssertTrue(app.staticTexts["招牌牛肉"].exists)
    }

    @MainActor
    func testP2DPartialRatingsEditClearDetailAndRestart() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-p1d-persistent-offline-fixture",
            "-p1d-reset-persistent-offline-fixture",
        ]
        app.launchEnvironment = [
            "TASTEMAP_P1D_UI_TEST": "1",
            "TASTEMAP_P1D_RESET": "1",
        ]
        app.launch()

        openP1DDetail(in: app, tab: "想吃")
        app.buttons["restaurant-detail-add-visit"].tap()
        XCTAssertTrue(app.navigationBars["新增到访"].waitForExistence(timeout: 5))
        let overallRating = app.buttons["4.5 星"]
        scrollUntilVisible(overallRating, in: app)
        XCTAssertTrue(overallRating.exists)
        overallRating.tap()
        let details = app.descendants(matching: .any)["visit-detailed-ratings"]
        scrollUntilVisible(details, in: app)
        XCTAssertTrue(details.exists)
        details.tap()
        let valueRating = app.buttons["性价比 5.0 星"]
        scrollUntilVisible(valueRating, in: app)
        XCTAssertTrue(valueRating.waitForExistence(timeout: 3))
        valueRating.tap()
        let serviceRating = app.buttons["服务 3.5 星"]
        scrollUntilVisible(serviceRating, in: app)
        XCTAssertTrue(serviceRating.exists)
        serviceRating.tap()
        app.buttons["visit-editor-save"].tap()

        let valueSummary = app.descendants(matching: .any)["restaurant-detailed-rating-value"]
        scrollUntilVisible(valueSummary, in: app)
        XCTAssertTrue(valueSummary.waitForExistence(timeout: 3))
        XCTAssertTrue(valueSummary.label.contains("5.0"))
        let serviceSummary = app.descendants(matching: .any)["restaurant-detailed-rating-service"]
        XCTAssertTrue(serviceSummary.exists)
        XCTAssertTrue(serviceSummary.label.contains("3.5"))
        XCTAssertFalse(app.descendants(matching: .any)["restaurant-detailed-rating-environment"].exists)

        scrollUntilVisible(app.staticTexts["第 1 次"], in: app)
        app.staticTexts["第 1 次"].tap()
        XCTAssertTrue(app.navigationBars["编辑到访"].waitForExistence(timeout: 5))
        let environmentRating = app.buttons["环境 4.0 星"]
        scrollUntilVisible(environmentRating, in: app)
        XCTAssertTrue(environmentRating.waitForExistence(timeout: 3))
        environmentRating.tap()
        let clearServiceRating = app.buttons["清除服务评分"]
        scrollUntilVisible(clearServiceRating, in: app)
        XCTAssertTrue(clearServiceRating.exists)
        clearServiceRating.tap()
        app.buttons["visit-editor-save"].tap()

        let environmentSummary = app.descendants(matching: .any)["restaurant-detailed-rating-environment"]
        scrollUntilVisible(environmentSummary, in: app)
        XCTAssertTrue(environmentSummary.waitForExistence(timeout: 3))
        XCTAssertTrue(environmentSummary.label.contains("4.0"))
        XCTAssertFalse(app.descendants(matching: .any)["restaurant-detailed-rating-service"].exists)

        app.terminate()
        app.launchArguments = ["-p1d-persistent-offline-fixture"]
        app.launchEnvironment = ["TASTEMAP_P1D_UI_TEST": "1"]
        app.launch()
        let markers = app.otherElements.matching(
            NSPredicate(format: "label == 'P1-D 离线验收餐厅'")
        )
        XCTAssertTrue(markers.firstMatch.waitForExistence(timeout: 5))
        markers.element(boundBy: max(0, markers.count - 1)).tap()
        XCTAssertTrue(app.navigationBars["餐厅详情"].waitForExistence(timeout: 5))
        let restoredValue = app.descendants(matching: .any)["restaurant-detailed-rating-value"]
        scrollUntilVisible(restoredValue, in: app)
        XCTAssertTrue(restoredValue.waitForExistence(timeout: 5))
        XCTAssertTrue(restoredValue.label.contains("5.0"))
        XCTAssertTrue(app.descendants(matching: .any)["restaurant-detailed-rating-environment"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["restaurant-detailed-rating-service"].exists)
    }

    @MainActor
    func testP2EDiningContextCreateEditClearAndRestart() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-p1d-persistent-offline-fixture",
            "-p1d-reset-persistent-offline-fixture",
        ]
        app.launchEnvironment = [
            "TASTEMAP_P1D_UI_TEST": "1",
            "TASTEMAP_P1D_RESET": "1",
        ]
        app.launch()

        openP1DDetail(in: app, tab: "想吃")
        app.buttons["restaurant-detail-add-visit"].tap()
        XCTAssertTrue(app.navigationBars["新增到访"].waitForExistence(timeout: 5))
        app.textFields["visit-editor-party-size"].tap()
        app.textFields["visit-editor-party-size"].typeText("3")

        let context = app.descendants(matching: .any)["visit-editor-dining-context"]
        scrollUntilVisible(context, in: app)
        XCTAssertTrue(context.waitForExistence(timeout: 3))
        context.tap()
        selectPicker("visit-editor-queue-duration", option: "无需排队", in: app)
        let friends = app.buttons["visit-editor-dining-occasions-friends"]
        scrollUntilVisible(friends, in: app)
        XCTAssertTrue(friends.waitForExistence(timeout: 3))
        friends.tap()

        selectPicker("visit-editor-payment-mode", option: "AA", in: app)
        let total = app.textFields["visit-editor-total-price"]
        scrollUntilVisible(total, in: app)
        XCTAssertTrue(total.exists)
        total.tap()
        total.typeText("360")
        let spend = app.textFields["visit-editor-spend"]
        scrollUntilVisible(spend, in: app)
        spend.tap()
        spend.typeText("120")
        selectPicker("visit-editor-visibility", option: "公开", in: app)
        app.buttons["visit-editor-save"].tap()

        let contextSummary = app.descendants(matching: .any)["visit-history-context"]
        scrollUntilVisible(contextSummary, in: app)
        XCTAssertTrue(contextSummary.waitForExistence(timeout: 5))
        XCTAssertTrue(contextSummary.label.contains("朋友聚餐"))
        XCTAssertTrue(contextSummary.label.contains("无需排队"))
        XCTAssertTrue(app.staticTexts["AA"].exists)

        scrollUntilVisible(app.staticTexts["第 1 次"], in: app)
        app.staticTexts["第 1 次"].tap()
        XCTAssertTrue(app.navigationBars["编辑到访"].waitForExistence(timeout: 5))
        let selectedFriends = app.buttons["visit-editor-dining-occasions-friends"]
        scrollUntilVisible(selectedFriends, in: app)
        XCTAssertEqual(selectedFriends.value as? String, "已选择")
        selectedFriends.tap()
        selectPicker("visit-editor-queue-duration", option: "不记录", in: app)
        let clearPayment = app.buttons["visit-editor-payment-clear"]
        scrollUntilVisible(clearPayment, in: app)
        XCTAssertTrue(clearPayment.waitForExistence(timeout: 3))
        clearPayment.tap()
        selectPicker("visit-editor-visibility", option: "仅自己", in: app)
        app.buttons["visit-editor-save"].tap()

        scrollUntilVisible(app.staticTexts["第 1 次"], in: app)
        XCTAssertTrue(app.staticTexts["第 1 次"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["visit-history-context"].exists)
        XCTAssertFalse(app.staticTexts["AA"].exists)

        app.terminate()
        app.launchArguments = ["-p1d-persistent-offline-fixture"]
        app.launchEnvironment = ["TASTEMAP_P1D_UI_TEST": "1"]
        app.launch()
        let markers = app.otherElements.matching(
            NSPredicate(format: "label == 'P1-D 离线验收餐厅'")
        )
        XCTAssertTrue(markers.firstMatch.waitForExistence(timeout: 5))
        markers.element(boundBy: max(0, markers.count - 1)).tap()
        XCTAssertTrue(app.navigationBars["餐厅详情"].waitForExistence(timeout: 5))
        scrollUntilVisible(app.staticTexts["第 1 次"], in: app)
        XCTAssertTrue(app.staticTexts["第 1 次"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["visit-history-context"].exists)
    }

    @MainActor
    func testP2FCompanionsAndSourceCreateEditRestartAndReuse() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-p1d-persistent-offline-fixture",
            "-p1d-reset-persistent-offline-fixture",
        ]
        app.launchEnvironment = [
            "TASTEMAP_P1D_UI_TEST": "1",
            "TASTEMAP_P1D_RESET": "1",
        ]
        app.launch()

        openP1DDetail(in: app, tab: "想吃")
        app.buttons["restaurant-detail-add-visit"].tap()
        XCTAssertTrue(app.navigationBars["新增到访"].waitForExistence(timeout: 5))

        let companionEntry = app.buttons["visit-editor-companions"]
        scrollUntilVisible(companionEntry, in: app)
        companionEntry.tap()
        XCTAssertTrue(app.navigationBars["和谁一起吃"].waitForExistence(timeout: 5))
        addDirectoryName("小王", field: "companion-new-name", button: "companion-add", in: app)
        addDirectoryName("妈妈", field: "companion-new-name", button: "companion-add", in: app)
        app.buttons["完成"].tap()

        let sourceEntry = app.buttons["visit-editor-recommendation-source"]
        scrollUntilVisible(sourceEntry, in: app)
        sourceEntry.tap()
        XCTAssertTrue(app.navigationBars["推荐来源"].waitForExistence(timeout: 5))
        addDirectoryName("朋友小李", field: "source-new-name", button: "source-add", in: app)
        app.buttons["完成"].tap()
        app.buttons["visit-editor-save"].tap()

        let companions = app.staticTexts["visit-history-companions"]
        scrollUntilVisible(companions, in: app)
        XCTAssertTrue(companions.waitForExistence(timeout: 5))
        XCTAssertTrue(companions.label.contains("小王"))
        XCTAssertTrue(companions.label.contains("妈妈"))
        let source = app.staticTexts["visit-history-recommendation-source"]
        XCTAssertTrue(source.exists)
        XCTAssertTrue(source.label.contains("朋友小李"))

        scrollUntilVisible(app.staticTexts["第 1 次"], in: app)
        app.staticTexts["第 1 次"].tap()
        XCTAssertTrue(app.navigationBars["编辑到访"].waitForExistence(timeout: 5))
        let editCompanions = app.buttons["visit-editor-companions"]
        scrollUntilVisible(editCompanions, in: app)
        editCompanions.tap()
        XCTAssertTrue(app.navigationBars["和谁一起吃"].waitForExistence(timeout: 5))
        tapDirectoryOption("小王", in: app)
        app.buttons["完成"].tap()
        let editSource = app.buttons["visit-editor-recommendation-source"]
        scrollUntilVisible(editSource, in: app)
        editSource.tap()
        XCTAssertTrue(app.navigationBars["推荐来源"].waitForExistence(timeout: 5))
        app.buttons["清除推荐来源"].tap()
        app.buttons["完成"].tap()
        app.buttons["visit-editor-save"].tap()

        let remainingCompanion = app.staticTexts["visit-history-companions"]
        scrollUntilVisible(remainingCompanion, in: app)
        XCTAssertTrue(remainingCompanion.label.contains("妈妈"))
        XCTAssertFalse(remainingCompanion.label.contains("小王"))
        XCTAssertFalse(app.staticTexts["visit-history-recommendation-source"].exists)

        app.terminate()
        app.launchArguments = ["-p1d-persistent-offline-fixture"]
        app.launchEnvironment = ["TASTEMAP_P1D_UI_TEST": "1"]
        app.launch()
        let restoredMarkers = app.otherElements.matching(
            NSPredicate(format: "label == 'P1-D 离线验收餐厅'")
        )
        XCTAssertTrue(restoredMarkers.firstMatch.waitForExistence(timeout: 5))
        restoredMarkers.element(boundBy: max(0, restoredMarkers.count - 1)).tap()
        XCTAssertTrue(app.navigationBars["餐厅详情"].waitForExistence(timeout: 5))
        let restoredCompanion = app.staticTexts["visit-history-companions"]
        scrollUntilVisible(restoredCompanion, in: app)
        XCTAssertTrue(restoredCompanion.waitForExistence(timeout: 5))
        XCTAssertTrue(restoredCompanion.label.contains("妈妈"))

        app.buttons["restaurant-detail-add-visit"].tap()
        XCTAssertTrue(app.navigationBars["新增到访"].waitForExistence(timeout: 5))
        let reuseCompanion = app.buttons["visit-editor-companions"]
        scrollUntilVisible(reuseCompanion, in: app)
        reuseCompanion.tap()
        XCTAssertTrue(app.navigationBars["和谁一起吃"].waitForExistence(timeout: 5))
        let companionSearch = app.searchFields.firstMatch
        XCTAssertTrue(companionSearch.waitForExistence(timeout: 3))
        companionSearch.tap()
        companionSearch.typeText("妈妈")
        dismissSearchKeyboard(in: app)
        tapDirectoryOption("妈妈", in: app)
        XCTAssertTrue(app.navigationBars["新增到访"].waitForExistence(timeout: 5))
        let reuseSource = app.buttons["visit-editor-recommendation-source"]
        scrollUntilVisible(reuseSource, in: app)
        reuseSource.tap()
        XCTAssertTrue(app.navigationBars["推荐来源"].waitForExistence(timeout: 5))
        let sourceSearch = app.searchFields.firstMatch
        XCTAssertTrue(sourceSearch.waitForExistence(timeout: 3))
        sourceSearch.tap()
        sourceSearch.typeText("朋友小李")
        dismissSearchKeyboard(in: app)
        tapDirectoryOption("朋友小李", in: app)
        XCTAssertTrue(app.navigationBars["新增到访"].waitForExistence(timeout: 5))
        app.buttons["visit-editor-save"].tap()
        XCTAssertTrue(app.staticTexts["第 2 次"].waitForExistence(timeout: 5))
    }

    @MainActor
    private func addDirectoryName(
        _ name: String,
        field: String,
        button: String,
        in app: XCUIApplication
    ) {
        let textField = app.textFields[field]
        XCTAssertTrue(textField.waitForExistence(timeout: 3))
        textField.tap()
        textField.typeText(name)
        app.buttons[button].tap()
    }

    @MainActor
    private func tapDirectoryOption(_ label: String, in app: XCUIApplication) {
        let option = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", label)
        ).firstMatch
        XCTAssertTrue(option.waitForExistence(timeout: 3))
        option.tap()
    }

    @MainActor
    private func dismissSearchKeyboard(in app: XCUIApplication) {
        let searchKey = app.keyboards.buttons["Search"]
        if searchKey.exists { searchKey.tap() }
    }

    @MainActor
    private func openP1DDetail(in app: XCUIApplication, tab: String) {
        app.segmentedControls.buttons[tab].tap()
        let card = app.buttons["restaurant-card-11111111-2222-3333-4444-555555555555"]
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        card.tap()
        XCTAssertTrue(app.navigationBars["餐厅详情"].waitForExistence(timeout: 5))
    }

    @MainActor
    private func addCompleteVisit(in app: XCUIApplication) {
        app.buttons["restaurant-detail-add-visit"].tap()
        XCTAssertTrue(app.navigationBars["新增到访"].waitForExistence(timeout: 5))
        app.segmentedControls.buttons["外卖"].tap()
        app.textFields["visit-editor-party-size"].tap()
        app.textFields["visit-editor-party-size"].typeText("2")
        let rating = app.buttons["4.5 星"]
        scrollUntilVisible(rating, in: app)
        XCTAssertTrue(rating.waitForExistence(timeout: 3))
        rating.tap()
        let spend = app.textFields["visit-editor-spend"]
        scrollUntilVisible(spend, in: app)
        spend.tap()
        spend.typeText("128.5")
        let note = app.descendants(matching: .any)["visit-editor-note"]
        scrollUntilVisible(note, in: app)
        note.tap()
        note.typeText("完整离线记录")
        app.buttons["visit-editor-save"].tap()
        XCTAssertTrue(app.staticTexts["restaurant-status-visited"].waitForExistence(timeout: 5))
    }

    @MainActor
    private func addMinimalVisit(in app: XCUIApplication) {
        app.buttons["restaurant-detail-add-visit"].tap()
        XCTAssertTrue(app.navigationBars["新增到访"].waitForExistence(timeout: 5))
        app.buttons["visit-editor-save"].tap()
        XCTAssertTrue(app.navigationBars["餐厅详情"].waitForExistence(timeout: 5))
    }

    @MainActor
    private func openDishManager(in app: XCUIApplication) {
        let button = app.buttons["visit-dish-manager"]
        scrollUntilVisible(button, in: app)
        XCTAssertTrue(button.exists)
        button.tap()
        XCTAssertTrue(app.navigationBars["本次吃了什么"].waitForExistence(timeout: 5))
    }

    @MainActor
    private func scrollUntilVisible(_ element: XCUIElement, in app: XCUIApplication) {
        // Keep the gesture above a presented software keyboard so the Form,
        // rather than the keyboard, receives the drag.
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.56))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.22))
        for _ in 0..<30 where !element.isHittable {
            start.press(forDuration: 0.05, thenDragTo: end)
        }
    }

    @MainActor
    private func selectPicker(_ identifier: String, option: String, in app: XCUIApplication) {
        let title = switch identifier {
        case "visit-editor-queue-duration": "排队 / 等位"
        case "visit-editor-payment-mode": "消费方式"
        case "visit-editor-visibility": "可见性"
        default: identifier
        }
        let picker = app.buttons[title]
        scrollUntilVisible(picker, in: app)
        XCTAssertTrue(picker.waitForExistence(timeout: 3))
        picker.tap()
        let choiceLabel = option == "不记录" ? "\(title)：不记录" : option
        let scopedChoice = app.buttons[choiceLabel]
        let choice = scopedChoice.waitForExistence(timeout: 1) ? scopedChoice : app.buttons[option]
        XCTAssertTrue(choice.waitForExistence(timeout: 3))
        choice.tap()
    }

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}

private extension XCUIElement {
    func clearAndType(_ text: String) {
        typeKey("a", modifierFlags: .command)
        typeKey(.delete, modifierFlags: [])
        typeText(text)
    }
}
