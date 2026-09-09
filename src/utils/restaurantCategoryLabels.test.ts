import { describe, expect, it } from 'vitest'
import { restaurantCategoryLabels } from './restaurantCategoryLabels'
describe('restaurant category labels', () => {
  it('normalizes provider metadata without inventing a cuisine or losing real tags', () => {
    expect(restaurantCategoryLabels(['MKPOICategoryRestaurant','川菜','MKPOICategoryCafe','MKPOICategoryFuture','餐厅'])).toEqual(['餐厅','川菜','咖啡馆'])
  })
})
