import { useEffect, useMemo, useState } from 'react'
import { createPortal } from 'react-dom'
import { Images, MoreHorizontal } from 'lucide-react'
import { resolveTasteMapPlatform } from '../platform/tasteMapPlatformResolver'
import { notifyPhotoDeleted, PHOTO_DELETED_EVENT, photoWasDeleted } from '../services/photoDeletionEvents'
import { ModalShell } from './ModalShell'
import { SyncedImage } from './SyncedImage'
import './restaurantUserPhotos.css'

type Photo = { source: string; photoId?: string | null }

/** One preview and owner-only action surface for every Restaurant summary. */
export function RestaurantUserPhotos({ restaurantID, restaurantName, photos }: {
  restaurantID: string; restaurantName: string; photos: Photo[]
}) {
  const [selected, setSelected] = useState<Photo | null>(null)
  const [allowed, setAllowed] = useState<string[]>([])
  const [more, setMore] = useState(false)
  const [confirming, setConfirming] = useState(false)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')
  const [, refresh] = useState(0)
  const platform = useMemo(() => typeof window === 'undefined' ? null : resolveTasteMapPlatform(), [])
  const visible = photos.filter(photo => !photoWasDeleted(photo.photoId))
  const close = () => { if (!busy) { setSelected(null); setMore(false); setConfirming(false); setError('') } }
  useEffect(() => {
    // A pull/visibility refresh can remove the open image on another device.
    // Do not keep a detached preview alive after its source leaves the album.
    if (selected && !visible.some(photo => selected.photoId ? photo.photoId === selected.photoId : photo.source === selected.source)) {
      setSelected(null); setMore(false); setConfirming(false)
    }
  }, [selected, visible])
  useEffect(() => {
    const changed = () => refresh(value => value + 1)
    window.addEventListener(PHOTO_DELETED_EVENT, changed)
    return () => window.removeEventListener(PHOTO_DELETED_EVENT, changed)
  }, [])
  useEffect(() => {
    let active = true
    setAllowed([])
    if (selected && platform) {
      void platform.restaurant.get(restaurantID).then(detail => {
        if (active) setAllowed(detail.deletablePhotoIDs ?? [])
      }).catch(() => { /* Missing authority never exposes a destructive control. */ })
    }
    const subscription = platform?.events.subscribe(event => {
      if (event.name === 'auth.changed') { active = false; setAllowed([]); setSelected(null) }
    })
    return () => { active = false; void subscription?.then(handle => handle.remove()).catch(() => undefined) }
  }, [platform, restaurantID, selected])
  const canDelete = Boolean(selected?.photoId && allowed.some(id => id.toLowerCase() === selected.photoId!.toLowerCase()))
  async function remove() {
    if (!selected?.photoId || !canDelete || !platform || busy) return
    setBusy(true); setError('')
    try {
      const id = selected.photoId
      await platform.photo.discard(id)
      notifyPhotoDeleted(id)
      setSelected(null); setConfirming(false); setMore(false)
    } catch (error) {
      setError(error instanceof Error ? error.message : '照片未能删除，请重试。')
    } finally { setBusy(false) }
  }
  return <>
    <section className="restaurant-user-photos" aria-label="用户实拍" data-summary-module="user-photos">
      <header><strong><Images size={14} /> 用户实拍</strong><span>{visible.length ? `${visible.length} 张` : '暂无实拍'}</span></header>
      {visible.length ? <div>{visible.slice(0, 4).map((photo, index) => <button type="button" key={photo.photoId ?? photo.source}
        aria-label={`查看${restaurantName}用户实拍 ${index + 1}`} onClick={() => setSelected(photo)}>
        <SyncedImage alt={`${restaurantName} 用户实拍 ${index + 1}`} photoId={photo.photoId} source={photo.source} loading="lazy" />
      </button>)}</div> : <p>暂时还没有用户分享的照片。</p>}
    </section>
    {selected && typeof document !== 'undefined' ? createPortal(<ModalShell title="照片" eyebrow={null} onClose={close} dismissDisabled={busy}>
      <div className="restaurant-photo-preview">
        <SyncedImage alt={`${restaurantName} 用户实拍`} photoId={selected.photoId} source={selected.source} />
        <nav aria-label="浏览照片">{visible.length > 1 ? visible.map((photo, index) => <button key={photo.photoId ?? photo.source}
          className="secondary-button" type="button" disabled={busy} aria-current={selected === photo ? 'true' : undefined} onClick={() => { setSelected(photo); setMore(false); setConfirming(false) }}>{index + 1}</button>) : null}</nav>
        {canDelete ? <button className="icon-button" type="button" aria-label="照片更多操作" aria-expanded={more} onClick={() => setMore(!more)} disabled={busy}><MoreHorizontal aria-hidden="true" size={20} /></button> : null}
        {canDelete && more ? <button className="danger-button" type="button" onClick={() => setConfirming(true)} disabled={busy}>删除照片</button> : null}
        {canDelete && confirming ? <section aria-label="确认删除照片"><h3>删除这张照片？</h3>
          <p>将从 Taste Map 中删除，不会删除系统相册中的原照片。</p>
          <button className="secondary-button" type="button" onClick={() => setConfirming(false)} disabled={busy}>取消</button>
          <button className="danger-button" type="button" onClick={() => void remove()} disabled={busy}>{busy ? '正在删除…' : '确认删除'}</button>
        </section> : null}
        {error ? <p role="alert">{error}</p> : null}
      </div>
    </ModalShell>, document.body) : null}
  </>
}
