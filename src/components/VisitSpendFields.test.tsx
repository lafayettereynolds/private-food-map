import { renderToStaticMarkup } from 'react-dom/server'
import { describe, expect, it } from 'vitest'
import { VisitSpendFields } from './VisitSpendFields'

describe('shared amount-only spend field', () => {
  it.each(['', '0', '285', '285.50'])('retains one editable input without calculation copy for %s', amount => {
    const html = renderToStaticMarkup(<VisitSpendFields amount={amount} onAmountChange={() => {}} />)
    expect(html.match(/<input /g)).toHaveLength(1)
    expect(html).toContain('aria-label="消费金额（元）"')
    expect(html).toContain(`value="${amount}"`)
    expect(html).toContain('inputMode="decimal"')
    expect(html).not.toMatch(/price-calculation|<output|计入总消费|参考人均|全额计入|本人不支出|历史支付|尚未计入|消费方式/)
    expect(html).not.toMatch(/disabled|readOnly|整桌账单|我的实际消费（元）/)
  })
})
