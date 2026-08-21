import { useState, type ChangeEvent } from 'react'
import { ImagePlus, Trash2 } from 'lucide-react'
import { optimizeVisitPhoto } from '../utils/images'
import { SyncedImage } from './SyncedImage'

interface VisitPhotoPickerProps {
  value: string[]
  photoIds: Array<string | null>
  onChange: (value: string[], photoIds: Array<string | null>) => void
}

export function VisitPhotoPicker({ value, photoIds, onChange }: VisitPhotoPickerProps) {
  const [processing, setProcessing] = useState(false)
  const [error, setError] = useState('')

  async function handleFiles(event: ChangeEvent<HTMLInputElement>) {
    const files = [...(event.target.files ?? [])]
    event.target.value = ''
    if (!files.length) return
    setProcessing(true)
    setError('')
    try {
      const images: string[] = []
      for (const file of files) {
        images.push(await optimizeVisitPhoto(file))
      }
      onChange([...value, ...images], [...photoIds, ...images.map(() => null)])
    } catch (imageError) {
      setError(imageError instanceof Error ? imageError.message : '照片处理失败。')
    } finally {
      setProcessing(false)
    }
  }

  return (
    <section className="visit-photo-picker">
      <header><strong>本次照片</strong><small>可选 · 不限张数</small></header>
      <div className="visit-photo-picker__grid">
        {value.map((photo, index) => (
          <figure key={`${index}-${photo.slice(-20)}`}>
            <SyncedImage alt={`本次就餐照片 ${index + 1}`} photoId={photoIds[index]} source={photo} />
            <button aria-label={`删除第 ${index + 1} 张照片`} onClick={() => onChange(value.filter((_, photoIndex) => photoIndex !== index), photoIds.filter((_, photoIndex) => photoIndex !== index))} type="button"><Trash2 size={13} /></button>
          </figure>
        ))}
        <label className="visit-photo-picker__add">
          <ImagePlus size={20} />
          <span>{processing ? '处理中…' : value.length ? '继续添加' : '上传照片'}</span>
          <input accept="image/*" disabled={processing} hidden multiple onChange={handleFiles} type="file" />
        </label>
      </div>
      {error ? <p className="form-error">{error}</p> : null}
    </section>
  )
}
