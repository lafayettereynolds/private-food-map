import type { HybridSurface } from '../routes/HybridRouteRegistry'

/**
 * Stable, Lafayette-approved product topology. Route ownership is intentionally
 * broader than bottom navigation: a registered route is not automatically a tab.
 */
export const HYBRID_BOTTOM_NAVIGATION = [
  { surface: 'map', label: '地图' },
  { surface: 'discovery', label: '发现' },
  { surface: 'profile', label: '我的' },
] as const satisfies ReadonlyArray<{ surface: HybridSurface; label: string }>

export const HYBRID_ADD_RESTAURANT_ENTRY = {
  label: '添加餐厅',
  ownerSurface: 'map',
  presentation: 'floatingPrimaryCTA',
  route: 'add',
} as const satisfies {
  label: string
  ownerSurface: HybridSurface
  presentation: 'floatingPrimaryCTA'
  route: HybridSurface
}

export const HYBRID_RESTAURANT_ACQUISITION_CONTRACT = {
  capabilities: ['search', 'nearby', 'share', 'manual'],
  primaryPasteLink: false,
  manualEntryCount: 1,
  candidateDestination: 'canonicalRestaurantDetail',
  bottomNavigationLabels: ['地图', '发现', '我的'],
} as const

export const HYBRID_MAP_PRIMARY_SCOPES = [
  ['visited', '去过'],
  ['wantToGo', '想吃'],
  ['recommended', '推荐'],
] as const

export const HYBRID_DISCOVERY_PRIMARY_TABS = [
  ['following', '关注'],
  ['forYou', '为你推荐'],
  ['similarTaste', '同味之选'],
  ['latest', '最新'],
  ['trending', '趋势'],
] as const

export const HYBRID_RESTAURANT_DETAIL_SECTION_ORDER = [
  'Cover',
  'CityAndState',
  'NameAndActions',
  'Address',
  'CompactBasics',
  'RatingReference',
  'UserPhotos',
  'MyVisitOverview',
  'DownstreamContent',
] as const

export const HYBRID_VISIT_HISTORY_EDIT_CONTRACT = {
  editableVisitEntryCount: 1,
  nonEditableVisitEntryCount: 0,
  ownershipAuthority: 'nativeOwnerScope',
  transitionRoute: 'visitEdit',
  writeOwner: 'existingNativeVisitEditor',
  refreshAfterDismiss: true,
} as const

export const HYBRID_PROFILE_OWNER_MODULES = [
  '身份与 Premium',
  '关注 / 被关注',
  '去过 / 想去 / 总消费',
  '今天吃什么 / 我的口味档案',
  '回味',
  '我的食单',
  '发现与洞察',
  '数据与设置 / 账号与隐私',
] as const

export const HYBRID_LIST_SCOPES = ['我的食单', '公开食单'] as const

export const HYBRID_ANALYTICS_MODES = [
  ['taste', '我的口味档案'],
  ['companion', '最佳饭搭子'],
  ['source', '谁最会种草'],
  ['monthly', '本月回顾'],
  ['annual', '年度回顾'],
] as const

export const HYBRID_SETTINGS_SECTIONS = [
  '账户',
  '数据与备份',
  '同步',
  '隐私与权限',
  '存储与 Premium',
  '帮助与关于',
] as const

export const HYBRID_NATIVE_CAPABILITY_HANDOFFS = [
  'profileEdit',
  'socialNative',
  'visit',
  'visitEdit',
  'restaurantEdit',
  'restaurantDelete',
  'restaurantAddToList',
  'restaurantWantToGo',
  'acquisitionNative',
  'listManage',
  'premiumStore',
  'settingsNative',
] as const
