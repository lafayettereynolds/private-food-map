import { renderToStaticMarkup } from 'react-dom/server'
import { describe, expect, it, vi } from 'vitest'
import { isStarRating, starToTenScore } from '../types/domain'
import { ratingFromPointerPosition, reduceEditableStarRating, stepHalfStarRating } from '../utils/starRatingInteraction'
import { StarRating, StarRatingField } from './StarRating'

describe('StarRating pointer interaction', () => {
  const rect = { left: 100, width: 44 }

  it.each([
    [1, 101, 0.5],
    [1, 121, 0.5],
    [1, 122, 1],
    [3, 110, 2.5],
    [3, 140, 3],
    [5, 101, 4.5],
    [5, 143, 5],
  ])('maps star %s at x=%s to %s stars', (star, clientX, expected) => {
    expect(ratingFromPointerPosition(star, clientX, rect)).toBe(expected)
  })

  it('moves through every half-star value with the keyboard', () => {
    expect(stepHalfStarRating(null, 1)).toBe(0.5)
    expect(stepHalfStarRating(0.5, 1)).toBe(1)
    expect(stepHalfStarRating(3.5, 1)).toBe(4)
    expect(stepHalfStarRating(4, -1)).toBe(3.5)
    expect(stepHalfStarRating(5, 1)).toBe(5)
  })

  it.each([
    [null, 4, 4],
    [4, 3.5, 3.5],
    [4, 2, 2],
    [3.5, 4.5, 4.5],
    [4.5, 1, 1],
    [4, 4, 4],
  ] as const)('SET changes %s directly to %s without toggling through nil', (current, target, expected) => {
    expect(reduceEditableStarRating(current, { type: 'set', value: target })).toBe(expected)
  })

  it('supports every formal half-star target through the same SET action', () => {
    const values = [0.5, 1, 1.5, 2, 2.5, 3, 3.5, 4, 4.5, 5] as const
    expect(values.map((value) => reduceEditableStarRating(4, { type: 'set', value }))).toEqual(values)
  })

  it('uses only the explicit CLEAR action to produce nil', () => {
    expect(reduceEditableStarRating(4, { type: 'clear' })).toBeNull()
    expect(reduceEditableStarRating(null, { type: 'set', value: 3.5 })).toBe(3.5)
  })

  it('never emits an intermediate nil while changing an existing rating', () => {
    const history = [4, reduceEditableStarRating(4, { type: 'set', value: 3.5 })]
    expect(history).toEqual([4, 3.5])
    expect(history).not.toContain(null)
  })

  it('keeps half-star values valid through the shared rating model', () => {
    expect(isStarRating(3.5)).toBe(true)
    expect(starToTenScore(3.5)).toBe(7)
  })

  it('exposes one slider and five independent star targets', () => {
    const markup = renderToStaticMarkup(<StarRating onChange={vi.fn()} value={3.5} />)
    expect(markup).toContain('role="slider"')
    expect(markup).toContain('aria-valuenow="3.5"')
    expect(markup).toContain('aria-label="个人评价，3.5 星，共 5 星"')
    expect(markup).toContain('3.5 星 · 喜欢 · 7.0 分')
    expect(markup).toContain('aria-label="清除评分"')
    expect((markup.match(/data-star=/g) ?? []).length).toBe(5)
    expect(markup).not.toContain('star-rating__hit--left')
    expect(markup).not.toContain('star-rating__hit--right')
  })

  it('uses a semantic fieldset instead of a label around the interactive clear button', () => {
    const markup = renderToStaticMarkup(<StarRatingField onChange={vi.fn()} value={4} />)
    expect(markup).toContain('<fieldset class="field rating-field">')
    expect(markup).toContain('<legend>个人评价<small>可选</small></legend>')
    expect(markup).not.toContain('<label')
  })

})
