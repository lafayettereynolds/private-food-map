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

        let listMode = app.buttons["map-header-view-list"]
        XCTAssertTrue(listMode.waitForExistence(timeout: 5))
        listMode.tap()
        let restaurantName = "F2-A 很长但仍需完整可读的江南季节料理餐厅"
        XCTAssertTrue(app.descendants(matching: .any)["restaurant-list-context"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["restaurant-list-result-count"].label, "1 家")
        XCTAssertTrue(app.staticTexts[restaurantName].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["2 次到访"].exists)
        XCTAssertTrue(app.staticTexts["4.5"].exists)
        XCTAssertTrue(app.descendants(matching: .any).matching(
            identifier: "restaurant-photo-fallback-00000000-0000-0000-0000-000000010001"
        ).firstMatch.exists)

        let mapMode = app.buttons["map-header-view-map"]
        XCTAssertTrue(mapMode.exists)
        mapMode.tap()
        XCTAssertTrue(app.maps.firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["map-header-view-list"].waitForExistence(timeout: 5))
        app.buttons["map-header-view-list"].tap()
        XCTAssertTrue(app.staticTexts[restaurantName].waitForExistence(timeout: 5))

        let restaurantID = "00000000-0000-0000-0000-000000010001"
        let actions = app.descendants(matching: .any)["restaurant-list-actions-\(restaurantID)"]
        XCTAssertTrue(actions.exists)
        let record = app.buttons["restaurant-list-record-\(restaurantID)"]
        let want = app.buttons["restaurant-list-want-\(restaurantID)"]
        let roulette = app.buttons["restaurant-list-roulette-\(restaurantID)"]
        XCTAssertTrue(record.isHittable)
        XCTAssertTrue(want.isHittable)
        XCTAssertTrue(roulette.isHittable)

        roulette.tap()
        let rouletteDock = app.descendants(matching: .any)["map-roulette-candidate-dock"]
        XCTAssertTrue(rouletteDock.waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["已选 1/10"].exists)
        XCTAssertFalse(app.buttons["开始抽"].isEnabled)
        roulette.tap()
        XCTAssertFalse(rouletteDock.waitForExistence(timeout: 2))

        record.tap()
        XCTAssertTrue(app.navigationBars["新增到访"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.navigationBars["餐厅详情"].exists)
        app.navigationBars["新增到访"].buttons["取消"].tap()
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
        let listMode = app.buttons["map-header-view-list"]
        let titleSwitch = app.descendants(matching: .any)["map-title-view-switch"]
        let scopeControl = app.descendants(matching: .any)["map-content-segment"]
        let filterStrip = app.descendants(matching: .any)["map-filter-chip-strip"]
        let title = app.staticTexts["map-home-title"]
        XCTAssertTrue(map.waitForExistence(timeout: 8))
        XCTAssertTrue(controls.waitForExistence(timeout: 5))
        XCTAssertTrue(visitedTab.exists)
        XCTAssertTrue(listMode.exists)
        XCTAssertTrue(title.exists)
        XCTAssertEqual(title.label, "我的地图")
        XCTAssertTrue(titleSwitch.exists)
        XCTAssertEqual(app.frame.width, 402, accuracy: 1)
        XCTAssertEqual(titleSwitch.frame.midX, app.frame.midX, accuracy: 2)
        XCTAssertLessThan(titleSwitch.frame.width, app.frame.width * 0.52)
        XCTAssertEqual(listMode.label, "切换到我的列表")
        XCTAssertGreaterThanOrEqual(listMode.frame.width, 44)
        XCTAssertGreaterThanOrEqual(listMode.frame.height, 44)
        XCTAssertFalse(app.descendants(matching: .any)["map-list-mode-control"].exists)
        XCTAssertTrue(scopeControl.exists)
        XCTAssertTrue(filterStrip.exists)
        XCTAssertLessThanOrEqual(title.frame.maxX, listMode.frame.minX + 2)
        XCTAssertLessThan(titleSwitch.frame.maxY, scopeControl.frame.minY)
        XCTAssertLessThan(scopeControl.frame.maxY, filterStrip.frame.minY)
        // The restored hierarchy intentionally gives the centered title its own
        // breathing room above three independent compact control rows. Keep the
        // complete header bounded to the upper 30% while the map remains full-bleed.
        XCTAssertLessThanOrEqual(controls.frame.maxY, app.frame.height * 0.30)
        XCTAssertGreaterThan(map.frame.height, app.frame.height * 0.72)
        XCTAssertLessThan(listMode.frame.minY, controls.frame.maxY)

        let addRestaurant = app.buttons["addRestaurantButton"]
        let mapTab = app.buttons["app-tab-map"]
        XCTAssertTrue(addRestaurant.exists)
        XCTAssertTrue(mapTab.exists)
        XCTAssertLessThan(addRestaurant.frame.midY, mapTab.frame.midY)
        keepScreenshot(named: "Task 04 Map After", of: app)

        listMode.tap()
        let search = app.textFields["restaurant-list-search-field"]
        let restaurantName = "F2-A 很长但仍需完整可读的江南季节料理餐厅"
        let row = app.buttons.containing(.staticText, identifier: restaurantName).firstMatch
        let rowContainer = app.descendants(matching: .any)[
            "restaurant-list-row-00000000-0000-0000-0000-000000010001"
        ]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertTrue(rowContainer.exists)
        XCTAssertLessThanOrEqual(row.frame.height, 96)
        XCTAssertEqual(rowContainer.frame.minX, 14, accuracy: 2)
        XCTAssertLessThanOrEqual(rowContainer.frame.height, 116)
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
        XCTAssertLessThanOrEqual(actions.frame.height, 130)
        keepScreenshot(named: "Task 04 Restaurant Detail After", of: app)
    }

    @MainActor
    func testMyMapListTitleSwitchKeepsScopeAndFilters() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleInterfaceStyle", "Light"]
        app.launchEnvironment = ["TASTEMAP_F2A_BROWSING_UI_TEST": "1"]
        app.launch()

        let titleGroup = app.descendants(matching: .any)["map-title-view-switch"]
        let mapTitle = app.staticTexts["map-home-title"]
        let listSwitch = app.buttons["map-header-view-list"]
        XCTAssertTrue(mapTitle.waitForExistence(timeout: 8))
        XCTAssertEqual(mapTitle.label, "我的地图")
        XCTAssertEqual(titleGroup.frame.midX, app.frame.midX, accuracy: 2)
        XCTAssertEqual(listSwitch.label, "切换到我的列表")

        let rating = app.buttons["map-filter-chip-rating"]
        rating.tap()
        let highRating = app.buttons["personal-filter-rating-5"]
        XCTAssertTrue(highRating.waitForExistence(timeout: 3))
        highRating.tap()
        app.buttons["personal-filter-apply"].tap()
        XCTAssertTrue(rating.waitForExistence(timeout: 3))
        let ratingLabelBeforeSwitch = rating.label

        let wantToGo = app.buttons["map-scope-wantToGo"]
        wantToGo.tap()
        XCTAssertTrue(wantToGo.isSelected)

        listSwitch.tap()
        let listTitle = app.staticTexts["map-home-title"]
        let mapSwitch = app.buttons["map-header-view-map"]
        XCTAssertTrue(listTitle.waitForExistence(timeout: 5))
        XCTAssertEqual(listTitle.label, "我的列表")
        XCTAssertEqual(titleGroup.frame.midX, app.frame.midX, accuracy: 2)
        XCTAssertEqual(mapSwitch.label, "切换到我的地图")
        XCTAssertEqual(app.buttons["map-filter-chip-rating"].label, ratingLabelBeforeSwitch)
        XCTAssertTrue(app.buttons["map-filter-chip-rating"].isSelected)
        XCTAssertTrue(wantToGo.isSelected)
        keepScreenshot(named: "My List Title Switch After", of: app)

        mapSwitch.tap()
        XCTAssertTrue(app.maps.firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["map-home-title"].label, "我的地图")
        XCTAssertEqual(titleGroup.frame.midX, app.frame.midX, accuracy: 2)
        XCTAssertEqual(app.buttons["map-header-view-list"].label, "切换到我的列表")
        XCTAssertEqual(app.buttons["map-filter-chip-rating"].label, ratingLabelBeforeSwitch)
        XCTAssertTrue(app.buttons["map-filter-chip-rating"].isSelected)
        XCTAssertTrue(wantToGo.isSelected)
        keepScreenshot(named: "My Map Title Switch After", of: app)
    }

    @MainActor
    func testProductUXMapFilterChipsOpenTheirOwnDimension() throws {
        let app = XCUIApplication()
        app.launchEnvironment = ["TASTEMAP_F2A_BROWSING_UI_TEST": "1"]
        app.launch()

        let rating = app.buttons["map-filter-chip-rating"]
        XCTAssertTrue(rating.waitForExistence(timeout: 8))
        rating.tap()
        XCTAssertTrue(app.navigationBars["评分"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["personal-filter-rating-5"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["personal-filter-sort"].exists)
        app.buttons["取消"].tap()

        let city = app.buttons["map-filter-chip-city"]
        XCTAssertTrue(city.waitForExistence(timeout: 3))
        city.tap()
        XCTAssertTrue(app.navigationBars["城市"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.descendants(matching: .any)["personal-filter-city"].exists)
        XCTAssertFalse(app.buttons["personal-filter-rating-5"].exists)
        keepScreenshot(named: "Product UX Specific City Filter After", of: app)
    }

    @MainActor
    func testFarMapKeepsIndependentRestaurantMarkers() throws {
        let app = XCUIApplication()
        app.launchEnvironment = ["TASTEMAP_MODULE8_MAP_CLUSTER_UI_TEST": "1"]
        app.launch()

        XCTAssertTrue(app.maps.firstMatch.waitForExistence(timeout: 8))
        let clusters = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "restaurant-map-cluster-")
        )
        let markers = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "restaurant-map-marker-")
        )
        XCTAssertFalse(clusters.firstMatch.exists)
        XCTAssertGreaterThanOrEqual(markers.count, 2)
        keepScreenshot(named: "Product UX Independent Markers After", of: app)
    }

    @MainActor
    func testLegacyFusionRichMapKeepsIndependentNaturalMarkers() throws {
        let app = XCUIApplication()
        app.launchEnvironment = ["TASTEMAP_VISUAL_QA_MODE": "rich"]
        app.launch()

        XCTAssertTrue(app.maps.firstMatch.waitForExistence(timeout: 12))
        let clusters = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "restaurant-map-cluster-")
        )
        let markers = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "restaurant-map-marker-")
        )
        XCTAssertFalse(clusters.firstMatch.exists)
        XCTAssertGreaterThanOrEqual(markers.count, 10)
        XCTAssertEqual(app.staticTexts["map-home-title"].label, "我的地图")
        keepScreenshot(named: "Legacy Fusion Rich Natural Markers", of: app)
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
        XCTAssertLessThanOrEqual(controls.frame.maxY, app.frame.height * 0.30)
        XCTAssertGreaterThan(map.frame.height, app.frame.height * 0.72)
        XCTAssertTrue(app.buttons["addRestaurantButton"].isHittable)
        keepScreenshot(named: "Task 04 Map Dark After", of: app)
    }

    @MainActor
    func testCoreProductLayoutParityMapDiscoveryProfileEvidence() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleInterfaceStyle", "Light"]
        app.launchEnvironment = [
            "TASTEMAP_F2A_BROWSING_UI_TEST": "1",
            "TASTEMAP_CORE_PARITY_INITIAL_TAB": "map",
        ]
        app.launch()

        let controls = app.descendants(matching: .any)["map-home-compact-controls"]
        XCTAssertTrue(controls.waitForExistence(timeout: 8))
        // The final parity contract deliberately includes a visible top breathing
        // area, centred title, mode controls, scope and one compact filter row.
        // Keep this aligned with the dedicated light/dark compact-layout checks.
        XCTAssertLessThanOrEqual(controls.frame.maxY, app.frame.height * 0.30)
        XCTAssertTrue(app.staticTexts["map-home-title"].exists)
        XCTAssertTrue(app.buttons["map-header-view-list"].isHittable)
        XCTAssertFalse(app.buttons["map-header-view-map"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["map-filter-chip-strip"].exists)
        XCTAssertTrue(app.buttons["map-filter-chip-city"].exists)
        XCTAssertTrue(app.buttons["map-filter-chip-rating"].exists)
        XCTAssertTrue(app.buttons["map-filter-chip-price"].exists)
        keepScreenshot(named: "Core Parity Map After", of: app)

        app.buttons["map-header-view-list"].tap()
        XCTAssertTrue(app.buttons["map-header-view-map"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["map-header-view-list"].exists)
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
        let discoveryTitle = app.staticTexts["discovery-header"]
        XCTAssertTrue(discoveryTitle.exists)
        XCTAssertEqual(discoveryTitle.frame.midX, app.frame.midX, accuracy: 3)
        let primaryTabs = [
            "discovery-primary-following", "discovery-primary-forYou",
            "discovery-primary-similarTaste", "discovery-primary-latest",
            "discovery-primary-trending",
        ].map { app.buttons[$0] }
        let tabWidths = primaryTabs.map(\.frame.width)
        XCTAssertLessThan((tabWidths.max() ?? 0) - (tabWidths.min() ?? 0), 3)
        XCTAssertFalse(app.buttons["发现餐厅"].exists)
        XCTAssertFalse(app.buttons["社区动态"].exists)
        XCTAssertTrue(app.buttons["discovery-city-menu"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["discovery-filters"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["discovery-filter-chip-strip"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["discovery-activity-rating-place:p3c-ui-0"].exists)
        keepScreenshot(named: "Core Parity Discovery After", of: app)

        app.terminate()
        app.launchEnvironment = [
            "TASTEMAP_F2A_BROWSING_UI_TEST": "1",
            "TASTEMAP_CORE_PARITY_INITIAL_TAB": "profile",
        ]
        app.launch()
        XCTAssertTrue(app.buttons["profile-settings-header-entry"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["profile-edit-button"].exists)
        XCTAssertTrue(app.buttons["profile-following-stat"].exists)
        XCTAssertTrue(app.buttons["profile-followers-stat"].exists)
        XCTAssertTrue(app.buttons["profile-stat-visited"].exists)
        XCTAssertTrue(app.buttons["profile-stat-want"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["profile-stat-spend"].exists)
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

        XCTAssertTrue(app.buttons["profile-settings-header-entry"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["profile-edit-button"].exists)
        XCTAssertTrue(app.buttons["profile-stat-visited"].exists)
        XCTAssertTrue(app.buttons["profile-stat-want"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["profile-stat-spend"].exists)
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
        XCTAssertTrue(app.descendants(matching: .any)["profile-identity-card"].waitForExistence(timeout: 8))
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
        XCTAssertTrue(app.descendants(matching: .any)["profile-identity-card"].waitForExistence(timeout: 5))

        let visitedEntry = app.buttons["profile-stat-visited"]
        scrollUntilVisible(visitedEntry, in: app)
        visitedEntry.tap()
        XCTAssertTrue(app.navigationBars["去过的餐厅"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["F2-A 很长但仍需完整可读的江南季节料理餐厅"].exists)
        app.navigationBars["去过的餐厅"].buttons.firstMatch.tap()

        let wantedEntry = app.buttons["profile-stat-want"]
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
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "taste-footprint-want-to-go-")).count, 1)
        XCTAssertTrue(app.staticTexts["未评分"].exists)
        XCTAssertTrue(app.staticTexts["F2-A 想吃小馆"].exists)
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
        keepScreenshot(named: "Final Atlas Map Filter Sheet", of: app)

        let topRating = app.buttons["personal-filter-rating-5"]
        XCTAssertTrue(topRating.waitForExistence(timeout: 3))
        topRating.tap()
        let takeout = app.buttons["personal-filter-dining-takeout"]
        scrollUntilVisible(takeout, in: app)
        XCTAssertTrue(takeout.isHittable)
        takeout.tap()
        app.buttons["personal-filter-apply"].tap()

        let activeFilter = app.buttons["personal-filter-button"]
        XCTAssertTrue(activeFilter.waitForExistence(timeout: 5))
        let enabledFilter = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", "已启用"),
            object: activeFilter
        )
        XCTAssertEqual(XCTWaiter.wait(for: [enabledFilter], timeout: 5), .completed)
        app.buttons["map-header-view-list"].tap()
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
        XCTAssertTrue(app.staticTexts["147 米"].exists)
        XCTAssertTrue(app.textFields["restaurant-query-field"].exists)
        XCTAssertFalse(app.textFields["restaurant-link-field"].exists)
        XCTAssertTrue(app.buttons["open-manual-restaurant"].exists)

        let candidate = app.descendants(matching: .any)[
            "restaurant-candidate-AC000001-0000-0000-0000-000000000001"
        ]
        XCTAssertTrue(candidate.exists)
        XCTAssertLessThanOrEqual(candidate.frame.height, 78)
        keepScreenshot(named: "Full Parity Add Restaurant Nearby After", of: app)

        let select = app.buttons["candidate-select-AC000001-0000-0000-0000-000000000001"]
        XCTAssertTrue(select.waitForExistence(timeout: 3))
        XCTAssertLessThanOrEqual(select.frame.width, 64)
        select.tap()
        XCTAssertTrue(app.navigationBars["确认餐厅"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.descendants(matching: .any)["restaurant-acquisition-preview"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["restaurant-detail-header"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["restaurant-detail-location"].exists)
        keepScreenshot(named: "Product UX Restaurant Candidate Preview", of: app)
        segmentedOption("我想去", in: app).tap()
        let confirm = app.buttons["confirm-restaurant-selection"]
        scrollUntilVisible(confirm, in: app)
        confirm.tap()
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

        let select = app.buttons["candidate-select-AC000002-0000-0000-0000-000000000002"]
        scrollUntilVisible(select, in: app)
        XCTAssertTrue(select.isHittable)
        select.tap()
        XCTAssertTrue(app.navigationBars["确认餐厅"].waitForExistence(timeout: 3))
        keepScreenshot(named: "Product UX Restaurant Search Preview", of: app)
        let confirm = app.buttons["confirm-restaurant-selection"]
        scrollUntilVisible(confirm, in: app)
        confirm.tap()
        XCTAssertTrue(app.navigationBars["新增到访"].waitForExistence(timeout: 5))
        app.navigationBars["新增到访"].buttons["取消"].tap()
    }

    @MainActor
    func testRestaurantAcquisitionLinkImportIsConfirmedBeforeCreation() throws {
        let app = XCUIApplication()
        app.launchEnvironment = ["TASTEMAP_RESTAURANT_ACQUISITION_SHARED_UI_TEST": "1"]
        app.launch()
        app.buttons["添加餐厅"].tap()

        XCTAssertTrue(app.descendants(matching: .any)["shared-restaurant-import"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.textFields["restaurant-link-field"].exists)
        XCTAssertTrue(app.staticTexts["V1 Apple 链接餐厅"].waitForExistence(timeout: 5))
        keepScreenshot(named: "Product UX External Share Recognition", of: app)

        let select = app.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH %@",
            "candidate-select-"
        )).firstMatch
        scrollUntilVisible(select, in: app)
        XCTAssertTrue(select.waitForExistence(timeout: 3))
        select.tap()
        XCTAssertTrue(app.navigationBars["确认餐厅"].waitForExistence(timeout: 3))
        keepScreenshot(named: "Product UX External Share Preview", of: app)
        segmentedOption("我想去", in: app).tap()
        let confirm = app.buttons["confirm-restaurant-selection"]
        scrollUntilVisible(confirm, in: app)
        confirm.tap()
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
        keepScreenshot(named: "Product UX Manual Restaurant", of: app)

        app.textFields["manual-restaurant-name"].tap()
        app.textFields["manual-restaurant-name"].typeText("地图外的小摊")
        app.textFields["manual-restaurant-city"].tap()
        app.textFields["manual-restaurant-city"].typeText("杭州")
        app.textFields["manual-restaurant-address"].tap()
        app.textFields["manual-restaurant-address"].typeText("武林路 8 号")
        app.buttons["manual-locate-address"].tap()
        let confirmManual = app.buttons["manual-confirm-restaurant"]
        scrollUntilVisible(confirmManual, in: app)
        XCTAssertTrue(confirmManual.waitForExistence(timeout: 5))
        confirmManual.tap()
        XCTAssertTrue(app.navigationBars["确认餐厅"].waitForExistence(timeout: 5))
        keepScreenshot(named: "Product UX Manual Restaurant Preview", of: app)
        segmentedOption("我想去", in: app).tap()
        let confirm = app.buttons["confirm-restaurant-selection"]
        scrollUntilVisible(confirm, in: app)
        confirm.tap()

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
        XCTAssertTrue(app.descendants(matching: .any)["profile-identity-card"].waitForExistence(timeout: 5))

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
        keepScreenshot(named: "Final Atlas Discovery For You", of: app)
        restaurant.tap()
        XCTAssertTrue(app.navigationBars["餐厅详情"].waitForExistence(timeout: 5))
        XCTAssertTrue(
            app.descendants(matching: .any)["restaurant-detail-header"]
                .waitForExistence(timeout: 3)
        )
        app.buttons["完成"].tap()

        let want = app.buttons["discovery-want-place:p3c-ui-0"]
        XCTAssertTrue(want.waitForExistence(timeout: 5))
        want.tap()
        XCTAssertTrue(app.staticTexts["已想吃"].waitForExistence(timeout: 5))

        app.buttons["discovery-primary-similarTaste"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "基于 5 家共同评分餐厅")).firstMatch.waitForExistence(timeout: 5))
        keepScreenshot(named: "Task 02 Same Taste Content After", of: app)
        app.buttons["同味小林"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["公开主页"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["同味小林"].exists)
        app.buttons["完成"].tap()

        app.buttons["discovery-primary-trending"].tap()
        XCTAssertTrue(app.buttons["discovery-trend-window-7"].waitForExistence(timeout: 5))
        app.buttons["discovery-trend-window-30"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "近 30 天有 8 位用户到访")).firstMatch.waitForExistence(timeout: 5))
        keepScreenshot(named: "Final Atlas Discovery Trending", of: app)
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
        keepScreenshot(named: "Final Atlas Discovery Offline", of: app)
        want.tap()
        XCTAssertTrue(app.staticTexts["已想吃"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testDiscoveryAndCommunityCardsUseConcreteVisitRating() throws {
        let discovery = XCUIApplication()
        discovery.launchEnvironment = ["TASTEMAP_P3C_DISCOVERY_UI_TEST": "1"]
        discovery.launch()
        discovery.buttons["发现"].tap()

        let rated = discovery.staticTexts["discovery-activity-rating-place:p3c-ui-0"]
        XCTAssertTrue(rated.waitForExistence(timeout: 5))
        XCTAssertTrue(rated.label.contains("3.5"))
        let unrated = discovery.staticTexts["discovery-activity-rating-place:p3c-ui-1"]
        if !unrated.exists { discovery.swipeUp() }
        XCTAssertTrue(unrated.waitForExistence(timeout: 5))
        XCTAssertTrue(unrated.label.contains("未评分"))
        XCTAssertFalse(discovery.staticTexts["社区 4.6"].exists)

        discovery.terminate()
        let community = XCUIApplication()
        community.launchEnvironment = ["TASTEMAP_P3D_COMMUNITY_UI_TEST": "1"]
        community.launch()
        community.buttons["发现"].tap()
        community.buttons["discovery-primary-latest"].tap()
        XCTAssertTrue(community.staticTexts["云边小馆·湖滨店"].waitForExistence(timeout: 5))
        keepScreenshot(named: "Final Atlas Discovery Latest", of: community)
        let communityUnrated = community.staticTexts["community-activity-rating-visit-p3d-ui-2"]
        if !communityUnrated.exists { community.swipeUp() }
        if !communityUnrated.exists { community.swipeUp() }
        XCTAssertTrue(communityUnrated.waitForExistence(timeout: 5))
        XCTAssertTrue(communityUnrated.label.contains("未评分"))
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
        app.launchArguments = ["-AppleInterfaceStyle", "Light"]
        app.launchEnvironment = ["TASTEMAP_P3D_COMMUNITY_UI_TEST": "1"]
        app.launchEnvironment["TASTEMAP_P4F_LISTS_UI_TEST"] = "1"
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
        XCTAssertTrue(app.descendants(matching: .any)["public-profile-following-stat"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["public-profile-followers-stat"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["public-profile-joined-date"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["public-profile-map-entry"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["public-profile-visited-entry"].exists)
        XCTAssertTrue(app.buttons["public-profile-want-entry"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["public-profile-map-section"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["public-profile-activity-section"].exists)
        XCTAssertTrue(app.staticTexts["TA 的食单"].exists)
        XCTAssertTrue(app.staticTexts["TA 的味觉足迹"].exists)
        XCTAssertFalse(app.staticTexts["去过公开记录"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["public-profile-metric-strip"].exists)
        keepScreenshot(named: "Core Parity Public Profile After", of: app)
        app.buttons["完成"].tap()

        app.staticTexts["云边小馆·湖滨店"].tap()
        XCTAssertTrue(app.navigationBars["餐厅详情"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["restaurant-photo-gallery"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["restaurant-detail-header"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["restaurant-detail-quick-actions"].exists)
        let remoteLocation = app.otherElements["restaurant-detail-location"]
        scrollUntilReadable(remoteLocation, in: app)
        XCTAssertTrue(remoteLocation.waitForExistence(timeout: 3))
        let remotePhotos = app.otherElements["restaurant-user-photos"]
        scrollUntilReadable(remotePhotos, in: app)
        XCTAssertTrue(remotePhotos.waitForExistence(timeout: 3))
        let remoteOverview = app.otherElements["restaurant-detail-statistics"]
        scrollUntilReadable(remoteOverview, in: app)
        XCTAssertTrue(remoteOverview.waitForExistence(timeout: 3))
        let remoteHistory = app.otherElements["restaurant-visit-history"]
        scrollUntilReadable(remoteHistory, in: app)
        XCTAssertTrue(remoteHistory.waitForExistence(timeout: 3))
        keepScreenshot(named: "Global Restaurant Detail Remote After", of: app)
        app.buttons["完成"].tap()

        let want = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "想吃")).firstMatch
        XCTAssertTrue(want.waitForExistence(timeout: 5))
        want.tap()
        XCTAssertTrue(app.staticTexts["已想吃"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testPublicProfileFootprintEntriesPreserveGalleryAndRestaurantActions() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleInterfaceStyle", "Light"]
        app.launchEnvironment = ["TASTEMAP_P3D_COMMUNITY_UI_TEST": "1", "TASTEMAP_P4F_LISTS_UI_TEST": "1"]
        app.launch()
        app.buttons["发现"].tap()
        XCTAssertTrue(app.buttons["discovery-primary-following"].waitForExistence(timeout: 5))
        app.buttons["discovery-primary-following"].tap()
        XCTAssertTrue(app.staticTexts["常去小馆的阿岚"].firstMatch.waitForExistence(timeout: 5))
        app.staticTexts["常去小馆的阿岚"].firstMatch.tap()

        let visited = app.buttons["public-profile-visited-entry"]
        XCTAssertTrue(visited.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["public-profile-want-entry"].exists)
        XCTAssertTrue(app.buttons["public-profile-map-entry"].exists)
        XCTAssertFalse(app.buttons["解除好友"].exists)
        XCTAssertTrue(app.buttons["public-profile-follow-action"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["public-profile-map-section"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["public-profile-activity-section"].exists)
        XCTAssertFalse(app.staticTexts["公开食单"].exists)
        keepScreenshot(named: "Public Profile Compact Entries", of: app)
        visited.tap()
        XCTAssertTrue(app.navigationBars["TA 的味觉足迹"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["public-profile-content-section"].exists)

        let photo = app.buttons["community-photos-visit:visit-p3d-ui-0"]
        scrollUntilVisible(photo, in: app)
        XCTAssertTrue(photo.waitForExistence(timeout: 5))
        XCTAssertTrue(photo.label.contains("3 张到访照片"))
        photo.tap()
        XCTAssertTrue(app.descendants(matching: .any)["community-photo-gallery"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.navigationBars["1 / 3"].exists)
        app.swipeLeft()
        XCTAssertTrue(app.navigationBars["2 / 3"].waitForExistence(timeout: 3))
        app.swipeLeft()
        XCTAssertTrue(app.navigationBars["3 / 3"].waitForExistence(timeout: 3))
        keepScreenshot(named: "Public Footprint All Photos Accessible", of: app)
        app.buttons["完成"].tap()

        let record = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "community-record-")).firstMatch
        scrollUntilVisible(record, in: app)
        XCTAssertTrue(record.waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(record.frame.width, 44)
        XCTAssertGreaterThanOrEqual(record.frame.height, 44)
        XCTAssertTrue(app.buttons["community-share-visit-p3d-ui-0"].exists)
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "community-list-")).firstMatch.exists)
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "community-roulette-")).firstMatch.exists)
        keepScreenshot(named: "Public Footprint Canonical Actions", of: app)
        record.tap()
        XCTAssertTrue(app.navigationBars["新增到访"].waitForExistence(timeout: 5))
        app.buttons["取消"].tap()
        app.navigationBars["TA 的味觉足迹"].buttons["公开主页"].tap()
        XCTAssertTrue(app.buttons["public-profile-want-entry"].waitForExistence(timeout: 5))
        app.buttons["public-profile-want-entry"].tap()
        XCTAssertTrue(app.navigationBars["TA 的味觉足迹"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["public-profile-content-section"].exists)
        app.navigationBars["TA 的味觉足迹"].buttons["公开主页"].tap()
        app.buttons["public-profile-map-entry"].tap()
        let publicMap = app.descendants(matching: .any)["public-profile-map"]
        XCTAssertTrue(publicMap.waitForExistence(timeout: 8))
        XCTAssertGreaterThan(publicMap.frame.height, 350)
        keepScreenshot(named: "Public Profile On Demand Full Map", of: app)
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
        XCTAssertTrue(app.descendants(matching: .any)["profile-identity-card"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["P3-A 初始用户"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["profile-edit-button"].exists)
        app.buttons["profile-settings-header-entry"].tap()
        XCTAssertTrue(app.buttons["settings-account-entry"].waitForExistence(timeout: 5))
        app.buttons["settings-account-entry"].tap()
        XCTAssertTrue(app.buttons["settings-edit-profile"].waitForExistence(timeout: 5))
        app.buttons["settings-edit-profile"].tap()
        XCTAssertTrue(app.navigationBars["编辑资料"].waitForExistence(timeout: 5))

        let name = app.textFields["profile-display-name"]
        name.tap()
        name.clearAndType("离线美食家 🍜")
        let city = app.textFields["profile-city"]
        city.tap()
        city.clearAndType("上海")
        XCTAssertFalse(app.textFields["profile-bio"].exists)
        XCTAssertFalse(app.staticTexts["个人简介"].exists)
        let otter = app.buttons["profile-avatar-preset-otter"]
        scrollUntilVisible(otter, in: app)
        otter.tap()
        app.buttons["profile-save-button"].tap()

        XCTAssertTrue(app.navigationBars["账户与安全"].waitForExistence(timeout: 5))
        app.navigationBars["账户与安全"].buttons["设置"].tap()
        XCTAssertTrue(app.navigationBars["设置"].waitForExistence(timeout: 5))
        app.navigationBars["设置"].buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.staticTexts["离线美食家 🍜"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["profile-user-id"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["profile-bio-text"].exists)
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
        XCTAssertTrue(app.buttons["profile-user-id"].exists)
        XCTAssertFalse(app.staticTexts["profile-bio-text"].exists)
        XCTAssertEqual(app.staticTexts["profile-city-text"].label, "上海")
        XCTAssertFalse(app.buttons["profile-edit-button"].exists)
        XCTAssertTrue(app.buttons["profile-settings-header-entry"].exists)
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
        XCTAssertTrue(app.descendants(matching: .any)["profile-identity-card"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["profile-backup-export-button"].exists)

        let settings = app.buttons["profile-settings-entry"]
        scrollUntilVisible(settings, in: app)
        XCTAssertTrue(settings.isHittable)
        settings.tap()
        XCTAssertTrue(app.navigationBars["设置"].waitForExistence(timeout: 5))
        keepScreenshot(named: "Final Atlas Settings Root", of: app)

        let account = app.buttons["settings-account-entry"]
        XCTAssertTrue(account.waitForExistence(timeout: 3))
        account.tap()
        XCTAssertTrue(app.navigationBars["账户与安全"].waitForExistence(timeout: 3))
        XCTAssertEqual(app.staticTexts["settings-tastemap-user-id"].label, "tm_p3a_ui_fixture")
        let editProfile = app.buttons["settings-edit-profile"]
        XCTAssertTrue(editProfile.exists)
        XCTAssertTrue(app.buttons["settings-sign-out"].exists)
        editProfile.tap()
        XCTAssertTrue(app.navigationBars["编辑资料"].waitForExistence(timeout: 3))
        app.navigationBars["编辑资料"].buttons["profile-back-button"].tap()
        app.navigationBars["账户与安全"].buttons["设置"].tap()

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
        keepScreenshot(named: "Final Atlas Backup Export Privacy", of: app)
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
        keepScreenshot(named: "Final Atlas Sync Pending", of: app)
        app.navigationBars["同步"].buttons["设置"].tap()

        let permissions = app.buttons["settings-permissions-entry"]
        scrollUntilVisible(permissions, in: app)
        permissions.tap()
        XCTAssertTrue(app.navigationBars["权限"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.descendants(matching: .any)["settings-location-permission"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["settings-photo-permission"].exists)
        XCTAssertTrue(app.buttons["settings-location-permission"].exists)
        XCTAssertTrue(app.buttons["settings-photo-permission"].exists)
        XCTAssertFalse(app.buttons["settings-open-system-settings"].exists)
        keepScreenshot(named: "Final Atlas Permissions", of: app)
        app.navigationBars["权限"].buttons["设置"].tap()

        let about = app.buttons["settings-about-entry"]
        scrollUntilVisible(about, in: app)
        about.tap()
        XCTAssertTrue(app.navigationBars["关于"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.descendants(matching: .any)["settings-app-version"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["settings-build-number"].exists)
        keepScreenshot(named: "Final Atlas About", of: app)
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
        keepScreenshot(named: "Final Atlas Import Preflight", of: app)

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
        keepScreenshot(named: "Final Atlas Import Blocking Error", of: app)
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
        keepScreenshot(named: "Final Atlas Import Plan", of: app)

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

        // Imported Restaurant detail is intentionally presented as a sheet
        // over the result list, so dismiss the sheet before walking the
        // NavigationStack back to the already-running Hybrid profile.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.09)).press(
            forDuration: 0.08,
            thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.82))
        )
        XCTAssertTrue(app.navigationBars["去过的餐厅"].waitForExistence(timeout: 5))
        let backToImportResult = app.navigationBars["去过的餐厅"].buttons["导入结果"]
        XCTAssertEqual(
            XCTWaiter.wait(
                for: [XCTNSPredicateExpectation(
                    predicate: NSPredicate(format: "isHittable == true"),
                    object: backToImportResult
                )],
                timeout: 5
            ),
            .completed
        )
        backToImportResult.tap()
        XCTAssertTrue(app.navigationBars["导入结果"].waitForExistence(timeout: 5))
        app.navigationBars["导入结果"].buttons["数据与备份"].tap()
        XCTAssertTrue(app.navigationBars["数据与备份"].waitForExistence(timeout: 5))
        app.navigationBars["数据与备份"].buttons["设置"].tap()
        XCTAssertTrue(app.navigationBars["设置"].waitForExistence(timeout: 5))
        app.navigationBars["设置"].buttons.firstMatch.tap()

        // WKWebView flattens its accessible descendants into the application
        // tree on current iOS versions, so query the stable control identifier
        // instead of depending on a WebView container element.
        let visitedStat = app.buttons["profile-stat-visited"]
        XCTAssertTrue(
            visitedStat.waitForExistence(timeout: 8),
            "The already-running Hybrid profile must remain visible after import"
        )
        XCTAssertEqual(
            visitedStat.label,
            "1, 去过",
            "The already-running Hybrid profile must refresh immediately after import"
        )
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
        XCTAssertTrue(segmentedOption("好友", in: app).exists)
        XCTAssertTrue(segmentedOption("关注", in: app).exists)
        XCTAssertTrue(segmentedOption("粉丝", in: app).exists)
        XCTAssertTrue(segmentedOption("推荐", in: app).exists)
        XCTAssertFalse(segmentedOption("找人", in: app).exists)
        XCTAssertFalse(segmentedOption("请求", in: app).exists)
        XCTAssertTrue(app.textFields["social-search-field"].exists)
        let inbox = app.buttons["social-collaboration-inbox"]
        XCTAssertTrue(inbox.exists)
        inbox.tap()
        XCTAssertTrue(app.navigationBars["协作收件箱"].waitForExistence(timeout: 3))
        app.buttons["完成"].tap()
        let privacyMessage = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "邮箱和 Apple 登录信息不能用于搜索")
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
        let note = app.descendants(matching: .any)["visit-editor-note"]
        XCTAssertTrue(note.waitForExistence(timeout: 2))
        XCTAssertTrue(app.textFields["visit-editor-party-size"].exists)
        let spend = app.textFields["visit-editor-spend"]
        scrollUntilVisible(spend, in: app)
        XCTAssertTrue(spend.exists)
        keepScreenshot(named: "Final Atlas Visit Core Form", of: app)

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
        scrollUntilReadable(metadata, in: app)
        XCTAssertTrue(metadata.waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["restaurant-call-phone"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["restaurant-opening-hours"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["restaurant-reference-price"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["restaurant-long-term-note"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["restaurant-website"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["restaurant-website-unavailable"].exists)
        XCTAssertFalse(app.staticTexts["官网"].exists)
        XCTAssertFalse(app.staticTexts["暂无官网"].exists)
        let location = app.otherElements["restaurant-detail-location"]
        scrollUntilReadable(location, in: app)
        XCTAssertTrue(location.waitForExistence(timeout: 3))
        XCTAssertLessThanOrEqual(location.frame.height, 80)
        XCTAssertTrue(app.buttons["open-in-apple-maps"].exists)
        let userPhotos = app.otherElements["restaurant-user-photos"]
        scrollUntilReadable(userPhotos, in: app)
        XCTAssertTrue(userPhotos.waitForExistence(timeout: 3))
        let personalOverview = app.otherElements["restaurant-detail-statistics"]
        scrollUntilReadable(personalOverview, in: app)
        XCTAssertTrue(personalOverview.waitForExistence(timeout: 3))
        let visitHistory = app.otherElements["restaurant-visit-history"]
        scrollUntilReadable(visitHistory, in: app)
        XCTAssertTrue(visitHistory.waitForExistence(timeout: 3))
        keepScreenshot(named: "Global Restaurant Detail Local After", of: app)

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
        // Re-open the editor to verify the persisted model values directly.
        // The read-only detail body is lazy, so one field can legitimately be
        // removed from the accessibility tree while the other is on screen.
        app.navigationBars["餐厅详情"].buttons["编辑"].tap()
        XCTAssertTrue(app.navigationBars["编辑餐厅"].waitForExistence(timeout: 5))
        let persistedAddress = app.textFields["restaurant-edit-address"]
        let persistedPhone = app.textFields["restaurant-edit-phone"]
        XCTAssertTrue(persistedAddress.waitForExistence(timeout: 3))
        XCTAssertTrue(persistedPhone.waitForExistence(timeout: 3))
        XCTAssertEqual(persistedAddress.value as? String, "杭州市上城区任务三新地址 88 号")
        XCTAssertEqual(persistedPhone.value as? String, "+86 571 8765 4321")
        app.buttons["取消"].tap()
        XCTAssertTrue(app.navigationBars["餐厅详情"].waitForExistence(timeout: 5))

        app.buttons["restaurant-detail-add-visit"].tap()
        XCTAssertTrue(app.navigationBars["新增到访"].waitForExistence(timeout: 5))
        app.buttons["visit-editor-save"].tap()
        let visitedStatus = app.staticTexts["restaurant-status-visited"]
        scrollTowardTopUntilReadable(visitedStatus, in: app)
        XCTAssertTrue(visitedStatus.waitForExistence(timeout: 5))
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
        // Free visits now allow two photos. Keep this
        // P2-B flow on the Free contract while still covering multi-photo
        // persistence and independent deletion.
        for _ in 0..<2 {
            scrollUntilVisible(importButton, in: app)
            importButton.tap()
            XCTAssertTrue(app.staticTexts["本机"].waitForExistence(timeout: 5))
        }
        XCTAssertTrue(app.staticTexts["2/2"].waitForExistence(timeout: 5))
        XCTAssertFalse(importButton.exists)
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
        XCTAssertTrue(app.staticTexts["2 张"].waitForExistence(timeout: 5))
        let photo = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH 'restaurant-photo-'")
        ).firstMatch
        XCTAssertTrue(photo.waitForExistence(timeout: 5))
        photo.tap()
        XCTAssertTrue(app.navigationBars["1 / 2"].waitForExistence(timeout: 5))
        app.buttons["完成"].tap()

        app.swipeUp()
        let firstVisit = app.staticTexts["第 1 次"]
        XCTAssertTrue(firstVisit.waitForExistence(timeout: 5))
        firstVisit.tap()
        XCTAssertTrue(app.navigationBars["编辑到访"].waitForExistence(timeout: 5))
        for _ in 0..<2 {
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
        keepScreenshot(named: "Round 2 Dish Photo Legacy Final Candidate", of: app)
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
        keepScreenshot(named: "Final Atlas Visit Rich Photo Dish Context", of: app)
        let value = app.buttons["性价比 5.0 星"]
        scrollUntilVisible(value, in: app)
        XCTAssertTrue(value.waitForExistence(timeout: 3))
        value.tap()
        let environment = app.buttons["环境 4.0 星"]
        scrollUntilVisible(environment, in: app)
        environment.tap()
        let service = app.buttons["服务 3.5 星"]
        scrollUntilVisible(service, in: app)
        service.tap()
        keepScreenshot(named: "Final Atlas Visit Detailed Ratings", of: app)

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
        let detailedRating = app.descendants(matching: .any)["restaurant-detailed-rating-value"]
        scrollUntilReadable(detailedRating, in: app)
        XCTAssertTrue(detailedRating.waitForExistence(timeout: 5))

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
        selectPicker("visit-editor-queue-duration", option: "无需排队", in: app)
        let friends = app.buttons["visit-editor-dining-occasions-friends"]
        scrollUntilVisible(friends, in: app)
        XCTAssertTrue(friends.waitForExistence(timeout: 3))
        friends.tap()

        selectPicker("visit-editor-payment-mode", option: "AA", in: app)
        let total = app.textFields["visit-editor-spend"]
        scrollUntilVisible(total, in: app)
        XCTAssertTrue(total.exists)
        total.tap()
        total.typeText("360")
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
        XCTAssertTrue(app.descendants(matching: .any)["profile-identity-card"].waitForExistence(timeout: 5))
        keepScreenshot(named: "Final Atlas Profile Premium Analytics", of: app)
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

        XCTAssertFalse(app.buttons["taste-profile-share-toolbar"].exists)
        let share = app.buttons["taste-profile-share-poster"]
        scrollToTop(in: app)
        scrollUntilVisible(share, in: app)
        XCTAssertTrue(share.waitForExistence(timeout: 5))
        share.tap()
        XCTAssertTrue(app.navigationBars["分享海报"].waitForExistence(timeout: 8))
        let posterPreview = app.images["analysis-poster-preview"]
        XCTAssertTrue(posterPreview.waitForExistence(timeout: 10))
        XCTAssertEqual(posterPreview.value as? String, "缩放 100%")
        posterPreview.pinch(withScale: 1.8, velocity: 1)
        let zoomChanged = NSPredicate { value, _ in
            guard let element = value as? XCUIElement,
                  let zoomValue = element.value as? String else { return false }
            return zoomValue != "缩放 100%"
        }
        XCTAssertEqual(
            XCTWaiter.wait(
                for: [XCTNSPredicateExpectation(predicate: zoomChanged, object: posterPreview)],
                timeout: 3
            ),
            .completed,
            "The poster preview must respond to an in-place pinch gesture"
        )
        let enlargedValue = posterPreview.value as? String
        XCTAssertTrue(app.buttons["analysis-poster-save"].exists)
        XCTAssertTrue(app.buttons["analysis-poster-system-share"].exists)
        keepScreenshot(named: "P4-A 9x16 Poster Zoomed", of: app)
        posterPreview.pinch(withScale: 0.5, velocity: -1)
        let zoomReduced = NSPredicate { value, _ in
            guard let element = value as? XCUIElement,
                  let zoomValue = element.value as? String else { return false }
            return zoomValue != enlargedValue
        }
        XCTAssertEqual(
            XCTWaiter.wait(
                for: [XCTNSPredicateExpectation(predicate: zoomReduced, object: posterPreview)],
                timeout: 3
            ),
            .completed,
            "The poster preview must support shrinking without leaving the page"
        )
    }

    @MainActor
    func testP4BDiningCompanionAnalysisRefreshAndPoster() throws {
        let app = XCUIApplication()
        app.launchEnvironment = ["TASTEMAP_P4B_COMPANION_UI_TEST": "1"]
        app.launch()

        app.buttons["我的"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["profile-identity-card"].waitForExistence(timeout: 5))
        let entry = app.buttons["profile-companion-analysis-entry"]
        scrollUntilVisible(entry, in: app)
        // Move the card clear of the custom bottom navigation before tapping.
        // On iOS 26 XCTest can report a partially covered card as hittable even
        // though the synthesized tap is consumed by the navigation overlay.
        app.swipeUp(velocity: .slow)
        XCTAssertTrue(entry.isHittable)
        entry.tap()

        XCTAssertTrue(app.navigationBars["最佳饭搭子"].waitForExistence(timeout: 8))
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
        app.navigationBars["你和 小林"].buttons["最佳饭搭子"].tap()
        XCTAssertTrue(app.navigationBars["最佳饭搭子"].waitForExistence(timeout: 8))
        XCTAssertTrue(lead.waitForExistence(timeout: 8))
        lead.tap()
        XCTAssertTrue(app.navigationBars["你和 小林"].waitForExistence(timeout: 8))
        let updated = app.staticTexts["15 次"]
        scrollUntilVisible(updated, in: app)
        XCTAssertTrue(updated.waitForExistence(timeout: 8))

        XCTAssertFalse(app.buttons["companion-analysis-share-toolbar"].exists)
        let share = app.buttons["companion-analysis-share-poster"]
        scrollToTop(in: app)
        scrollUntilVisible(share, in: app)
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
        XCTAssertTrue(app.descendants(matching: .any)["profile-identity-card"].waitForExistence(timeout: 5))
        let entry = app.buttons["profile-recommendation-source-analysis-entry"]
        scrollUntilVisible(entry, in: app)
        XCTAssertTrue(entry.isHittable)
        entry.tap()

        XCTAssertTrue(app.navigationBars["谁最会种草"].waitForExistence(timeout: 8))
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

        app.navigationBars["小林的私藏清单"].buttons["谁最会种草"].tap()
        XCTAssertTrue(app.navigationBars["谁最会种草"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["recommendation-source-share-toolbar"].exists)
        let share = app.buttons["recommendation-source-share-poster"]
        scrollToTop(in: app)
        scrollUntilVisible(share, in: app)
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
        app.navigationBars["小林的私藏清单"].buttons["谁最会种草"].tap()
        XCTAssertTrue(app.navigationBars["谁最会种草"].waitForExistence(timeout: 8))
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
        XCTAssertTrue(app.descendants(matching: .any)["profile-identity-card"].waitForExistence(timeout: 5))
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

        XCTAssertFalse(app.buttons["monthly-recap-share-toolbar"].exists)
        let share = app.buttons["monthly-recap-share-poster"]
        scrollUntilVisible(share, in: app)
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
        scrollToTop(in: app)
        XCTAssertTrue(previous.waitForExistence(timeout: 8))
        previous.tap()
        let calendar = Calendar.current
        let previousMonth = calendar.date(byAdding: .month, value: -1, to: .now) ?? .now
        let previousComponents = calendar.dateComponents([.year, .month], from: previousMonth)
        let previousMonthLabel = "\(previousComponents.year ?? 0) 年 \(previousComponents.month ?? 0) 月"
        XCTAssertTrue(app.staticTexts[previousMonthLabel].waitForExistence(timeout: 8))
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
        XCTAssertTrue(app.descendants(matching: .any)["profile-identity-card"].waitForExistence(timeout: 5))
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

        XCTAssertFalse(app.buttons["annual-recap-share-toolbar"].exists)
        let share = app.buttons["annual-recap-share-poster"]
        scrollUntilVisible(share, in: app)
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
        keepScreenshot(named: "Full Layout Closure Canonical Empty State", of: app)
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
    func testP4GRouletteLargeLibraryUsesTenRealOneToOneSegments() throws {
        let app = launchP4GRouletteFixture(environmentKey: "TASTEMAP_P4G_ROULETTE_LARGE_UI_TEST")
        openP4GRoulette(in: app)
        XCTAssertTrue(app.staticTexts["roulette-candidate-count"].label.contains("10"))
        XCTAssertTrue(app.buttons["roulette-spin"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["候选库 120 家 · 最多选择 10 家"].exists)
        XCTAssertFalse(app.staticTexts["完整候选池参与随机，轮盘仅做简化展示"].exists)
        XCTAssertEqual(
            app.descendants(matching: .any).matching(
                NSPredicate(format: "identifier BEGINSWITH 'roulette-candidate-chip-'")
            ).count,
            10
        )
        keepScreenshot(named: "P4-G Large Candidate Pool", of: app)
    }

    @MainActor
    func testFinalAtlasRouletteDark() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-p1d-persistent-offline-fixture",
            "-p1d-reset-persistent-offline-fixture",
            "-AppleInterfaceStyle",
            "Dark",
        ]
        app.launchEnvironment = [
            "TASTEMAP_P1D_UI_TEST": "1",
            "TASTEMAP_P1D_RESET": "1",
            "TASTEMAP_P4G_ROULETTE_LARGE_UI_TEST": "1",
        ]
        app.launch()

        openP4GRoulette(in: app)
        XCTAssertTrue(app.staticTexts["roulette-candidate-count"].label.contains("10"))
        XCTAssertTrue(app.buttons["roulette-spin"].waitForExistence(timeout: 5))
        keepScreenshot(named: "Final Atlas Roulette Dark", of: app)
    }

    @MainActor
    func testFinalAtlasRouletteLargeText() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-p1d-persistent-offline-fixture", "-p1d-reset-persistent-offline-fixture"]
        app.launchEnvironment = [
            "TASTEMAP_P1D_UI_TEST": "1",
            "TASTEMAP_P1D_RESET": "1",
            "TASTEMAP_P4G_ROULETTE_LARGE_UI_TEST": "1",
        ]
        app.launch()

        openP4GRoulette(in: app)
        XCTAssertTrue(app.staticTexts["roulette-candidate-count"].label.contains("10"))
        XCTAssertTrue(app.buttons["roulette-spin"].waitForExistence(timeout: 5))
        keepScreenshot(named: "Final Atlas Roulette Large Text", of: app)
    }

    @MainActor
    func testP4GRouletteCandidateManagerSupportsTemporaryNameAndOfficialRestaurantFlow() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-p1d-persistent-offline-fixture", "-p1d-reset-persistent-offline-fixture"]
        app.launchEnvironment = [
            "TASTEMAP_P1D_UI_TEST": "1", "TASTEMAP_P1D_RESET": "1",
            "TASTEMAP_P4G_ROULETTE_UI_TEST": "1",
            "TASTEMAP_RESTAURANT_ACQUISITION_UI_TEST": "1",
        ]
        app.launch()

        openP4GRoulette(in: app)
        app.buttons["roulette-manage-candidates"].tap()
        XCTAssertTrue(app.navigationBars["管理候选餐厅"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.searchFields["搜索我的餐厅"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["roulette-manager-source"].exists)
        XCTAssertTrue(app.buttons["roulette-apply-candidates"].exists)

        segmentedOption("想吃", in: app).tap()
        app.searchFields["搜索我的餐厅"].tap()
        app.searchFields["搜索我的餐厅"].typeText("西湖")
        XCTAssertTrue(
            app.descendants(matching: .any).matching(
                NSPredicate(format: "identifier BEGINSWITH 'roulette-candidate-toggle-'")
            ).count > 0
        )
        dismissSearchKeyboard(in: app)

        let customName = "Lafayette 夜宵自选"
        let temporaryName = app.textFields["roulette-custom-candidate-name"]
        scrollUntilVisible(temporaryName, in: app)
        XCTAssertTrue(temporaryName.isHittable)
        temporaryName.tap()
        temporaryName.typeText(customName)
        let addTemporary = app.buttons["roulette-add-temporary-candidate"]
        XCTAssertTrue(addTemporary.isEnabled)
        addTemporary.tap()
        XCTAssertTrue(app.staticTexts[customName].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["roulette-custom-candidate-message"].label.contains("已将"))
        dismissSearchKeyboard(in: app)
        let createRestaurant = app.buttons["roulette-create-restaurant"]
        scrollUntilVisible(createRestaurant, in: app)
        XCTAssertTrue(createRestaurant.exists)
        createRestaurant.tap()
        XCTAssertTrue(app.navigationBars["手动添加餐厅"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.textFields["manual-restaurant-name"].exists)
        XCTAssertTrue(app.textFields["manual-restaurant-city"].exists)
        XCTAssertTrue(app.otherElements["manual-restaurant-map"].exists)
        XCTAssertFalse(app.buttons["manual-confirm-restaurant"].exists)
        keepScreenshot(named: "P4-G Candidate Manager To Manual Add", of: app)
    }

    @MainActor
    func testSignupTrialHybridClaim() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--tastemap-hybrid-development", "-AppleInterfaceStyle", "Light"]
        app.launchEnvironment = ["TASTEMAP_VISUAL_QA_MODE": "rich", "TASTEMAP_SIGNUP_TRIAL_UI_TEST": "1", "TASTEMAP_CORE_PARITY_INITIAL_TAB": "profile"]
        app.launch()
        let web = app.webViews.firstMatch
        XCTAssertTrue(web.waitForExistence(timeout: 20))
        XCTAssertTrue(web.buttons["我的"].waitForExistence(timeout: 15)); web.buttons["我的"].tap()
        let settings = web.buttons["设置"]
        XCTAssertTrue(settings.waitForExistence(timeout: 15)); settings.tap()
        let entry = web.buttons.matching(NSPredicate(format: "label CONTAINS 'Premium' AND label CONTAINS '查看'")).firstMatch
        XCTAssertTrue(entry.waitForExistence(timeout: 10)); entry.tap()
        let claim = web.buttons["免费领取 7 天"]
        XCTAssertTrue(claim.waitForExistence(timeout: 15))
        keepScreenshot(named: "Signup Trial Hybrid Eligible", of: app)
        claim.tap()
        XCTAssertTrue(web.staticTexts.matching(NSPredicate(format: "label CONTAINS '领取成功'")).firstMatch.waitForExistence(timeout: 10))
        XCTAssertFalse(claim.exists)
        keepScreenshot(named: "Signup Trial Hybrid Claimed", of: app)
    }

    @MainActor
    func testSignupTrialNativeClaim() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleInterfaceStyle", "Light"]
        app.launchEnvironment = ["TASTEMAP_VISUAL_QA_MODE": "rich", "TASTEMAP_SIGNUP_TRIAL_UI_TEST": "1", "TASTEMAP_CORE_PARITY_INITIAL_TAB": "profile"]
        app.launch()
        let entry = app.buttons["profile-premium-entry"]
        XCTAssertTrue(entry.waitForExistence(timeout: 8)); entry.tap()
        let claim = app.buttons["premium-signup-trial-claim"]
        XCTAssertTrue(claim.waitForExistence(timeout: 8))
        XCTAssertTrue(app.descendants(matching: .any)["premium-status-free"].exists)
        XCTAssertTrue(app.staticTexts["无需订阅，不会自动续费"].exists)
        keepScreenshot(named: "Signup Trial Native Eligible", of: app)
        claim.tap()
        let message = app.staticTexts["premium-signup-trial-message"]
        XCTAssertTrue(message.waitForExistence(timeout: 8))
        XCTAssertTrue(message.label.contains("领取成功"))
        XCTAssertFalse(claim.exists)
        XCTAssertTrue(app.descendants(matching: .any)["premium-status-active"].exists)
        keepScreenshot(named: "Signup Trial Native Claimed", of: app)
    }

    @MainActor
    func testP4HFreeProfilePaywallFeatureGateAndDevelopmentUpgrade() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleInterfaceStyle", "Light"]
        app.launchEnvironment = [
            "TASTEMAP_P4A_ANALYSIS_UI_TEST": "1",
            "TASTEMAP_P4H_PREMIUM_UI_TEST": "free",
        ]
        app.launch()

        app.buttons["我的"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["profile-identity-card"].waitForExistence(timeout: 5))
        keepScreenshot(named: "Final Atlas Profile Free", of: app)
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
    func testCoreProductParityPremiumProfileUsesApprovedHamburgerBadge() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleInterfaceStyle", "Light"]
        app.launchEnvironment = [
            "TASTEMAP_P4A_ANALYSIS_UI_TEST": "1",
            "TASTEMAP_P4H_PREMIUM_UI_TEST": "premium",
        ]
        app.launch()

        app.buttons["我的"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["profile-identity-card"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["profile-premium-badge-entry"].waitForExistence(timeout: 5))
        keepScreenshot(named: "Core Parity Approved Premium Hamburger", of: app)
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
        XCTAssertTrue(app.descendants(matching: .any)["profile-identity-card"].waitForExistence(timeout: 5))
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
        if searchKey.exists {
            searchKey.tap()
            return
        }
        let doneKey = app.keyboards.buttons["Done"]
        if doneKey.exists {
            doneKey.tap()
        }
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
        XCTAssertTrue(app.descendants(matching: .any)["profile-identity-card"].waitForExistence(timeout: 5))
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
    private func scrollMemoryElement(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<12 where !element.isHittable || element.frame.maxY > app.frame.maxY - 100 {
            app.webViews.firstMatch.swipeUp(velocity: .slow)
        }
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
    private func scrollToTop(in app: XCUIApplication) {
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.28))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.76))
        for _ in 0..<12 {
            start.press(forDuration: 0.03, thenDragTo: end)
        }
    }

    /// Moves the first Hybrid Discovery card below the fixed page controls so
    /// its identity, evidence block, and complete two-group footer fit in one
    /// device screenshot. This is evidence framing only; it does not mutate UI.
    @MainActor
    private func scrollDiscoveryCardIntoView(in app: XCUIApplication) {
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.72))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.43))
        start.press(forDuration: 0.05, thenDragTo: end)
    }

    @MainActor
    private func launchHybridDiscoveryFooter() -> (XCUIApplication, XCUIElement) {
        var lastApp: XCUIApplication?
        for _ in 0..<2 {
            let app = XCUIApplication()
            lastApp = app
            app.launchArguments = ["--tastemap-hybrid-development", "-AppleInterfaceStyle", "Light"]
            app.launchEnvironment = ["TASTEMAP_VISUAL_QA_MODE": "rich"]
            app.launch()
            let webView = app.webViews.firstMatch
            guard webView.waitForExistence(timeout: 20) else {
                app.terminate()
                continue
            }
            let discovery = webView.buttons["发现"]
            guard discovery.waitForExistence(timeout: 8) else {
                app.terminate()
                continue
            }
            discovery.tap()
            guard webView.buttons["为你推荐"].waitForExistence(timeout: 12) else {
                // The iOS 26.5 simulator occasionally loses WebKit's
                // accessibility tree between rapid independent launches.
                app.terminate()
                continue
            }
            let record = webView.buttons.matching(
                NSPredicate(
                    format: "label BEGINSWITH %@ OR label BEGINSWITH %@ OR label BEGINSWITH %@",
                    "记录 ", "再次添加 ", "加入餐厅 "
                )
            ).firstMatch
            guard record.waitForExistence(timeout: 8) else {
                app.terminate()
                continue
            }
            scrollDiscoveryCardIntoView(in: app)
            return (app, webView)
        }

        XCTFail("Unable to open the Hybrid Discovery footer after one accessibility relaunch")
        let app = lastApp ?? XCUIApplication()
        return (app, app.webViews.firstMatch)
    }

    /// Selects the first card's restaurant-qualified action. The accessible
    /// label includes the Restaurant name, so this never scans every repeated
    /// action in WebKit's full offscreen tree.
    @MainActor
    private func visibleDiscoveryAction(
        _ label: String,
        in webView: XCUIElement,
        app: XCUIApplication,
        near preferredFrame: CGRect? = nil
    ) -> XCUIElement {
        let query = webView.descendants(matching: .any).matching(
            NSPredicate(format: "label BEGINSWITH %@", "\(label) ")
        )
        let action = query.firstMatch
        XCTAssertTrue(action.waitForExistence(timeout: 8), "Missing Discovery action named \(label)")
        let visible = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: action)
        XCTAssertEqual(XCTWaiter.wait(for: [visible], timeout: 8), .completed, "Discovery action named \(label) is not visible")
        if let preferredFrame {
            XCTAssertLessThan(abs(action.frame.midY - preferredFrame.midY), 80, "Discovery action changed a different Card")
        }
        return action
    }

    @MainActor
    private func tapVisibleFrame(of element: XCUIElement, in app: XCUIApplication) {
        let origin = app.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0))
        origin.withOffset(CGVector(dx: element.frame.midX, dy: element.frame.midY)).tap()
    }

    @MainActor
    private func waitUntilEnabled(_ element: XCUIElement, timeout: TimeInterval = 8) {
        let enabled = NSPredicate { value, _ in
            (value as? XCUIElement)?.isEnabled == true
        }
        let result = XCTWaiter.wait(
            for: [XCTNSPredicateExpectation(predicate: enabled, object: element)],
            timeout: timeout
        )
        XCTAssertEqual(result, .completed, "Discovery mutation did not reach its authoritative settled state")
    }

    /// Scrolls read-only section containers into the visible viewport without
    /// requiring them to become hittable. Structural accessibility elements
    /// intentionally have no tap action, so using `isHittable` would always
    /// exhaust the gesture budget even after the section is on screen.
    @MainActor
    private func scrollUntilReadable(_ element: XCUIElement, in app: XCUIApplication) {
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.68))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.24))
        let readableViewport = CGRect(
            x: app.frame.minX,
            y: app.frame.minY + 72,
            width: app.frame.width,
            height: max(1, app.frame.height - 164)
        )

        for _ in 0..<16 {
            if element.exists, element.frame.intersects(readableViewport) {
                return
            }
            start.press(forDuration: 0.05, thenDragTo: end)
        }
    }

    /// Returns toward the beginning of a lazy detail body until a read-only
    /// element is materialized and inside the visible viewport.
    @MainActor
    private func scrollTowardTopUntilReadable(_ element: XCUIElement, in app: XCUIApplication) {
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.26))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.72))
        let readableViewport = CGRect(
            x: app.frame.minX,
            y: app.frame.minY + 72,
            width: app.frame.width,
            height: max(1, app.frame.height - 164)
        )

        for _ in 0..<16 {
            if element.exists, element.frame.intersects(readableViewport) {
                return
            }
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
        if identifier == "visit-editor-queue-duration" || identifier == "visit-editor-payment-mode" {
            let directChoice = app.buttons["\(title)：\(option)"]
            scrollUntilVisible(directChoice, in: app)
            XCTAssertTrue(directChoice.waitForExistence(timeout: 3))
            directChoice.tap()
            return
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
        if nativeOption.exists { return nativeOption }
        let exactButton = app.buttons[label]
        if exactButton.exists { return exactButton }
        return app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "\(label)，")
        ).firstMatch
    }

    @MainActor
    private func keepScreenshot(named name: String, of app: XCUIApplication) {
        let screenshot = app.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        guard let outputDirectory = ProcessInfo.processInfo.environment["TASTEMAP_SCREENSHOT_OUTPUT_DIR"],
              !outputDirectory.isEmpty else { return }
        let safeName = name.lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: "/", with: "-")
        let directory = URL(fileURLWithPath: outputDirectory, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? screenshot.pngRepresentation.write(to: directory.appendingPathComponent("\(safeName).png"))
    }

    @MainActor
    private func keepScreenScreenshot(named name: String) {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        guard let outputDirectory = ProcessInfo.processInfo.environment["TASTEMAP_SCREENSHOT_OUTPUT_DIR"],
              !outputDirectory.isEmpty else { return }
        let safeName = name.lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: "/", with: "-")
        let directory = URL(fileURLWithPath: outputDirectory, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? screenshot.pngRepresentation.write(to: directory.appendingPathComponent("\(safeName).png"))
    }

    @MainActor
    func testTask09RichVisualQAPremiumAccessibilityPath() throws {
        let app = XCUIApplication()
        app.launchEnvironment = [
            "TASTEMAP_VISUAL_QA_MODE": "rich",
            "UIPreferredContentSizeCategoryName": "UICTContentSizeCategoryAccessibilityExtraExtraLarge",
        ]
        app.launchArguments = ["-AppleInterfaceStyle", "Light"]
        app.launch()

        XCTAssertTrue(app.staticTexts["map-home-title"].waitForExistence(timeout: 15))
        XCTAssertEqual(app.staticTexts["map-home-title"].label, "我的地图")
        XCTAssertTrue(app.maps.firstMatch.waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["map-header-view-list"].exists)
        keepScreenshot(named: "Task09-Rich-Map-Accessibility", of: app)

        app.buttons["app-tab-discover"].tap()
        XCTAssertTrue(app.staticTexts["discovery-header"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["discovery-primary-following"].exists)
        XCTAssertTrue(app.buttons["discovery-primary-similarTaste"].exists)
        XCTAssertTrue(app.buttons["discovery-primary-trending"].exists)
        keepScreenshot(named: "Task09-Rich-Discovery-Accessibility", of: app)

        app.buttons["app-tab-profile"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["profile-stat-visited"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any)["profile-premium-badge-entry"].exists)
        XCTAssertTrue(app.buttons["profile-taste-analysis-entry"].exists)
        keepScreenshot(named: "Task09-Rich-Profile-Premium", of: app)
    }

    @MainActor
    func testReferralDashboardAndShareInHybridAndNative() throws {
        for hybrid in [true,false] {
            let app = XCUIApplication()
            app.launchArguments = hybrid ? ["--tastemap-hybrid-development", "-AppleInterfaceStyle", "Light"] : ["-AppleInterfaceStyle", "Light"]
            app.launchEnvironment = ["TASTEMAP_VISUAL_QA_MODE":"rich","TASTEMAP_REFERRAL_UI_TEST":"1","TASTEMAP_CORE_PARITY_INITIAL_TAB":"profile"]
            app.launch()
            if hybrid {
                let web = app.webViews.firstMatch
                XCTAssertTrue(web.buttons["我的"].waitForExistence(timeout:20)); web.buttons["我的"].tap()
                XCTAssertTrue(web.buttons["设置"].waitForExistence(timeout:15)); web.buttons["设置"].tap()
                let entry = web.buttons.matching(NSPredicate(format:"label CONTAINS '邀请好友'")).firstMatch
                XCTAssertTrue(entry.waitForExistence(timeout:15)); entry.tap()
                XCTAssertTrue(app.staticTexts["已成功邀请 2/5"].waitForExistence(timeout:15))
            } else {
                let settings = app.buttons["profile-settings-header-entry"]
                XCTAssertTrue(settings.waitForExistence(timeout:15)); settings.tap()
                let entry = app.buttons["settings-referral-entry"]
                XCTAssertTrue(entry.waitForExistence(timeout:10)); entry.tap()
                XCTAssertTrue(app.staticTexts.matching(NSPredicate(format:"label CONTAINS '2/5'")).firstMatch.waitForExistence(timeout:15))
            }
            keepScreenshot(named:"Referral-\(hybrid ? "Hybrid" : "Native")",of:app)
            if hybrid {
                app.webViews.buttons["返回上一页"].tap()
                let entry=app.webViews.buttons.matching(NSPredicate(format:"label CONTAINS '邀请好友'")).firstMatch
                XCTAssertTrue(entry.waitForExistence(timeout:10));entry.tap()
                XCTAssertTrue(app.staticTexts["已成功邀请 2/5"].waitForExistence(timeout:10))
            } else {
                app.navigationBars["邀请好友"].buttons["设置"].tap()
                let entry=app.buttons["settings-referral-entry"]
                XCTAssertTrue(entry.waitForExistence(timeout:10));entry.tap()
            }
            let share = hybrid ? app.webViews.buttons.matching(NSPredicate(format:"label CONTAINS '分享邀请链接'")).firstMatch : app.buttons["referral-share-link"]
            XCTAssertTrue(share.exists); share.tap()
            XCTAssertTrue(app.buttons["拷贝"].waitForExistence(timeout:10) || app.buttons["Copy"].exists || app.otherElements["ActivityListView"].exists)
            keepScreenshot(named:"Referral-Share-\(hybrid ? "Hybrid" : "Native")",of:app)
            app.terminate()
        }
    }

    @MainActor
    func testGiftPremiumStatusUsesAuthoritativeSourceInHybridAndNative() throws {
        for hybrid in [true, false] {
            for source in ["giftAnnual", "giftLifetime"] {
                let app = XCUIApplication()
                app.launchArguments = hybrid ? ["--tastemap-hybrid-development", "-AppleInterfaceStyle", "Light"] : ["-AppleInterfaceStyle", "Light"]
                app.launchEnvironment = ["TASTEMAP_VISUAL_QA_MODE": "rich", "TASTEMAP_P4H_PREMIUM_UI_TEST": source,
                    "TASTEMAP_CORE_PARITY_INITIAL_TAB": "profile"]
                app.launch()
                if hybrid {
                    let web = app.webViews.firstMatch
                    XCTAssertTrue(web.waitForExistence(timeout: 20))
                    XCTAssertTrue(web.buttons["我的"].waitForExistence(timeout: 15))
                    web.buttons["我的"].tap()
                    let settings = web.buttons["设置"]
                    XCTAssertTrue(settings.waitForExistence(timeout: 15))
                    settings.tap()
                    let entry = web.buttons.matching(NSPredicate(format: "label CONTAINS 'Premium' AND label CONTAINS '查看'")).firstMatch
                    XCTAssertTrue(entry.waitForExistence(timeout: 10))
                    entry.tap()
                } else {
                    let entry = app.buttons["profile-premium-badge-entry"]
                    XCTAssertTrue(entry.waitForExistence(timeout: 15))
                    entry.tap()
                }
                let text = source == "giftLifetime" ? "永久会员 · 由 Taste Map 赠送" : "赠送会员 · 有效期至"
                XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch.waitForExistence(timeout: 15))
                XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label CONTAINS '管理订阅' OR label CONTAINS '管理 App Store' OR label CONTAINS '管理会员'")).firstMatch.exists)
                keepScreenshot(named: "Gift-\(source)-\(hybrid ? "Hybrid" : "Native")", of: app)
                app.terminate()
            }
        }
    }

    @MainActor
    func testDynamicTypeP1AccessibilityExtraExtraLargeClosure() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleInterfaceStyle", "Light"]
        app.launchEnvironment = [
            "TASTEMAP_VISUAL_QA_MODE": "rich",
            "TASTEMAP_CORE_PARITY_INITIAL_TAB": "profile",
        ]
        app.launch()

        let addRestaurant = app.buttons["addRestaurantButton"]
        let mapTab = app.buttons["app-tab-map"]
        let discoverTab = app.buttons["app-tab-discover"]
        let profileTab = app.buttons["app-tab-profile"]
        XCTAssertTrue(profileTab.waitForExistence(timeout: 5))
        XCTAssertFalse(addRestaurant.exists)
        XCTAssertTrue(mapTab.isHittable)
        XCTAssertTrue(discoverTab.isHittable)
        XCTAssertTrue(profileTab.isHittable)
        XCTAssertFalse(mapTab.frame.intersects(discoverTab.frame))
        XCTAssertFalse(discoverTab.frame.intersects(profileTab.frame))

        let rouletteEntry = app.buttons["profile-restaurant-roulette-entry"]
        scrollUntilVisible(rouletteEntry, in: app)
        XCTAssertTrue(rouletteEntry.isHittable)
        keepScreenshot(named: "Dynamic Type P1 Profile XX Large", of: app)
        rouletteEntry.tap()

        XCTAssertTrue(app.navigationBars["今天吃什么"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["addRestaurantButton"].exists)
        XCTAssertTrue(app.staticTexts["roulette-candidate-count"].exists)
        let manageCandidates = app.buttons["roulette-manage-candidates"]
        scrollUntilVisible(manageCandidates, in: app)
        XCTAssertTrue(manageCandidates.isHittable)
        XCTAssertGreaterThanOrEqual(manageCandidates.frame.height, 44)
        keepScreenshot(named: "Dynamic Type P1 Roulette XX Large", of: app)

        app.terminate()
        app.launchEnvironment = [
            "TASTEMAP_VISUAL_QA_MODE": "rich",
            "TASTEMAP_CORE_PARITY_INITIAL_TAB": "discover",
        ]
        app.launch()

        XCTAssertTrue(app.staticTexts["discovery-header"].waitForExistence(timeout: 12))
        XCTAssertTrue(app.buttons["discovery-primary-forYou"].isHittable)
        XCTAssertTrue(app.buttons["discovery-city-menu"].isHittable)
        XCTAssertTrue(app.buttons["discovery-filters"].isHittable)
        XCTAssertFalse(app.buttons["addRestaurantButton"].exists)
        keepScreenshot(named: "Dynamic Type P1 Discovery XX Large", of: app)
    }

    @MainActor
    func testFinalVisualAcceptanceVisualQAStateAtlas() throws {
        let app = XCUIApplication()

        app.launchArguments = ["-AppleInterfaceStyle", "Light"]
        app.launchEnvironment = ["TASTEMAP_VISUAL_QA_MODE": "empty"]
        app.launch()
        XCTAssertTrue(app.staticTexts["map-home-title"].waitForExistence(timeout: 15))
        app.buttons["app-tab-profile"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["profile-identity-card"].waitForExistence(timeout: 8))
        keepScreenshot(named: "Final Atlas Visual QA Empty Profile", of: app)

        app.terminate()
        app.launchArguments = ["-AppleInterfaceStyle", "Light"]
        app.launchEnvironment = ["TASTEMAP_VISUAL_QA_MODE": "long-text"]
        app.launch()
        XCTAssertTrue(app.staticTexts["map-home-title"].waitForExistence(timeout: 15))
        app.buttons["app-tab-profile"].tap()
        XCTAssertTrue(app.staticTexts["Lafayette · 丰富美食档案"].waitForExistence(timeout: 8))
        keepScreenshot(named: "Final Atlas Visual QA Long Text Profile", of: app)

        app.terminate()
        app.launchArguments = ["-AppleInterfaceStyle", "Light"]
        app.launchEnvironment = ["TASTEMAP_VISUAL_QA_MODE": "missing-photo"]
        app.launch()
        XCTAssertTrue(app.staticTexts["map-home-title"].waitForExistence(timeout: 15))
        app.buttons["map-header-view-list"].tap()
        XCTAssertTrue(app.textFields["restaurant-list-search-field"].waitForExistence(timeout: 8))
        keepScreenshot(named: "Final Atlas Visual QA Missing Photo List", of: app)

        app.terminate()
        app.launchArguments = ["-AppleInterfaceStyle", "Light"]
        app.launchEnvironment = ["TASTEMAP_VISUAL_QA_MODE": "error"]
        app.launch()
        XCTAssertTrue(app.staticTexts["map-home-title"].waitForExistence(timeout: 15))
        app.buttons["app-tab-discover"].tap()
        XCTAssertTrue(app.staticTexts["discovery-header"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["重试"].firstMatch.waitForExistence(timeout: 10))
        keepScreenshot(named: "Final Atlas Visual QA Discovery Error", of: app)

        app.terminate()
        app.launchArguments = ["-AppleInterfaceStyle", "Dark"]
        app.launchEnvironment = ["TASTEMAP_VISUAL_QA_MODE": "rich"]
        app.launch()
        XCTAssertTrue(app.staticTexts["map-home-title"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.maps.firstMatch.waitForExistence(timeout: 10))
        keepScreenshot(named: "Final Atlas Visual QA Rich Map Dark", of: app)
    }

    @MainActor
    func testLegacyFusion02CanonicalRestaurantImagesAcrossMapListAndDetail() throws {
        let app = XCUIApplication()
        app.launchEnvironment = ["TASTEMAP_VISUAL_QA_MODE": "rich"]
        app.launchArguments = ["-AppleInterfaceStyle", "Light"]
        app.launch()

        XCTAssertTrue(app.staticTexts["map-home-title"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.maps.firstMatch.waitForExistence(timeout: 10))
        keepScreenshot(named: "Legacy Fusion 02 Map Real Restaurant Images", of: app)

        let wantToGo = app.buttons["map-scope-wantToGo"]
        XCTAssertTrue(wantToGo.waitForExistence(timeout: 5))
        wantToGo.tap()
        XCTAssertTrue(wantToGo.isSelected)
        keepScreenshot(named: "Legacy Fusion 02 Map Honest Fallback", of: app)

        let visited = app.buttons["map-scope-visited"]
        visited.tap()
        XCTAssertTrue(visited.isSelected)
        app.buttons["map-header-view-list"].tap()
        XCTAssertTrue(app.staticTexts["map-home-title"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["map-home-title"].label, "我的列表")
        XCTAssertTrue(app.textFields["restaurant-list-search-field"].waitForExistence(timeout: 5))
        let realImages = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH 'restaurant-image-user-'")
        )
        XCTAssertGreaterThan(realImages.count, 0)
        keepScreenshot(named: "Legacy Fusion 02 My List Images", of: app)

        let firstRow = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH 'restaurant-list-item-'")
        ).firstMatch
        XCTAssertTrue(firstRow.waitForExistence(timeout: 5))
        firstRow.tap()
        XCTAssertTrue(app.navigationBars["餐厅详情"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.descendants(matching: .any)["restaurant-photo-gallery"].waitForExistence(timeout: 8))
        XCTAssertGreaterThan(
            app.descendants(matching: .any).matching(
                NSPredicate(format: "identifier BEGINSWITH 'restaurant-image-user-'")
            ).count,
            0
        )
        keepScreenshot(named: "Legacy Fusion 02 Restaurant Detail Image", of: app)
    }

    @MainActor
    func testLegacyFusion02CanonicalRestaurantImagesAcrossDiscoveryRouletteAndAnalytics() throws {
        let app = XCUIApplication()
        app.launchEnvironment = ["TASTEMAP_VISUAL_QA_MODE": "rich"]
        app.launchArguments = ["-AppleInterfaceStyle", "Light"]
        app.launch()

        app.buttons["app-tab-discover"].tap()
        XCTAssertTrue(app.staticTexts["discovery-header"].waitForExistence(timeout: 10))
        XCTAssertGreaterThan(
            app.descendants(matching: .any).matching(
                NSPredicate(format: "identifier BEGINSWITH 'restaurant-image-'")
            ).count,
            0
        )
        keepScreenshot(named: "Legacy Fusion 02 Discovery Images", of: app)

        app.buttons["app-tab-profile"].tap()
        let roulette = app.buttons["profile-restaurant-roulette-entry"]
        scrollUntilVisible(roulette, in: app)
        XCTAssertTrue(roulette.waitForExistence(timeout: 8))
        roulette.tap()
        XCTAssertTrue(app.descendants(matching: .any)["restaurant-roulette-screen"].waitForExistence(timeout: 10))
        XCTAssertGreaterThan(
            app.descendants(matching: .any).matching(
                NSPredicate(format: "identifier BEGINSWITH 'restaurant-image-'")
            ).count,
            0
        )
        keepScreenshot(named: "Legacy Fusion 02 Roulette Images", of: app)

        XCTAssertTrue(app.navigationBars.buttons.firstMatch.waitForExistence(timeout: 5))
        app.navigationBars.buttons.firstMatch.tap()
        let tasteProfile = app.buttons["profile-taste-analysis-entry"]
        scrollUntilVisible(tasteProfile, in: app)
        XCTAssertTrue(tasteProfile.waitForExistence(timeout: 8))
        tasteProfile.tap()
        XCTAssertTrue(app.descendants(matching: .any)["taste-profile-analysis-page"].waitForExistence(timeout: 10))
        XCTAssertGreaterThan(
            app.descendants(matching: .any).matching(
                NSPredicate(format: "identifier BEGINSWITH 'restaurant-image-'")
            ).count,
            0
        )
        keepScreenshot(named: "Legacy Fusion 02 Analytics Restaurant Images", of: app)
    }

    @MainActor
    func testHybridPhotoDeleteControlMapListMap() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--tastemap-hybrid-development", "-AppleInterfaceStyle", "Light"]
        app.launchEnvironment = ["TASTEMAP_VISUAL_QA_MODE": "rich", "TASTEMAP_PHOTO_DELETE_QA_SESSION": "1",
            "TASTEMAP_PHOTO_DELETE_QA_RUN": UUID().uuidString]
        app.launch()
        let web = app.webViews.firstMatch
        XCTAssertTrue(web.buttons["地图"].waitForExistence(timeout: 20))
        web.buttons["地图"].tap()
        let toList = web.buttons["切换到我的列表"]
        XCTAssertTrue(toList.waitForExistence(timeout: 15))
        XCTAssertTrue(toList.isHittable)
        XCTAssertFalse(web.staticTexts["发现与食单暂未更新，请重试。"].exists)
        keepScreenshot(named: "Photo QA Control Map", of: app)
        toList.tap()
        let toMap = web.buttons["切换到我的地图"]
        XCTAssertTrue(toMap.waitForExistence(timeout: 10))
        XCTAssertTrue(toMap.isHittable)
        keepScreenshot(named: "Photo QA Control List", of: app)
        toMap.tap()
        XCTAssertTrue(toList.waitForExistence(timeout: 10))
        XCTAssertTrue(toList.isHittable)
        XCTAssertTrue(app.descendants(matching: .any)["hybrid-mapkit-restaurant-map"].waitForExistence(timeout: 10))
        keepScreenshot(named: "Photo QA Control Map Return", of: app)
    }

    @MainActor
    func testHybridPhotoDeleteOwnerLocalFirstRuntime() throws {
        let app = XCUIApplication()
        func reveal(_ element: XCUIElement) {
            for _ in 0..<12 {
                if element.exists && element.isHittable && element.frame.maxY < app.frame.maxY - 92 { return }
                app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.56))
                    .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.22)))
            }
            XCTAssertTrue(element.isHittable)
        }
        // Isolated per-run disk fixture permits a genuine process-restart check.
        app.launchArguments = ["--tastemap-hybrid-development", "-AppleInterfaceStyle", "Light"]
        app.launchEnvironment = ["TASTEMAP_VISUAL_QA_MODE": "rich", "TASTEMAP_PHOTO_DELETE_QA_SESSION": "1",
            "TASTEMAP_PHOTO_DELETE_QA_RUN": UUID().uuidString]
        app.launch()
        let web = app.webViews.firstMatch
        XCTAssertTrue(web.waitForExistence(timeout: 20))
        XCTAssertTrue(web.buttons["我的"].waitForExistence(timeout: 15))
        let profileReady = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: web.buttons["我的"])
        XCTAssertEqual(XCTWaiter.wait(for: [profileReady], timeout: 15), .completed)
        web.buttons["我的"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let visited = web.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "去过")).firstMatch
        XCTAssertTrue(visited.waitForExistence(timeout: 15))
        visited.tap()
        let restaurant = web.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "野火烧鸟 5")).firstMatch
        reveal(restaurant)
        XCTAssertTrue(restaurant.waitForExistence(timeout: 10))
        restaurant.tap()
        let photo = web.buttons["查看野火烧鸟 5用户实拍 1"]
        reveal(photo)
        XCTAssertTrue(photo.waitForExistence(timeout: 10))
        keepScreenshot(named: "Photo Delete Capacitor Detail Before", of: app)
        // WKWebView exposes nested AX WebViews on iOS 26.5. Verify deletion
        // does not add a surface relative to this settled detail hierarchy.
        let detailWebViewCount = app.webViews.count
        photo.tap()
        let more = web.buttons["照片更多操作"]
        XCTAssertTrue(more.waitForExistence(timeout: 10))
        more.tap()
        web.buttons["删除照片"].tap()
        XCTAssertTrue(web.staticTexts["删除这张照片？"].waitForExistence(timeout: 5))
        XCTAssertTrue(web.staticTexts["将从 Taste Map 中删除，不会删除系统相册中的原照片。"].exists)
        keepScreenshot(named: "Photo Delete Capacitor Owner Confirmation", of: app)
        web.buttons["确认删除"].tap()
        let hidden = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: photo)
        XCTAssertEqual(XCTWaiter.wait(for: [hidden], timeout: 10), .completed)
        XCTAssertFalse(web.buttons["照片更多操作"].exists)
        XCTAssertTrue(web.buttons["返回上一页"].exists)
        XCTAssertEqual(app.webViews.count, detailWebViewCount)
        keepScreenshot(named: "Photo Delete Capacitor Immediately Hidden", of: app)
        web.buttons["返回上一页"].tap()
        XCTAssertTrue(visited.waitForExistence(timeout: 10))
        visited.tap()
        reveal(restaurant)
        XCTAssertTrue(restaurant.waitForExistence(timeout: 10))
        restaurant.tap()
        let empty = web.staticTexts["暂时还没有用户分享的照片。"]
        reveal(empty)
        XCTAssertTrue(empty.waitForExistence(timeout: 10))
        XCTAssertFalse(photo.exists)
        XCTAssertEqual(app.webViews.count, detailWebViewCount)
        keepScreenshot(named: "Photo Delete Capacitor Detail Reopened", of: app)
        // A fresh process/WebView must read the disk tombstone, not the JS Set.
        app.terminate()
        app.launch()
        XCTAssertTrue(web.buttons["我的"].waitForExistence(timeout: 20))
        web.buttons["我的"].tap()
        XCTAssertTrue(visited.waitForExistence(timeout: 10))
        visited.tap()
        reveal(restaurant)
        restaurant.tap()
        reveal(empty)
        XCTAssertTrue(empty.waitForExistence(timeout: 10))
        XCTAssertFalse(photo.exists)
        keepScreenshot(named: "Photo Delete Capacitor Process Restart Tombstone", of: app)
        web.buttons["返回上一页"].tap()
        web.buttons["地图"].tap()
        let toList = web.buttons["切换到我的列表"]
        XCTAssertTrue(toList.waitForExistence(timeout: 10))
        keepScreenshot(named: "Photo Delete Personal Map After Restart", of: app)
        XCTAssertFalse(web.staticTexts["发现与食单暂未更新，请重试。"].exists)
        XCTAssertTrue(toList.isHittable)
        toList.tap()
        let toMap = web.buttons["切换到我的地图"]
        XCTAssertTrue(toMap.waitForExistence(timeout: 10))
        XCTAssertTrue(toMap.isHittable)
        keepScreenshot(named: "Photo Delete Personal List After Restart", of: app)
        toMap.tap()
        XCTAssertTrue(toList.waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any)["hybrid-mapkit-restaurant-map"].waitForExistence(timeout: 10))
        keepScreenshot(named: "Photo Delete Personal Map List Map Return", of: app)
    }

    @MainActor
    func testHybridProfileUsesFansTerminology() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--tastemap-hybrid-development", "-AppleInterfaceStyle", "Light"]
        app.launchEnvironment = ["TASTEMAP_VISUAL_QA_MODE": "rich"]
        app.launch()

        let webView = app.webViews.firstMatch
        XCTAssertTrue(webView.waitForExistence(timeout: 20))
        XCTAssertTrue(webView.buttons["我的"].waitForExistence(timeout: 8))
        webView.buttons["我的"].tap()
        XCTAssertTrue(webView.staticTexts["Lafayette · 丰富美食档案"].waitForExistence(timeout: 15))
        XCTAssertTrue(webView.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "粉丝 ")
        ).firstMatch.waitForExistence(timeout: 8))
        XCTAssertFalse(webView.staticTexts["被关注"].exists)
        XCTAssertFalse(webView.staticTexts["关注我的"].exists)
    }

    @MainActor
    func testHybridProfileRestaurantAndSharedRoulettePaths() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--tastemap-hybrid-development", "-AppleInterfaceStyle", "Light"]
        app.launchEnvironment = ["TASTEMAP_VISUAL_QA_MODE": "rich"]
        app.launch()

        let webView = app.webViews.firstMatch
        XCTAssertTrue(webView.waitForExistence(timeout: 20))
        let profileTab = webView.buttons["我的"]
        XCTAssertTrue(profileTab.waitForExistence(timeout: 8))
        profileTab.tap()
        XCTAssertTrue(webView.staticTexts["Lafayette · 丰富美食档案"].waitForExistence(timeout: 15))
        XCTAssertTrue(webView.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "ID ")
        ).firstMatch.waitForExistence(timeout: 8))
        XCTAssertTrue(webView.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "粉丝 ")
        ).firstMatch.waitForExistence(timeout: 8))
        XCTAssertFalse(webView.staticTexts["被关注"].exists)
        XCTAssertFalse(webView.staticTexts["关注我的"].exists)
        XCTAssertFalse(webView.staticTexts["认真记录每一次值得记住的饭。"].exists)

        let visited = webView.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "去过")
        ).firstMatch
        XCTAssertTrue(visited.waitForExistence(timeout: 8))
        visited.tap()

        let restaurant = webView.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "青岚寿司 1")
        ).firstMatch
        XCTAssertTrue(restaurant.waitForExistence(timeout: 8))
        restaurant.tap()

        let hybridBack = webView.buttons["返回上一页"]
        XCTAssertTrue(hybridBack.waitForExistence(timeout: 12))
        hybridBack.tap()
        XCTAssertTrue(webView.staticTexts["Lafayette · 丰富美食档案"].waitForExistence(timeout: 10))

        let roulette = webView.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "今天吃什么")
        ).firstMatch
        XCTAssertTrue(roulette.waitForExistence(timeout: 8))
        roulette.tap()

        XCTAssertTrue(webView.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "今天吃什么")
        ).firstMatch.waitForExistence(timeout: 12))
        XCTAssertTrue(webView.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "最多选择 10 家")
        ).firstMatch.waitForExistence(timeout: 8))
        webView.buttons["关闭"].firstMatch.tap()
        XCTAssertTrue(webView.staticTexts["Lafayette · 丰富美食档案"].waitForExistence(timeout: 10))
    }

    @MainActor
    func testHybridPhase2BMapListScopeAndDetailState() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--tastemap-hybrid-development", "-AppleInterfaceStyle", "Light"]
        app.launchEnvironment = [
            "TASTEMAP_VISUAL_QA_MODE": "rich",
            "TASTEMAP_CORE_PARITY_INITIAL_TAB": "map",
        ]
        app.launch()

        let webView = app.webViews.firstMatch
        XCTAssertTrue(webView.waitForExistence(timeout: 20))
        let listSwitch = webView.buttons["切换到我的列表"]
        if !listSwitch.waitForExistence(timeout: 2) {
            let mapTab = webView.buttons["地图"]
            XCTAssertTrue(mapTab.waitForExistence(timeout: 5))
            mapTab.tap()
        }
        XCTAssertTrue(listSwitch.waitForExistence(timeout: 15))
        XCTAssertTrue(webView.buttons["去过，90 家餐厅"].waitForExistence(timeout: 12))
        XCTAssertTrue(webView.buttons["想吃，25 家餐厅"].waitForExistence(timeout: 12))
        XCTAssertTrue(webView.buttons["推荐，12 家餐厅"].waitForExistence(timeout: 12))

        let wantedScope = webView.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "想吃")
        ).firstMatch
        XCTAssertTrue(wantedScope.waitForExistence(timeout: 8))
        wantedScope.tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@", "青岚寿司 6", "想吃")
        ).firstMatch.waitForExistence(timeout: 8))
        keepScreenshot(named: "Hybrid Wanted Restaurants Dashed Markers", of: app)

        listSwitch.tap()
        let mapSwitch = webView.buttons["切换到我的地图"]
        XCTAssertTrue(mapSwitch.waitForExistence(timeout: 8))
        XCTAssertTrue(webView.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "青岚寿司 6")
        ).firstMatch.waitForExistence(timeout: 8))

        mapSwitch.tap()
        XCTAssertTrue(webView.buttons["切换到我的列表"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS %@", "青岚寿司 6")
        ).firstMatch.waitForExistence(timeout: 8))

        let visitedScope = webView.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "去过")
        ).firstMatch
        visitedScope.tap()
        let marker = app.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS %@", "青岚寿司 1")
        ).firstMatch
        XCTAssertTrue(marker.waitForExistence(timeout: 10))
        marker.tap()

        let hybridBack = webView.buttons["返回上一页"]
        XCTAssertTrue(hybridBack.waitForExistence(timeout: 12))
        let addToRoulette = webView.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "加入转盘 青岚寿司 1")
        ).firstMatch
        XCTAssertTrue(addToRoulette.waitForExistence(timeout: 8))
        addToRoulette.tap()
        hybridBack.tap()
        XCTAssertTrue(webView.buttons["切换到我的列表"].waitForExistence(timeout: 8))
        XCTAssertTrue(visitedScope.exists)
        XCTAssertTrue(webView.staticTexts["已选 1/10"].waitForExistence(timeout: 5))
        XCTAssertTrue(webView.buttons["查看"].exists)
        XCTAssertFalse(webView.buttons["开始抽"].isEnabled)
    }

    @MainActor
    func testHybridVisitedListShowsRichRestaurantInformation() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--tastemap-hybrid-development", "-AppleInterfaceStyle", "Light"]
        app.launchEnvironment = [
            "TASTEMAP_VISUAL_QA_MODE": "rich",
            "TASTEMAP_CORE_PARITY_INITIAL_TAB": "map",
        ]
        app.launch()

        let webView = app.webViews.firstMatch
        XCTAssertTrue(webView.waitForExistence(timeout: 20))

        let listSwitch = webView.buttons["切换到我的列表"]
        if !listSwitch.waitForExistence(timeout: 2) {
            let mapTab = webView.buttons["地图"]
            XCTAssertTrue(mapTab.waitForExistence(timeout: 5))
            mapTab.tap()
        }

        XCTAssertTrue(listSwitch.waitForExistence(timeout: 15))
        listSwitch.tap()
        XCTAssertTrue(webView.staticTexts["去过的餐厅"].waitForExistence(timeout: 8))

        let richRestaurant = webView.buttons.matching(
            NSPredicate(
                format: "label BEGINSWITH %@ AND label CONTAINS %@ AND label CONTAINS %@ AND label CONTAINS %@",
                "查看餐厅 ",
                "分",
                "次到访",
                "最近到访"
            )
        ).firstMatch
        XCTAssertTrue(
            richRestaurant.waitForExistence(timeout: 8),
            "Visited Restaurant rows should expose score, visit count, and latest visit."
        )
        XCTAssertTrue(
            richRestaurant.label.contains("人均"),
            "Rich Demo's visited Restaurant row should expose its real per-person spend."
        )
        keepScreenshot(named: "Hybrid My Visited List Rich Restaurant Information", of: app)
    }

    @MainActor
    func testHybridRecommendedMarkersUseHistoricalUnvisitedShell() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--tastemap-hybrid-development", "-AppleInterfaceStyle", "Light"]
        app.launchEnvironment = [
            "TASTEMAP_VISUAL_QA_MODE": "rich",
            "TASTEMAP_CORE_PARITY_INITIAL_TAB": "map",
        ]
        app.launch()

        let webView = app.webViews.firstMatch
        XCTAssertTrue(webView.waitForExistence(timeout: 20))
        let mapSwitch = webView.buttons["切换到我的列表"]
        if !mapSwitch.waitForExistence(timeout: 2) {
            let mapTab = webView.buttons["地图"]
            XCTAssertTrue(mapTab.waitForExistence(timeout: 5))
            mapTab.tap()
        }
        XCTAssertTrue(mapSwitch.waitForExistence(timeout: 15))

        let recommendedScope = webView.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "推荐")
        ).firstMatch
        XCTAssertTrue(recommendedScope.waitForExistence(timeout: 8))
        XCTAssertEqual(recommendedScope.label, "推荐，12 家餐厅")
        recommendedScope.tap()
        XCTAssertTrue(recommendedScope.isSelected)

        let recommendedMarker = app.descendants(matching: .any).matching(
            NSPredicate(
                format: "identifier BEGINSWITH %@ AND label CONTAINS %@",
                "restaurant-map-marker-",
                "推荐"
            )
        ).firstMatch
        XCTAssertTrue(recommendedMarker.waitForExistence(timeout: 10))
        let firstForYouRestaurantMarker = app.descendants(matching: .any).matching(
            NSPredicate(
                format: "identifier BEGINSWITH %@ AND label CONTAINS %@ AND label CONTAINS %@",
                "restaurant-map-marker-",
                "春日泰味 7",
                "推荐"
            )
        ).firstMatch
        XCTAssertTrue(
            firstForYouRestaurantMarker.waitForExistence(timeout: 10),
            "Map recommendation must include the same first Restaurant as Discovery For You"
        )
        keepScreenshot(named: "Hybrid Recommended Restaurants Historical Unvisited Markers", of: app)
    }

    @MainActor
    func testHybridMapSuppressesBrowserStyleLongPressSelectionMenu() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--tastemap-hybrid-development", "-AppleInterfaceStyle", "Light"]
        app.launchEnvironment = [
            "TASTEMAP_VISUAL_QA_MODE": "rich",
            "TASTEMAP_CORE_PARITY_INITIAL_TAB": "map",
        ]
        app.launch()

        let webView = app.webViews.firstMatch
        XCTAssertTrue(webView.waitForExistence(timeout: 20))
        let filter = webView.buttons["筛选"]
        if !filter.waitForExistence(timeout: 2) {
            let mapTab = webView.buttons["地图"]
            XCTAssertTrue(mapTab.waitForExistence(timeout: 5))
            mapTab.tap()
        }
        XCTAssertTrue(filter.waitForExistence(timeout: 15))
        filter.press(forDuration: 1.2)

        for browserMenuLabel in ["Copy", "Look Up", "Translate", "复制", "查询", "翻译"] {
            XCTAssertFalse(
                app.descendants(matching: .any)[browserMenuLabel].waitForExistence(timeout: 0.5),
                "Hybrid product chrome must not expose the browser \(browserMenuLabel) menu"
            )
        }
        keepScreenshot(named: "Hybrid Map Without Browser Long Press Menu", of: app)
    }

    @MainActor
    func testHybridNativeMapFillsBehindSharedBottomNavigation() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--tastemap-hybrid-development", "-AppleInterfaceStyle", "Light"]
        app.launchEnvironment = [
            "TASTEMAP_VISUAL_QA_MODE": "rich",
            "TASTEMAP_CORE_PARITY_INITIAL_TAB": "map",
        ]
        app.launch()

        let webView = app.webViews.firstMatch
        XCTAssertTrue(webView.waitForExistence(timeout: 20))
        let listSwitch = webView.buttons["切换到我的列表"]
        if !listSwitch.waitForExistence(timeout: 2) {
            let mapTab = webView.buttons["地图"]
            XCTAssertTrue(mapTab.waitForExistence(timeout: 5))
            mapTab.tap()
        }
        XCTAssertTrue(listSwitch.waitForExistence(timeout: 15))
        let map = app.descendants(matching: .any)["restaurant-map"]
        XCTAssertTrue(map.waitForExistence(timeout: 15))
        XCTAssertGreaterThanOrEqual(
            map.frame.maxY,
            app.frame.maxY - 1,
            "The Native Map canvas must fill behind the shared bottom navigation without a reserved seam"
        )
        XCTAssertTrue(webView.buttons["地图"].isHittable, "The full-width navigation cutout must remain tappable above MapKit")
        keepScreenshot(named: "Hybrid Native Map Flush Bottom Navigation", of: app)
    }

    @MainActor
    func testHybridMapGeometrySurvivesAcquisitionKeyboardAndRouteReturn() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--tastemap-hybrid-development", "-AppleInterfaceStyle", "Light"]
        app.launchEnvironment = [
            "TASTEMAP_VISUAL_QA_MODE": "rich",
            "TASTEMAP_RESTAURANT_ACQUISITION_UI_TEST": "1",
            "TASTEMAP_CORE_PARITY_INITIAL_TAB": "map",
        ]
        app.launch()
        let web = app.webViews.firstMatch
        XCTAssertTrue(web.waitForExistence(timeout: 20), "The intended renderer is React Hybrid")
        let title = web.buttons["切换到我的列表"]
        let filter = web.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "筛选")).firstMatch
        let map = app.descendants(matching: .any)["restaurant-map"]
        let add = web.buttons["添加餐厅"]
        let mapTab = web.buttons["地图"]
        if !title.waitForExistence(timeout: 2) { mapTab.tap() }

        @MainActor
        func verifyLayout(_ phase: String, expected: CGRect? = nil) throws -> CGRect {
            XCTAssertTrue(title.waitForExistence(timeout: 12))
            XCTAssertTrue(filter.waitForExistence(timeout: 8))
            XCTAssertTrue(map.waitForExistence(timeout: 12), "The renderer must also expose its Native MapKit surface")
            XCTAssertTrue(add.waitForExistence(timeout: 8))
            XCTAssertTrue(title.isHittable, "Native geometry must not cover the React title: \(phase)")
            XCTAssertTrue(filter.isHittable, "Native geometry must not cover the React filters: \(phase)")
            XCTAssertTrue(add.isHittable, "The Native exclusion must match the real Add CTA: \(phase)")
            XCTAssertTrue(mapTab.isHittable, "The Native bottom exclusion must preserve shared navigation")
            let nativeFrame = map.frame
            print("MAP_SURFACE_GEOMETRY \(phase); app \(app.frame); web \(web.frame); title \(title.frame); filter \(filter.frame); native \(nativeFrame); add \(add.frame); mapTab \(mapTab.frame)")
            // restaurant-map is the host's non-rendering geometry probe, pinned
            // to the Native rectangle. Its bottom deliberately includes the
            // navigation cutout, so do not mistake that overlap for a defect.
            XCTAssertGreaterThanOrEqual(nativeFrame.minY, filter.frame.maxY - 2)
            XCTAssertGreaterThanOrEqual(nativeFrame.maxY, app.frame.maxY - 1)
            XCTAssertGreaterThan(nativeFrame.height, app.frame.height * 0.6, "Map must never become a half-height canvas")
            XCTAssertTrue(nativeFrame.contains(add.frame), "Map must extend behind the real Add control")
            XCTAssertLessThan(add.frame.maxY, mapTab.frame.minY, "Add remains above the bottom navigation")
            if let expected {
                XCTAssertEqual(nativeFrame.minY, expected.minY, accuracy: 1)
                XCTAssertEqual(nativeFrame.height, expected.height, accuracy: 1)
                XCTAssertEqual(nativeFrame.width, expected.width, accuracy: 1)
            }
            keepScreenshot(named: "Hybrid Map Viewport Geometry — \(phase)", of: app)
            return nativeFrame
        }

        let original = try verifyLayout("initial")
        for cycle in 0..<2 {
            add.tap()
            let query = web.textFields["餐厅名称或地址"]
            let city = web.textFields["城市"]
            XCTAssertTrue(query.waitForExistence(timeout: 10))
            XCTAssertTrue(city.waitForExistence(timeout: 10))
            XCTAssertTrue(map.waitForNonExistence(timeout: 5), "Hidden Map geometry must not survive into acquisition")
            query.tap()
            query.typeText("牛new")
            XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
            city.tap()
            XCTAssertTrue(app.keyboards.firstMatch.exists)
            print("MAP_KEYBOARD_GEOMETRY cycle \(cycle); web \(web.frame); query \(query.frame); city \(city.frame); keyboard \(app.keyboards.firstMatch.frame)")
            keepScreenshot(named: "Hybrid Map Return — Focused Acquisition \(cycle)", of: app)
            if cycle == 0 {
                web.buttons["搜索餐厅"].tap()
                XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 8))
            }
            let back = web.buttons["返回上一页"]
            XCTAssertTrue(back.waitForExistence(timeout: 8))
            XCTAssertTrue(back.isHittable)
            back.tap()
            XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 8))
            _ = try verifyLayout("after-acquisition-\(cycle)", expected: original)
            web.buttons["发现"].tap()
            XCTAssertTrue(web.buttons["为你推荐"].waitForExistence(timeout: 8))
            XCTAssertTrue(map.waitForNonExistence(timeout: 5), "A late layout callback must never reveal MapKit over Discovery")
            mapTab.tap()
            _ = try verifyLayout("after-discovery-\(cycle)", expected: original)
        }
    }

    @MainActor
    func testHybridNativeMapKitPanZoomSelectionAndViewportRestoration() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--tastemap-hybrid-development", "-AppleInterfaceStyle", "Light"]
        app.launchEnvironment = [
            "TASTEMAP_VISUAL_QA_MODE": "rich",
            "TASTEMAP_CORE_PARITY_INITIAL_TAB": "map",
        ]
        app.launch()

        let webView = app.webViews.firstMatch
        XCTAssertTrue(webView.waitForExistence(timeout: 20))
        let listSwitch = webView.buttons["切换到我的列表"]
        if !listSwitch.waitForExistence(timeout: 2) {
            let mapTab = webView.buttons["地图"]
            XCTAssertTrue(mapTab.waitForExistence(timeout: 5))
            mapTab.tap()
        }
        XCTAssertTrue(listSwitch.waitForExistence(timeout: 15))
        let filterBar = webView.descendants(matching: .any)["地图筛选"]
        XCTAssertTrue(filterBar.waitForExistence(timeout: 8), "React FilterBar must remain visible above the Native MapKit surface")
        XCTAssertTrue(filterBar.isHittable, "Native MapKit must not cover the React FilterBar hit area")

        // A reused MKMapView embedded through UIHostingController can be exposed
        // by XCTest as either Map or Other depending on the current iOS runtime.
        // Querying the identifier across all element types keeps the assertion
        // about the real native view, not about XCTest's presentation category.
        let map = app.descendants(matching: .any)["restaurant-map"]
        XCTAssertTrue(map.waitForExistence(timeout: 15), "Hybrid iOS must expose the reused Native MKMapView")
        XCTAssertTrue(map.isHittable)
        XCTAssertTrue(app.descendants(matching: .any)["restaurant-map-user-avatar-marker"].waitForExistence(timeout: 15))

        let marker = app.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS %@", "青岚寿司 1")
        ).firstMatch
        XCTAssertTrue(marker.waitForExistence(timeout: 12))

        let viewportReady = expectation(
            for: NSPredicate(format: "value CONTAINS %@", "center"),
            evaluatedWith: map
        )
        wait(for: [viewportReady], timeout: 8)
        let initialViewport = map.value as? String ?? ""
        print("TASTEMAP_MAPKIT_VIEWPORT_INITIAL=\(initialViewport)")
        XCTAssertTrue(initialViewport.contains("center"), "MapKit must publish its real center/span")

        let tapStartedAt = Date()
        marker.tap()
        let back = webView.buttons["返回上一页"]
        XCTAssertTrue(back.waitForExistence(timeout: 12))
        let tapToDetailSeconds = Date().timeIntervalSince(tapStartedAt)
        print("TASTEMAP_MAP_TAP_TO_DETAIL_SECONDS=\(tapToDetailSeconds)")
        XCTAssertLessThan(tapToDetailSeconds, 2.0, "Marker tap should present full Restaurant Detail without visible lag")
        back.tap()
        XCTAssertTrue(map.waitForExistence(timeout: 10))
        XCTAssertEqual(map.value as? String, initialViewport, "Restaurant Detail return must preserve the Native viewport")

        // Move enough to prove the center changes; marker selection and the
        // Restaurant Detail return path were already verified above.
        let panStart = map.coordinate(withNormalizedOffset: CGVector(dx: 0.68, dy: 0.56))
        let panEnd = map.coordinate(withNormalizedOffset: CGVector(dx: 0.32, dy: 0.56))
        panStart.press(forDuration: 0.12, thenDragTo: panEnd)
        let changedAfterPan = expectation(
            for: NSPredicate(format: "value != %@", initialViewport),
            evaluatedWith: map
        )
        wait(for: [changedAfterPan], timeout: 8)
        let pannedViewport = map.value as? String ?? ""
        print("TASTEMAP_MAPKIT_VIEWPORT_AFTER_PAN=\(pannedViewport)")
        XCTAssertNotEqual(pannedViewport, initialViewport)

        map.pinch(withScale: 1.7, velocity: 1.0)
        let changedAfterZoom = expectation(
            for: NSPredicate(format: "value != %@", pannedViewport),
            evaluatedWith: map
        )
        wait(for: [changedAfterZoom], timeout: 8)
        let zoomedViewport = map.value as? String ?? ""
        print("TASTEMAP_MAPKIT_VIEWPORT_AFTER_ZOOM=\(zoomedViewport)")
        XCTAssertNotEqual(zoomedViewport, pannedViewport)

        webView.buttons["切换到我的列表"].tap()
        XCTAssertTrue(webView.buttons["切换到我的地图"].waitForExistence(timeout: 8))
        webView.buttons["切换到我的地图"].tap()
        XCTAssertTrue(map.waitForExistence(timeout: 8))
        XCTAssertEqual(map.value as? String, zoomedViewport, "Map/List must reuse the same persistent MapKit viewport")
        keepScreenshot(named: "Hybrid Native MapKit Interaction", of: app)
    }

    @MainActor
    func testHybridNativeMapRestaurantImagesStayAnchoredAcrossZoomAndPan() throws {
        try verifyHybridNativeMapRestaurantImageAnchors(regionOnly: false)
    }

    @MainActor
    func testHybridPendingMapMarkersAreLargerAndStayCentered() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--tastemap-hybrid-development", "-AppleInterfaceStyle", "Light"]
        app.launchEnvironment = [
            "TASTEMAP_VISUAL_QA_MODE": "rich",
            "TASTEMAP_MAP_GEOMETRY_QA": "1",
            "TASTEMAP_CORE_PARITY_INITIAL_TAB": "map",
        ]
        app.launch()
        let web = app.webViews.firstMatch
        XCTAssertTrue(web.waitForExistence(timeout: 20))
        let map = app.descendants(matching: .any)["restaurant-map"]
        if !map.waitForExistence(timeout: 2) { web.buttons["地图"].tap() }
        XCTAssertTrue(map.waitForExistence(timeout: 15))
        let gestureArea = app.otherElements["restaurant-map-gesture-area"]
        XCTAssertTrue(gestureArea.waitForExistence(timeout: 8))
        let pattern = try NSRegularExpression(pattern: #"^anchorError ([-+0-9.]+),([-+0-9.]+); diameter ([-+0-9.]+);"#)

        @MainActor
        func verify(_ scope: String, emphasis: Double, phase: String) throws {
            let markers = app.otherElements.matching(NSPredicate(
                format: "identifier BEGINSWITH %@ AND label CONTAINS %@",
                "restaurant-map-marker-", "，\(scope)，"
            ))
            XCTAssertTrue(markers.firstMatch.waitForExistence(timeout: 12))
            let viewport = map.value as? String ?? ""
            let spanText = try XCTUnwrap(viewport.components(separatedBy: "; span ").last?.split(separator: ",").first)
            let span = try XCTUnwrap(Double(spanText))
            let progress = log(min(1.5, max(0.008, span)) / 0.008) / log(1.5 / 0.008)
            let expectedOuter = 32 - 4 * progress + emphasis
            var checked = 0
            for marker in markers.allElementsBoundByIndex {
                guard marker.frame.intersects(gestureArea.frame), !marker.frame.isEmpty else { continue }
                let value = try XCTUnwrap(marker.value as? String)
                let match = try XCTUnwrap(pattern.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)))
                let values = try (1...3).map { index in
                    let range = try XCTUnwrap(Range(match.range(at: index), in: value))
                    return try XCTUnwrap(Double(value[range]))
                }
                XCTAssertEqual(marker.frame.width, 44, accuracy: 1)
                XCTAssertEqual(marker.frame.height, 44, accuracy: 1)
                XCTAssertLessThanOrEqual(hypot(values[0], values[1]), 1, value)
                // The AX viewport and inner layer are read on separate frames
                // during a real pinch; allow quarter-point display rounding.
                XCTAssertEqual(values[2], expectedOuter, accuracy: 0.25, value)
                print("PENDING_MARKER \(phase) \(marker.identifier) \(value)")
                checked += 1
            }
            XCTAssertGreaterThan(checked, 0, "Must measure actual visible \(scope) circles")
            keepScreenshot(named: "Pending Map Markers — \(phase)", of: app)
        }

        try verify("去过", emphasis: 0, phase: "visited-unchanged")
        for scope in ["想吃", "推荐"] {
            let viewportBeforeScope = map.value as? String
            let button = web.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "\(scope)，")).firstMatch
            XCTAssertTrue(button.waitForExistence(timeout: 8))
            button.tap()
            try verify(scope, emphasis: 4, phase: "\(scope)-larger")
            XCTAssertEqual(map.value as? String, viewportBeforeScope, "Sizing/scope must not fit the camera")
            for scale: CGFloat in [1.5, 0.67] {
                let previous = map.value as? String ?? ""
                gestureArea.pinch(withScale: scale, velocity: scale > 1 ? 1 : -1)
                let changed = expectation(for: NSPredicate(format: "value != %@", previous), evaluatedWith: map)
                wait(for: [changed], timeout: 8)
                try verify(scope, emphasis: 4, phase: "\(scope)-zoom-\(scale)")
            }
            let start = gestureArea.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            let end = gestureArea.coordinate(withNormalizedOffset: CGVector(dx: 0.65, dy: 0.62))
            start.press(forDuration: 0.1, thenDragTo: end)
            try verify(scope, emphasis: 4, phase: "\(scope)-pan")
        }
        web.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "去过，")).firstMatch.tap()
        try verify("去过", emphasis: 0, phase: "visited-restored")
    }

    @MainActor
    func testHybridNativeMapRegionalRestaurantImagesStayAnchoredAcrossPinch() throws {
        try verifyHybridNativeMapRestaurantImageAnchors(regionOnly: true)
    }

    @MainActor
    func testHybridNativeMapOverlapOrderSurvivesPurePans() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--tastemap-hybrid-development", "-AppleInterfaceStyle", "Light"]
        app.launchEnvironment = [
            "TASTEMAP_VISUAL_QA_MODE": "dense-mall",
            "TASTEMAP_MAP_GEOMETRY_QA": "1",
            "TASTEMAP_MAP_FRAME_DIAGNOSTICS": "1",
            "TASTEMAP_CORE_PARITY_INITIAL_TAB": "map",
        ]
        app.launch()
        let web = app.webViews.firstMatch
        XCTAssertTrue(web.waitForExistence(timeout: 20))
        let map = app.descendants(matching: .any)["restaurant-map"]
        if !map.waitForExistence(timeout: 2) { web.buttons["地图"].tap() }
        XCTAssertTrue(map.waitForExistence(timeout: 15))
        let area = app.otherElements["restaurant-map-gesture-area"]
        XCTAssertTrue(area.waitForExistence(timeout: 8))
        let markers = app.otherElements.matching(NSPredicate(format: "identifier BEGINSWITH %@", "restaurant-map-marker-"))
        XCTAssertTrue(markers.firstMatch.waitForExistence(timeout: 12))
        let priorityPattern = try NSRegularExpression(pattern: #"; priority ([0-9.]+); layer ([0-9.]+); members (.+)$"#)
        let geometryPattern = try NSRegularExpression(pattern: #"^anchorError ([-+0-9.]+),([-+0-9.]+); diameter ([-+0-9.]+);"#)
        typealias LayerEvidence = (priority: Double, layer: Double, members: String, frame: CGRect, diameter: Double)

        @MainActor
        func snapshot(_ phase: String) throws -> [String: LayerEvidence] {
            var values: [String: LayerEvidence] = [:]
            for marker in markers.allElementsBoundByIndex {
                guard marker.frame.intersects(map.frame), !marker.frame.isEmpty else { continue }
                let value = try XCTUnwrap(marker.value as? String)
                let match = try XCTUnwrap(priorityPattern.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)))
                let ranges = try (1...3).map { try XCTUnwrap(Range(match.range(at: $0), in: value)) }
                let priority = try XCTUnwrap(Double(value[ranges[0]]))
                let layer = try XCTUnwrap(Double(value[ranges[1]]))
                let geometryMatch = try XCTUnwrap(geometryPattern.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)))
                let geometry = try (1...3).map { index in
                    try XCTUnwrap(Double(value[try XCTUnwrap(Range(geometryMatch.range(at: index), in: value))]))
                }
                // Preserve the measured value before a fail-fast assertion:
                // XCTest's sparse AX attachments may omit live marker values.
                print("PAN_LAYER \(phase) \(marker.identifier) \(value)")
                if hypot(geometry[0], geometry[1]) > 1 {
                    print("PAN_ANCHOR_FAILURE \(phase) viewport=\(map.value as? String ?? "missing") markerFrame=\(marker.frame) mapFrame=\(map.frame)")
                    keepScreenshot(named: "Stable Restaurant Overlap — \(phase) anchor failure", of: app)
                }
                XCTAssertLessThanOrEqual(hypot(geometry[0], geometry[1]), 1, "Actual circle must stay on its projected Restaurant coordinate: \(phase) \(marker.identifier) \(value)")
                XCTAssertEqual(marker.frame.width, 44, accuracy: 1)
                XCTAssertEqual(marker.frame.height, 44, accuracy: 1)
                XCTAssertGreaterThan(priority, 100)
                XCTAssertLessThan(priority, 900)
                values[marker.identifier] = (priority, layer, String(value[ranges[2]]), marker.frame, geometry[2])
            }
            XCTAssertEqual(values.count, 4, "Dense fixture must retain its four actual coordinates")
            XCTAssertEqual(Set(values.values.map(\.priority)).count, values.count,
                           "Equal MapKit defaults allow the system to reorder overlap on pan")
            let ordered = values.values.sorted { $0.priority < $1.priority }
            for index in 1..<ordered.count {
                XCTAssertGreaterThan(ordered[index].layer, ordered[index - 1].layer,
                                     "Actual compositing must match the declared Restaurant priority")
            }
            keepScreenshot(named: "Stable Restaurant Overlap — \(phase)", of: app)
            return values
        }

        let original = try snapshot("before-pan")
        for step in 0..<8 {
            let reverse = step % 2 == 1
            let vertical = step >= 4
            let from: CGFloat = reverse ? 0.60 : 0.40
            let to: CGFloat = reverse ? 0.40 : 0.60
            let start = area.coordinate(withNormalizedOffset: CGVector(dx: vertical ? 0.5 : from, dy: vertical ? from : 0.5))
            let end = area.coordinate(withNormalizedOffset: CGVector(dx: vertical ? 0.5 : to, dy: vertical ? to : 0.5))
            let previous = map.value as? String ?? ""
            start.press(forDuration: 0.1, thenDragTo: end)
            let changed = expectation(for: NSPredicate(format: "value != %@", previous), evaluatedWith: map)
            wait(for: [changed], timeout: 8)
            let current = try snapshot("pan-\(step)")
            XCTAssertEqual(Set(current.keys), Set(original.keys))
            for (id, baseline) in original {
                let actual = try XCTUnwrap(current[id])
                XCTAssertEqual(actual.priority, baseline.priority)
                XCTAssertEqual(actual.members, baseline.members, "Pure pan cannot swap leader or stack image identity")
                XCTAssertEqual(actual.diameter, baseline.diameter, accuracy: 0.15,
                               "A north/south pan may change Mercator latitude span but must not resize the circle")
            }
        }
    }

    @MainActor
    private func verifyHybridNativeMapRestaurantImageAnchors(regionOnly: Bool) throws {
        let app = XCUIApplication()
        app.launchArguments = ["--tastemap-hybrid-development", "-AppleInterfaceStyle", "Light"]
        app.launchEnvironment = [
            "TASTEMAP_VISUAL_QA_MODE": "dense-mall",
            "TASTEMAP_CORE_PARITY_INITIAL_TAB": "map",
        ]
        app.launch()

        let webView = app.webViews.firstMatch
        XCTAssertTrue(webView.waitForExistence(timeout: 20))
        let map = app.descendants(matching: .any)["restaurant-map"]
        if !map.waitForExistence(timeout: 2) {
            let mapTab = webView.buttons["地图"]
            XCTAssertTrue(mapTab.waitForExistence(timeout: 5))
            mapTab.tap()
        }
        XCTAssertTrue(map.waitForExistence(timeout: 15))
        let gestureArea = app.otherElements["restaurant-map-gesture-area"]
        XCTAssertTrue(gestureArea.waitForExistence(timeout: 8))
        XCTAssertGreaterThan(gestureArea.frame.minY, map.frame.minY)
        XCTAssertLessThan(gestureArea.frame.maxY, map.frame.maxY - 100)
        let markers = app.otherElements.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "restaurant-map-marker-")
        )
        XCTAssertTrue(markers.firstMatch.waitForExistence(timeout: 12))
        let geometryReady = expectation(
            for: NSPredicate(format: "value BEGINSWITH %@", "anchorError "),
            evaluatedWith: markers.firstMatch
        )
        wait(for: [geometryReady], timeout: 8)

        typealias MarkerGeometry = (
            anchorError: CGPoint, diameter: Double, latitude: Double,
            longitude: Double, groupSize: Int, kind: String
        )
        let geometryPattern = try NSRegularExpression(
            pattern: #"^anchorError ([-+0-9.]+),([-+0-9.]+); diameter ([-+0-9.]+); coordinate ([-+0-9.]+),([-+0-9.]+); groupSize ([0-9]+); kind (restaurant|representative|stack)$"#
        )

        @MainActor
        func visibleMarkerSnapshot(_ phase: String) throws -> [String: MarkerGeometry] {
            var result: [String: MarkerGeometry] = [:]
            for marker in markers.allElementsBoundByIndex {
                guard marker.exists, !marker.frame.isEmpty,
                      marker.frame.intersects(map.frame) else { continue }
                let value = try XCTUnwrap(marker.value as? String)
                let match = try XCTUnwrap(geometryPattern.firstMatch(
                    in: value, range: NSRange(value.startIndex ..< value.endIndex, in: value)
                ), "Missing actual-circle geometry: \(value)")
                let numbers = try (1 ... 6).map { index -> Double in
                    let range = try XCTUnwrap(Range(match.range(at: index), in: value))
                    let number = try XCTUnwrap(Double(value[range]))
                    XCTAssertTrue(number.isFinite)
                    return number
                }
                let kindRange = try XCTUnwrap(Range(match.range(at: 7), in: value))
                let geometry: MarkerGeometry = (
                    CGPoint(x: numbers[0], y: numbers[1]), numbers[2],
                    numbers[3], numbers[4], Int(numbers[5]), String(value[kindRange])
                )
                // The root hit box is fixed. The probe reports the actual
                // centered circle, never its 44-point annotation frame.
                XCTAssertEqual(marker.frame.width, 44, accuracy: 1)
                XCTAssertEqual(marker.frame.height, 44, accuracy: 1)
                XCTAssertLessThanOrEqual(
                    hypot(geometry.anchorError.x, geometry.anchorError.y), 1,
                    "\(marker.identifier) drifted from its source coordinate"
                )
                XCTAssertGreaterThanOrEqual(geometry.diameter, 28)
                XCTAssertLessThanOrEqual(geometry.diameter, 36)
                XCTAssertGreaterThanOrEqual(geometry.groupSize, 1)
                if geometry.kind == "restaurant" {
                    XCTAssertEqual(geometry.groupSize, 1)
                } else {
                    XCTAssertGreaterThan(geometry.groupSize, 1)
                    XCTAssertFalse(marker.label.contains("\(geometry.groupSize) 家餐厅"))
                    XCTAssertTrue(marker.label.contains(geometry.kind == "stack"
                        ? "此处有重叠餐厅，查看列表" : "区域代表餐厅，放大查看"))
                }
                result[marker.identifier] = geometry
            }
            XCTAssertFalse(result.isEmpty)
            let maximumError = result.values.map { hypot($0.anchorError.x, $0.anchorError.y) }.max() ?? 0
            let header = "MAP_GEOMETRY \(phase); span \(latitudeSpan()); visible \(result.count); members \(result.values.reduce(0) { $0 + $1.groupSize }); maxAnchorError \(maximumError)"
            let rows = result.keys.sorted().compactMap { id -> String? in
                guard let value = result[id] else { return nil }
                return "\(id); kind \(value.kind); members \(value.groupSize); coordinate \(value.latitude),\(value.longitude); error \(value.anchorError.x),\(value.anchorError.y); diameter \(value.diameter)"
            }
            let evidence = XCTAttachment(string: ([header] + rows).joined(separator: "\n"))
            evidence.name = "Restaurant Geometry — \(phase)"
            evidence.lifetime = .keepAlways
            add(evidence)
            print(header)
            // The isolated dense-mall fixture contains 18 distinct Restaurants
            // and 36 Visits. Every zoom must still represent exactly 18.
            XCTAssertEqual(result.values.reduce(0) { $0 + $1.groupSize }, 18)
            return result
        }

        @MainActor
        func latitudeSpan() -> Double {
            let value = map.value as? String ?? ""
            guard let span = value.components(separatedBy: "; span ").last,
                  let latitude = span.split(separator: ",").first else { return 0 }
            return Double(latitude) ?? 0
        }

        @MainActor
        func zoom(_ scale: CGFloat) throws {
            let previousViewport = map.value as? String ?? ""
            let previousSpan = latitudeSpan()
            // This DEBUG-only transparent target cannot handle touches itself;
            // both fingers pass through to the real MapKit gesture recognizers.
            // It keeps XCTest's synthesized pinch away from bottom navigation.
            gestureArea.pinch(withScale: scale, velocity: scale > 1 ? 1 : -1)
            let changed = expectation(
                for: NSPredicate(format: "value != %@", previousViewport), evaluatedWith: map
            )
            wait(for: [changed], timeout: 8)
            XCTAssertEqual(app.state, .runningForeground)
            XCTAssertTrue(map.waitForExistence(timeout: 8), "Map zoom must stay on the Map route")
            XCTAssertTrue(markers.firstMatch.waitForExistence(timeout: 8))
            if scale > 1 {
                XCTAssertLessThan(latitudeSpan(), previousSpan, "A real pinch-open must zoom MapKit in")
            } else {
                XCTAssertGreaterThan(latitudeSpan(), previousSpan, "A real pinch-close must zoom MapKit out")
            }
            _ = try visibleMarkerSnapshot("after-pinch-\(scale)")
        }

        keepScreenshot(named: "Hybrid Native Restaurant Stack Initial Runtime Evidence", of: app)
        let city = try visibleMarkerSnapshot("initial-city")
        XCTAssertLessThanOrEqual(latitudeSpan(), 0.8)
        XCTAssertEqual(city.count, 4, "The fixture has four distinct coordinates; ordinary city overlap must not hide them")
        XCTAssertFalse(city.values.contains { $0.kind == "representative" })
        keepScreenshot(named: "Hybrid Native City Restaurant Images Without Numbers", of: app)

        // First exercise the user's city close/open/pan/list workflow so a
        // separate wider-area gesture failure cannot erase that coverage.
        if !regionOnly {
            try zoom(0.5)
            try zoom(1.8)
            for _ in 0 ..< 4 where latitudeSpan() > 0.012 { try zoom(1.8) }
            XCTAssertLessThanOrEqual(latitudeSpan(), 0.02)
            let street = try visibleMarkerSnapshot("street-restored")
            XCTAssertFalse(street.values.contains { $0.kind == "representative" },
                           "City and street zoom must restore every distinct Restaurant coordinate")
            XCTAssertEqual(Set(street.keys), Set(city.keys))
            XCTAssertTrue(street.values.contains { $0.kind == "stack" },
                          "This fixture must expose its exact-coordinate Restaurants through a stack")
            keepScreenshot(named: "Hybrid Native Street Restaurant Images Without Numbers", of: app)

            let previousViewport = map.value as? String ?? ""
            let start = map.coordinate(withNormalizedOffset: CGVector(dx: 0.54, dy: 0.56))
            let end = map.coordinate(withNormalizedOffset: CGVector(dx: 0.46, dy: 0.56))
            start.press(forDuration: 0.08, thenDragTo: end)
            let panned = expectation(
                for: NSPredicate(format: "value != %@", previousViewport), evaluatedWith: map
            )
            wait(for: [panned], timeout: 8)
            let afterPan = try visibleMarkerSnapshot("after-street-pan")
            XCTAssertEqual(Set(afterPan.keys), Set(street.keys))
            for (id, original) in street {
                let current = try XCTUnwrap(afterPan[id])
                XCTAssertEqual(current.latitude, original.latitude)
                XCTAssertEqual(current.longitude, original.longitude)
                XCTAssertEqual(current.groupSize, original.groupSize)
                XCTAssertEqual(current.kind, original.kind)
                XCTAssertEqual(current.diameter, original.diameter, accuracy: 0.2)
            }

            let stack = markers.matching(NSPredicate(format: "label CONTAINS %@", "查看列表")).firstMatch
            XCTAssertTrue(stack.waitForExistence(timeout: 5))
            stack.tap()
            let closeList = webView.buttons["关闭餐厅列表"]
            XCTAssertTrue(closeList.waitForExistence(timeout: 8),
                          "A street stack must open its real Restaurant list, not repeatedly zoom")
            let memberRows = webView.buttons.matching(
                NSPredicate(format: "label BEGINSWITH %@", "查看餐厅 ")
            )
            XCTAssertGreaterThan(memberRows.count, 1)
            XCTAssertLessThanOrEqual(memberRows.count, 18)
            keepScreenshot(named: "Hybrid Native Stack Real Restaurant List", of: app)
            closeList.tap()
            XCTAssertTrue(map.waitForExistence(timeout: 8))
            print("MAP_LOCAL_WORKFLOW_PASS: real close/open pinch, restored Restaurant IDs, fixed-circle pan, complete-member list and return")
            return
        }

        for _ in 0 ..< 10 where latitudeSpan() < 2.5 { try zoom(0.5) }
        XCTAssertGreaterThanOrEqual(latitudeSpan(), 2.4)
        let region = try visibleMarkerSnapshot("region")
        XCTAssertTrue(region.values.contains { $0.kind == "representative" },
                      "Wider-area grouping must retain a real Restaurant image")
        XCTAssertLessThan(region.count, city.count)
        keepScreenshot(named: "Hybrid Native Regional Restaurant Image", of: app)
        for _ in 0 ..< 10 where latitudeSpan() > 0.08 { try zoom(1.8) }
        XCTAssertLessThanOrEqual(latitudeSpan(), 0.8)
        let returnedCity = try visibleMarkerSnapshot("city-restored-after-region")
        XCTAssertFalse(returnedCity.values.contains { $0.kind == "representative" })
        XCTAssertEqual(Set(returnedCity.keys), Set(city.keys))
        keepScreenshot(named: "Hybrid Native City Restaurant Images Restored", of: app)
    }

    @MainActor
    func testHybridIndependentMapFiltersAndNaturalRestaurantOverlap() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--tastemap-hybrid-development", "-AppleInterfaceStyle", "Light"]
        app.launchEnvironment = ["TASTEMAP_VISUAL_QA_MODE": "rich", "TASTEMAP_MAP_GEOMETRY_QA": "1"]
        app.launch()
        let web = app.webViews.firstMatch
        XCTAssertTrue(web.waitForExistence(timeout: 20))
        web.buttons["地图"].tap()
        let map = app.descendants(matching: .any)["restaurant-map"]
        XCTAssertTrue(map.waitForExistence(timeout: 15))
        let markers = app.otherElements.matching(NSPredicate(format: "identifier BEGINSWITH %@", "restaurant-map-marker-"))
        XCTAssertTrue(markers.firstMatch.waitForExistence(timeout: 12))
        let settle = expectation(description: "Initial map and image snapshot")
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { settle.fulfill() }
        wait(for: [settle], timeout: 3)
        let area = app.otherElements["restaurant-map-gesture-area"]
        XCTAssertTrue(area.waitForExistence(timeout: 8))
        let geometry = try NSRegularExpression(pattern: #"^anchorError ([-+0-9.]+),([-+0-9.]+);"#)
        @MainActor func evidence(_ phase: String) throws -> [String: String] {
            var members: [String: String] = [:]
            for marker in markers.allElementsBoundByIndex where marker.frame.intersects(area.frame) {
                let value = try XCTUnwrap(marker.value as? String)
                let match = try XCTUnwrap(geometry.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)))
                let offsets = try (1...2).map { index in
                    try XCTUnwrap(Double(value[try XCTUnwrap(Range(match.range(at: index), in: value))]))
                }
                XCTAssertLessThanOrEqual(hypot(offsets[0], offsets[1]), 1, value)
                XCTAssertEqual(marker.frame.width, 44, accuracy: 1)
                XCTAssertEqual(marker.frame.height, 44, accuracy: 1)
                members[marker.identifier] = value.components(separatedBy: "; members ").last
                print("NATURAL_OVERLAP \(phase) \(marker.identifier) \(value)")
            }
            XCTAssertFalse(members.isEmpty)
            keepScreenshot(named: "Natural Restaurant Overlap — \(phase)", of: app)
            return members
        }
        let original = try evidence("initial")
        XCTAssertTrue(original.values.allSatisfy { $0.split(separator: ",").count <= 3 }, "The rejected five-image nearby flower layout must not return")
        XCTAssertTrue(original.values.contains { $0.split(separator: ",").count == 1 }, "Distinct coordinates remain independent markers")
        for step in 0..<4 {
            let reverse = step % 2 == 1
            let a = area.coordinate(withNormalizedOffset: CGVector(dx: reverse ? 0.55 : 0.45, dy: 0.5))
            let b = area.coordinate(withNormalizedOffset: CGVector(dx: reverse ? 0.45 : 0.55, dy: 0.5))
            a.press(forDuration: 0.1, thenDragTo: b)
            let current = try evidence("pan-\(step)")
            for id in Set(current.keys).intersection(original.keys) {
                XCTAssertEqual(current[id], original[id], "Pan must not replace or reorder real stack images")
            }
        }
        for scale: CGFloat in [1.7, 0.59, 1.7, 0.59] {
            area.pinch(withScale: scale, velocity: scale > 1 ? 1 : -1)
            _ = try evidence("zoom-\(scale)")
        }
        let rating = web.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "评分")).firstMatch
        rating.tap()
        app.buttons["6 分以上"].tap()
        let city = web.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "城市")).firstMatch
        city.tap()
        app.buttons["杭州"].tap()
        let filtered = expectation(description: "Filtered snapshot and camera settle")
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { filtered.fulfill() }
        wait(for: [filtered], timeout: 3)
        let viewport = map.value as? String
        keepScreenshot(named: "Independent Filters — Visited Hangzhou 6", of: app)
        for scope in ["想吃", "推荐"] {
            web.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "\(scope)，")).firstMatch.tap()
            XCTAssertTrue((rating.value as? String ?? "").contains("不限评分"))
            XCTAssertTrue((city.value as? String ?? "").contains("城市"))
            XCTAssertEqual(map.value as? String, viewport, "Restoring a scope's query must not fit the camera")
            keepScreenshot(named: "Independent Filters — \(scope) Initially Clear", of: app)
        }
        rating.tap()
        app.buttons["9 分以上"].tap()
        web.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "去过，")).firstMatch.tap()
        XCTAssertTrue((rating.value as? String ?? "").contains("6 分以上"))
        XCTAssertTrue((city.value as? String ?? "").contains("杭州"))
        web.buttons["切换到我的列表"].tap()
        XCTAssertTrue((rating.value as? String ?? "").contains("6 分以上"))
        web.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "推荐，")).firstMatch.tap()
        XCTAssertTrue((rating.value as? String ?? "").contains("9 分以上"))
        keepScreenshot(named: "Independent Filters — List Restores Recommendation 9", of: app)
        rating.tap()
        app.buttons["不限评分"].tap()
        web.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "去过，")).firstMatch.tap()
        web.buttons["切换到我的地图"].tap()
        let filterButton = web.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "筛选")).firstMatch
        XCTAssertTrue(filterButton.waitForExistence(timeout: 8))
        filterButton.tap()
        // Reset only this scope; leave the current app on its rich Map preview.
        web.buttons["重置"].tap()
        web.buttons["查看结果"].tap()
        keepScreenshot(named: "Natural Restaurant Overlap — Final Preview", of: app)
    }

    @MainActor
    func testHybridFarZoomShrinksAndProfileSummaryIsCompact() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--tastemap-hybrid-development", "-AppleInterfaceStyle", "Light"]
        app.launchEnvironment = ["TASTEMAP_VISUAL_QA_MODE": "rich", "TASTEMAP_MAP_GEOMETRY_QA": "1"]
        app.launch()
        let web = app.webViews.firstMatch
        XCTAssertTrue(web.waitForExistence(timeout: 20))
        web.buttons["我的"].tap()
        let spend = web.buttons.matching(NSPredicate(format: "label CONTAINS %@", "总消费")).firstMatch
        XCTAssertTrue(spend.waitForExistence(timeout: 12), app.debugDescription)
        XCTAssertGreaterThanOrEqual(spend.frame.height, 44)
        XCTAssertLessThanOrEqual(spend.frame.height, 54)
        keepScreenshot(named: "Compact Profile Statistics", of: app)
        web.buttons["地图"].tap()
        let map = app.descendants(matching: .any)["restaurant-map"]
        XCTAssertTrue(map.waitForExistence(timeout: 15))
        let area = app.otherElements["restaurant-map-gesture-area"]
        XCTAssertTrue(area.waitForExistence(timeout: 10))
        let markers = app.otherElements.matching(NSPredicate(format: "identifier BEGINSWITH %@", "restaurant-map-marker-"))
        XCTAssertTrue(markers.firstMatch.waitForExistence(timeout: 12))
        @MainActor func span() -> Double {
            Double((map.value as? String ?? "").components(separatedBy: "; span ").last?.split(separator: ",").first ?? "0") ?? 0
        }
        @MainActor func zoomOut(to minimum: Double) {
            for _ in 0..<14 where span() < minimum {
                let previous = map.value as? String ?? ""
                area.pinch(withScale: 0.4, velocity: -1)
                let changed = expectation(for: NSPredicate(format: "value != %@", previous), evaluatedWith: map)
                wait(for: [changed], timeout: 8)
            }
            XCTAssertGreaterThanOrEqual(span(), minimum)
        }
        let pattern = try NSRegularExpression(pattern: #"^anchorError ([-+0-9.]+),([-+0-9.]+); diameter ([-+0-9.]+);"#)
        @MainActor func measure(_ phase: String) throws -> Double {
            let marker = try XCTUnwrap(markers.allElementsBoundByIndex.first { $0.frame.intersects(area.frame) })
            let value = try XCTUnwrap(marker.value as? String)
            let match = try XCTUnwrap(pattern.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)))
            let values = try (1...3).map { index in
                try XCTUnwrap(Double(value[try XCTUnwrap(Range(match.range(at: index), in: value))]))
            }
            XCTAssertLessThanOrEqual(hypot(values[0], values[1]), 1, value)
            XCTAssertEqual(marker.frame.width, 44, accuracy: 1)
            XCTAssertGreaterThanOrEqual(values[2], 14)
            print("FAR_ZOOM \(phase) span \(span()) \(value)")
            keepScreenshot(named: "Far Zoom Restaurant Size — \(phase)", of: app)
            return values[2]
        }
        zoomOut(to: 1.5)
        let region = try measure("region")
        zoomOut(to: 12)
        let country = try measure("country")
        XCTAssertLessThan(country, region)
        zoomOut(to: 70)
        let world = try measure("world")
        XCTAssertLessThan(world, country)
        XCTAssertLessThanOrEqual(world, 16)
        for _ in 0..<14 where span() > 0.12 { area.pinch(withScale: 2.5, velocity: 1) }
        _ = try measure("city-restored")
    }

    @MainActor
    func testHybridAcquisitionLoadsRemainingRestaurantsWithoutDuplicates() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--tastemap-hybrid-development", "-AppleInterfaceStyle", "Light"]
        app.launchEnvironment = ["TASTEMAP_VISUAL_QA_MODE": "rich", "TASTEMAP_RESTAURANT_ACQUISITION_UI_TEST": "1"]
        app.launch()
        let web = app.webViews.firstMatch
        XCTAssertTrue(web.waitForExistence(timeout: 20))
        web.buttons["地图"].tap()
        web.buttons["添加餐厅"].tap()
        let query = web.textFields["餐厅名称或地址"]
        XCTAssertTrue(query.waitForExistence(timeout: 12), app.debugDescription)
        query.tap()
        query.typeText("分页测试拉面")
        web.buttons["搜索餐厅"].tap()
        let results = web.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "查看 分页测试拉面"))
        let firstPage = expectation(for: NSPredicate(format: "count == 20"), evaluatedWith: results)
        wait(for: [firstPage], timeout: 12)
        let next = web.buttons["继续加载餐厅"]
        XCTAssertTrue(next.exists)
        for _ in 0..<18 where !next.isHittable { web.swipeUp() }
        XCTAssertTrue(next.isHittable)
        keepScreenshot(named: "Acquisition Pagination — First 20 Synthetic Candidates", of: app)
        next.tap()
        let complete = expectation(for: NSPredicate(format: "count == 24"), evaluatedWith: results)
        wait(for: [complete], timeout: 12)
        XCTAssertEqual(Set(results.allElementsBoundByIndex.map(\.label)).count, 24)
        XCTAssertFalse(next.exists)
        keepScreenshot(named: "Acquisition Pagination — All 24 Without Duplicates", of: app)
        // Editing the query invalidates the previous results/continuation.
        for _ in 0..<18 where !query.isHittable { web.swipeDown() }
        XCTAssertTrue(query.isHittable)
        query.tap()
        query.typeText("没有结果")
        XCTAssertEqual(results.count, 0)
        XCTAssertFalse(next.exists)
        web.buttons["搜索餐厅"].tap()
        XCTAssertTrue(web.staticTexts["没有找到匹配的餐厅，请换一个名称、地址或城市。"].waitForExistence(timeout: 12))
        keepScreenshot(named: "Acquisition Pagination — Edited Query Clears Previous Results", of: app)
    }

    @MainActor
    func testHybridCompleteRatingFilterChoices() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--tastemap-hybrid-development", "-AppleInterfaceStyle", "Light"]
        app.launchEnvironment = ["TASTEMAP_VISUAL_QA_MODE": "rich"]
        app.launch()
        let web = app.webViews.firstMatch
        XCTAssertTrue(web.waitForExistence(timeout: 20))
        web.buttons["地图"].tap()
        let marker = app.otherElements.matching(NSPredicate(format: "identifier BEGINSWITH %@", "restaurant-map-marker-")).firstMatch
        XCTAssertTrue(marker.waitForExistence(timeout: 15))
        let initialPaint = expectation(description: "Allow initial Map snapshot and images to settle before opening the system select")
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { initialPaint.fulfill() }
        wait(for: [initialPaint], timeout: 3)
        let rating = web.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "评分")).firstMatch
        XCTAssertTrue(rating.waitForExistence(timeout: 15), app.debugDescription)
        rating.tap()
        for score in 1...10 {
            let label = score == 10 ? "10 分" : "\(score) 分以上"
            let option = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", label)).firstMatch
            XCTAssertTrue(option.waitForExistence(timeout: 3), "Missing \(label): \(app.debugDescription)")
        }
        keepScreenshot(named: "Complete Map Rating Menu 1 to 10", of: app)
        app.buttons["1 分以上"].tap()
        XCTAssertTrue((rating.value as? String ?? "").contains("1 分以上"))
        rating.tap()
        app.buttons["10 分"].tap()
        XCTAssertTrue((rating.value as? String ?? "").contains("10 分"))
        keepScreenshot(named: "Map Full Score Filter", of: app)
        rating.tap()
        app.buttons["不限评分"].tap()
        XCTAssertTrue((rating.value as? String ?? "").contains("不限评分"))

        web.buttons["切换到我的列表"].tap()
        rating.tap()
        XCTAssertTrue(app.buttons["1 分以上"].exists)
        XCTAssertTrue(app.buttons["10 分"].exists)
        keepScreenshot(named: "Complete List Rating Menu", of: app)
        app.buttons["不限评分"].tap()

        web.buttons["发现"].tap()
        let discoveryRating = web.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "公开评分")).firstMatch
        XCTAssertTrue(discoveryRating.waitForExistence(timeout: 10), app.debugDescription)
        discoveryRating.tap()
        for label in ["1 分以上", "5 分以上", "7.5 分以上", "10 分", "不限评分"] {
            XCTAssertTrue(app.buttons[label].exists, "Missing Discovery option \(label)")
        }
        keepScreenshot(named: "Complete Discovery Rating Menu", of: app)
        app.buttons["不限评分"].tap()
    }

    @MainActor
    func testHybridNativeMapFullFilterSheetStaysAboveMapKit() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--tastemap-hybrid-development", "-AppleInterfaceStyle", "Light"]
        app.launchEnvironment = [
            "TASTEMAP_VISUAL_QA_MODE": "rich",
            "TASTEMAP_CORE_PARITY_INITIAL_TAB": "map",
        ]
        app.launch()

        let webView = app.webViews.firstMatch
        XCTAssertTrue(webView.waitForExistence(timeout: 20))
        let filter = webView.buttons["筛选"]
        if !filter.waitForExistence(timeout: 2) {
            let mapTab = webView.buttons["地图"]
            XCTAssertTrue(mapTab.waitForExistence(timeout: 5))
            mapTab.tap()
        }
        XCTAssertTrue(filter.waitForExistence(timeout: 15))

        let map = app.descendants(matching: .any)["restaurant-map"]
        XCTAssertTrue(map.waitForExistence(timeout: 15))
        XCTAssertTrue(map.isHittable)

        filter.tap()
        XCTAssertTrue(webView.staticTexts["筛选餐厅"].waitForExistence(timeout: 5))
        for label in ["用餐方式", "到访次数", "评分区间 · 可多选", "等待时长", "适合场景 · 可多选", "推荐来源", "人均价格", "到访时间", "距离"] {
            XCTAssertTrue(webView.staticTexts[label].exists, "Full Filter sheet is missing \(label)")
        }
        let done = webView.buttons["查看结果"]
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        keepScreenshot(named: "Hybrid Native Map Full Filter", of: app)
        XCTAssertTrue(done.isHittable, "Full Filter sheet must own touches instead of remaining behind MapKit")
        XCTAssertFalse(map.isHittable, "MapKit must yield while the full Filter sheet is presented")

        done.tap()
        XCTAssertTrue(map.waitForExistence(timeout: 8))
        XCTAssertTrue(map.isHittable)
    }

    @MainActor
    func testHybridNativeMapKitSustainedGesturePerformance() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--tastemap-hybrid-development", "-AppleInterfaceStyle", "Light"]
        app.launchEnvironment = [
            "TASTEMAP_VISUAL_QA_MODE": "rich",
            "TASTEMAP_CORE_PARITY_INITIAL_TAB": "map",
        ]
        app.launch()

        let webView = app.webViews.firstMatch
        XCTAssertTrue(webView.waitForExistence(timeout: 20))
        let map = app.descendants(matching: .any)["restaurant-map"]
        if !map.waitForExistence(timeout: 2) {
            let mapTab = webView.buttons["地图"]
            XCTAssertTrue(mapTab.waitForExistence(timeout: 5))
            mapTab.tap()
        }
        XCTAssertTrue(map.waitForExistence(timeout: 20))
        let options = XCTMeasureOptions()
        options.iterationCount = 1
        measure(metrics: [XCTClockMetric(), XCTMemoryMetric()], options: options) {
            for index in 0 ..< 6 {
                let movingRight = index.isMultiple(of: 2)
                let start = map.coordinate(withNormalizedOffset: CGVector(
                    dx: movingRight ? 0.54 : 0.46,
                    dy: 0.52
                ))
                let end = map.coordinate(withNormalizedOffset: CGVector(
                    dx: movingRight ? 0.46 : 0.54,
                    dy: 0.48
                ))
                start.press(forDuration: 0.05, thenDragTo: end)
            }
            map.pinch(withScale: 1.2, velocity: 1)
            map.pinch(withScale: 0.84, velocity: -1)
        }
        XCTAssertTrue(map.exists)
        XCTAssertTrue(map.isHittable)
        XCTAssertEqual(app.state, .runningForeground)
    }

    @MainActor
    func testHybridActivityAlbumsKeepTwoAndLargerPhotoLayoutsConsistent() throws {
        var measuredSizes: [Int: CGSize] = [:]
        for tab in ["同味之选", "最新"] {
            let app = XCUIApplication()
            app.launchArguments = ["--tastemap-hybrid-development", "-AppleInterfaceStyle", "Light"]
            app.launchEnvironment = ["TASTEMAP_VISUAL_QA_MODE": "rich"]
            app.launch()
            let webView = app.webViews.firstMatch
            XCTAssertTrue(webView.waitForExistence(timeout: 20))
            let discovery = webView.buttons["发现"]
            XCTAssertTrue(discovery.waitForExistence(timeout: 12))
            discovery.tap()
            let feed = webView.buttons[tab]
            XCTAssertTrue(feed.waitForExistence(timeout: 12))
            feed.tap()
            // Latest keeps the existing non-Visit want-to-go card in place.
            let counts = tab == "最新" ? [1, 2, 4, 5, 7, 6] : [1, 2, 4, 5, 6, 7]
            for count in counts {
                let matchingPhotos = webView.buttons.matching(NSPredicate(format: "label CONTAINS %@ AND label ENDSWITH %@", "，图片 ", " / \(count)"))
                let first = matchingPhotos.element(boundBy: 0)
                // WebKit can omit below-fold buttons from the accessibility
                // snapshot. Scroll the real feed before asserting presence.
                for _ in 0..<12 where !first.exists { scrollDiscoveryCardIntoView(in: app) }
                XCTAssertTrue(first.waitForExistence(timeout: 8), "Missing \(count)-photo fixture in \(tab)")
                let albumPrefix = (first.label.components(separatedBy: "，图片 ").first ?? first.label) + "，图片 "
                let photos = webView.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", albumPrefix))
                XCTAssertEqual(photos.count, count, "Every original fixture photo should be visible in the activity, without duplicates")
                let last = photos.element(boundBy: count - 1)
                scrollUntilVisible(last, in: app)
                let firstFrame = first.frame
                XCTAssertGreaterThanOrEqual(firstFrame.width, 44)
                XCTAssertEqual(firstFrame.width, firstFrame.height, accuracy: 1)
                if count == 2 {
                    XCTAssertEqual(firstFrame.minY, last.frame.minY, accuracy: 1, "Two photos stay side by side")
                    XCTAssertGreaterThan(last.frame.minX, firstFrame.maxX)
                }
                if let previous = measuredSizes[count] {
                    XCTAssertEqual(firstFrame.width, previous.width, accuracy: 1, "Same Taste and Latest share photo sizing")
                    XCTAssertEqual(firstFrame.height, previous.height, accuracy: 1)
                } else { measuredSizes[count] = firstFrame.size }
                keepScreenshot(named: "Hybrid Activity Album \(tab) \(count) Photos", of: app)
            }
            app.terminate()
        }
    }

    @MainActor
    func testHybridRemainingBatchPrimaryProductRoutesStayInteractiveWithRichData() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--tastemap-hybrid-development", "-AppleInterfaceStyle", "Light"]
        app.launchEnvironment = ["TASTEMAP_VISUAL_QA_MODE": "rich"]
        app.launch()

        let webView = app.webViews.firstMatch
        XCTAssertTrue(webView.waitForExistence(timeout: 20))

        let discovery = webView.buttons["发现"]
        XCTAssertTrue(discovery.waitForExistence(timeout: 12))
        discovery.tap()
        XCTAssertTrue(webView.staticTexts["发现"].waitForExistence(timeout: 12))
        for label in ["关注", "为你推荐", "同味之选", "最新", "趋势"] {
            let tab = webView.buttons[label]
            XCTAssertTrue(tab.waitForExistence(timeout: 8), "Missing Discovery tab: \(label)")
            tab.tap()
        }
        let discoveryRestaurant = webView.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "查看餐厅 ")
        ).firstMatch
        XCTAssertTrue(discoveryRestaurant.waitForExistence(timeout: 8))
        keepScreenshot(named: "Hybrid Batch 01 Discovery", of: app)

        webView.buttons["地图"].tap()
        let add = webView.buttons["添加餐厅"].firstMatch
        XCTAssertTrue(add.waitForExistence(timeout: 8))
        add.tap()
        XCTAssertTrue(webView.staticTexts["搜索餐厅"].waitForExistence(timeout: 8))
        XCTAssertTrue(webView.staticTexts["附近餐厅"].waitForExistence(timeout: 8))
        XCTAssertTrue(webView.buttons["手动添加餐厅"].waitForExistence(timeout: 8))
        XCTAssertTrue(webView.buttons["从外部分享添加"].waitForExistence(timeout: 8))
        keepScreenshot(named: "Hybrid Batch 01 Add Restaurant", of: app)

        webView.buttons["我的"].tap()
        XCTAssertTrue(webView.staticTexts["Lafayette · 丰富美食档案"].waitForExistence(timeout: 12))
        let lists = webView.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "查看全部")
        ).firstMatch
        scrollUntilVisible(lists, in: app)
        XCTAssertTrue(lists.waitForExistence(timeout: 8))
        XCTAssertTrue(lists.isHittable)
        lists.tap()
        XCTAssertTrue(webView.staticTexts["把餐厅整理成收藏或有顺序的榜单；加入食单不会改变想吃状态。"].waitForExistence(timeout: 8))
        let publicLists = webView.descendants(matching: .any)["公开食单"]
        XCTAssertTrue(publicLists.waitForExistence(timeout: 8))
        publicLists.tap()
        XCTAssertTrue(webView.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "朋友来杭带吃")
        ).firstMatch.waitForExistence(timeout: 8))
        keepScreenshot(named: "Hybrid Batch 01 Lists", of: app)

        webView.buttons["我的"].tap()
        let roulette = webView.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "今天吃什么")
        ).firstMatch
        XCTAssertTrue(roulette.waitForExistence(timeout: 8))
        roulette.tap()
        XCTAssertTrue(webView.staticTexts["今天吃什么"].waitForExistence(timeout: 8))
        XCTAssertTrue(webView.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "最多选择 10 家")
        ).firstMatch.waitForExistence(timeout: 8))
        keepScreenshot(named: "Hybrid Batch 01 Roulette", of: app)
        let closeRoulette = webView.buttons["关闭"]
        XCTAssertTrue(closeRoulette.waitForExistence(timeout: 8))
        closeRoulette.tap()

        webView.buttons["我的"].tap()
        XCTAssertTrue(webView.staticTexts["Lafayette · 丰富美食档案"].waitForExistence(timeout: 12))
        let analytics = webView.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "我的口味档案")
        ).firstMatch
        XCTAssertTrue(analytics.waitForExistence(timeout: 8))
        XCTAssertTrue(analytics.isHittable)
        analytics.tap()
        XCTAssertTrue(webView.staticTexts["我的口味档案"].firstMatch.waitForExistence(timeout: 8))
        XCTAssertFalse(webView.staticTexts["数据分析"].exists)
        for label in ["我的口味档案", "最佳饭搭子", "谁最会种草", "本月回顾", "年度回顾"] {
            XCTAssertFalse(webView.buttons[label].exists, "A dedicated report must not render sibling Analytics tabs: \(label)")
        }
        XCTAssertTrue(webView.buttons["数据"].waitForExistence(timeout: 8))
        XCTAssertTrue(webView.buttons["画报"].exists)
        XCTAssertTrue(webView.buttons["分享数据"].exists)
        XCTAssertTrue(webView.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS %@", "我的口味档案完整信息图")
        ).firstMatch.waitForExistence(timeout: 8))
        for label in ["统计周期", "数据总览", "最常吃 TOP 3", "口味偏好", "近期洞察", "消费分布", "人均消费区间", "城市足迹 TOP 5", "常见饭搭子", "用餐时间偏好"] {
            XCTAssertTrue(webView.staticTexts.matching(
                NSPredicate(format: "label CONTAINS %@", label)
            ).firstMatch.waitForExistence(timeout: 8), "Missing Taste Profile module: \(label)")
        }
        keepScreenshot(named: "Hybrid Batch 01 Analytics", of: app)

        webView.buttons["我的"].tap()
        XCTAssertTrue(webView.staticTexts["Lafayette · 丰富美食档案"].waitForExistence(timeout: 12))
        scrollToTop(in: app)
        let settings = webView.buttons["设置"]
        XCTAssertTrue(settings.waitForExistence(timeout: 8))
        XCTAssertFalse(webView.staticTexts["数据与设置"].exists)
        XCTAssertFalse(webView.staticTexts["账号与隐私"].exists)
        settings.tap()
        XCTAssertTrue(webView.staticTexts["设置"].waitForExistence(timeout: 8))
        XCTAssertTrue(webView.staticTexts["账户与安全"].waitForExistence(timeout: 8))
        XCTAssertTrue(webView.staticTexts["隐私"].waitForExistence(timeout: 8))
        XCTAssertTrue(webView.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "Backup v1 不包含照片原图")
        ).firstMatch.waitForExistence(timeout: 8))
        keepScreenshot(named: "Hybrid Batch 01 Settings", of: app)
    }

    @MainActor
    func testHybridTasteProfileReplicatesApprovedEditorialCompositionAndPoster() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--tastemap-hybrid-development", "-AppleInterfaceStyle", "Light"]
        app.launchEnvironment = ["TASTEMAP_VISUAL_QA_MODE": "rich"]
        app.launch()

        let webView = app.webViews.firstMatch
        XCTAssertTrue(webView.waitForExistence(timeout: 20))
        XCTAssertTrue(webView.staticTexts["Lafayette · 丰富美食档案"].waitForExistence(timeout: 12))
        let analytics = webView.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "我的口味档案")
        ).firstMatch
        XCTAssertTrue(analytics.waitForExistence(timeout: 8))
        analytics.tap()

        XCTAssertTrue(webView.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS %@", "我的口味档案完整信息图")
        ).firstMatch.waitForExistence(timeout: 12))
        for label in ["统计周期", "数据总览", "最常吃 TOP 3", "口味偏好", "近期洞察", "消费分布", "人均消费区间", "城市足迹 TOP 5", "常见饭搭子", "用餐时间偏好"] {
            XCTAssertTrue(webView.staticTexts.matching(
                NSPredicate(format: "label CONTAINS %@", label)
            ).firstMatch.waitForExistence(timeout: 8), "Missing Taste Profile module: \(label)")
        }
        keepScreenshot(named: "Taste Profile Approved Editorial Analysis", of: app)

        webView.buttons["画报"].tap()
        XCTAssertTrue(webView.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS %@", "我的口味档案 2:3 画报预览")
        ).firstMatch.waitForExistence(timeout: 12))
        XCTAssertTrue(webView.buttons["分享这张画报"].waitForExistence(timeout: 8))
        XCTAssertTrue(webView.images.matching(
            NSPredicate(format: "label CONTAINS %@", "我的口味档案 2:3 分享画报")
        ).firstMatch.waitForExistence(timeout: 15))
        keepScreenshot(named: "Taste Profile Approved Editorial Poster", of: app)
    }

    @MainActor
    func testHybridOwnedRestaurantDetailPaintsWithoutAColdLoadingScreen() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--tastemap-hybrid-development", "-AppleInterfaceStyle", "Light"]
        app.launchEnvironment = ["TASTEMAP_VISUAL_QA_MODE": "rich"]
        app.launch()

        let webView = app.webViews.firstMatch
        XCTAssertTrue(webView.waitForExistence(timeout: 20))
        let profileTab = webView.buttons["我的"]
        XCTAssertTrue(profileTab.waitForExistence(timeout: 8))
        profileTab.tap()
        XCTAssertTrue(webView.staticTexts["Lafayette · 丰富美食档案"].waitForExistence(timeout: 12))
        let visited = webView.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "去过")
        ).firstMatch
        XCTAssertTrue(visited.waitForExistence(timeout: 5))
        visited.tap()
        let restaurant = webView.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "青岚寿司 1")
        ).firstMatch
        XCTAssertTrue(restaurant.waitForExistence(timeout: 8))

        let startedAt = ProcessInfo.processInfo.systemUptime
        restaurant.tap()
        let detailBack = webView.buttons["返回上一页"]
        let deadline = startedAt + 1.5
        while !detailBack.exists && ProcessInfo.processInfo.systemUptime < deadline {
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.02))
        }
        let paintDuration = ProcessInfo.processInfo.systemUptime - startedAt

        XCTAssertTrue(detailBack.exists)
        XCTAssertLessThan(paintDuration, 1.5, "An owned Restaurant should paint from the warm Profile snapshot")
        XCTAssertFalse(webView.staticTexts["正在读取餐厅详情…"].exists)
        XCTAssertTrue(webView.staticTexts["用户实拍"].waitForExistence(timeout: 8))
        XCTAssertFalse(webView.buttons["加入食单"].exists)
        XCTAssertFalse(webView.buttons["分享"].exists)
        XCTAssertFalse(webView.buttons["编辑"].exists)
        XCTAssertFalse(webView.buttons["删除"].exists)
        keepScreenshot(named: "Hybrid Warm Restaurant Detail", of: app)
    }

    @MainActor
    func testHybridRestaurantAvatarEditorSavesCompositeEmoji() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--tastemap-hybrid-development", "-AppleInterfaceStyle", "Light"]
        app.launchEnvironment = ["TASTEMAP_VISUAL_QA_MODE": "rich"]
        app.launch()

        let webView = app.webViews.firstMatch
        XCTAssertTrue(webView.waitForExistence(timeout: 20))
        let profileTab = webView.buttons["我的"]
        XCTAssertTrue(profileTab.waitForExistence(timeout: 8))
        profileTab.tap()
        XCTAssertTrue(webView.staticTexts["Lafayette · 丰富美食档案"].waitForExistence(timeout: 12))
        let visited = webView.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "去过")
        ).firstMatch
        XCTAssertTrue(visited.waitForExistence(timeout: 8))
        visited.tap()
        let restaurant = webView.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "青岚寿司 1")
        ).firstMatch
        XCTAssertTrue(restaurant.waitForExistence(timeout: 8))
        restaurant.tap()

        let editAvatar = webView.buttons["修改餐厅头像"]
        XCTAssertTrue(editAvatar.waitForExistence(timeout: 12))
        XCTAssertLessThan(editAvatar.frame.midX, app.frame.width / 3)
        XCTAssertEqual(editAvatar.frame.width, 44, accuracy: 2)
        editAvatar.tap()
        XCTAssertTrue(webView.staticTexts["修改餐厅头像"].waitForExistence(timeout: 8))
        XCTAssertTrue(webView.buttons["上传图片"].exists)
        XCTAssertTrue(webView.buttons["使用表情"].exists)
        keepScreenshot(named: "Hybrid Restaurant Avatar Choices", of: app)

        webView.buttons["使用表情"].tap()
        XCTAssertTrue(webView.textFields["餐厅头像表情"].waitForExistence(timeout: 8))
        let compositeEmoji = webView.buttons["使用表情 🧑🏽‍🍳"]
        XCTAssertTrue(compositeEmoji.waitForExistence(timeout: 8))
        compositeEmoji.tap()
        webView.buttons["保存头像"].tap()

        let savedAvatar = webView.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@", "青岚寿司 1 餐厅头像", "🧑🏽‍🍳")
        ).firstMatch
        XCTAssertTrue(savedAvatar.waitForExistence(timeout: 12))
        keepScreenshot(named: "Hybrid Restaurant Composite Emoji Avatar", of: app)

        webView.buttons["返回上一页"].tap()
        XCTAssertTrue(webView.staticTexts["Lafayette · 丰富美食档案"].waitForExistence(timeout: 10))
        visited.tap()
        XCTAssertTrue(restaurant.waitForExistence(timeout: 8))
        restaurant.tap()
        XCTAssertTrue(savedAvatar.waitForExistence(timeout: 12), "Restaurant avatar must persist after leaving and reopening detail.")
    }

    @MainActor
    func testHybridMapNeverCoversDiscoveryAfterRepeatedTabSwitches() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--tastemap-hybrid-development", "-AppleInterfaceStyle", "Light"]
        app.launchEnvironment = ["TASTEMAP_VISUAL_QA_MODE": "rich"]
        app.launch()
        let web = app.webViews.firstMatch
        XCTAssertTrue(web.waitForExistence(timeout: 20))
        web.buttons["地图"].tap()
        let map = app.descendants(matching: .any)["restaurant-map"]
        XCTAssertTrue(map.waitForExistence(timeout: 12))
        let ready = expectation(for: NSPredicate(format: "value CONTAINS %@", "center"), evaluatedWith: map)
        wait(for: [ready], timeout: 10)
        let initialViewport = map.value as? String ?? ""
        let start = map.coordinate(withNormalizedOffset: CGVector(dx: 0.66, dy: 0.52))
        let end = map.coordinate(withNormalizedOffset: CGVector(dx: 0.38, dy: 0.52))
        start.press(forDuration: 0.1, thenDragTo: end)
        let moved = expectation(for: NSPredicate(format: "value != %@", initialViewport), evaluatedWith: map)
        wait(for: [moved], timeout: 8)
        // Read the published settled viewport, not the pre-gesture probe value.
        let viewport = map.value as? String
        for index in 0..<8 {
            web.buttons["发现"].tap()
            XCTAssertTrue(web.buttons["为你推荐"].waitForExistence(timeout: 8))
            XCTAssertTrue(map.waitForNonExistence(timeout: 4), "Native MapKit leaked into Discovery on switch \(index)")
            web.buttons[index.isMultiple(of: 2) ? "同味之选" : "为你推荐"].tap()
            XCTAssertFalse(map.exists, "Discovery tab updates must not resurrect MapKit")
            web.buttons["地图"].tap()
            XCTAssertTrue(map.waitForExistence(timeout: 8))
            XCTAssertEqual(map.value as? String, viewport, "Tab switching must preserve the user's map viewport")
        }
        web.buttons["切换到我的列表"].tap()
        XCTAssertTrue(map.waitForNonExistence(timeout: 4))
        web.buttons["切换到我的地图"].tap()
        XCTAssertTrue(map.waitForExistence(timeout: 8))
        XCTAssertEqual(map.value as? String, viewport)
        keepScreenshot(named: "Map Layer Returned With Preserved Viewport", of: app)
        web.buttons["我的"].tap()
        XCTAssertTrue(map.waitForNonExistence(timeout: 4))
        web.buttons["设置"].tap()
        XCTAssertTrue(web.staticTexts["会员权益"].waitForExistence(timeout: 8))
        XCTAssertFalse(map.exists)
        web.buttons["返回上一页"].tap()
        web.buttons["发现"].tap()
        web.buttons["为你推荐"].tap()
        let firstRestaurant = web.buttons["查看餐厅 春日泰味 7"]
        XCTAssertTrue(firstRestaurant.waitForExistence(timeout: 8))
        XCTAssertTrue(firstRestaurant.isHittable)
        XCTAssertFalse(map.exists)
        firstRestaurant.tap()
        XCTAssertTrue(web.buttons["返回上一页"].waitForExistence(timeout: 8))
        XCTAssertFalse(map.exists)
        web.buttons["返回上一页"].tap()
        XCTAssertTrue(firstRestaurant.waitForExistence(timeout: 8))
        keepScreenshot(named: "Discovery Feed After Repeated Map Switches", of: app)
        let initialCardY = firstRestaurant.frame.minY
        web.swipeUp()
        XCTAssertFalse(map.exists, "Scrolling the feed must not reveal the retained Native layer")
        XCTAssertNotEqual(firstRestaurant.frame.minY, initialCardY, "The actual Discovery feed must respond to scrolling")
        keepScreenshot(named: "Discovery Feed Scroll Without Map Overlay", of: app)
    }

    @MainActor
    func testHybridSafeAreaCanvasFollowsTheVisiblePage() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--tastemap-hybrid-development", "-AppleInterfaceStyle", "Light"]
        app.launchEnvironment = ["TASTEMAP_VISUAL_QA_MODE": "rich"]
        app.launch()
        let web = app.webViews.firstMatch
        XCTAssertTrue(web.waitForExistence(timeout: 20))
        web.buttons["我的"].tap()
        XCTAssertTrue(web.staticTexts["Lafayette · 丰富美食档案"].waitForExistence(timeout: 12))
        keepScreenshot(named: "Canvas Profile Initial", of: app)
        web.buttons["发现"].tap()
        XCTAssertTrue(web.buttons["为你推荐"].waitForExistence(timeout: 8))
        keepScreenshot(named: "Canvas Discovery", of: app)
        web.buttons["地图"].tap()
        XCTAssertTrue(web.buttons["添加餐厅"].waitForExistence(timeout: 8))
        keepScreenshot(named: "Canvas Map", of: app)
        web.buttons["添加餐厅"].tap()
        XCTAssertTrue(web.buttons["返回上一页"].waitForExistence(timeout: 8))
        keepScreenshot(named: "Canvas Add", of: app)
        web.buttons["返回上一页"].tap()
        web.buttons["我的"].tap()
        web.buttons["设置"].tap()
        XCTAssertTrue(web.staticTexts["会员权益"].waitForExistence(timeout: 8))
        keepScreenshot(named: "Canvas Settings", of: app)
        web.buttons["返回上一页"].tap()
        XCTAssertTrue(web.staticTexts["Lafayette · 丰富美食档案"].waitForExistence(timeout: 8))
        XCTAssertFalse(web.buttons["编辑资料"].exists)
        XCTAssertTrue(web.buttons.matching(NSPredicate(format: "label CONTAINS %@", "今天吃什么")).firstMatch.exists)
        keepScreenshot(named: "Canvas Profile Returned", of: app)
    }

    @MainActor
    func testHybridSettingsMembershipIsVisibleNearTopAndOpensBenefits() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--tastemap-hybrid-development", "-AppleInterfaceStyle", "Light"]
        app.launchEnvironment = ["TASTEMAP_VISUAL_QA_MODE": "rich"]
        app.launch()
        let web = app.webViews.firstMatch
        XCTAssertTrue(web.waitForExistence(timeout: 20))
        web.buttons["我的"].tap()
        web.buttons["设置"].tap()
        let premium = web.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Premium")).firstMatch
        XCTAssertTrue(premium.waitForExistence(timeout: 8))
        let account = web.buttons.matching(NSPredicate(format: "label CONTAINS %@", "账户与安全")).firstMatch
        let backup = web.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "导出备份")).firstMatch
        XCTAssertTrue(premium.isHittable)
        XCTAssertGreaterThan(premium.frame.minY, account.frame.maxY)
        XCTAssertLessThan(premium.frame.maxY, backup.frame.minY)
        XCTAssertLessThan(premium.frame.maxY, app.frame.height - 100)
        XCTAssertTrue(web.staticTexts["会员权益"].exists)
        XCTAssertFalse(web.staticTexts["存储与 Premium"].exists)
        keepScreenshot(named: "Settings Membership Near Top", of: app)
        premium.tap()
        XCTAssertTrue(web.staticTexts["已开通"].waitForExistence(timeout: 8))
        XCTAssertTrue(web.buttons["管理会员"].exists)
        keepScreenshot(named: "Settings Membership Benefits Destination", of: app)
        web.buttons["返回上一页"].tap()
        XCTAssertTrue(premium.waitForExistence(timeout: 8))
        XCTAssertTrue(premium.isHittable)
        keepScreenshot(named: "Settings Membership Ready For Review", of: app)
    }

    @MainActor
    func testNativeAboutICPRegistrationOpensSystemBrowser() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-p1d-persistent-offline-fixture", "-p1d-reset-persistent-offline-fixture", "-AppleInterfaceStyle", "Light"]
        app.launchEnvironment = ["TASTEMAP_P1D_UI_TEST": "1", "TASTEMAP_P1D_RESET": "1", "TASTEMAP_P3A_PROFILE_UI_TEST": "1", "TASTEMAP_F1B3_SETTINGS_UI_TEST": "1"]
        app.launch()
        app.buttons["我的"].tap()
        let settings = app.buttons["profile-settings-entry"]
        scrollUntilVisible(settings, in: app)
        settings.tap()
        XCTAssertTrue(app.navigationBars["设置"].waitForExistence(timeout: 5))
        let about = app.buttons["settings-about-entry"]
        scrollUntilVisible(about, in: app)
        about.tap()
        XCTAssertTrue(app.navigationBars["关于"].waitForExistence(timeout: 5))
        let registration = app.descendants(matching: .any)["settings-icp-registration-link"].firstMatch
        XCTAssertTrue(registration.waitForExistence(timeout: 5))
        XCTAssertEqual(registration.label, "备案号：浙ICP备2026070007号-1A")
        XCTAssertTrue(registration.isHittable)
        XCTAssertGreaterThanOrEqual(registration.frame.height, 44)
        XCTAssertTrue(app.descendants(matching: .any)["settings-app-version"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["settings-build-number"].exists)
        keepScreenshot(named: "Native About ICP Registration", of: app)

        registration.tap()
        let safari = XCUIApplication(bundleIdentifier: "com.apple.mobilesafari")
        XCTAssertTrue(safari.wait(for: .runningForeground, timeout: 10))
        let address = safari.textFields.matching(NSPredicate(
            format: "value CONTAINS %@", "beian.miit.gov.cn"
        )).firstMatch
        XCTAssertTrue(address.waitForExistence(timeout: 10))
        keepScreenshot(named: "ICP Registration System Browser", of: safari)
        app.activate()
        XCTAssertTrue(registration.waitForExistence(timeout: 5))
    }

    @MainActor
    func testNativeSettingsMembershipIsVisibleNearTopAndOpensBenefits() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-p1d-persistent-offline-fixture", "-p1d-reset-persistent-offline-fixture", "-AppleInterfaceStyle", "Light"]
        app.launchEnvironment = ["TASTEMAP_P1D_UI_TEST": "1", "TASTEMAP_P1D_RESET": "1", "TASTEMAP_P3A_PROFILE_UI_TEST": "1", "TASTEMAP_F1B3_SETTINGS_UI_TEST": "1"]
        app.launch()
        app.buttons["我的"].tap()
        let settings = app.buttons["profile-settings-entry"]
        XCTAssertTrue(settings.waitForExistence(timeout: 8))
        settings.tap()
        XCTAssertTrue(app.navigationBars["设置"].waitForExistence(timeout: 5))
        let premium = app.buttons["settings-premium-entry"]
        let account = app.buttons["settings-account-entry"]
        let data = app.buttons["settings-data-backup-entry"]
        XCTAssertTrue(premium.isHittable)
        XCTAssertGreaterThan(premium.frame.minY, account.frame.maxY)
        XCTAssertLessThan(premium.frame.maxY, data.frame.minY)
        XCTAssertLessThan(premium.frame.maxY, app.frame.height - 100)
        keepScreenshot(named: "Native Settings Membership Near Top", of: app)
        premium.tap()
        XCTAssertTrue(app.navigationBars["Premium"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["settings-premium-paywall"].exists)
        keepScreenshot(named: "Native Settings Membership Destination", of: app)
    }

    @MainActor
    func testHybridSettingsAccountEntryOpensOnlyAccountAndSecurity() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--tastemap-hybrid-development", "-AppleInterfaceStyle", "Light"]
        app.launchEnvironment = ["TASTEMAP_VISUAL_QA_MODE": "rich"]
        app.launch()

        let webView = app.webViews.firstMatch
        XCTAssertTrue(webView.waitForExistence(timeout: 20))
        webView.buttons["我的"].tap()
        XCTAssertTrue(webView.staticTexts["Lafayette · 丰富美食档案"].waitForExistence(timeout: 12))
        scrollToTop(in: app)
        webView.buttons["设置"].tap()

        let accountEntry = webView.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "账户与安全")
        ).firstMatch
        XCTAssertTrue(accountEntry.waitForExistence(timeout: 8))
        XCTAssertFalse(webView.staticTexts["账户与资料"].exists)
        XCTAssertFalse(webView.staticTexts["账户安全"].exists)
        keepScreenshot(named: "Hybrid Settings Consolidated Index", of: app)
        accountEntry.tap()

        XCTAssertTrue(app.navigationBars["账户与安全"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["settings-edit-profile"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["settings-sign-out"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["settings-delete-account"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["settings-data-backup-entry"].exists)
        XCTAssertFalse(app.navigationBars["设置"].exists)
        keepScreenshot(named: "Hybrid Settings Consolidated Account Security", of: app)
    }

    @MainActor
    func testHybridSettingsProfileFieldsEditDirectlyAndPreserveOtherFields() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--tastemap-hybrid-development", "-AppleInterfaceStyle", "Light"]
        app.launchEnvironment = ["TASTEMAP_VISUAL_QA_MODE": "rich"]
        app.launch()
        let webView = app.webViews.firstMatch
        XCTAssertTrue(webView.waitForExistence(timeout: 20))
        webView.buttons["我的"].tap()
        XCTAssertTrue(webView.staticTexts["Lafayette · 丰富美食档案"].waitForExistence(timeout: 12))
        scrollToTop(in: app)
        webView.buttons["设置"].tap()
        let account = webView.buttons.matching(NSPredicate(format: "label CONTAINS %@", "账户与安全")).firstMatch
        XCTAssertTrue(account.waitForExistence(timeout: 8))
        account.tap()

        let nameRow = app.buttons["settings-edit-display-name"]
        XCTAssertTrue(nameRow.waitForExistence(timeout: 8))
        let initialName = nameRow.value as? String
        nameRow.tap()
        XCTAssertTrue(app.navigationBars["修改显示名称"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.textFields["profile-city"].exists)
        XCTAssertFalse(app.buttons["profile-avatar-picker"].exists)
        let name = app.textFields["profile-display-name"]
        name.clearAndType("设置直接修改")
        keepScreenshot(named: "Settings Direct Name Editor", of: app)
        XCTAssertFalse(app.navigationBars["修改显示名称"].buttons["取消"].exists)
        app.navigationBars["修改显示名称"].buttons["profile-back-button"].tap()
        XCTAssertTrue(nameRow.waitForExistence(timeout: 5))
        XCTAssertEqual(nameRow.value as? String, initialName)

        nameRow.tap()
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.clearAndType("设置直接修改")
        app.buttons["profile-save-button"].tap()
        XCTAssertTrue(app.navigationBars["账户与安全"].waitForExistence(timeout: 8))
        XCTAssertEqual(nameRow.value as? String, "设置直接修改")

        let visibility = app.buttons["settings-edit-profile-visibility"]
        XCTAssertTrue(visibility.exists)
        visibility.tap()
        XCTAssertTrue(app.navigationBars["主页可见范围"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.textFields["profile-display-name"].exists)
        let privateChoice = app.buttons["profile-visibility-仅自己"]
        XCTAssertTrue(privateChoice.waitForExistence(timeout: 5))
        privateChoice.tap()
        keepScreenshot(named: "Settings Direct Visibility Editor", of: app)
        app.buttons["profile-save-button"].tap()
        XCTAssertTrue(app.navigationBars["账户与安全"].waitForExistence(timeout: 8))
        XCTAssertEqual(visibility.value as? String, "仅自己")
        XCTAssertEqual(nameRow.value as? String, "设置直接修改")
        keepScreenshot(named: "Settings Direct Editable Account Rows", of: app)

        app.buttons["settings-edit-profile"].tap()
        XCTAssertTrue(app.navigationBars["编辑资料"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.textFields["profile-city"].exists)
        XCTAssertTrue(app.textFields["profile-display-name"].exists)
        XCTAssertFalse(app.navigationBars["编辑资料"].buttons["取消"].exists)
        app.navigationBars["编辑资料"].buttons["profile-back-button"].tap()

        app.navigationBars["账户与安全"].buttons["返回"].tap()
        XCTAssertTrue(webView.staticTexts["设置"].waitForExistence(timeout: 8))
        let updatedAccount = webView.buttons.matching(NSPredicate(format: "label CONTAINS %@", "账户与安全")).firstMatch
        XCTAssertTrue(updatedAccount.waitForExistence(timeout: 8))
        XCTAssertTrue(updatedAccount.label.contains("设置直接修改"))
        updatedAccount.tap()
        XCTAssertTrue(app.buttons["settings-edit-display-name"].waitForExistence(timeout: 8))
        XCTAssertEqual(app.buttons["settings-edit-display-name"].value as? String, "设置直接修改")
        XCTAssertEqual(app.buttons["settings-edit-profile-visibility"].value as? String, "仅自己")
    }

    @MainActor
    func testHybridPrivacySettingOpensOnlyVisibilityEditor() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--tastemap-hybrid-development", "-AppleInterfaceStyle", "Light"]
        app.launchEnvironment = ["TASTEMAP_VISUAL_QA_MODE": "rich"]
        app.launch()
        let webView = app.webViews.firstMatch
        XCTAssertTrue(webView.waitForExistence(timeout: 20))
        webView.buttons["我的"].tap()
        XCTAssertTrue(webView.staticTexts["Lafayette · 丰富美食档案"].waitForExistence(timeout: 12))
        scrollToTop(in: app)
        webView.buttons["设置"].tap()
        let privacy = webView.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "隐私 ")).firstMatch
        scrollUntilVisible(privacy, in: app)
        XCTAssertTrue(privacy.isHittable)
        privacy.tap()
        XCTAssertTrue(app.navigationBars["隐私"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.staticTexts["当前可见范围"].exists)
        app.buttons["settings-privacy-edit-profile"].tap()
        XCTAssertTrue(app.navigationBars["主页可见范围"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.textFields["profile-display-name"].exists)
        XCTAssertTrue(app.buttons["profile-visibility-公开"].exists)
        keepScreenshot(named: "Privacy Focused Visibility Editor", of: app)
        XCTAssertFalse(app.navigationBars["主页可见范围"].buttons["取消"].exists)
        app.navigationBars["主页可见范围"].buttons["profile-back-button"].tap()
        XCTAssertTrue(app.navigationBars["隐私"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testHybridNativeProfileEditRefreshesWithoutRelaunch() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--tastemap-hybrid-development", "-AppleInterfaceStyle", "Light"]
        app.launchEnvironment = ["TASTEMAP_VISUAL_QA_MODE": "rich"]
        app.launch()

        let webView = app.webViews.firstMatch
        XCTAssertTrue(webView.waitForExistence(timeout: 20))
        webView.buttons["我的"].tap()
        XCTAssertTrue(webView.staticTexts["Lafayette · 丰富美食档案"].waitForExistence(timeout: 12))
        scrollToTop(in: app)

        XCTAssertFalse(webView.buttons["编辑资料"].exists)
        XCTAssertTrue(webView.buttons["编辑个人资料"].exists, "The pre-existing avatar action is not part of this removal")
        webView.buttons["设置"].tap()
        let account = webView.buttons.matching(NSPredicate(format: "label CONTAINS %@", "账户与安全")).firstMatch
        XCTAssertTrue(account.waitForExistence(timeout: 8))
        account.tap()
        let edit = app.buttons["settings-edit-profile"]
        XCTAssertTrue(edit.waitForExistence(timeout: 8))
        edit.tap()
        XCTAssertTrue(app.navigationBars["编辑资料"].waitForExistence(timeout: 8))
        let bar = app.navigationBars["编辑资料"]
        let back = bar.buttons["profile-back-button"]
        XCTAssertTrue(back.isHittable)
        XCTAssertFalse(bar.buttons["取消"].exists)
        XCTAssertFalse(bar.buttons["返回"].exists, "The Native host must not add another exit")
        XCTAssertEqual(bar.buttons.count, 2, "Only back and save belong in the editor toolbar")
        XCTAssertGreaterThanOrEqual(back.frame.width, 44)
        XCTAssertGreaterThanOrEqual(back.frame.height, 44)
        XCTAssertTrue(app.buttons["profile-avatar-picker"].exists)
        XCTAssertTrue(app.textFields["profile-city"].exists)
        XCTAssertTrue(app.buttons["profile-visibility-公开"].exists)
        keepScreenshot(named: "Profile Editor Single Back Icon", of: app)

        let name = app.textFields["profile-display-name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        let initialName = name.value as? String
        name.clearAndType("不应保存的修改")
        back.tap()
        XCTAssertTrue(app.navigationBars["账户与安全"].waitForExistence(timeout: 8))
        edit.tap()
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        XCTAssertEqual(name.value as? String, initialName, "Back discards the draft without saving")
        name.tap()
        name.clearAndType("即时刷新用户")
        app.buttons["profile-save-button"].tap()

        XCTAssertTrue(app.navigationBars["账户与安全"].waitForExistence(timeout: 8))
        XCTAssertEqual(app.buttons["settings-edit-display-name"].value as? String, "即时刷新用户")
        app.navigationBars["账户与安全"].buttons["返回"].tap()
        XCTAssertTrue(webView.staticTexts["设置"].waitForExistence(timeout: 8))
        webView.buttons["返回上一页"].tap()
        XCTAssertTrue(
            webView.staticTexts["即时刷新用户"].waitForExistence(timeout: 12),
            "A successful Native settings save must refresh the running Hybrid profile without relaunching"
        )
        XCTAssertFalse(webView.buttons["编辑资料"].exists)
    }

    @MainActor
    func testHybridSettingsClearsOnlyLocalDataAfterConfirmation() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--tastemap-hybrid-development", "-AppleInterfaceStyle", "Light"]
        app.launchEnvironment = ["TASTEMAP_VISUAL_QA_MODE": "rich"]
        app.launch()

        let webView = app.webViews.firstMatch
        XCTAssertTrue(webView.waitForExistence(timeout: 20))
        webView.buttons["我的"].tap()
        XCTAssertTrue(webView.staticTexts["Lafayette · 丰富美食档案"].waitForExistence(timeout: 12))
        scrollToTop(in: app)
        XCTAssertTrue(webView.buttons["设置"].waitForExistence(timeout: 8))
        webView.buttons["设置"].tap()

        let clearEntry = webView.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "清除本机数据")
        ).firstMatch
        scrollUntilVisible(clearEntry, in: app)
        XCTAssertTrue(clearEntry.waitForExistence(timeout: 8))
        XCTAssertTrue(clearEntry.label.contains("保留账号、个人资料和云端数据"))
        keepScreenshot(named: "Hybrid Settings Clear Local Data Entry", of: app)
        clearEntry.tap()

        XCTAssertTrue(app.navigationBars["清除数据"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["只清除这台 iPhone"].exists)
        XCTAssertTrue(app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "云端数据、其他设备上的记录")
        ).firstMatch.exists)
        let confirm = app.buttons["settings-clear-local-data-confirm"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 8))
        keepScreenshot(named: "Native Clear Local Data Scope", of: app)
        confirm.tap()
        XCTAssertTrue(app.alerts["清除这台 iPhone 上的数据？"].waitForExistence(timeout: 5))
        app.alerts.buttons["确认清除"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["settings-clear-local-data-success"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["本机数据已清除"].exists)
        keepScreenshot(named: "Native Clear Local Data Success", of: app)

        app.navigationBars["清除数据"].buttons["返回"].tap()
        let emptyOverview = webView.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "0 家餐厅 · 0 次到访")
        ).firstMatch
        XCTAssertTrue(emptyOverview.waitForExistence(timeout: 12))
        webView.buttons["返回上一页"].tap()
        XCTAssertTrue(webView.staticTexts["Lafayette · 丰富美食档案"].waitForExistence(timeout: 10))
    }

    @MainActor
    func testHybridSimilarTasteDoesNotRepeatItsCategoryOnEveryCard() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--tastemap-hybrid-development", "-AppleInterfaceStyle", "Light"]
        app.launchEnvironment = ["TASTEMAP_VISUAL_QA_MODE": "rich"]
        app.launch()

        let webView = app.webViews.firstMatch
        XCTAssertTrue(webView.waitForExistence(timeout: 20))
        let discovery = webView.buttons["发现"]
        XCTAssertTrue(discovery.waitForExistence(timeout: 8))
        discovery.tap()
        let similarTaste = webView.buttons["同味之选"]
        XCTAssertTrue(similarTaste.waitForExistence(timeout: 8))
        similarTaste.tap()

        XCTAssertTrue(webView.buttons["查看同味来源用户 林夏"].waitForExistence(timeout: 8))
        XCTAssertTrue(webView.descendants(matching: .any).matching(
            NSPredicate(format: "label == %@", "林夏本次到访评分 9.0")
        ).firstMatch.waitForExistence(timeout: 8))
        XCTAssertFalse(webView.staticTexts["评分"].exists)
        XCTAssertFalse(webView.staticTexts["林夏的评分"].exists)
        XCTAssertTrue(webView.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "记录 ")
        ).firstMatch.waitForExistence(timeout: 8))
        XCTAssertTrue(webView.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "分享动态 ")
        ).firstMatch.waitForExistence(timeout: 8))
        XCTAssertTrue(webView.staticTexts["同味推荐依据"].waitForExistence(timeout: 8))
        XCTAssertFalse(webView.staticTexts["大家评分"].exists)
        XCTAssertFalse(webView.staticTexts["同味推荐"].exists)
        keepScreenshot(named: "Hybrid Similar Taste Without Repeated Tag", of: app)
    }

    @MainActor
    func testHybridDiscoveryFilterSheetsWorkAcrossEveryTab() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--tastemap-hybrid-development", "-AppleInterfaceStyle", "Light"]
        app.launchEnvironment = ["TASTEMAP_VISUAL_QA_MODE": "rich"]
        app.launch()
        let web = app.webViews.firstMatch
        XCTAssertTrue(web.waitForExistence(timeout: 20))
        web.buttons["发现"].tap()
        for tab in ["为你推荐", "同味之选", "关注", "最新", "趋势"] {
            let tabButton = web.buttons[tab]
            XCTAssertTrue(tabButton.waitForExistence(timeout: 10))
            tabButton.tap()
            // WKWebView exposes an aria-haspopup=dialog trigger as Other.
            // The toolbar shares the label; select its narrower child target.
            let candidates = web.descendants(matching: .any).matching(NSPredicate(format: "label MATCHES %@", "筛选( [0-9]+)?"))
            let filters = candidates.allElementsBoundByIndex.last!
            XCTAssertTrue(filters.waitForExistence(timeout: 5))
            filters.tap()
            XCTAssertTrue(web.staticTexts["筛选餐厅"].waitForExistence(timeout: 5))
            for label in ["筛选城市", "筛选排序", "筛选最低评分"] {
                XCTAssertTrue(web.descendants(matching: .any).matching(NSPredicate(format: "label == %@", label)).firstMatch.exists)
            }
            let rating = web.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "筛选最低评分")).firstMatch
            rating.tap()
            XCTAssertTrue(app.buttons["9 分以上"].waitForExistence(timeout: 3))
            app.buttons["9 分以上"].tap()
            XCTAssertTrue((rating.value as? String ?? "").contains("9 分以上"))
            keepScreenshot(named: "Discovery Filter Controls \(tab)", of: app)
            web.buttons["查看结果"].tap()
            XCTAssertFalse(web.staticTexts["筛选餐厅"].exists)
            let activeFilters = web.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "筛选 1")).firstMatch
            XCTAssertTrue(activeFilters.exists)
            activeFilters.tap()
            XCTAssertTrue((rating.value as? String ?? "").contains("9 分以上"))
            web.buttons["重置"].tap()
            XCTAssertTrue((rating.value as? String ?? "").contains("不限评分"))
            web.buttons["关闭"].tap()
            XCTAssertTrue(web.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "筛选")).firstMatch.exists)
        }
        web.buttons["为你推荐"].tap()
        web.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "筛选")).allElementsBoundByIndex.last!.tap()
        keepScreenshot(named: "Discovery Filters Ready For Review", of: app)
    }

    @MainActor
    func testHybridCompactFiltersShareGeometryAndKeepNativePickers() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--tastemap-hybrid-development", "-AppleInterfaceStyle", "Light"]
        app.launchEnvironment = ["TASTEMAP_VISUAL_QA_MODE": "rich"]
        app.launch()
        let web = app.webViews.firstMatch
        XCTAssertTrue(web.waitForExistence(timeout: 20))
        web.buttons["地图"].tap()
        func control(_ label: String) -> XCUIElement {
            web.descendants(matching: .any).matching(NSPredicate(format: "label == %@", label)).firstMatch
        }
        let city = control("城市")
        XCTAssertTrue(city.waitForExistence(timeout: 10))
        let mapCityWidth = city.frame.width
        let mapCityHeight = city.frame.height
        let mapCityLeft = city.frame.minX
        let mapRatingWidth = control("评分").frame.width
        XCTAssertGreaterThanOrEqual(mapCityHeight, 44)
        keepScreenshot(named: "Shared Filter Geometry My Map", of: app)
        city.tap()
        let hangzhou = app.buttons.matching(NSPredicate(format: "label MATCHES %@", "杭州市?")).firstMatch
        XCTAssertTrue(hangzhou.waitForExistence(timeout: 3))
        hangzhou.tap()
        XCTAssertTrue((city.value as? String ?? "").contains("杭州"))
        city.tap()
        app.buttons["城市"].tap()
        let rating = control("评分")
        rating.tap()
        XCTAssertTrue(app.buttons["9 分以上"].waitForExistence(timeout: 3))
        app.buttons["9 分以上"].tap()
        XCTAssertTrue((rating.value as? String ?? "").contains("9 分以上"))
        rating.tap()
        app.buttons["不限评分"].tap()
        web.buttons["切换到我的列表"].tap()
        XCTAssertEqual(control("城市").frame.width, mapCityWidth, accuracy: 0.5)
        keepScreenshot(named: "Shared Filter Geometry My List", of: app)
        web.buttons["发现"].tap()
        XCTAssertTrue(web.buttons["为你推荐"].waitForExistence(timeout: 8))
        XCTAssertEqual(control("城市").frame.width, mapCityWidth, accuracy: 0.5)
        XCTAssertEqual(control("城市").frame.height, mapCityHeight, accuracy: 0.5)
        XCTAssertEqual(control("城市").frame.minX, mapCityLeft, accuracy: 0.5)
        XCTAssertEqual(control("公开评分").frame.width, mapRatingWidth, accuracy: 0.5)
        keepScreenshot(named: "Shared Filter Geometry Discovery", of: app)
        control("城市").tap()
        XCTAssertTrue(hangzhou.waitForExistence(timeout: 3))
        hangzhou.tap()
        XCTAssertTrue((control("城市").value as? String ?? "").contains("杭州"))
        control("城市").tap()
        app.buttons["城市"].tap()
        control("公开评分").tap()
        app.buttons["9 分以上"].tap()
        XCTAssertTrue((control("公开评分").value as? String ?? "").contains("9 分以上"))
        control("公开评分").tap()
        app.buttons["不限评分"].tap()
        keepScreenshot(named: "Shared Filter Geometry Ready For Review", of: app)
    }

    @MainActor
    func testHybridVisitBlankSpendHasNoUnrecordedHint() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--tastemap-hybrid-development", "-AppleInterfaceStyle", "Light"]
        app.launchEnvironment = ["TASTEMAP_VISUAL_QA_MODE": "rich"]
        app.launch()
        let webView = app.webViews.firstMatch
        XCTAssertTrue(webView.waitForExistence(timeout: 20))
        app.open(URL(string: "tastemap://restaurant/00000000-0000-4000-8000-000000032000")!)
        XCTAssertTrue(webView.buttons["返回上一页"].waitForExistence(timeout: 12))
        let record = webView.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "再次添加 ")).firstMatch
        XCTAssertTrue(record.waitForExistence(timeout: 8))
        tapVisibleFrame(of: record, in: app)
        XCTAssertTrue(webView.staticTexts["记录一次到访"].waitForExistence(timeout: 8))
        let hint = webView.staticTexts["单人消费 · 全额计入"]
        scrollUntilVisible(hint, in: app)
        XCTAssertTrue(hint.exists)
        XCTAssertFalse(webView.staticTexts["尚未计入消费统计"].exists)
        XCTAssertFalse(webView.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "计入总消费 ¥")).firstMatch.exists)
        keepScreenshot(named: "Visit Blank Spend Without Unrecorded Hint", of: app)
        // Inspect only; do not save or mutate a Visit.
    }

    @MainActor
    func testHybridVisitUnframedSummaryVisualCheckpoint() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--tastemap-hybrid-development", "-AppleInterfaceStyle", "Light"]
        app.launchEnvironment = ["TASTEMAP_VISUAL_QA_MODE": "rich"]
        app.launch()
        let webView = app.webViews.firstMatch
        XCTAssertTrue(webView.waitForExistence(timeout: 20))
        // Target this app's canonical Restaurant route directly; Profile's
        // long sheet is not the subject of this narrow visual checkpoint.
        app.open(URL(string: "tastemap://restaurant/00000000-0000-4000-8000-000000032000")!)
        XCTAssertTrue(webView.buttons["返回上一页"].waitForExistence(timeout: 12))
        let editVisit = webView.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "编辑第")).firstMatch
        scrollUntilVisible(editVisit, in: app)
        XCTAssertTrue(editVisit.waitForExistence(timeout: 8))
        tapVisibleFrame(of: editVisit, in: app)
        XCTAssertTrue(webView.staticTexts["编辑到访记录"].waitForExistence(timeout: 8))
        XCTAssertTrue(webView.staticTexts["修改这次到访"].exists)
        keepScreenshot(named: "Visit Unframed Summary", of: app)
        XCTAssertTrue(webView.buttons["保存修改"].exists)
        // Leave this isolated visual editor open; do not mutate any Visit.
    }

    @MainActor
    func testHybridVisitHistoryEditUsesOwnedHybridEditorAndRefreshesDetail() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--tastemap-hybrid-development", "-AppleInterfaceStyle", "Light"]
        app.launchEnvironment = ["TASTEMAP_VISUAL_QA_MODE": "rich"]
        app.launch()

        let webView = app.webViews.firstMatch
        XCTAssertTrue(webView.waitForExistence(timeout: 20))
        webView.buttons["我的"].tap()
        XCTAssertTrue(webView.staticTexts["Lafayette · 丰富美食档案"].waitForExistence(timeout: 12))

        let visited = webView.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "去过")
        ).firstMatch
        XCTAssertTrue(visited.waitForExistence(timeout: 8))
        visited.tap()
        let restaurant = webView.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "青岚寿司 1")
        ).firstMatch
        XCTAssertTrue(restaurant.waitForExistence(timeout: 8))
        restaurant.tap()

        let editVisit = webView.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "编辑第")
        ).firstMatch
        scrollUntilVisible(editVisit, in: app)
        XCTAssertTrue(editVisit.waitForExistence(timeout: 8))
        XCTAssertEqual(webView.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "编辑第")
        ).count, 4)
        editVisit.tap()

        XCTAssertTrue(webView.staticTexts["编辑到访记录"].waitForExistence(timeout: 10))
        let note = webView.textViews["到访笔记"]
        scrollUntilVisible(note, in: app)
        XCTAssertTrue(note.waitForExistence(timeout: 5))
        let noteX = note.frame.minX
        let horizontalDragStart = app.coordinate(withNormalizedOffset: CGVector(dx: 0.78, dy: 0.56))
        let horizontalDragEnd = app.coordinate(withNormalizedOffset: CGVector(dx: 0.22, dy: 0.56))
        horizontalDragStart.press(forDuration: 0.05, thenDragTo: horizontalDragEnd)
        XCTAssertEqual(
            note.frame.minX,
            noteX,
            accuracy: 1,
            "The visit editor must remain horizontally fixed while its contents scroll vertically."
        )
        keepScreenshot(named: "Hybrid Visit Editor Fixed Horizontal Frame", of: app)

        note.tap()
        note.typeText(" Batch 2 Hybrid 编辑后刷新")
        webView.buttons["保存修改"].tap()

        XCTAssertTrue(webView.buttons["返回上一页"].waitForExistence(timeout: 12))
        let refreshedNote = webView.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "Batch 2 Hybrid 编辑后刷新")
        ).firstMatch
        scrollUntilVisible(refreshedNote, in: app)
        XCTAssertTrue(refreshedNote.waitForExistence(timeout: 8))
        webView.buttons["返回上一页"].tap()
        XCTAssertTrue(webView.staticTexts["Lafayette · 丰富美食档案"].waitForExistence(timeout: 8))
        XCTAssertFalse(webView.staticTexts["编辑到访记录"].exists,
                       "Saving must finish the editor history entry, so Detail Back returns to Profile.")
    }

    @MainActor
    func testHybridRecordedSpendRefreshesProfileTotalWithoutRelaunch() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--tastemap-hybrid-development", "-AppleInterfaceStyle", "Light"]
        app.launchEnvironment = ["TASTEMAP_VISUAL_QA_MODE": "rich"]
        app.launch()

        let webView = app.webViews.firstMatch
        XCTAssertTrue(webView.waitForExistence(timeout: 20))
        webView.buttons["我的"].tap()
        XCTAssertTrue(webView.staticTexts["Lafayette · 丰富美食档案"].waitForExistence(timeout: 12))

        let initialSpend = webView.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "总消费")
        ).firstMatch
        XCTAssertTrue(initialSpend.waitForExistence(timeout: 8))
        let initialSpendLabel = initialSpend.label

        let visited = webView.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "去过")
        ).firstMatch
        visited.tap()
        let restaurant = webView.buttons.matching(
            NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@", "去过", "次 · 最近")
        ).firstMatch
        XCTAssertTrue(restaurant.waitForExistence(timeout: 8))
        scrollUntilVisible(restaurant, in: app)
        restaurant.tap()
        let editVisit = webView.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "编辑第")
        ).firstMatch
        scrollUntilVisible(editVisit, in: app)
        XCTAssertTrue(editVisit.waitForExistence(timeout: 8))
        editVisit.tap()

        let aa = webView.buttons["AA"]
        scrollUntilVisible(aa, in: app)
        XCTAssertTrue(aa.exists)
        aa.tap()
        let actualSpend = webView.textFields["消费金额（元）"]
        scrollUntilVisible(actualSpend, in: app)
        XCTAssertTrue(actualSpend.waitForExistence(timeout: 8))
        XCTAssertFalse(webView.textFields["整桌账单（元）"].exists)
        XCTAssertFalse(webView.textFields["我的实际消费（元）"].exists)
        actualSpend.clearAndType("200")
        let people = webView.textFields.matching(NSPredicate(format: "label CONTAINS %@", "用餐人数")).firstMatch
        scrollUntilVisible(people, in: app)
        XCTAssertTrue(people.exists)
        people.clearAndType("4")
        XCTAssertFalse(webView.staticTexts["计入总消费 ¥50.00"].exists)
        XCTAssertFalse(webView.staticTexts["参考人均约 ¥50 / 人"].exists)
        keepScreenshot(named: "Amount Input Without Internal Calculation Copy", of: app)
        webView.buttons["保存修改"].tap()

        XCTAssertTrue(webView.buttons["我的"].waitForExistence(timeout: 12))
        webView.buttons["我的"].tap()
        let changedSpend = webView.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@ AND label != %@", "总消费", initialSpendLabel)
        ).firstMatch
        XCTAssertTrue(
            changedSpend.waitForExistence(timeout: 12),
            "Saving my actual spend must update the running Profile total without relaunching the app"
        )
        keepScreenshot(named: "Hybrid Profile Total Spend Live Refresh", of: app)
    }

    @MainActor
    func testHybridProfileSpendDetailContainsOnlySpendBreakdown() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--tastemap-hybrid-development", "-AppleInterfaceStyle", "Light"]
        app.launchEnvironment = ["TASTEMAP_VISUAL_QA_MODE": "rich"]
        app.launch()

        let webView = app.webViews.firstMatch
        XCTAssertTrue(webView.waitForExistence(timeout: 20))
        webView.buttons["我的"].tap()
        XCTAssertTrue(webView.staticTexts["Lafayette · 丰富美食档案"].waitForExistence(timeout: 12))

        let totalSpend = webView.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "总消费")
        ).firstMatch
        XCTAssertTrue(totalSpend.waitForExistence(timeout: 8))
        totalSpend.tap()

        XCTAssertTrue(webView.staticTexts["消费明细"].waitForExistence(timeout: 8))
        XCTAssertTrue(webView.staticTexts["城市消费"].exists)
        XCTAssertTrue(webView.staticTexts["最近消费"].exists)
        XCTAssertFalse(webView.staticTexts["我的数据"].exists)
        XCTAssertFalse(webView.staticTexts["总用餐次数"].exists)
        XCTAssertFalse(webView.staticTexts["去过餐厅"].exists)
        XCTAssertFalse(webView.staticTexts["去过城市"].exists)
        XCTAssertFalse(webView.staticTexts["复购倾向"].exists)
        keepScreenshot(named: "Hybrid Profile Spend Detail", of: app)
    }

    @MainActor
    func testHybridProfileDoesNotRenderDuplicateFloatingShortcuts() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--tastemap-hybrid-development", "-AppleInterfaceStyle", "Light"]
        app.launchEnvironment = ["TASTEMAP_VISUAL_QA_MODE": "rich"]
        app.launch()

        let webView = app.webViews.firstMatch
        XCTAssertTrue(webView.waitForExistence(timeout: 20))
        webView.buttons["我的"].tap()
        XCTAssertTrue(webView.staticTexts["Lafayette · 丰富美食档案"].waitForExistence(timeout: 12))
        XCTAssertTrue(webView.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "看看我爱吃什么")
        ).firstMatch.waitForExistence(timeout: 8))
        XCTAssertFalse(webView.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "西餐 · 江浙菜 · 甜点")
        ).firstMatch.exists)

        XCTAssertFalse(webView.descendants(matching: .any)["Hybrid 主要功能快捷入口"].exists)
        XCTAssertFalse(webView.buttons["我的食单"].exists)
        XCTAssertFalse(webView.buttons["数据分析"].exists)
        XCTAssertTrue(webView.buttons["设置"].exists)
        XCTAssertFalse(webView.staticTexts["数据与设置"].exists)
        XCTAssertFalse(webView.staticTexts["账号与隐私"].exists)
        let listsEntry = webView.buttons["查看全部食单"].firstMatch
        scrollUntilVisible(listsEntry, in: app)
        XCTAssertTrue(listsEntry.waitForExistence(timeout: 8))
        keepScreenshot(named: "Hybrid Profile Without Floating Shortcuts", of: app)

        scrollToTop(in: app)
        webView.buttons["设置"].tap()
        XCTAssertTrue(webView.staticTexts["设置"].waitForExistence(timeout: 8))
        for label in ["账户与安全", "导出备份", "隐私"] {
            let entry = webView.buttons.matching(
                NSPredicate(format: "label CONTAINS %@", label)
            ).firstMatch
            XCTAssertTrue(entry.waitForExistence(timeout: 8), "Missing unified Settings entry: \(label)")
        }
        keepScreenshot(named: "Hybrid Profile Unified Settings Entry", of: app)
    }

    @MainActor
    func testHybridProfileTasteEntryUsesShortInvitationCopy() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--tastemap-hybrid-development", "-AppleInterfaceStyle", "Light"]
        app.launchEnvironment = ["TASTEMAP_VISUAL_QA_MODE": "rich"]
        app.launch()

        let webView = app.webViews.firstMatch
        XCTAssertTrue(webView.waitForExistence(timeout: 20))
        webView.buttons["我的"].tap()
        XCTAssertTrue(webView.staticTexts["Lafayette · 丰富美食档案"].waitForExistence(timeout: 12))
        XCTAssertTrue(webView.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "看看我爱吃什么")
        ).firstMatch.waitForExistence(timeout: 8))
        XCTAssertFalse(webView.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "西餐 · 江浙菜 · 甜点")
        ).firstMatch.exists)
        keepScreenshot(named: "Hybrid Profile Taste Entry Short Invitation", of: app)
    }

    @MainActor
    func testHybridFiveStoryHomesAndReachableDetails() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--tastemap-hybrid-development", "-AppleInterfaceStyle", "Light"]
        app.launchEnvironment = ["TASTEMAP_VISUAL_QA_MODE": "rich"]
        app.launch()
        let web = app.webViews.firstMatch
        XCTAssertTrue(web.waitForExistence(timeout: 20))
        for (title, cta) in [
            ("我的口味档案", "查看完整分析"),
            ("本月回顾", "查看本月完整回顾"),
            ("年度回顾", "查看完整年鉴"),
            ("最佳饭搭子", "查看完整共同回忆"),
            ("谁最会种草", "查看完整分析"),
        ] {
            web.buttons["我的"].tap()
            XCTAssertTrue(web.staticTexts["Lafayette · 丰富美食档案"].waitForExistence(timeout: 12))
            for _ in 0..<3 { app.swipeDown() }
            let entry = web.buttons.matching(NSPredicate(format: "label CONTAINS %@", title)).firstMatch
            scrollUntilVisible(entry, in: app)
            XCTAssertTrue(entry.isHittable, "Profile entry must remain reachable: \(title)")
            entry.tap()
            XCTAssertTrue(web.staticTexts[title].firstMatch.waitForExistence(timeout: 8))
            keepScreenshot(named: "Story Home \(title)", of: app)
            let complete = web.buttons[cta].firstMatch
            scrollUntilVisible(complete, in: app)
            XCTAssertTrue(complete.isHittable, "Real touchscreen scrolling must reach \(cta)")
            keepScreenshot(named: "Story Home Footer \(title)", of: app)
            complete.tap()
            XCTAssertTrue(web.staticTexts["完整分析"].firstMatch.waitForExistence(timeout: 8))
            // WebKit exposes aria-pressed buttons as Switches to XCTest.
            let records = web.descendants(matching: .any)["原始记录"].firstMatch
            XCTAssertTrue(records.waitForExistence(timeout: 8))
            records.tap()
            XCTAssertTrue(web.staticTexts["参与本报告的原始记录"].waitForExistence(timeout: 8))
            keepScreenshot(named: "Story Original Records \(title)", of: app)
            web.buttons["返回报告首页"].tap()
            XCTAssertTrue(web.staticTexts[title].firstMatch.waitForExistence(timeout: 8))
            web.buttons["返回上一页"].tap()
        }
    }

    @MainActor
    func testHybridTasteProfileQuestionRoutes() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--tastemap-hybrid-development", "-AppleInterfaceStyle", "Light"]
        app.launchEnvironment = ["TASTEMAP_VISUAL_QA_MODE": "rich"]
        app.launch()
        let web = app.webViews.firstMatch
        XCTAssertTrue(web.waitForExistence(timeout: 20))
        XCTAssertTrue(web.buttons["我的"].waitForExistence(timeout: 20))
        web.buttons["我的"].tap()
        XCTAssertTrue(web.staticTexts["Lafayette · 丰富美食档案"].waitForExistence(timeout: 15))
        let entry = web.buttons.matching(NSPredicate(format: "label CONTAINS %@", "我的口味档案")).firstMatch
        XCTAssertTrue(entry.waitForExistence(timeout: 10))
        scrollMemoryElement(entry, in: app)
        entry.tap()
        let complete = web.buttons["查看完整分析"].firstMatch
        XCTAssertTrue(complete.waitForExistence(timeout: 12))
        keepScreenshot(named: "F01 Taste Profile Real Hybrid", of: app)
        scrollMemoryElement(complete, in: app)
        complete.tap()
        XCTAssertTrue(web.staticTexts["从一个问题开始"].waitForExistence(timeout: 8))
        XCTAssertFalse(web.staticTexts["查看章节"].exists)
        keepScreenshot(named: "F02 Five Direct Questions", of: app)
        XCTAssertFalse(web.buttons.matching(NSPredicate(format: "label CONTAINS %@", "饭搭子与来源")).firstMatch.exists)
        let filter = web.buttons["筛选这份档案"].firstMatch
        scrollMemoryElement(filter, in: app)
        filter.tap()
        XCTAssertTrue(web.buttons["应用条件"].waitForExistence(timeout: 8))
        keepScreenshot(named: "F03 Filter Sheet", of: app)
        web.buttons["关闭"].tap()
        XCTAssertTrue(web.staticTexts["从一个问题开始"].exists)
    }

    @MainActor
    func testHybridAnalysisMemoryV2Routes() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--tastemap-hybrid-development", "-AppleInterfaceStyle", "Light"]
        app.launchEnvironment = ["TASTEMAP_VISUAL_QA_MODE": "rich"]
        app.launch()
        let web = app.webViews.firstMatch
        XCTAssertTrue(web.waitForExistence(timeout: 20))
        XCTAssertTrue(web.buttons["我的"].waitForExistence(timeout: 20))
        web.buttons["我的"].tap()
        XCTAssertTrue(web.staticTexts["Lafayette · 丰富美食档案"].waitForExistence(timeout: 15))
        let monthly = web.buttons.matching(NSPredicate(format: "label CONTAINS %@", "本月回顾")).firstMatch
        scrollMemoryElement(monthly, in: app)
        monthly.tap()
        let calendar = web.buttons.matching(NSPredicate(format: "label CONTAINS %@", "翻一翻这个月")).firstMatch
        XCTAssertTrue(calendar.waitForExistence(timeout: 12))
        keepScreenshot(named: "V2 M01 Monthly Story", of: app)
        scrollMemoryElement(calendar, in: app)
        calendar.tap()
        XCTAssertTrue(web.staticTexts["本月用餐日历"].waitForExistence(timeout: 8))
        keepScreenshot(named: "V2 M03 Real Calendar", of: app)
        let day = web.switches.matching(NSPredicate(format: "label CONTAINS %@", "次用餐")).firstMatch
        XCTAssertTrue(day.waitForExistence(timeout: 8))
        scrollMemoryElement(day, in: app)
        day.tap()
        XCTAssertTrue(web.staticTexts["那一天的用餐"].waitForExistence(timeout: 8))
        web.buttons["返回上一页"].tap()
        web.buttons["返回上一页"].tap()
        let changed = web.buttons.matching(NSPredicate(format: "label CONTAINS %@", "和上个月有什么不同")).firstMatch
        scrollMemoryElement(changed, in: app)
        changed.tap()
        XCTAssertTrue(web.staticTexts["本月的变化"].waitForExistence(timeout: 8))
        keepScreenshot(named: "V2 M06 Matched Period Comparison", of: app)
    }

    @MainActor
    func testHybridMonthlyReviewOpensAsDedicatedReport() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--tastemap-hybrid-development", "-AppleInterfaceStyle", "Light"]
        app.launchEnvironment = ["TASTEMAP_VISUAL_QA_MODE": "rich"]
        app.launch()

        let webView = app.webViews.firstMatch
        XCTAssertTrue(webView.waitForExistence(timeout: 20))
        webView.buttons["我的"].tap()
        XCTAssertTrue(webView.staticTexts["Lafayette · 丰富美食档案"].waitForExistence(timeout: 12))

        let monthlyReview = webView.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "本月回顾")
        ).firstMatch
        scrollUntilVisible(monthlyReview, in: app)
        XCTAssertTrue(monthlyReview.waitForExistence(timeout: 8))
        monthlyReview.tap()

        XCTAssertTrue(webView.staticTexts["本月回顾"].firstMatch.waitForExistence(timeout: 8))
        XCTAssertFalse(webView.staticTexts["数据分析"].exists)
        for label in ["我的口味档案", "最佳饭搭子", "谁最会种草", "本月回顾", "年度回顾"] {
            XCTAssertFalse(webView.buttons[label].exists, "Dedicated Monthly Review must not expose an Analytics tab: \(label)")
        }
        XCTAssertTrue(webView.buttons["数据"].waitForExistence(timeout: 8))
        XCTAssertTrue(webView.buttons["画报"].exists)
        XCTAssertTrue(webView.buttons["分享数据"].exists)
        keepScreenshot(named: "Hybrid Monthly Review Dedicated Report", of: app)
    }

    @MainActor
    func testHybridAddFriendOpensPeopleSearchInsteadOfRestaurantDiscovery() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--tastemap-hybrid-development", "-AppleInterfaceStyle", "Light"]
        app.launchEnvironment = ["TASTEMAP_VISUAL_QA_MODE": "rich"]
        app.launch()

        let webView = app.webViews.firstMatch
        XCTAssertTrue(webView.waitForExistence(timeout: 20))
        webView.buttons["我的"].tap()
        XCTAssertTrue(webView.staticTexts["Lafayette · 丰富美食档案"].waitForExistence(timeout: 12))
        let addFriend = webView.buttons["添加好友"]
        XCTAssertTrue(addFriend.waitForExistence(timeout: 8))
        addFriend.tap()

        XCTAssertTrue(app.navigationBars["好友与关注"].waitForExistence(timeout: 8))
        XCTAssertTrue(segmentedOption("推荐", in: app).exists)
        XCTAssertTrue(app.textFields["social-search-field"].exists)
        XCTAssertTrue(app.staticTexts["推荐给你"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["TestUser08"].exists)
        let followRecommendation = app.buttons["关注 TestUser08"]
        XCTAssertTrue(followRecommendation.exists)
        XCTAssertEqual(followRecommendation.frame.width, 64, accuracy: 1)
        XCTAssertGreaterThanOrEqual(followRecommendation.frame.height, 44)
        // The button exposes one combined VoiceOver label, not a second text
        // element. Check title centering in the retained runtime screenshot.
        XCTAssertFalse(webView.buttons["为你推荐"].isHittable)
        keepScreenshot(named: "Compact Centered Follow Recommendations", of: app)

        let search = app.textFields["social-search-field"]
        search.tap()
        search.typeText("小周\n")
        let followSearch = app.buttons["关注 小周"]
        XCTAssertTrue(followSearch.waitForExistence(timeout: 12))
        XCTAssertEqual(followSearch.frame.width, 64, accuracy: 1)
        XCTAssertGreaterThanOrEqual(followSearch.frame.height, 44)
        keepScreenshot(named: "Compact Centered Follow Cached Search", of: app)
    }

    @MainActor
    func testHybridFollowingOpensPeopleListInsteadOfRestaurantDiscovery() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--tastemap-hybrid-development", "-AppleInterfaceStyle", "Light"]
        app.launchEnvironment = ["TASTEMAP_VISUAL_QA_MODE": "rich"]
        app.launch()

        let webView = app.webViews.firstMatch
        XCTAssertTrue(webView.waitForExistence(timeout: 20))
        webView.buttons["我的"].tap()
        XCTAssertTrue(webView.staticTexts["Lafayette · 丰富美食档案"].waitForExistence(timeout: 12))

        let following = webView.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "关注 ")
        ).firstMatch
        XCTAssertTrue(following.waitForExistence(timeout: 8))
        XCTAssertEqual(following.label, "关注 4")
        following.tap()

        XCTAssertTrue(app.navigationBars["好友与关注"].waitForExistence(timeout: 8))
        XCTAssertTrue(segmentedOption("关注", in: app).exists)
        XCTAssertTrue(segmentedOption("粉丝", in: app).exists)
        for followedUser in ["林夏", "陈一碗", "阿岚", "陆小满"] {
            XCTAssertTrue(
                app.staticTexts[followedUser].waitForExistence(timeout: 8),
                "Profile following list must contain Discovery following author \(followedUser)"
            )
        }
        segmentedOption("粉丝", in: app).tap()
        XCTAssertTrue(app.staticTexts["小周"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.staticTexts["阿岚"].exists)
        XCTAssertFalse(app.staticTexts["发现"].exists)
        XCTAssertFalse(webView.buttons["为你推荐"].isHittable)
        keepScreenshot(named: "Hybrid Following Native People List", of: app)
    }

    @MainActor
    func testCompactFollowSearchInNativeRollbackAndDarkHybrid() throws {
        for hybrid in [false, true] {
            let app = XCUIApplication()
            app.launchArguments = hybrid
                ? ["--tastemap-hybrid-development", "-AppleInterfaceStyle", "Dark"]
                : ["-AppleInterfaceStyle", "Light"]
            app.launchEnvironment = ["TASTEMAP_VISUAL_QA_MODE": "rich"]
            if !hybrid {
                // Scope this style check to the existing Native Profile entry;
                // map bootstrap/navigation has its own regression coverage.
                app.launchEnvironment["TASTEMAP_CORE_PARITY_INITIAL_TAB"] = "profile"
            }
            app.launch()
            if hybrid {
                XCTAssertTrue(app.buttons["我的"].waitForExistence(timeout: 20))
                app.buttons["我的"].tap()
                let addFriend = app.webViews.firstMatch.buttons["添加好友"]
                XCTAssertTrue(addFriend.waitForExistence(timeout: 12))
                addFriend.tap()
            } else {
                let entry = app.buttons["profile-social-entry"]
                XCTAssertTrue(entry.waitForExistence(timeout: 12))
                entry.tap()
            }
            XCTAssertTrue(app.navigationBars["好友与关注"].waitForExistence(timeout: 8))
            let search = app.textFields["social-search-field"]
            search.tap()
            search.typeText("小周\n")
            let follow = app.buttons["关注 小周"]
            XCTAssertTrue(follow.waitForExistence(timeout: 12))
            XCTAssertTrue(follow.isHittable)
            XCTAssertEqual(follow.frame.width, 64, accuracy: 1)
            XCTAssertGreaterThanOrEqual(follow.frame.height, 44)
            keepScreenshot(named: hybrid ? "Compact Follow Dark Hybrid Search" : "Compact Follow Native Rollback Search", of: app)
            app.terminate()
        }
    }

    @MainActor
    func testHybridVisitRatingSetsEveryTargetInOneInteraction() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--tastemap-hybrid-development", "-AppleInterfaceStyle", "Light"]
        app.launchEnvironment = ["TASTEMAP_VISUAL_QA_MODE": "rich"]
        app.launch()

        let webView = app.webViews.firstMatch
        XCTAssertTrue(webView.waitForExistence(timeout: 20))
        webView.buttons["我的"].tap()
        XCTAssertTrue(webView.staticTexts["Lafayette · 丰富美食档案"].waitForExistence(timeout: 12))

        let visited = webView.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "去过")
        ).firstMatch
        XCTAssertTrue(visited.waitForExistence(timeout: 8))
        visited.tap()
        let restaurant = webView.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "青岚寿司 1")
        ).firstMatch
        XCTAssertTrue(restaurant.waitForExistence(timeout: 8))
        restaurant.tap()

        let editVisit = webView.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "编辑第")
        ).firstMatch
        scrollUntilVisible(editVisit, in: app)
        XCTAssertTrue(editVisit.waitForExistence(timeout: 8))
        editVisit.tap()
        XCTAssertTrue(webView.staticTexts["编辑到访记录"].waitForExistence(timeout: 10))

        func setRating(_ rating: Double, summary: String) {
            let ratingLabel = rating.rounded() == rating
                ? String(Int(rating))
                : String(rating)
            let target = webView.descendants(matching: .any)["设置个人评价为 \(ratingLabel) 星"]
            scrollUntilVisible(target, in: app)
            XCTAssertTrue(target.waitForExistence(timeout: 5))
            target.tap()
            let updatedGroup = webView.descendants(matching: .any)["个人评价，\(ratingLabel) 星，共 5 星"]
            XCTAssertTrue(updatedGroup.waitForExistence(timeout: 3), "Expected one-tap rating state and summary: \(summary)")
            XCTAssertFalse(webView.staticTexts["未评分 · 可直接保存"].exists)
        }

        setRating(4, summary: "4 星 · 喜欢 · 8.0 分")
        setRating(3.5, summary: "3.5 星 · 喜欢 · 7.0 分")
        setRating(5, summary: "5 星 · 挚爱 · 10.0 分")
        setRating(2.5, summary: "2.5 星 · 不错 · 5.0 分")
        setRating(4.5, summary: "4.5 星 · 挚爱 · 9.0 分")
        keepScreenshot(named: "Hybrid Visit Rating Warm Amber", of: app)

        let clear = webView.buttons["清除评分"]
        XCTAssertTrue(clear.waitForExistence(timeout: 5))
        clear.tap()
        XCTAssertTrue(webView.staticTexts["未评分 · 可直接保存"].waitForExistence(timeout: 3))
        XCTAssertFalse(webView.buttons["清除评分"].exists)

        setRating(3, summary: "3 星 · 不错 · 6.0 分")
        XCTAssertTrue(webView.descendants(matching: .any)["个人评价，3 星，共 5 星"].waitForExistence(timeout: 3))
        keepScreenshot(named: "Hybrid Visit Rating Direct Set Final", of: app)
    }

    @MainActor
    func testHybridBackRemainsVisibleThroughoutLongSecondaryPages() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--tastemap-hybrid-development", "-AppleInterfaceStyle", "Light"]
        app.launchEnvironment = ["TASTEMAP_VISUAL_QA_MODE": "rich"]
        app.launch()
        let web = app.webViews.firstMatch
        XCTAssertTrue(web.waitForExistence(timeout: 20))
        web.buttons["地图"].tap()
        let listSwitch = web.buttons["切换到我的列表"]
        XCTAssertTrue(listSwitch.waitForExistence(timeout: 15))
        listSwitch.tap()
        XCTAssertTrue(web.staticTexts["去过的餐厅"].waitForExistence(timeout: 8))
        // Scope the real visible list row, not a similarly named footprint behind a modal.
        let restaurant = web.buttons.matching(NSPredicate(
            format: "label BEGINSWITH %@ AND label CONTAINS %@", "查看餐厅 ", "次到访"
        )).firstMatch
        XCTAssertTrue(restaurant.waitForExistence(timeout: 8))
        restaurant.tap()
        let back = web.buttons["返回上一页"]
        XCTAssertTrue(back.waitForExistence(timeout: 8))
        XCTAssertFalse(web.buttons["关闭餐厅卡片"].exists, "A full page has one back action, not a duplicate card close")
        XCTAssertTrue(web.staticTexts["用户实拍"].exists)
        XCTAssertTrue(web.staticTexts["我的到访概览"].exists)
        keepScreenshot(named: "Persistent Back Restaurant Top", of: app)
        func scrollAndCheck(_ name: String, swipes: Int) {
            for index in 0..<swipes {
                web.swipeUp()
                XCTAssertEqual(web.buttons.matching(identifier: "返回上一页").count, 1)
                XCTAssertTrue(back.isHittable, "\(name) back must be tappable at scroll \(index)")
                XCTAssertGreaterThanOrEqual(back.frame.minY, 59, "Back must clear the fixed QA device status bar")
                XCTAssertLessThan(back.frame.maxY, 140, "Back must stay at the top, not scroll with content")
                XCTAssertGreaterThanOrEqual(back.frame.width, 44)
                XCTAssertGreaterThanOrEqual(back.frame.height, 44)
                if index == 0 { keepScreenshot(named: "Persistent Back \(name) Middle", of: app) }
            }
            keepScreenshot(named: "Persistent Back \(name) Bottom", of: app)
        }
        scrollAndCheck("Restaurant", swipes: 5)
        // The visit history has its own scroller. Also move the outer page past it.
        let outerStart = web.coordinate(withNormalizedOffset: CGVector(dx: 0.99, dy: 0.82))
        let outerEnd = web.coordinate(withNormalizedOffset: CGVector(dx: 0.99, dy: 0.20))
        for _ in 0..<3 {
            outerStart.press(forDuration: 0.05, thenDragTo: outerEnd)
            XCTAssertTrue(back.isHittable)
            XCTAssertGreaterThanOrEqual(back.frame.minY, 59)
            XCTAssertLessThan(back.frame.maxY, 140)
        }
        keepScreenshot(named: "Persistent Back Restaurant Page End", of: app)
        let notes = web.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "也愿意为了招牌菜再来一次"))
        XCTAssertGreaterThan(notes.count, 0)
        if notes.count > 0 {
            let lastNote = notes.element(boundBy: notes.count - 1)
            XCTAssertLessThanOrEqual(lastNote.frame.maxY, web.buttons["地图"].frame.minY, "The final visit must clear the fixed bottom navigation")
        }
        back.tap()
        XCTAssertTrue(web.staticTexts["去过的餐厅"].waitForExistence(timeout: 8), "The visible arrow must return to the actual restaurant list")
        XCTAssertTrue(restaurant.isHittable)
        web.buttons["我的"].tap()
        web.buttons["设置"].tap()
        XCTAssertTrue(back.waitForExistence(timeout: 8))
        scrollAndCheck("Settings", swipes: 3)
        back.tap()
        XCTAssertTrue(web.staticTexts["Lafayette · 丰富美食档案"].waitForExistence(timeout: 8))
        XCTAssertFalse(web.buttons["编辑资料"].exists)
        let analytics = web.buttons.matching(NSPredicate(format: "label CONTAINS %@", "我的口味档案")).firstMatch
        scrollUntilVisible(analytics, in: app)
        analytics.tap()
        XCTAssertTrue(back.waitForExistence(timeout: 8))
        scrollAndCheck("Analytics", swipes: 4)
        back.tap()
        XCTAssertTrue(web.staticTexts["Lafayette · 丰富美食档案"].waitForExistence(timeout: 8))
        XCTAssertFalse(web.buttons["编辑资料"].exists)
    }

    @MainActor
    func testHybridFullPageDrillInsProvideBackNavigation() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--tastemap-hybrid-development", "-AppleInterfaceStyle", "Light"]
        app.launchEnvironment = [
            "TASTEMAP_VISUAL_QA_MODE": "rich",
            "TASTEMAP_CORE_PARITY_INITIAL_TAB": "profile",
        ]
        app.launch()

        let webView = app.webViews.firstMatch
        XCTAssertTrue(webView.waitForExistence(timeout: 20))
        let profileTab = webView.buttons["我的"]
        XCTAssertTrue(profileTab.waitForExistence(timeout: 8))
        profileTab.tap()
        XCTAssertTrue(webView.staticTexts["Lafayette · 丰富美食档案"].waitForExistence(timeout: 12))
        scrollToTop(in: app)

        let settings = webView.buttons["设置"]
        XCTAssertTrue(settings.waitForExistence(timeout: 8))
        XCTAssertTrue(settings.isHittable)
        settings.tap()
        let accountEntry = webView.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "账户与安全")
        ).firstMatch
        XCTAssertTrue(accountEntry.waitForExistence(timeout: 8))
        var back = webView.buttons["返回上一页"]
        XCTAssertTrue(back.waitForExistence(timeout: 8))
        XCTAssertLessThanOrEqual(back.frame.width, 52, "Back control must remain an icon-only 44-point action.")
        keepScreenshot(named: "Hybrid Settings Icon Back", of: app)

        let premium = webView.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "查看当前权益与订阅管理")
        ).firstMatch
        scrollUntilVisible(premium, in: app)
        XCTAssertTrue(premium.waitForExistence(timeout: 8))
        premium.tap()
        XCTAssertTrue(webView.staticTexts["已开通"].waitForExistence(timeout: 8))
        back = webView.buttons["返回上一页"]
        XCTAssertTrue(back.waitForExistence(timeout: 8))
        XCTAssertLessThanOrEqual(back.frame.width, 52)
        keepScreenshot(named: "Hybrid Premium Icon Back", of: app)
        back.tap()
        XCTAssertTrue(accountEntry.waitForExistence(timeout: 8))
        webView.buttons["返回上一页"].tap()
        XCTAssertTrue(webView.staticTexts["Lafayette · 丰富美食档案"].waitForExistence(timeout: 10))

        let analytics = webView.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "我的口味档案")
        ).firstMatch
        scrollUntilVisible(analytics, in: app)
        XCTAssertTrue(analytics.waitForExistence(timeout: 8))
        analytics.tap()
        XCTAssertTrue(webView.staticTexts["我的口味档案"].firstMatch.waitForExistence(timeout: 8))
        back = webView.buttons["返回上一页"]
        XCTAssertTrue(back.waitForExistence(timeout: 8))
        XCTAssertLessThanOrEqual(back.frame.width, 52)
        back.tap()
        XCTAssertTrue(webView.staticTexts["Lafayette · 丰富美食档案"].waitForExistence(timeout: 10))

        let lists = webView.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "查看全部")
        ).firstMatch
        scrollUntilVisible(lists, in: app)
        XCTAssertTrue(lists.waitForExistence(timeout: 8))
        lists.tap()
        XCTAssertTrue(webView.staticTexts["我的食单"].waitForExistence(timeout: 8))
        back = webView.buttons["返回上一页"]
        XCTAssertTrue(back.waitForExistence(timeout: 8))
        XCTAssertLessThanOrEqual(back.frame.width, 52)
        back.tap()
        XCTAssertTrue(webView.staticTexts["Lafayette · 丰富美食档案"].waitForExistence(timeout: 10))

        webView.buttons["地图"].tap()
        let addRestaurant = webView.buttons["添加餐厅"].firstMatch
        XCTAssertTrue(addRestaurant.waitForExistence(timeout: 8))
        addRestaurant.tap()
        XCTAssertTrue(webView.staticTexts["搜索餐厅"].waitForExistence(timeout: 8))
        back = webView.buttons["返回上一页"]
        XCTAssertTrue(back.waitForExistence(timeout: 8))
        XCTAssertLessThanOrEqual(back.frame.width, 52)
        keepScreenshot(named: "Hybrid Add Restaurant Icon Back", of: app)
        back.tap()
        XCTAssertTrue(webView.buttons["添加餐厅"].firstMatch.waitForExistence(timeout: 10))
    }

    @MainActor
    func testNativeGlobalProductNavigationContract() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleInterfaceStyle", "Light"]
        app.launchEnvironment = ["TASTEMAP_VISUAL_QA_MODE": "rich"]
        app.launch()

        let map = app.buttons["app-tab-map"]
        let discovery = app.buttons["app-tab-discover"]
        let profile = app.buttons["app-tab-profile"]
        XCTAssertTrue(map.waitForExistence(timeout: 15))
        XCTAssertTrue(discovery.exists)
        XCTAssertTrue(profile.exists)
        XCTAssertFalse(app.buttons["添加"].exists)
        XCTAssertEqual(app.buttons.matching(identifier: "addRestaurantButton").count, 1)

        discovery.tap()
        XCTAssertTrue(app.staticTexts["discovery-header"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["addRestaurantButton"].exists)

        profile.tap()
        XCTAssertTrue(app.descendants(matching: .any)["profile-identity-card"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["addRestaurantButton"].exists)

        map.tap()
        XCTAssertTrue(app.staticTexts["map-home-title"].waitForExistence(timeout: 8))
        XCTAssertEqual(app.buttons.matching(identifier: "addRestaurantButton").count, 1)
        XCTAssertTrue(app.buttons["addRestaurantButton"].isHittable)
    }

    @MainActor
    func testHybridGlobalProductNavigationContract() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--tastemap-hybrid-development", "-AppleInterfaceStyle", "Light"]
        app.launchEnvironment = ["TASTEMAP_VISUAL_QA_MODE": "rich"]
        app.launch()

        let webView = app.webViews.firstMatch
        XCTAssertTrue(webView.waitForExistence(timeout: 20))
        for label in ["地图", "发现", "我的"] {
            XCTAssertTrue(webView.buttons[label].waitForExistence(timeout: 8), "Missing exact bottom-navigation item: \(label)")
        }
        XCTAssertFalse(webView.buttons["添加"].exists, "Add Restaurant must never be a fourth bottom-navigation tab")

        webView.buttons["地图"].tap()
        let addEntries = webView.buttons.matching(NSPredicate(format: "label == %@", "添加餐厅"))
        XCTAssertEqual(addEntries.count, 1, "My Map must expose exactly one floating Add Restaurant primary entry")
        XCTAssertTrue(addEntries.firstMatch.isHittable)
    }

    @MainActor
    func testHybridAddRestaurantVisualAndInputFocusContract() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--tastemap-hybrid-development", "-AppleInterfaceStyle", "Light"]
        app.launchEnvironment = [
            "TASTEMAP_VISUAL_QA_MODE": "rich",
            "TASTEMAP_ADD_IMAGE_REUSE_UI_TEST": "1",
        ]
        app.launch()

        let webView = app.webViews.firstMatch
        XCTAssertTrue(webView.waitForExistence(timeout: 20))
        webView.buttons["地图"].tap()
        let add = webView.buttons["添加餐厅"].firstMatch
        XCTAssertTrue(add.waitForExistence(timeout: 12))
        add.tap()

        let query = webView.textFields["餐厅名称或地址"]
        let city = webView.textFields["城市"]
        XCTAssertTrue(query.waitForExistence(timeout: 10))
        XCTAssertTrue(city.waitForExistence(timeout: 10))
        XCTAssertTrue(webView.staticTexts["附近餐厅"].exists)
        let detectedCity = expectation(for: NSPredicate(format: "value == %@", "杭州"), evaluatedWith: city)
        wait(for: [detectedCity], timeout: 10)
        XCTAssertTrue(webView.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "青岚寿司 1 · 已有用户照片")
        ).firstMatch.waitForExistence(timeout: 10), "Rich QA Nearby must never open as an empty list")
        keepScreenshot(named: "Hybrid Add Restaurant Auto City", of: app)
        XCTAssertTrue(webView.buttons["从外部分享添加"].exists)
        XCTAssertTrue(webView.buttons["手动添加餐厅"].exists)

        let queryFrameBeforeFocus = query.frame
        query.tap()
        query.typeText("牛new")
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(query.frame.width, queryFrameBeforeFocus.width, accuracy: 1)

        let cityFrameBeforeFocus = city.frame
        city.tap()
        XCTAssertEqual(city.frame.width, cityFrameBeforeFocus.width, accuracy: 1)
        XCTAssertTrue(webView.buttons["搜索餐厅"].isHittable)

        webView.buttons["搜索餐厅"].tap()
        XCTAssertFalse(app.keyboards.firstMatch.waitForExistence(timeout: 3))
        let matchingSearchAndNearby = webView.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "牛New寿喜烧 · 全新 Apple 候选")
        )
        let filteredResults = expectation(for: NSPredicate(format: "count == 2"), evaluatedWith: matchingSearchAndNearby)
        wait(for: [filteredResults], timeout: 8)
        XCTAssertEqual(webView.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "青岚寿司 1 · 已有用户照片")
        ).count, 1, "Unrelated provider suggestions must remain only in Nearby, never leak into Search results")
        XCTAssertEqual(webView.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "春日泰味 4 · 已有公开缓存")
        ).count, 1, "Search must remove unrelated provider suggestions")
        scrollUntilVisible(query, in: app)
        keepScreenshot(named: "Hybrid Add Restaurant Search Relevance", of: app)
        let share = webView.buttons["从外部分享添加"]
        scrollUntilVisible(share, in: app)
        XCTAssertTrue(share.isHittable)
        let manual = webView.buttons["手动添加餐厅"]
        scrollUntilVisible(manual, in: app)
        XCTAssertTrue(manual.isHittable)
        keepScreenshot(named: "Hybrid Add Restaurant Final", of: app)
    }

    @MainActor
    func testHybridDiscoverySharedProductAndVisualContract() throws {
        let (app, webView) = launchHybridDiscoveryFooter()
        XCTAssertTrue(webView.staticTexts["发现"].waitForExistence(timeout: 12))
        XCTAssertTrue(webView.staticTexts["按照你的口味，找到更值得参考的人和下一家餐厅。"].waitForExistence(timeout: 12))
        XCTAssertFalse(webView.staticTexts["DISCOVER"].exists)

        let tabs = ["关注", "为你推荐", "同味之选", "最新", "趋势"]
        for label in tabs {
            XCTAssertTrue(webView.buttons[label].waitForExistence(timeout: 8), "Missing Discovery tab: \(label)")
        }
        XCTAssertTrue(webView.buttons["筛选"].waitForExistence(timeout: 8))
        XCTAssertTrue(webView.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "查看餐厅 ")
        ).firstMatch.waitForExistence(timeout: 8))
        XCTAssertTrue(webView.images.matching(
            NSPredicate(format: "label BEGINSWITH %@", "猜你会喜欢")
        ).firstMatch.waitForExistence(timeout: 8))
        XCTAssertFalse(webView.staticTexts["优先推荐"].exists)
        XCTAssertFalse(webView.staticTexts["推荐给你"].exists)
        XCTAssertFalse(webView.images.matching(
            NSPredicate(format: "label BEGINSWITH %@", "大家评分")
        ).firstMatch.exists)
        XCTAssertFalse(webView.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "查看推荐来源用户 ")
        ).firstMatch.exists, "For You must not turn a photo uploader into the recommender")
        let recommendationReason = webView.staticTexts["为什么适合你"]
        XCTAssertTrue(recommendationReason.waitForExistence(timeout: 8))
        scrollDiscoveryCardIntoView(in: app)
        for label in ["加入餐厅", "加入转盘"] {
            XCTAssertTrue(webView.descendants(matching: .any).matching(
                NSPredicate(format: "label BEGINSWITH %@", "\(label) ")
            ).firstMatch.waitForExistence(timeout: 8), "Missing Restaurant action: \(label)")
        }
        XCTAssertFalse(webView.descendants(matching: .any).matching(
            NSPredicate(format: "label BEGINSWITH %@", "食单 ")
        ).firstMatch.exists, "Discovery Card must not expose a List shortcut")
        XCTAssertTrue(webView.descendants(matching: .any).matching(
            NSPredicate(format: "label BEGINSWITH %@ OR label BEGINSWITH %@ OR label BEGINSWITH %@", "收藏餐厅 ", "取消收藏餐厅 ", "已收藏餐厅 ")
        ).firstMatch.waitForExistence(timeout: 8), "Missing WantToGo state action")

        webView.buttons["同味之选"].tap()
        XCTAssertTrue(webView.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "查看同味来源用户 ")
        ).firstMatch.waitForExistence(timeout: 8), "Same Taste keeps its real activity author")

        webView.buttons["关注"].tap()
        let followingLike = webView.switches.matching(
            NSPredicate(format: "label BEGINSWITH %@ OR label BEGINSWITH %@", "点赞 ", "取消点赞 ")
        ).firstMatch
        XCTAssertTrue(followingLike.waitForExistence(timeout: 8))
        scrollUntilVisible(followingLike, in: app)
        XCTAssertTrue(webView.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "评论 ")).firstMatch.waitForExistence(timeout: 8))
        XCTAssertTrue(webView.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "分享动态 ")).firstMatch.waitForExistence(timeout: 8))

        for label in ["同味之选", "最新", "趋势", "为你推荐"] {
            webView.buttons[label].tap()
            XCTAssertTrue(webView.buttons[label].isSelected)
        }
        let recordAction = webView.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "加入餐厅 ")).firstMatch
        scrollDiscoveryCardIntoView(in: app)
        XCTAssertTrue(recordAction.waitForExistence(timeout: 8))
        XCTAssertTrue(recordAction.isHittable)
        keepScreenshot(named: "Batch 01 Discovery Full Card", of: app)
    }

    @MainActor
    func testHybridDiscoveryLikeInteractionEvidence() throws {
        let (app, webView) = launchHybridDiscoveryFooter()
        let like = visibleDiscoveryAction("点赞", in: webView, app: app)
        let likeFrame = like.frame
        tapVisibleFrame(of: like, in: app)
        let unlike = visibleDiscoveryAction("取消点赞", in: webView, app: app, near: likeFrame)
        waitUntilEnabled(unlike)
        keepScreenScreenshot(named: "Batch 01 Discovery Like After")
        tapVisibleFrame(of: unlike, in: app)
        let restoredLike = visibleDiscoveryAction("点赞", in: webView, app: app, near: likeFrame)
        waitUntilEnabled(restoredLike)
        XCTAssertTrue(webView.buttons["为你推荐"].isSelected)
        print("DISCOVERY_INTERACTION_EVIDENCE like=optimistic-authoritative-toggle-pass")
    }

    @MainActor
    func testHybridDiscoveryActivityCardsDoNotShowOverflow() throws {
        let (app, webView) = launchHybridDiscoveryFooter()
        webView.buttons["关注"].tap()
        let overflow = webView.descendants(matching: .any).matching(
            NSPredicate(format: "label == %@", "动态操作：举报或屏蔽")
        ).firstMatch
        XCTAssertFalse(overflow.waitForExistence(timeout: 2))
        let tenPointRating = webView.descendants(matching: .any).matching(
            NSPredicate(format: "label == %@", "本次到访评分 9.0")
        ).firstMatch
        XCTAssertTrue(tenPointRating.waitForExistence(timeout: 8))
        XCTAssertFalse(webView.descendants(matching: .any).matching(
            NSPredicate(format: "label == %@", "本次到访评分 4.5")
        ).firstMatch.exists)
        XCTAssertFalse(app.navigationBars["好友与关注"].exists)
        keepScreenScreenshot(named: "Hybrid Discovery Activity Without Overflow")
    }

    @MainActor
    func testHybridSimilarTasteCommentsLoadAndRemainVisitScoped() throws {
        let (app, webView) = launchHybridDiscoveryFooter()
        webView.buttons["同味之选"].tap()
        tapVisibleFrame(of: visibleDiscoveryAction("评论", in: webView, app: app), in: app)
        let input = webView.textFields["写下评论"]
        XCTAssertTrue(input.waitForExistence(timeout: 8))
        XCTAssertTrue(webView.staticTexts["招牌菜很好吃，下次还会再来。"].waitForExistence(timeout: 8))
        XCTAssertTrue(webView.staticTexts["环境舒服，适合和朋友一起吃。"].exists)
        XCTAssertFalse(webView.staticTexts["评论暂时无法加载。"].exists)
        keepScreenScreenshot(named: "Same Taste Existing Comments")
        input.tap()
        input.typeText("同味评论模拟器回归")
        webView.buttons["发送评论"].tap()
        let added = webView.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "同味评论模拟器回归")).firstMatch
        XCTAssertTrue(added.waitForExistence(timeout: 8))
        webView.buttons["关闭"].tap()
        XCTAssertTrue(webView.buttons["同味之选"].isSelected)
        tapVisibleFrame(of: visibleDiscoveryAction("评论", in: webView, app: app), in: app)
        XCTAssertTrue(added.waitForExistence(timeout: 8))
        keepScreenScreenshot(named: "Same Taste Comment Reopen")
        webView.buttons["关闭"].tap()
        for tab in ["关注", "最新"] {
            webView.buttons[tab].tap()
            tapVisibleFrame(of: visibleDiscoveryAction("评论", in: webView, app: app), in: app)
            XCTAssertTrue(webView.staticTexts["招牌菜很好吃，下次还会再来。"].waitForExistence(timeout: 8))
            XCTAssertFalse(added.exists, "A Same Taste comment must not leak into a different Visit")
            webView.buttons["关闭"].tap()
            XCTAssertTrue(webView.buttons[tab].isSelected)
        }
    }

    @MainActor
    func testHybridDiscoveryCommentInteractionEvidence() throws {
        let (app, webView) = launchHybridDiscoveryFooter()
        tapVisibleFrame(of: visibleDiscoveryAction("评论", in: webView, app: app), in: app)
        let input = webView.textFields["写下评论"]
        XCTAssertTrue(input.waitForExistence(timeout: 8))
        XCTAssertTrue(webView.staticTexts["招牌菜很好吃，下次还会再来。"].waitForExistence(timeout: 8))
        XCTAssertFalse(webView.staticTexts["还没有评论，来说说你的想法。"].exists)
        input.tap()
        input.typeText("真机交互验收评论")
        let send = webView.buttons["发送评论"]
        XCTAssertTrue(send.isHittable)
        send.tap()
        let submittedComment = webView.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "真机交互验收评论")
        ).firstMatch
        XCTAssertTrue(submittedComment.waitForExistence(timeout: 8))
        XCTAssertTrue(webView.navigationBars["评论"].exists || webView.staticTexts["评论"].exists)
        keepScreenScreenshot(named: "Batch 01 Discovery Comment Target")
        webView.buttons["关闭"].tap()
        XCTAssertTrue(webView.buttons["为你推荐"].isSelected)
        _ = visibleDiscoveryAction("评论", in: webView, app: app)
        print("DISCOVERY_INTERACTION_EVIDENCE comment=visit-targeted-create-and-return-pass")
    }

    @MainActor
    func testHybridDiscoveryRecordVisitInteractionEvidence() throws {
        let (app, webView) = launchHybridDiscoveryFooter()
        tapVisibleFrame(of: visibleDiscoveryAction("记录", in: webView, app: app), in: app)
        let save = webView.buttons["保存到我的地图"]
        XCTAssertTrue(save.waitForExistence(timeout: 8))
        keepScreenScreenshot(named: "Batch 01 Discovery Visit Editor")
        save.tap()
        XCTAssertTrue(webView.buttons["为你推荐"].waitForExistence(timeout: 12))
        XCTAssertTrue(webView.buttons["为你推荐"].isSelected)
        _ = visibleDiscoveryAction("记录", in: webView, app: app)
        print("DISCOVERY_INTERACTION_EVIDENCE record-visit=hybrid-editor-save-refresh-return-pass")
    }

    @MainActor
    func testHybridDiscoveryWantToGoInteractionEvidence() throws {
        let (app, webView) = launchHybridDiscoveryFooter()
        let wantToGo = visibleDiscoveryAction("想吃", in: webView, app: app)
        let wantFrame = wantToGo.frame
        tapVisibleFrame(of: wantToGo, in: app)
        let remove = visibleDiscoveryAction("移出想吃", in: webView, app: app, near: wantFrame)
        waitUntilEnabled(remove)
        keepScreenScreenshot(named: "Batch 01 Discovery WantToGo After Add")
        tapVisibleFrame(of: remove, in: app)
        let restoredWant = visibleDiscoveryAction("想吃", in: webView, app: app, near: wantFrame)
        waitUntilEnabled(restoredWant)
        XCTAssertTrue(webView.buttons["为你推荐"].isSelected)
        print("DISCOVERY_INTERACTION_EVIDENCE want-to-go=authoritative-add-remove-pass")
    }

    @MainActor
    func testHybridDiscoveryRouletteInteractionEvidence() throws {
        let (app, webView) = launchHybridDiscoveryFooter()
        let roulette = visibleDiscoveryAction("轮盘", in: webView, app: app)
        tapVisibleFrame(of: roulette, in: app)
        XCTAssertTrue(webView.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "随机选一家")
        ).firstMatch.waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["返回"].exists, "Hybrid-owned Roulette must not be sent to openNative")
        keepScreenScreenshot(named: "Batch 01 Discovery Roulette Route")
        webView.buttons["关闭"].tap()
        XCTAssertTrue(webView.buttons["为你推荐"].waitForExistence(timeout: 8))
        XCTAssertTrue(webView.buttons["为你推荐"].isSelected)
        _ = visibleDiscoveryAction("轮盘", in: webView, app: app)
        print("DISCOVERY_INTERACTION_EVIDENCE roulette=hybrid-route-candidate-return-pass")
    }

    @MainActor
    func testHybridRouletteCustomCandidateInteractionEvidence() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--tastemap-hybrid-development", "-AppleInterfaceStyle", "Light"]
        app.launchEnvironment = ["TASTEMAP_VISUAL_QA_MODE": "rich"]
        app.launch()

        let webView = app.webViews.firstMatch
        XCTAssertTrue(webView.waitForExistence(timeout: 20))
        webView.buttons["我的"].tap()
        XCTAssertTrue(webView.staticTexts["Lafayette · 丰富美食档案"].waitForExistence(timeout: 12))
        let roulette = webView.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "今天吃什么")
        ).firstMatch
        XCTAssertTrue(roulette.waitForExistence(timeout: 8))
        roulette.tap()

        let manage = webView.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "管理候选餐厅")
        ).firstMatch
        XCTAssertTrue(manage.waitForExistence(timeout: 8))
        manage.tap()
        let customNameField = webView.textFields["自定义餐厅名称"]
        XCTAssertTrue(customNameField.waitForExistence(timeout: 8))
        XCTAssertTrue(customNameField.isHittable, "管理入口应把自定义名称输入框带入当前可操作区域")
        customNameField.tap()
        customNameField.typeText("Lafayette 夜宵自选")
        let add = webView.buttons["添加自定义餐厅到候选"]
        XCTAssertTrue(add.isEnabled)
        add.tap()

        XCTAssertTrue(webView.buttons["移除 Lafayette 夜宵自选"].waitForExistence(timeout: 8))
        XCTAssertTrue(webView.staticTexts["已将“Lafayette 夜宵自选”加入候选餐厅。"].exists)
        let candidateCount = webView.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS %@", "6 / 10")
        ).firstMatch
        XCTAssertTrue(candidateCount.waitForExistence(timeout: 4))
        keepScreenshot(named: "Hybrid Roulette Custom Candidate", of: app)
    }

    @MainActor
    func testHybridRouletteUsesRealSegmentsAndRestoresWinnerAfterDetail() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--tastemap-hybrid-development", "-AppleInterfaceStyle", "Light"]
        app.launchEnvironment = ["TASTEMAP_VISUAL_QA_MODE": "rich"]
        app.launch()

        let webView = app.webViews.firstMatch
        XCTAssertTrue(webView.waitForExistence(timeout: 20))
        webView.buttons["我的"].tap()
        XCTAssertTrue(webView.staticTexts["Lafayette · 丰富美食档案"].waitForExistence(timeout: 12))
        let roulette = webView.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "今天吃什么")
        ).firstMatch
        XCTAssertTrue(roulette.waitForExistence(timeout: 8))
        roulette.tap()

        let manage = webView.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "管理候选餐厅")
        ).firstMatch
        XCTAssertTrue(manage.waitForExistence(timeout: 8))
        manage.tap()

        for _ in 0..<3 {
            let addCandidate = webView.descendants(matching: .any).matching(
                NSPredicate(format: "label BEGINSWITH %@", "加入候选餐厅 ")
            ).firstMatch
            XCTAssertTrue(addCandidate.waitForExistence(timeout: 8))
            scrollUntilVisible(addCandidate, in: app)
            XCTAssertTrue(addCandidate.isHittable)
            addCandidate.tap()
        }

        let threeCandidates = webView.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS %@", "3 / 10")
        ).firstMatch
        XCTAssertTrue(threeCandidates.waitForExistence(timeout: 8))
        scrollToTop(in: app)
        let threeSegmentWheel = webView.descendants(matching: .any).matching(
            NSPredicate(format: "label BEGINSWITH %@", "当前轮盘有 3 个扇区")
        ).firstMatch
        XCTAssertTrue(threeSegmentWheel.waitForExistence(timeout: 8))
        XCTAssertFalse(webView.buttons["添加更多餐厅"].exists)

        let spin = webView.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "开始")
        ).firstMatch
        scrollUntilVisible(spin, in: app)
        XCTAssertTrue(spin.isHittable)
        spin.tap()

        let winnerAvatar = webView.images.matching(
            NSPredicate(format: "label ENDSWITH %@", "餐厅头像")
        ).firstMatch
        XCTAssertTrue(winnerAvatar.waitForExistence(timeout: 8))
        let winnerAvatarLabel = winnerAvatar.label
        let detail = webView.buttons["查看详情"]
        XCTAssertTrue(detail.waitForExistence(timeout: 3))
        detail.tap()

        let back = webView.buttons["返回上一页"]
        XCTAssertTrue(back.waitForExistence(timeout: 8))
        back.tap()

        XCTAssertTrue(webView.images.matching(
            NSPredicate(format: "label == %@", winnerAvatarLabel)
        ).firstMatch.waitForExistence(timeout: 8))
        XCTAssertTrue(webView.descendants(matching: .any).matching(
            NSPredicate(format: "label BEGINSWITH %@", "当前轮盘有 3 个扇区")
        ).firstMatch.exists)
        XCTAssertTrue(webView.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "再抽一次")
        ).firstMatch.exists)
        XCTAssertFalse(webView.buttons["添加更多餐厅"].exists)
        keepScreenshot(named: "Hybrid Roulette Restored Winner", of: app)
    }

    @MainActor
    func testHybridProfileListPreviewMatchesAllListsSnapshot() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--tastemap-hybrid-development", "-AppleInterfaceStyle", "Light"]
        app.launchEnvironment = ["TASTEMAP_VISUAL_QA_MODE": "rich"]
        app.launch()

        let webView = app.webViews.firstMatch
        XCTAssertTrue(webView.waitForExistence(timeout: 20))
        webView.buttons["我的"].tap()
        XCTAssertTrue(webView.staticTexts["Lafayette · 丰富美食档案"].waitForExistence(timeout: 12))

        let firstPreview = webView.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "查看食单 杭州私藏餐厅")
        ).firstMatch
        let secondPreview = webView.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "查看食单 周末想吃")
        ).firstMatch
        XCTAssertTrue(firstPreview.waitForExistence(timeout: 8))
        XCTAssertTrue(secondPreview.exists)
        XCTAssertFalse(webView.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "查看食单 年度 TOP 10")
        ).firstMatch.exists)
        XCTAssertTrue(webView.buttons["查看全部 5 份食单"].exists)
        keepScreenshot(named: "Hybrid Profile Native List Preview", of: app)

        webView.buttons["查看全部 5 份食单"].tap()
        Thread.sleep(forTimeInterval: 1)
        keepScreenshot(named: "Hybrid All Native Lists", of: app)

        app.terminate()
        app.launch()
        let detailWebView = app.webViews.firstMatch
        XCTAssertTrue(detailWebView.waitForExistence(timeout: 20))
        detailWebView.buttons["我的"].tap()
        let detailPreview = detailWebView.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "查看食单 杭州私藏餐厅")
        ).firstMatch
        XCTAssertTrue(detailPreview.waitForExistence(timeout: 8))
        detailPreview.tap()
        XCTAssertTrue(detailWebView.buttons["← 返回食单"].waitForExistence(timeout: 8))
        XCTAssertTrue(detailWebView.staticTexts["杭州私藏餐厅"].exists)
        detailWebView.buttons["← 返回食单"].tap()
        Thread.sleep(forTimeInterval: 1)
        keepScreenshot(named: "Hybrid Profile Restored After List Detail", of: app)
    }

    @MainActor
    func testHybridProfileTasteFootprintCombinesVisitsAndWantToGoChronologically() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--tastemap-hybrid-development", "-AppleInterfaceStyle", "Light"]
        app.launchEnvironment = ["TASTEMAP_VISUAL_QA_MODE": "rich"]
        app.launch()

        let webView = app.webViews.firstMatch
        XCTAssertTrue(webView.waitForExistence(timeout: 20))
        webView.buttons["我的"].tap()
        XCTAssertTrue(webView.staticTexts["Lafayette · 丰富美食档案"].waitForExistence(timeout: 12))

        let preview = webView.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "查看全部味觉足迹，共 ")
        ).firstMatch
        scrollUntilVisible(preview, in: app)
        XCTAssertTrue(preview.waitForExistence(timeout: 8))
        XCTAssertTrue(preview.isHittable)
        XCTAssertTrue(preview.label.contains("记录去过"))
        XCTAssertTrue(preview.label.contains("加入想去"))
        keepScreenshot(named: "Hybrid Profile Taste Footprint Preview", of: app)

        preview.tap()
        XCTAssertTrue(webView.staticTexts["味觉足迹"].waitForExistence(timeout: 8))
        let tenPointRating = webView.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS %@", "8.0 分")
        ).firstMatch
        XCTAssertTrue(tenPointRating.waitForExistence(timeout: 8), "旧存储的 4.0 星必须按 10 分制显示为 8.0 分")

        let firstVisit = webView.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "记录去过")
        ).firstMatch
        let firstWant = webView.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "加入想去")
        ).firstMatch
        XCTAssertTrue(firstVisit.exists)
        XCTAssertTrue(firstWant.exists)
        XCTAssertLessThan(firstVisit.frame.minY, firstWant.frame.minY, "较新的实际到访必须排在较早的想去收藏之前")
        keepScreenshot(named: "Hybrid Profile Taste Footprint Timeline", of: app)
    }

    @MainActor
    func testHybridDiscoveryShareInteractionEvidence() throws {
        let (app, webView) = launchHybridDiscoveryFooter()
        let share = visibleDiscoveryAction("分享动态", in: webView, app: app)
        tapVisibleFrame(of: share, in: app)
        Thread.sleep(forTimeInterval: 2)
        keepScreenScreenshot(named: "Batch 01 Discovery Share Handoff")
        let systemSheet = app.sheets.firstMatch
        XCTAssertTrue(systemSheet.exists || app.otherElements["ActivityListView"].exists)
        if systemSheet.exists {
            systemSheet.swipeDown()
        } else if app.buttons["关闭"].exists {
            app.buttons["关闭"].tap()
        }
        XCTAssertTrue(webView.buttons["为你推荐"].waitForExistence(timeout: 8))
        XCTAssertTrue(webView.buttons["为你推荐"].isSelected)
        print("DISCOVERY_INTERACTION_EVIDENCE share=system-share-handoff-return-pass state=\(app.state.rawValue)")
    }

    @MainActor
    func testHybridTrendingOmitsTrendTagAndCommunityScoreButPreservesContent() throws {
        let (app, webView) = launchHybridDiscoveryFooter()
        webView.buttons["趋势"].tap()
        let restaurant = webView.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "查看餐厅 ")).firstMatch
        XCTAssertTrue(restaurant.waitForExistence(timeout: 8))
        XCTAssertFalse(webView.staticTexts["近期趋势"].exists)
        XCTAssertFalse(webView.descendants(matching: .any).matching(
            NSPredicate(format: "label BEGINSWITH %@", "大家评分")
        ).firstMatch.exists)
        XCTAssertTrue(webView.buttons.matching(
            NSPredicate(format: "label ENDSWITH %@", " 餐厅图片")
        ).firstMatch.exists)
        XCTAssertTrue(webView.buttons["查看 2 条完整推荐理由"].firstMatch.exists)
        for prefix in ["分享餐厅 ", "加入餐厅 ", "收藏餐厅 ", "加入转盘 "] {
            XCTAssertTrue(webView.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", prefix)).firstMatch.exists)
        }
        keepScreenshot(named: "Trending Without Header Tag Or Community Score", of: app)
        webView.buttons["为你推荐"].tap()
        XCTAssertTrue(webView.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "口味匹配度 ")).firstMatch.waitForExistence(timeout: 8))
    }

    @MainActor
    func testHybridRemainingBatchScreenshotAtlas() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--tastemap-hybrid-development", "-AppleInterfaceStyle", "Light"]
        app.launchEnvironment = ["TASTEMAP_VISUAL_QA_MODE": "rich"]
        app.launch()

        let webView = app.webViews.firstMatch
        XCTAssertTrue(webView.waitForExistence(timeout: 20))
        webView.buttons["发现"].tap()
        let discoveryTabs = [
            ("关注", "Batch 01 Discovery Following"),
            ("为你推荐", "Batch 01 Discovery For You"),
            ("同味之选", "Batch 01 Discovery Same Taste"),
            ("最新", "Batch 01 Discovery Latest"),
            ("趋势", "Batch 01 Discovery Trending"),
        ]
        for (label, screenshotName) in discoveryTabs {
            let button = webView.buttons[label]
            XCTAssertTrue(button.waitForExistence(timeout: 8))
            button.tap()
            keepScreenshot(named: screenshotName, of: app)
        }

        webView.buttons["地图"].tap()
        webView.buttons["添加餐厅"].firstMatch.tap()
        keepScreenshot(named: "Batch 01 Add Search", of: app)
        let search = webView.textFields["餐厅名称或地址"]
        XCTAssertTrue(search.waitForExistence(timeout: 8))
        search.tap()
        search.typeText("青岚")
        let submitSearch = webView.buttons["搜索餐厅"]
        XCTAssertTrue(submitSearch.waitForExistence(timeout: 8))
        submitSearch.tap()
        XCTAssertTrue(webView.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "青岚寿司")
        ).firstMatch.waitForExistence(timeout: 8))
        keepScreenshot(named: "Batch 01 Add Search Results", of: app)
        XCTAssertTrue(webView.staticTexts["附近餐厅"].waitForExistence(timeout: 8))
        keepScreenshot(named: "Batch 01 Add Nearby", of: app)
        let manual = webView.buttons["手动添加餐厅"]
        scrollUntilVisible(manual, in: app)
        XCTAssertTrue(manual.waitForExistence(timeout: 8))
        keepScreenshot(named: "Batch 01 Add Manual", of: app)
        let share = webView.buttons["从外部分享添加"]
        scrollUntilVisible(share, in: app)
        XCTAssertTrue(share.waitForExistence(timeout: 8))
        keepScreenshot(named: "Batch 01 Add Share", of: app)

        webView.buttons["我的"].tap()
        XCTAssertTrue(webView.staticTexts["Lafayette · 丰富美食档案"].waitForExistence(timeout: 12))
        let allLists = webView.buttons["查看全部食单"].firstMatch
        scrollUntilVisible(allLists, in: app)
        allLists.tap()
        keepScreenshot(named: "Batch 01 Lists Mine", of: app)
        let publicLists = webView.descendants(matching: .any)["公开食单"]
        XCTAssertTrue(publicLists.waitForExistence(timeout: 8))
        publicLists.tap()
        keepScreenshot(named: "Batch 01 Lists Public", of: app)
        let publicList = webView.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "朋友来杭带吃")
        ).firstMatch
        XCTAssertTrue(publicList.waitForExistence(timeout: 8))
        publicList.tap()
        keepScreenshot(named: "Batch 01 Public List Detail", of: app)

        webView.buttons["我的"].tap()
        let roulette = webView.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "今天吃什么")
        ).firstMatch
        XCTAssertTrue(roulette.waitForExistence(timeout: 8))
        roulette.tap()
        keepScreenshot(named: "Batch 01 Roulette Wheel", of: app)
        let manage = webView.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "管理候选餐厅")
        ).firstMatch
        XCTAssertTrue(manage.waitForExistence(timeout: 8))
        manage.tap()
        keepScreenshot(named: "Batch 01 Roulette Management", of: app)
        scrollToTop(in: app)
        let spin = webView.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "开始")
        ).firstMatch
        scrollUntilVisible(spin, in: app)
        XCTAssertTrue(spin.waitForExistence(timeout: 8))
        spin.tap()
        let spinAgain = webView.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "再抽一次")
        ).firstMatch
        XCTAssertTrue(spinAgain.waitForExistence(timeout: 8))
        keepScreenshot(named: "Batch 01 Roulette Result", of: app)
        spinAgain.tap()
        webView.buttons["关闭"].tap()

        XCTAssertTrue(webView.staticTexts["Lafayette · 丰富美食档案"].waitForExistence(timeout: 12))
        let analyticsReports = [
            ("我的口味档案", "taste-profile"),
            ("最佳饭搭子", "best-companion"),
            ("谁最会种草", "recommendation-source"),
            ("本月回顾", "monthly-review"),
            ("年度回顾", "annual-review"),
        ]
        for (label, slug) in analyticsReports {
            webView.buttons["我的"].tap()
            let entry = webView.buttons.matching(
                NSPredicate(format: "label CONTAINS %@", label)
            ).firstMatch
            scrollUntilVisible(entry, in: app)
            XCTAssertTrue(entry.waitForExistence(timeout: 8))
            entry.tap()
            XCTAssertTrue(webView.staticTexts[label].firstMatch.waitForExistence(timeout: 8))
            XCTAssertFalse(webView.staticTexts["数据分析"].exists)
            keepScreenshot(named: "Batch 01 Analytics \(slug)", of: app)
            webView.buttons["画报"].tap()
            XCTAssertTrue(webView.buttons["分享这张画报"].waitForExistence(timeout: 8))
            keepScreenshot(named: "Batch 01 Poster \(slug)", of: app)
            webView.buttons["数据"].tap()
        }

        webView.buttons["我的"].tap()
        XCTAssertTrue(webView.staticTexts["Lafayette · 丰富美食档案"].waitForExistence(timeout: 12))
        scrollToTop(in: app)
        let settings = webView.buttons["设置"]
        XCTAssertTrue(settings.waitForExistence(timeout: 8))
        settings.tap()
        keepScreenshot(named: "Batch 01 Settings Main", of: app)
        let premium = webView.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "查看当前权益与订阅管理")
        ).firstMatch
        scrollUntilVisible(premium, in: app)
        XCTAssertTrue(premium.waitForExistence(timeout: 8))
        premium.tap()
        XCTAssertTrue(webView.staticTexts["已开通"].waitForExistence(timeout: 8))
        keepScreenshot(named: "Batch 01 Premium Active", of: app)
    }

    @MainActor
    func testHybridRemainingBatchTenMinuteNavigationSoak() throws {
        guard ProcessInfo.processInfo.environment["TASTEMAP_HYBRID_SOAK"] == "1" else {
            throw XCTSkip("10-minute Hybrid soak is opt-in; run with TASTEMAP_HYBRID_SOAK=1.")
        }
        let app = XCUIApplication()
        app.launchArguments = ["--tastemap-hybrid-development", "-AppleInterfaceStyle", "Light"]
        app.launchEnvironment = ["TASTEMAP_VISUAL_QA_MODE": "rich"]
        app.launch()

        let webView = app.webViews.firstMatch
        XCTAssertTrue(webView.waitForExistence(timeout: 20))
        for _ in 0..<20 {
            for label in ["地图", "发现", "我的"] {
                let route = webView.buttons[label].firstMatch
                XCTAssertTrue(route.waitForExistence(timeout: 8))
                route.tap()
            }
        }

        webView.buttons["发现"].tap()
        let restaurant = webView.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "查看餐厅 ")
        ).firstMatch
        XCTAssertTrue(restaurant.waitForExistence(timeout: 8))
        restaurant.tap()
        XCTAssertTrue(webView.buttons["返回上一页"].waitForExistence(timeout: 8))
        webView.buttons["返回上一页"].tap()

        webView.buttons["我的"].tap()
        let listsEntry = webView.buttons["查看全部食单"].firstMatch
        scrollUntilVisible(listsEntry, in: app)
        XCTAssertTrue(listsEntry.waitForExistence(timeout: 8))
        listsEntry.tap()
        XCTAssertTrue(webView.descendants(matching: .any)["公开食单"].waitForExistence(timeout: 8))
        webView.buttons["我的"].tap()
        let analyticsEntry = webView.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "最佳饭搭子")
        ).firstMatch
        scrollUntilVisible(analyticsEntry, in: app)
        XCTAssertTrue(analyticsEntry.waitForExistence(timeout: 8))
        analyticsEntry.tap()
        XCTAssertTrue(webView.staticTexts["最佳饭搭子"].firstMatch.waitForExistence(timeout: 8))
        XCTAssertFalse(webView.buttons["年度回顾"].exists)

        webView.buttons["我的"].tap()
        scrollToTop(in: app)
        let roulette = webView.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "今天吃什么")
        ).firstMatch
        XCTAssertTrue(roulette.waitForExistence(timeout: 8))
        roulette.tap()
        let spin = webView.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "开始")
        ).firstMatch
        XCTAssertTrue(spin.waitForExistence(timeout: 8))
        webView.buttons["关闭"].tap()

        webView.buttons["我的"].tap()
        scrollToTop(in: app)
        let settings = webView.buttons["设置"]
        XCTAssertTrue(settings.waitForExistence(timeout: 8))
        settings.tap()
        XCTAssertTrue(webView.staticTexts["设置"].waitForExistence(timeout: 8))

        webView.buttons["发现"].tap()
        webView.buttons["为你推荐"].tap()
        print("TASTEMAP_HYBRID_SOAK_SETTLED")
        Thread.sleep(forTimeInterval: 600)
        XCTAssertTrue(webView.exists)
        XCTAssertTrue(webView.buttons["发现"].exists)
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
