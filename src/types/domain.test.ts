import { describe, expect, it } from 'vitest'
import { scoreBandFromScore, scoreColor } from './domain'

describe('score colors', () => {
  it('uses five two-point score bands', () => {
    expect([scoreBandFromScore(10), scoreBandFromScore(9), scoreBandFromScore(8.9), scoreBandFromScore(7), scoreBandFromScore(6.9), scoreBandFromScore(5), scoreBandFromScore(4.9), scoreBandFromScore(3), scoreBandFromScore(2.9), scoreBandFromScore(1)]).toEqual([5, 5, 4, 4, 3, 3, 2, 2, 1, 1])
  })

  it('varies color inside each band and makes the lowest red the deepest', () => {
    expect(scoreColor(9)).not.toBe(scoreColor(10))
    expect(scoreColor(7)).not.toBe(scoreColor(8.9))
    expect(scoreColor(1)).toBe('#851522')
    expect(scoreColor(1)).not.toBe(scoreColor(2.9))
  })
})
