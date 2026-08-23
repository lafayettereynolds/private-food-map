import { useEffect, useMemo, useRef, useState, type CSSProperties, type FormEvent } from 'react'
import { Check, MapPin, Plus, RotateCw, Search, Sparkles, Volume2, VolumeX, X } from 'lucide-react'
import type { RestaurantStatus, RestaurantSummary } from '../types/domain'
import { ModalShell } from './ModalShell'
import { RestaurantAvatar } from './RestaurantAvatar'

const MAX_RESTAURANTS = 10
const SPIN_DURATION_MS = 4_200
const WHEEL_COLORS = ['#7893A8', '#8EA7A0', '#D7B77E', '#B9ADC4', '#91AC94', '#D3A58D', '#9CAEBB', '#C6B58C', '#92A7B4', '#B7A3AC']

type StatusFilter = 'all' | RestaurantStatus

export interface RouletteTemporaryCandidate {
  id: string
  name: string
}

interface RouletteItem extends RouletteTemporaryCandidate { restaurant?: RestaurantSummary }

function normalizedName(name: string) {
  return name.trim().toLocaleLowerCase('zh-CN')
}

function shortRestaurantName(name: string) {
  const withoutBranch = name.replace(/[（(][^）)]*[）)]/g, '').trim() || name.trim()
  const characters = [...withoutBranch]
  return characters.length > 7 ? `${characters.slice(0, 7).join('')}…` : withoutBranch
}

export function RestaurantRoulette({ restaurants, selectedRestaurantIds, temporaryItems, onSelectedRestaurantIdsChange, onTemporaryItemsChange, onClose, onSelectRestaurant }: {
  restaurants: RestaurantSummary[]
  selectedRestaurantIds: string[]
  temporaryItems: RouletteTemporaryCandidate[]
  onSelectedRestaurantIdsChange: (ids: string[]) => void
  onTemporaryItemsChange: (items: RouletteTemporaryCandidate[]) => void
  onClose: () => void
  onSelectRestaurant: (restaurant: RestaurantSummary) => void
}) {
  const [temporaryName, setTemporaryName] = useState('')
  const [statusFilter, setStatusFilter] = useState<StatusFilter>('all')
  const [tagFilter, setTagFilter] = useState('all')
  const [search, setSearch] = useState('')
  const [rotation, setRotation] = useState(0)
  const [spinning, setSpinning] = useState(false)
  const [winnerId, setWinnerId] = useState<string | null>(null)
  const [message, setMessage] = useState('')
  const [soundEnabled, setSoundEnabled] = useState(true)
  const audioContextRef = useRef<AudioContext | null>(null)
  const tickTimeoutRef = useRef<number | null>(null)
  const spinTimeoutRef = useRef<number | null>(null)

  const tags = useMemo(() => [...new Set(restaurants.flatMap((restaurant) => restaurant.tags).filter(Boolean))].sort((a, b) => a.localeCompare(b, 'zh-CN')), [restaurants])
  const filteredRestaurants = useMemo(() => {
    const keyword = search.trim().toLocaleLowerCase('zh-CN')
    return restaurants.filter((restaurant) => {
      if (statusFilter !== 'all' && restaurant.status !== statusFilter) return false
      if (tagFilter !== 'all' && !restaurant.tags.includes(tagFilter)) return false
      return !keyword || [restaurant.name, restaurant.city, ...restaurant.tags].some((item) => item.toLocaleLowerCase('zh-CN').includes(keyword))
    })
  }, [restaurants, search, statusFilter, tagFilter])
  const selectedItems = useMemo<RouletteItem[]>(() => {
    const savedItems = selectedRestaurantIds.flatMap((id) => {
      const restaurant = restaurants.find((item) => item.id === id)
      return restaurant ? [{ id: restaurant.id, name: restaurant.name, restaurant }] : []
    })
    return [...savedItems, ...temporaryItems.map((item) => ({ ...item, restaurant: undefined }))]
  }, [restaurants, selectedRestaurantIds, temporaryItems])
  const winner = selectedItems.find((item) => item.id === winnerId) ?? null

  useEffect(() => {
    if (winnerId && !selectedItems.some((item) => item.id === winnerId)) setWinnerId(null)
  }, [selectedItems, winnerId])

  useEffect(() => () => {
    if (tickTimeoutRef.current !== null) window.clearTimeout(tickTimeoutRef.current)
    if (spinTimeoutRef.current !== null) window.clearTimeout(spinTimeoutRef.current)
    if (audioContextRef.current) void audioContextRef.current.close().catch(() => undefined)
  }, [])

  function addTemporary(event: FormEvent) {
    event.preventDefault()
    if (spinning) return
    const name = temporaryName.trim()
    if (!name) {
      setMessage('请输入餐厅名称。')
      return
    }
    if (selectedItems.some((item) => normalizedName(item.name) === normalizedName(name))) {
      setMessage('这家餐厅已经在候选池里了。')
      return
    }
    if (selectedItems.length >= MAX_RESTAURANTS) {
      setMessage('最多选择 10 家餐厅。')
      return
    }
    onTemporaryItemsChange([...temporaryItems, { id: `temporary-${Date.now()}-${temporaryItems.length}`, name }])
    setTemporaryName('')
    setWinnerId(null)
    setMessage('')
  }

  function removeItem(item: RouletteItem) {
    if (spinning) return
    if (item.restaurant) onSelectedRestaurantIdsChange(selectedRestaurantIds.filter((id) => id !== item.id))
    else onTemporaryItemsChange(temporaryItems.filter((current) => current.id !== item.id))
    if (winnerId === item.id) setWinnerId(null)
    setMessage('')
  }

  function toggleRestaurant(restaurant: RestaurantSummary) {
    if (spinning) return
    setMessage('')
    if (selectedRestaurantIds.includes(restaurant.id)) {
      onSelectedRestaurantIdsChange(selectedRestaurantIds.filter((id) => id !== restaurant.id))
      if (winnerId === restaurant.id) setWinnerId(null)
      return
    }
    if (selectedItems.some((item) => normalizedName(item.name) === normalizedName(restaurant.name))) {
      setMessage('这家餐厅已经在候选池里了。')
      return
    }
    if (selectedItems.length >= MAX_RESTAURANTS) {
      setMessage('最多选择 10 家餐厅。')
      return
    }
    onSelectedRestaurantIdsChange([...selectedRestaurantIds, restaurant.id])
    setWinnerId(null)
  }

  function addFilteredRestaurants() {
    if (spinning) return
    const existingNames = new Set(selectedItems.map((item) => normalizedName(item.name)))
    const availableSlots = MAX_RESTAURANTS - selectedItems.length
    const additions = filteredRestaurants
      .filter((restaurant) => !selectedRestaurantIds.includes(restaurant.id) && !existingNames.has(normalizedName(restaurant.name)))
      .slice(0, availableSlots)
    onSelectedRestaurantIdsChange([...selectedRestaurantIds, ...additions.map((restaurant) => restaurant.id)])
    setWinnerId(null)
    setMessage(additions.length ? `已加入 ${additions.length} 家符合条件的餐厅。` : availableSlots ? '当前结果已经全部加入。' : '最多选择 10 家餐厅。')
  }

  function spin() {
    if (spinning || selectedItems.length < 2) return
    const winnerIndex = Math.floor(Math.random() * selectedItems.length)
    const segmentAngle = 360 / selectedItems.length
    const targetAngle = 360 - (winnerIndex + 0.5) * segmentAngle
    const nextRotation = Math.ceil(rotation / 360) * 360 + 5 * 360 + targetAngle
    setSpinning(true)
    setWinnerId(null)
    setMessage('')
    setRotation(nextRotation)
    startSpinAudio()
    spinTimeoutRef.current = window.setTimeout(() => {
      setWinnerId(selectedItems[winnerIndex].id)
      setSpinning(false)
      stopTicking()
      playTone(620, 0.13, 0.035, 'sine')
    }, SPIN_DURATION_MS)
  }

  function clearCandidates() {
    if (spinning || !selectedItems.length) return
    onSelectedRestaurantIdsChange([])
    onTemporaryItemsChange([])
    setWinnerId(null)
    setMessage('')
  }

  function ensureAudioContext() {
    if (!soundEnabled) return null
    const AudioContextConstructor = window.AudioContext || (window as typeof window & { webkitAudioContext?: typeof AudioContext }).webkitAudioContext
    if (!AudioContextConstructor) return null
    audioContextRef.current ??= new AudioContextConstructor()
    void audioContextRef.current.resume().catch(() => undefined)
    return audioContextRef.current
  }

  function playTone(frequency: number, duration: number, volume: number, waveform: OscillatorType = 'sine') {
    const context = ensureAudioContext()
    if (!context || !soundEnabled) return
    try {
      const oscillator = context.createOscillator()
      const gain = context.createGain()
      oscillator.type = waveform
      oscillator.frequency.setValueAtTime(frequency, context.currentTime)
      gain.gain.setValueAtTime(0.0001, context.currentTime)
      gain.gain.exponentialRampToValueAtTime(volume, context.currentTime + 0.008)
      gain.gain.exponentialRampToValueAtTime(0.0001, context.currentTime + duration)
      oscillator.connect(gain).connect(context.destination)
      oscillator.start()
      oscillator.stop(context.currentTime + duration + 0.01)
    } catch {
      // Sound is optional; browser audio restrictions must never block the draw.
    }
  }

  function startSpinAudio() {
    stopTicking()
    if (!soundEnabled) return
    playTone(310, 0.08, 0.025, 'sine')
    const startedAt = performance.now()
    const tick = () => {
      const progress = Math.min(1, (performance.now() - startedAt) / SPIN_DURATION_MS)
      if (progress >= 0.97) return
      playTone(180 + progress * 45, 0.025, 0.014, 'triangle')
      tickTimeoutRef.current = window.setTimeout(tick, 52 + Math.round(progress * progress * 210))
    }
    tickTimeoutRef.current = window.setTimeout(tick, 70)
  }

  function stopTicking() {
    if (tickTimeoutRef.current !== null) window.clearTimeout(tickTimeoutRef.current)
    tickTimeoutRef.current = null
  }

  const wheelBackground = selectedItems.length ? `conic-gradient(from 0deg, ${selectedItems.map((_, index) => {
    const start = index / selectedItems.length * 100
    const end = (index + 1) / selectedItems.length * 100
    return `${WHEEL_COLORS[index]} ${start}% ${end}%`
  }).join(', ')})` : '#e9eef2'

  const wheelStyle = {
    '--wheel-background': wheelBackground,
    '--wheel-rotation': `${rotation}deg`,
    '--spin-duration': `${SPIN_DURATION_MS}ms`,
  } as CSSProperties

  return <ModalShell description="从我的餐厅中挑选，或自定义添加；至少 2 家，最多 10 家。" onClose={onClose} size="large" title="今天吃什么">
    <div className="roulette-layout">
      <section className="roulette-candidate-pool" aria-label={`已选餐厅 ${selectedItems.length} / ${MAX_RESTAURANTS}`}>
        <header><strong>已选餐厅</strong><span>{selectedItems.length} / {MAX_RESTAURANTS}</span><button className="roulette-clear" disabled={!selectedItems.length || spinning} onClick={clearCandidates} type="button">清空</button></header>
        <div className="roulette-candidate-chips">
          {selectedItems.map((item) => <span className="roulette-candidate-chip" key={item.id}>{item.name}<button aria-label={`移除 ${item.name}`} disabled={spinning} onClick={() => removeItem(item)} type="button"><X size={13} /></button></span>)}
          {!selectedItems.length ? <span className="roulette-candidate-empty">从下方选择餐厅，轮盘会立即生成</span> : null}
        </div>
        <p className={selectedItems.length >= 2 ? 'is-ready' : ''}>{selectedItems.length < 2 ? '至少选择 2 家餐厅' : '候选已就绪，可以开始抽取'}</p>
      </section>

      <section className="roulette-wheel-stage" aria-label={`当前轮盘有 ${selectedItems.length} 个扇区`}>
        <div className="roulette-wheel-wrap">
          <button aria-label={soundEnabled ? '关闭转盘声音' : '开启转盘声音'} className="roulette-sound-toggle" onClick={() => { if (soundEnabled) stopTicking(); setSoundEnabled((enabled) => !enabled) }} title={soundEnabled ? '关闭声音' : '开启声音'} type="button">{soundEnabled ? <Volume2 size={15} /> : <VolumeX size={15} />}</button>
          <div className="roulette-pointer" />
          <div className={`roulette-wheel${selectedItems.length ? '' : ' is-empty'}`} style={wheelStyle}>
            {selectedItems.map((item, index) => {
              const angle = (index + 0.5) * 360 / selectedItems.length
              return <span className="roulette-wheel-label" key={item.id} style={{ '--label-angle': `${angle}deg` } as CSSProperties}><span style={{ '--label-upright': `${-(angle + rotation)}deg`, '--spin-duration': `${SPIN_DURATION_MS}ms` } as CSSProperties}>{shortRestaurantName(item.name)}</span></span>
            })}
          </div>
          <button className="roulette-wheel-center" disabled={selectedItems.length < 2 || spinning} onClick={spin} type="button">
            <span>{spinning ? '抽取中' : winner ? '再抽' : '开始'}</span>
          </button>
        </div>
        {winner ? <div className="roulette-winner" role="status">
          <span><Sparkles size={17} /></span>
          <div><small>今天吃</small><strong>{winner.name}</strong></div>
          <div className="roulette-winner__actions"><button disabled={spinning} onClick={spin} type="button"><RotateCw size={14} /> 再抽一次</button>{winner.restaurant ? <button className="is-primary" onClick={() => { onClose(); onSelectRestaurant(winner.restaurant!) }} type="button"><MapPin size={14} /> 查看详情</button> : null}</div>
        </div> : <p className="roulette-wheel-hint">{selectedItems.length < 2 ? '选满两家后，点击轮盘中央开始' : '点击轮盘中央，随机决定今天吃什么'}</p>}
      </section>

      <section className="roulette-picker">
        <header><div><strong>选择餐厅</strong><span>点击餐厅即可加入，再点一次取消</span></div><b>{filteredRestaurants.length} 家</b></header>
        <div className="roulette-picker-tools">
          <label className="roulette-search"><Search size={15} /><input onChange={(event) => setSearch(event.target.value)} placeholder="搜索我的餐厅" value={search} /></label>
          <form className="roulette-add-form" onSubmit={addTemporary}><label><Plus size={15} /><input maxLength={40} onChange={(event) => setTemporaryName(event.target.value)} placeholder="添加自定义餐厅" value={temporaryName} /></label><button disabled={!temporaryName.trim() || selectedItems.length >= MAX_RESTAURANTS || spinning} type="submit">添加</button></form>
        </div>
        <div className="roulette-filter-row">
          <div className="roulette-filter-group"><span>餐厅状态</span><div>{([['all', '全部'], ['visited', '去过'], ['wantToGo', '想吃']] as [StatusFilter, string][]).map(([value, label]) => <button className={statusFilter === value ? 'is-active' : ''} key={value} onClick={() => setStatusFilter(value)} type="button">{label}</button>)}</div></div>
          <div className="roulette-filter-group"><span>菜系 / 标签</span><div className="roulette-tags"><button className={tagFilter === 'all' ? 'is-active' : ''} onClick={() => setTagFilter('all')} type="button">全部</button>{tags.map((tag) => <button className={tagFilter === tag ? 'is-active' : ''} key={tag} onClick={() => setTagFilter(tag)} type="button">{tag}</button>)}</div></div>
        </div>
        <div className="roulette-result-toolbar"><span>最多选择 10 家</span><button disabled={!filteredRestaurants.length || selectedItems.length >= MAX_RESTAURANTS || spinning} onClick={addFilteredRestaurants} type="button"><Sparkles size={13} /> 加入当前结果</button></div>
        <div className="roulette-restaurant-list">{filteredRestaurants.map((restaurant) => {
          const selected = selectedRestaurantIds.includes(restaurant.id)
          return <button aria-pressed={selected} className={selected ? 'is-selected' : ''} disabled={spinning} key={restaurant.id} onClick={() => toggleRestaurant(restaurant)} type="button">
            <RestaurantAvatar restaurant={restaurant} />
            <div><strong>{restaurant.name}</strong><small>{restaurant.status === 'visited' ? '去过' : '想吃'}{restaurant.tags.length ? ` · ${restaurant.tags.slice(0, 2).join('、')}` : ''}{restaurant.city ? ` · ${restaurant.city}` : ''}</small></div>
            <span className="roulette-selection-indicator">{selected ? <Check size={14} /> : null}</span>
          </button>
        })}{!filteredRestaurants.length ? <div className="roulette-list-empty">没有符合当前条件的餐厅</div> : null}</div>
        {message ? <p className="roulette-message" role="status">{message}</p> : null}
      </section>
    </div>
  </ModalShell>
}
