import { useEffect, useState, type ImgHTMLAttributes, type ReactNode } from 'react'
import { resolvePhotoSource } from '../services/photoAssets'

interface SyncedImageProps extends Omit<ImgHTMLAttributes<HTMLImageElement>, 'src'> {
  source: string | null | undefined
  photoId?: string | null
  fallback?: ReactNode
  /** Content covers may advance to the next authorized photo or local illustration. */
  failureFallback?: ReactNode
}

export function SyncedImage({ source, photoId, fallback = null, failureFallback, ...props }: SyncedImageProps) {
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

  if (failed && failureFallback !== undefined) return <>{failureFallback}</>
  if (resolvedSource) return <img {...props} src={resolvedSource} onError={failureFallback === undefined ? props.onError : (event) => { setFailed(true); props.onError?.(event) }} />
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
