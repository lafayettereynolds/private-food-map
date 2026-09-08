import { readFileSync } from 'node:fs'
import { describe, expect, it } from 'vitest'

const source = (path: string) => readFileSync(new URL(path, import.meta.url), 'utf8')
const native = '../../ios/TasteMap/TasteMap/'

describe('Public Profile authorized taste footprints', () => {
  it('refreshes relationship rows without replacing the presented profile identity', () => {
    const hub = source(`${native}Features/Profile/SocialViews.swift`).split('struct SocialPublicProfileView: View')[0]
    const callback = hub.split('onChange: { changed in')[1].split('}')[0]
    expect(callback).toContain('replace(changed)')
    expect(callback).not.toContain('selectedUser =')
  })
  it('has one footprint heading while preserving the existing sections and real list/map consumers', () => {
    const profile = source(`${native}Features/Profile/SocialViews.swift`)
    expect(profile).toContain('title: "TA 的味觉足迹"')
    expect(profile).not.toContain('Text("去过公开记录")')
    expect(profile).toContain('.init(.visits, title: RestaurantStatus.visited.title, systemImage: RestaurantStatus.visited.systemImage)')
    expect(profile).toContain('.init(.wantToGo, title: RestaurantStatus.wantToGo.title, systemImage: RestaurantStatus.wantToGo.systemImage)')
    expect(profile.match(/items: publicFootprintScopeItems/g)).toHaveLength(2)
    expect(profile).toContain('Label(status.title, systemImage: status.systemImage)')
    expect(profile).not.toContain('"想去"')
    expect(profile).not.toContain('title: "到访"')
    expect(profile).toContain('PublicRestaurantListsSection(')
    expect(profile).toContain('private func publicMapSection(mapHeight: CGFloat)')
    expect(profile).toContain('contentNextCursor = page.nextCursor')
  })

  it('keeps compact count/map entrances and replaces the obsolete bottom overview with the owner’s actual records', () => {
    const profile = source(`${native}Features/Profile/SocialViews.swift`).split('struct SocialPublicProfileView: View')[1]
    const home = profile.split('var body: some View')[1].split('.refreshable')[0]
    expect(home).toContain('footprintEntries')
    expect(home).not.toContain('publicMapSection')
    expect(home).toContain('if communityAPI != nil { publicFootprints }')
    expect(home.indexOf('PublicRestaurantListsSection(')).toBeLessThan(home.indexOf('publicFootprints'))
    expect(home).not.toContain('publicOverview(overview)')
    expect(profile).not.toContain('口味与餐厅证据')
    expect(profile).not.toContain('PUBLIC DINING EVIDENCE')
    expect(profile).not.toContain('Text("代表餐厅")')
    const footprints = profile.split('private var publicFootprints: some View')[1].split('@MainActor')[0]
    expect(footprints).toContain('publicContent')
    expect(footprints).not.toContain('.tasteMapCoreCard')
    expect(profile.match(/\.task\(id: contentSection\)/g)).toHaveLength(1)
    expect(profile).toContain('contentStatistics?.visibleRestaurantCount')
    expect(profile).toContain('contentStatistics?.visibleWantToGoCount')
    expect(profile).toContain('case .footprints: footprintDestination')
    expect(profile).toContain('case .map: publicMapDestination')
    expect(profile).not.toContain('Button("解除好友"')
    expect(profile).toContain('PublicProfileFollowDirection.label(')
    expect(profile).toContain('revision == contentLoadRevision, section == contentSection')
  })

  it('shows direct real list cards without the former public-list wrapper', () => {
    const lists = source(`${native}Features/Lists/RestaurantListsView.swift`)
      .split('struct PublicRestaurantListsSection: View')[1].split('struct PublicRestaurantListDetailView: View')[0]
    expect(lists).not.toContain('Text("公开食单")')
    expect(lists).not.toContain('.padding(16)\n        .tasteMapCoreCard(radius: 20)')
    expect(lists).toContain('PublicProfileListSummaryCard(list: list, photoAPI: photoAPI)')
    expect(lists).toContain('api.profileLists(userID: ownerUserID')
    expect(lists).toContain('PublicRestaurantListDetailView(')
  })

  it('requires concrete restaurant callbacks and connects all public-profile destinations', () => {
    const card = source(`${native}Features/Community/CommunityFeedView.swift`).split('struct PublicContentCard: View')[1]
    expect(card).not.toMatch(/var on(?:RecordVisit|AddToList|AddToRoulette): \(\) -> Void = \{\}/)
    const profile = source(`${native}Features/Profile/SocialViews.swift`)
    expect(profile).toContain('onRecordVisit: { selectedVisitContent = content }')
    expect(profile).toContain('onAddToList: { selectedListContent = content }')
    expect(profile).toContain('onAddToRoulette: { addToRoulette(content) }')
    expect(profile).toContain('.sheet(item: $selectedVisitContent)')
    expect(profile).toContain('.sheet(item: $selectedListContent)')
    expect(profile).toContain('initialRestaurantID: selectedRouletteRestaurantID')
    expect(profile).toContain('among: ownedRestaurants')
  })

  it('shares the compact multi-photo layout and canonical loader without losing the authorized album', () => {
    const card = source(`${native}Features/Community/CommunityFeedView.swift`)
    const media = card.split('struct PublicContentMedia: View')[1].split('struct PublicContentThumbnail: View')[0]
    expect(media).toContain('PublicContentActivityMedia(presentation: .init(item: item)')
    expect(media).not.toContain('PublicContentPhotoTile')
    const presentation = source(`${native}Features/Community/PublicContentMediaPresentation.swift`)
    expect(presentation).toContain('Self.validatedPhotos($0.photos, visitID: $0.id, authorID: $0.ownerUserId)')
    expect(presentation).toContain('RestaurantImagePriorityPolicy.resolution(')
    expect(presentation).toContain('providerMerchantImageURL: merchantURL')
    const gallery = source(`${native}Features/Community/PublicContentPhotoGallery.swift`)
    expect(gallery).toContain('TasteMapRestaurantImage(')
    expect(gallery).toContain('PublicContentPhotoGallery(photos: photos')
    expect(gallery).toContain('PublicContentMediaPresentation.columnCount(photoCount: photos.count)')
    expect(gallery).toContain('Array(photos.prefix(9))')
    expect(gallery).toContain('variant: .display')
    expect(gallery).toContain('这张照片暂时无法查看')
    expect(gallery).not.toMatch(/ShareLink|ImageRenderer|UIImageWriteToSavedPhotosAlbum|PhotoAsset\(/)
  })

  it('keeps social icons unframed and restaurant actions circular with 44-point shared hit targets', () => {
    const controls = source(`${native}Features/Community/CommunityInteractionViews.swift`)
    expect(controls).toContain('private var socialActions: some View')
    expect(controls).toContain('ShareLink(item: shareText)')
    expect(controls).toContain('restaurantActions')
    const actions = source(`${native}Features/Discovery/DiscoveryView.swift`)
      .split('struct DiscoveryRestaurantQuickActions: View')[1].split('private struct DiscoveryRestaurantCard: View')[0]
    expect(actions).not.toContain('.buttonStyle(.bordered')
    expect(actions).toContain('in: Circle()')
    expect(actions).toContain('TasteMapDesignTokens.Control.minimumHitTarget')
    expect(actions).toContain('.accessibilityLabel(title)')
    expect(actions).not.toContain('primary: true')
    expect(actions).not.toContain('circle.hexagongrid')
    expect(actions).not.toContain('circularAction("加入我的食单"')
    expect(actions).toContain('TasteMapDiceActionGlyph()')
    expect(controls.split('struct CommunityInteractionControls')[1].split('private var socialActions')[0]).not.toContain('safetyMenu')
    const card = source(`${native}Features/Community/CommunityFeedView.swift`).split('struct PublicContentCard: View')[1]
    expect(card).toContain('CommunityContentMoreMenu(')
    expect(controls).toContain('Button("加入我的食单", systemImage: "list.number", action: onAddToList)')
  })
})
