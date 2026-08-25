import { useEffect, useState, type FormEvent } from 'react'
import { Crown, LoaderCircle, Search, ShieldCheck } from 'lucide-react'
import type { MembershipAdminUser } from '../types/membership'
import { MembershipService } from '../services/membershipService'
import { ModalShell } from './ModalShell'

export function MembershipAdminEntry() {
  const [isAdmin, setIsAdmin] = useState(false)
  const [open, setOpen] = useState(false)
  useEffect(() => {
    void MembershipService.getEntitlement().then((result) => setIsAdmin(result.isAdmin)).catch(() => setIsAdmin(false))
  }, [])
  if (!isAdmin) return null
  return <><button className="account-setting-button" onClick={() => setOpen(true)} type="button"><span><strong>会员资格管理</strong><small>管理员赠送、修改与撤销</small></span><ShieldCheck size={17} /></button>{open ? <MembershipAdminModal onClose={() => setOpen(false)} /> : null}</>
}

function MembershipAdminModal({ onClose }: { onClose: () => void }) {
  const [query, setQuery] = useState('')
  const [users, setUsers] = useState<MembershipAdminUser[]>([])
  const [selected, setSelected] = useState<MembershipAdminUser | null>(null)
  const [duration, setDuration] = useState<'1m' | '3m' | '6m' | '1y' | 'lifetime' | 'custom'>('1m')
  const [customDate, setCustomDate] = useState('')
  const [note, setNote] = useState('')
  const [message, setMessage] = useState('')
  const [loading, setLoading] = useState(false)

  async function search(event?: FormEvent) {
    event?.preventDefault()
    setLoading(true); setMessage('')
    try { setUsers(await MembershipService.searchUsers(query)) } catch (error) { setMessage(error instanceof Error ? error.message : '搜索失败。') } finally { setLoading(false) }
  }

  async function mutate(action: () => Promise<unknown>) {
    setLoading(true); setMessage('')
    try {
      await action()
      setMessage('会员资格已更新。')
      const refreshed = await MembershipService.searchUsers(query)
      setUsers(refreshed)
      setSelected(selected ? refreshed.find((user) => user.id === selected.id) ?? null : null)
    } catch (error) { setMessage(error instanceof Error ? error.message : '操作失败。') } finally { setLoading(false) }
  }

  return <ModalShell description="会员资格以服务端权益为准，撤销赠送不会影响 App Store 购买。" onClose={onClose} size="large" title="会员资格管理"><div className="membership-admin"><form onSubmit={search}><label className="search-box"><Search size={15} /><input onChange={(event) => setQuery(event.target.value)} placeholder="搜索昵称、邮箱或城市" value={query} /></label><button className="secondary-button" disabled={loading} type="submit">搜索</button></form>{message ? <p>{message}</p> : null}{loading && !users.length ? <LoaderCircle className="spin" size={20} /> : null}<div className="membership-admin__users">{users.map((user) => <button className={selected?.id === user.id ? 'is-active' : ''} key={user.id} onClick={() => setSelected(user)} type="button"><span><strong>{user.nickname}</strong><small>{user.email || user.city || user.id}</small></span><em>{user.entitlement.isPremium ? <><Crown size={13} />会员</> : '免费'}</em></button>)}</div>{selected ? <section className="membership-admin__editor"><h3>{selected.nickname}</h3><div className="membership-admin__entitlements">{selected.entitlement.entitlements.map((item) => <article key={item.id}><span><strong>{sourceLabel(item.source)}</strong><small>{item.isLifetime ? '永久' : item.expiresAt ? `至 ${new Date(item.expiresAt).toLocaleDateString('zh-CN')}` : '无到期日'}</small></span>{item.source === 'admin_grant' && item.status === 'active' ? <button className="danger-ghost-button" disabled={loading} onClick={() => void mutate(() => MembershipService.revoke(item.id, '管理员撤销'))} type="button">撤销赠送</button> : null}</article>)}</div><label className="field"><span>赠送期限</span><select onChange={(event) => setDuration(event.target.value as typeof duration)} value={duration}><option value="1m">1 个月</option><option value="3m">3 个月</option><option value="6m">6 个月</option><option value="1y">1 年</option><option value="lifetime">永久</option><option value="custom">自定义到期</option></select></label>{duration === 'custom' ? <label className="field"><span>到期日期</span><input min={new Date().toISOString().slice(0, 10)} onChange={(event) => setCustomDate(event.target.value)} type="date" value={customDate} /></label> : null}<label className="field"><span>备注</span><input maxLength={160} onChange={(event) => setNote(event.target.value)} placeholder="赠送原因" value={note} /></label><button className="primary-button" disabled={loading || (duration === 'custom' && !customDate)} onClick={() => void mutate(() => MembershipService.grant(selected.id, duration, customDate ? new Date(`${customDate}T23:59:59.999Z`).toISOString() : null, note))} type="button"><Crown size={15} />确认赠送</button></section> : null}</div></ModalShell>
}

function sourceLabel(source: MembershipAdminUser['entitlement']['entitlements'][number]['source']) {
  return ({ app_store_monthly: 'App Store 月度', app_store_yearly: 'App Store 年度', app_store_lifetime: 'App Store 永久', admin_grant: '管理员赠送', promo: '活动赠送', redeem_code: '兑换码' } as const)[source]
}
