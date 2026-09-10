import { useEffect, useRef, useState } from 'react'
import { MoreHorizontal } from 'lucide-react'
import { ModalShell } from './ModalShell'
import type { TasteMapPlatform } from '../platform/TasteMapPlatform'
import type { ModerationReasonV1, UGCSafetyCapabilities, UGCSafetyTarget } from '../contracts/releaseSafetyV1'
import './ugcSafetyMenu.css'
import { ugcSafetyState } from './ugcSafetyState'

const reasons: Array<[ModerationReasonV1, string]> = [
  ['spam', '垃圾 / 广告'], ['harassment', '骚扰或攻击'], ['hate', '仇恨内容'],
  ['sexual', '不当色情内容'], ['violence', '暴力或危险内容'], ['privacy', '泄露隐私'], ['other', '其他'],
]

/** The service decides action eligibility; the renderer never compares owner IDs. */
export function UGCSafetyMenu({ platform, target, onHidden }: {
  platform: TasteMapPlatform; target: UGCSafetyTarget
  onHidden?: (action: 'delete' | 'block', ownerID: string, hidden: boolean) => void
}) {
  const [open, setOpen] = useState(false)
  const [capabilities, setCapabilities] = useState<UGCSafetyCapabilities | null>(null)
  const [error, setError] = useState('')
  const [message, setMessage] = useState('')
  const [busy, setBusy] = useState(false)
  const [reason, setReason] = useState<ModerationReasonV1>('spam')
  const [details, setDetails] = useState('')
  const [action, setAction] = useState<'report' | 'block' | 'delete' | null>(null)
  const requestID = useRef(crypto.randomUUID())
  const epoch = useRef(0)
  useEffect(() => {
    setOpen(false); setCapabilities(null); setBusy(false); setMessage('')
    requestID.current = crypto.randomUUID()
    return () => { epoch.current += 1 }
  }, [platform, target.type, target.id])
  useEffect(() => {
    const subscription = platform.events.subscribe(event => {
      if (event.name === 'auth.changed') { epoch.current += 1; setOpen(false); setCapabilities(null); setMessage(''); setBusy(false) }
    })
    return () => { void subscription.then(value => value.remove()).catch(() => undefined) }
  }, [platform])

  async function show() {
    setOpen(true); setError(''); setCapabilities(null); setAction(null)
    const current = ++epoch.current
    try {
      if (!platform.community.safety) throw new Error('当前版本暂不支持，请更新后重试。')
      const value = await platform.community.safety(target)
      if (current === epoch.current) setCapabilities(value)
    } catch (error) { if (current === epoch.current) setError(error instanceof Error ? error.message : '操作暂不可用，请重试。') }
  }
  async function submit() {
    if (!capabilities || !action || busy) return
    const current = epoch.current
    const selected = action
    setBusy(true); setError('')
    // Keep this menu mounted while the caller hides only the comment body.
    if (selected === 'delete') {
      ugcSafetyState(platform).update('deleted', target.id, true)
      onHidden?.('delete', capabilities.ownerID, true)
    }
    try {
      if (selected === 'report' && capabilities.canReport && platform.community.report) {
        await platform.community.report(target, reason, details, requestID.current)
      } else if (selected === 'block' && capabilities.canBlock && platform.community.block) {
        await platform.community.block(target)
      } else if (selected === 'delete' && capabilities.canDelete && platform.community.deleteComment) {
        await platform.community.deleteComment(target)
      } else throw new Error('此操作不可用。')
      if (current !== epoch.current) return
      if (selected === 'block') {
        ugcSafetyState(platform).update('blocked', capabilities.ownerID, true)
        onHidden?.('block', capabilities.ownerID, true)
      }
      setMessage(selected === 'report' ? '举报已收到，将按社区规则审核。' : selected === 'block' ? '已屏蔽此用户。' : '评论已删除。')
      requestID.current = crypto.randomUUID(); setOpen(false)
    } catch (error) {
      if (current !== epoch.current) return
      if (selected === 'delete') {
        ugcSafetyState(platform).update('deleted', target.id, false)
        onHidden?.('delete', capabilities.ownerID, false)
      }
      setError(error instanceof Error ? error.message : '操作未完成，请重试。')
    } finally { if (current === epoch.current) setBusy(false) }
  }
  return <span className="tm-ugc-safety" onClick={event => event.stopPropagation()}>
    <button type="button" aria-label="内容更多操作" aria-haspopup="dialog" onClick={() => void show()}><MoreHorizontal size={20} /></button>
    {message ? <span role="status">{message}</span> : null}
    {open ? <ModalShell title={action === 'report' ? '举报内容' : action === 'block' ? '屏蔽此用户' : action === 'delete' ? '删除评论' : '内容操作'} dismissDisabled={busy} onClose={() => { if (!busy) setOpen(false) }} size="small">
      <div className="tm-ugc-safety-actions">
        {error ? <p role="alert">{error}</p> : null}
        {!capabilities && !error ? <p role="status">正在确认可用操作…</p> : null}
        {!capabilities && error ? <button type="button" onClick={() => void show()}>重试</button> : null}
        {capabilities && !action ? <>
          {capabilities.canReport ? <button type="button" onClick={() => setAction('report')}>举报</button> : null}
          {capabilities.canBlock ? <button type="button" onClick={() => setAction('block')}>屏蔽此用户</button> : null}
          {capabilities.canDelete ? <button type="button" onClick={() => setAction('delete')}>删除评论</button> : null}
          {!capabilities.canReport && !capabilities.canBlock && !capabilities.canDelete ? <p>这是你的内容，可在记录中管理。</p> : null}
        </> : null}
        {action === 'report' ? <><label>举报原因<select disabled={busy} value={reason} onChange={event => { setReason(event.target.value as ModerationReasonV1); requestID.current = crypto.randomUUID() }}>{reasons.map(([value, label]) => <option key={value} value={value}>{label}</option>)}</select></label><label>补充说明（选填）<textarea disabled={busy} value={details} maxLength={500} onChange={event => { setDetails(event.target.value); requestID.current = crypto.randomUUID() }} /></label></> : null}
        {action === 'block' ? <p>屏蔽后不再显示该用户的公开内容，不会删除对方的数据。</p> : null}
        {action === 'delete' ? <p>确认删除这条评论？删除后无法恢复。</p> : null}
        {action ? <button type="button" disabled={busy} className="primary-button" onClick={() => void submit()}>{busy ? '正在处理…' : action === 'report' ? '提交举报' : '确认'}</button> : null}
      </div>
    </ModalShell> : null}
  </span>
}
