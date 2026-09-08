import { describe, expect, it } from 'vitest'
import { nativeMapViewportGeometry } from './NativeMapSurface'

describe('Native Map geometry follows the visible WebKit viewport', () => {
  const frame = { x: 0, y: 207, width: 402, height: 667 }
  const addButton = { x: 150, y: 754, width: 102, height: 43 }

  it('preserves the full map and header gap when layout and visual viewport heights disagree', () => {
    const viewport = nativeMapViewportGeometry(402, 1750, { width: 402, height: 874, offsetLeft: 0, offsetTop: 0 })
    expect(viewport.width).toBe(402)
    expect(viewport.height).toBe(874)
    expect(viewport.rect(frame)).toEqual(frame)
    expect(viewport.rect(addButton)).toEqual(addButton)
    expect(viewport.rect(frame).y + viewport.rect(frame).height).toBe(874)
  })

  it('converts the map and every control into the same visual origin after zoom or focus scrolling', () => {
    const viewport = nativeMapViewportGeometry(402, 874, { width: 201, height: 320, offsetLeft: 18, offsetTop: 140 })
    expect(viewport.rect(frame)).toEqual({ x: -18, y: 67, width: 402, height: 667 })
    expect(viewport.rect(addButton)).toEqual({ x: 132, y: 614, width: 102, height: 43 })
    expect(viewport.rect(addButton).y - viewport.rect(frame).y).toBe(addButton.y - frame.y)
    expect(viewport.width).toBe(201)
    expect(viewport.height).toBe(320)
  })

  it('returns to the original geometry when the keyboard/focus viewport is restored', () => {
    const original = nativeMapViewportGeometry(402, 874)
    const restored = nativeMapViewportGeometry(402, 874, { width: 402, height: 874, offsetLeft: 0, offsetTop: 0 })
    expect(restored.rect(frame)).toEqual(original.rect(frame))
    expect(restored.rect(addButton)).toEqual(original.rect(addButton))
    expect(nativeMapViewportGeometry(402, 874, { width: 0, height: 0, offsetLeft: 10, offsetTop: 20 }).rect(frame)).toEqual(frame)
  })
})
