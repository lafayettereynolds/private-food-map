import { useCallback, useEffect, useLayoutEffect, useRef } from 'react'
import type {
  TasteMapNativeMapSurfaceUpdateRequest,
  TasteMapNativeMapSurfaceRect,
} from '../platform/TasteMapPlatform'
import { resolveRestaurantFoodEmoji } from '../visuals/FoodCategoryVisualContract'
import type { MyMapSurfaceProps } from './MyMapBrowsePage'

type NativeMapSurfaceProps = MyMapSurfaceProps

type MapVisualViewport = Pick<VisualViewport, 'width' | 'height' | 'offsetLeft' | 'offsetTop'>

export function nativeMapViewportGeometry(width: number, height: number, visualViewport?: MapVisualViewport | null) {
  const visual = visualViewport && visualViewport.width > 0 && visualViewport.height > 0 ? visualViewport : null
  return {
    width: visual?.width ?? width,
    height: visual?.height ?? height,
    rect: (value: Pick<DOMRect, 'x' | 'y' | 'width' | 'height'>): TasteMapNativeMapSurfaceRect => ({
      x: value.x - (visual?.offsetLeft ?? 0),
      y: value.y - (visual?.offsetTop ?? 0),
      width: value.width,
      height: value.height,
    }),
  }
}

export const hybridMapReactControlSelector = [
  '.tm-my-map__add',
  '.tm-my-map__location-note',
  '.tm-map-error',
  '.tm-map-filter-sheet',
  '.wheel-candidate-bar',
  '.wheel-candidate-popover',
  '.tm-hybrid-bottom-nav',
].join(',')

export function isRenderedHybridMapReactControl(value: Pick<HTMLElement, 'getClientRects'>) {
  // Fixed-position controls (notably the persistent bottom navigation) have a
  // null offsetParent even while visible. Geometry is the reliable visibility
  // signal for the Native surface's hit-test cut-outs.
  return value.getClientRects().length > 0
}

/**
 * React owns this placeholder and every control around it. On iOS, the typed
 * bridge positions the one persistent Native MapKit surface over exactly this
 * rectangle while cutting out React-owned floating controls.
 */
export function NativeMapSurface({
  active, interactionBlocked, platform, restaurants, images, selectedRestaurantID, scope, filters,
  sort, search, cameraFitKey, currentUser, tasteDataProgress, overlayRevision, onError,
}: NativeMapSurfaceProps) {
  const elementRef = useRef<HTMLDivElement>(null)
  const latestRequestID = useRef('')
  const scheduledFrame = useRef<number | null>(null)
  const lastSurfaceSignature = useRef('')
  const lastFrame = useRef<TasteMapNativeMapSurfaceRect>({ x: 0, y: 0, width: 1, height: 1 })

  const updateSurface = useCallback(() => {
    if (scheduledFrame.current != null) cancelAnimationFrame(scheduledFrame.current)
    const commitSurface = () => {
      scheduledFrame.current = null
      const element = elementRef.current
      const frame = element?.getBoundingClientRect()
      if (!frame) return
      const viewport = nativeMapViewportGeometry(window.innerWidth, window.innerHeight, window.visualViewport)
      lastFrame.current = viewport.rect(frame)
      const requestID = globalThis.crypto?.randomUUID?.() ?? `mapkit-${Date.now()}-${Math.random()}`
      const visible = active && !interactionBlocked
      const request: TasteMapNativeMapSurfaceUpdateRequest = {
        requestID,
        visible,
        viewportWidth: viewport.width,
        viewportHeight: viewport.height,
        frame: viewport.rect(frame),
        reactControlExclusions: Array.from(document.querySelectorAll<HTMLElement>(hybridMapReactControlSelector))
          .filter(isRenderedHybridMapReactControl)
          .map((value) => viewport.rect(value.getBoundingClientRect())),
        scope,
        filters,
        sort,
        search,
        cameraFitKey,
        selectedRestaurantID,
        userAvatarPresetID: currentUser.avatarPresetId,
        userAvatarPhotoID: currentUser.avatarPhotoId ?? null,
        tasteDataProgress,
        markers: visible ? restaurants.map((restaurant, index) => ({
          id: restaurant.id,
          name: restaurant.name,
          latitude: restaurant.latitude,
          longitude: restaurant.longitude,
          status: scope === 'recommended' ? 'recommended' as const : restaurant.status,
          recommendationRank: scope === 'recommended' ? restaurant.recommendationRank ?? index + 1 : null,
          visitCount: restaurant.visitCount,
          averageRating: scope === 'recommended' ? null : restaurant.averageRating,
          fallbackEmoji: resolveRestaurantFoodEmoji(restaurant, restaurant.markerEmoji),
          image: images[restaurant.id] ?? {
            kind: 'foodDiningFallback' as const,
            stableSeed: restaurant.id,
            accessibilityLabel: `${restaurant.name} 餐饮图示`,
          },
        })) : [],
      }
      const signature = JSON.stringify({ ...request, requestID: '' })
      if (signature === lastSurfaceSignature.current) return
      lastSurfaceSignature.current = signature
      latestRequestID.current = requestID
      void platform.map.updateNativeSurface(request).then((response) => {
        if (latestRequestID.current !== response.requestID) return
        onError(null)
      }).catch((reason: unknown) => {
        if (latestRequestID.current !== requestID) return
        lastSurfaceSignature.current = ''
        onError(reason instanceof Error ? reason.message : '原生 MapKit 地图暂时不可用。')
      })
    }
    // Hiding is a lifecycle transition, not a geometry update. Do not leave
    // MapKit over the next route while waiting for another animation frame.
    if (!active || interactionBlocked) commitSurface()
    else scheduledFrame.current = requestAnimationFrame(commitSurface)
  }, [active, cameraFitKey, currentUser.avatarPhotoId, currentUser.avatarPresetId, filters, images, interactionBlocked, onError, platform, restaurants, scope, search, selectedRestaurantID, sort, tasteDataProgress])

  const updateSurfaceRef = useRef(updateSurface)
  updateSurfaceRef.current = updateSurface

  useLayoutEffect(updateSurface, [overlayRevision, updateSurface])

  useEffect(() => {
    const element = elementRef.current
    if (!element) return
    const requestUpdate = () => updateSurfaceRef.current()
    const observer = new ResizeObserver(requestUpdate)
    observer.observe(element)
    window.addEventListener('resize', requestUpdate)
    window.addEventListener('scroll', requestUpdate, { passive: true })
    const visualViewport = window.visualViewport
    visualViewport?.addEventListener('resize', requestUpdate)
    visualViewport?.addEventListener('scroll', requestUpdate)
    return () => {
      observer.disconnect()
      window.removeEventListener('resize', requestUpdate)
      window.removeEventListener('scroll', requestUpdate)
      visualViewport?.removeEventListener('resize', requestUpdate)
      visualViewport?.removeEventListener('scroll', requestUpdate)
      if (scheduledFrame.current != null) cancelAnimationFrame(scheduledFrame.current)
    }
  }, [])

  useEffect(() => () => {
    void platform.map.updateNativeSurface({
      requestID: globalThis.crypto?.randomUUID?.() ?? `mapkit-hide-${Date.now()}`,
      visible: false,
      viewportWidth: window.innerWidth,
      viewportHeight: window.innerHeight,
      frame: lastFrame.current,
      reactControlExclusions: [],
      scope: 'visited',
      filters: {},
      sort: 'recent',
      search: '',
      cameraFitKey: 'unmounted',
      selectedRestaurantID: null,
      userAvatarPresetID: 'polar-bear',
      userAvatarPhotoID: null,
      tasteDataProgress: null,
      markers: [],
    }).catch(() => undefined)
  }, [platform])

  return <div
    aria-hidden="true"
    className="tm-native-map-surface"
    data-map-engine="native-mapkit"
    data-restaurant-count={restaurants.length}
    ref={elementRef}
  />
}
