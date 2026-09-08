import { useEffect, useMemo, useRef, useState } from 'react'
import { Crown, Globe2, ListPlus, Lock, PencilLine, Plus, Share2, Trophy, UserRound } from 'lucide-react'
import type { TasteMapHybridListDTO, TasteMapPlatform } from '../platform/TasteMapPlatform'
import { HybridBackButton, HybridPageHeader, HybridRestaurantImage, HybridState } from './TasteMapHybridShared'
import { HYBRID_LIST_SCOPES } from '../hybrid/app/HybridProductContracts'
import { validatedListShareURL } from '../platform/restaurantListProjection'
import { useTasteMapListDetail } from './useTasteMapListDetail'

export function HybridProfileListsPreview({ lists, loading = false, onCreate, onOpenList }: {
  lists: TasteMapHybridListDTO[]
  loading?: boolean
  onCreate: () => void
  onOpenList: (id: string) => void
}) {
  const ownedLists = useMemo(() => lists
    .filter((item) => item.isOwnedByViewer)
    .sort((left, right) => right.updatedAt.localeCompare(left.updatedAt)), [lists])
  const previewLists = ownedLists.slice(0, 2)
  return <section className="profile-dashboard__section restaurant-lists-section" data-owned-list-count={ownedLists.length}>
    <header><h2>我的食单</h2><button onClick={onCreate} type="button"><Plus size={14} />新建</button></header>
    {loading
      ? <div aria-label="正在读取食单" className="restaurant-list-preview-loading"><span /><span /></div>
      : previewLists.length
        ? <div className="restaurant-list-collection-grid">{previewLists.map((list) => <button aria-label={`查看食单 ${list.title}，${list.restaurantCount} 家餐厅`} key={list.id} onClick={() => onOpenList(list.id)} type="button"><span><strong>{list.title}</strong><small>{list.restaurantCount} 家餐厅 · {list.visibility === 'public' ? '公开' : list.visibility === 'friends' ? '好友可见' : '仅自己'}</small></span><HybridProfileListCover list={list} /></button>)}</div>
        : <button className="restaurant-list-empty" onClick={onCreate} type="button"><ListPlus size={20} /><strong>建立第一份食单</strong><small>整理一组餐厅，也记录你自己的观点。</small></button>}
  </section>
}

function HybridProfileListCover({ list }: { list: TasteMapHybridListDTO }) {
  const images = list.restaurants.slice(0, 4)
  return <div className={`restaurant-list-cover count-${Math.min(4, images.length)}`}>{images.length
    ? images.map((restaurant) => <HybridRestaurantImage image={restaurant.image} key={restaurant.id} name={restaurant.name} />)
    : <ListPlus size={24} />}</div>
}

export function TasteMapListsPage({ lists, platform, onOpenRestaurant, initialSelectedID, onInitialDetailBack, onBack }: { lists: TasteMapHybridListDTO[]; platform: TasteMapPlatform; onOpenRestaurant: (id: string) => void; initialSelectedID?: string; onInitialDetailBack?: () => void; onBack?: () => void }) {
  const [scope, setScope] = useState<'mine' | 'public'>('mine')
  const [selectedID, setSelectedID] = useState<string | null>(initialSelectedID ?? null)
  useEffect(() => setSelectedID(initialSelectedID ?? null), [initialSelectedID])
  const visible = useMemo(() => lists.filter((item) => scope === 'mine' ? item.isOwnedByViewer : item.visibility === 'public'), [lists, scope])
  const selected = lists.find((item) => item.id === selectedID)
  if (selectedID) return <ListDetail id={selectedID} key={selectedID} seed={selected} onBack={() => initialSelectedID === selectedID && onInitialDetailBack ? onInitialDetailBack() : setSelectedID(null)} onOpenRestaurant={onOpenRestaurant} platform={platform} />
  return <main className="tm-hybrid-page tm-hybrid-lists">
    <HybridBackButton onBack={onBack} />
    <HybridPageHeader description="把餐厅整理成收藏或有顺序的榜单；加入食单不会改变想吃状态。" eyebrow="MY LISTS" title="我的食单" trailing={<button className="tm-hybrid-page-action" onClick={() => void platform.navigation.openNative({ route: 'listManage' })} type="button"><Plus size={17} />新建</button>} />
    <div aria-label="食单范围" className="tm-hybrid-segmented">{HYBRID_LIST_SCOPES.map((label, index) => { const value = index === 0 ? 'mine' : 'public'; return <button aria-pressed={scope === value} key={value} onClick={() => setScope(value)} type="button">{label}</button> })}</div>
    {visible.length ? <section className="tm-hybrid-list-grid">{visible.map((list) => <button className="tm-hybrid-list-card" key={list.id} onClick={() => setSelectedID(list.id)} type="button"><div className="tm-hybrid-list-card__collage">{list.restaurants.slice(0, 4).map((item) => <HybridRestaurantImage image={item.image} key={item.id} name={item.name} />)}{!list.restaurants.length ? <div className="tm-hybrid-image-fallback"><Trophy size={26} /></div> : null}</div><div><span>{list.isRanked ? <><Crown size={14} />榜单</> : <>收藏</>}</span><h2>{list.title}</h2><p>{list.description || '还没有补充食单说明。'}</p><footer><small>{list.restaurantCount} 家餐厅</small><small>{list.visibility === 'public' ? <><Globe2 size={13} />公开</> : list.visibility === 'friends' ? <><UserRound size={13} />好友</> : <><Lock size={13} />仅自己</>}</small></footer></div></button>)}</section> : <HybridState kind="empty" message={scope === 'mine' ? '创建一个收藏或榜单，开始整理自己的餐厅。' : '本地缓存中还没有可见的公开食单。'} title={scope === 'mine' ? '还没有食单' : '暂无公开食单'} action={scope === 'mine' ? <button onClick={() => void platform.navigation.openNative({ route: 'listManage' })} type="button">创建食单</button> : undefined} />}
  </main>
}

function ListDetail({ id, seed, platform, onBack, onOpenRestaurant }: { id: string; seed?: TasteMapHybridListDTO; platform: TasteMapPlatform; onBack: () => void; onOpenRestaurant: (id: string) => void }) {
  const detail = useTasteMapListDetail(id, seed, platform)
  const list = detail.list
  const [shareURL, setShareURL] = useState<string | null>(null)
  const [shareError, setShareError] = useState('')
  const [sharing, setSharing] = useState(false)
  const shareGeneration = useRef(0)
  useEffect(() => {
    ++shareGeneration.current
    setShareURL(null); setShareError(''); setSharing(false)
    return () => { ++shareGeneration.current }
  }, [list?.id, list?.updatedAt, list?.visibility])
  async function createShareLink() {
    if (sharing) return
    const sequence = ++shareGeneration.current
    setSharing(true); setShareError('')
    try {
      if (!platform.lists) throw new Error('当前版本尚未连接食单链接分享。')
      const result = await platform.lists.createShareLink(id)
      if (sequence === shareGeneration.current) setShareURL(validatedListShareURL(result.url))
    } catch (reason) {
      if (sequence === shareGeneration.current) setShareError(reason instanceof Error ? reason.message : '暂时无法生成公开链接。')
    } finally { if (sequence === shareGeneration.current) setSharing(false) }
  }
  if (!list) return <main className="tm-hybrid-page tm-hybrid-list-detail"><HybridBackButton onBack={onBack} /><HybridState kind={detail.error ? 'error' : 'loading'} title={detail.error ? '食单暂时不可用' : '正在读取食单'} message={detail.error || '正在验证这份食单的可见范围。'} action={detail.error ? <button onClick={() => void detail.reload()} type="button">重试</button> : undefined} /></main>
  return <main className="tm-hybrid-page tm-hybrid-list-detail">
    <HybridBackButton onBack={onBack} />
    <HybridPageHeader description={list.description || `${list.ownerName} 整理的餐厅食单`} eyebrow={list.isRanked ? 'RANKED LIST' : 'COLLECTION'} title={list.title} trailing={<div className="tm-hybrid-inline-actions">{list.isOwnedByViewer ? <button onClick={() => void platform.navigation.openNative({ route: 'listManage', identifier: list.id })} type="button"><PencilLine size={16} />编辑</button> : null}<button disabled={sharing} onClick={() => void createShareLink()} type="button"><Share2 size={16} />{sharing ? '正在生成链接' : '分享'}</button></div>} />
    <div className="tm-hybrid-list-detail__meta"><span>{list.ownerName}</span><span>{list.restaurantCount} 家餐厅</span><span>{list.visibility === 'public' ? '公开' : list.visibility === 'friends' ? '好友可见' : '仅自己'}</span></div>
    {shareURL ? <div className="tm-hybrid-inline-actions"><a className="tm-hybrid-page-action" href={shareURL} rel="noreferrer" target="_blank">打开公开链接</a><button onClick={() => void platform.share.open({ title: list.title, url: shareURL }).catch(reason => setShareError(reason instanceof Error ? reason.message : '系统分享不可用，可打开公开链接。'))} type="button">分享链接</button></div> : null}
    {shareError ? <p role="alert">{shareError}</p> : null}
    {detail.error ? <p role="alert">{detail.error}<button className="tm-hybrid-page-action" onClick={() => void detail.reload()} type="button">重新读取</button></p> : null}
    {list.restaurants.length ? <ol className={list.isRanked ? 'tm-hybrid-ranked-list' : 'tm-hybrid-collection-list'}>{list.restaurants.map((item, index) => <li key={`${item.id}-${item.position}`}><button onClick={() => onOpenRestaurant(item.id)} type="button">{list.isRanked ? <b>{index + 1}</b> : null}<HybridRestaurantImage image={item.image} name={item.name} /><span><strong>{item.name}</strong><small>{item.city} · {item.address}</small><small>{item.rating ? `${item.rating.source === 'viewer' ? '我的评分' : '公开评分'} ${item.rating.valueOutOfTen.toFixed(1)} / 10 · ${item.rating.sampleCount} 个评分` : '暂无评分'}</small>{item.note ? <em>{item.note}</em> : null}</span></button></li>)}</ol> : <HybridState kind="empty" message="在原生正式编辑流程中添加餐厅；不会隐式修改想吃状态。" title="这份食单还是空的" />}
    {detail.loading ? <p role="status">正在读取食单…</p> : null}
    {detail.nextCursor ? <button className="tm-hybrid-page-action" disabled={detail.loading} onClick={() => void detail.loadMore()} type="button">继续加载餐厅（已显示 {list.restaurants.length} / {list.restaurantCount} 家）</button> : list.restaurants.length < list.restaurantCount ? <p role="status">已读取 {list.restaurants.length} / {list.restaurantCount} 家餐厅；部分条目暂不可用。</p> : null}
  </main>
}
