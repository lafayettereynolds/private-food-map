import { readFileSync } from 'node:fs'
import { expect, it } from 'vitest'

it('uses authenticated owner cache/download while rechecking owner and deletion after await', () => {
  const source = readFileSync('ios/TasteMap/TasteMap/Hybrid/TasteMapHybridRuntime.swift', 'utf8')
  const resource = source.split('func resourceData(for url: URL)')[1].split('private static func isOwnerVisibleCachedPhoto')[0]
  expect(resource).toContain('guard case .authenticated(let ownerUserID) = authServices.localAccountScope')
  expect(resource).toContain('let context = container.mainContext')
  expect(resource).toContain('$0.ownerUserID == ownerUserID')
  const owned = resource.split('if let ownedPhoto {')[1].split('guard parts[0] == "public-photo"')[0]
  expect(owned).toContain('try await photoTransferCoordinator.imageData(for: ownedPhoto, variant: variant)')
  expect(owned).toContain('authServices.localAccountScope == .authenticated(ownerUserID)')
  expect(owned).toContain('ownedPhoto.deletedAt == nil, ownedPhoto.binaryDeletedAt == nil')
  expect(owned).toContain('try !isLocallyDeleted()')
  expect(resource).toContain('guard parts[0] == "public-photo"')
})
