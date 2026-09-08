import { useRef, useState } from 'react'
import { ImagePlus, SmilePlus } from 'lucide-react'
import type { TasteMapPhotoPickItemDTO, TasteMapPlatform, TasteMapRestaurantDetailViewModel } from '../platform/TasteMapPlatform'
import { HybridRestaurantImage } from './TasteMapHybridShared'
import { ModalShell } from './ModalShell'

const QUICK_EMOJIS = ['🍜', '🍣', '🍕', '🥟', '🍔', '🥩', '🍰', '☕️', '🌶️', '🧑🏽‍🍳']

export function RestaurantAvatarEditorSheet({
  detail,
  onClose,
  onSaved,
  platform,
}: {
  detail: TasteMapRestaurantDetailViewModel
  onClose: () => void
  onSaved: (next: TasteMapRestaurantDetailViewModel) => void | Promise<void>
  platform: TasteMapPlatform
}) {
  const [mode, setMode] = useState<'choice' | 'emoji' | 'photo'>('choice')
  const [emoji, setEmoji] = useState(detail.restaurant.markerEmoji || '🍽️')
  const [pendingPhoto, setPendingPhoto] = useState<TasteMapPhotoPickItemDTO | null>(null)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')
  const consumedPhoto = useRef(false)
  const initialScrollPosition = useRef(typeof window === 'undefined' ? null : { x: window.scrollX, y: window.scrollY })

  const finishClose = () => {
    const position = initialScrollPosition.current
    onClose()
    if (!position || typeof window === 'undefined') return
    const restore = () => window.scrollTo(position.x, position.y)
    window.requestAnimationFrame(restore)
    window.setTimeout(restore, 350)
  }

  const discardPendingPhoto = async () => {
    if (!pendingPhoto || consumedPhoto.current) return
    await platform.photo.discard(pendingPhoto.photoID).catch(() => undefined)
    setPendingPhoto(null)
  }

  const close = async () => {
    if (busy) return
    await discardPendingPhoto()
    finishClose()
  }

  const pickPhoto = async () => {
    if (busy) return
    setBusy(true)
    setError('')
    try {
      await discardPendingPhoto()
      const selected = (await platform.photo.pick(1)).photos[0]
      if (!selected) return
      setPendingPhoto(selected)
      setMode('photo')
    } catch {
      setError('没有成功读取这张图片，请重新选择。')
    } finally {
      setBusy(false)
    }
  }

  const save = async () => {
    if (busy) return
    const normalizedEmoji = normalizeSingleEmoji(emoji)
    if (mode === 'emoji' && !normalizedEmoji) {
      setError('请输入一个 iOS 表情，可以使用肤色、旗帜或组合表情。')
      return
    }
    if (mode === 'photo' && !pendingPhoto) {
      setError('请先选择一张图片。')
      return
    }
    setBusy(true)
    setError('')
    try {
      await platform.restaurant.setAvatar(
        detail.restaurant.id,
        mode === 'photo'
          ? { kind: 'photo', photoID: pendingPhoto!.photoID }
          : { kind: 'emoji', emoji: normalizedEmoji! },
      )
      consumedPhoto.current = mode === 'photo'
      const next = await platform.restaurant.get(detail.restaurant.id)
      await platform.haptics.selection()
      await onSaved(next)
      finishClose()
    } catch {
      setError('餐厅头像没有保存成功，请重试。')
    } finally {
      setBusy(false)
    }
  }

  return <ModalShell
    backdropClassName="restaurant-avatar-editor-backdrop"
    description="上传一张自己的图片，或输入任意一个 iOS 表情。修改后会同步用于地图和餐厅列表。"
    onClose={() => void close()}
    size="small"
    title="修改餐厅头像"
  >
    <div className="restaurant-avatar-editor">
      {mode === 'choice' ? <div className="restaurant-avatar-editor__choices">
        <button aria-label="上传图片" disabled={busy} onClick={() => void pickPhoto()} type="button">
          <span><ImagePlus aria-hidden="true" size={24} /></span>
          <strong>上传图片</strong>
          <small>从 iOS 照片中选择一张</small>
        </button>
        <button aria-label="使用表情" disabled={busy} onClick={() => { setMode('emoji'); setError('') }} type="button">
          <span><SmilePlus aria-hidden="true" size={24} /></span>
          <strong>使用表情</strong>
          <small>支持任意 iOS Emoji</small>
        </button>
      </div> : null}

      {mode === 'photo' && pendingPhoto ? <div className="restaurant-avatar-editor__photo">
        <div><HybridRestaurantImage image={pendingPhoto.preview} name={detail.restaurant.name} /></div>
        <p>图片会裁成圆形头像，原图比例不会被拉伸。</p>
      </div> : null}

      {mode === 'emoji' ? <div className="restaurant-avatar-editor__emoji">
        <label>
          <span>输入一个表情</span>
          <input
            aria-label="餐厅头像表情"
            autoComplete="off"
            autoFocus
            inputMode="text"
            maxLength={32}
            onChange={(event) => { setEmoji(event.target.value); setError('') }}
            value={emoji}
          />
        </label>
        <p>可切换到 iOS 表情键盘；肤色、旗帜和家庭等组合表情也支持。</p>
        <div aria-label="常用餐厅表情" className="restaurant-avatar-editor__emoji-grid">
          {QUICK_EMOJIS.map((value) => <button
            aria-label={`使用表情 ${value}`}
            key={value}
            onClick={() => {
              setEmoji(value)
              setError('')
              if (document.activeElement instanceof HTMLElement) document.activeElement.blur()
            }}
            type="button"
          >{value}</button>)}
        </div>
      </div> : null}

      {error ? <p className="restaurant-avatar-editor__error" role="alert">{error}</p> : null}
      {mode !== 'choice' ? <div className="restaurant-avatar-editor__actions">
        <button disabled={busy} onClick={() => { setMode('choice'); setError(''); void discardPendingPhoto() }} type="button">返回选择</button>
        <button aria-busy={busy} className="is-primary" disabled={busy} onClick={() => void save()} type="button">{busy ? '正在保存…' : '保存头像'}</button>
      </div> : null}
    </div>
  </ModalShell>
}

function normalizeSingleEmoji(input: string) {
  const value = input.trim()
  if (!value || value.length > 32 || !/\p{Emoji}/u.test(value)) return null
  type Segmenter = { segment(value: string): Iterable<unknown> }
  type SegmenterConstructor = new (locale: string, options: { granularity: 'grapheme' }) => Segmenter
  const Segmenter = (Intl as unknown as { Segmenter?: SegmenterConstructor }).Segmenter
  if (Segmenter && Array.from(new Segmenter('zh-CN', { granularity: 'grapheme' }).segment(value)).length !== 1) return null
  return value
}
