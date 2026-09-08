import { useEffect, useMemo, useRef, useState } from 'react'
import { AddVisitModal } from '../../components/AddVisitModal'
import type { AddVisitInput } from '../../db/restaurants'
import type { MembershipTier, RestaurantSummary, Visit } from '../../types/domain'
import { visitPhotoLimit } from '../../services/featurePolicy'
import type { TasteMapPlatform, TasteMapRestaurantDetailViewModel, TasteMapVisitWriteDraftDTO } from '../../platform/TasteMapPlatform'
import { HybridBackButton, HybridState } from '../../components/TasteMapHybridShared'
import { boundedVisitEditorRead, loadVisitEditorContext, type VisitEditorContext } from './visitEditorContext'

interface HybridVisitEditorPageProps {
  platform: TasteMapPlatform
  membershipTier?: MembershipTier
  restaurantID?: string
  visitID?: string
  restaurants: RestaurantSummary[]
  visits: Visit[]
  sourceDetail?: TasteMapRestaurantDetailViewModel | null
  onClose: () => void
  onSaved: (restaurantID: string) => void
  onRestaurantDeleted: (restaurantID: string) => void
}

export function HybridVisitEditorPage({ platform, membershipTier = 'free', restaurantID, visitID, restaurants, visits, sourceDetail, onClose, onSaved, onRestaurantDeleted }: HybridVisitEditorPageProps) {
  const identity = `${visitID ? 'edit' : 'create'}:${visitID ?? restaurantID ?? ''}`
  const [loaded, setLoaded] = useState<{ identity: string; context: VisitEditorContext } | null>(null)
  const [error, setError] = useState('')
  const [retry, setRetry] = useState(0)
  const latestInput = useRef({ restaurantID, visitID, restaurants, visits, sourceDetail })
  latestInput.current = { restaurantID, visitID, restaurants, visits, sourceDetail }
  const companionOptions = useMemo(() => [...new Set(visits.flatMap((visit) => visit.companions))].sort((a, b) => a.localeCompare(b, 'zh-CN')), [visits])

  useEffect(() => {
    let active = true
    setError('')
    setLoaded(null)
    boundedVisitEditorRead(loadVisitEditorContext(platform, latestInput.current)).then((context) => {
      if (active) setLoaded({ identity, context })
    }).catch((reason) => {
      if (active) setError(reason instanceof Error ? reason.message : '无法读取到访记录，请重试。')
    })
    return () => { active = false }
    // Snapshot refreshes must never replace an in-progress local editor draft.
  }, [platform, identity, retry])

  if (loaded?.identity !== identity) return <main className="tm-hybrid-page" data-visit-editor-state={error ? 'error' : 'loading'}>
    <HybridBackButton onBack={onClose} />
    <HybridState kind={error ? 'error' : 'loading'} title={error ? '无法打开到访记录' : '正在读取到访记录'} message={error || '正在读取这次到访的原始内容…'} action={error ? <button onClick={() => setRetry((value) => value + 1)} type="button">重试</button> : undefined} />
  </main>

  const { restaurant, visit: existingVisit } = loaded.context

  return <AddVisitModal
    key={identity}
    companionOptions={companionOptions}
    initialVisit={existingVisit ?? undefined}
    maxPhotos={visitPhotoLimit(membershipTier)}
    canUploadDishPhotos={membershipTier === 'member'}
    onClose={onClose}
    onDelete={existingVisit ? async () => {
      const result = await platform.visit.delete(existingVisit.id)
      if (result.deletedRestaurantID) onRestaurantDeleted(result.deletedRestaurantID)
      else onSaved(result.restaurantID)
    } : undefined}
    onSave={async (input) => {
      const result = await platform.visit.save({
        restaurantID: restaurant.id,
        visitID: existingVisit?.id ?? null,
        draft: visitWriteDraft(input),
        ...(platform.kind === 'browser' ? { browserPhotoMaterial: {
          photos: input.photos, photoIds: input.photoIds ?? [],
          dishPhotos: input.dishes.map(({ id, imageData }) => ({ id, imageData })),
        } } : {}),
      })
      if (result.photoWarning) window.alert(result.photoWarning)
      onSaved(result.restaurantID)
    }}
    onPickNativePhotos={platform.kind === 'native' ? async (selectionLimit) => (await platform.photo.pick(selectionLimit)).photos.map((photo) => ({
      source: photo.preview.resourceURL,
      photoID: photo.photoID,
    })) : undefined}
    onCaptureNativePhoto={platform.kind === 'native' ? async () => {
      const photo = (await platform.photo.capture()).photos[0]
      return photo ? { source: photo.preview.resourceURL, photoID: photo.photoID } : null
    } : undefined}
    onRemoveNativePhoto={platform.kind === 'native' ? (photoID) => platform.photo.discard(photoID) : undefined}
    photoUpgradeAvailable={membershipTier !== 'member'}
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
    pendingPhotos: input.pendingNativePhotos ?? [],
    note: input.note,
  }
}
