import { useEffect, useRef, useState, type ChangeEvent, type FormEvent, type ReactNode } from 'react'
import { Camera, Crown, Dices, LockKeyhole, Save, Settings, ShieldCheck } from 'lucide-react'
import type { UserProfile, Visibility } from '../types/domain'
import type { CloudSyncState } from '../types/cloudSync'
import { optimizeAvatarImage } from '../utils/images'
import { CloudSyncIndicator } from './CloudSyncIndicator'
import { AVATAR_PRESETS } from '../utils/avatarPresets'
import { PresetAvatar, UserAvatar } from './UserAvatar'

export function ProfilePage({
  user,
  onSave,
  editable = true,
  cloudSyncState,
  connections,
  onOpenRoulette,
  onOpenSettings,
  onMapPrivacyChange,
}: {
  user: UserProfile
  onSave: (changes: Pick<UserProfile, 'nickname' | 'bio' | 'city' | 'avatarImageData' | 'avatarPhotoId' | 'avatarPresetId'>) => Promise<unknown>
  editable?: boolean
  cloudSyncState?: CloudSyncState
  connections?: ReactNode
  onOpenRoulette?: () => void
  onOpenSettings?: () => void
  onMapPrivacyChange?: (changes: Pick<UserProfile, 'mapSharingEnabled' | 'mapVisibility'>) => Promise<unknown>
}) {
  const inputRef = useRef<HTMLInputElement>(null)
  const [nickname, setNickname] = useState(user.nickname)
  const [bio, setBio] = useState(user.bio)
  const [city, setCity] = useState(user.city)
  const [avatarImageData, setAvatarImageData] = useState(user.avatarImageData)
  const [avatarPhotoId, setAvatarPhotoId] = useState(user.avatarPhotoId)
  const [avatarPresetId, setAvatarPresetId] = useState(user.avatarPresetId ?? 'polar-bear')
  const [avatarPickerOpen, setAvatarPickerOpen] = useState(false)
  const [saving, setSaving] = useState(false)
  const [message, setMessage] = useState('')
  useEffect(() => {
    setNickname(user.nickname)
    setBio(user.bio)
    setCity(user.city)
    setAvatarImageData(user.avatarImageData)
    setAvatarPhotoId(user.avatarPhotoId)
    setAvatarPresetId(user.avatarPresetId ?? 'polar-bear')
  }, [user.avatarImageData, user.avatarPhotoId, user.avatarPresetId, user.bio, user.city, user.id, user.nickname, user.updatedAt])

  async function chooseAvatar(event: ChangeEvent<HTMLInputElement>) {
    const file = event.target.files?.[0]
    event.target.value = ''
    if (!file || user.membershipTier !== 'member') return
    setAvatarImageData(await optimizeAvatarImage(file))
    setAvatarPhotoId(null)
  }

  async function submit(event: FormEvent) {
    event.preventDefault()
    setSaving(true)
    setMessage('')
    try {
      await onSave({ nickname, bio, city, avatarImageData, avatarPhotoId, avatarPresetId })
      setMessage('个人资料已保存')
    } finally {
      setSaving(false)
    }
  }

  return (
    <section className="social-page profile-page">
      <div className="profile-hero profile-hero--centered">
        <button aria-label={editable ? '选择头像' : `${user.nickname} 的头像`} className="profile-avatar" disabled={!editable} onClick={() => setAvatarPickerOpen((open) => !open)} type="button">
          <UserAvatar alt="我的头像" avatarImageData={avatarImageData} avatarPhotoId={avatarPhotoId} avatarPresetId={avatarPresetId} membershipTier={user.membershipTier} />
          {editable ? <span><Camera size={14} /></span> : null}
        </button>
        <input accept="image/*" disabled={user.membershipTier !== 'member'} hidden onChange={chooseAvatar} ref={inputRef} type="file" />
        <div><span className="eyebrow">MY TASTE MAP</span><h1>{nickname || 'Taste Map 用户'}</h1><p>{bio || '记录每一次真实的味觉记忆。'}</p><small className={`membership-label${user.membershipTier === 'member' ? ' is-member' : ''}`}>{user.membershipTier === 'member' ? <><Crown size={12} /> Taste Map 会员</> : 'Taste Map 用户'}</small></div>
      </div>
      {editable && avatarPickerOpen ? <section className="avatar-picker-panel"><header><div><strong>选择头像</strong><span>默认使用北极熊，选择后保存资料即可同步。</span></div></header><div className="avatar-preset-grid">{AVATAR_PRESETS.map((preset) => <button aria-label={preset.label} className={avatarPresetId === preset.id && (user.membershipTier !== 'member' || !avatarImageData && !avatarPhotoId) ? 'is-active' : ''} key={preset.id} onClick={() => { setAvatarPresetId(preset.id); setAvatarImageData(null); setAvatarPhotoId(null) }} type="button"><PresetAvatar id={preset.id} /><small>{preset.label}</small></button>)}</div>{user.membershipTier === 'member' ? <button className="custom-avatar-upload" onClick={() => inputRef.current?.click()} type="button"><Camera size={15} /> 自定义上传头像</button> : <p className="custom-avatar-locked"><LockKeyhole size={14} /> 会员可自定义上传头像；普通用户可使用上面的全部预设头像。</p>}</section> : null}
      {editable && connections ? connections : null}
      {editable ? <form className="profile-editor" onSubmit={submit}>
        <label className="field"><span>昵称</span><input maxLength={30} onChange={(event) => setNickname(event.target.value)} required value={nickname} /></label>
        <label className="field"><span>城市</span><input maxLength={30} onChange={(event) => setCity(event.target.value)} placeholder="例如：杭州" value={city} /></label>
        <label className="field profile-bio"><span>个人资料</span><textarea maxLength={160} onChange={(event) => setBio(event.target.value)} placeholder="写一句关于你的饮食偏好" rows={2} value={bio} /></label>
        <button className="secondary-button" disabled={saving} type="submit"><Save size={15} /> 保存资料</button>
        {message ? <small>{message}</small> : null}
      </form> : null}
      {editable ? <section className="profile-toolbox">
        <div className="profile-quick-actions">
          <button className="roulette-profile-entry" onClick={onOpenRoulette} type="button"><span><Dices size={21} /></span><div><strong>今天吃什么</strong><small>临时添加，或从我的餐厅生成轮盘</small></div></button>
          <div className="profile-settings-entry"><div><strong>数据与设置</strong><small>云同步、备份、恢复和账号设置</small></div><div>{cloudSyncState && onOpenSettings ? <CloudSyncIndicator onOpenSettings={onOpenSettings} state={cloudSyncState} /> : null}<button aria-label="打开设置" className="settings-button" onClick={onOpenSettings} type="button"><Settings size={18} /></button></div></div>
        </div>
        <div className="map-privacy-setting">
          <header><div><ShieldCheck size={18} /><span><strong>我的地图隐私</strong><small>控制其他用户能否看到你的餐厅足迹</small></span></div><button aria-pressed={user.mapSharingEnabled} className={`privacy-switch${user.mapSharingEnabled ? ' is-on' : ''}`} onClick={() => void onMapPrivacyChange?.({ mapSharingEnabled: !user.mapSharingEnabled, mapVisibility: user.mapVisibility ?? 'private' })} type="button"><i /></button></header>
          <div className="privacy-choice" aria-label="地图可见范围">{([['private', '仅自己'], ['friends', '互相关注'], ['public', '公开']] as [Visibility, string][]).map(([visibility, label]) => <button className={user.mapVisibility === visibility ? 'is-active' : ''} disabled={!user.mapSharingEnabled && visibility !== 'private'} key={visibility} onClick={() => void onMapPrivacyChange?.({ mapSharingEnabled: visibility !== 'private', mapVisibility: visibility })} type="button">{label}</button>)}</div>
        </div>
      </section> : null}
    </section>
  )
}
