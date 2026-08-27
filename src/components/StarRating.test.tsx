import { renderToStaticMarkup } from 'react-dom/server'
import { describe, expect, it, vi } from 'vitest'
import { isStarRating, starToTenScore } from '../types/domain'
import { ratingFromPointerPosition, stepHalfStarRating } from '../utils/starRatingInteraction'
import { StarRating } from './StarRating'

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

  it('keeps half-star values valid through the shared rating model', () => {
    expect(isStarRating(3.5)).toBe(true)
    expect(starToTenScore(3.5)).toBe(7)
  })

  it('exposes one slider and five independent star targets', () => {
    const markup = renderToStaticMarkup(<StarRating onChange={vi.fn()} value={3.5} />)
    expect(markup).toContain('role="slider"')
    expect(markup).toContain('aria-valuenow="3.5"')
    expect((markup.match(/data-star=/g) ?? []).length).toBe(5)
    expect(markup).not.toContain('star-rating__hit--left')
    expect(markup).not.toContain('star-rating__hit--right')
  })
})
