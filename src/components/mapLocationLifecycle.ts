import type { TasteMapLocationDTO } from '../platform/TasteMapPlatform'

/** UI delivery gate only; shared Native sensor work is not cancelled when one
 * consumer leaves. Older responses/events may not revive a previous origin. */
export class MapLocationDeliveryGate {
  private sequence = 0
  private startedAt = 0
  private lastAcceptedTimestamp = 0

  begin(now = Date.now()) {
    this.startedAt = now
    return ++this.sequence
  }

  invalidate(now = Date.now()) {
    this.begin(now)
  }

  isCurrent(sequence: number) {
    return sequence === this.sequence
  }

  accept(location: TasteMapLocationDTO, sequence = this.sequence, now = Date.now()) {
    const timestamp = Date.parse(location.timestamp)
    const maximumAccuracy = location.accuracyMode === 'reduced' ? 10_000 : 100
    if (!this.isCurrent(sequence)
      || !Number.isFinite(timestamp) || timestamp < this.startedAt - 1_000
      || timestamp < this.lastAcceptedTimestamp || now - timestamp > 15_000 || timestamp - now > 5_000
      || !Number.isFinite(location.latitude) || !Number.isFinite(location.longitude)
      || Math.abs(location.latitude) > 90 || Math.abs(location.longitude) > 180
      || !Number.isFinite(location.horizontalAccuracy) || location.horizontalAccuracy < 0
      || location.horizontalAccuracy > maximumAccuracy || location.authorizationStatus !== 'allowed') return false
    this.lastAcceptedTimestamp = timestamp
    return true
  }
}
