import { useCallback, useEffect, useLayoutEffect, useRef } from 'react'
import type {
  TasteMapNativeMapSurfaceUpdateRequest,
  TasteMapNativeMapSurfaceRect,
} from '../platform/TasteMapPlatform'
import { resolveRestaurantFoodEmoji } from '../visuals/FoodCategoryVisualContract'
import type { MyMapSurfaceProps } from './MyMapBrowsePage'

type NativeMapSurfaceProps = MyMapSurfaceProps

export const hybridMapReactControlSelector = [
  '.tm-my-map__add',
  '.tm-my-map__location-note',
  '.tm-map-error',
  '.tm-map-filter-sheet',
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
  sort, search, cameraFitKey, currentUser, overlayRevision, onError,
}: NativeMapSurfaceProps) {
  const elementRef = useRef<HTMLDivElement>(null)
  const latestRequestID = useRef('')
  const scheduledFrame = useRef<number | null>(null)
  const lastSurfaceSignature = useRef('')
  const lastFrame = useRef<TasteMapNativeMapSurfaceRect>({ x: 0, y: 0, width: 1, height: 1 })

  const updateSurface = useCallback(() => {
    if (scheduledFrame.current != null) cancelAnimationFrame(scheduledFrame.current)
    scheduledFrame.current = requestAnimationFrame(() => {
      scheduledFrame.current = null
      const element = elementRef.current
      const frame = element?.getBoundingClientRect()
      if (!frame) return
      lastFrame.current = rect(frame)
      const requestID = globalThis.crypto?.randomUUID?.() ?? `mapkit-${Date.now()}-${Math.random()}`
      const visible = active && !interactionBlocked
      const request: TasteMapNativeMapSurfaceUpdateRequest = {
        requestID,
        visible,
        viewportWidth: window.innerWidth,
        viewportHeight: window.innerHeight,
        frame: rect(frame),
        reactControlExclusions: Array.from(document.querySelectorAll<HTMLElement>(hybridMapReactControlSelector))
          .filter(isRenderedHybridMapReactControl)
          .map((value) => rect(value.getBoundingClientRect())),
        scope,
        filters,
        sort,
        search,
        cameraFitKey,
        selectedRestaurantID,
        userAvatarPresetID: currentUser.avatarPresetId,
        userAvatarPhotoID: currentUser.avatarPhotoId ?? null,
        markers: visible ? restaurants.map((restaurant) => ({
          id: restaurant.id,
          name: restaurant.name,
          latitude: restaurant.latitude,
          longitude: restaurant.longitude,
          status: scope === 'recommended' ? 'recommended' as const : restaurant.status,
          visitCount: restaurant.visitCount,
          averageRating: restaurant.averageRating,
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
    })
  }, [active, cameraFitKey, currentUser.avatarPhotoId, currentUser.avatarPresetId, filters, images, interactionBlocked, onError, platform, restaurants, scope, search, selectedRestaurantID, sort])

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
    return () => {
      observer.disconnect()
      window.removeEventListener('resize', requestUpdate)
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

function rect(value: DOMRect): TasteMapNativeMapSurfaceRect {
  return { x: value.x, y: value.y, width: value.width, height: value.height }
}
