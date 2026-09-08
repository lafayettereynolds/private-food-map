import { useEffect, useRef, useState, type PointerEvent as ReactPointerEvent, type WheelEvent } from 'react'

interface PosterViewport {
  scale: number
  x: number
  y: number
}

interface PointerPosition {
  x: number
  y: number
}

interface PinchOrigin {
  distance: number
  center: PointerPosition
  viewport: PosterViewport
}

const MIN_SCALE = 0.75
const MAX_SCALE = 5

export function ZoomablePosterPreview({ src, alt }: { src: string; alt: string }) {
  const surfaceRef = useRef<HTMLDivElement>(null)
  const pointers = useRef(new Map<number, PointerPosition>())
  const pinchOrigin = useRef<PinchOrigin | null>(null)
  const dragOrigin = useRef<{ pointer: PointerPosition; viewport: PosterViewport } | null>(null)
  const [viewport, setViewport] = useState<PosterViewport>({ scale: 1, x: 0, y: 0 })

  useEffect(() => {
    pointers.current.clear()
    pinchOrigin.current = null
    dragOrigin.current = null
    setViewport({ scale: 1, x: 0, y: 0 })
  }, [src])

  const onPointerDown = (event: ReactPointerEvent<HTMLDivElement>) => {
    event.currentTarget.setPointerCapture?.(event.pointerId)
    pointers.current.set(event.pointerId, point(event))
    if (pointers.current.size >= 2) {
      pinchOrigin.current = makePinchOrigin(pointers.current, viewport)
      dragOrigin.current = null
    } else {
      dragOrigin.current = { pointer: point(event), viewport }
    }
  }

  const onPointerMove = (event: ReactPointerEvent<HTMLDivElement>) => {
    if (!pointers.current.has(event.pointerId)) return
    pointers.current.set(event.pointerId, point(event))
    if (pointers.current.size >= 2) {
      const origin = pinchOrigin.current
      if (!origin) {
        pinchOrigin.current = makePinchOrigin(pointers.current, viewport)
        return
      }
      const [first, second] = Array.from(pointers.current.values())
      const center = midpoint(first, second)
      const scale = clampScale(origin.viewport.scale * distance(first, second) / origin.distance)
      const translated = scale <= 1
        ? { x: 0, y: 0 }
        : clampTranslation(
            surfaceRef.current,
            origin.viewport.x + center.x - origin.center.x,
            origin.viewport.y + center.y - origin.center.y,
            scale,
          )
      setViewport({ scale, ...translated })
      return
    }

    const origin = dragOrigin.current
    if (!origin || origin.viewport.scale <= 1) return
    const current = point(event)
    const translated = clampTranslation(
      surfaceRef.current,
      origin.viewport.x + current.x - origin.pointer.x,
      origin.viewport.y + current.y - origin.pointer.y,
      origin.viewport.scale,
    )
    setViewport({ scale: origin.viewport.scale, ...translated })
  }

  const endPointer = (event: ReactPointerEvent<HTMLDivElement>) => {
    pointers.current.delete(event.pointerId)
    pinchOrigin.current = null
    const remaining = Array.from(pointers.current.values())[0]
    dragOrigin.current = remaining ? { pointer: remaining, viewport } : null
  }

  const changeScale = (nextScale: number) => {
    const scale = clampScale(nextScale)
    if (scale <= 1) {
      setViewport({ scale, x: 0, y: 0 })
      return
    }
    setViewport((current) => ({
      scale,
      ...clampTranslation(surfaceRef.current, current.x, current.y, scale),
    }))
  }

  const onWheel = (event: WheelEvent<HTMLDivElement>) => {
    if (!event.ctrlKey && !event.metaKey) return
    event.preventDefault()
    changeScale(viewport.scale * Math.exp(-event.deltaY * 0.01))
  }

  return (
    <div
      aria-label={`${alt}，双指张合缩放，放大后拖动查看，双击恢复`}
      aria-roledescription="可缩放海报"
      className="poster-zoom-surface"
      data-poster-scale={viewport.scale.toFixed(2)}
      onDoubleClick={() => setViewport(viewport.scale === 1 ? { scale: 2.5, x: 0, y: 0 } : { scale: 1, x: 0, y: 0 })}
      onKeyDown={(event) => {
        if (event.key === '+' || event.key === '=') changeScale(viewport.scale * 1.25)
        if (event.key === '-') changeScale(viewport.scale / 1.25)
        if (event.key === '0' || event.key === 'Escape') setViewport({ scale: 1, x: 0, y: 0 })
      }}
      onPointerCancel={endPointer}
      onPointerDown={onPointerDown}
      onPointerMove={onPointerMove}
      onPointerUp={endPointer}
      onWheel={onWheel}
      ref={surfaceRef}
      tabIndex={0}
    >
      <img
        alt={alt}
        draggable={false}
        src={src}
        style={{ transform: `translate3d(${viewport.x}px, ${viewport.y}px, 0) scale(${viewport.scale})` }}
      />
    </div>
  )
}

function point(event: ReactPointerEvent<HTMLDivElement>): PointerPosition {
  return { x: event.clientX, y: event.clientY }
}

function distance(first: PointerPosition, second: PointerPosition) {
  return Math.max(1, Math.hypot(second.x - first.x, second.y - first.y))
}

function midpoint(first: PointerPosition, second: PointerPosition): PointerPosition {
  return { x: (first.x + second.x) / 2, y: (first.y + second.y) / 2 }
}

function makePinchOrigin(values: Map<number, PointerPosition>, viewport: PosterViewport): PinchOrigin {
  const [first, second] = Array.from(values.values())
  return { distance: distance(first, second), center: midpoint(first, second), viewport }
}

function clampScale(value: number) {
  return Math.min(MAX_SCALE, Math.max(MIN_SCALE, value))
}

function clampTranslation(element: HTMLElement | null, x: number, y: number, scale: number) {
  if (!element || element.clientWidth <= 0 || element.clientHeight <= 0) return { x, y }
  const maxX = element.clientWidth * Math.max(0, scale - 1) / 2
  const maxY = element.clientHeight * Math.max(0, scale - 1) / 2
  return {
    x: Math.min(maxX, Math.max(-maxX, x)),
    y: Math.min(maxY, Math.max(-maxY, y)),
  }
}
