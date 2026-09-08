import { useState, type ReactNode } from 'react'

/** Layout only: the caller supplies authorized photos from this activity. */
export function TasteMapActivityMedia({ images, name, onOpen }: {
  images: readonly ReactNode[]
  name: string
  onOpen: () => void
}) {
  const [expanded, setExpanded] = useState(false)
  const visible = expanded ? images : images.slice(0, 9)
  const columns = images.length < 3 ? images.length : images.length === 4 ? 2 : 3
  if (!images.length) return null
  return <div className="tm-activity-media" data-columns={columns} data-photo-count={images.length}>
    <div className="tm-activity-media__grid">
      {visible.map((image, index) => <button
        aria-label={`查看 ${name}，图片 ${index + 1} / ${images.length}`}
        className="tm-activity-media__tile"
        key={index}
        onClick={onOpen}
        type="button"
      >{image}</button>)}
    </div>
    {images.length > 9 ? <button className="tm-activity-media__expand" aria-expanded={expanded}
      onClick={() => setExpanded((value) => !value)} type="button">
      {expanded ? '收起照片' : `展开全部 ${images.length} 张照片`}
    </button> : null}
  </div>
}
