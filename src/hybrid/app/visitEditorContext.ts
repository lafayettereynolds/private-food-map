import type { RestaurantSummary, Visit } from '../../types/domain'
import type { TasteMapPlatform, TasteMapRestaurantDetailViewModel } from '../../platform/TasteMapPlatform'

export interface VisitEditorContext {
  restaurant: RestaurantSummary
  visit: Visit | null
}

export interface VisitEditorContextInput {
  restaurantID?: string
  visitID?: string
  restaurants: RestaurantSummary[]
  visits: Visit[]
  sourceDetail?: TasteMapRestaurantDetailViewModel | null
}

const sameID = (left: string, right: string) => left.toLowerCase() === right.toLowerCase()

/** An edit is a specific Visit, never a blank create form or an aggregate score. */
export async function loadVisitEditorContext(
  platform: Pick<TasteMapPlatform, 'profile' | 'restaurant'>,
  input: VisitEditorContextInput,
): Promise<VisitEditorContext> {
  let restaurantID = input.restaurantID
  if (input.visitID) {
    const visitID = input.visitID
    const sourceVisit = input.sourceDetail?.restaurant.visits.find((item) => sameID(item.id, visitID))
    const cachedVisit = input.visits.find((item) => sameID(item.id, visitID))
    restaurantID = sourceVisit ? input.sourceDetail!.restaurant.id : cachedVisit?.restaurantId ?? restaurantID
    if (!restaurantID) {
      // A newly saved/imported Visit may exist in Detail before the dashboard
      // snapshot catches up. A cold edit route also needs this real read path.
      const profile = await platform.profile.getCurrent()
      restaurantID = profile.visits.find((item) => sameID(item.id, visitID))?.restaurantId
    }
    if (!restaurantID) throw new Error('未找到这次到访记录，可能已删除或尚未同步。请重试，或返回餐厅查看。')
    const detail = await platform.restaurant.get(restaurantID)
    const visit = detail.restaurant.visits.find((item) => sameID(item.id, visitID))
    if (!visit) throw new Error('这次到访记录已不可用，请返回餐厅刷新后重试。')
    if (!detail.editableVisitIDs.some((id) => sameID(id, visit.id))) {
      throw new Error('当前账户无法编辑这次到访记录。')
    }
    return { restaurant: detail.restaurant, visit }
  }
  if (!restaurantID) throw new Error('缺少餐厅信息，请返回餐厅后重新记录到访。')
  const detail = await platform.restaurant.get(restaurantID)
  if (!detail.capabilities.canRecordVisit) throw new Error('当前餐厅暂时无法记录到访。')
  return { restaurant: detail.restaurant, visit: null }
}

/** Native reads normally return quickly; an unresolved bridge must not trap the page. */
export function boundedVisitEditorRead<T>(request: Promise<T>, timeoutMS = 15_000): Promise<T> {
  return new Promise((resolve, reject) => {
    const timeout = setTimeout(() => reject(new Error('读取到访记录超时，请重试。未对原记录作任何修改。')), timeoutMS)
    request.then(resolve, reject).finally(() => clearTimeout(timeout))
  })
}
