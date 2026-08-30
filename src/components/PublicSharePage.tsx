import { ImageOff, MapPin, UserRound, Utensils } from 'lucide-react'
import { useEffect, useState } from 'react'
import { apiURL } from '../config/apiEnvironment'

type PublicSharePayload = {
  apiVersion: 1
  shareId: string
  entityType: 'restaurant' | 'profile' | 'list'
  entity: Record<string, unknown>
}

export function PublicSharePage({ shareId }: { shareId: string }) {
  const [share, setShare] = useState<PublicSharePayload | null>(null)
  const [error, setError] = useState('')
  useEffect(() => {
    let active = true
    void fetch(apiURL(`/api/public/shares/${encodeURIComponent(shareId)}`))
      .then(async (response) => {
        const body = await response.json() as PublicSharePayload & { error?: string }
        if (!response.ok) throw new Error(body.error || '这个分享暂时不可用。')
        if (active) setShare(body)
      })
      .catch((reason) => { if (active) setError(reason instanceof Error ? reason.message : '这个分享暂时不可用。') })
    return () => { active = false }
  }, [shareId])

  return <main className="public-share-page">
    <header className="public-restaurant-brand"><span>🍴</span><strong>Taste Map</strong></header>
    {!share && !error ? <section className="public-restaurant-state"><span className="loading-spinner" /><strong>正在打开分享</strong></section> : null}
    {error ? <section className="public-restaurant-state"><strong>这个分享已经不可用</strong><p>{error}</p><p>内容被删除或改为非公开后，原链接不会继续泄露资料。</p><a href="/">打开 Taste Map</a></section> : null}
    {share?.entityType === 'restaurant' ? <RestaurantShare entity={share.entity} /> : null}
    {share?.entityType === 'profile' ? <ProfileShare entity={share.entity} /> : null}
    {share?.entityType === 'list' ? <ListShare entity={share.entity} /> : null}
  </main>
}

function RestaurantShare({ entity }: { entity: Record<string, unknown> }) {
  const image = stringValue(entity.merchantImageUrl)
  const cuisines = stringArray(entity.cuisines)
  return <article className="public-share-card">
    {image ? <img className="public-share-cover" alt="餐厅封面" src={image} /> : <Placeholder icon="restaurant" />}
    <div className="public-share-body"><span className="eyebrow">TASTE MAP RESTAURANT</span>
      <h1>{stringValue(entity.name)}</h1>
      {cuisines.length ? <p>{cuisines.join(' · ')}</p> : null}
      <p><MapPin size={17} />{[stringValue(entity.city), stringValue(entity.address)].filter(Boolean).join(' · ')}</p>
      <OpenTasteMap />
    </div>
  </article>
}

function ProfileShare({ entity }: { entity: Record<string, unknown> }) {
  const statistics = objectValue(entity.statistics)
  return <article className="public-share-card"><Placeholder icon="profile" />
    <div className="public-share-body"><span className="eyebrow">TASTE MAP PROFILE</span>
      <h1>{stringValue(entity.displayName)}</h1>
      {stringValue(entity.city) ? <p><MapPin size={17} />{stringValue(entity.city)}</p> : null}
      {stringValue(entity.bio) ? <p>{stringValue(entity.bio)}</p> : null}
      <div className="public-share-stats"><strong>{numberValue(statistics.restaurantCount)} 家公开餐厅</strong><strong>{numberValue(statistics.visitCount)} 次公开到访</strong></div>
      <OpenTasteMap />
    </div>
  </article>
}

function ListShare({ entity }: { entity: Record<string, unknown> }) {
  const restaurants = Array.isArray(entity.restaurants)
    ? entity.restaurants.filter((value): value is Record<string, unknown> => Boolean(value) && typeof value === 'object' && !Array.isArray(value))
    : []
  return <article className="public-share-card"><Placeholder icon="list" />
    <div className="public-share-body"><span className="eyebrow">TASTE MAP LIST</span>
      <h1>{stringValue(entity.title)}</h1>
      <p>{stringValue(entity.ownerDisplayName)} · {numberValue(entity.restaurantCount)} 家餐厅</p>
      {stringValue(entity.description) ? <p>{stringValue(entity.description)}</p> : null}
      <ol className="public-share-list">{restaurants.map((restaurant, index) => <li key={`${stringValue(restaurant.name)}-${index}`}>
        <strong>{stringValue(restaurant.name)}</strong>
        <span>{[stringValue(restaurant.city), stringValue(restaurant.address)].filter(Boolean).join(' · ')}</span>
        {stringValue(restaurant.note) ? <small>{stringValue(restaurant.note)}</small> : null}
      </li>)}</ol>
      <OpenTasteMap />
    </div>
  </article>
}

function Placeholder({ icon }: { icon: 'restaurant' | 'profile' | 'list' }) {
  return <div className="public-share-cover is-placeholder">
    {icon === 'profile' ? <UserRound size={36} /> : icon === 'list' ? <Utensils size={36} /> : <ImageOff size={36} />}
  </div>
}

function OpenTasteMap() { return <a className="primary-button public-restaurant-cta" href="/">打开 Taste Map</a> }
function stringValue(value: unknown) { return typeof value === 'string' ? value : '' }
function numberValue(value: unknown) { return typeof value === 'number' && Number.isFinite(value) ? value : 0 }
function stringArray(value: unknown) { return Array.isArray(value) ? value.filter((item): item is string => typeof item === 'string') : [] }
function objectValue(value: unknown): Record<string, unknown> { return value && typeof value === 'object' && !Array.isArray(value) ? value as Record<string, unknown> : {} }
