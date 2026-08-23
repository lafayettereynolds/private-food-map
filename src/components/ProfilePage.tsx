import { useMemo, useRef, useState, type ChangeEvent, type FormEvent, type ReactNode } from 'react'
import { ArrowLeft, ChevronRight, Database, Dices, LockKeyhole, Save, Settings, ShieldCheck, UserPlus } from 'lucide-react'
import type { CloudSyncState } from '../types/cloudSync'
import type { RestaurantSummary, UserProfile, Visibility, Visit } from '../types/domain'
import { buildProfileInsights } from '../services/profileInsights'
import { optimizeAvatarImage } from '../utils/images'
import { AVATAR_PRESETS } from '../utils/avatarPresets'
import { ModalShell } from './ModalShell'
import { PresetAvatar, UserAvatar } from './UserAvatar'

export function ProfilePage({ user, restaurants = [], visits = [], followerCount = 0, followingCount = 0, onSave, editable = true, cloudSyncState, connections, followerConnections, followingConnections, onOpenRoulette, onOpenSettings, onMapPrivacyChange }: {
  user: UserProfile
  restaurants?: RestaurantSummary[]
  visits?: Visit[]
  followerCount?: number
  followingCount?: number
  onSave: (changes: Pick<UserProfile, 'nickname' | 'bio' | 'city' | 'avatarImageData' | 'avatarPhotoId' | 'avatarPresetId'>) => Promise<unknown>
  editable?: boolean
  cloudSyncState?: CloudSyncState
  connections?: ReactNode
  followerConnections?: ReactNode
  followingConnections?: ReactNode
  onOpenRoulette?: () => void
  onOpenSettings?: () => void
  onMapPrivacyChange?: (changes: Pick<UserProfile, 'mapSharingEnabled' | 'mapVisibility'>) => Promise<unknown>
}) {
  const [page, setPage] = useState<'dashboard' | 'account'>('dashboard')
  const [editorOpen, setEditorOpen] = useState(false)
  const [connectionsOpen, setConnectionsOpen] = useState<'discover' | 'following' | 'followers' | null>(null)
  const [detail, setDetail] = useState<'month' | 'year' | 'day' | 'taste' | 'data' | null>(null)
  const insights = useMemo(() => buildProfileInsights(restaurants, visits), [restaurants, visits])
  if (page === 'account') return <AccountPrivacyPage onBack={() => setPage('dashboard')} onMapPrivacyChange={onMapPrivacyChange} onOpenSettings={onOpenSettings} user={user} />

  return <section className="social-page profile-page profile-dashboard">
    {editable ? <div className="profile-dashboard__top"><button onClick={() => setConnectionsOpen('discover')} type="button"><UserPlus size={17} />添加好友</button><button aria-label="账号与隐私" onClick={() => setPage('account')} type="button"><Settings size={19} /></button></div> : null}
    <header className="profile-dashboard__header">
      <button aria-label={editable ? '编辑个人资料' : `${user.nickname} 的头像`} className="profile-avatar profile-dashboard__avatar" disabled={!editable} onClick={() => setEditorOpen(true)} type="button"><UserAvatar alt={user.nickname} avatarImageData={user.avatarImageData} avatarPhotoId={user.avatarPhotoId} avatarPresetId={user.avatarPresetId} membershipTier={user.membershipTier} /></button>
      <div><h1>{user.nickname}</h1><p>{user.city ? `${user.city} · ` : ''}{user.bio || '记录每一次真实的味觉记忆。'}</p>{editable ? <button className="profile-edit-button" onClick={() => setEditorOpen(true)} type="button">编辑资料</button> : null}</div>
    </header>
    <div className="profile-dashboard__counts"><button disabled={!editable} onClick={() => setConnectionsOpen('following')} type="button"><strong>{followingCount}</strong><small>我关注的</small></button><button disabled={!editable} onClick={() => setConnectionsOpen('followers')} type="button"><strong>{followerCount}</strong><small>关注我的</small></button><span><strong>{visits.length}</strong><small>记录</small></span><span><strong>{restaurants.filter((item) => item.status === 'visited').length}</strong><small>去过餐厅</small></span></div>
    {editable ? <button className="profile-roulette-card" onClick={onOpenRoulette} type="button"><span><Dices size={22} /></span><div><strong>今天吃什么</strong><small>从候选餐厅中随机挑一家</small></div><ChevronRight size={18} /></button> : null}
    <ProfileSection action="查看全部" onAction={() => setDetail('month')} title="回味"><div className="profile-memory-grid"><MemoryCard onClick={() => setDetail('month')} title="本月回顾" subtitle={`${new Date().getMonth() + 1} 月食记`} values={[`${insights.month.visitCount} 次用餐`, `${insights.month.restaurantCount} 家餐厅`, `¥${insights.month.spend} 消费`]} /><MemoryCard onClick={() => setDetail('year')} title="年度回顾" subtitle={`${new Date().getFullYear()} 食味年鉴`} values={[`${insights.year.visitCount} 次用餐`, `${insights.year.restaurantCount} 家餐厅`, `${insights.year.cityCount} 个城市`]} /><MemoryCard onClick={() => setDetail('day')} title="那年今日" subtitle={`${new Date().getMonth() + 1} 月 ${new Date().getDate()} 日`} values={insights.onThisDay.length ? insights.onThisDay.slice(0, 2).map((visit) => restaurants.find((item) => item.id === visit.restaurantId)?.name ?? '一次味觉记忆') : ['还没有往年记录']} /></div></ProfileSection>
    <ProfileSection action="查看完整档案" onAction={() => setDetail('taste')} title="我的口味档案"><TasteProfileSummary onClick={() => setDetail('taste')} profile={insights.tasteProfile} /></ProfileSection>
    <ProfileSection action="查看全部" onAction={() => setDetail('data')} title="我的数据"><button className="profile-data-grid" onClick={() => setDetail('data')} type="button"><span><strong>{visits.length}</strong><small>总用餐次数</small></span><span><strong>{restaurants.filter((item) => item.status === 'visited').length}</strong><small>去过餐厅</small></span><span><strong>{insights.averageScore?.toFixed(1) ?? '—'}</strong><small>平均评分</small></span><span><strong>{insights.cityCount}</strong><small>去过城市</small></span></button></ProfileSection>
    {editable ? <div className="profile-settings-links"><button onClick={onOpenSettings} type="button"><Database size={19} /><span><strong>数据与设置</strong><small>云同步、备份、恢复与图片存储</small></span><ChevronRight size={18} /></button><button onClick={() => setPage('account')} type="button"><ShieldCheck size={19} /><span><strong>账号与隐私</strong><small>账号安全、地图隐私与权限管理</small></span><ChevronRight size={18} /></button>{cloudSyncState ? <small className="profile-sync-line">{cloudSyncState.status === 'synced' ? '云端已同步' : cloudSyncState.status === 'syncing' ? '正在同步' : cloudSyncState.errorMessage || '等待同步'}</small> : null}</div> : null}
    {editorOpen ? <ProfileEditorModal onClose={() => setEditorOpen(false)} onSave={onSave} user={user} /> : null}
    {connectionsOpen ? <ModalShell description={connectionsOpen === 'discover' ? '搜索昵称或城市，找到想关注的 Taste Map 用户。' : '点击用户可以查看对方的公开资料。'} onClose={() => setConnectionsOpen(null)} size="large" title={connectionsOpen === 'discover' ? '发现好友' : connectionsOpen === 'following' ? '我关注的' : '关注我的'}>{connectionsOpen === 'discover' ? connections : connectionsOpen === 'following' ? followingConnections : followerConnections}</ModalShell> : null}
    {detail ? <ProfileDetailModal detail={detail} insights={insights} onClose={() => setDetail(null)} restaurants={restaurants} visits={visits} /> : null}
  </section>
}

function ProfileSection({ title, action, onAction, children }: { title: string; action: string; onAction?: () => void; children: ReactNode }) { return <section className="profile-dashboard__section"><header><h2>{title}</h2><button disabled={!onAction} onClick={onAction} type="button">{action}</button></header>{children}</section> }
function MemoryCard({ title, subtitle, values, onClick }: { title: string; subtitle: string; values: string[]; onClick: () => void }) { return <button onClick={onClick} type="button"><strong>{title}</strong><span>{subtitle}</span><div>{values.map((value) => <small key={value}>{value}</small>)}</div><ChevronRight size={15} /></button> }

type TasteProfile = ReturnType<typeof buildProfileInsights>['tasteProfile']

function TasteProfileSummary({ profile, onClick }: { profile: TasteProfile; onClick: () => void }) {
  if (profile.confidence === 'insufficient') return <button className="taste-profile-card taste-profile-card--summary" onClick={onClick} type="button"><p>{profile.summary}</p><small>基于 {profile.validVisitCount} 次有效记录 · 持续更新中</small></button>
  return <button className="taste-profile-card taste-profile-card--summary" onClick={onClick} type="button"><dl><div><dt>偏爱菜系</dt><dd>{profile.preferredCuisines.slice(0, 3).map((item) => item.label).join(' · ') || '逐渐形成中'}</dd></div><div><dt>常去价位</dt><dd>{profile.preferredPriceRange}</dd></div><div><dt>高分偏好</dt><dd>{profile.highRatingTraits.slice(0, 3).map((item) => item.label).join(' · ') || '继续记录后生成'}</dd></div><div className="taste-profile-summary"><dt>口味总结</dt><dd>{profile.summary}</dd></div></dl><small>基于 {profile.validVisitCount} 次有效记录生成 · 持续更新中</small></button>
}

function ProfileDetailModal({ detail, insights, visits, restaurants, onClose }: { detail: 'month' | 'year' | 'day' | 'taste' | 'data'; insights: ReturnType<typeof buildProfileInsights>; visits: Visit[]; restaurants: RestaurantSummary[]; onClose: () => void }) {
  if (detail === 'taste') return <ModalShell description="根据真实到访、评分、重复到访与结构化体验持续更新。" onClose={onClose} size="large" title="完整口味档案"><TasteProfileDetails profile={insights.tasteProfile} /></ModalShell>
  if (detail === 'data') return <ModalShell description="只统计当前账号的有效记录。" onClose={onClose} size="large" title="我的数据"><div className="profile-data-detail"><span><strong>{visits.length}</strong>总用餐次数</span><span><strong>{restaurants.filter((item) => item.status === 'visited').length}</strong>去过餐厅</span><span><strong>{insights.cityCount}</strong>去过城市</span><span><strong>{insights.tasteProfile.repeatVisit.tendency}</strong>复购倾向</span></div></ModalShell>
  const selectedVisits = detail === 'month' ? insights.monthVisits : detail === 'year' ? insights.yearVisits : insights.onThisDay
  const title = detail === 'month' ? '本月回顾' : detail === 'year' ? '年度回顾' : '那年今日'
  return <ModalShell description={`${selectedVisits.length} 条真实到访记录`} onClose={onClose} size="large" title={title}><div className="profile-memory-detail">{selectedVisits.length ? selectedVisits.map((visit) => <article key={visit.id}><time>{new Date(visit.visitedAt).toLocaleDateString('zh-CN')}</time><strong>{restaurants.find((item) => item.id === visit.restaurantId)?.name ?? '一次味觉记忆'}</strong>{visit.note ? <p>{visit.note}</p> : null}</article>) : <p>这一段时间还没有记录。</p>}</div></ModalShell>
}

function TasteProfileDetails({ profile }: { profile: TasteProfile }) {
  const percent = (value: number) => `${Math.round(value * 100)}%`
  return <div className="taste-profile-details"><section><h3>菜系偏好</h3>{profile.preferredCuisines.length ? <ol>{profile.preferredCuisines.map((item) => <li key={item.label}><span>{item.label}</span><small>{item.visits} 次相关记录</small></li>)}</ol> : <p>多记录一些带菜系标签的餐厅后生成。</p>}</section><section><h3>价位偏好</h3><div className="taste-profile-bars">{profile.priceBuckets.map((bucket) => <div key={bucket.key}><span>{bucket.label}</span><i><b style={{ width: percent(bucket.share) }} /></i><em>{percent(bucket.share)}</em></div>)}</div></section><section><h3>你容易给高分的特征</h3><div className="taste-profile-tags">{profile.highRatingTraits.length ? profile.highRatingTraits.map((item) => <span key={item.label}>{item.label}</span>) : <p>高分特征仍在形成中。</p>}</div></section><section><h3>用餐场景偏好</h3><div className="taste-profile-bars">{profile.scenes.slice(0, 6).map((scene) => <div key={scene.label}><span>{scene.label}</span><i><b style={{ width: percent(scene.share) }} /></i><em>{percent(scene.share)}</em></div>)}</div></section><section className="taste-profile-compact-grid"><div><h3>到店 / 外卖</h3><p>到店 {percent(profile.diningMode.dineInShare)} · 外卖 {percent(profile.diningMode.takeoutShare)}</p></div><div><h3>复购倾向</h3><p>{profile.repeatVisit.tendency} · 重复到访 {percent(profile.repeatVisit.share)}</p></div></section><section><h3>评分习惯</h3><div className="taste-rating-grid"><span><strong>{profile.ratingBehavior.average?.toFixed(1) ?? '—'}</strong>平均评分</span><span><strong>{percent(profile.ratingBehavior.aboveEightShare)}</strong>8 分以上</span><span><strong>{percent(profile.ratingBehavior.aboveNineShare)}</strong>9 分以上</span><span><strong>{percent(profile.ratingBehavior.lowShare)}</strong>低分记录</span></div></section><section className="taste-profile-conclusion"><h3>口味总结</h3><p>{profile.summary}</p><small>基于 {profile.validVisitCount} 次有效记录 · {profile.confidence === 'stable' ? '稳定画像' : profile.confidence === 'forming' ? '初步形成' : '数据不足'}</small></section></div>
}

function ProfileEditorModal({ user, onSave, onClose }: { user: UserProfile; onSave: (changes: Pick<UserProfile, 'nickname' | 'bio' | 'city' | 'avatarImageData' | 'avatarPhotoId' | 'avatarPresetId'>) => Promise<unknown>; onClose: () => void }) {
  const inputRef = useRef<HTMLInputElement>(null)
  const [nickname, setNickname] = useState(user.nickname)
  const [bio, setBio] = useState(user.bio)
  const [city, setCity] = useState(user.city)
  const [avatarImageData, setAvatarImageData] = useState(user.avatarImageData)
  const [avatarPhotoId, setAvatarPhotoId] = useState(user.avatarPhotoId)
  const [avatarPresetId, setAvatarPresetId] = useState(user.avatarPresetId ?? 'polar-bear')
  const [saving, setSaving] = useState(false)
  const [message, setMessage] = useState('')
  async function chooseAvatar(event: ChangeEvent<HTMLInputElement>) { const file = event.target.files?.[0]; event.target.value = ''; if (file && user.membershipTier === 'member') { setAvatarImageData(await optimizeAvatarImage(file)); setAvatarPhotoId(null) } }
  async function submit(event: FormEvent) { event.preventDefault(); setSaving(true); setMessage(''); try { await onSave({ nickname, bio, city, avatarImageData, avatarPhotoId, avatarPresetId }); setMessage('个人资料已保存并等待云端同步') } finally { setSaving(false) } }
  return <ModalShell description="头像、昵称、城市和简介统一在这里修改。" onClose={onClose} size="large" title="编辑资料"><form className="profile-editor-modal" onSubmit={submit}><div className="avatar-preset-grid">{AVATAR_PRESETS.map((preset) => <button aria-label={preset.label} className={avatarPresetId === preset.id && !avatarImageData && !avatarPhotoId ? 'is-active' : ''} key={preset.id} onClick={() => { setAvatarPresetId(preset.id); setAvatarImageData(null); setAvatarPhotoId(null) }} type="button"><PresetAvatar id={preset.id} /><small>{preset.label}</small></button>)}</div>{user.membershipTier === 'member' ? <button className="custom-avatar-upload" onClick={() => inputRef.current?.click()} type="button">自定义上传头像</button> : <p className="custom-avatar-locked"><LockKeyhole size={14} />会员可上传自定义头像；预设头像均可直接使用。</p>}<input accept="image/*" hidden onChange={chooseAvatar} ref={inputRef} type="file" /><div className="profile-editor-modal__fields"><label className="field"><span>昵称</span><input maxLength={30} onChange={(event) => setNickname(event.target.value)} required value={nickname} /></label><label className="field"><span>城市</span><input maxLength={30} onChange={(event) => setCity(event.target.value)} placeholder="例如：杭州" value={city} /></label><label className="field"><span>个人简介</span><textarea maxLength={160} onChange={(event) => setBio(event.target.value)} rows={3} value={bio} /></label></div><footer><span>{message}</span><button className="primary-button" disabled={saving} type="submit"><Save size={15} />{saving ? '保存中' : '保存资料'}</button></footer></form></ModalShell>
}

function AccountPrivacyPage({ user, onBack, onOpenSettings, onMapPrivacyChange }: { user: UserProfile; onBack: () => void; onOpenSettings?: () => void; onMapPrivacyChange?: (changes: Pick<UserProfile, 'mapSharingEnabled' | 'mapVisibility'>) => Promise<unknown> }) {
  return <section className="social-page account-privacy-page"><header><button aria-label="返回我的" onClick={onBack} type="button"><ArrowLeft size={20} /></button><h1>账号与隐私</h1><span /></header><SettingsGroup title="账户"><SettingRow label="登录方式" value={user.authProvider === 'cloudflare-access' ? 'Cloudflare Access' : '本地账号'} /><SettingRow label="绑定邮箱" value={user.email || '未绑定'} /></SettingsGroup><SettingsGroup title="隐私设置"><div className="account-map-privacy"><span><strong>个人主页可见范围</strong><small>决定其他用户能否看到你的地图足迹</small></span><div>{([['private', '仅自己'], ['friends', '好友'], ['public', '公开']] as [Visibility, string][]).map(([value, label]) => <button className={user.mapVisibility === value && user.mapSharingEnabled === (value !== 'private') ? 'is-active' : ''} key={value} onClick={() => void onMapPrivacyChange?.({ mapSharingEnabled: value !== 'private', mapVisibility: value })} type="button">{label}</button>)}</div></div><SettingRow label="公开记录默认权限" value="每次记录时选择" /><SettingRow label="谁可以给我发送消息" value="好友" /></SettingsGroup><SettingsGroup title="权限管理"><SettingRow label="定位权限" value="由浏览器管理" /><SettingRow label="照片权限" value="选择照片时授权" /><SettingRow label="通知权限" value="由浏览器管理" /></SettingsGroup><SettingsGroup title="数据管理"><button className="account-setting-button" onClick={onOpenSettings} type="button"><span><strong>导出、备份与恢复</strong><small>打开数据与设置</small></span><ChevronRight size={17} /></button></SettingsGroup><SettingsGroup title="关于"><SettingRow label="隐私政策" value="查看" /><SettingRow label="用户协议" value="查看" /><SettingRow label="帮助与反馈" value="查看" /><SettingRow label="关于 Taste Map" value="v1.2.0" /></SettingsGroup><section className="danger-zone"><strong>危险操作</strong><button disabled type="button">删除账号</button><small>账号删除需要再次验证登录身份，当前不会误触执行。</small></section></section>
}
function SettingsGroup({ title, children }: { title: string; children: ReactNode }) { return <section className="account-settings-group"><h2>{title}</h2><div>{children}</div></section> }
function SettingRow({ label, value }: { label: string; value: string }) { return <button className="account-setting-button" type="button"><span><strong>{label}</strong></span><em>{value}</em><ChevronRight size={16} /></button> }
