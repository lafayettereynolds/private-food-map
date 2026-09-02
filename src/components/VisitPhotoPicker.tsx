import { useState, type ChangeEvent } from 'react'
import { ImagePlus, Sparkles, Trash2 } from 'lucide-react'
import { optimizeVisitPhoto } from '../utils/images'
import { SyncedImage } from './SyncedImage'
import { openPremiumPaywall } from '../services/premiumPaywall'

interface VisitPhotoPickerProps {
  value: string[]
  photoIds: Array<string | null>
  maxPhotos?: number
  upgradeAvailable?: boolean
  onChange: (value: string[], photoIds: Array<string | null>) => void
  onPickNative?: (availableSlots: number) => Promise<Array<{ source: string; photoID: string }>>
  onRemoveNative?: (photoID: string) => Promise<void>
}

export function VisitPhotoPicker({ value, photoIds, maxPhotos = 20, upgradeAvailable = false, onChange, onPickNative, onRemoveNative }: VisitPhotoPickerProps) {
  const [processing, setProcessing] = useState(false)
  const [error, setError] = useState('')

  async function handleFiles(event: ChangeEvent<HTMLInputElement>) {
    const files = [...(event.target.files ?? [])]
    event.target.value = ''
    if (!files.length) return
    const availableSlots = Math.max(0, maxPhotos - value.length)
    if (!availableSlots) {
      if (upgradeAvailable) {
        openPremiumPaywall('visit_photo_limit')
        setError('免费版每次到访最多上传 3 张照片；开通 Premium 后可继续添加。')
        return
      }
      setError(`每次到访最多可上传 ${maxPhotos} 张照片。`)
      return
    }
    setProcessing(true)
    setError('')
    try {
      const images: string[] = []
      for (const file of files.slice(0, availableSlots)) {
        images.push(await optimizeVisitPhoto(file))
      }
      onChange([...value, ...images], [...photoIds, ...images.map(() => null)])
      if (files.length > availableSlots) setError(`已保留前 ${availableSlots} 张；当前账号每次到访最多 ${maxPhotos} 张。`)
    } catch (imageError) {
      setError(imageError instanceof Error ? imageError.message : '照片处理失败。')
    } finally {
      setProcessing(false)
    }
  }

  async function handleNativePick() {
    const availableSlots = Math.max(0, maxPhotos - value.length)
    if (!availableSlots || !onPickNative) return
    setProcessing(true)
    setError('')
    try {
      const selected = await onPickNative(availableSlots)
      onChange(
        [...value, ...selected.map((photo) => photo.source)],
        [...photoIds, ...selected.map((photo) => photo.photoID)],
      )
    } catch (photoError) {
      setError(photoError instanceof Error ? photoError.message : '照片处理失败。')
    } finally {
      setProcessing(false)
    }
  }

  async function removePhoto(index: number) {
    const photoID = photoIds[index]
    if (photoID && onRemoveNative) {
      setProcessing(true)
      setError('')
      try { await onRemoveNative(photoID) }
      catch (photoError) {
        setError(photoError instanceof Error ? photoError.message : '照片没有删除成功。')
        setProcessing(false)
        return
      }
      setProcessing(false)
    }
    onChange(value.filter((_, photoIndex) => photoIndex !== index), photoIds.filter((_, photoIndex) => photoIndex !== index))
  }

  return (
    <section className="visit-photo-picker">
      <header><strong>本次照片</strong><small>{value.length} / {maxPhotos} 张</small></header>
      <div className="visit-photo-picker__grid">
        {value.map((photo, index) => (
          <figure key={`${index}-${photo.slice(-20)}`}>
            <SyncedImage alt={`本次就餐照片 ${index + 1}`} photoId={photoIds[index]} source={photo} />
            <button aria-label={`删除第 ${index + 1} 张照片`} disabled={processing} onClick={() => void removePhoto(index)} type="button"><Trash2 size={13} /></button>
          </figure>
        ))}
        {value.length < maxPhotos && onPickNative ? <button className="visit-photo-picker__add" disabled={processing} onClick={() => void handleNativePick()} type="button">
          <ImagePlus size={20} />
          <span>{processing ? '处理中…' : value.length ? '继续添加' : '上传照片'}</span>
        </button> : value.length < maxPhotos ? <label className="visit-photo-picker__add">
          <ImagePlus size={20} />
          <span>{processing ? '处理中…' : value.length ? '继续添加' : '上传照片'}</span>
          <input accept="image/*" disabled={processing} hidden multiple onChange={handleFiles} type="file" />
        </label> : upgradeAvailable ? <button className="visit-photo-picker__add is-premium-limit" onClick={() => openPremiumPaywall('visit_photo_limit')} type="button"><Sparkles size={20} /><span>继续添加</span></button> : null}
      </div>
      {upgradeAvailable ? <button className="visit-photo-picker__premium" onClick={() => openPremiumPaywall('visit_photo_limit')} type="button"><Sparkles size={14} /><span>Premium 每次到访可上传 20 张照片</span><b>了解更多</b></button> : null}
      {error ? <p className="form-error">{error}</p> : null}
    </section>
  )
}
