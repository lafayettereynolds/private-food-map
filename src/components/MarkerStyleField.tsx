import { useRef, useState, type ChangeEvent } from 'react'
import { ImageIcon, Smile, Upload, X } from 'lucide-react'
import type { MarkerType } from '../types/domain'
import { optimizeMarkerImage } from '../utils/images'
import { SyncedImage } from './SyncedImage'

const EMOJIS = ['🍽️', '🍜', '🍣', '🍲', '🥩', '🍔', '🍕', '☕', '🍰', '🥟', '🌮', '🍷']

interface MarkerStyleFieldProps {
  markerType: MarkerType
  markerImageData: string | null
  markerPhotoId?: string | null
  merchantImageUrl: string | null
  markerEmoji: string
  onTypeChange: (value: MarkerType) => void
  onImageChange: (value: string | null) => void
  onEmojiChange: (value: string) => void
}

export function MarkerStyleField({
  markerType,
  markerImageData,
  markerPhotoId,
  merchantImageUrl,
  markerEmoji,
  onTypeChange,
  onImageChange,
  onEmojiChange,
}: MarkerStyleFieldProps) {
  const inputRef = useRef<HTMLInputElement>(null)
  const [error, setError] = useState('')
  const imageSource = markerImageData || merchantImageUrl

  async function handleFile(event: ChangeEvent<HTMLInputElement>) {
    const file = event.target.files?.[0]
    event.target.value = ''
    if (!file) return
    setError('')
    try {
      onImageChange(await optimizeMarkerImage(file))
      onTypeChange('image')
    } catch (imageError) {
      setError(imageError instanceof Error ? imageError.message : '图片处理失败。')
    }
  }

  return (
    <fieldset className="marker-style-field">
      <legend>地图上的样子</legend>
      <div className="marker-type-tabs">
        <button className={markerType === 'image' ? 'is-active' : ''} onClick={() => onTypeChange('image')} type="button"><ImageIcon size={15} /> 图片</button>
        <button className={markerType === 'emoji' ? 'is-active' : ''} onClick={() => onTypeChange('emoji')} type="button"><Smile size={15} /> 表情</button>
      </div>

      {markerType === 'image' ? (
        <div className="marker-image-picker">
          <div className="marker-image-preview">
            {imageSource || markerPhotoId ? <SyncedImage alt="地图标记预览" photoId={markerPhotoId} source={imageSource} /> : <ImageIcon size={22} />}
          </div>
          <div>
            <strong>{markerImageData ? '使用你的图片' : merchantImageUrl ? '使用商家图片' : '还没有图片'}</strong>
            <p>上传后优先使用你的图片；未上传时会使用高德提供的商家图片。</p>
            <div className="marker-image-actions">
              <button className="secondary-button" onClick={() => inputRef.current?.click()} type="button"><Upload size={14} /> 上传图片</button>
              {markerImageData ? <button className="plain-icon-button" aria-label="移除上传图片" onClick={() => onImageChange(null)} type="button"><X size={15} /></button> : null}
            </div>
          </div>
          <input accept="image/*" hidden onChange={handleFile} ref={inputRef} type="file" />
        </div>
      ) : (
        <div className="emoji-picker">
          {EMOJIS.map((emoji) => (
            <button className={markerEmoji === emoji ? 'is-active' : ''} key={emoji} onClick={() => onEmojiChange(emoji)} type="button">{emoji}</button>
          ))}
        </div>
      )}
      {error ? <p className="form-error">{error}</p> : null}
    </fieldset>
  )
}
