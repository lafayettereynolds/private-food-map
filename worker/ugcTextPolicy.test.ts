import { describe, expect, it } from 'vitest'
import { prohibitedUGCText } from './ugcTextPolicy'

describe('UGC text policy', () => {
  it.each(['我要杀了你', '你全家都去死', 'I will kill you', '幼女裸照', '刷单返利联系我', 'i will ki\u200bll you', 'Ｉ ｗｉｌｌ ｋｉｌｌ ｙｏｕ'])('rejects explicit prohibited content: %s', text => {
    expect(prohibitedUGCText(text)).not.toBeNull()
  })
  it.each(['不好吃，再也不来了', '火爆腰花，麻辣过瘾', '差评，服务不好', 'https://restaurant.example/menu', '小朋友喜欢这里的鸡翅'])('preserves legitimate dining speech: %s', text => {
    expect(prohibitedUGCText(text)).toBeNull()
  })
})
