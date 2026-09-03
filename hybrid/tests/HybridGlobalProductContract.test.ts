import { existsSync, readFileSync } from 'node:fs'
import { describe, expect, it } from 'vitest'
import {
  HYBRID_ADD_RESTAURANT_ENTRY,
  HYBRID_RESTAURANT_ACQUISITION_CONTRACT,
  HYBRID_BOTTOM_NAVIGATION,
  HYBRID_DISCOVERY_PRIMARY_TABS,
  HYBRID_ANALYTICS_MODES,
  HYBRID_LIST_SCOPES,
  HYBRID_MAP_PRIMARY_SCOPES,
  HYBRID_NATIVE_CAPABILITY_HANDOFFS,
  HYBRID_PROFILE_OWNER_MODULES,
  HYBRID_RESTAURANT_DETAIL_SECTION_ORDER,
  HYBRID_SETTINGS_SECTIONS,
  HYBRID_VISIT_HISTORY_EDIT_CONTRACT,
} from '../../src/hybrid/app/HybridProductContracts'
import { HYBRID_ROUTE_REGISTRY } from '../../src/hybrid/routes/HybridRouteRegistry'

const source = (name: string) => readFileSync(new URL(name, import.meta.url), 'utf8')

describe('Hybrid global Product Contract', () => {
  it('keeps route ownership independent from the exact three-item bottom navigation', () => {
    expect(HYBRID_ROUTE_REGISTRY.add).toBe('HYBRID_INTEGRATED')
    expect(HYBRID_BOTTOM_NAVIGATION).toEqual([
      { surface: 'map', label: '地图' },
      { surface: 'discovery', label: '发现' },
      { surface: 'profile', label: '我的' },
    ])
    expect(HYBRID_BOTTOM_NAVIGATION).toHaveLength(3)
    expect(HYBRID_BOTTOM_NAVIGATION.map((item) => item.label)).not.toContain('添加')
  })

  it('fills the mobile bottom edge and keeps the safe area inside the navigation surface', () => {
    const hybridCSS = source('../../src/hybrid/app/hybridShell.css')
    const browserCSS = source('../../src/styles/global.css')
    expect(hybridCSS).toMatch(/\.tm-hybrid-bottom-nav \{[^}]*left:\s*0;[^}]*right:\s*0;[^}]*bottom:\s*0;[^}]*height:\s*calc\(56px \+ var\(--tm-safe-bottom\)\);/)
    expect(hybridCSS).toMatch(/\.tm-hybrid-bottom-nav \{[^}]*border:\s*0;[^}]*border-top:[^}]*border-radius:\s*0;/)
    expect(hybridCSS).not.toMatch(/\.tm-hybrid-bottom-nav \{[^}]*bottom:\s*max\(/)
    expect(browserCSS).toMatch(/@media \(max-width: 760px\)[\s\S]*?\.bottom-navigation \{[^}]*left:\s*0;[^}]*bottom:\s*0;[^}]*width:\s*100vw;[^}]*border-radius:\s*0;/)
  })

  it('keeps the owner Profile header open with one separator instead of nested card frames', () => {
    const css = source('../../src/styles/global.css')
    expect(css).toMatch(/\.profile-dashboard--owner \{[^}]*border:\s*0;[^}]*border-radius:\s*0;[^}]*box-shadow:\s*none;/)
    expect(css).toMatch(/\.profile-dashboard--owner \.profile-dashboard__hero \{[^}]*border:\s*0;[^}]*border-bottom:\s*1px solid var\(--color-divider\);[^}]*border-radius:\s*0;[^}]*background:\s*transparent;/)
    expect(css).not.toMatch(/\.profile-dashboard--owner \.profile-dashboard__hero \{[^}]*border:\s*1px/)
  })

  it('keeps exactly one Add Restaurant primary entry as the Map floating CTA', () => {
    const shell = source('../../src/hybrid/app/HybridAppShell.tsx')
    const map = source('../../src/components/MyMapBrowsePage.tsx')
    const combined = `${shell}\n${map}`
    expect(HYBRID_ADD_RESTAURANT_ENTRY).toEqual({
      label: '添加餐厅', ownerSurface: 'map', presentation: 'floatingPrimaryCTA', route: 'add',
    })
    expect(combined.match(/data-product-contract="add-restaurant-primary-entry"/g) ?? []).toHaveLength(1)
    expect(shell).not.toContain('className="is-add"')
    expect(shell).not.toMatch(/<nav[^>]*>[\s\S]*?<span>添加<\/span>[\s\S]*?<\/nav>/)
  })

  it('uses one shared Add Restaurant product skeleton with all four formal acquisition capabilities', () => {
    const hybrid = source('../../src/hybrid/app/HybridAddRestaurantPage.tsx')
    const formalWeb = source('../../src/components/AddRestaurantModal.tsx')
    const shared = source('../../src/components/TasteMapRestaurantAcquisitionShared.tsx')
    const sharedCSS = source('../../src/components/tasteMapRestaurantAcquisitionShared.css')
    const hybridCSS = source('../../src/hybrid/app/hybridShell.css')
    expect(HYBRID_RESTAURANT_ACQUISITION_CONTRACT).toEqual({
      capabilities: ['search', 'nearby', 'share', 'manual'],
      primaryPasteLink: false,
      manualEntryCount: 1,
      candidateDestination: 'canonicalRestaurantDetail',
      bottomNavigationLabels: ['地图', '发现', '我的'],
    })
    for (const consumer of [hybrid, formalWeb]) {
      expect(consumer).toContain('TasteMapRestaurantAcquisitionScaffold')
      expect(consumer).toContain('TasteMapRestaurantAcquisitionSearch')
      expect(consumer).toContain('TasteMapRestaurantAcquisitionStatus')
      expect(consumer).toContain('TasteMapRestaurantAcquisitionResults')
    }
    for (const capability of HYBRID_RESTAURANT_ACQUISITION_CONTRACT.capabilities) {
      expect(shared).toContain(`data-acquisition-capability="${capability}"`)
    }
    expect(shared.match(/data-acquisition-capability="manual"/g)).toHaveLength(1)
    expect(shared).toContain('data-location-semantic="city-not-gps"')
    expect(shared).toContain('data-shared-acquisition-component="search-city"')
    expect(shared).toContain('data-shared-acquisition-component="nearby-status"')
    expect(shared).toContain('data-shared-acquisition-component="candidate-results"')
    expect(shared).toContain('data-search-action="compact-icon"')
    expect(shared).not.toContain('<span>搜索</span>')
    expect(sharedCSS).toMatch(/\.tm-acquisition-field input[\s\S]*?font-size:\s*16px/)
    expect(sharedCSS).toMatch(/\.tm-acquisition-search__submit[\s\S]*?width:\s*44px[\s\S]*?height:\s*44px/)
    expect(sharedCSS).toMatch(/\.tm-acquisition-status > button[\s\S]*?min-height:\s*44px/)
    expect(sharedCSS).toContain('.tm-acquisition__section-icon')
    for (const consumer of [hybrid, formalWeb, shared]) {
      expect(consumer).not.toContain('当前位置已更新')
      expect(consumer).not.toContain('附近搜索已完成')
    }
    expect(shared).not.toContain("'ready'")
    expect(hybrid).toContain("if (state === 'ready') return null")
    expect(formalWeb).toContain('nearbyLoading || nearbyError')
    expect(formalWeb).toContain('当前位置 3 公里内没有找到餐厅。')
    expect(formalWeb).toContain('正在取得新鲜位置')
    expect(formalWeb).toContain('暂时无法取得精确位置')
    const nativeAcquisition = source('../../ios/TasteMap/TasteMap/Features/Restaurant/AddRestaurantView.swift')
    expect(nativeAcquisition).not.toContain('以上餐厅按当前 GPS 坐标计算')
    expect(nativeAcquisition).not.toContain('以上餐厅按当前大致位置计算距离')
    expect(nativeAcquisition).toContain('当前为大致位置')
    expect(nativeAcquisition).toContain('附近餐厅暂时不可用')
    expect(hybrid).not.toContain('ADD RESTAURANT')
    expect(hybridCSS).not.toMatch(/tm-hybrid-add-panel|tm-hybrid-add-entry-row|tm-hybrid-add-legacy-stack|tm-hybrid-add-search|tm-hybrid-location-status|tm-hybrid-search-results/)
    expect(shared).not.toMatch(/user-scalable\s*=\s*no|maximum-scale\s*=\s*1/)
  })

  it('hands Native provider candidates back to the canonical Hybrid Restaurant Detail', () => {
    const nativeAdd = source('../../ios/TasteMap/TasteMap/Hybrid/TasteMapHybridRootView.swift')
    const nativeAcquisition = source('../../ios/TasteMap/TasteMap/Features/Restaurant/AddRestaurantView.swift')
    expect(nativeAdd).toContain('onCandidateSelected: openCanonicalDetail')
    expect(nativeAdd).toContain('TasteMapHybridRestaurantReferenceResolver.cacheCandidate')
    expect(nativeAdd).toContain('surface: .restaurant')
    expect(nativeAcquisition).toContain('private let onCandidateSelected')
    expect(nativeAcquisition).toContain('try onCandidateSelected(candidate)')
    expect(nativeAcquisition).toContain('RestaurantCandidateConfirmationView')
    expect(nativeAdd).not.toContain('RestaurantCandidateConfirmationView')
  })

  it('keeps the Hybrid-owned Add route in React for Share handoff and typed acquisition actions', () => {
    const add = source('../../src/hybrid/app/HybridAddRestaurantPage.tsx')
    const runtime = source('../../ios/TasteMap/TasteMap/Hybrid/TasteMapHybridRuntime.swift')
    for (const method of ['search', 'nearby', 'shared', 'manual', 'select']) {
      expect(add).toContain(`platform.acquisition.${method}`)
    }
    expect(add).not.toContain('acquisitionNative')
    expect(runtime).toContain('let state = try navigation.openHybrid(target)')
    expect(runtime).not.toMatch(/receive\(sharedImport:[\s\S]{0,400}navigation\.openNative\(target\)/)
  })

  it('locks exact Map scopes and forbids the superseded label and segmented Map/List row', () => {
    expect(HYBRID_MAP_PRIMARY_SCOPES.map((item) => item[1])).toEqual(['去过', '想吃', '推荐'])
    const map = source('../../src/components/MyMapBrowsePage.tsx')
    const sharedTabs = source('../../src/components/TasteMapDiscoveryShared.tsx')
    const nativeTabs = source('../../ios/TasteMap/TasteMap/Components/TasteMapCoreTheme.swift')
    const nativeMap = source('../../ios/TasteMap/TasteMap/Features/Map/MapHomeView.swift')
    expect(map).not.toContain('适合你')
    expect(map).toContain('tm-my-map__title-switch')
    expect(map).toContain('count: scopeCounts[value]')
    expect(sharedTabs).toContain('tm-primary-tab-bar__count')
    expect(sharedTabs).toContain('${item.label}，${item.count} 家餐厅')
    expect(nativeTabs).toContain('item.count.map { "\\(item.title)，\\($0) 家餐厅" }')
    expect(nativeMap).toContain('count: scopeCounts[.visited]')
    expect(nativeMap).toContain('count: scopeCounts[.wantToGo]')
    expect(nativeMap).toContain('count: scopeCounts[.forYou]')
    expect(map).not.toMatch(/地图\s*\/\s*列表|map-list-mode-picker|地图.*segmented|列表.*segmented/i)
  })

  it('locks one React product UI while allowing platform-native map engines', () => {
    const page = source('../../src/components/MyMapBrowsePage.tsx')
    const browserSurface = source('../../src/components/BrowserMapSurface.tsx')
    const nativeSurface = source('../../src/components/NativeMapSurface.tsx')
    const browserApp = source('../../src/App.tsx')
    const hybridShell = source('../../src/hybrid/app/HybridAppShell.tsx')
    const nativeHost = source('../../ios/TasteMap/TasteMap/Hybrid/TasteMapHybridMapSurface.swift')
    expect(page).toContain('MapSurface: ComponentType<MyMapSurfaceProps>')
    expect(page).not.toContain("from './MapView'")
    expect(page).not.toContain("from './NativeMapSurface'")
    expect(browserSurface).toContain("import { MapView } from './MapView'")
    expect(browserApp).toContain('MapSurface={BrowserMapSurface}')
    expect(hybridShell).toContain('MapSurface={NativeMapSurface}')
    expect(hybridShell).not.toContain('BrowserMapSurface')
    expect(nativeSurface).toContain('reactControlExclusions')
    expect(nativeHost).toContain('RestaurantMapView(')
    expect(nativeHost).not.toContain('MKMapView(')
  })

  it('locks the exact five first-level Discovery tabs', () => {
    expect(HYBRID_DISCOVERY_PRIMARY_TABS.map((item) => item[1])).toEqual([
      '关注', '为你推荐', '同味之选', '最新', '趋势',
    ])
  })

  it('uses one shared Discovery scaffold, FilterBar and Activity Card in formal Web and Hybrid', () => {
    const hybrid = source('../../src/hybrid/app/HybridDiscoveryPage.tsx')
    const formalWeb = source('../../src/components/CommunityPage.tsx')
    const shared = source('../../src/components/TasteMapDiscoveryShared.tsx')
    const sharedCSS = source('../../src/components/tasteMapDiscoveryShared.css')
    const hybridCSS = source('../../src/hybrid/app/hybridShell.css')
    const nativeShared = source('../../ios/TasteMap/TasteMap/Components/TasteMapCoreTheme.swift')
    for (const consumer of [hybrid, formalWeb]) {
      expect(consumer).toContain('TasteMapDiscoveryShared')
      expect(consumer).toContain('TasteMapDiscoveryScaffold')
      expect(consumer).toContain('TasteMapFilterBar')
      expect(consumer).toContain('TasteMapActivityCardFrame')
      expect(consumer).not.toContain('>DISCOVER<')
    }
    expect(shared).toContain('data-product-contract="discovery-page"')
    expect(shared).toContain('data-product-contract="activity-card"')
    for (const region of [
      'author-time-visibility', 'restaurant-image', 'restaurant-name-address-context',
      'visit-rating', 'like-comment-more-share', 'restaurant-actions',
    ]) expect(shared).toContain(`data-activity-region="${region}"`)
    expect(shared).toContain("variant === 'recommendation' ? 'recommendation-reason'")
    const cardOrder = [
      'restaurant-name-address-context', 'visit-rating', 'restaurant-image',
      'recommendation-reason', 'like-comment-more-share', 'restaurant-actions',
    ].map((region) => shared.indexOf(`data-activity-region={variant === 'recommendation' ? 'recommendation-reason'`) >= 0 && region === 'recommendation-reason'
      ? shared.indexOf(`data-activity-region={variant === 'recommendation' ? 'recommendation-reason'`)
      : shared.indexOf(`data-activity-region="${region}"`))
    expect(cardOrder.every((index) => index >= 0)).toBe(true)
    expect(cardOrder).toEqual([...cardOrder].sort((left, right) => left - right))
    expect(hybrid).toContain('tm-activity-card__recommendation-reason')
    expect(hybrid).toContain('CommunityRatingSummary')
    expect(hybrid).not.toContain('tm-activity-card__source"><')
    expect(hybrid).not.toContain('aria-label="关注用户"')
    expect(hybrid).not.toMatch(/<Send\b/)
    expect(sharedCSS).toMatch(/\.tm-activity-card \{[^}]*border:\s*0[^}]*border-radius:\s*0/)
    expect(sharedCSS).toMatch(/\.tm-activity-card__media \{[^}]*width:\s*min\(48%,\s*178px\)[^}]*aspect-ratio:\s*1/)
    expect(sharedCSS).toMatch(/\.tm-activity-card__recommendation-reason \{[^}]*border:\s*0[^}]*border-top:/)
    expect(sharedCSS).toMatch(/\.tm-discovery-page__content \{[^}]*background:\s*var\(--color-surface/)
    expect(hybridCSS).toMatch(/\.tm-hybrid-discovery \.tm-hybrid-activity-feed \{[^}]*gap:\s*0/)
    const nativeActivitySurface = nativeShared.match(/struct TasteMapActivityCard<[\s\S]*?\n}\n\nstruct TasteMapSectionHeader/)?.[0] ?? ''
    expect(nativeActivitySurface).toContain('.overlay(alignment: .bottom) { Divider() }')
    expect(nativeActivitySurface).not.toContain('.tasteMapCoreCard(')
    expect(hybridCSS).not.toMatch(/tm-hybrid-discovery-card|tm-hybrid-activity-card|tm-hybrid-discovery-grid/)
    expect(hybridCSS).not.toContain('grid-template-columns: 122px minmax(0,1fr)')
  })

  it('keeps one canonical Restaurant Detail body and its required section order', () => {
    const shell = source('../../src/hybrid/app/HybridAppShell.tsx')
    const platform = source('../../src/platform/TasteMapPlatform.ts')
    const nativeContracts = source('../../ios/TasteMap/TasteMap/Hybrid/TasteMapHybridContracts.swift')
    const nativeService = source('../../ios/TasteMap/TasteMap/Hybrid/TasteMapHybridBridgeService.swift')
    expect(shell.match(/<RestaurantPreviewCard/g)).toHaveLength(1)
    expect(shell).not.toMatch(/<DiscoverRestaurantDetail|<MapRestaurantDetail|<FriendRestaurantDetail|<RecommendationRestaurantDetail/)
    expect(HYBRID_RESTAURANT_DETAIL_SECTION_ORDER).toEqual([
      'Cover', 'CityAndState', 'NameAndActions', 'Address', 'CompactBasics',
      'RatingReference', 'UserPhotos', 'MyVisitOverview', 'DownstreamContent',
    ])
    expect(platform).toContain('socialStats?: RestaurantSocialStats | null')
    expect(nativeContracts).toContain('TasteMapHybridRestaurantSocialStatsDTO')
    expect(nativeService).toContain('$0.currentUserID == ownerUserID && globalIdentityKeys.contains($0.globalKey)')
    expect(shell).toContain('socialStats={restaurant.socialStats}')
  })

  it('locks current-only Profile, Lists, Analytics, Posters and Settings topology', () => {
    expect(HYBRID_PROFILE_OWNER_MODULES).toEqual([
      '身份与 Premium', '关注 / 被关注', '去过 / 想去 / 总消费',
      '今天吃什么 / 我的口味档案', '回味', '我的食单', '发现与洞察',
      '数据与设置 / 账号与隐私',
    ])
    expect(HYBRID_LIST_SCOPES).toEqual(['我的食单', '公开食单'])
    expect(HYBRID_ANALYTICS_MODES.map((item) => item[1])).toEqual([
      '我的口味档案', '最佳饭搭子', '谁最会种草', '本月回顾', '年度回顾',
    ])
    expect(HYBRID_SETTINGS_SECTIONS).toEqual([
      '账户', '数据与备份', '同步', '隐私与权限', '存储与 Premium', '帮助与关于',
    ])
    expect(source('../../src/components/TasteMapAnalyticsPage.tsx')).toContain('renderAnalysisPosterBlob')
    expect(source('../../src/components/TasteMapPremiumSettingsPages.tsx')).toContain('PremiumBurgerBadge')
  })

  it('keeps every migration-pending formal capability visible through an allowlisted Native handoff', () => {
    const shell = source('../../src/hybrid/app/HybridAppShell.tsx')
    const root = source('../../ios/TasteMap/TasteMap/Hybrid/TasteMapHybridRootView.swift')
    const contracts = source('../../ios/TasteMap/TasteMap/Hybrid/TasteMapHybridContracts.swift')
    for (const route of HYBRID_NATIVE_CAPABILITY_HANDOFFS) {
      expect(`${shell}\n${root}\n${contracts}`).toContain(route)
    }
    expect(shell).not.toMatch(/onSave=\{async \(\) => undefined\}|onEdit=\{\(\) => undefined\}|onDelete=\{\(\) => undefined\}|onEditVisit=\{\(\) => undefined\}/)
  })

  it('keeps an owner-scoped, exactly-one Visit edit entry routed to the official Native editor', () => {
    const shell = source('../../src/hybrid/app/HybridAppShell.tsx')
    const detail = source('../../src/components/RestaurantPreviewCard.tsx')
    expect(HYBRID_VISIT_HISTORY_EDIT_CONTRACT).toEqual({
      editableVisitEntryCount: 1,
      nonEditableVisitEntryCount: 0,
      ownershipAuthority: 'nativeOwnerScope',
      transitionRoute: 'visitEdit',
      writeOwner: 'existingNativeVisitEditor',
      refreshAfterDismiss: true,
    })
    expect(detail.match(/data-product-contract="visit-edit-entry"/g)).toHaveLength(1)
    expect(detail).toContain('canEditVisit ? canEditVisit(visit) : !readOnly')
    expect(shell).toContain("navigate({ surface: 'visitEdit', id: visit.id })")
    expect(shell).not.toContain("openNativeRoute(platform, 'visitEdit', visit.id)")
    expect(shell).toContain('restaurant.editableVisitIDs.includes(visit.id)')
    expect(shell).not.toMatch(/visit\.userId\s*===|CURRENT_USER_ID.*visit/)
  })

  it('keeps Browser and Capacitor on one direct-set editable rating component', () => {
    const browser = source('../../src/App.tsx')
    const hybrid = source('../../src/hybrid/app/HybridVisitEditorPage.tsx')
    const editor = source('../../src/components/AddVisitModal.tsx')
    const acquisition = source('../../src/components/AddRestaurantModal.tsx')
    const rating = source('../../src/components/StarRating.tsx')
    const interaction = source('../../src/utils/starRatingInteraction.ts')
    for (const consumer of [browser, hybrid]) expect(consumer).toContain('<AddVisitModal')
    for (const consumer of [editor, acquisition]) {
      expect(consumer).toContain('<StarRatingField')
      expect(consumer).not.toMatch(/<label[^>]*>[\s\S]{0,160}<StarRating/)
    }
    expect(rating).toContain("reduceEditableStarRating(value, { type: 'set'")
    expect(rating).toContain("reduceEditableStarRating(value, { type: 'clear' })")
    expect(interaction).not.toMatch(/current\s*===\s*action\.value|action\.value\s*===\s*current/)
  })

  it('keeps public/cached Restaurant capabilities explicit and never substitutes the social route for WantToGo', () => {
    const shell = source('../../src/hybrid/app/HybridAppShell.tsx')
    const discovery = source('../../src/hybrid/app/HybridDiscoveryPage.tsx')
    const contracts = source('../../ios/TasteMap/TasteMap/Hybrid/TasteMapHybridContracts.swift')
    const bridge = source('../../ios/TasteMap/TasteMap/Hybrid/TasteMapHybridBridgeService.swift')
    expect(contracts).toContain('public static let publicReadable')
    expect(contracts).toContain('canAddToWantToGo')
    expect(bridge).toContain('TasteMapHybridRestaurantReferenceResolver.resolve')
    expect(shell).toContain('platform.restaurant.setWantToGo')
    expect(discovery).toContain('platform.restaurant.setWantToGo')
    expect(discovery).not.toContain("route: 'restaurantWantToGo'")
    expect(discovery).not.toContain("route: 'socialNative', identifier: item.restaurant.id")
    expect(discovery).toContain("previous === 'visited'")
    expect(shell).not.toMatch(/restaurant\.restaurant\.userId\s*===|CURRENT_USER_ID.*canEdit/)
  })

  it('routes Discovery interactions through typed owners without generic social or Native Hybrid-page handoffs', () => {
    const discovery = source('../../src/hybrid/app/HybridDiscoveryPage.tsx')
    const shell = source('../../src/hybrid/app/HybridAppShell.tsx')
    const platform = source('../../src/platform/TasteMapPlatform.ts')
    const runtime = source('../../ios/TasteMap/TasteMap/Hybrid/TasteMapHybridRuntime.swift')
    for (const method of ['community.setLike', 'community.comments', 'community.addComment', 'restaurant.setWantToGo']) {
      expect(platform).toContain(`'${method}'`)
    }
    expect(discovery).toContain('platform.community.setLike')
    expect(discovery).toContain('platform.community.comments')
    expect(discovery).toContain('platform.community.addComment')
    expect(discovery).not.toMatch(/openNative\(\{ route: 'visit'/)
    expect(discovery).not.toMatch(/aria-label=\{[^\n]*点赞[^\n]*openNative/)
    expect(discovery).not.toMatch(/aria-label="评论"[^\n]*openNative/)
    expect(shell).toContain("navigate({ surface: 'visit', id: restaurantID })")
    expect(shell).toContain("navigate({ surface: 'roulette' })")
    expect(runtime).toContain('hybrid_route_requires_openHybrid')
  })

  it('backs debug comment badges with the same per-visit comment collections on Browser and Native', () => {
    const fixture = source('../../src/platform/TasteMapBrowserDebugFixture.ts')
    const browser = source('../../src/platform/TasteMapBrowserAdapter.ts')
    const native = source('../../ios/TasteMap/TasteMap/Hybrid/TasteMapHybridRuntime.swift')
    expect(fixture).toContain('commentsByVisit: buildComments(content)')
    expect(browser).toContain('items: await this.commentsFor(target.visitID)')
    expect(browser).toContain('const values = [...await this.commentsFor(target.visitID), comment]')
    expect(native).toContain('items: debugComments(request.target.visitID)')
    expect(native).toContain('var comments = debugComments(request.target.visitID)')
  })

  it('keeps exactly three Discovery Restaurant actions without removing List elsewhere', () => {
    const discovery = source('../../src/hybrid/app/HybridDiscoveryPage.tsx')
    const shell = source('../../src/hybrid/app/HybridAppShell.tsx')
    const platform = source('../../src/platform/TasteMapPlatform.ts')
    for (const icon of ['NotebookPen', 'Bookmark', 'Dices']) expect(discovery).toContain(icon)
    for (const removed of ['ListPlus', 'CirclePlus', 'BookmarkPlus', '食单 ', "route: 'restaurantAddToList'"]) {
      expect(discovery).not.toContain(removed)
    }
    expect(shell).toContain("openNativeRoute(platform, 'restaurantAddToList'")
    expect(platform).toContain("'restaurantAddToList'")
    expect(HYBRID_NATIVE_CAPABILITY_HANDOFFS).toContain('restaurantAddToList')
  })

  it('owns all thirteen Batch 1 surfaces through formal shared React renderers or thin capability adapters', () => {
    const browser = source('../../src/App.tsx')
    const hybrid = source('../../src/hybrid/app/HybridAppShell.tsx')
    const sharedRenderers = [
      'MyMapBrowsePage', 'ProfilePage', 'RestaurantPreviewCard', 'TasteMapListsPage',
      'RestaurantRoulette', 'TasteMapAnalyticsPage', 'TasteMapPremiumPage', 'TasteMapSettingsPage',
    ]
    for (const renderer of sharedRenderers) {
      expect(browser).toContain(`<${renderer}`)
      expect(hybrid).toContain(`<${renderer}`)
    }
    const discoveryAdapter = source('../../src/hybrid/app/HybridDiscoveryPage.tsx')
    const formalDiscovery = source('../../src/components/CommunityPage.tsx')
    for (const renderer of ['TasteMapDiscoveryScaffold', 'TasteMapFilterBar', 'TasteMapActivityCardFrame']) {
      expect(discoveryAdapter).toContain(renderer)
      expect(formalDiscovery).toContain(renderer)
    }
    const acquisitionAdapter = source('../../src/hybrid/app/HybridAddRestaurantPage.tsx')
    const formalAcquisition = source('../../src/components/AddRestaurantModal.tsx')
    expect(acquisitionAdapter).toContain('TasteMapRestaurantAcquisitionScaffold')
    expect(formalAcquisition).toContain('TasteMapRestaurantAcquisitionScaffold')
    expect(source('../../src/components/TasteMapAnalyticsPage.tsx')).toContain('renderAnalysisPosterBlob')
  })

  it('keeps retired duplicate Hybrid page implementations absent', () => {
    const retired = [
      'HybridListsPage.tsx', 'HybridRoulettePage.tsx', 'HybridAnalyticsPage.tsx',
      'HybridPremiumPage.tsx', 'HybridSettingsPage.tsx', 'HybridRestaurantDetailPage.tsx',
      'HybridProfilePage.tsx', 'CapacitorDiscoveryPage.tsx', 'IOSAddRestaurantPage.tsx',
    ]
    for (const name of retired) {
      expect(existsSync(new URL(`../../src/hybrid/app/${name}`, import.meta.url))).toBe(false)
    }
  })

  it('forbids production no-op callbacks and route-to-tab coupling in the Hybrid shell', () => {
    const shell = source('../../src/hybrid/app/HybridAppShell.tsx')
    expect(shell).not.toMatch(/on[A-Z][A-Za-z]+\s*=\{\s*\(.*\)\s*=>\s*(?:undefined|\{\s*\})\s*\}/)
    expect(shell).not.toContain('Object.keys(HYBRID_ROUTE_REGISTRY).map')
    expect(shell).not.toContain('HYBRID_ROUTE_REGISTRY.map')
    expect(shell.match(/data-product-contract="bottom-navigation"/g)).toHaveLength(1)
  })

  it('keeps Batch 2 system capabilities typed and owned by existing Native services', () => {
    const platform = source('../../src/platform/TasteMapPlatform.ts')
    const settings = source('../../src/components/TasteMapPremiumSettingsPages.tsx')
    const runtime = source('../../ios/TasteMap/TasteMap/Hybrid/TasteMapHybridRuntime.swift')
    for (const method of [
      'premium.products', 'premium.purchase', 'premium.restore', 'premium.manage',
      'sync.status', 'sync.run', 'permissions.status', 'permissions.openSettings',
      'backup.openExport', 'backup.openImport', 'account.openDelete', 'photo.pick', 'photo.capture',
    ]) expect(platform).toContain(`'${method}'`)
    expect(runtime).toContain('premiumEntitlementService.productsProvider')
    expect(runtime).toContain('syncCoordinator.synchronizeNow()')
    expect(runtime).toContain('SettingsPermissionSnapshot.live')
    expect(runtime).toContain('photoTransferCoordinator.preparePhoto')
    expect(runtime).toContain('UIImagePickerController.isSourceTypeAvailable(.camera)')
    expect(settings).toContain('platform.backup.openExport()')
    expect(settings).toContain('platform.backup.openImport()')
    expect(settings).toContain('platform.account.openDelete()')
    expect(settings).not.toMatch(/fake Product|fake product|isPremium\s*=\s*true/)
  })
})

describe('Hybrid forbidden Product patterns', () => {
  it('forbids clusters and default separation while requiring food emoji fallback markers', () => {
    const map = source('../../src/components/MapView.tsx')
    const mapService = source('../../src/services/amap.ts')
    const nativeMap = source('../../ios/TasteMap/TasteMap/Features/Map/ClusteredRestaurantMapView.swift')
    const nativePresentation = source('../../ios/TasteMap/TasteMap/Features/Map/RestaurantMapPresentation.swift')
    const combined = `${map}\n${mapService}\n${nativeMap}\n${nativePresentation}`
    expect(combined).not.toMatch(/MarkerCluster|createClusterData|spiderfy|collision dispersion|coordinateOffset|adjustedCoordinate|spreadCoordinate/i)
    expect(map).toContain('resolveRestaurantFoodEmoji')
    expect(nativeMap).toContain('emojiLabel')
    expect(nativePresentation).toContain('FoodCategoryEmojiResolver.resolve')
  })

  it('uses Activity/Visit rating and never substitutes Restaurant aggregate rating', () => {
    const discovery = source('../../src/hybrid/app/HybridDiscoveryPage.tsx')
    const formalWeb = source('../../src/components/CommunityPage.tsx')
    const shared = source('../../src/components/TasteMapDiscoveryShared.tsx')
    const nativeShared = source('../../ios/TasteMap/TasteMap/Components/TasteMapCoreTheme.swift')
    expect(discovery).toContain('item.activityRating')
    expect(discovery).toContain('item.visitRating')
    expect(discovery).not.toMatch(/item\.restaurant\.(averageRating|scoreOutOfTen)/)
    expect(formalWeb).toContain('const activityRating = item.visit.rating')
    expect(formalWeb).not.toMatch(/activityRating=\{[^}]*item\.restaurant\.(averageRating|scoreOutOfTen)/)
    expect(shared).toContain("variant === 'activity' && activityRating")
    expect(shared).toContain('scoreColor(rating == null ? null : rating * 2)')
    expect(nativeShared).toContain('RestaurantScoreColorPolicy.color(forFivePointRating: rating)')
  })

  it('does not restore paste-link as the primary Add Restaurant flow', () => {
    const add = source('../../src/hybrid/app/HybridAddRestaurantPage.tsx')
    const formal = source('../../src/components/AddRestaurantModal.tsx')
    const shared = source('../../src/components/TasteMapRestaurantAcquisitionShared.tsx')
    expect(add).not.toMatch(/placeholder="[^"]*(粘贴|链接)/)
    expect(add).not.toMatch(/<input[^>]+(?:paste|url|link)/i)
    expect(shared).not.toMatch(/粘贴餐厅链接/)
    expect(shared).not.toMatch(/<input[^>]+(?:paste|url|link)/i)
    expect(formal).toContain('data-secondary-share-ingestion="true"')
  })

  it('does not restore retired Google Drive controls through either formal Settings surface', () => {
    const settingsModal = source('../../src/components/SettingsModal.tsx')
    const settingsPage = source('../../src/components/TasteMapPremiumSettingsPages.tsx')
    for (const settings of [settingsModal, settingsPage]) {
      expect(settings).not.toMatch(/Google Drive|connectGoogleDrive|useGoogleDrive|连接 Google/)
    }
  })
})
