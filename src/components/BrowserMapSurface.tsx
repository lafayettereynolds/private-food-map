import { MapView } from './MapView'
import type { MyMapSurfaceProps } from './MyMapBrowsePage'

/**
 * Browser-only map surface adapter. Keeping this import outside the shared
 * My Map page prevents the Web map renderer and credential vocabulary from
 * being pulled into the Capacitor bundle.
 */
export function BrowserMapSurface({
  active, cameraFitKey, currentCoordinates, currentUser, initialViewport,
  onClearSelection, onSelect, onSelectGroup, onViewportChange, restaurants, scope, selectedRestaurant,
}: MyMapSurfaceProps) {
  if (!active) return null
  return <MapView
    cameraFitKey={cameraFitKey}
    currentCoordinates={currentCoordinates}
    currentUser={currentUser}
    initialViewport={initialViewport}
    onClearSelection={onClearSelection}
    onSelect={onSelect}
    onSelectGroup={onSelectGroup}
    onViewportChange={onViewportChange}
    restaurants={restaurants}
    selectedRestaurant={selectedRestaurant}
    unvisitedMarkerStyle={scope === 'recommended'}
  />
}
