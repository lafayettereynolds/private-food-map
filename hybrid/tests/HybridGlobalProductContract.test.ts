import { existsSync, readFileSync } from 'node:fs'
import { describe, expect, it } from 'vitest'
import {
  HYBRID_ADD_RESTAURANT_ENTRY,
  HYBRID_RESTAURANT_ACQUISITION_CONTRACT,
  HYBRID_BOTTOM_NAVIGATION,
  HYBRID_DISCOVERY_PRIMARY_TABS,
  HYBRID_ANALYTICS_MODES,
  HYBRID_ANALYTICS_MODULES,
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
  it('uses one compact centered follow action for Native recommendation and search rows', () => {
    const social = source('../../ios/TasteMap/TasteMap/Features/Profile/SocialViews.swift')
    const control = source('../../ios/TasteMap/TasteMap/Components/TasteMapCompactFollowButton.swift')
    expect(social).toContain('row(suggestion.user, allowsFollow: true)')
    expect(social).toContain('row(item, allowsFollow: section == .recommendations)')
    expect(social).toContain('TasteMapCompactFollowButton(')
    expect(social).not.toContain('Label("关注", systemImage: "person.badge.plus")')
    expect(control).toContain('alignment: .center')
    expect(control).toContain('TasteMapDesignTokens.Control.minimumHitTarget')
    expect(control).toContain('.fixedSize(horizontal: true, vertical: false)')
    expect(control).toContain('.disabled(isPending)')
    expect(control).not.toContain('Spacer(')
    expect(control).not.toContain('maxWidth: .infinity')
  })
  it('has one owner for profile-editor dismissal across host and editor variants', () => {
    const profile = source('../../src/components/ProfilePage.tsx').split('function ProfileEditorModal')[1].split('export type AccountSettingsSection')[0]
    expect(profile).toContain('dismissAction="back" dismissDisabled={saving}')
    expect(profile).not.toContain('secondaryAction=')
    const native = source('../../ios/TasteMap/TasteMap/Features/Profile/ProfileView.swift').split('struct ProfileEditorSheet: View')[1].split('#if DEBUG')[0]
    expect(native).toContain('TasteMapReturnButton { dismiss() }')
    expect(native).toContain('.accessibilityIdentifier("profile-back-button")')
    expect(native).not.toContain('Button("取消")')
    expect(native).toContain('.interactiveDismissDisabled(isSaving)')
    const host = source('../../ios/TasteMap/TasteMap/Hybrid/TasteMapHybridRootView.swift')
    expect(host).toContain('TasteMapHybridNativeNavigationPolicy.destinationOwnsNavigation(route.surface)')
    expect(host).toContain('TasteMapHybridNativeDismissibleFailure(title: "无法编辑个人资料")')
  })
  it('keeps secondary-page back navigation in one persistent shared primitive', () => {
    const shared = source('../../src/components/TasteMapHybridShared.tsx')
    const css = source('../../src/components/tasteMapNavigation.css')
    const shell = source('../../src/hybrid/app/HybridAppShell.tsx')
    const browser = source('../../src/App.tsx')
    expect(shared).toContain('export function PersistentPageNavigation')
    expect(shared).toContain('<PersistentPageNavigation>')
    expect(css).toMatch(/\.tm-hybrid-page-navigation \{[^}]*position: sticky;/)
    expect(css).toContain('--tm-safe-top')
    expect(css).toContain('--control-min-hit-target')
    expect(css).toContain('pointer-events: none')
    expect(shell).toContain('<HybridBackButton onBack={() => void navigateBack()} />')
    expect(shell).not.toContain('tm-hybrid-detail__back')
    expect(shell).toContain('showCloseButton={false}')
    expect(browser.match(/<HybridBackButton onBack=\{\(\) => set(?:SelectedId|StandaloneRestaurant)\(null\)\}/g)).toHaveLength(2)
    for (const path of ['../../src/components/ProfilePage.tsx', '../../src/components/TasteFootprints.tsx']) {
      expect(source(path)).toContain('<PersistentPageNavigation')
    }
  })
  it('opens editable Discovery filter sheets on both React entry points instead of summaries or tab-gated placeholders', () => {
    const hybrid = source('../../src/hybrid/app/HybridDiscoveryPage.tsx')
    const browser = source('../../src/components/CommunityPage.tsx')
    for (const implementation of [hybrid, browser]) {
      expect(implementation).toContain('TasteMapFilterSheet')
      expect(implementation).toContain('aria-haspopup="dialog"')
      for (const label of ['筛选城市', '筛选排序', '筛选最低评分']) expect(implementation).toContain(`aria-label="${label}"`)
      expect(implementation).not.toContain('tm-discovery-filter-summary')
    }
    expect(browser).not.toContain("if (mode !== 'for_you') return evidenceFeed")
    expect(browser).toContain("score(item) >= ratingFilter")
    expect(browser).toContain("sameCity(item.restaurant.city, city)")
    expect(browser).toContain('item.visit.recommendationSourceType === sourceFilter')
    expect(browser).toContain('.includes(companionFilter)')
    expect(browser).toContain('aria-label="筛选适合场景"')
    const shared = source('../../src/components/TasteMapDiscoveryShared.tsx')
    expect(shared).toContain('<ModalShell title="筛选餐厅"')
    expect(shared).toContain('onClick={onReset}')
    expect(shared).toContain('onClick={onApply ?? onClose}')
    expect(shared).toContain("onApply ? '应用' : '查看结果'")
    expect(shared).toContain('onClick={onClose} type="button">取消')
  })

  it('keeps internal consumption calculations out of shared and Native Visit editors', () => {
    const shared = source('../../src/components/VisitSpendFields.tsx')
    const native = source('../../ios/TasteMap/TasteMap/Features/Visit/VisitEditorView.swift')
    for (const implementation of [shared, native]) {
      expect(implementation).not.toContain('尚未计入消费统计')
      expect(implementation).not.toContain('计入总消费')
      expect(implementation).not.toContain('参考人均')
      expect(implementation).not.toContain('全额计入')
      expect(implementation).not.toContain('历史支付金额')
      expect(implementation).toContain('消费金额（元）')
    }
    for (const consumer of ['AddRestaurantModal', 'AddVisitModal']) {
      expect(source(`../../src/components/${consumer}.tsx`)).toContain('<VisitSpendFields')
    }
  })

  it('keeps comment inputs at the iOS-safe focus size', () => {
    expect(source('../../src/styles/global.css')).toContain('.community-comment-panel form input { font-size: 16px; }')
  })

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
    expect(hybridCSS).toContain('--tm-bottom-navigation-content-height: 56px;')
    expect(hybridCSS).toMatch(/\.tm-hybrid-bottom-nav \{[^}]*left:\s*0;[^}]*right:\s*0;[^}]*bottom:\s*0;[^}]*height:\s*calc\(var\(--tm-bottom-navigation-content-height\) \+ var\(--tm-safe-bottom\)\);/)
    expect(hybridCSS).toMatch(/\.tm-hybrid-detail \{[^}]*padding: 14px 14px calc\(var\(--tm-bottom-navigation-content-height\) \+ 14px\);/)
    expect(hybridCSS).toMatch(/\.tm-hybrid-bottom-nav \{[^}]*border:\s*0;[^}]*border-top:[^}]*border-radius:\s*0;/)
    expect(hybridCSS).not.toMatch(/\.tm-hybrid-bottom-nav \{[^}]*bottom:\s*max\(/)
    expect(browserCSS).toMatch(/@media \(max-width: 760px\)[\s\S]*?\.bottom-navigation \{[^}]*left:\s*0;[^}]*bottom:\s*0;[^}]*width:\s*100vw;[^}]*border-radius:\s*0;/)
  })

  it('uses the active page canvas through the status-bar safe area without hidden-route leakage', () => {
    const css = source('../../src/hybrid/app/hybridShell.css')
    const browseCSS = source('../../src/components/tasteMapDiscoveryShared.css')
    const acquisitionCSS = source('../../src/components/tasteMapRestaurantAcquisitionShared.css')
    expect(css).toContain(':root:has(.tm-hybrid-shell[data-route="profile"])')
    expect(css).toContain('--tm-shell-background: var(--color-surface);')
    for (const route of ['map', 'discovery', 'activity', 'add']) {
      expect(css).toContain(`:root:has(.tm-hybrid-shell[data-route="${route}"])`)
    }
    expect(css).toContain('--tm-shell-background: var(--tm-browse-chrome-background);')
    expect(css).toContain('--tm-shell-background: var(--tm-acquisition-surface);')
    expect(css).not.toContain(':root:has(.profile-page)')
    expect(css).toContain(':root:has(.tm-hybrid-shell) body { background: var(--tm-shell-background); }')
    expect(css).toMatch(/\.tm-hybrid-shell \{[^}]*padding:\s*var\(--tm-safe-top\)[^;]*;[^}]*background:\s*var\(--tm-shell-background\);/)
    expect(browseCSS).toContain('--tm-browse-chrome-background: #f8fafc;')
    expect(browseCSS).toContain('--tm-browse-chrome-background: #12191f;')
    expect(browseCSS).not.toContain('rgba(248,250,252,')
    expect(source('../../src/components/myMapBrowsePage.css')).not.toContain('rgba(18,25,31,')
    expect(acquisitionCSS).toContain(':root { --tm-acquisition-surface: var(--color-surface, #fff); }')
    expect(css).toContain('.tm-hybrid-add { padding: 0 0 92px; background: var(--tm-acquisition-surface); }')
  })

  it('suppresses browser-style long-press callouts outside editable fields', () => {
    const shell = source('../../src/hybrid/app/HybridAppShell.tsx')
    const css = source('../../src/hybrid/app/hybridShell.css')
    const host = source('../../ios/TasteMap/TasteMap/Hybrid/TasteMapHybridCapacitorHost.swift')
    expect(css).toMatch(/\.tm-hybrid-shell \{[^}]*-webkit-touch-callout:\s*none;[^}]*-webkit-user-select:\s*none;[^}]*user-select:\s*none;/)
    expect(css).toMatch(/\.tm-hybrid-shell input,[\s\S]*?\[contenteditable="true"\] \{[^}]*-webkit-touch-callout:\s*default;[^}]*-webkit-user-select:\s*text;[^}]*user-select:\s*text;/)
    expect(shell).toContain('onContextMenu={(event) => {')
    expect(shell).toContain("closest('input, textarea, [contenteditable=\"true\"]')")
    expect(shell).toContain('event.preventDefault()')
    expect(host).toContain('webView.allowsLinkPreview = false')
  })

  it('keeps the owner Profile header open with one separator instead of nested card frames', () => {
    const css = source('../../src/styles/global.css')
    expect(css).toMatch(/\.profile-dashboard--owner \{[^}]*border:\s*0;[^}]*border-radius:\s*0;[^}]*box-shadow:\s*none;/)
    expect(css).toMatch(/\.profile-dashboard--owner \.profile-dashboard__hero \{[^}]*border:\s*0;[^}]*border-bottom:\s*1px solid var\(--color-divider\);[^}]*border-radius:\s*0;[^}]*background:\s*transparent;/)
    expect(css).not.toMatch(/\.profile-dashboard--owner \.profile-dashboard__hero \{[^}]*border:\s*1px/)
  })

  it('keeps phone, opening hours and directions in one balanced Restaurant Detail grid without a website item', () => {
    const summary = source('../../src/components/RestaurantRecordSummary.tsx')
    const css = source('../../src/styles/global.css')
    expect(summary.match(/className="restaurant-contact-actions"/g)).toHaveLength(1)
    expect(summary.indexOf('<Phone size={14}')).toBeLessThan(summary.indexOf('<Clock3 size={14}'))
    expect(summary.indexOf('<Clock3 size={14}')).toBeLessThan(summary.indexOf('<Navigation size={14}'))
    expect(summary).not.toContain('<Globe2')
    expect(summary).not.toContain('暂无官网')
    expect(summary).not.toContain('<small>官网</small>')
    expect(css).toMatch(/\.restaurant-contact-actions \{[^}]*display:\s*grid;[^}]*grid-template-columns:\s*repeat\(3,\s*minmax\(0,\s*1fr\)\);/)
    expect(css).not.toMatch(/\.restaurant-contact-actions \{[^}]*flex-wrap:\s*wrap;/)
  })

  it('keeps Profile feature cards free of redundant trailing arrows', () => {
    const profile = source('../../src/components/ProfilePage.tsx')
    const css = source('../../src/styles/global.css')
    const nativeProfile = source('../../ios/TasteMap/TasteMap/Features/Profile/ProfileView.swift')
    expect(profile).not.toContain('ArrowRight')
    const tasteCard = profile.slice(profile.indexOf('function TasteProfileSummary'), profile.indexOf('function ProfileDetailModal'))
    expect(tasteCard).not.toContain('<ChevronRight')
    const insightCards = profile.slice(profile.indexOf('className="profile-analytics-links"'), profile.indexOf('</ProfileSection> : null}', profile.indexOf('className="profile-analytics-links"')))
    expect(insightCards).not.toContain('<ChevronRight')
    expect(css).toMatch(/@media \(max-width: 760px\)[\s\S]*?\.profile-analytics-links \{[^}]*grid-template-columns:\s*repeat\(2,\s*minmax\(0,\s*1fr\)\);/)
    expect(css).not.toMatch(/\.profile-analytics-links \{[^}]*grid-template-columns:\s*1fr;/)
    const nativeDashboardTile = nativeProfile.slice(nativeProfile.indexOf('private struct ProfileDashboardTile'), nativeProfile.indexOf('private struct ProfileCompactTile'))
    expect(nativeDashboardTile).not.toContain('chevron.right')
  })

  it('keeps the Profile List card and all-lists entry in a non-overlapping vertical flow', () => {
    const browserCSS = source('../../src/styles/global.css')
    const hybridCSS = source('../../src/hybrid/app/hybridShell.css')
    const shell = source('../../src/hybrid/app/HybridAppShell.tsx')
    const lists = source('../../src/components/TasteMapListsPage.tsx')
    expect(browserCSS).toMatch(/\.restaurant-list-collection-grid > button:only-child \{[^}]*grid-column:\s*1 \/ -1;/)
    expect(hybridCSS).toMatch(/\.profile-lists-hybrid-entry \{[^}]*margin:\s*8px 16px 18px;/)
    expect(hybridCSS).not.toMatch(/\.profile-lists-hybrid-entry \{[^}]*margin:\s*-/)
    expect(shell).toContain('<HybridProfileListsPreview')
    expect(shell).toContain('lists={content.lists}')
    expect(shell).toContain('content.lists.filter((item) => item.isOwnedByViewer).length')
    expect(lists).toContain('.sort((left, right) => right.updatedAt.localeCompare(left.updatedAt))')
    expect(lists).toContain('const previewLists = ownedLists.slice(0, 2)')
  })

  it('keeps add-to-List Restaurant rows circular and structurally separated', () => {
    const component = source('../../src/components/RestaurantListsPanel.tsx')
    const css = source('../../src/styles/global.css')
    expect(component).toContain('className="restaurant-list-add-panel__copy"')
    expect(component).toContain('className="restaurant-list-add-panel__action"')
    expect(css).toMatch(/\.restaurant-list-add-panel > div > button \{[^}]*grid-template-columns:\s*42px minmax\(0, 1fr\) 28px;/)
    expect(css).toMatch(/\.restaurant-list-add-panel > div > button > \.restaurant-avatar \{[^}]*width:\s*42px;[^}]*height:\s*42px;/)
    expect(css).not.toContain('.restaurant-list-add-panel > div > button > span:not(.loading-spinner)')
  })

  it('places the public user ID directly under the account name and retires profile bios from product UI', () => {
    const profile = source('../../src/components/ProfilePage.tsx')
    const nativeProfile = source('../../ios/TasteMap/TasteMap/Features/Profile/ProfileView.swift')
    const nativeSocial = source('../../ios/TasteMap/TasteMap/Features/Profile/SocialViews.swift')
    expect(profile.indexOf('<h1><span>{user.nickname}</span>')).toBeLessThan(profile.indexOf('profile-user-id--under-name'))
    expect(profile).not.toContain('visibleProfileBio')
    expect(profile).not.toContain('<span>个人简介</span>')
    expect(profile).not.toContain('setBio')
    expect(nativeProfile).toContain('.accessibilityIdentifier("profile-user-id")')
    expect(nativeProfile).not.toContain('.accessibilityIdentifier("profile-bio")')
    expect(nativeProfile).not.toContain('.accessibilityIdentifier("profile-bio-text")')
    expect(nativeSocial).not.toContain('Text([item.profile.city, item.profile.bio]')
    expect(nativeSocial).not.toContain('Text(bio)')
  })

  it('never renders an inert account-deletion control on the iPhone Hybrid path', () => {
    const profile = source('../../src/components/ProfilePage.tsx')
    const shell = source('../../src/hybrid/app/HybridAppShell.tsx')
    expect(profile).toContain('onDeleteAccount?: () => void')
    expect(profile).toContain('onDeleteAccount ? <button onClick={onDeleteAccount}')
    expect(profile).toContain('请在 Taste Map iPhone App 的账户与安全中完成身份验证后删除账户。')
    expect(profile).not.toContain('<button disabled type="button">删除账号</button>')
    expect(shell).toContain('onDeleteAccount={() => void platform.account.openDelete()}')
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
    const browserAdapter = source('../../src/platform/TasteMapBrowserAdapter.ts')
    const mapService = source('../../src/services/mapService.ts')
    const searchRelevance = source('../../src/services/restaurantSearchRelevance.ts')
    const nativeRuntime = source('../../ios/TasteMap/TasteMap/Hybrid/TasteMapHybridRuntime.swift')
    const nativeAcquisitionModel = source('../../ios/TasteMap/TasteMap/Features/Restaurant/RestaurantAcquisitionViewModel.swift')
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
    expect(shared).toContain("'empty'")
    expect(hybrid).toContain("if (state === 'ready') return null")
    expect(hybrid).toContain('state="empty"')
    expect(hybrid).toContain('retryLabel="重新查找"')
    expect(hybrid).toContain('cityEditedRef')
    expect(hybrid).toContain('value.detectedCity')
    expect(hybrid).toContain("replace(/市$/, '')")
    expect(browserAdapter).toContain('resolveCoordinatesLocation(coordinates)')
    expect(mapService).toContain('rankRestaurantSearchMatches(')
    expect(browserAdapter).toContain('rankRestaurantSearchMatches(debugAcquisitionPOIs')
    expect(searchRelevance).toContain('name.includes(compactQuery)')
    expect(searchRelevance).toContain('address.includes(compactQuery)')
    expect(nativeRuntime).toContain('RestaurantSearchRelevancePolicy.rankedMatches(')
    expect(nativeAcquisitionModel).toContain('RestaurantSearchRelevancePolicy.rankedMatches(')
    expect(formalWeb).toContain('nearbyLoading || nearbyError')
    expect(formalWeb).toContain('当前位置 3 公里内没有找到餐厅。')
    expect(formalWeb).toContain('state="empty"')
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
    expect(map).toContain("count: value === 'recommended' && canonicalRecommendations ? canonicalRecommendations.length : scopeCounts[value]")
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

  it('keeps iOS Discovery chrome on the same visual tokens as My Map', () => {
    const sharedCSS = source('../../src/components/tasteMapDiscoveryShared.css')
    const mapCSS = source('../../src/components/myMapBrowsePage.css')
    const shared = source('../../src/components/TasteMapDiscoveryShared.tsx')
    const map = source('../../src/components/MyMapBrowsePage.tsx')
    const discovery = source('../../src/hybrid/app/HybridDiscoveryPage.tsx')
    for (const token of [
      '--tm-browse-title-size', '--tm-browse-title-color', '--tm-browse-tab-height',
      '--tm-browse-tab-size', '--tm-browse-tab-inactive', '--tm-browse-tab-active',
      '--tm-browse-row-gap', '--tm-browse-indicator-height', '--tm-browse-indicator-bottom',
      '--tm-browse-filter-height', '--tm-browse-filter-size', '--tm-browse-filter-icon-size',
      '--tm-browse-filter-text',
      '--tm-browse-divider', '--tm-browse-chrome-background',
    ]) {
      expect(sharedCSS).toContain(`${token}:`)
      expect(sharedCSS).toContain(`var(${token})`)
      if (!token.startsWith('--tm-browse-filter-')) expect(mapCSS).toContain(`var(${token})`)
    }
    expect(sharedCSS).toContain('--tm-browse-chrome-height: 145px')
    expect(mapCSS).toContain('var(--tm-browse-chrome-height)')
    expect(sharedCSS).toMatch(/\.tm-hybrid-page\.tm-hybrid-discovery \{[^}]*padding:\s*0 0 92px/)
    expect(sharedCSS).toMatch(/\.tm-hybrid-discovery \.tm-primary-tab-bar \{[^}]*margin-top:\s*var\(--tm-browse-row-gap\)/)
    expect(sharedCSS).toMatch(/\.tm-hybrid-discovery \.tm-discovery-page__filters \{[^}]*margin-top:\s*var\(--tm-browse-row-gap\)/)
    expect(sharedCSS).toMatch(/\.tm-hybrid-discovery \.tm-discovery-page__header p \{[^}]*position:\s*absolute[^}]*width:\s*1px/)
    expect(sharedCSS).toMatch(/\.tm-browse-filter-bar > button > svg,[^}]*width:\s*var\(--tm-browse-filter-icon-size\);[^}]*height:\s*var\(--tm-browse-filter-icon-size\)/)
    expect(sharedCSS).toMatch(/@media \(max-width: 420px\)[\s\S]*?\.tm-primary-tab-bar button \{ font-size: var\(--tm-browse-tab-size\); \}/)
    expect(sharedCSS).not.toMatch(/@media \(max-width: 420px\)[\s\S]*?\.tm-primary-tab-bar button \{ font-size: 11px; \}/)
    expect(shared).toContain('className="tm-browse-filter-bar tm-shared-filter-bar"')
    expect(map).toContain('className="tm-browse-filter-bar tm-map-filter-bar"')
    expect(map).toContain('label="城市"')
    expect(discovery).toContain('<TasteMapCitySearch city={selectedCity}')
    expect(discovery).toContain("onChange={(value) => setCity(value || 'all')}")
    expect(mapCSS).not.toMatch(/\.tm-map-filter-bar > (?:button|label)[^{]*\{/)
    expect(discovery).not.toContain('<option value="all">全部城市</option>')
    expect(mapCSS).toMatch(/\.tm-my-map__controls \{[^}]*border-bottom:\s*1px solid var\(--tm-browse-divider\)/)
    expect(mapCSS).toMatch(/\.tm-my-map__stage \{[^}]*var\(--tm-browse-chrome-height\)/)
    expect(mapCSS).toMatch(/@media \(max-width: 420px\)[\s\S]*?\.tm-my-map__title-switch \{ font-size: var\(--tm-browse-title-size\); \}/)
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
    expect(hybrid).toContain('TasteMapRecommendationReasons')
    expect(hybrid).toContain('CommunityRatingSummary')
    expect(hybrid).not.toContain('tm-activity-card__source"><')
    expect(hybrid).not.toContain('aria-label="关注用户"')
    expect(hybrid).not.toMatch(/<Send\b/)
    expect(sharedCSS).toMatch(/\.tm-activity-card \{[^}]*border:\s*0[^}]*border-radius:\s*0/)
    expect(sharedCSS).toContain('--tm-activity-photo-size: 178px')
    expect(sharedCSS).toMatch(/\.tm-activity-card__media \{[^}]*width:\s*min\(48%,\s*var\(--tm-activity-photo-size\)\)[^}]*aspect-ratio:\s*1/)
    expect(sharedCSS).toMatch(/\.tm-activity-card\.is-activity > \.tm-activity-card__media\.has-multiple \{[^}]*aspect-ratio:\s*auto/)
    expect(sharedCSS).toMatch(/\.tm-activity-card__recommendation-reasons \{[^}]*flex-wrap:\s*wrap/)
    expect(sharedCSS).toMatch(/\.tm-activity-card__recommendation-reasons > li \{[^}]*width:\s*fit-content;[^}]*border:\s*0;[^}]*border-radius:/)
    expect(sharedCSS).toMatch(/\.tm-activity-card > footer \{[^}]*display:\s*grid;[^}]*grid-template-columns:\s*minmax\(0,\s*1fr\) minmax\(0,\s*1fr\);/)
    expect(sharedCSS).toMatch(/\.tm-activity-card__social \{[^}]*justify-content:\s*flex-start;/)
    expect(sharedCSS).toMatch(/\.tm-activity-card__social button \{[^}]*min-width:\s*var\(--control-min-hit-target\);[^}]*min-height:\s*var\(--control-min-hit-target\);[^}]*border:\s*0;[^}]*border-radius:\s*0;/)
    expect(sharedCSS).toMatch(/\.tm-activity-card__recommendation-reasons > li::before \{ content: none; \}/)
    expect(sharedCSS).not.toMatch(/\.tm-activity-card__body > ul \{[^}]*display:\s*grid/)
    expect(sharedCSS).toMatch(/\.tm-activity-card__restaurant-actions \{[^}]*justify-content:\s*flex-end;/)
    expect(sharedCSS).toMatch(/\.tm-activity-card__restaurant-actions \.restaurant-quick-actions button \{[^}]*width:\s*40px;[^}]*height:\s*40px;/)
    expect(sharedCSS).toMatch(/\.tm-hybrid-discovery \.tm-activity-card\.is-recommendation > footer \{[^}]*border-top:\s*0;/)
    expect(sharedCSS).toMatch(/\.tm-hybrid-discovery \.tm-activity-card\.is-recommendation > footer \.tm-activity-card__social \{[^}]*margin-right:\s*auto;/)
    expect(sharedCSS).toMatch(/\.tm-hybrid-discovery \.tm-activity-card\.is-recommendation > footer \.tm-activity-card__restaurant-actions \{[^}]*margin-left:\s*auto;/)
    expect(sharedCSS).toMatch(/\.tm-discovery-page__content \{[^}]*background:\s*var\(--color-surface/)
    expect(hybridCSS).toMatch(/\.tm-hybrid-discovery \.tm-hybrid-activity-feed \{[^}]*gap:\s*0/)
    const nativeActivitySurface = nativeShared.match(/struct TasteMapActivityCard<[\s\S]*?\n}/)?.[0] ?? ''
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
    expect(shell).toContain('socialStats={detailRestaurant.socialStats}')
  })

  it('keeps shared Hybrid navigation and reads off the repeated cold path', () => {
    const shell = source('../../src/hybrid/app/HybridAppShell.tsx')
    const runtime = source('../../ios/TasteMap/TasteMap/Hybrid/TasteMapHybridRuntime.swift')
    const service = source('../../ios/TasteMap/TasteMap/Hybrid/TasteMapHybridBridgeService.swift')
    expect(shell).toContain('commitLocalRoute(nextRoute, setRoute)')
    const navigation = shell.slice(shell.indexOf('const navigate = useCallback'), shell.indexOf('const refreshReadyData'))
    expect(navigation.indexOf('commitLocalRoute(nextRoute, setRoute)')).toBeLessThan(navigation.indexOf('void platform.navigation.openHybrid'))
    expect(navigation).toContain('void platform.navigation.openHybrid')
    expect(navigation).not.toContain('await platform.navigation')
    expect(navigation).not.toContain('requestAnimationFrame')
    expect(shell).toContain('if (revision !== navigationRevision.current) return')
    expect(shell).toContain('ownedRestaurantPreview(profile, route.id)')
    expect(shell).toContain('contentReady: false')
    expect(shell.indexOf("setBootstrap({ state: 'ready', runtime, profile")).toBeLessThan(shell.indexOf('const result = await contentRequest'))
    expect(shell).toContain('profileWasActivated ? <div className="tm-hybrid-persistent-route"')
    expect(runtime).toContain('private var cachedBridgeService: TasteMapHybridBridgeService?')
    expect(runtime).toContain('private var cachedMapSurfaceResources: TasteMapHybridCachedMapSurfaceResources?')
    expect(service).toContain('if let cached = projectedRestaurantSnapshot?.first')
    expect(service).toContain('associationsByVisitID')
    expect(service).toContain('photosByVisitID')
  })

  it('keeps data refresh and Visit saves out of account bootstrap, with recoverable failures', () => {
    const shell = source('../../src/hybrid/app/HybridAppShell.tsx')
    const dataEvent = shell.slice(shell.indexOf("if (event.name === 'data.changed')"), shell.indexOf("if (event.name === 'app.lifecycle'"))
    const saved = shell.slice(shell.indexOf('onSaved={(restaurantID)'), shell.indexOf('restaurantID={route.surface'))
    for (const block of [dataEvent, saved]) {
      expect(block).not.toContain('setGeneration')
      expect(block).not.toContain("setBootstrap({ state: 'loading' })")
    }
    expect(shell).toContain('refreshHybridSnapshots(platform, {')
    expect(shell).toContain('onProfile: (profile) => setBootstrap')
    expect(shell).toContain('onContent: (content) => setBootstrap')
    expect(saved).not.toContain('refreshReadyData().finally(')
    expect(saved).toContain('const parentRoute = visitParentRoute.current')
    expect(saved).toContain('void navigateBack()')
    expect(saved).toContain('navigate(destination, true)')
    expect(shell).toContain('if (replace) replaceLocalRoute(nextRoute, setRoute)')
    expect(shell).toContain('else commitLocalRoute(nextRoute, setRoute)')
    expect(shell).toContain('{ localTransition: true, replaceCurrent: replace }')
    expect(shell).toContain('const traversed = beginHybridHistoryBack()')
    expect(shell).toContain('Promise.all([platform.navigation.back({ localTransition: true }), traversed])')
    expect(saved).not.toContain("navigate({ surface: 'restaurant'")
    expect(shell).toContain('sequence !== snapshotRefreshSequence.current')
    expect(shell).toContain('重试刷新')
    expect(shell).not.toContain('<ShellState kind="loading" message={routeError')
    const routeProjection = shell.slice(shell.indexOf('function platformRouteToHybrid'))
    expect(routeProjection).not.toContain("if (route.surface === 'visitEdit'")
  })

  it('does not repeat the current similar-taste category on every Restaurant card', () => {
    const discovery = source('../../src/hybrid/app/HybridDiscoveryPage.tsx')
    expect(discovery).not.toContain('近期趋势')
    expect(discovery).toContain("item.mode === 'trending' ? undefined : <CommunityRatingSummary")
    expect(discovery).not.toContain("item.mode === 'similar_taste' ? '同味推荐'")
    expect(discovery).toContain('TasteMapRecommendationReasons')
    expect(source('../../src/components/TasteMapDiscoveryShared.tsx')).toContain('aria-label="推荐理由"')
    expect(discovery).not.toContain('为什么适合你')
    expect(discovery).toContain('const similarTasteSource')
    expect(discovery).toContain('口味相似 {item.similarityPercent}%')
    expect(discovery).toContain('rating={item.activityRating}')
    expect(discovery).not.toContain('identifiesSourceActivity')
  })

  it('locks current-only Profile, Lists, Analytics, Posters and Settings topology', () => {
    const shell = source('../../src/hybrid/app/HybridAppShell.tsx')
    const shellStyles = source('../../src/hybrid/app/hybridShell.css')
    expect(HYBRID_PROFILE_OWNER_MODULES).toEqual([
      '身份与 Premium', '关注 / 粉丝', '去过 / 想去 / 总消费',
      '今天吃什么 / 我的口味档案', '回味', '我的食单', '发现与洞察',
      '右上角设置入口',
    ])
    expect(HYBRID_LIST_SCOPES).toEqual(['我的食单', '公开食单'])
    expect(HYBRID_ANALYTICS_MODES.map((item) => item[1])).toEqual([
      '我的口味档案', '最佳饭搭子', '谁最会种草', '本月回顾', '年度回顾',
    ])
    expect(HYBRID_ANALYTICS_MODULES).toEqual([
      ['data', '数据'], ['poster', '画报'],
    ])
    expect(HYBRID_SETTINGS_SECTIONS).toEqual([
      '账户', '数据与备份', '同步', '隐私与权限', '存储与 Premium', '帮助与关于',
    ])
    expect(source('../../src/components/TasteMapAnalyticsPage.tsx')).toContain('renderAnalysisPosterBlob')
    expect(source('../../src/components/TasteMapPremiumSettingsPages.tsx')).toContain('PremiumBurgerBadge')
    expect(shell).not.toContain('Hybrid 主要功能快捷入口')
    expect(shell).not.toContain('tm-hybrid-profile-shortcuts')
    expect(shellStyles).not.toContain('tm-hybrid-profile-shortcuts')
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

  it('routes Profile people actions to the Native social hub instead of Restaurant discovery', () => {
    const shell = source('../../src/hybrid/app/HybridAppShell.tsx')
    const root = source('../../ios/TasteMap/TasteMap/Hybrid/TasteMapHybridRootView.swift')
    expect(shell).toContain("route: 'socialNative', identifier: section")
    expect(root).toContain('case .socialNative:')
    expect(root).toMatch(/TasteMapHybridNativeSocialRoute\(\s*identifier: route\.identifier,\s*onClose: dismissNativePresentation\s*\)/)
    expect(root).toContain('SocialHubView(')
    expect(root).toContain('collaborationAPI: authServices.socialCollaborationAPI')
    expect(root).not.toContain('case .socialNative:\n            DiscoverHubView()')
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
    expect(shell).toContain('detailRestaurant.editableVisitIDs.includes(visit.id)')
    expect(shell).not.toMatch(/visit\.userId\s*===|CURRENT_USER_ID.*visit/)
  })

  it('keeps the user-photo section free of duplicate Restaurant-level actions', () => {
    const detail = source('../../src/components/RestaurantPreviewCard.tsx')
    expect(detail).not.toContain('map-card__actions')
    expect(detail).not.toContain('<ListPlus')
    expect(detail).not.toContain('<Share2')
    // Lafayette moved the only whole-Restaurant delete to the overview header;
    // it must remain absent from the photo area and preserve ownership checks.
    expect(detail.match(/<Trash2 /g)).toHaveLength(1)
    const overview = detail.split('aria-label="我的到访概览"')[1].split('</header>')[0]
    expect(overview).toContain('!readOnly && onDelete')
    expect(overview).toContain('aria-label="删除餐厅"')
    expect(overview).toContain('<Trash2 aria-hidden="true"')
    expect(detail.match(/data-product-contract="visit-edit-entry"/g)).toHaveLength(1)
  })

  it('keeps Visit restaurant context unframed without removing its content or the named section divider', () => {
    const editor = source('../../src/components/AddVisitModal.tsx')
    const styles = source('../../src/styles/global.css')
    const browser = source('../../src/App.tsx')
    const hybrid = source('../../src/hybrid/app/HybridVisitEditorPage.tsx')
    for (const consumer of [browser, hybrid]) expect(consumer).toContain('<AddVisitModal')
    expect(editor).toContain('<RestaurantSummarySection')
    expect(editor).toContain('className="is-form-summary is-unframed"')
    expect(editor).toContain("initialVisit ? '修改这次到访' : '这次到访'")
    expect(styles).toMatch(/\.restaurant-record-summary\.is-form-summary\.is-unframed\s*\{\s*border:\s*0;\s*\}/)
    expect(styles).toMatch(/\.restaurant-record-form-divider::after\s*\{[^}]*height:\s*1px;/)
    expect(styles).not.toMatch(/\.restaurant-record-summary[^{}]*\{[^}]*(?:display:\s*none|visibility:\s*hidden)/)
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
    expect(discovery).not.toContain('data-community-safety-target')
    expect(discovery).not.toContain('Ellipsis')
    expect(discovery).not.toContain("route: 'socialNative', identifier: item.id")
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
    const quickActions = source('../../src/components/RestaurantQuickActions.tsx')
    const shell = source('../../src/hybrid/app/HybridAppShell.tsx')
    const platform = source('../../src/platform/TasteMapPlatform.ts')
    expect(discovery).toContain('RestaurantQuickActions')
    expect(discovery).toContain('SendIcon')
    for (const icon of ['PlusAction', 'Bookmark', 'Dices']) expect(quickActions).toContain(icon)
    for (const removedIcon of ['NotebookPen', 'Share2']) expect(discovery).not.toContain(removedIcon)
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
    expect(settings).toContain("openNativeSettingsDetail('accountSettings')")
    expect(settings).not.toContain('platform.account.openDelete()')
    expect(settings).not.toMatch(/fake Product|fake product|isPremium\s*=\s*true/)
  })
})

describe('Hybrid forbidden Product patterns', () => {
  it('keeps Restaurant marker centers geographically anchored instead of moving collisions into free slots', () => {
    const map = source('../../src/components/MapView.tsx')
    const mapPriority = source('../../src/components/mapMarkerPriority.ts')
    const mapService = source('../../src/services/amap.ts')
    const nativeMap = source('../../ios/TasteMap/TasteMap/Features/Map/ClusteredRestaurantMapView.swift')
    const nativePresentation = source('../../ios/TasteMap/TasteMap/Features/Map/RestaurantMapPresentation.swift')
    const combined = `${map}\n${mapService}\n${nativeMap}\n${nativePresentation}`
    expect(combined).not.toMatch(/spiderfy|collision dispersion|adjustedCoordinate|spreadCoordinate/i)
    expect(`${combined}\n${mapPriority}`).not.toMatch(/NonOverlappingOffsets|NonOverlapPolicy|firstAvailableOffset|setLayoutOffset/)
    expect(map).not.toContain('.setOffset(')
    expect(map).toContain('position: [restaurant.longitude, restaurant.latitude]')
    expect(map).toContain("anchor: 'center'")
    expect(map).toContain('offset: new AMap.Pixel(0, 0)')
    expect(mapPriority).toContain('markerRegionalGroups')
    expect(nativeMap).toContain('centerOffset = .zero')
    expect(nativeMap).toContain('applyAnchoredMarkerVisibility')
    expect(nativePresentation).toContain('RestaurantMapRegionalGroupingPolicy')
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
    expect(shared).toContain('activityRating ? <div className="tm-activity-card__restaurant-row">')
    expect(shared).toContain('const score = starToTenScore(rating)')
    expect(shared).toContain('scoreColor(score)')
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
