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
        XCTAssertTrue(app.textFields["visit-editor-spend"].exists)
        let note = app.descendants(matching: .any)["visit-editor-note"]
        if !note.exists { app.swipeUp() }
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
        if !editedNote.exists { app.swipeUp() }
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
        if !deleteButton.exists { app.swipeUp() }
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
        app.buttons["4.5 星"].tap()
        let spend = app.textFields["visit-editor-spend"]
        if !spend.exists { app.swipeUp() }
        spend.tap()
        spend.typeText("128.5")
        let note = app.descendants(matching: .any)["visit-editor-note"]
        if !note.exists { app.swipeUp() }
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
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
