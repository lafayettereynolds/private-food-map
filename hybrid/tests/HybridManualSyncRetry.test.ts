import { readFileSync } from 'node:fs'
import { describe, expect, it } from 'vitest'

describe('Hybrid explicit manual sync retry', () => {
  it('rearms failed mutations through the existing owner-scoped retry path', () => {
    const runtime = readFileSync(new URL('../../ios/TasteMap/TasteMap/Hybrid/TasteMapHybridRuntime.swift', import.meta.url), 'utf8')
    const branch = runtime.split('case .syncRun:')[1]?.split('case .permissionsStatus:')[0]
    expect(branch).toBeDefined()
    expect(branch).toContain('await syncCoordinator.retryNow()')
    expect(branch).not.toContain('synchronizeNow()')
    expect(branch).toContain('return try encode(syncStatus())')
  })
})
