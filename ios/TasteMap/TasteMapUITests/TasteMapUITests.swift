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
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
