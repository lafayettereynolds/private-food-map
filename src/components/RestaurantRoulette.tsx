import { useMemo, useState, type CSSProperties, type FormEvent } from 'react'
import { ArrowLeft, Check, Dices, MapPin, Plus, RotateCw, Search, Sparkles, X } from 'lucide-react'
import type { RestaurantStatus, RestaurantSummary } from '../types/domain'
import { ModalShell } from './ModalShell'

const MAX_RESTAURANTS = 10
const WHEEL_COLORS = ['#4F6F8C', '#D6A754', '#6F8FA8', '#C96F62', '#608477', '#8B739F', '#7394AE', '#C68C4E', '#7D8FA1', '#B66767']

type RouletteSource = 'temporary' | 'mine'
type RoulettePhase = 'setup' | 'wheel'
type StatusFilter = 'all' | RestaurantStatus

interface RouletteItem {
  id: string
  name: string
  restaurant?: RestaurantSummary
}

export function RestaurantRoulette({ restaurants, selectedRestaurantIds, onSelectedRestaurantIdsChange, onClose, onSelectRestaurant }: {
  restaurants: RestaurantSummary[]
  selectedRestaurantIds: string[]
  onSelectedRestaurantIdsChange: (ids: string[]) => void
  onClose: () => void
  onSelectRestaurant: (restaurant: RestaurantSummary) => void
}) {
  const [source, setSource] = useState<RouletteSource>(selectedRestaurantIds.length ? 'mine' : 'temporary')
  const [phase, setPhase] = useState<RoulettePhase>('setup')
  const [temporaryName, setTemporaryName] = useState('')
  const [temporaryItems, setTemporaryItems] = useState<RouletteItem[]>([])
  const [statusFilter, setStatusFilter] = useState<StatusFilter>('all')
  const [tagFilter, setTagFilter] = useState('all')
  const [search, setSearch] = useState('')
  const [rotation, setRotation] = useState(0)
  const [spinning, setSpinning] = useState(false)
  const [winnerId, setWinnerId] = useState<string | null>(null)
  const [message, setMessage] = useState('')

  const tags = useMemo(() => [...new Set(restaurants.flatMap((restaurant) => restaurant.tags).filter(Boolean))].sort((a, b) => a.localeCompare(b, 'zh-CN')), [restaurants])
  const filteredRestaurants = useMemo(() => {
    const keyword = search.trim().toLocaleLowerCase('zh-CN')
    return restaurants.filter((restaurant) => {
      if (statusFilter !== 'all' && restaurant.status !== statusFilter) return false
      if (tagFilter !== 'all' && !restaurant.tags.includes(tagFilter)) return false
      return !keyword || [restaurant.name, restaurant.city, ...restaurant.tags].some((item) => item.toLocaleLowerCase('zh-CN').includes(keyword))
    })
  }, [restaurants, search, statusFilter, tagFilter])
  const selectedItems = source === 'temporary'
    ? temporaryItems
    : selectedRestaurantIds.flatMap((id) => {
      const restaurant = restaurants.find((item) => item.id === id)
      return restaurant ? [{ id: restaurant.id, name: restaurant.name, restaurant }] : []
    })
  const winner = selectedItems.find((item) => item.id === winnerId) ?? null

  function switchSource(next: RouletteSource) {
    setSource(next)
    setPhase('setup')
    setWinnerId(null)
    setMessage('')
  }

  function addTemporary(event: FormEvent) {
    event.preventDefault()
    const name = temporaryName.trim()
    if (!name) return
    if (temporaryItems.some((item) => item.name.toLocaleLowerCase('zh-CN') === name.toLocaleLowerCase('zh-CN'))) {
      setMessage('这家餐厅已经在轮盘里了。')
      return
    }
    if (temporaryItems.length >= MAX_RESTAURANTS) {
      setMessage('轮盘最多添加 10 家餐厅。')
      return
    }
    setTemporaryItems((items) => [...items, { id: `temporary-${Date.now()}-${items.length}`, name }])
    setTemporaryName('')
    setMessage('')
  }

  function toggleRestaurant(id: string) {
    setMessage('')
    if (selectedRestaurantIds.includes(id)) {
      onSelectedRestaurantIdsChange(selectedRestaurantIds.filter((item) => item !== id))
      return
    }
    if (selectedRestaurantIds.length >= MAX_RESTAURANTS) {
      setMessage('轮盘最多添加 10 家餐厅。')
      return
    }
    onSelectedRestaurantIdsChange([...selectedRestaurantIds, id])
  }

  function addFilteredRestaurants() {
    const additions = filteredRestaurants.filter((restaurant) => !selectedRestaurantIds.includes(restaurant.id)).slice(0, MAX_RESTAURANTS - selectedRestaurantIds.length)
    onSelectedRestaurantIdsChange([...selectedRestaurantIds, ...additions.map((restaurant) => restaurant.id)])
    setMessage(additions.length ? `已加入 ${additions.length} 家符合条件的餐厅。` : '当前结果已经全部加入。')
  }

  function openWheel() {
    if (selectedItems.length < 2) return
    setWinnerId(null)
    setPhase('wheel')
  }

  function spin() {
    if (spinning || selectedItems.length < 2) return
    const winnerIndex = Math.floor(Math.random() * selectedItems.length)
    const segmentAngle = 360 / selectedItems.length
    const targetAngle = 360 - (winnerIndex + 0.5) * segmentAngle
    const nextRotation = Math.ceil(rotation / 360) * 360 + 5 * 360 + targetAngle
    setSpinning(true)
    setWinnerId(null)
    setRotation(nextRotation)
    window.setTimeout(() => {
      setWinnerId(selectedItems[winnerIndex].id)
      setSpinning(false)
    }, 3600)
  }

  const wheelBackground = selectedItems.length ? `conic-gradient(from -90deg, ${selectedItems.map((_, index) => {
    const start = index / selectedItems.length * 100
    const end = (index + 1) / selectedItems.length * 100
    return `${WHEEL_COLORS[index]} ${start}% ${end}%`
  }).join(', ')})` : '#e7edf2'

  return <ModalShell description="临时输入，或从自己的清单挑选；至少 2 家、最多 10 家。" onClose={onClose} size="large" title="今天吃什么">
    <div className="roulette-source-tabs" aria-label="轮盘餐厅来源">
      <button className={source === 'temporary' ? 'is-active' : ''} disabled={phase === 'wheel'} onClick={() => switchSource('temporary')} type="button">临时餐厅</button>
      <button className={source === 'mine' ? 'is-active' : ''} disabled={phase === 'wheel'} onClick={() => switchSource('mine')} type="button">我的餐厅</button>
    </div>

    {phase === 'setup' ? <div className="roulette-live-preview" aria-label={`当前轮盘有 ${selectedItems.length} 家餐厅`}>
      <div className="roulette-wheel-wrap roulette-wheel-wrap--preview"><div className="roulette-pointer" /><div className={`roulette-wheel${selectedItems.length ? '' : ' is-empty'}`} style={{ '--wheel-background': wheelBackground, '--wheel-rotation': '0deg' } as CSSProperties}>{selectedItems.map((item, index) => {
        const angle = (index + 0.5) * 360 / selectedItems.length
        return <span className="roulette-wheel-label" key={item.id} style={{ '--label-angle': `${angle}deg` } as CSSProperties}>{item.name}</span>
      })}<div className="roulette-wheel-center">{selectedItems.length ? <strong>{selectedItems.length}</strong> : <Plus size={22} />}</div></div></div>
      <div><strong>{selectedItems.length ? `${selectedItems.length} 家候选餐厅` : '先添加候选餐厅'}</strong><span>{selectedItems.length < 2 ? '加入两家后即可开始转动' : '轮盘已经可以开始'}</span></div>
    </div> : null}

    {phase === 'setup' ? <div className="roulette-setup">
      {source === 'temporary' ? <>
        <form className="roulette-add-form" onSubmit={addTemporary}><label className="field"><span>餐厅名称</span><div><input autoFocus maxLength={40} onChange={(event) => setTemporaryName(event.target.value)} placeholder="输入后临时加入轮盘" value={temporaryName} /><button disabled={!temporaryName.trim() || temporaryItems.length >= MAX_RESTAURANTS} type="submit"><Plus size={16} /> 加入</button></div></label></form>
        <div className="roulette-picked-list">{temporaryItems.map((item, index) => <div key={item.id}><span>{index + 1}</span><strong>{item.name}</strong><button aria-label={`移除 ${item.name}`} onClick={() => setTemporaryItems((items) => items.filter((current) => current.id !== item.id))} type="button"><X size={14} /></button></div>)}</div>
      </> : <>
        <div className="roulette-filter-group"><span>餐厅状态</span><div>{([['all', '全部'], ['visited', '去过'], ['wantToGo', '想去']] as [StatusFilter, string][]).map(([value, label]) => <button className={statusFilter === value ? 'is-active' : ''} key={value} onClick={() => setStatusFilter(value)} type="button">{label}</button>)}</div></div>
        <div className="roulette-filter-group"><span>菜系 / 标签</span><div className="roulette-tags"><button className={tagFilter === 'all' ? 'is-active' : ''} onClick={() => setTagFilter('all')} type="button">全部</button>{tags.map((tag) => <button className={tagFilter === tag ? 'is-active' : ''} key={tag} onClick={() => setTagFilter(tag)} type="button">{tag}</button>)}</div></div>
        <label className="roulette-search"><Search size={15} /><input onChange={(event) => setSearch(event.target.value)} placeholder="搜索我的餐厅" value={search} /></label>
        <div className="roulette-result-toolbar"><span>找到 {filteredRestaurants.length} 家 · 已选 {selectedRestaurantIds.length}/10</span><button disabled={!filteredRestaurants.length || selectedRestaurantIds.length >= MAX_RESTAURANTS} onClick={addFilteredRestaurants} type="button"><Sparkles size={13} /> 加入当前结果</button></div>
        <div className="roulette-restaurant-list">{filteredRestaurants.map((restaurant) => {
          const selected = selectedRestaurantIds.includes(restaurant.id)
          return <button className={selected ? 'is-selected' : ''} key={restaurant.id} onClick={() => toggleRestaurant(restaurant.id)} type="button"><span>{selected ? <Check size={14} /> : <Plus size={14} />}</span><div><strong>{restaurant.name}</strong><small>{restaurant.status === 'visited' ? '去过' : '想去'}{restaurant.tags.length ? ` · ${restaurant.tags.slice(0, 2).join('、')}` : ''}</small></div></button>
        })}</div>
      </>}
      {message ? <p className="roulette-message" role="status">{message}</p> : null}
      <footer className="roulette-start-bar"><span>{selectedItems.length < 2 ? `再加入 ${2 - selectedItems.length} 家即可开始` : `已准备 ${selectedItems.length} 家餐厅`}</span><button className="primary-button" disabled={selectedItems.length < 2} onClick={openWheel} type="button"><Dices size={17} /> 开始转盘</button></footer>
    </div> : <div className="roulette-wheel-stage">
      <button className="back-button" disabled={spinning} onClick={() => { setPhase('setup'); setWinnerId(null) }} type="button"><ArrowLeft size={15} /> 调整餐厅</button>
      <div className="roulette-wheel-wrap"><div className="roulette-pointer" /><div className="roulette-wheel" style={{ '--wheel-background': wheelBackground, '--wheel-rotation': `${rotation}deg` } as CSSProperties}>{selectedItems.map((item, index) => {
        const angle = (index + 0.5) * 360 / selectedItems.length
        return <span className="roulette-wheel-label" key={item.id} style={{ '--label-angle': `${angle}deg` } as CSSProperties}>{item.name}</span>
      })}<div className="roulette-wheel-center"><Dices size={22} /></div></div></div>
      {winner ? <div className="roulette-winner"><span>今天就吃</span><strong>{winner.name}</strong>{winner.restaurant ? <button className="secondary-button" onClick={() => { onClose(); onSelectRestaurant(winner.restaurant!) }} type="button"><MapPin size={15} /> 在地图查看</button> : null}</div> : <p className="roulette-wheel-hint">{spinning ? '正在替你决定……' : '准备好了，转一次看看。'}</p>}
      <button className="primary-button roulette-spin-button" disabled={spinning} onClick={spin} type="button"><RotateCw className={spinning ? 'spin' : ''} size={18} /> {spinning ? '转动中' : winner ? '再转一次' : '转动轮盘'}</button>
    </div>}
  </ModalShell>
}
