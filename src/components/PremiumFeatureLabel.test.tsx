import { renderToStaticMarkup } from 'react-dom/server'
import { describe, expect, it } from 'vitest'
import { PremiumAccessContext } from './PremiumAccess'
import { PremiumFeatureLabel } from './PremiumFeatureLabel'

describe('Premium feature discoverability', () => {
  for (const access of [null, false, true]) {
    it(`retains the entry when access is ${access}`, () => {
      const html = renderToStaticMarkup(<PremiumAccessContext.Provider value={access}><PremiumFeatureLabel>最坑推荐来源</PremiumFeatureLabel></PremiumAccessContext.Provider>)
      expect(html).toContain('最坑推荐来源')
      expect(html.includes('会员专享')).toBe(access !== true)
    })
  }
})
