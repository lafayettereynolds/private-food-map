import { useContext, useEffect, useMemo, useRef, useState, type CSSProperties, type FormEvent } from 'react'
import { PremiumAccountContext, usePremiumAccess, useResolvedPremiumAccess } from './PremiumAccess'
import { consumeRouletteAllowance, rouletteAllowanceUsed } from '../services/rouletteAllowance'
import { LockKeyhole } from 'lucide-react'
import { openPremiumPaywall } from '../services/premiumPaywall'
import { Check, ChevronRight, Lightbulb, MapPin, Plus, RotateCw, Search, Sparkles, Star, Utensils, Volume2, VolumeX, X } from 'lucide-react'
import type { RestaurantStatus, RestaurantSummary } from '../types/domain'
import { ModalShell } from './ModalShell'
import { RestaurantAvatar } from './RestaurantAvatar'

const MAX_RESTAURANTS = 10
const SPIN_DURATION_MS = 4_200
const WHEEL_COLORS = ['#DCE5ED', '#D7E3DF', '#F0D7B5', '#E3DDE8', '#DEE7DC', '#EADBD2', '#DCE4E8', '#E8E0CF', '#D7E2E8', '#E4DADF']

type StatusFilter = 'all' | RestaurantStatus

export interface RouletteTemporaryCandidate {
  id: string
  name: string
}

interface RouletteItem extends RouletteTemporaryCandidate { restaurant?: RestaurantSummary }

export interface RouletteSessionState {
  rotation: number
  winnerId: string | null
}

const EMPTY_ROULETTE_SESSION: RouletteSessionState = { rotation: 0, winnerId: null }

function normalizedName(name: string) {
  return name.trim().toLocaleLowerCase('zh-CN')
}

function shortRestaurantName(name: string) {
  const withoutBranch = name.replace(/[（(][^）)]*[）)]/g, '').trim() || name.trim()
  const characters = [...withoutBranch]
  return characters.length > 7 ? `${characters.slice(0, 7).join('')}…` : withoutBranch
}

export function RestaurantRoulette({ restaurants, selectedRestaurantIds, temporaryItems, sessionState, onSessionStateChange, onSelectedRestaurantIdsChange, onTemporaryItemsChange, onClose, onSelectRestaurant }: {
  restaurants: RestaurantSummary[]
  selectedRestaurantIds: string[]
  temporaryItems: RouletteTemporaryCandidate[]
  sessionState?: RouletteSessionState
  onSessionStateChange?: (state: RouletteSessionState) => void
  onSelectedRestaurantIdsChange: (ids: string[]) => void
  onTemporaryItemsChange: (items: RouletteTemporaryCandidate[]) => void
  onClose: () => void
  onSelectRestaurant: (restaurant: RestaurantSummary) => void
}) {
  const [temporaryName, setTemporaryName] = useState('')
  const premium = usePremiumAccess()
  const ownerID = useContext(PremiumAccountContext)
  const resolvedPremium = useResolvedPremiumAccess()
  const [dailyLimitReached, setDailyLimitReached] = useState(() => typeof window !== 'undefined' && rouletteAllowanceUsed(window.localStorage, ownerID))
  useEffect(() => {
    const refresh = () => setDailyLimitReached(rouletteAllowanceUsed(window.localStorage, ownerID))
    refresh()
    const timer = window.setInterval(refresh, 60_000)
    return () => window.clearInterval(timer)
  }, [ownerID])
  const [statusFilter, setStatusFilter] = useState<StatusFilter>('all')
  const [search, setSearch] = useState('')
  const [localSessionState, setLocalSessionState] = useState<RouletteSessionState>(EMPTY_ROULETTE_SESSION)
  const [spinning, setSpinning] = useState(false)
  const [message, setMessage] = useState('')
  const [soundEnabled, setSoundEnabled] = useState(true)
  const [managerFocused, setManagerFocused] = useState(false)
  const audioContextRef = useRef<AudioContext | null>(null)
  const tickTimeoutRef = useRef<number | null>(null)
  const spinTimeoutRef = useRef<number | null>(null)
  const managerHighlightTimeoutRef = useRef<number | null>(null)
  const pickerRef = useRef<HTMLElement | null>(null)
  const pickerToolsRef = useRef<HTMLDivElement | null>(null)
  const rouletteSession = sessionState ?? localSessionState
  const { rotation, winnerId } = rouletteSession

  function commitRouletteSession(next: RouletteSessionState) {
    if (!sessionState) setLocalSessionState(next)
    onSessionStateChange?.(next)
  }

  const filteredRestaurants = useMemo(() => {
    const keyword = search.trim().toLocaleLowerCase('zh-CN')
    return restaurants.filter((restaurant) => {
      if (statusFilter !== 'all' && restaurant.status !== statusFilter) return false
      return !keyword || [restaurant.name, restaurant.city, restaurant.address].some((item) => item.toLocaleLowerCase('zh-CN').includes(keyword))
    })
  }, [restaurants, search, statusFilter])
  const selectedItems = useMemo<RouletteItem[]>(() => {
    const savedItems = selectedRestaurantIds.flatMap((id) => {
      const restaurant = restaurants.find((item) => item.id === id)
      return restaurant ? [{ id: restaurant.id, name: restaurant.name, restaurant }] : []
    })
    return [...savedItems, ...temporaryItems.map((item) => ({ ...item, restaurant: undefined }))]
  }, [restaurants, selectedRestaurantIds, temporaryItems])
  const winner = selectedItems.find((item) => item.id === winnerId) ?? null
  const visualSegmentCount = Math.max(1, selectedItems.length)
  const wheelItems = selectedItems

  useEffect(() => {
    if (winnerId && !selectedItems.some((item) => item.id === winnerId)) {
      commitRouletteSession({ ...rouletteSession, winnerId: null })
    }
  }, [selectedItems, winnerId]) // eslint-disable-line react-hooks/exhaustive-deps

  useEffect(() => () => {
    if (tickTimeoutRef.current !== null) window.clearTimeout(tickTimeoutRef.current)
    if (spinTimeoutRef.current !== null) window.clearTimeout(spinTimeoutRef.current)
    if (managerHighlightTimeoutRef.current !== null) window.clearTimeout(managerHighlightTimeoutRef.current)
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
    commitRouletteSession({ ...rouletteSession, winnerId: null })
    setMessage(`已将“${name}”加入候选餐厅。`)
  }

  function removeItem(item: RouletteItem) {
    if (spinning) return
    if (item.restaurant) onSelectedRestaurantIdsChange(selectedRestaurantIds.filter((id) => id !== item.id))
    else onTemporaryItemsChange(temporaryItems.filter((current) => current.id !== item.id))
    if (winnerId === item.id) commitRouletteSession({ ...rouletteSession, winnerId: null })
    setMessage('')
  }

  function toggleRestaurant(restaurant: RestaurantSummary) {
    if (spinning) return
    setMessage('')
    if (selectedRestaurantIds.includes(restaurant.id)) {
      onSelectedRestaurantIdsChange(selectedRestaurantIds.filter((id) => id !== restaurant.id))
      if (winnerId === restaurant.id) commitRouletteSession({ ...rouletteSession, winnerId: null })
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
    commitRouletteSession({ ...rouletteSession, winnerId: null })
  }

  function addFilteredRestaurants() {
    if (spinning) return
    const existingNames = new Set(selectedItems.map((item) => normalizedName(item.name)))
    const availableSlots = MAX_RESTAURANTS - selectedItems.length
    const additions = filteredRestaurants
      .filter((restaurant) => !selectedRestaurantIds.includes(restaurant.id) && !existingNames.has(normalizedName(restaurant.name)))
      .slice(0, availableSlots)
    onSelectedRestaurantIdsChange([...selectedRestaurantIds, ...additions.map((restaurant) => restaurant.id)])
    commitRouletteSession({ ...rouletteSession, winnerId: null })
    setMessage(additions.length ? `已加入 ${additions.length} 家符合条件的餐厅。` : availableSlots ? '当前结果已经全部加入。' : '最多选择 10 家餐厅。')
  }

  function spin() {
    if (spinning || selectedItems.length < 2) return
    if (resolvedPremium === null) { setMessage('正在确认会员状态，请稍后再试。'); return }
    if (!consumeRouletteAllowance(window.localStorage, ownerID, premium)) {
      setDailyLimitReached(true)
      setMessage('今日免费抽选次数已用完，明天再来；Premium 可继续抽选。')
      openPremiumPaywall('roulette_daily_limit')
      return
    }
    if (!premium) setDailyLimitReached(true)
    const winnerIndex = Math.floor(Math.random() * selectedItems.length)
    const segmentAngle = 360 / visualSegmentCount
    const targetAngle = 360 - (winnerIndex + 0.5) * segmentAngle
    const nextRotation = Math.ceil(rotation / 360) * 360 + 5 * 360 + targetAngle
    setSpinning(true)
    commitRouletteSession({ rotation: nextRotation, winnerId: null })
    setMessage('')
    startSpinAudio()
    spinTimeoutRef.current = window.setTimeout(() => {
      commitRouletteSession({ rotation: nextRotation, winnerId: selectedItems[winnerIndex].id })
      setSpinning(false)
      stopTicking()
      playTone(620, 0.13, 0.035, 'sine')
    }, SPIN_DURATION_MS)
  }

  function clearCandidates() {
    if (spinning || !selectedItems.length) return
    onSelectedRestaurantIdsChange([])
    onTemporaryItemsChange([])
    commitRouletteSession(EMPTY_ROULETTE_SESSION)
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

  const wheelBackground = wheelItems.length ? `conic-gradient(from 0deg, ${wheelItems.map((item, index) => {
    const start = index / visualSegmentCount * 100
    const end = (index + 1) / visualSegmentCount * 100
    const color = WHEEL_COLORS[index]
    return `${color} ${start}% calc(${end}% - 0.35%), #fff calc(${end}% - 0.35%) ${end}%`
  }).join(', ')})` : '#F4F1ED'

  const wheelStyle = {
    '--wheel-background': wheelBackground,
    '--wheel-rotation': `${rotation}deg`,
    '--spin-duration': `${SPIN_DURATION_MS}ms`,
  } as CSSProperties

  function scrollToPicker() {
    setManagerFocused(true)
    if (managerHighlightTimeoutRef.current !== null) window.clearTimeout(managerHighlightTimeoutRef.current)
    window.requestAnimationFrame(() => {
      pickerToolsRef.current?.scrollIntoView({ behavior: 'smooth', block: 'center' })
      pickerRef.current?.focus({ preventScroll: true })
    })
    managerHighlightTimeoutRef.current = window.setTimeout(() => setManagerFocused(false), 1_600)
  }

  return <ModalShell description="从我的餐厅中随机挑选一家，帮你决定！" onClose={onClose} size="large" title="今天吃什么">
    <div className="roulette-layout">
      {!premium ? <p role="status">非会员每天可免费抽选 1 次</p> : null}
      <section className="roulette-candidate-pool" aria-label={`已选餐厅 ${selectedItems.length} / ${MAX_RESTAURANTS}`}>
        <header><strong>候选餐厅</strong><span>{selectedItems.length} / {MAX_RESTAURANTS}</span><button className="roulette-clear" disabled={!selectedItems.length || spinning} onClick={clearCandidates} type="button">清空</button></header>
        <div className="roulette-candidate-chips">
          {selectedItems.map((item) => <span className="roulette-candidate-chip" key={item.id}>
            {item.restaurant ? <RestaurantAvatar restaurant={item.restaurant} /> : <span className="roulette-temporary-avatar"><Utensils size={13} /></span>}
            <span>{item.name}</span>
            <button aria-label={`移除 ${item.name}`} disabled={spinning} onClick={() => removeItem(item)} type="button"><X size={13} /></button>
          </span>)}
          {!selectedItems.length ? <span className="roulette-candidate-empty">从下方选择餐厅，轮盘会立即生成</span> : null}
        </div>
      </section>

      <section className="roulette-wheel-stage" aria-label={`当前轮盘有 ${selectedItems.length} 个扇区`} data-roulette-segment-count={selectedItems.length}>
        <p className={`roulette-ready-tip${selectedItems.length >= 2 ? ' is-ready' : ''}`}><span><Lightbulb size={15} /></span>{selectedItems.length < 2 ? '至少选择 2 家餐厅，就可以开始抽选' : '点击转盘中央，随机决定今天去哪家吃吧！'}</p>
        <div className="roulette-wheel-wrap">
          <button aria-label={soundEnabled ? '关闭转盘声音' : '开启转盘声音'} className="roulette-sound-toggle" onClick={() => { if (soundEnabled) stopTicking(); setSoundEnabled((enabled) => !enabled) }} title={soundEnabled ? '关闭声音' : '开启声音'} type="button">{soundEnabled ? <Volume2 size={15} /> : <VolumeX size={15} />}</button>
          <div className="roulette-pointer"><MapPin size={44} strokeWidth={1.7} /></div>
          <div className={`roulette-wheel${selectedItems.length ? '' : ' is-empty'}`} style={wheelStyle}>
            {wheelItems.map((item, index) => {
              const angle = (index + 0.5) * 360 / visualSegmentCount
              return <span className="roulette-wheel-label" key={item.id} style={{ '--label-angle': `${angle}deg` } as CSSProperties}>
                <span className="roulette-wheel-label__content" style={{ '--label-upright': `${-(angle + rotation)}deg`, '--spin-duration': `${SPIN_DURATION_MS}ms` } as CSSProperties}>
                  {item.restaurant ? <RestaurantAvatar restaurant={item.restaurant} /> : <span className="roulette-wheel-temporary-avatar"><Utensils size={16} /></span>}
                  <strong>{shortRestaurantName(item.name)}</strong>
                  <small>{item.restaurant?.city || (item.restaurant ? '我的餐厅' : '临时候选')}</small>
                  {item.restaurant?.scoreOutOfTen != null ? <b><Star size={12} fill="currentColor" /> {item.restaurant.scoreOutOfTen.toFixed(1)}</b> : null}
                </span>
              </span>
            })}
          </div>
          <button className="roulette-wheel-center" disabled={selectedItems.length < 2 || spinning} onClick={spin} type="button">
            <span>{!spinning && !premium && dailyLimitReached ? <LockKeyhole aria-label="今日免费次数已用完，会员可继续" size={16} /> : null}{spinning ? '抽取中' : winner ? '再抽一次' : '开始'}</span><small>{spinning ? '正在转动' : !premium && dailyLimitReached ? '会员继续抽选' : '随机选一家'}</small>
          </button>
        </div>
        {winner ? <div className="roulette-winner" data-roulette-winner-id={winner.id} role="status">
          {winner.restaurant
            ? <span aria-label={`${winner.name}餐厅头像`} className="roulette-winner__avatar" role="img"><RestaurantAvatar restaurant={winner.restaurant} /></span>
            : <span aria-label={`${winner.name}临时候选图标`} className="roulette-winner__avatar roulette-temporary-avatar" role="img"><Utensils size={15} /></span>}
          <div><small>今天吃</small><strong>{winner.name}</strong></div>
          <div className="roulette-winner__actions"><button disabled={spinning} onClick={spin} type="button"><RotateCw size={14} /> 再抽一次</button>{winner.restaurant ? <button className="is-primary" onClick={() => onSelectRestaurant(winner.restaurant!)} type="button"><MapPin size={14} /> 查看详情</button> : null}</div>
        </div> : null}
        <button aria-controls="roulette-candidate-manager" className="roulette-manage-button" onClick={scrollToPicker} type="button"><span><Plus size={20} /></span><div><strong>管理候选餐厅</strong><small>搜索已有餐厅，或输入自定义餐厅名称</small></div><ChevronRight size={22} /></button>
      </section>

      <section className={`roulette-picker${managerFocused ? ' is-targeted' : ''}`} id="roulette-candidate-manager" ref={pickerRef} tabIndex={-1}>
        <header><div><strong>选择餐厅</strong><span>点击餐厅即可加入，再点一次取消</span></div><b>{filteredRestaurants.length} 家</b></header>
        <div className="roulette-picker-tools" data-roulette-candidate-tools="shared" ref={pickerToolsRef}>
          <label className="roulette-search"><Search size={15} /><input aria-label="搜索我的餐厅" onChange={(event) => setSearch(event.target.value)} placeholder="搜索我的餐厅" value={search} /></label>
          <form className="roulette-add-form" data-roulette-custom-candidate="temporary-only" onSubmit={addTemporary}><label><Plus size={15} /><input aria-label="自定义餐厅名称" maxLength={40} onChange={(event) => setTemporaryName(event.target.value)} placeholder="添加自定义餐厅" value={temporaryName} /></label><button aria-label="添加自定义餐厅到候选" disabled={!temporaryName.trim() || selectedItems.length >= MAX_RESTAURANTS || spinning} type="submit">添加</button></form>
        </div>
        <div className="roulette-filter-row">
          <div className="roulette-filter-group"><span>餐厅状态</span><div>{([['all', '全部'], ['visited', '去过'], ['wantToGo', '想吃']] as [StatusFilter, string][]).map(([value, label]) => <button className={statusFilter === value ? 'is-active' : ''} key={value} onClick={() => setStatusFilter(value)} type="button">{label}</button>)}</div></div>
        </div>
        <div className="roulette-result-toolbar"><span>最多选择 10 家</span><button disabled={!filteredRestaurants.length || selectedItems.length >= MAX_RESTAURANTS || spinning} onClick={addFilteredRestaurants} type="button"><Sparkles size={13} /> 加入当前结果</button></div>
        <div className="roulette-restaurant-list">{filteredRestaurants.map((restaurant) => {
          const selected = selectedRestaurantIds.includes(restaurant.id)
          return <button aria-label={`${selected ? '移除' : '加入'}候选餐厅 ${restaurant.name}`} aria-pressed={selected} className={selected ? 'is-selected' : ''} disabled={spinning} key={restaurant.id} onClick={() => toggleRestaurant(restaurant)} type="button">
            <RestaurantAvatar restaurant={restaurant} />
            <div><strong>{restaurant.name}</strong><small>{restaurant.status === 'visited' ? '去过' : '想吃'}{restaurant.city ? ` · ${restaurant.city}` : ''}</small></div>
            <span className="roulette-selection-indicator">{selected ? <Check size={14} /> : null}</span>
          </button>
        })}{!filteredRestaurants.length ? <div className="roulette-list-empty">没有符合当前条件的餐厅</div> : null}</div>
        {message ? <p className="roulette-message" role="status">{message}</p> : null}
      </section>
    </div>
  </ModalShell>
}
