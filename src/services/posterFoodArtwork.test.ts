import { describe, expect, it } from 'vitest'
import { posterObjectArtwork, posterPreferenceArtwork } from './posterFoodArtwork'

describe('poster decorative object policy', () => {
  it('returns no invented artwork for missing flavor/time catalog entries', async () => {
    for (const label of ['偏辣', '偏酸', '偏鲜', '早餐', '夜宵', '未知']) expect(await posterPreferenceArtwork(label)).toBeNull()
  })
  it('fails empty when original sheet cannot be rendered, never emitting emoji or remote assets', async () => {
    expect(await posterObjectArtwork('city')).toBeNull()
    expect(await posterPreferenceArtwork('清淡')).toBeNull()
    expect(await posterPreferenceArtwork('偏咸')).toBeNull()
  })
})
