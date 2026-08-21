import { useEffect, useState, type ImgHTMLAttributes, type ReactNode } from 'react'
import { resolvePhotoSource } from '../services/photoAssets'

interface SyncedImageProps extends Omit<ImgHTMLAttributes<HTMLImageElement>, 'src'> {
  source: string | null | undefined
  photoId?: string | null
  fallback?: ReactNode
}

export function SyncedImage({ source, photoId, fallback = null, ...props }: SyncedImageProps) {
  const [resolvedSource, setResolvedSource] = useState<string | null>(() => (
    source && !source.startsWith('drive-photo:') ? source : null
  ))
  const [failed, setFailed] = useState(false)
  const [retryKey, setRetryKey] = useState(0)

  useEffect(() => {
    let active = true
    setFailed(false)
    void resolvePhotoSource(source, photoId)
      .then((resolved) => {
        if (active) setResolvedSource(resolved)
      })
      .catch(() => {
        if (active) {
          setResolvedSource(null)
          setFailed(true)
        }
      })
    return () => { active = false }
  }, [source, photoId, retryKey])

  if (resolvedSource) return <img {...props} src={resolvedSource} />
  if (failed) {
    return (
      <span
        className="photo-retry"
        onClick={(event) => { event.preventDefault(); event.stopPropagation(); setRetryKey((value) => value + 1) }}
        onKeyDown={(event) => { if (event.key === 'Enter' || event.key === ' ') setRetryKey((value) => value + 1) }}
        role="button"
        tabIndex={0}
      >
        <span>图片未加载</span><small>重新加载</small>
      </span>
    )
  }
  return <>{fallback}</>
}
