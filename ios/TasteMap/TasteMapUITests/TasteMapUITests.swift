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
        app.launchEnvironment["TASTEMAP_UI_TEST_RUNTIME"] = "1"
        app.launch()

        XCTAssertTrue(app.buttons["地图"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["发现"].exists)
        XCTAssertTrue(app.buttons["我的"].exists)
        XCTAssertTrue(app.buttons["添加餐厅"].exists)
        XCTAssertTrue(segmentedOption("去过", in: app).exists)
        XCTAssertTrue(segmentedOption("想吃", in: app).exists)

        app.buttons["添加餐厅"].tap()
        XCTAssertTrue(app.navigationBars["添加餐厅"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.textFields["restaurant-city-field"].exists)
        XCTAssertTrue(app.textFields["restaurant-query-field"].exists)
    }

    @MainActor
    func testF2AMapListSwitchAndSharedRestaurantDetail() throws {
        let app = XCUIApplication()
        app.launchEnvironment = ["TASTEMAP_F2A_BROWSING_UI_TEST": "1"]
        app.launch()

        let listMode = app.buttons["map-floating-view-list"]
        XCTAssertTrue(listMode.waitForExistence(timeout: 5))
        listMode.tap()
        let restaurantName = "F2-A 很长但仍需完整可读的江南季节料理餐厅"
        XCTAssertTrue(app.staticTexts[restaurantName].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["2 次到访"].exists)
        XCTAssertTrue(app.staticTexts["4.5"].exists)
        XCTAssertTrue(app.descendants(matching: .any).matching(
            identifier: "restaurant-photo-fallback-00000000-0000-0000-0000-000000010001"
        ).firstMatch.exists)

        let mapMode = app.buttons["map-floating-view-map"]
        XCTAssertTrue(mapMode.exists)
        mapMode.tap()
        XCTAssertTrue(app.maps.firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["map-floating-view-list"].waitForExistence(timeout: 5))
        app.buttons["map-floating-view-list"].tap()
        XCTAssertTrue(app.staticTexts[restaurantName].waitForExistence(timeout: 5))

        let row = app.buttons.containing(.staticText, identifier: restaurantName).firstMatch
        XCTAssertTrue(row.exists)
        row.tap()
        XCTAssertTrue(app.navigationBars["餐厅详情"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testTask04CoreLayoutParityEvidence() throws {
        let app = XCUIApplication()
        app.launchEnvironment = ["TASTEMAP_F2A_BROWSING_UI_TEST": "1"]
        app.launch()

        let map = app.maps.firstMatch
        let controls = app.descendants(matching: .any)["map-home-compact-controls"]
        let visitedTab = segmentedOption("去过", in: app)
        let listMode = app.buttons["map-floating-view-list"]
        XCTAssertTrue(map.waitForExistence(timeout: 8))
        XCTAssertTrue(controls.waitForExistence(timeout: 5))
        XCTAssertTrue(visitedTab.exists)
        XCTAssertTrue(listMode.exists)
        XCTAssertLessThanOrEqual(controls.frame.height, 104)
        XCTAssertGreaterThan(map.frame.height, app.frame.height * 0.72)
        XCTAssertGreaterThan(listMode.frame.minY, app.frame.height * 0.68)

        let addRestaurant = app.buttons["addRestaurantButton"]
        let mapTab = app.buttons["地图"].firstMatch
        XCTAssertTrue(addRestaurant.exists)
        XCTAssertTrue(mapTab.exists)
        XCTAssertLessThan(addRestaurant.frame.midY, mapTab.frame.midY)
        keepScreenshot(named: "Task 04 Map After", of: app)

        listMode.tap()
        let search = app.textFields["restaurant-list-search-field"]
        let restaurantName = "F2-A 很长但仍需完整可读的江南季节料理餐厅"
        let row = app.buttons.containing(.staticText, identifier: restaurantName).firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertLessThanOrEqual(row.frame.height, 96)
        XCTAssertEqual(row.frame.minX, 14, accuracy: 2)
        keepScreenshot(named: "Task 04 List After", of: app)

        row.tap()
        XCTAssertTrue(app.navigationBars["餐厅详情"].waitForExistence(timeout: 5))
        let hero = app.descendants(matching: .any)["restaurant-photo-gallery"]
        let header = app.descendants(matching: .any)["restaurant-detail-header"]
        let actions = app.descendants(matching: .any)["restaurant-detail-quick-actions"]
        XCTAssertTrue(hero.waitForExistence(timeout: 5))
        XCTAssertTrue(header.exists)
        XCTAssertTrue(actions.exists)
        XCTAssertLessThan(hero.frame.minY, header.frame.minY)
        XCTAssertLessThanOrEqual(actions.frame.height, 190)
        keepScreenshot(named: "Task 04 Restaurant Detail After", of: app)
    }

    @MainActor
    func testTask04DarkLayoutKeepsCompactMapControls() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleInterfaceStyle", "Dark"]
        app.launchEnvironment = ["TASTEMAP_F2A_BROWSING_UI_TEST": "1"]
        app.launch()

        let map = app.maps.firstMatch
        let controls = app.descendants(matching: .any)["map-home-compact-controls"]
        XCTAssertTrue(map.waitForExistence(timeout: 8))
        XCTAssertTrue(controls.waitForExistence(timeout: 5))
        XCTAssertLessThanOrEqual(controls.frame.height, 112)
        XCTAssertGreaterThan(map.frame.height, app.frame.height * 0.72)
        XCTAssertTrue(app.buttons["addRestaurantButton"].isHittable)
        keepScreenshot(named: "Task 04 Map Dark After", of: app)
    }

    @MainActor
    func testCoreProductLayoutParityMapDiscoveryProfileEvidence() throws {
        let app = XCUIApplication()
        app.launchEnvironment = [
            "TASTEMAP_F2A_BROWSING_UI_TEST": "1",
            "TASTEMAP_CORE_PARITY_INITIAL_TAB": "map",
        ]
        app.launch()

        let controls = app.descendants(matching: .any)["map-home-compact-controls"]
        XCTAssertTrue(controls.waitForExistence(timeout: 8))
        XCTAssertLessThanOrEqual(controls.frame.height, 104)
        XCTAssertTrue(app.descendants(matching: .any)["map-filter-chip-strip"].exists)
        XCTAssertTrue(app.buttons["map-filter-chip-city"].exists)
        XCTAssertTrue(app.buttons["map-filter-chip-rating"].exists)
        XCTAssertTrue(app.buttons["map-filter-chip-price"].exists)
        XCTAssertTrue(app.buttons["map-floating-view-list"].isHittable)
        XCTAssertFalse(app.segmentedControls.buttons["列表"].exists)
        keepScreenshot(named: "Core Parity Map After", of: app)

        app.buttons["map-floating-view-list"].tap()
        XCTAssertTrue(app.buttons["map-floating-view-map"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.textFields["restaurant-list-search-field"].exists)
        keepScreenshot(named: "Core Parity List After", of: app)

        app.terminate()
        app.launchEnvironment = [
            "TASTEMAP_P3C_DISCOVERY_UI_TEST": "1",
            "TASTEMAP_CORE_PARITY_INITIAL_TAB": "discover",
        ]
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["discovery-header"].waitForExistence(timeout: 8))
        for identifier in [
            "discovery-primary-following", "discovery-primary-forYou",
            "discovery-primary-similarTaste", "discovery-primary-latest",
            "discovery-primary-trending",
        ] {
            XCTAssertTrue(app.buttons[identifier].exists, "Missing primary Discovery tab \(identifier)")
        }
        XCTAssertFalse(app.buttons["发现餐厅"].exists)
        XCTAssertFalse(app.buttons["社区动态"].exists)
        XCTAssertTrue(app.buttons["discovery-city-menu"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["discovery-filters"].exists)
        keepScreenshot(named: "Core Parity Discovery After", of: app)

        app.terminate()
        app.launchEnvironment = [
            "TASTEMAP_F2A_BROWSING_UI_TEST": "1",
            "TASTEMAP_CORE_PARITY_INITIAL_TAB": "profile",
        ]
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["profile-compact-header"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.descendants(matching: .any)["profile-horizontal-statistics"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["profile-primary-actions"].exists)
        XCTAssertTrue(app.buttons["profile-restaurant-roulette-entry"].exists)
        XCTAssertTrue(app.buttons["profile-taste-analysis-entry"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["profile-memories-section"].exists)
        keepScreenshot(named: "Core Parity Profile After", of: app)
    }

    @MainActor
    func testCoreProductLayoutParityDarkDiscoveryAndProfile() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleInterfaceStyle", "Dark"]
        app.launchEnvironment = [
            "TASTEMAP_P3C_DISCOVERY_UI_TEST": "1",
            "TASTEMAP_CORE_PARITY_INITIAL_TAB": "discover",
        ]
        app.launch()

        XCTAssertTrue(app.descendants(matching: .any)["discovery-header"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["discovery-primary-following"].isHittable)
        XCTAssertTrue(app.buttons["discovery-primary-forYou"].isHittable)
        XCTAssertTrue(app.buttons["discovery-primary-similarTaste"].isHittable)
        XCTAssertTrue(app.buttons["discovery-primary-latest"].isHittable)
        XCTAssertTrue(app.buttons["discovery-primary-trending"].isHittable)
        XCTAssertTrue(app.buttons["discovery-city-menu"].isHittable)
        XCTAssertTrue(app.buttons["discovery-filters"].isHittable)
        keepScreenshot(named: "Core Parity Discovery Dark", of: app)

        app.terminate()
        app.launchArguments = ["-AppleInterfaceStyle", "Dark"]
        app.launchEnvironment = [
            "TASTEMAP_F2A_BROWSING_UI_TEST": "1",
            "TASTEMAP_CORE_PARITY_INITIAL_TAB": "profile",
        ]
        app.launch()

        XCTAssertTrue(app.descendants(matching: .any)["profile-compact-header"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.descendants(matching: .any)["profile-horizontal-statistics"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["profile-primary-actions"].exists)
        XCTAssertTrue(app.buttons["profile-restaurant-roulette-entry"].isHittable)
        XCTAssertTrue(app.buttons["profile-taste-analysis-entry"].isHittable)
        XCTAssertTrue(app.descendants(matching: .any)["profile-memories-section"].exists)
        keepScreenshot(named: "Core Parity Profile Dark", of: app)
    }

    /// Screenshot-only compatibility path used to capture the immutable
    /// origin/main app bundle before the parity patch. Assertions deliberately
    /// use long-standing labels so the same test binary can drive both builds.
    @MainActor
    func testCoreProductLayoutParityBaselineEvidenceCapture() throws {
        let app = XCUIApplication()
        app.launchEnvironment = ["TASTEMAP_F2A_BROWSING_UI_TEST": "1"]
        app.launch()
        XCTAssertTrue(app.buttons["地图"].waitForExistence(timeout: 8))
        keepScreenshot(named: "Core Parity Map Before", of: app)

        app.terminate()
        app.launchEnvironment = ["TASTEMAP_P3C_DISCOVERY_UI_TEST": "1"]
        app.launch()
        app.buttons["发现"].tap()
        XCTAssertTrue(app.buttons["发现"].waitForExistence(timeout: 8))
        keepScreenshot(named: "Core Parity Discovery Before", of: app)

        app.terminate()
        app.launchEnvironment = ["TASTEMAP_F2A_BROWSING_UI_TEST": "1"]
        app.launch()
        app.buttons["我的"].tap()
        XCTAssertTrue(app.navigationBars["我的"].waitForExistence(timeout: 8))
        keepScreenshot(named: "Core Parity Profile Before", of: app)
    }

    @MainActor
    func testMapMarkerSelectionUsesSharedRestaurantDetail() throws {
        let app = XCUIApplication()
        app.launchEnvironment = ["TASTEMAP_F2A_BROWSING_UI_TEST": "1"]
        app.launch()

        XCTAssertTrue(app.maps.firstMatch.waitForExistence(timeout: 8))
        let marker = app.descendants(matching: .any)[
            "restaurant-map-marker-00000000-0000-0000-0000-000000010001"
        ]
        XCTAssertTrue(marker.waitForExistence(timeout: 10))
        marker.tap()
        XCTAssertTrue(app.navigationBars["餐厅详情"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["F2-A 很长但仍需完整可读的江南季节料理餐厅"].exists)
    }

    @MainActor
    func testF2AProfileListsAndIndependentFootprints() throws {
        let app = XCUIApplication()
        app.launchEnvironment = ["TASTEMAP_F2A_BROWSING_UI_TEST": "1"]
        app.launch()
        app.buttons["我的"].tap()
        XCTAssertTrue(app.navigationBars["我的"].waitForExistence(timeout: 5))

        let visitedEntry = app.buttons["profile-visited-list-entry"]
        scrollUntilVisible(visitedEntry, in: app)
        visitedEntry.tap()
        XCTAssertTrue(app.navigationBars["去过的餐厅"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["F2-A 很长但仍需完整可读的江南季节料理餐厅"].exists)
        app.navigationBars["去过的餐厅"].buttons.firstMatch.tap()

        let wantedEntry = app.buttons["profile-want-list-entry"]
        scrollUntilVisible(wantedEntry, in: app)
        wantedEntry.tap()
        XCTAssertTrue(app.navigationBars["想吃的餐厅"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["F2-A 想吃小馆"].exists)
        app.navigationBars["想吃的餐厅"].buttons.firstMatch.tap()

        let footprintEntry = app.buttons["profile-taste-footprints-entry"]
        scrollUntilVisible(footprintEntry, in: app)
        footprintEntry.tap()
        XCTAssertTrue(app.navigationBars["味觉足迹"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "taste-footprint-item-")).count, 2)
        XCTAssertTrue(app.staticTexts["未评分"].exists)
        XCTAssertFalse(app.staticTexts["F2-A 已删除餐厅"].exists)
        XCTAssertFalse(app.staticTexts["F2-A 已删除餐厅"].waitForExistence(timeout: 1))
    }

    @MainActor
    func testF2BMapFilterMultiSelectApplyListParityAndReset() throws {
        let app = XCUIApplication()
        app.launchEnvironment = ["TASTEMAP_F2B_FILTERS_UI_TEST": "1"]
        app.launch()

        let filter = app.buttons["personal-filter-button"]
        XCTAssertTrue(filter.waitForExistence(timeout: 5))
        filter.tap()
        XCTAssertTrue(app.navigationBars["筛选与排序"].waitForExistence(timeout: 5))

        let topRating = app.buttons["personal-filter-rating-5"]
        XCTAssertTrue(topRating.waitForExistence(timeout: 3))
        topRating.tap()
        let takeout = app.buttons["personal-filter-dining-takeout"]
        scrollUntilVisible(takeout, in: app)
        XCTAssertTrue(takeout.isHittable)
        takeout.tap()
        app.buttons["personal-filter-apply"].tap()

        XCTAssertTrue(app.buttons["personal-filter-button"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["personal-filter-button"].label.contains("已启用"))
        app.buttons["map-floating-view-list"].tap()
        XCTAssertTrue(app.staticTexts["F2-B 命中外卖餐厅"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["F2-B 排除到店餐厅"].exists)

        app.buttons["personal-filter-button"].tap()
        let reset = app.buttons["personal-filter-reset"]
        XCTAssertTrue(reset.waitForExistence(timeout: 3))
        reset.tap()
        app.buttons["personal-filter-apply"].tap()
        XCTAssertTrue(app.staticTexts["F2-B 命中外卖餐厅"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["F2-B 排除到店餐厅"].exists)
    }

    @MainActor
    func testRestaurantAcquisitionNearbyRequiresExplicitWantToGoAction() throws {
        let app = XCUIApplication()
        app.launchEnvironment = ["TASTEMAP_RESTAURANT_ACQUISITION_UI_TEST": "1"]
        app.launch()

        app.buttons["添加餐厅"].tap()
        XCTAssertTrue(app.navigationBars["添加餐厅"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["V1 附近小馆"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["146 米"].exists)
        keepScreenshot(named: "Restaurant Acquisition Nearby", of: app)

        let want = app.buttons["candidate-want-AC000001-0000-0000-0000-000000000001"]
        XCTAssertTrue(want.waitForExistence(timeout: 3))
        want.tap()
        XCTAssertFalse(app.navigationBars["添加餐厅"].waitForExistence(timeout: 3))
        segmentedOption("想吃", in: app).tap()
        XCTAssertTrue(app.staticTexts["V1 附近小馆"].waitForExistence(timeout: 5))
        openWantToGoDetail(named: "V1 附近小馆", in: app)
    }

    @MainActor
    func testRestaurantAcquisitionCitySearchNoResultAndVisitEntry() throws {
        let app = XCUIApplication()
        app.launchEnvironment = ["TASTEMAP_RESTAURANT_ACQUISITION_UI_TEST": "1"]
        app.launch()
        app.buttons["添加餐厅"].tap()
        XCTAssertTrue(app.navigationBars["添加餐厅"].waitForExistence(timeout: 5))

        let city = app.textFields["restaurant-city-field"]
        scrollUntilVisible(city, in: app)
        XCTAssertTrue(city.waitForExistence(timeout: 5))
        city.tap()
        city.clearAndType("上海")
        let query = app.textFields["restaurant-query-field"]
        query.tap()
        query.typeText("没有结果")
        app.buttons["restaurant-search-submit"].tap()
        XCTAssertTrue(app.staticTexts["没有找到匹配的餐厅，请换一个名称、地址或城市。"].waitForExistence(timeout: 5))

        query.tap()
        query.clearAndType("外滩餐厅")
        app.buttons["restaurant-search-submit"].tap()
        XCTAssertTrue(app.staticTexts["上海 · 外滩餐厅"].waitForExistence(timeout: 5))
        dismissSearchKeyboard(in: app)

        let want = app.buttons["candidate-want-AC000002-0000-0000-0000-000000000002"]
        scrollUntilVisible(want, in: app)
        XCTAssertTrue(want.isHittable)
        want.tap()
        segmentedOption("想吃", in: app).tap()
        XCTAssertTrue(app.staticTexts["上海 · 外滩餐厅"].waitForExistence(timeout: 5))
        openWantToGoDetail(named: "上海 · 外滩餐厅", in: app)

        app.buttons["restaurant-detail-add-visit"].tap()
        XCTAssertTrue(app.navigationBars["新增到访"].waitForExistence(timeout: 5))
        app.navigationBars["新增到访"].buttons["取消"].tap()
    }

    @MainActor
    func testRestaurantAcquisitionLinkImportIsConfirmedBeforeCreation() throws {
        let app = XCUIApplication()
        app.launchEnvironment = ["TASTEMAP_RESTAURANT_ACQUISITION_UI_TEST": "1"]
        app.launch()
        app.buttons["添加餐厅"].tap()

        let entry = app.buttons["open-restaurant-link-import"]
        scrollUntilVisible(entry, in: app)
        entry.tap()
        XCTAssertTrue(app.navigationBars["粘贴餐厅链接"].waitForExistence(timeout: 5))
        let field = app.textViews["restaurant-link-field"]
        field.tap()
        field.typeText("https://example.com/restaurants/apple")
        app.buttons["resolve-restaurant-link"].tap()
        XCTAssertTrue(app.staticTexts["V1 Apple 链接餐厅"].waitForExistence(timeout: 5))

        let want = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "加入想吃")).firstMatch
        XCTAssertTrue(want.waitForExistence(timeout: 3))
        want.tap()
        segmentedOption("想吃", in: app).tap()
        XCTAssertTrue(app.staticTexts["V1 Apple 链接餐厅"].waitForExistence(timeout: 5))
        openWantToGoDetail(named: "V1 Apple 链接餐厅", in: app)
    }

    @MainActor
    func testRestaurantAcquisitionDeniedLocationStillAllowsManualRestaurant() throws {
        let app = XCUIApplication()
        app.launchEnvironment = ["TASTEMAP_RESTAURANT_ACQUISITION_DENIED_UI_TEST": "1"]
        app.launch()
        app.buttons["添加餐厅"].tap()

        XCTAssertTrue(app.staticTexts["没有定位权限也可以添加"].waitForExistence(timeout: 5))
        let query = app.textFields["restaurant-query-field"]
        scrollUntilVisible(query, in: app)
        XCTAssertTrue(query.exists)
        let entry = app.buttons["open-manual-restaurant"]
        scrollUntilVisible(entry, in: app)
        entry.tap()
        XCTAssertTrue(app.navigationBars["手动添加餐厅"].waitForExistence(timeout: 5))

        app.textFields["manual-restaurant-name"].tap()
        app.textFields["manual-restaurant-name"].typeText("地图外的小摊")
        app.textFields["manual-restaurant-city"].tap()
        app.textFields["manual-restaurant-city"].typeText("杭州")
        app.textFields["manual-restaurant-address"].tap()
        app.textFields["manual-restaurant-address"].typeText("武林路 8 号")
        app.buttons["manual-locate-address"].tap()
        let want = app.buttons["manual-add-want-to-go"]
        scrollUntilVisible(want, in: app)
        XCTAssertTrue(want.waitForExistence(timeout: 5))
        want.tap()

        segmentedOption("想吃", in: app).tap()
        XCTAssertTrue(app.staticTexts["地图外的小摊"].waitForExistence(timeout: 5))
        openWantToGoDetail(named: "地图外的小摊", in: app)
    }

    private func openWantToGoDetail(named name: String, in app: XCUIApplication) {
        let card = app.buttons.containing(.staticText, identifier: name).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        card.tap()
        XCTAssertTrue(app.navigationBars["餐厅详情"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testBottomNavigationSwitchesBetweenThreeMainTabs() throws {
        let app = XCUIApplication()
        app.launchEnvironment["TASTEMAP_UI_TEST_RUNTIME"] = "1"
        app.launch()

        app.buttons["发现"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["discovery-header"].waitForExistence(timeout: 5))

        app.buttons["我的"].tap()
        XCTAssertTrue(app.navigationBars["我的"].waitForExistence(timeout: 5))

        app.buttons["地图"].tap()
        XCTAssertTrue(segmentedOption("去过", in: app).waitForExistence(timeout: 5))
    }

    @MainActor
    func testP3CDiscoveryNativeFlowRestaurantWantSimilarProfileTrendingAndRefresh() throws {
        let app = XCUIApplication()
        app.launchEnvironment = ["TASTEMAP_P3C_DISCOVERY_UI_TEST": "1"]
        app.launch()

        app.buttons["发现"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["discovery-header"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["discovery-primary-following"].exists)
        XCTAssertTrue(app.buttons["discovery-primary-forYou"].exists)
        XCTAssertTrue(app.buttons["discovery-primary-similarTaste"].exists)
        XCTAssertTrue(app.buttons["discovery-primary-latest"].exists)
        XCTAssertTrue(app.buttons["discovery-primary-trending"].exists)
        let restaurant = app.staticTexts["P3-C 发现寿司店"]
        XCTAssertTrue(restaurant.waitForExistence(timeout: 5))
        restaurant.tap()
        XCTAssertTrue(app.navigationBars["餐厅详情"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "只有你明确加入想吃")).firstMatch.exists)
        app.buttons["完成"].tap()

        let want = app.buttons["discovery-want-place:p3c-ui-0"]
        XCTAssertTrue(want.waitForExistence(timeout: 5))
        want.tap()
        XCTAssertTrue(app.staticTexts["已想吃"].waitForExistence(timeout: 5))

        app.buttons["discovery-primary-similarTaste"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "基于 5 家共同评分餐厅")).firstMatch.waitForExistence(timeout: 5))
        app.buttons["同味小林"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["公开主页"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["同味小林"].exists)
        app.buttons["完成"].tap()

        app.buttons["discovery-primary-trending"].tap()
        XCTAssertTrue(segmentedOption("近 7 天", in: app).waitForExistence(timeout: 5))
        segmentedOption("近 30 天", in: app).tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "近 30 天有 8 位用户到访")).firstMatch.waitForExistence(timeout: 5))
        app.swipeDown()
        XCTAssertTrue(app.staticTexts["P3-C 发现寿司店"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testP3CDiscoveryOfflineCacheStillAllowsWantToGo() throws {
        let app = XCUIApplication()
        app.launchEnvironment = [
            "TASTEMAP_P3C_DISCOVERY_UI_TEST": "1",
            "TASTEMAP_P3C_DISCOVERY_OFFLINE_UI_TEST": "1",
        ]
        app.launch()
        app.buttons["发现"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "离线内容")).firstMatch.waitForExistence(timeout: 5))
        let want = app.buttons["discovery-want-place:p3c-ui-0"]
        XCTAssertTrue(want.waitForExistence(timeout: 5))
        want.tap()
        XCTAssertTrue(app.staticTexts["已想吃"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testTask07DiscoveryFiltersReasonsAndViewerActions() throws {
        let app = XCUIApplication()
        app.launchEnvironment = ["TASTEMAP_P3C_DISCOVERY_UI_TEST": "1"]
        app.launch()
        app.buttons["发现"].tap()

        XCTAssertTrue(app.buttons["discovery-city-menu"].waitForExistence(timeout: 5))
        app.buttons["discovery-filters"].tap()
        XCTAssertTrue(app.navigationBars["筛选推荐"].waitForExistence(timeout: 3))
        app.buttons["discovery-rating"].tap()
        app.buttons["4.5 分以上"].tap()
        app.buttons["discovery-filter-done"].tap()
        XCTAssertTrue(app.staticTexts["P3-C 发现寿司店"].waitForExistence(timeout: 5))

        let reasons = app.buttons["discovery-reasons-place:p3c-ui-0"]
        if !reasons.exists { app.swipeUp() }
        XCTAssertTrue(reasons.waitForExistence(timeout: 3))
        reasons.tap()
        XCTAssertTrue(app.staticTexts["当前城市的公开评分样本稳定"].waitForExistence(timeout: 3))

        let record = app.buttons["discovery-record-place:p3c-ui-0"]
        XCTAssertTrue(record.waitForExistence(timeout: 3))
        record.tap()
        XCTAssertTrue(app.navigationBars["新增到访"].waitForExistence(timeout: 3))
        app.buttons["取消"].tap()

        let list = app.buttons["discovery-list-place:p3c-ui-0"]
        XCTAssertTrue(list.waitForExistence(timeout: 3))
        list.tap()
        XCTAssertTrue(app.navigationBars["加入榜单"].waitForExistence(timeout: 3))
        app.buttons["完成"].tap()

        let roulette = app.buttons["discovery-roulette-place:p3c-ui-0"]
        XCTAssertTrue(roulette.waitForExistence(timeout: 3))
        roulette.tap()
        XCTAssertTrue(app.navigationBars["今天吃什么"].waitForExistence(timeout: 5))
        app.buttons["完成"].tap()
    }

    @MainActor
    func testP3DCommunityFeedOpensPublicProfileRestaurantAndSupportsExplicitWantToGo() throws {
        let app = XCUIApplication()
        app.launchEnvironment = ["TASTEMAP_P3D_COMMUNITY_UI_TEST": "1"]
        app.launch()
        app.buttons["发现"].tap()
        XCTAssertTrue(app.buttons["discovery-primary-following"].waitForExistence(timeout: 5))
        app.buttons["discovery-primary-following"].tap()
        XCTAssertTrue(app.buttons["discovery-primary-following"].exists)
        XCTAssertTrue(app.buttons["discovery-primary-latest"].exists)
        XCTAssertTrue(app.staticTexts["云边小馆·湖滨店"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["community-like-visit-p3d-ui-0"].exists)
        let comments = app.buttons["community-comments-visit-p3d-ui-0"]
        XCTAssertTrue(comments.exists)
        comments.tap()
        XCTAssertTrue(app.navigationBars["评论"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.textFields["community-comment-field"].exists)
        app.buttons["完成"].tap()
        keepScreenshot(named: "P3-D Community Feed", of: app)

        app.staticTexts["常去小馆的阿岚"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["公开主页"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["常去小馆的阿岚"].exists)
        app.buttons["完成"].tap()

        app.staticTexts["云边小馆·湖滨店"].tap()
        XCTAssertTrue(app.navigationBars["餐厅详情"].waitForExistence(timeout: 5))
        app.buttons["完成"].tap()

        let want = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "想吃")).firstMatch
        XCTAssertTrue(want.waitForExistence(timeout: 5))
        want.tap()
        XCTAssertTrue(app.staticTexts["已想吃"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testP3DCommunityOfflineFixtureShowsCacheAndStillAllowsLocalWantToGo() throws {
        let app = XCUIApplication()
        app.launchEnvironment = [
            "TASTEMAP_P3D_COMMUNITY_UI_TEST": "1",
            "TASTEMAP_P3D_COMMUNITY_OFFLINE_UI_TEST": "1",
        ]
        app.launch()
        app.buttons["发现"].tap()
        app.buttons["discovery-primary-following"].tap()
        XCTAssertTrue(app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "当前显示最近缓存")
        ).firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["云边小馆·湖滨店"].exists)
        keepScreenshot(named: "P3-D Community Offline Cache", of: app)
    }

    @MainActor
    func testTask07CommunityViewerActionsAndWantActivity() throws {
        let app = XCUIApplication()
        app.launchEnvironment = ["TASTEMAP_P3D_COMMUNITY_UI_TEST": "1"]
        app.launch()
        app.buttons["发现"].tap()
        app.buttons["discovery-primary-following"].tap()
        app.swipeUp()
        XCTAssertTrue(app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "加入了想吃")
        ).firstMatch.waitForExistence(timeout: 5))

        app.swipeDown()
        let record = app.buttons["community-record-place:p3d-ui-0"]
        if !record.exists { app.swipeDown() }
        XCTAssertTrue(record.waitForExistence(timeout: 3))
        record.tap()
        XCTAssertTrue(app.navigationBars["新增到访"].waitForExistence(timeout: 3))
        app.buttons["取消"].tap()

        let list = app.buttons["community-list-place:p3d-ui-0"]
        XCTAssertTrue(list.waitForExistence(timeout: 3))
        list.tap()
        XCTAssertTrue(app.navigationBars["加入榜单"].waitForExistence(timeout: 3))
        app.buttons["完成"].tap()

        let roulette = app.buttons["community-roulette-place:p3d-ui-0"]
        XCTAssertTrue(roulette.waitForExistence(timeout: 3))
        roulette.tap()
        XCTAssertTrue(app.navigationBars["今天吃什么"].waitForExistence(timeout: 5))
        app.buttons["完成"].tap()
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
    func testF1B3SettingsFoundationNavigationAndBackupPrivacyFlow() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-p1d-persistent-offline-fixture",
            "-p1d-reset-persistent-offline-fixture",
        ]
        app.launchEnvironment = [
            "TASTEMAP_P1D_UI_TEST": "1",
            "TASTEMAP_P1D_RESET": "1",
            "TASTEMAP_P3A_PROFILE_UI_TEST": "1",
            "TASTEMAP_F1B3_SETTINGS_UI_TEST": "1",
        ]
        app.launch()

        app.buttons["我的"].tap()
        XCTAssertTrue(app.navigationBars["我的"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["profile-backup-export-button"].exists)

        let settings = app.buttons["profile-settings-entry"]
        scrollUntilVisible(settings, in: app)
        XCTAssertTrue(settings.isHittable)
        settings.tap()
        XCTAssertTrue(app.navigationBars["设置"].waitForExistence(timeout: 5))

        let account = app.buttons["settings-account-entry"]
        XCTAssertTrue(account.waitForExistence(timeout: 3))
        account.tap()
        XCTAssertTrue(app.navigationBars["账户"].waitForExistence(timeout: 3))
        XCTAssertEqual(app.staticTexts["settings-tastemap-user-id"].label, "tm_p3a_ui_fixture")
        let editProfile = app.buttons["settings-edit-profile"]
        XCTAssertTrue(editProfile.exists)
        XCTAssertTrue(app.buttons["settings-sign-out"].exists)
        editProfile.tap()
        XCTAssertTrue(app.navigationBars["编辑资料"].waitForExistence(timeout: 3))
        app.navigationBars["编辑资料"].buttons["取消"].tap()
        app.navigationBars["账户"].buttons["设置"].tap()

        let dataAndBackup = app.buttons["settings-data-backup-entry"]
        XCTAssertTrue(dataAndBackup.waitForExistence(timeout: 3))
        dataAndBackup.tap()
        XCTAssertTrue(app.navigationBars["数据与备份"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["settings-import-data-entry"].exists)
        XCTAssertFalse(app.buttons["恢复我的备份"].exists)
        let export = app.buttons["settings-backup-export-button"]
        XCTAssertTrue(export.waitForExistence(timeout: 3))
        export.tap()

        XCTAssertTrue(app.staticTexts["导出 Backup v1"].waitForExistence(timeout: 5))
        let warning = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "Backup v1 不包含照片原图")
        ).firstMatch
        XCTAssertTrue(warning.exists)
        XCTAssertTrue(app.buttons["生成并分享"].exists)
        app.buttons["取消"].tap()
        XCTAssertFalse(app.buttons["生成并分享"].exists)
        app.navigationBars["数据与备份"].buttons["设置"].tap()

        let sync = app.buttons["settings-sync-entry"]
        scrollUntilVisible(sync, in: app)
        sync.tap()
        XCTAssertTrue(app.navigationBars["同步"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["等待同步"].exists)
        let pendingCount = app.descendants(matching: .any)["settings-sync-pending-count"]
        XCTAssertTrue(pendingCount.exists)
        XCTAssertTrue(pendingCount.label.contains("2") || pendingCount.value as? String == "2")
        app.navigationBars["同步"].buttons["设置"].tap()

        let permissions = app.buttons["settings-permissions-entry"]
        scrollUntilVisible(permissions, in: app)
        permissions.tap()
        XCTAssertTrue(app.navigationBars["权限"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.descendants(matching: .any)["settings-location-permission"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["settings-photo-permission"].exists)
        XCTAssertTrue(app.buttons["settings-open-system-settings"].exists)
        app.navigationBars["权限"].buttons["设置"].tap()

        let about = app.buttons["settings-about-entry"]
        scrollUntilVisible(about, in: app)
        about.tap()
        XCTAssertTrue(app.navigationBars["关于"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.descendants(matching: .any)["settings-app-version"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["settings-build-number"].exists)
    }

    @MainActor
    func testF1C2LegacyImportPreflightDryRunAndDetails() throws {
        let app = launchImportPreflightFixture("legacy")
        openImportPreflight(in: app)

        app.buttons["backup-import-choose-file"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["backup-import-processing"]
            .waitForExistence(timeout: 2))
        let format = app.descendants(matching: .any)["backup-import-source-format"]
        XCTAssertTrue(format.waitForExistence(timeout: 10))
        XCTAssertTrue(format.label.contains("Legacy Web v4") || (format.value as? String)?.contains("Legacy Web v4") == true)
        let photoMessage = app.descendants(matching: .any)["backup-import-photo-message"]
        scrollUntilVisible(photoMessage, in: app)
        XCTAssertTrue(photoMessage.exists)

        let details = app.buttons["backup-import-issues-entry"]
        scrollUntilVisible(details, in: app)
        XCTAssertTrue(details.isHittable)
        details.tap()
        XCTAssertTrue(app.navigationBars["问题详情"].waitForExistence(timeout: 3))
        app.navigationBars["问题详情"].buttons["导入数据"].tap()

        let close = app.buttons["backup-import-close"]
        XCTAssertTrue(close.waitForExistence(timeout: 3))
        close.tap()
        XCTAssertTrue(app.navigationBars["数据与备份"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testF1C2BlockingFixtureCannotContinue() throws {
        let app = launchImportPreflightFixture("blocking")
        openImportPreflight(in: app)

        app.buttons["backup-import-choose-file"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["backup-import-blocking-state"]
            .waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["此文件暂时无法继续导入。"].exists)
        XCTAssertFalse(app.buttons["导入"].exists)
        let details = app.buttons["backup-import-issues-entry"]
        scrollUntilVisible(details, in: app)
        XCTAssertTrue(details.isHittable)
    }

    @MainActor
    func testF1C3DevelopmentMatchingPlanStillRequiresFinalConfirmation() throws {
        let app = launchImportPreflightFixture("legacy")
        openImportPreflight(in: app)

        app.buttons["backup-import-choose-file"].tap()
        let generate = app.buttons["backup-import-generate-plan"]
        scrollUntilVisible(generate, in: app)
        XCTAssertTrue(generate.waitForExistence(timeout: 10))
        generate.tap()

        XCTAssertTrue(app.navigationBars["逐项确认"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.descendants(matching: .any)["backup-import-plan-page"].exists)
        XCTAssertFalse(app.buttons["正式导入"].exists)
        XCTAssertFalse(app.buttons["导入"].exists)

        let skip = app.buttons["backup-import-review-option-restaurant-skip"]
        scrollUntilVisible(skip, in: app)
        XCTAssertTrue(skip.waitForExistence(timeout: 3))
        skip.tap()
        XCTAssertTrue(app.navigationBars["匹配计划"].waitForExistence(timeout: 3))
        let reviewComplete = app.buttons["backup-import-review-complete"]
        scrollUntilVisible(reviewComplete, in: app)
        XCTAssertTrue(reviewComplete.exists)
        XCTAssertFalse(app.buttons["backup-import-confirm-execute"].exists)

        app.buttons["backup-import-close"].tap()
        XCTAssertTrue(app.navigationBars["数据与备份"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testF1C4BackupV1FormalImportCompletesAndShowsLocalResult() throws {
        let app = launchImportPreflightFixture("backup")
        openImportPreflight(in: app)

        app.buttons["backup-import-choose-file"].tap()
        let generate = app.buttons["backup-import-generate-plan"]
        scrollUntilVisible(generate, in: app)
        XCTAssertTrue(generate.waitForExistence(timeout: 10))
        generate.tap()

        XCTAssertTrue(app.navigationBars["匹配计划"].waitForExistence(timeout: 8))
        let reviewComplete = app.buttons["backup-import-review-complete"]
        scrollUntilVisible(reviewComplete, in: app)
        XCTAssertTrue(reviewComplete.waitForExistence(timeout: 8))
        reviewComplete.tap()
        XCTAssertTrue(app.navigationBars["最终确认"].waitForExistence(timeout: 5))
        let photoWarning = app.descendants(matching: .any)["backup-import-final-photo-warning"]
        scrollUntilVisible(photoWarning, in: app)
        XCTAssertTrue(photoWarning.exists)
        let execute = app.buttons["backup-import-confirm-execute"]
        scrollUntilVisible(execute, in: app)
        XCTAssertTrue(execute.isHittable)
        execute.tap()

        XCTAssertTrue(app.descendants(matching: .any)["backup-import-local-success"]
            .waitForExistence(timeout: 15))
        XCTAssertTrue(app.navigationBars["导入结果"].exists)
        let mutationCount = app.descendants(matching: .any)["backup-import-result-mutation-count"]
        scrollUntilVisible(mutationCount, in: app)
        XCTAssertTrue(mutationCount.exists)
        let importAnother = app.buttons["backup-import-another"]
        scrollUntilVisible(importAnother, in: app)
        XCTAssertTrue(importAnother.exists)
        let restaurants = app.buttons["backup-import-result-restaurants"]
        scrollUntilVisible(restaurants, in: app)
        XCTAssertTrue(restaurants.isHittable)
        restaurants.tap()
        XCTAssertTrue(app.navigationBars["去过的餐厅"].waitForExistence(timeout: 8))
        let importedRestaurant = app.staticTexts["F1-C4 Backup v1 餐厅"]
        XCTAssertTrue(importedRestaurant.waitForExistence(timeout: 5))
        importedRestaurant.tap()
        XCTAssertTrue(app.navigationBars["餐厅详情"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testF1C4LegacyReviewCreateImportAndRestaurantNavigation() throws {
        let app = launchImportPreflightFixture("legacy")
        openImportPreflight(in: app)

        app.buttons["backup-import-choose-file"].tap()
        let generate = app.buttons["backup-import-generate-plan"]
        scrollUntilVisible(generate, in: app)
        XCTAssertTrue(generate.waitForExistence(timeout: 10))
        generate.tap()

        XCTAssertTrue(app.navigationBars["逐项确认"].waitForExistence(timeout: 8))
        let create = app.buttons["backup-import-review-option-restaurant-create"]
        scrollUntilVisible(create, in: app)
        XCTAssertTrue(create.waitForExistence(timeout: 5))
        create.tap()

        let reviewComplete = app.buttons["backup-import-review-complete"]
        scrollUntilVisible(reviewComplete, in: app)
        XCTAssertTrue(reviewComplete.waitForExistence(timeout: 5))
        reviewComplete.tap()
        XCTAssertTrue(app.navigationBars["最终确认"].waitForExistence(timeout: 5))
        let execute = app.buttons["backup-import-confirm-execute"]
        scrollUntilVisible(execute, in: app)
        XCTAssertTrue(execute.isHittable)
        execute.tap()

        XCTAssertTrue(app.descendants(matching: .any)["backup-import-local-success"]
            .waitForExistence(timeout: 15))
        let mutationCount = app.descendants(matching: .any)["backup-import-result-mutation-count"]
        XCTAssertTrue(mutationCount.exists)
        let restaurants = app.buttons["backup-import-result-restaurants"]
        scrollUntilVisible(restaurants, in: app)
        XCTAssertTrue(restaurants.isHittable)
        restaurants.tap()
        XCTAssertTrue(app.navigationBars["去过的餐厅"].waitForExistence(timeout: 8))
        let importedRestaurant = app.staticTexts["P1-D 离线验收餐厅"]
        XCTAssertTrue(importedRestaurant.waitForExistence(timeout: 5))
        importedRestaurant.tap()
        XCTAssertTrue(app.navigationBars["餐厅详情"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testF1C4InjectedFailureShowsExistingDataUnchanged() throws {
        let app = launchImportPreflightFixture("failure")
        openImportPreflight(in: app)

        app.buttons["backup-import-choose-file"].tap()
        let generate = app.buttons["backup-import-generate-plan"]
        scrollUntilVisible(generate, in: app)
        XCTAssertTrue(generate.waitForExistence(timeout: 10))
        generate.tap()
        XCTAssertTrue(app.navigationBars["逐项确认"].waitForExistence(timeout: 8))
        let create = app.buttons["backup-import-review-option-restaurant-create"]
        scrollUntilVisible(create, in: app)
        XCTAssertTrue(create.waitForExistence(timeout: 5))
        create.tap()
        let reviewComplete = app.buttons["backup-import-review-complete"]
        scrollUntilVisible(reviewComplete, in: app)
        XCTAssertTrue(reviewComplete.waitForExistence(timeout: 5))
        reviewComplete.tap()
        XCTAssertTrue(app.navigationBars["最终确认"].waitForExistence(timeout: 5))
        let execute = app.buttons["backup-import-confirm-execute"]
        scrollUntilVisible(execute, in: app)
        XCTAssertTrue(execute.isHittable)
        execute.tap()

        XCTAssertTrue(app.descendants(matching: .any)["backup-import-error-message"]
            .waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["你的现有数据保持不变。"].exists)
        XCTAssertTrue(app.buttons["backup-import-reselect"].exists)
    }

    @MainActor
    func testF1C4PreTransactionCancelWritesNothing() throws {
        let app = launchImportPreflightFixture("legacy")
        openImportPreflight(in: app)

        app.buttons["backup-import-choose-file"].tap()
        let cancel = app.buttons["backup-import-cancel"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 2))
        cancel.tap()
        XCTAssertTrue(app.descendants(matching: .any)["backup-import-cancelled-state"]
            .waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["尚未开始事务，没有修改任何数据。"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["backup-import-local-success"].exists)
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
        XCTAssertTrue(segmentedOption("找人", in: app).exists)
        XCTAssertTrue(segmentedOption("好友", in: app).exists)
        XCTAssertTrue(segmentedOption("请求", in: app).exists)
        XCTAssertTrue(segmentedOption("关注", in: app).exists)
        XCTAssertTrue(app.textFields["social-search-field"].exists)
        let inbox = app.buttons["social-collaboration-inbox"]
        XCTAssertTrue(inbox.exists)
        inbox.tap()
        XCTAssertTrue(app.navigationBars["协作收件箱"].waitForExistence(timeout: 3))
        app.buttons["完成"].tap()
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

        segmentedOption("想吃", in: app).tap()
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

        segmentedOption("想吃", in: app).tap()
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
    func testF3ARestaurantDetailMetadataEditAndVisitRefresh() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-p1b-restaurant-detail-fixture"]
        app.launchEnvironment = ["TASTEMAP_F3A_DETAIL_UI_TEST": "1"]
        app.launch()

        segmentedOption("想吃", in: app).tap()
        let card = app.buttons["restaurant-card-11111111-2222-3333-4444-555555555555"]
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        card.tap()
        XCTAssertTrue(app.navigationBars["餐厅详情"].waitForExistence(timeout: 5))

        let metadata = app.staticTexts["restaurant-business-information"]
        scrollUntilVisible(metadata, in: app)
        XCTAssertTrue(metadata.waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["restaurant-call-phone"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["restaurant-opening-hours"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["restaurant-reference-price"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["restaurant-long-term-note"].exists)

        let edit = app.navigationBars["餐厅详情"].buttons["编辑"]
        XCTAssertTrue(edit.isHittable)
        edit.tap()
        XCTAssertTrue(app.navigationBars["编辑餐厅"].waitForExistence(timeout: 5))
        let address = app.textFields["restaurant-edit-address"]
        XCTAssertTrue(address.waitForExistence(timeout: 3))
        address.clearAndType("杭州市上城区任务三新地址 88 号")
        let phone = app.textFields["restaurant-edit-phone"]
        XCTAssertTrue(phone.waitForExistence(timeout: 3))
        phone.clearAndType("+86 571 8765 4321")
        app.buttons["restaurant-edit-save"].tap()

        XCTAssertTrue(app.navigationBars["餐厅详情"].waitForExistence(timeout: 5))
        let updatedPhone = app.staticTexts["+86 571 8765 4321"]
        scrollUntilVisible(updatedPhone, in: app)
        XCTAssertTrue(updatedPhone.waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["杭州市上城区任务三新地址 88 号"].exists)

        app.buttons["restaurant-detail-add-visit"].tap()
        XCTAssertTrue(app.navigationBars["新增到访"].waitForExistence(timeout: 5))
        app.buttons["visit-editor-save"].tap()
        XCTAssertTrue(app.staticTexts["restaurant-status-visited"].waitForExistence(timeout: 5))
        let visitCount = app.staticTexts["1 次"]
        scrollUntilVisible(visitCount, in: app)
        XCTAssertTrue(visitCount.waitForExistence(timeout: 3))
    }

    @MainActor
    func testRestaurantParityActionsShareHookAndConfirmedDelete() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-p1b-restaurant-detail-fixture"]
        app.launchEnvironment = ["TASTEMAP_F3A_DETAIL_UI_TEST": "1"]
        app.launch()

        segmentedOption("想吃", in: app).tap()
        let card = app.buttons["restaurant-card-11111111-2222-3333-4444-555555555555"]
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        card.tap()
        XCTAssertTrue(app.navigationBars["餐厅详情"].waitForExistence(timeout: 5))

        let share = app.buttons["restaurant-action-share"]
        scrollUntilVisible(share, in: app)
        XCTAssertTrue(share.exists)
        XCTAssertTrue(app.buttons["restaurant-action-record-visit"].exists)
        XCTAssertTrue(app.buttons["restaurant-action-want-to-go"].exists)
        XCTAssertTrue(app.buttons["restaurant-action-edit"].exists)
        XCTAssertTrue(app.buttons["restaurant-detail-add-to-list"].exists)
        XCTAssertTrue(app.buttons["restaurant-action-roulette"].exists)
        XCTAssertTrue(app.buttons["restaurant-action-more"].exists)
        XCTAssertFalse(share.isEnabled)
        XCTAssertTrue(app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "至少公开一次到访后，才可生成餐厅公开链接")
        ).firstMatch.exists)

        app.buttons["restaurant-action-more"].tap()
        XCTAssertTrue(app.buttons["复制餐厅名"].waitForExistence(timeout: 2))
        app.buttons["复制餐厅名"].tap()

        app.buttons["restaurant-action-more"].tap()
        let delete = app.buttons["删除餐厅"]
        XCTAssertTrue(delete.waitForExistence(timeout: 2))
        delete.tap()
        let confirm = app.buttons["restaurant-delete-confirm"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 3))
        confirm.firstMatch.tap()

        XCTAssertFalse(app.navigationBars["餐厅详情"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["P1-B 想吃餐厅"].exists)
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

        let twoVisits = app.staticTexts["2 条"]
        scrollUntilVisible(twoVisits, in: app)
        XCTAssertTrue(twoVisits.waitForExistence(timeout: 5))
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

        segmentedOption("想吃", in: app).tap()
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
        // P4-H intentionally limits Free visits to three new photos. Keep this
        // P2-B flow on the Free contract while still covering multi-photo
        // persistence and independent deletion.
        for _ in 0..<3 {
            scrollUntilVisible(importButton, in: app)
            importButton.tap()
            XCTAssertTrue(app.staticTexts["本机"].waitForExistence(timeout: 5))
        }
        XCTAssertTrue(app.staticTexts["3/3"].waitForExistence(timeout: 5))
        app.buttons["visit-editor-save"].tap()

        app.terminate()
        app.launchArguments = ["-p1d-persistent-offline-fixture"]
        app.launchEnvironment = [
            "TASTEMAP_P1D_UI_TEST": "1",
            "TASTEMAP_P2B_UI_TEST": "1",
        ]
        app.launch()
        let markers = app.otherElements.matching(
            NSPredicate(format: "identifier == 'restaurant-map-marker-11111111-2222-3333-4444-555555555555'")
        )
        XCTAssertTrue(markers.firstMatch.waitForExistence(timeout: 5))
        markers.element(boundBy: max(0, markers.count - 1)).tap()
        XCTAssertTrue(app.navigationBars["餐厅详情"].waitForExistence(timeout: 5))
        app.swipeUp()
        XCTAssertTrue(app.staticTexts["3 张"].waitForExistence(timeout: 5))
        let photo = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH 'restaurant-photo-'")
        ).firstMatch
        XCTAssertTrue(photo.waitForExistence(timeout: 5))
        photo.tap()
        XCTAssertTrue(app.navigationBars["1 / 3"].waitForExistence(timeout: 5))
        app.buttons["完成"].tap()

        app.swipeUp()
        let firstVisit = app.staticTexts["第 1 次"]
        XCTAssertTrue(firstVisit.waitForExistence(timeout: 5))
        firstVisit.tap()
        XCTAssertTrue(app.navigationBars["编辑到访"].waitForExistence(timeout: 5))
        for _ in 0..<3 {
            let deletePhoto = app.buttons["删除照片"].firstMatch
            scrollUntilVisible(deletePhoto, in: app)
            XCTAssertTrue(deletePhoto.waitForExistence(timeout: 5))
            deletePhoto.tap()
        }
        app.buttons["visit-editor-save"].tap()
        let galleryTitle = app.staticTexts["照片"]
        for _ in 0..<12 where !galleryTitle.isHittable {
            app.swipeDown()
        }
        XCTAssertTrue(galleryTitle.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["餐厅图标"].waitForExistence(timeout: 5))
        XCTAssertEqual(
            app.buttons.matching(
                NSPredicate(format: "identifier BEGINSWITH 'restaurant-photo-'")
            ).count,
            0
        )
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

        let note = app.descendants(matching: .any)["visit-editor-note"]
        scrollUntilVisible(note, in: app)
        note.tap()
        note.typeText("P2-G 完整离线记录")
        let overall = app.buttons["4.5 星"]
        scrollUntilVisible(overall, in: app)
        overall.tap()

        segmentedOption("外卖", in: app).tap()
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

        let spend = app.textFields["visit-editor-spend"]
        scrollUntilVisible(spend, in: app)
        spend.tap()
        spend.typeText("128")

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

        selectPicker("visit-editor-visibility", option: "公开", in: app)
        app.buttons["visit-editor-save"].tap()

        XCTAssertTrue(app.staticTexts["restaurant-status-visited"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["1 张"].waitForExistence(timeout: 5))
        scrollUntilVisible(app.staticTexts["P2-G 招牌菜"], in: app)
        XCTAssertTrue(app.staticTexts["P2-G 招牌菜"].exists)
        let companions = app.staticTexts["visit-history-companions"]
        scrollUntilVisible(companions, in: app)
        XCTAssertTrue(companions.label.contains("P2-G 饭搭子"))
        XCTAssertTrue(app.staticTexts["visit-history-recommendation-source"].label.contains("P2-G 推荐来源"))
        XCTAssertTrue(app.descendants(matching: .any)["restaurant-detailed-rating-value"].exists)

        app.terminate()
        app.launchArguments = ["-p1d-persistent-offline-fixture"]
        app.launchEnvironment = [
            "TASTEMAP_P1D_UI_TEST": "1",
            "TASTEMAP_P2B_UI_TEST": "1",
        ]
        app.launch()
        let markers = app.otherElements.matching(
            NSPredicate(format: "identifier == 'restaurant-map-marker-11111111-2222-3333-4444-555555555555'")
        )
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
    func testTask04DoubleTapSaveCreatesOnlyOneVisit() throws {
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
        let save = app.buttons["visit-editor-save"]
        XCTAssertTrue(save.waitForExistence(timeout: 3))
        save.doubleTap()

        XCTAssertTrue(app.navigationBars["餐厅详情"].waitForExistence(timeout: 5))
        scrollUntilVisible(app.staticTexts["第 1 次"], in: app)
        XCTAssertTrue(app.staticTexts["第 1 次"].exists)
        XCTAssertFalse(app.staticTexts["第 2 次"].exists)
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

        let markers = app.otherElements.matching(
            NSPredicate(format: "identifier == 'restaurant-map-marker-11111111-2222-3333-4444-555555555555'")
        )
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
            NSPredicate(format: "identifier == 'restaurant-map-marker-11111111-2222-3333-4444-555555555555'")
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
            NSPredicate(format: "identifier == 'restaurant-map-marker-11111111-2222-3333-4444-555555555555'")
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
            NSPredicate(format: "identifier == 'restaurant-map-marker-11111111-2222-3333-4444-555555555555'")
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
            NSPredicate(format: "identifier == 'restaurant-map-marker-11111111-2222-3333-4444-555555555555'")
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
            NSPredicate(format: "identifier == 'restaurant-map-marker-11111111-2222-3333-4444-555555555555'")
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
    func testP4ATasteProfilePageAndIndependentPoster() throws {
        let app = XCUIApplication()
        app.launchEnvironment = ["TASTEMAP_P4A_ANALYSIS_UI_TEST": "1"]
        app.launch()

        app.buttons["我的"].tap()
        XCTAssertTrue(app.navigationBars["我的"].waitForExistence(timeout: 5))
        let entry = app.buttons["profile-taste-analysis-entry"]
        scrollUntilVisible(entry, in: app)
        XCTAssertTrue(entry.isHittable)
        entry.tap()

        XCTAssertTrue(app.navigationBars["口味档案"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["你真正喜欢什么"].waitForExistence(timeout: 5))
        keepScreenshot(named: "P4-A Taste Profile", of: app)

        let restaurantStories = app.staticTexts["代表你的几家店"]
        scrollUntilVisible(restaurantStories, in: app)
        XCTAssertTrue(restaurantStories.exists)

        let share = app.buttons["taste-profile-share-toolbar"]
        XCTAssertTrue(share.waitForExistence(timeout: 5))
        share.tap()
        XCTAssertTrue(app.navigationBars["分享海报"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.images["analysis-poster-preview"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["analysis-poster-save"].exists)
        XCTAssertTrue(app.buttons["analysis-poster-system-share"].exists)
        keepScreenshot(named: "P4-A 9x16 Poster", of: app)
    }

    @MainActor
    func testP4BDiningCompanionAnalysisRefreshAndPoster() throws {
        let app = XCUIApplication()
        app.launchEnvironment = ["TASTEMAP_P4B_COMPANION_UI_TEST": "1"]
        app.launch()

        app.buttons["我的"].tap()
        XCTAssertTrue(app.navigationBars["我的"].waitForExistence(timeout: 5))
        let entry = app.buttons["profile-companion-analysis-entry"]
        scrollUntilVisible(entry, in: app)
        // Move the card clear of the custom bottom navigation before tapping.
        // On iOS 26 XCTest can report a partially covered card as hittable even
        // though the synthesized tap is consumed by the navigation overlay.
        app.swipeUp(velocity: .slow)
        XCTAssertTrue(entry.isHittable)
        entry.tap()

        XCTAssertTrue(app.navigationBars["饭搭子分析"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.descendants(matching: .any)["companion-analysis-overview"].exists)
        let lead = app.buttons["companion-analysis-lead"]
        XCTAssertTrue(lead.waitForExistence(timeout: 5))
        lead.tap()

        XCTAssertTrue(app.navigationBars["你和 小林"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["14 次"].waitForExistence(timeout: 5))
        let foods = app.staticTexts["最常一起吃什么"]
        scrollUntilVisible(foods, in: app)
        XCTAssertTrue(foods.exists)
        let restaurants = app.staticTexts["最常去的餐厅"]
        scrollUntilVisible(restaurants, in: app)
        XCTAssertTrue(restaurants.exists)
        keepScreenshot(named: "P4-B Companion Detail", of: app)

        let restaurant = app.staticTexts["山葵小料理"].firstMatch
        scrollUntilVisible(restaurant, in: app)
        XCTAssertTrue(restaurant.waitForExistence(timeout: 5))
        restaurant.tap()
        XCTAssertTrue(app.navigationBars["餐厅详情"].waitForExistence(timeout: 5))
        let closeDetail = app.buttons["companion-restaurant-detail-close"]
        XCTAssertTrue(closeDetail.waitForExistence(timeout: 5))
        closeDetail.tap()
        XCTAssertTrue(closeDetail.waitForNonExistence(timeout: 8))

        XCTAssertTrue(app.navigationBars["你和 小林"].waitForExistence(timeout: 8))
        let fixtureMutation = app.buttons["companion-analysis-fixture-add-visit"]
        XCTAssertTrue(fixtureMutation.waitForExistence(timeout: 5))
        fixtureMutation.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["companion-analysis-fixture-mutation-result"]
                .waitForExistence(timeout: 8)
        )
        app.navigationBars["你和 小林"].buttons["饭搭子分析"].tap()
        XCTAssertTrue(app.navigationBars["饭搭子分析"].waitForExistence(timeout: 8))
        XCTAssertTrue(lead.waitForExistence(timeout: 8))
        lead.tap()
        XCTAssertTrue(app.navigationBars["你和 小林"].waitForExistence(timeout: 8))
        let updated = app.staticTexts["15 次"]
        scrollUntilVisible(updated, in: app)
        XCTAssertTrue(updated.waitForExistence(timeout: 8))

        let share = app.buttons["companion-analysis-share-toolbar"]
        XCTAssertTrue(share.waitForExistence(timeout: 5))
        share.tap()
        XCTAssertTrue(app.navigationBars["分享海报"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.images["analysis-poster-preview"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["analysis-poster-save"].exists)
        XCTAssertTrue(app.buttons["analysis-poster-system-share"].exists)
        keepScreenshot(named: "P4-B 9x16 Poster", of: app)
    }

    @MainActor
    func testP4CRecommendationSourceAnalysisEvidencePosterAndRefresh() throws {
        let app = XCUIApplication()
        app.launchEnvironment = ["TASTEMAP_P4C_SOURCE_UI_TEST": "1"]
        app.launch()

        app.buttons["我的"].tap()
        XCTAssertTrue(app.navigationBars["我的"].waitForExistence(timeout: 5))
        let entry = app.buttons["profile-recommendation-source-analysis-entry"]
        scrollUntilVisible(entry, in: app)
        XCTAssertTrue(entry.isHittable)
        entry.tap()

        XCTAssertTrue(app.navigationBars["推荐来源分析"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.descendants(matching: .any)["recommendation-source-analysis-overview"].exists)
        XCTAssertTrue(app.staticTexts["最常使用来源"].waitForExistence(timeout: 5))
        let bestLabel = app.staticTexts["最靠谱推荐来源"]
        scrollUntilVisible(bestLabel, in: app)
        XCTAssertTrue(bestLabel.exists)
        let worstLabel = app.staticTexts["最坑推荐来源"]
        scrollUntilVisible(worstLabel, in: app)
        XCTAssertTrue(worstLabel.exists)
        XCTAssertTrue(app.staticTexts["小林的私藏清单"].exists)
        XCTAssertTrue(app.staticTexts["深夜刷到的收藏夹"].exists)
        keepScreenshot(named: "P4-C Recommendation Source Overview", of: app)

        let sourceCard = app.descendants(matching: .any)[
            "recommendation-source-card-00000000-0000-0000-0000-000000004700"
        ]
        scrollUntilVisible(sourceCard, in: app)
        XCTAssertTrue(sourceCard.waitForExistence(timeout: 5))
        sourceCard.tap()

        XCTAssertTrue(app.navigationBars["小林的私藏清单"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["评分表现"].waitForExistence(timeout: 5))
        let restaurant = app.descendants(matching: .any)[
            "recommendation-source-restaurant-00000000-0000-0000-0000-000000004801"
        ]
        scrollUntilVisible(restaurant, in: app)
        XCTAssertTrue(restaurant.waitForExistence(timeout: 5))
        restaurant.tap()
        XCTAssertTrue(app.navigationBars["餐厅详情"].waitForExistence(timeout: 5))
        let closeRestaurant = app.buttons["recommendation-source-restaurant-detail-close"]
        XCTAssertTrue(closeRestaurant.waitForExistence(timeout: 5))
        closeRestaurant.tap()
        XCTAssertTrue(closeRestaurant.waitForNonExistence(timeout: 8))

        app.navigationBars["小林的私藏清单"].buttons["推荐来源分析"].tap()
        XCTAssertTrue(app.navigationBars["推荐来源分析"].waitForExistence(timeout: 8))
        let share = app.buttons["recommendation-source-share-toolbar"]
        XCTAssertTrue(share.waitForExistence(timeout: 5))
        share.tap()
        XCTAssertTrue(app.navigationBars["分享海报"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.images["analysis-poster-preview"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["analysis-poster-save"].exists)
        let systemShare = app.buttons["analysis-poster-system-share"]
        XCTAssertTrue(systemShare.exists)
        keepScreenshot(named: "P4-C 9x16 Poster", of: app)
        systemShare.tap()
        let activityList = app.otherElements["ActivityListView"]
        XCTAssertTrue(activityList.waitForExistence(timeout: 8))
        let closeSystemShare = activityList.buttons["关闭"]
        XCTAssertTrue(closeSystemShare.waitForExistence(timeout: 5))
        closeSystemShare.tap()
        XCTAssertTrue(activityList.waitForNonExistence(timeout: 8))
        let posterClose = app.navigationBars["分享海报"].buttons["关闭"]
        XCTAssertTrue(posterClose.waitForExistence(timeout: 8))
        posterClose.tap()

        scrollUntilVisible(sourceCard, in: app)
        sourceCard.tap()
        XCTAssertTrue(app.navigationBars["小林的私藏清单"].waitForExistence(timeout: 8))
        let mutate = app.buttons["recommendation-source-fixture-change-rating"]
        XCTAssertTrue(mutate.waitForExistence(timeout: 5))
        mutate.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["recommendation-source-fixture-result"]
                .waitForExistence(timeout: 8)
        )
        app.navigationBars["小林的私藏清单"].buttons["推荐来源分析"].tap()
        XCTAssertTrue(app.navigationBars["推荐来源分析"].waitForExistence(timeout: 8))
        scrollUntilVisible(sourceCard, in: app)
        sourceCard.tap()
        XCTAssertTrue(app.navigationBars["小林的私藏清单"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["4.3 / 5"].waitForExistence(timeout: 8))
    }

    @MainActor
    func testP4DMonthlyRecapHistoryRestaurantPosterShareAndRefresh() throws {
        let app = XCUIApplication()
        app.launchEnvironment = ["TASTEMAP_P4D_MONTHLY_UI_TEST": "1"]
        app.launch()

        app.buttons["我的"].tap()
        XCTAssertTrue(app.navigationBars["我的"].waitForExistence(timeout: 5))
        let entry = app.buttons["profile-monthly-recap-entry"]
        scrollUntilVisible(entry, in: app)
        // The custom bottom navigation can overlap the first visible pixels of a
        // deeply-scrolled card. Move the card fully above that safe-area inset
        // before tapping so the test exercises the NavigationLink itself.
        app.swipeUp(velocity: .slow)
        XCTAssertTrue(entry.isHittable)
        entry.tap()

        XCTAssertTrue(app.navigationBars["本月回顾"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.descendants(matching: .any)["monthly-recap-analysis-page"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["monthly-recap-core-statistics"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["12 次用餐，5 家餐厅"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["本月餐桌主角"].waitForExistence(timeout: 5))
        keepScreenshot(named: "P4-D Monthly Recap Current", of: app)

        let favorite = app.buttons["monthly-recap-favorite"]
        scrollUntilVisible(favorite, in: app)
        XCTAssertTrue(favorite.waitForExistence(timeout: 5))
        favorite.tap()
        XCTAssertTrue(app.navigationBars["餐厅详情"].waitForExistence(timeout: 8))
        app.navigationBars["餐厅详情"].buttons["本月回顾"].tap()
        XCTAssertTrue(app.navigationBars["本月回顾"].waitForExistence(timeout: 8))

        let share = app.buttons["monthly-recap-share-toolbar"]
        XCTAssertTrue(share.waitForExistence(timeout: 5))
        share.tap()
        XCTAssertTrue(app.navigationBars["分享海报"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.images["analysis-poster-preview"].waitForExistence(timeout: 12))
        XCTAssertTrue(app.buttons["analysis-poster-save"].exists)
        let systemShare = app.buttons["analysis-poster-system-share"]
        XCTAssertTrue(systemShare.exists)
        keepScreenshot(named: "P4-D 9x16 Monthly Poster", of: app)
        systemShare.tap()
        let activityList = app.otherElements["ActivityListView"]
        XCTAssertTrue(activityList.waitForExistence(timeout: 8))
        let closeSystemShare = activityList.buttons["关闭"]
        XCTAssertTrue(closeSystemShare.waitForExistence(timeout: 5))
        closeSystemShare.tap()
        XCTAssertTrue(activityList.waitForNonExistence(timeout: 8))
        app.navigationBars["分享海报"].buttons["关闭"].tap()

        let previous = app.buttons["monthly-recap-previous-month"]
        XCTAssertTrue(previous.waitForExistence(timeout: 8))
        previous.tap()
        XCTAssertTrue(app.staticTexts["2026 年 7 月"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["历史月份"].exists)
        keepScreenshot(named: "P4-D Monthly Recap Previous", of: app)
        let next = app.buttons["monthly-recap-next-month"]
        XCTAssertTrue(next.waitForExistence(timeout: 5))
        next.tap()
        XCTAssertTrue(app.staticTexts["截至今天"].waitForExistence(timeout: 8))

        let addVisit = app.buttons["monthly-recap-fixture-add-visit"]
        scrollUntilVisible(addVisit, in: app)
        XCTAssertTrue(addVisit.waitForExistence(timeout: 5))
        addVisit.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["monthly-recap-fixture-result"]
                .waitForExistence(timeout: 8)
        )
        XCTAssertTrue(app.staticTexts["13 次用餐，5 家餐厅"].waitForExistence(timeout: 8))
    }

    @MainActor
    func testP4EAnnualRecapHistoryRestaurantJourneyPosterShareAndRefresh() throws {
        let app = XCUIApplication()
        app.launchEnvironment = ["TASTEMAP_P4E_ANNUAL_UI_TEST": "1"]
        app.launch()

        app.buttons["我的"].tap()
        XCTAssertTrue(app.navigationBars["我的"].waitForExistence(timeout: 5))
        let entry = app.buttons["profile-annual-recap-entry"]
        scrollUntilVisible(entry, in: app)
        app.swipeUp(velocity: .slow)
        XCTAssertTrue(entry.waitForExistence(timeout: 5))
        XCTAssertTrue(entry.isHittable)
        entry.tap()

        XCTAssertTrue(app.navigationBars["年度回顾"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any)["annual-recap-analysis-page"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["annual-recap-core-statistics"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any)["annual-recap-hero"].exists)
        keepScreenshot(named: "P4-E Annual Recap Current", of: app)

        let favorite = app.buttons["annual-recap-favorite"]
        scrollUntilVisible(favorite, in: app)
        XCTAssertTrue(favorite.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["同时也是年度最常去"].exists)
        favorite.tap()
        XCTAssertTrue(app.navigationBars["餐厅详情"].waitForExistence(timeout: 8))
        app.navigationBars["餐厅详情"].buttons["年度回顾"].tap()
        XCTAssertTrue(app.navigationBars["年度回顾"].waitForExistence(timeout: 8))

        let journey = app.descendants(matching: .any)["annual-recap-taste-journey"]
        for _ in 0..<8 where !journey.exists {
            app.swipeDown(velocity: .slow)
        }
        XCTAssertTrue(journey.waitForExistence(timeout: 6))
        XCTAssertTrue(app.staticTexts["年度味觉轨迹"].exists)

        let share = app.buttons["annual-recap-share-toolbar"]
        XCTAssertTrue(share.waitForExistence(timeout: 5))
        share.tap()
        XCTAssertTrue(app.navigationBars["分享海报"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.images["analysis-poster-preview"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["analysis-poster-save"].exists)
        let systemShare = app.buttons["analysis-poster-system-share"]
        XCTAssertTrue(systemShare.exists)
        keepScreenshot(named: "P4-E 9x16 Annual Poster", of: app)
        systemShare.tap()
        let activityList = app.otherElements["ActivityListView"]
        XCTAssertTrue(activityList.waitForExistence(timeout: 8))
        let closeSystemShare = activityList.buttons["关闭"]
        XCTAssertTrue(closeSystemShare.waitForExistence(timeout: 5))
        closeSystemShare.tap()
        XCTAssertTrue(activityList.waitForNonExistence(timeout: 8))
        app.navigationBars["分享海报"].buttons["关闭"].tap()

        let previous = app.buttons["annual-recap-previous-year"]
        for _ in 0..<10 where !previous.exists {
            app.swipeDown(velocity: .slow)
        }
        XCTAssertTrue(previous.waitForExistence(timeout: 8))
        previous.tap()
        let previousYear = Calendar.current.component(.year, from: .now) - 1
        XCTAssertTrue(app.staticTexts["\(previousYear) 年"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["历史年度"].exists)
        keepScreenshot(named: "P4-E Annual Recap Previous", of: app)

        let next = app.buttons["annual-recap-next-year"]
        XCTAssertTrue(next.waitForExistence(timeout: 5))
        next.tap()
        XCTAssertTrue(app.staticTexts["截至今天"].waitForExistence(timeout: 10))

        let visitCount = app.staticTexts["annual-recap-visit-count"]
        scrollUntilVisible(visitCount, in: app)
        XCTAssertTrue(visitCount.waitForExistence(timeout: 5))
        let visitCountBeforeInsertion = visitCount.label

        let addVisit = app.buttons["annual-recap-fixture-add-visit"]
        for _ in 0..<8 where !addVisit.exists {
            app.swipeDown(velocity: .slow)
        }
        XCTAssertTrue(addVisit.waitForExistence(timeout: 5))
        addVisit.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["annual-recap-fixture-result"]
                .waitForExistence(timeout: 8)
        )
        scrollUntilVisible(visitCount, in: app)
        XCTAssertTrue(visitCount.waitForExistence(timeout: 5))
        XCTAssertNotEqual(visitCount.label, visitCountBeforeInsertion)
    }

    @MainActor
    func testP4FOwnRestaurantListCreateAddReorderEditRemovePublicAndRestart() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-p1d-persistent-offline-fixture", "-p1d-reset-persistent-offline-fixture"]
        app.launchEnvironment = [
            "TASTEMAP_P1D_UI_TEST": "1", "TASTEMAP_P1D_RESET": "1",
            "TASTEMAP_P4F_LISTS_UI_TEST": "1",
        ]
        app.launch()

        app.buttons["我的"].tap()
        let entry = app.buttons["profile-restaurant-lists-entry"]
        scrollUntilVisible(entry, in: app)
        XCTAssertTrue(entry.waitForExistence(timeout: 5))
        entry.tap()
        XCTAssertTrue(app.navigationBars["我的榜单"].waitForExistence(timeout: 5))
        app.buttons["新建"].tap()
        let title = app.textFields["restaurant-list-title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        title.tap()
        title.typeText("P4-F 周末会再去")
        let description = app.textFields["restaurant-list-description"]
        description.tap()
        description.typeText("真实餐厅榜单 UI E2E")
        app.buttons["restaurant-list-save"].tap()
        XCTAssertTrue(app.staticTexts["P4-F 周末会再去"].waitForExistence(timeout: 5))
        app.staticTexts["P4-F 周末会再去"].tap()

        let add = app.buttons["restaurant-list-add-restaurants"]
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        add.tap()
        let restaurantIDs = [
            "11111111-2222-3333-4444-555555555555",
            "00000000-0000-0000-0000-000000008001",
            "00000000-0000-0000-0000-000000008002",
            "00000000-0000-0000-0000-000000008003",
            "00000000-0000-0000-0000-000000008004",
        ]
        for id in restaurantIDs {
            let button = app.buttons["restaurant-list-add-\(id)"]
            scrollUntilVisible(button, in: app)
            XCTAssertTrue(button.waitForExistence(timeout: 3))
            button.tap()
        }
        app.navigationBars["添加餐厅"].buttons["完成"].tap()
        XCTAssertTrue(app.staticTexts["P4-F 小满食堂"].waitForExistence(timeout: 5))

        app.buttons["restaurant-list-edit-mode"].tap()
        let first = app.buttons["restaurant-list-item-apple_maps:apple-ui-test-p1d"]
        let last = app.buttons["restaurant-list-item-apple_maps:apple-p4f-ui-4"]
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        scrollUntilVisible(last, in: app)
        first.coordinate(withNormalizedOffset: CGVector(dx: 0.88, dy: 0.5))
            .press(forDuration: 0.9, thenDragTo: last.coordinate(withNormalizedOffset: CGVector(dx: 0.88, dy: 0.75)))
        app.buttons["restaurant-list-edit-mode"].tap()

        app.buttons["restaurant-list-settings"].tap()
        let editedTitle = app.textFields["restaurant-list-title"]
        editedTitle.tap()
        editedTitle.clearAndType("P4-F 杭州周末 Top 4")
        let visibility = app.buttons["restaurant-list-visibility"]
        XCTAssertTrue(visibility.waitForExistence(timeout: 3))
        visibility.tap()
        app.buttons["公开"].tap()
        app.buttons["restaurant-list-save"].tap()
        let updatedTitle = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "P4-F 杭州周末 Top 4")
        ).firstMatch
        XCTAssertTrue(updatedTitle.waitForExistence(timeout: 5))

        let remove = app.buttons["restaurant-list-item-apple_maps:apple-p4f-ui-2"]
        scrollUntilVisible(remove, in: app)
        remove.swipeLeft()
        XCTAssertTrue(app.buttons["移除"].waitForExistence(timeout: 3))
        app.buttons["移除"].tap()
        XCTAssertTrue(remove.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.buttons["分享榜单"].exists)
        keepScreenshot(named: "P4-F Own Public Ranking", of: app)

        app.terminate()
        app.launchArguments = ["-p1d-persistent-offline-fixture"]
        app.launchEnvironment = ["TASTEMAP_P1D_UI_TEST": "1", "TASTEMAP_P4F_LISTS_UI_TEST": "1"]
        app.launch()
        app.buttons["我的"].tap()
        let reopenedEntry = app.buttons["profile-restaurant-lists-entry"]
        scrollUntilVisible(reopenedEntry, in: app)
        XCTAssertTrue(reopenedEntry.waitForExistence(timeout: 5))
        reopenedEntry.tap()
        XCTAssertTrue(app.navigationBars["我的榜单"].waitForExistence(timeout: 5))
        // SwiftData has saved synchronously, but under a full two-runner UI
        // sweep the relaunched overview can materialize its @Query later than
        // the navigation bar. Wait for the persisted row itself.
        XCTAssertTrue(app.staticTexts["P4-F 杭州周末 Top 4"].waitForExistence(timeout: 15))
        app.staticTexts["P4-F 杭州周末 Top 4"].tap()
        XCTAssertFalse(app.staticTexts["P4-F 雨巷火锅"].exists)
        XCTAssertTrue(app.staticTexts["P4-F 小满食堂"].exists)
    }

    @MainActor
    func testP4FPublicProfileListRestaurantWantToGoAndVisibilityRevocation() throws {
        let app = XCUIApplication()
        app.launchEnvironment = [
            "TASTEMAP_P3D_COMMUNITY_UI_TEST": "1", "TASTEMAP_P4F_LISTS_UI_TEST": "1",
        ]
        app.launch()
        app.buttons["发现"].tap()
        app.buttons["discovery-primary-following"].tap()
        XCTAssertTrue(app.staticTexts["常去小馆的阿岚"].firstMatch.waitForExistence(timeout: 5))
        app.staticTexts["常去小馆的阿岚"].firstMatch.tap()
        let publicList = app.buttons["public-restaurant-list-p4f-public-ui-list"]
        scrollUntilVisible(publicList, in: app)
        XCTAssertTrue(publicList.waitForExistence(timeout: 5))
        publicList.tap()
        XCTAssertTrue(app.navigationBars["P4-F 阿岚的杭州小馆"].waitForExistence(timeout: 5))
        let restaurant = app.buttons["public-list-restaurant-apple_maps:p4f-public-1"]
        XCTAssertTrue(restaurant.waitForExistence(timeout: 5))
        restaurant.tap()
        XCTAssertTrue(app.navigationBars["餐厅详情"].waitForExistence(timeout: 5))
        let wantToGo = app.buttons["discovery-detail-want-apple_maps:p4f-public-1"]
        XCTAssertTrue(wantToGo.waitForExistence(timeout: 5))
        wantToGo.tap()
        keepScreenshot(named: "P4-F Public List To Want To Go", of: app)

        app.terminate()
        app.launchEnvironment = [
            "TASTEMAP_P3D_COMMUNITY_UI_TEST": "1", "TASTEMAP_P4F_LISTS_PRIVATE_UI_TEST": "1",
        ]
        app.launch()
        app.buttons["发现"].tap()
        app.buttons["discovery-primary-following"].tap()
        app.staticTexts["常去小馆的阿岚"].firstMatch.tap()
        let revoked = app.staticTexts["这些榜单已经不可查看。"]
        scrollUntilVisible(revoked, in: app)
        XCTAssertTrue(revoked.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["public-restaurant-list-p4f-public-ui-list"].exists)
    }

    @MainActor
    func testP4GRouletteFilterSpinResultDetailRerollAndOfflineRestart() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-p1d-persistent-offline-fixture", "-p1d-reset-persistent-offline-fixture"]
        app.launchEnvironment = [
            "TASTEMAP_P1D_UI_TEST": "1", "TASTEMAP_P1D_RESET": "1",
            "TASTEMAP_P4G_ROULETTE_UI_TEST": "1",
        ]
        app.launch()

        openP4GRoulette(in: app)
        XCTAssertTrue(app.staticTexts["roulette-candidate-count"].label.contains("8"))
        XCTAssertTrue(app.staticTexts["roulette-offline-note"].exists)

        app.buttons["roulette-filter-open"].tap()
        XCTAssertTrue(app.navigationBars["候选条件"].waitForExistence(timeout: 5))
        segmentedOption("想吃", in: app).tap()
        app.navigationBars["候选条件"].buttons["完成"].tap()
        XCTAssertTrue(app.staticTexts["roulette-candidate-count"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["roulette-candidate-count"].label.contains("4"))

        let spin = app.buttons["roulette-spin"]
        XCTAssertTrue(spin.waitForExistence(timeout: 5))
        spin.tap()
        let firstResult = app.staticTexts["roulette-result-name"]
        XCTAssertTrue(firstResult.waitForExistence(timeout: 8))
        let firstName = firstResult.label
        XCTAssertFalse(firstName.isEmpty)
        keepScreenshot(named: "P4-G Roulette Result", of: app)

        app.buttons["roulette-open-restaurant"].tap()
        XCTAssertTrue(app.navigationBars["餐厅详情"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts[firstName].exists)
        app.navigationBars["餐厅详情"].buttons.firstMatch.tap()
        XCTAssertTrue(app.navigationBars["今天吃什么"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["roulette-result-name"].label, firstName)

        app.buttons["roulette-reroll"].tap()
        XCTAssertTrue(app.staticTexts["roulette-result-name"].waitForExistence(timeout: 8))
        XCTAssertNotEqual(app.staticTexts["roulette-result-name"].label, firstName)

        app.terminate()
        app.launchArguments = ["-p1d-persistent-offline-fixture"]
        app.launchEnvironment = [
            "TASTEMAP_P1D_UI_TEST": "1",
            "TASTEMAP_P4G_ROULETTE_UI_TEST": "1",
        ]
        app.launch()
        openP4GRoulette(in: app)
        XCTAssertTrue(app.staticTexts["roulette-candidate-count"].label.contains("8"))
        XCTAssertTrue(app.buttons["roulette-spin"].isHittable)
    }

    @MainActor
    func testP4GRouletteEmptyState() throws {
        let app = launchP4GRouletteFixture(environmentKey: "TASTEMAP_P4G_ROULETTE_EMPTY_UI_TEST")
        openP4GRoulette(in: app)
        XCTAssertTrue(app.staticTexts["还没有候选餐厅"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["搜索餐厅"].exists)
        XCTAssertFalse(app.buttons["roulette-spin"].exists)
    }

    @MainActor
    func testP4GRouletteSingleCandidateSkipsFakeSpin() throws {
        let app = launchP4GRouletteFixture(environmentKey: "TASTEMAP_P4G_ROULETTE_SINGLE_UI_TEST")
        openP4GRoulette(in: app)
        XCTAssertTrue(app.otherElements["roulette-single-state"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["roulette-result-name"].exists)
        XCTAssertFalse(app.buttons["roulette-spin"].exists)
    }

    @MainActor
    func testP4GRouletteLargePoolKeepsAllCandidatesEligible() throws {
        let app = launchP4GRouletteFixture(environmentKey: "TASTEMAP_P4G_ROULETTE_LARGE_UI_TEST")
        openP4GRoulette(in: app)
        XCTAssertTrue(app.staticTexts["roulette-candidate-count"].label.contains("120"))
        XCTAssertTrue(app.buttons["roulette-spin"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["完整候选池参与随机，轮盘仅做简化展示"].exists)
        keepScreenshot(named: "P4-G Large Candidate Pool", of: app)
    }

    @MainActor
    func testP4HFreeProfilePaywallFeatureGateAndDevelopmentUpgrade() throws {
        let app = XCUIApplication()
        app.launchEnvironment = [
            "TASTEMAP_P4A_ANALYSIS_UI_TEST": "1",
            "TASTEMAP_P4H_PREMIUM_UI_TEST": "free",
        ]
        app.launch()

        app.buttons["我的"].tap()
        XCTAssertTrue(app.navigationBars["我的"].waitForExistence(timeout: 5))
        let profileEntry = app.buttons["profile-premium-entry"]
        XCTAssertTrue(profileEntry.waitForExistence(timeout: 5))
        profileEntry.tap()
        XCTAssertTrue(app.otherElements["premium-paywall"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["premium-status-free"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["premium-no-store-products"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["premium-purchase"].exists)
        keepScreenshot(named: "P4-H Free Paywall", of: app)
        app.buttons["premium-paywall-close"].tap()
        XCTAssertFalse(app.otherElements["premium-paywall"].waitForExistence(timeout: 2))

        let taste = app.buttons["profile-taste-analysis-entry"]
        scrollUntilVisible(taste, in: app)
        taste.tap()
        let gate = app.descendants(matching: .any)["premium-feature-gate-full_taste_profile"]
        XCTAssertTrue(gate.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["你真正喜欢什么"].exists)
        app.buttons["premium-feature-gate-open-paywall"].tap()
        XCTAssertTrue(app.staticTexts["看懂长期偏好、预算、场景与评分风格"].waitForExistence(timeout: 5))
        let enable = app.buttons["premium-development-enable"]
        scrollUntilVisible(enable, in: app)
        XCTAssertTrue(enable.isHittable)
        enable.tap()
        XCTAssertTrue(app.descendants(matching: .any)["premium-status-active"].waitForExistence(timeout: 5))
        app.buttons["premium-paywall-close"].tap()
        XCTAssertTrue(app.staticTexts["你真正喜欢什么"].waitForExistence(timeout: 8))
        XCTAssertFalse(gate.exists)
    }

    @MainActor
    func testP4HPremiumFixtureDirectNavigationDoesNotShowPaywallAgain() throws {
        let app = XCUIApplication()
        app.launchEnvironment = [
            "TASTEMAP_P4A_ANALYSIS_UI_TEST": "1",
            "TASTEMAP_P4H_PREMIUM_UI_TEST": "premium",
        ]
        app.launch()

        app.buttons["我的"].tap()
        XCTAssertTrue(app.buttons["profile-premium-badge-entry"].waitForExistence(timeout: 5))
        let taste = app.buttons["profile-taste-analysis-entry"]
        scrollUntilVisible(taste, in: app)
        taste.tap()
        XCTAssertTrue(app.staticTexts["你真正喜欢什么"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.otherElements["premium-paywall"].exists)
        XCTAssertFalse(app.otherElements["premium-feature-gate-full_taste_profile"].exists)
    }

    @MainActor
    func testF7AProfileOnThisDayHistoricalRestaurantAndBack() throws {
        let app = XCUIApplication()
        app.launchEnvironment = ["TASTEMAP_F7A_ON_THIS_DAY_UI_TEST": "1"]
        app.launch()

        app.buttons["我的"].tap()
        XCTAssertTrue(app.navigationBars["我的"].waitForExistence(timeout: 5))
        let entry = app.buttons["profile-on-this-day-entry"]
        scrollUntilVisible(entry, in: app)
        XCTAssertTrue(entry.waitForExistence(timeout: 5))
        XCTAssertTrue(entry.isHittable)
        entry.tap()

        XCTAssertTrue(app.navigationBars["那年今日"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.descendants(matching: .any)["on-this-day-page"].exists)
        XCTAssertTrue(app.staticTexts["看看过去这些年的今天，你吃了什么。"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["on-this-day-year-2025"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["那年今日 · 湖畔小馆"].exists)
        keepScreenshot(named: "F7-A On This Day", of: app)

        let memory = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH 'on-this-day-memory-'")
        ).firstMatch
        scrollUntilVisible(memory, in: app)
        XCTAssertTrue(memory.waitForExistence(timeout: 5))
        memory.tap()
        XCTAssertTrue(app.navigationBars["餐厅详情"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["那年今日 · 湖畔小馆"].waitForExistence(timeout: 5))
        app.navigationBars["餐厅详情"].buttons["那年今日"].tap()
        XCTAssertTrue(app.navigationBars["那年今日"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["on-this-day-year-2025"].exists)

        let share = app.buttons["on-this-day-share-toolbar"]
        XCTAssertTrue(share.waitForExistence(timeout: 5))
        share.tap()
        XCTAssertTrue(app.navigationBars["分享海报"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.images["analysis-poster-preview"].waitForExistence(timeout: 12))
        XCTAssertTrue(app.buttons["analysis-poster-save"].exists)
        XCTAssertTrue(app.buttons["analysis-poster-system-share"].exists)
        app.navigationBars["分享海报"].buttons["关闭"].tap()
        XCTAssertTrue(app.navigationBars["那年今日"].waitForExistence(timeout: 5))
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
    private func launchP4GRouletteFixture(environmentKey: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-p1d-persistent-offline-fixture", "-p1d-reset-persistent-offline-fixture"]
        app.launchEnvironment = [
            "TASTEMAP_P1D_UI_TEST": "1", "TASTEMAP_P1D_RESET": "1",
            environmentKey: "1",
        ]
        app.launch()
        return app
    }

    @MainActor
    private func openP4GRoulette(in app: XCUIApplication) {
        app.buttons["我的"].tap()
        let entry = app.buttons["profile-restaurant-roulette-entry"]
        scrollUntilVisible(entry, in: app)
        XCTAssertTrue(entry.waitForExistence(timeout: 5))
        entry.tap()
        XCTAssertTrue(app.navigationBars["今天吃什么"].waitForExistence(timeout: 5))
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
        segmentedOption(tab, in: app).tap()
        let card = app.buttons["restaurant-card-11111111-2222-3333-4444-555555555555"]
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        card.tap()
        XCTAssertTrue(app.navigationBars["餐厅详情"].waitForExistence(timeout: 5))
    }

    @MainActor
    private func addCompleteVisit(in app: XCUIApplication) {
        app.buttons["restaurant-detail-add-visit"].tap()
        XCTAssertTrue(app.navigationBars["新增到访"].waitForExistence(timeout: 5))
        // The restored editor keeps the free-form record near the top and
        // spending near the bottom. Fill it before moving down the form so the
        // test does not need to reverse-scroll through an active number pad.
        let note = app.descendants(matching: .any)["visit-editor-note"]
        scrollUntilVisible(note, in: app)
        XCTAssertTrue(note.waitForExistence(timeout: 3))
        note.tap()
        note.typeText("完整离线记录")
        app.navigationBars["新增到访"].tap()
        let diningMode = segmentedOption("外卖", in: app)
        scrollUntilVisible(diningMode, in: app)
        XCTAssertTrue(diningMode.waitForExistence(timeout: 3))
        diningMode.tap()
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
        app.buttons["visit-editor-save"].tap()
        XCTAssertTrue(app.staticTexts["restaurant-status-visited"].waitForExistence(timeout: 5))
    }

    @MainActor
    private func launchImportPreflightFixture(_ mode: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-p1d-persistent-offline-fixture",
            "-p1d-reset-persistent-offline-fixture",
        ]
        app.launchEnvironment = [
            "TASTEMAP_P1D_UI_TEST": "1",
            "TASTEMAP_P1D_RESET": "1",
            "TASTEMAP_P3A_PROFILE_UI_TEST": "1",
            "TASTEMAP_F1B3_SETTINGS_UI_TEST": "1",
            "TASTEMAP_F1C2_IMPORT_UI_TEST": mode,
        ]
        app.launch()
        return app
    }

    @MainActor
    private func openImportPreflight(in app: XCUIApplication) {
        app.buttons["我的"].tap()
        XCTAssertTrue(app.navigationBars["我的"].waitForExistence(timeout: 5))
        let settings = app.buttons["profile-settings-entry"]
        scrollUntilVisible(settings, in: app)
        XCTAssertTrue(settings.isHittable)
        settings.tap()
        XCTAssertTrue(app.navigationBars["设置"].waitForExistence(timeout: 5))
        let dataAndBackup = app.buttons["settings-data-backup-entry"]
        XCTAssertTrue(dataAndBackup.waitForExistence(timeout: 3))
        dataAndBackup.tap()
        XCTAssertTrue(app.navigationBars["数据与备份"].waitForExistence(timeout: 3))
        let importEntry = app.buttons["settings-import-data-entry"]
        scrollUntilVisible(importEntry, in: app)
        XCTAssertTrue(importEntry.isHittable)
        importEntry.tap()
        XCTAssertTrue(app.navigationBars["导入数据"].waitForExistence(timeout: 3))
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
        // `isHittable` may still be true when only a thin strip sits beneath
        // the app's custom bottom navigation. Keep a real tap-safe margin so
        // long Profile/Settings cards do not absorb a no-op tap at the edge.
        for _ in 0..<30 where !element.isHittable || element.frame.maxY > app.frame.maxY - 92 {
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

    /// Supports both native segmented pickers and Taste Map's visually restored
    /// segmented buttons without coupling product behavior tests to one renderer.
    @MainActor
    private func segmentedOption(_ label: String, in app: XCUIApplication) -> XCUIElement {
        for prefix in ["map-content-segment", "map-list-mode-picker", "discover-hub-segment"] {
            let restoredOption = app.buttons["\(prefix)-\(label)"]
            if restoredOption.exists { return restoredOption }
        }
        let nativeOption = app.segmentedControls.buttons[label]
        return nativeOption.exists ? nativeOption : app.buttons[label]
    }

    @MainActor
    private func keepScreenshot(named name: String, of app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
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
        let existingValue = value as? String ?? ""
        coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        // Send the delete characters through this element rather than as
        // process-wide key events. Xcode can lose TextField first-responder
        // focus during long UI sweeps even though `typeKey` reports success.
        typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: existingValue.count + 2))
        typeText(text)
        XCTAssertEqual(value as? String, text)
    }
}
