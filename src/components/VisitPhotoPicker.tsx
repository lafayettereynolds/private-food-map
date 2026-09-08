import { useState, type ChangeEvent } from 'react'
import { Camera, Images, LockKeyhole, Sparkles, Trash2 } from 'lucide-react'
import { optimizeVisitPhoto } from '../utils/images'
import { SyncedImage } from './SyncedImage'
import { openPremiumPaywall } from '../services/premiumPaywall'
import { visitPhotoLimit } from '../services/featurePolicy'

interface VisitPhotoPickerProps {
  value: string[]
  photoIds: Array<string | null>
  maxPhotos?: number
  totalPhotoCount?: number
  upgradeAvailable?: boolean
  onChange: (value: string[], photoIds: Array<string | null>) => void
  onPickNative?: (availableSlots: number) => Promise<Array<{ source: string; photoID: string }>>
  onCaptureNative?: () => Promise<{ source: string; photoID: string } | null>
  onRemoveNative?: (photoID: string) => Promise<void>
}

export function VisitPhotoPicker({ value, photoIds, maxPhotos = visitPhotoLimit('free'), totalPhotoCount = value.length, upgradeAvailable = false, onChange, onPickNative, onCaptureNative, onRemoveNative }: VisitPhotoPickerProps) {
  const [processing, setProcessing] = useState(false)
  const [error, setError] = useState('')

  async function handleFiles(event: ChangeEvent<HTMLInputElement>) {
    const files = [...(event.target.files ?? [])]
    event.target.value = ''
    if (!files.length) return
    const availableSlots = Math.max(0, maxPhotos - totalPhotoCount)
    if (!availableSlots) {
      if (upgradeAvailable) {
        openPremiumPaywall('visit_photo_limit')
        setError(`免费版每次到访最多上传 ${maxPhotos} 张照片；开通 Premium 后可继续添加。`)
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
    const availableSlots = Math.max(0, maxPhotos - totalPhotoCount)
    if (!availableSlots || !onPickNative) return
    setProcessing(true)
    setError('')
    try {
      const selected = await onPickNative(availableSlots)
      if (selected.length > availableSlots) {
        // These are newly selected drafts, never retained historical photos.
        await Promise.allSettled(selected.map((photo) => onRemoveNative?.(photo.photoID)))
        throw new Error(`本次最多还可选择 ${availableSlots} 张照片，请重新选择。`)
      }
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

  async function handleNativeCapture() {
    const availableSlots = Math.max(0, maxPhotos - totalPhotoCount)
    if (!availableSlots || !onCaptureNative) return
    setProcessing(true)
    setError('')
    try {
      const captured = await onCaptureNative()
      if (captured) onChange([...value, captured.source], [...photoIds, captured.photoID])
    } catch (photoError) {
      setError(photoError instanceof Error ? photoError.message : '相机没有完成拍摄。')
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
      <header><strong>本次照片</strong><small>{totalPhotoCount} / {maxPhotos} 张</small></header>
      <div className="visit-photo-picker__grid">
        {value.map((photo, index) => (
          <figure key={`${index}-${photo.slice(-20)}`}>
            <SyncedImage alt={`本次就餐照片 ${index + 1}`} photoId={photoIds[index]} source={photo} />
            <button aria-label={`删除第 ${index + 1} 张照片`} disabled={processing} onClick={() => void removePhoto(index)} type="button"><Trash2 size={13} /></button>
          </figure>
        ))}
        {totalPhotoCount < maxPhotos && onCaptureNative ? <button aria-label="拍摄到访照片" className="visit-photo-picker__add" disabled={processing} onClick={() => void handleNativeCapture()} type="button">
          <Camera size={20} />
          <span>{processing ? '处理中…' : '拍照'}</span>
        </button> : null}
        {totalPhotoCount < maxPhotos && onPickNative ? <button aria-label="从照片图库选择" className="visit-photo-picker__add" disabled={processing} onClick={() => void handleNativePick()} type="button">
          <Images size={20} />
          <span>{processing ? '处理中…' : '照片图库'}</span>
        </button> : totalPhotoCount < maxPhotos ? <label className="visit-photo-picker__add">
          <Images size={20} />
          <span>{processing ? '处理中…' : value.length ? '继续添加' : '上传照片'}</span>
          <input accept="image/*" disabled={processing} hidden multiple onChange={handleFiles} type="file" />
        </label> : upgradeAvailable ? <button aria-label="继续添加照片，会员专享" className="visit-photo-picker__add is-premium-limit" onClick={() => openPremiumPaywall('visit_photo_limit')} type="button"><LockKeyhole size={20} /><span>继续添加</span></button> : null}
      </div>
      {upgradeAvailable ? <button className="visit-photo-picker__premium" onClick={() => openPremiumPaywall('visit_photo_limit')} type="button"><Sparkles size={14} /><span>Premium 每次到访可上传 20 张照片</span><b>了解更多</b></button> : null}
      {error ? <p className="form-error">{error}</p> : null}
    </section>
  )
}
