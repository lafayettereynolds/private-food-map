import { Clock3, ImageOff, MapPin, Phone, Star } from 'lucide-react'
import { useEffect, useState } from 'react'
import { apiURL } from '../config/apiEnvironment'

interface PublicRestaurantPayload {
  publicRestaurantId: string
  name: string
  coverImageUrl: string | null
  cuisines: string[]
  pricePerPerson: number | null
  city: string
  address: string
  phone: string | null
  openingHours: string | null
  publicRating: { value: number; sampleCount: number; confidence: 'low' | 'normal' } | null
}

export function PublicRestaurantPage({ publicRestaurantId }: { publicRestaurantId: string }) {
  const [restaurant, setRestaurant] = useState<PublicRestaurantPayload | null>(null)
  const [error, setError] = useState('')
  useEffect(() => {
    let active = true
    void fetch(apiURL(`/api/public/restaurants/${encodeURIComponent(publicRestaurantId)}`))
      .then(async (response) => {
        const body = await response.json() as PublicRestaurantPayload & { error?: string }
        if (!response.ok) throw new Error(body.error || '暂时无法读取这家餐厅。')
        if (active) setRestaurant(body)
      })
      .catch((reason) => { if (active) setError(reason instanceof Error ? reason.message : '暂时无法读取这家餐厅。') })
    return () => { active = false }
  }, [publicRestaurantId])

  return <main className="public-restaurant-page">
    <header className="public-restaurant-brand"><span>🍴</span><strong>Taste Map</strong></header>
    {!restaurant && !error ? <section className="public-restaurant-state"><span className="loading-spinner" /><strong>正在打开餐厅</strong></section> : null}
    {error ? <section className="public-restaurant-state"><strong>这个餐厅链接暂时不可用</strong><p>{error}</p><a href="/">打开 Taste Map</a></section> : null}
    {restaurant ? <article className="public-restaurant-card">
      {restaurant.coverImageUrl ? <img className="public-restaurant-cover" alt={`${restaurant.name} 餐厅封面`} src={restaurant.coverImageUrl} /> : <div className="public-restaurant-cover is-placeholder"><ImageOff size={32} /><span>暂无餐厅封面</span></div>}
      <div className="public-restaurant-body"><span className="eyebrow">TASTE MAP RESTAURANT</span><h1>{restaurant.name}</h1>
        <p className="public-restaurant-meta">{[restaurant.cuisines.join(' · '), restaurant.pricePerPerson ? `参考人均 ¥${Math.round(restaurant.pricePerPerson)}` : ''].filter(Boolean).join(' · ')}</p>
        <p><MapPin size={17} />{restaurant.city} · {restaurant.address}</p>
        <div className="public-restaurant-basics">{restaurant.phone ? <span><Phone size={16} />{restaurant.phone}</span> : null}{restaurant.openingHours ? <span><Clock3 size={16} />{restaurant.openingHours}</span> : null}</div>
        {restaurant.publicRating ? <section className="public-restaurant-rating"><Star size={19} /><div><strong>{restaurant.publicRating.value.toFixed(1)}</strong><span>全部用户 · {restaurant.publicRating.sampleCount} 人{restaurant.publicRating.confidence === 'low' ? ' · 样本较少' : ''}</span></div></section> : null}
        <a className="primary-button public-restaurant-cta" href="/">在 Taste Map 中查看</a>
      </div>
    </article> : null}
  </main>
}
