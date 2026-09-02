import { useMemo, useState } from 'react'
import { Crown, Globe2, Lock, PencilLine, Plus, Share2, Trophy, UserRound } from 'lucide-react'
import type { TasteMapHybridListDTO, TasteMapPlatform } from '../platform/TasteMapPlatform'
import { HybridPageHeader, HybridRestaurantImage, HybridState } from './TasteMapHybridShared'
import { HYBRID_LIST_SCOPES } from '../hybrid/app/HybridProductContracts'

export function TasteMapListsPage({ lists, platform, onOpenRestaurant }: { lists: TasteMapHybridListDTO[]; platform: TasteMapPlatform; onOpenRestaurant: (id: string) => void }) {
  const [scope, setScope] = useState<'mine' | 'public'>('mine')
  const [selectedID, setSelectedID] = useState<string | null>(null)
  const visible = useMemo(() => lists.filter((item) => scope === 'mine' ? item.isOwnedByViewer : item.visibility === 'public'), [lists, scope])
  const selected = lists.find((item) => item.id === selectedID)
  if (selected) return <ListDetail list={selected} onBack={() => setSelectedID(null)} onOpenRestaurant={onOpenRestaurant} platform={platform} />
  return <main className="tm-hybrid-page tm-hybrid-lists">
    <HybridPageHeader description="把餐厅整理成收藏或有顺序的榜单；加入食单不会改变想吃状态。" eyebrow="MY LISTS" title="我的食单" trailing={<button className="tm-hybrid-page-action" onClick={() => void platform.navigation.openNative({ route: 'listManage' })} type="button"><Plus size={17} />新建</button>} />
    <div aria-label="食单范围" className="tm-hybrid-segmented">{HYBRID_LIST_SCOPES.map((label, index) => { const value = index === 0 ? 'mine' : 'public'; return <button aria-pressed={scope === value} key={value} onClick={() => setScope(value)} type="button">{label}</button> })}</div>
    {visible.length ? <section className="tm-hybrid-list-grid">{visible.map((list) => <button className="tm-hybrid-list-card" key={list.id} onClick={() => setSelectedID(list.id)} type="button"><div className="tm-hybrid-list-card__collage">{list.restaurants.slice(0, 4).map((item) => <HybridRestaurantImage image={item.image} key={item.id} name={item.name} />)}{!list.restaurants.length ? <div className="tm-hybrid-image-fallback"><Trophy size={26} /></div> : null}</div><div><span>{list.isRanked ? <><Crown size={14} />榜单</> : <>收藏</>}</span><h2>{list.title}</h2><p>{list.description || '还没有补充食单说明。'}</p><footer><small>{list.restaurantCount} 家餐厅</small><small>{list.visibility === 'public' ? <><Globe2 size={13} />公开</> : list.visibility === 'friends' ? <><UserRound size={13} />好友</> : <><Lock size={13} />仅自己</>}</small></footer></div></button>)}</section> : <HybridState kind="empty" message={scope === 'mine' ? '创建一个收藏或榜单，开始整理自己的餐厅。' : '本地缓存中还没有可见的公开食单。'} title={scope === 'mine' ? '还没有食单' : '暂无公开食单'} action={scope === 'mine' ? <button onClick={() => void platform.navigation.openNative({ route: 'listManage' })} type="button">创建食单</button> : undefined} />}
  </main>
}

function ListDetail({ list, platform, onBack, onOpenRestaurant }: { list: TasteMapHybridListDTO; platform: TasteMapPlatform; onBack: () => void; onOpenRestaurant: (id: string) => void }) {
  return <main className="tm-hybrid-page tm-hybrid-list-detail">
    <button className="tm-hybrid-back" onClick={onBack} type="button">← 返回食单</button>
    <HybridPageHeader description={list.description || `${list.ownerName} 整理的餐厅食单`} eyebrow={list.isRanked ? 'RANKED LIST' : 'COLLECTION'} title={list.title} trailing={<div className="tm-hybrid-inline-actions">{list.isOwnedByViewer ? <button onClick={() => void platform.navigation.openNative({ route: 'listManage', identifier: list.id })} type="button"><PencilLine size={16} />编辑</button> : null}<button onClick={() => void platform.share.open({ title: list.title, text: `${list.ownerName} 的 Taste Map 食单：${list.title}` })} type="button"><Share2 size={16} />分享</button></div>} />
    <div className="tm-hybrid-list-detail__meta"><span>{list.ownerName}</span><span>{list.restaurantCount} 家餐厅</span><span>{list.visibility === 'public' ? '公开' : list.visibility === 'friends' ? '好友可见' : '仅自己'}</span></div>
    {list.restaurants.length ? <ol className={list.isRanked ? 'tm-hybrid-ranked-list' : 'tm-hybrid-collection-list'}>{list.restaurants.map((item, index) => <li key={`${item.id}-${item.position}`}><button onClick={() => onOpenRestaurant(item.id)} type="button">{list.isRanked ? <b>{index + 1}</b> : null}<HybridRestaurantImage image={item.image} name={item.name} /><span><strong>{item.name}</strong><small>{item.city} · {item.address}</small>{item.note ? <em>{item.note}</em> : null}</span></button></li>)}</ol> : <HybridState kind="empty" message="在原生正式编辑流程中添加餐厅；不会隐式修改想吃状态。" title="这份食单还是空的" />}
  </main>
}
