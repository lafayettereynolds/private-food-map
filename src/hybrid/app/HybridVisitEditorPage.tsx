import { useEffect, useMemo, useState } from 'react'
import { AddVisitModal } from '../../components/AddVisitModal'
import type { AddVisitInput } from '../../db/restaurants'
import type { RestaurantSummary, Visit } from '../../types/domain'
import type { TasteMapPlatform, TasteMapVisitWriteDraftDTO } from '../../platform/TasteMapPlatform'

interface HybridVisitEditorPageProps {
  platform: TasteMapPlatform
  restaurantID?: string
  visitID?: string
  restaurants: RestaurantSummary[]
  visits: Visit[]
  onClose: () => void
  onSaved: (restaurantID: string) => void
}

export function HybridVisitEditorPage({ platform, restaurantID, visitID, restaurants, visits, onClose, onSaved }: HybridVisitEditorPageProps) {
  const existingVisit = visitID ? visits.find((visit) => visit.id === visitID) ?? null : null
  const initialRestaurant = restaurants.find((restaurant) => restaurant.id === (restaurantID ?? existingVisit?.restaurantId)) ?? null
  const [restaurant, setRestaurant] = useState<RestaurantSummary | null>(initialRestaurant)
  const [error, setError] = useState('')
  const companionOptions = useMemo(() => [...new Set(visits.flatMap((visit) => visit.companions))].sort((a, b) => a.localeCompare(b, 'zh-CN')), [visits])

  useEffect(() => {
    if (restaurant || !restaurantID) return
    let active = true
    platform.restaurant.get(restaurantID).then((value) => {
      if (active) setRestaurant(value.restaurant)
    }).catch((reason) => {
      if (active) setError(reason instanceof Error ? reason.message : '无法读取餐厅。')
    })
    return () => { active = false }
  }, [platform, restaurant, restaurantID])

  if (!restaurant) return <main className="tm-hybrid-state is-fatal"><h1>无法打开到访记录</h1><p>{error || '正在读取餐厅…'}</p><button onClick={onClose} type="button">返回</button></main>

  return <AddVisitModal
    companionOptions={companionOptions}
    initialVisit={existingVisit ?? undefined}
    maxPhotos={20}
    onClose={onClose}
    onDelete={existingVisit ? async () => {
      const result = await platform.visit.delete(existingVisit.id)
      onSaved(result.restaurantID)
    } : undefined}
    onSave={async (input) => {
      const result = await platform.visit.save({
        restaurantID: restaurant.id,
        visitID: existingVisit?.id ?? null,
        draft: visitWriteDraft(input),
      })
      onSaved(result.restaurantID)
    }}
    photoUpgradeAvailable={false}
    restaurant={restaurant}
  />
}

function visitWriteDraft(input: AddVisitInput): TasteMapVisitWriteDraftDTO {
  return {
    visitedAt: input.visitedAt,
    rating: input.rating,
    visibility: input.visibility,
    diningMode: input.diningMode,
    totalPrice: input.totalPrice,
    myActualSpend: input.myActualSpend,
    paymentMode: input.paymentMode,
    partySize: input.partySize,
    queueDuration: input.queueDuration,
    diningOccasions: input.diningOccasions,
    diningOccasionText: input.diningOccasionText,
    valueRating: input.valueRating,
    environmentRating: input.environmentRating,
    serviceRating: input.serviceRating,
    valueTags: input.valueTags,
    environmentTags: input.environmentTags,
    serviceTags: input.serviceTags,
    noiseLevel: input.noiseLevel,
    diningDuration: input.diningDuration,
    portionLevel: input.portionLevel,
    transportConvenience: input.transportConvenience,
    specialNotes: input.specialNotes,
    recommendationSourceType: input.recommendationSourceType,
    recommendationSourceUserID: input.recommendationSourceUserId,
    recommendationSourceText: input.recommendationSourceText,
    sharedParticipantUserIDs: input.sharedParticipantUserIds,
    companions: input.companions,
    dishes: input.dishes.map((dish) => ({
      id: dish.id,
      name: dish.name,
      taste: dish.taste,
      rating: dish.rating,
      price: dish.price,
      photoID: dish.photoId,
    })),
    note: input.note,
  }
}
