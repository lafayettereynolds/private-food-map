import { useEffect, useMemo, useState, type DragEvent, type FormEvent } from 'react'
import { useLiveQuery } from 'dexie-react-hooks'
import { Check, GripVertical, ImagePlus, ListPlus, Plus, Save, Search, Trash2, X } from 'lucide-react'
import { db } from '../db/appDb'
import { addRestaurantToList, createRestaurantList, deleteRestaurantList, removeRestaurantFromList, reorderRestaurantListItems, updateRestaurantList, updateRestaurantListItem } from '../db/restaurantLists'
import type { RestaurantListCollection, RestaurantListItem, RestaurantSummary, Visibility } from '../types/domain'
import { ModalShell } from './ModalShell'
import { RestaurantAvatar } from './RestaurantAvatar'
import { fetchPublicRestaurantList } from '../services/socialApi'

export function RestaurantListsSection({ restaurants, editable = true, onSelectRestaurant }: { restaurants: RestaurantSummary[]; editable?: boolean; onSelectRestaurant?: (restaurant: RestaurantSummary) => void }) {
  const lists = useLiveQuery(() => db.restaurantLists.filter((item) => !item.deletedAt && (editable ? item.userId === 'owner' : item.visibility === 'public')).toArray(), [editable]) ?? []
  const items = useLiveQuery(() => db.restaurantListItems.filter((item) => !item.deletedAt).toArray(), []) ?? []
  const [selectedId, setSelectedId] = useState<string | null>(null)
  const [creating, setCreating] = useState(false)
  const selected = lists.find((item) => item.id === selectedId) ?? null
  return <section className="profile-dashboard__section restaurant-lists-section">
    <header><h2>我的食单</h2>{editable ? <button onClick={() => setCreating(true)} type="button"><Plus size={14} />新建</button> : null}</header>
    {lists.length ? <div className="restaurant-list-collection-grid">{lists.map((list) => {
      const listItems = items.filter((item) => item.listId === list.id).sort((a, b) => a.position - b.position)
      return <button key={list.id} onClick={() => setSelectedId(list.id)} type="button"><span><strong>{list.title}</strong><small>{listItems.length} 家餐厅{list.isRanked ? ' · 排名榜单' : ''}</small></span><RestaurantListCover items={listItems} list={list} restaurants={restaurants} /></button>
    })}</div> : <button className="restaurant-list-empty" disabled={!editable} onClick={() => setCreating(true)} type="button"><ListPlus size={20} /><strong>建立第一份食单</strong><small>整理一组餐厅，也记录你自己的观点。</small></button>}
    {creating ? <RestaurantListEditor onClose={() => setCreating(false)} /> : null}
    {selected ? <RestaurantListDetail editable={editable} items={items.filter((item) => item.listId === selected.id)} list={selected} onClose={() => setSelectedId(null)} onSelectRestaurant={onSelectRestaurant} restaurants={restaurants} /> : null}
  </section>
}

export function AddToRestaurantListModal({ restaurant, onClose }: { restaurant: RestaurantSummary; onClose: () => void }) {
  const lists = useLiveQuery(() => db.restaurantLists.filter((item) => item.userId === 'owner' && !item.deletedAt).toArray(), []) ?? []
  const items = useLiveQuery(() => db.restaurantListItems.filter((item) => !item.deletedAt).toArray(), []) ?? []
  const [creating, setCreating] = useState(false)
  const [message, setMessage] = useState('')
  return <ModalShell description="同一家餐厅在同一份食单中只会出现一次。" onClose={onClose} title="加入食单">
    <div className="add-to-restaurant-list"><header><RestaurantAvatar restaurant={restaurant} /><div><strong>{restaurant.name}</strong><small>{restaurant.city} · {restaurant.address}</small></div></header>
      <div>{lists.map((list) => { const existing = items.find((item) => item.listId === list.id && item.restaurantId === restaurant.id); return <button disabled={Boolean(existing)} key={list.id} onClick={() => void addRestaurantToList(list.id, restaurant.id).then(() => setMessage(`已加入「${list.title}」`))} type="button"><span><strong>{list.title}</strong><small>{items.filter((item) => item.listId === list.id).length} 家餐厅</small></span>{existing ? '已加入' : <Plus size={16} />}</button> })}</div>
      <button className="secondary-button" onClick={() => setCreating(true)} type="button"><Plus size={15} />新建食单</button>{message ? <p>{message}</p> : null}
    </div>
    {creating ? <RestaurantListEditor initialRestaurantId={restaurant.id} onClose={() => setCreating(false)} /> : null}
  </ModalShell>
}

export function PublicRestaurantListRoute({ restaurants, onSelectRestaurant }: { restaurants: RestaurantSummary[]; onSelectRestaurant?: (restaurant: RestaurantSummary) => void }) {
  const [listId, setListId] = useState(() => readListIdFromHash())
  const localList = useLiveQuery(() => listId ? db.restaurantLists.get(listId) : undefined, [listId])
  const localItems = useLiveQuery(() => listId ? db.restaurantListItems.where('listId').equals(listId).filter((item) => !item.deletedAt).toArray() : [], [listId]) ?? []
  const [remote, setRemote] = useState<Awaited<ReturnType<typeof fetchPublicRestaurantList>>>(null)
  const [message, setMessage] = useState('')
  useEffect(() => {
    const handleHash = () => setListId(readListIdFromHash())
    window.addEventListener('hashchange', handleHash)
    return () => window.removeEventListener('hashchange', handleHash)
  }, [])
  useEffect(() => {
    setRemote(null); setMessage('')
    if (!listId || localList) return
    fetchPublicRestaurantList(listId).then((result) => setRemote(result)).catch((error: unknown) => setMessage(error instanceof Error ? error.message : '食单加载失败'))
  }, [listId, localList])
  if (!listId) return null
  const list = localList && !localList.deletedAt ? localList : remote ? { ...remote.list, customCoverImageData: null } : null
  const items = localList && !localList.deletedAt ? localItems : remote?.items ?? []
  const remoteRestaurants = remote?.restaurants.map(toListRestaurantSummary) ?? []
  const availableRestaurants = remoteRestaurants.length ? remoteRestaurants : restaurants
  const close = () => { window.history.replaceState(null, '', `${window.location.pathname}${window.location.search}`); setListId(null) }
  const selectRestaurant = (restaurant: RestaurantSummary) => onSelectRestaurant?.(restaurant)
  if (!list) return <ModalShell description={message || '正在读取公开食单…'} onClose={close} title="食单"><div /></ModalShell>
  return <RestaurantListDetail editable={false} items={items} list={list} onClose={close} onSelectRestaurant={selectRestaurant} restaurants={availableRestaurants} />
}

function readListIdFromHash() { return window.location.hash.startsWith('#list=') ? decodeURIComponent(window.location.hash.slice(6)) : null }
function toListRestaurantSummary(restaurant: Pick<RestaurantSummary, 'id' | 'amapPoiId' | 'name' | 'address' | 'city' | 'latitude' | 'longitude' | 'tags' | 'merchantImageUrl' | 'markerEmoji'>): RestaurantSummary {
  return { ...restaurant, userId: 'public', status: 'wantToGo', preferenceLevel: 'normal', overallRating: null, foodRating: null, environmentRating: null, serviceRating: null, valueRating: null, longTermNote: '', pricePerPerson: null, markerType: restaurant.merchantImageUrl ? 'image' : 'emoji', markerImageData: null, markerPhotoId: null, createdAt: '', updatedAt: '', deletedAt: null, visits: [], visitCount: 0, averageRating: null, latestVisitDate: null, latestVisit: null, scoreOutOfTen: null, averagePricePerPerson: null, averageQueueMinutes: null, isRecommendation: true }
}

function RestaurantListEditor({ onClose, initialRestaurantId }: { onClose: () => void; initialRestaurantId?: string }) {
  const [title, setTitle] = useState('')
  const [description, setDescription] = useState('')
  const [visibility, setVisibility] = useState<Visibility>('private')
  const [isRanked, setIsRanked] = useState(false)
  async function submit(event: FormEvent) { event.preventDefault(); const list = await createRestaurantList({ title, description, visibility, isRanked }); if (initialRestaurantId) await addRestaurantToList(list.id, initialRestaurantId); onClose() }
  return <ModalShell description="普通合集不显示名次；排名榜单会按顺序显示 01、02、03。" onClose={onClose} title="新建食单"><form className="restaurant-list-editor" onSubmit={(event) => void submit(event)}><label className="field"><span>食单名称</span><input autoFocus maxLength={60} onChange={(event) => setTitle(event.target.value)} required value={title} /></label><label className="field"><span>简介</span><textarea maxLength={240} onChange={(event) => setDescription(event.target.value)} rows={3} value={description} /></label><div className="restaurant-list-editor__choices"><label><input checked={isRanked} onChange={(event) => setIsRanked(event.target.checked)} type="checkbox" />排名榜单</label><label><span>可见范围</span><select onChange={(event) => setVisibility(event.target.value as Visibility)} value={visibility}><option value="private">仅自己</option><option value="friends">好友</option><option value="public">公开</option></select></label></div><button className="primary-button" type="submit"><Save size={15} />创建食单</button></form></ModalShell>
}

function RestaurantListDetail({ list, items, restaurants, editable, onClose, onSelectRestaurant }: { list: RestaurantListCollection; items: RestaurantListItem[]; restaurants: RestaurantSummary[]; editable: boolean; onClose: () => void; onSelectRestaurant?: (restaurant: RestaurantSummary) => void }) {
  const ordered = useMemo(() => [...items].sort((a, b) => a.position - b.position), [items])
  const [draggedId, setDraggedId] = useState<string | null>(null)
  const [addingRestaurant, setAddingRestaurant] = useState(false)
  const [restaurantQuery, setRestaurantQuery] = useState('')
  const [addMessage, setAddMessage] = useState('')
  const [addingRestaurantId, setAddingRestaurantId] = useState<string | null>(null)
  const restaurantById = useMemo(() => new Map(restaurants.map((item) => [item.id, item])), [restaurants])
  const existingRestaurantIds = useMemo(() => new Set(ordered.map((item) => item.restaurantId)), [ordered])
  const availableRestaurants = useMemo(() => {
    const normalizedQuery = restaurantQuery.trim().toLocaleLowerCase()
    return restaurants
      .filter((restaurant) => !restaurant.deletedAt && !existingRestaurantIds.has(restaurant.id))
      .filter((restaurant) => !normalizedQuery || [restaurant.name, restaurant.city, restaurant.address, ...restaurant.tags].join(' ').toLocaleLowerCase().includes(normalizedQuery))
      .sort((left, right) => (right.latestVisitDate ?? right.updatedAt).localeCompare(left.latestVisitDate ?? left.updatedAt))
      .slice(0, 20)
  }, [existingRestaurantIds, restaurantQuery, restaurants])
  function drop(event: DragEvent, targetId: string) { event.preventDefault(); if (!draggedId || draggedId === targetId) return; const ids = ordered.map((item) => item.id); const from = ids.indexOf(draggedId); const to = ids.indexOf(targetId); ids.splice(to, 0, ids.splice(from, 1)[0]); void reorderRestaurantListItems(list.id, ids); setDraggedId(null) }
  async function chooseCover(file: File | undefined) { if (!file) return; const reader = new FileReader(); reader.onload = () => void updateRestaurantList(list.id, { coverMode: 'custom', customCoverImageData: String(reader.result), customCoverPhotoId: null }); reader.readAsDataURL(file) }
  async function addRestaurant(restaurant: RestaurantSummary) {
    setAddingRestaurantId(restaurant.id)
    setAddMessage('')
    try {
      await addRestaurantToList(list.id, restaurant.id)
      setAddMessage(`已添加「${restaurant.name}」`)
    } catch (error) {
      setAddMessage(error instanceof Error ? error.message : '添加失败，请重试')
    } finally {
      setAddingRestaurantId(null)
    }
  }
  return <ModalShell backdropClassName="restaurant-list-backdrop" description={list.description || `${ordered.length} 家餐厅`} onClose={onClose} size="large" title={list.title}><div className="restaurant-list-detail">
    <RestaurantListCover items={ordered} list={list} restaurants={restaurants} />
    {editable ? <><div className="restaurant-list-detail__toolbar"><button className="is-primary" onClick={() => setAddingRestaurant((current) => !current)} type="button"><Plus size={15} />添加餐厅</button><label><ImagePlus size={15} />自定义封面<input accept="image/*" hidden onChange={(event) => void chooseCover(event.target.files?.[0])} type="file" /></label><button onClick={() => void updateRestaurantList(list.id, { coverMode: 'automatic', customCoverImageData: null, customCoverPhotoId: null })} type="button">自动封面</button><button className="danger-ghost-button" onClick={() => void deleteRestaurantList(list.id).then(onClose)} type="button"><Trash2 size={14} />删除食单</button></div>{addingRestaurant ? <section className="restaurant-list-add-panel"><label><Search size={16} /><input autoFocus onChange={(event) => setRestaurantQuery(event.target.value)} placeholder="搜索我的餐厅" value={restaurantQuery} /></label><div>{availableRestaurants.length ? availableRestaurants.map((restaurant) => <button disabled={addingRestaurantId === restaurant.id} key={restaurant.id} onClick={() => void addRestaurant(restaurant)} type="button"><RestaurantAvatar restaurant={restaurant} /><span><strong>{restaurant.name}</strong><small>{[restaurant.city, restaurant.address].filter(Boolean).join(' · ')}</small></span>{addingRestaurantId === restaurant.id ? <span className="loading-spinner" /> : <Plus size={16} />}</button>) : <p>{restaurants.length === existingRestaurantIds.size ? '当前餐厅已经全部加入这份食单。' : '没有找到匹配的餐厅。'}</p>}</div>{addMessage ? <p className="restaurant-list-add-message"><Check size={14} />{addMessage}</p> : null}</section> : null}</> : null}
    <div className="restaurant-list-detail__items">{ordered.map((item, index) => { const restaurant = restaurantById.get(item.restaurantId); if (!restaurant) return null; return <article draggable={editable} key={item.id} onClick={() => onSelectRestaurant?.(restaurant)} onDragOver={(event) => event.preventDefault()} onDragStart={() => setDraggedId(item.id)} onDrop={(event) => drop(event, item.id)} onKeyDown={(event) => { if ((event.key === 'Enter' || event.key === ' ') && onSelectRestaurant) { event.preventDefault(); onSelectRestaurant(restaurant) } }} role={onSelectRestaurant ? 'button' : undefined} tabIndex={onSelectRestaurant ? 0 : undefined}>{editable ? <GripVertical size={16} /> : null}{list.isRanked ? <b>{String(index + 1).padStart(2, '0')}</b> : null}<RestaurantAvatar restaurant={restaurant} /><div><strong>{restaurant.name}</strong><small>{[restaurant.city, restaurant.address].filter(Boolean).join(' · ')}</small>{editable ? <input defaultValue={item.note} maxLength={160} onBlur={(event) => void updateRestaurantListItem(item.id, { note: event.target.value })} onClick={(event) => event.stopPropagation()} placeholder="写一句入选理由" /> : item.note ? <p>{item.note}</p> : null}</div>{editable ? <button aria-label={`从食单删除 ${restaurant.name}`} onClick={(event) => { event.stopPropagation(); void removeRestaurantFromList(item.id) }} type="button"><X size={15} /></button> : null}</article> })}</div>
    {list.visibility === 'public' ? <p className="restaurant-list-public-url">公开地址：{`${location.origin}${location.pathname}#list=${list.id}`}</p> : null}
  </div></ModalShell>
}

function RestaurantListCover({ list, items, restaurants }: { list: RestaurantListCollection; items: RestaurantListItem[]; restaurants: RestaurantSummary[] }) {
  if (list.coverMode === 'custom' && list.customCoverImageData) return <div className="restaurant-list-cover is-custom"><img alt="" src={list.customCoverImageData} /></div>
  const byId = new Map(restaurants.map((item) => [item.id, item]))
  const covers = items.slice(0, 4).map((item) => byId.get(item.restaurantId)).filter((item): item is RestaurantSummary => Boolean(item))
  return <div className={`restaurant-list-cover count-${Math.min(4, covers.length)}`}>{covers.length ? covers.map((restaurant) => restaurant.merchantImageUrl ? <img alt="" key={restaurant.id} src={restaurant.merchantImageUrl} /> : <span key={restaurant.id}><RestaurantAvatar restaurant={restaurant} /></span>) : <ListPlus size={24} />}</div>
}
