import { describe, expect, it } from 'vitest'
import { splitCompanions } from './companions'

describe('splitCompanions', () => {
  it('supports common separators and removes duplicate names', () => {
    expect(splitCompanions('妈妈、朋友，同事/朋友')).toEqual(['妈妈', '朋友', '同事'])
  })

  it('ignores empty names and surrounding spaces', () => {
    expect(splitCompanions('  小王 , , 妈妈  ')).toEqual(['小王', '妈妈'])
  })
})
