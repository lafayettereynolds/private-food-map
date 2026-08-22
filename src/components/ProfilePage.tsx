import { useRef, useState, type ChangeEvent, type FormEvent } from 'react'
import { Camera, MapPin, Save, Star, UserRound } from 'lucide-react'
import type { RestaurantSummary, UserProfile, Visit } from '../types/domain'
import { optimizeAvatarImage } from '../utils/images'
import { formatVisitDateTime } from '../utils/date'
import { SyncedImage } from './SyncedImage'

export function ProfilePage({
  user,
  restaurants,
  onSave,
  onSelectRestaurant,
  editable = true,
}: {
  user: UserProfile
  restaurants: RestaurantSummary[]
  onSave: (changes: Pick<UserProfile, 'nickname' | 'bio' | 'city' | 'avatarImageData' | 'avatarPhotoId'>) => Promise<unknown>
  onSelectRestaurant: (restaurant: RestaurantSummary) => void
  editable?: boolean
}) {
  const inputRef = useRef<HTMLInputElement>(null)
  const [nickname, setNickname] = useState(user.nickname)
  const [bio, setBio] = useState(user.bio)
  const [city, setCity] = useState(user.city)
  const [avatarImageData, setAvatarImageData] = useState(user.avatarImageData)
  const [avatarPhotoId, setAvatarPhotoId] = useState(user.avatarPhotoId)
  const [saving, setSaving] = useState(false)
  const [message, setMessage] = useState('')
  const timeline = restaurants
    .flatMap((restaurant) => restaurant.visits.map((visit) => ({ restaurant, visit })))
    .sort((a, b) => b.visit.visitedAt.localeCompare(a.visit.visitedAt))

  async function chooseAvatar(event: ChangeEvent<HTMLInputElement>) {
    const file = event.target.files?.[0]
    event.target.value = ''
    if (!file) return
    setAvatarImageData(await optimizeAvatarImage(file))
    setAvatarPhotoId(null)
  }

  async function submit(event: FormEvent) {
    event.preventDefault()
    setSaving(true)
    setMessage('')
    try {
      await onSave({ nickname, bio, city, avatarImageData, avatarPhotoId })
      setMessage('个人资料已保存')
    } finally {
      setSaving(false)
    }
  }

  return (
    <section className="social-page profile-page">
      <div className="profile-hero">
        <button aria-label={editable ? '更换头像' : `${user.nickname} 的头像`} className="profile-avatar" disabled={!editable} onClick={() => inputRef.current?.click()} type="button">
          {avatarImageData || avatarPhotoId ? <SyncedImage alt="我的头像" photoId={avatarPhotoId} source={avatarImageData} /> : <UserRound size={34} />}
          {editable ? <span><Camera size={14} /></span> : null}
        </button>
        <input accept="image/*" hidden onChange={chooseAvatar} ref={inputRef} type="file" />
        <div><span className="eyebrow">MY TASTE MAP</span><h1>{nickname || 'Taste Map 用户'}</h1><p>{bio || '记录每一次真实的味觉记忆。'}</p></div>
      </div>
      {editable ? <form className="profile-editor" onSubmit={submit}>
        <label className="field"><span>昵称</span><input maxLength={30} onChange={(event) => setNickname(event.target.value)} required value={nickname} /></label>
        <label className="field"><span>城市</span><input maxLength={30} onChange={(event) => setCity(event.target.value)} placeholder="例如：杭州" value={city} /></label>
        <label className="field profile-bio"><span>个人资料</span><textarea maxLength={160} onChange={(event) => setBio(event.target.value)} placeholder="写一句关于你的饮食偏好" rows={2} value={bio} /></label>
        <button className="secondary-button" disabled={saving} type="submit"><Save size={15} /> 保存资料</button>
        {message ? <small>{message}</small> : null}
      </form> : null}
      <section className="profile-timeline">
        <header><div><span className="eyebrow">FOOD TIMELINE</span><h2>饮食时间线</h2></div><strong>{timeline.length} 条</strong></header>
        {timeline.length ? <div className="timeline-list">{timeline.map(({ restaurant, visit }) => <TimelineRow key={visit.id} onClick={() => onSelectRestaurant(restaurant)} restaurant={restaurant} visit={visit} />)}</div> : <div className="social-empty"><MapPin size={22} /><strong>还没有到访记录</strong><p>记录餐厅后，时间线会自动从 Visit 生成。</p></div>}
      </section>
    </section>
  )
}

function TimelineRow({ restaurant, visit, onClick }: { restaurant: RestaurantSummary; visit: Visit; onClick: () => void }) {
  return <button className="timeline-row" onClick={onClick} type="button"><time>{formatVisitDateTime(visit.visitedAt)}</time><div><strong>{restaurant.name}</strong><span>{restaurant.city}{visit.rating ? <> · <Star fill="currentColor" size={11} /> {visit.rating} 星</> : null}</span>{visit.note ? <p>{visit.note}</p> : null}</div></button>
}
