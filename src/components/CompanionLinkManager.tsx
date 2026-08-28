import { useEffect, useMemo, useState } from 'react'
import { useLiveQuery } from 'dexie-react-hooks'
import { Check, Link2, Search, Unlink, X } from 'lucide-react'
import { db } from '../db/appDb'
import { ensureDiningCompanions } from '../db/diningCompanions'
import { fetchCompanionHistory, fetchCompanionLinks, importCompanionHistory, requestCompanionLink, respondToCompanionLink, searchCloudUsers, unlinkCompanion, type PublicUser } from '../services/socialApi'
import type { CompanionLinkRequest, DiningCompanion, HistoricalMealFact } from '../types/domain'

export function CompanionLinkManager({ currentUserId, onImported }: { currentUserId: string; onImported?: (message: string) => void }) {
  const storedVisits = useLiveQuery(() => db.visits.filter((visit) => !visit.deletedAt).toArray(), [])
  const storedCompanionRows = useLiveQuery(() => db.diningCompanions.filter((item) => !item.deletedAt).toArray(), [])
  const visits = useMemo(() => storedVisits ?? [], [storedVisits])
  const storedCompanions = useMemo(() => storedCompanionRows ?? [], [storedCompanionRows])
  const [companions, setCompanions] = useState<DiningCompanion[]>([])
  const [requests, setRequests] = useState<CompanionLinkRequest[]>([])
  const [users, setUsers] = useState<PublicUser[]>([])
  const [selectedCompanionId, setSelectedCompanionId] = useState('')
  const [query, setQuery] = useState('')
  const [searchResults, setSearchResults] = useState<PublicUser[]>([])
  const [history, setHistory] = useState<{ requestId: string; facts: HistoricalMealFact[] } | null>(null)
  const [selectedFacts, setSelectedFacts] = useState<string[]>([])
  const [message, setMessage] = useState('')

  const refresh = () => fetchCompanionLinks().then((result) => {
    setCompanions(result.companions)
    setRequests(result.requests)
    setUsers(result.users)
  }).catch(() => undefined)

  useEffect(() => { void ensureDiningCompanions(visits.flatMap((visit) => visit.companions)) }, [visits])
  useEffect(() => { void refresh() }, [])
  useEffect(() => {
    if ([...query.trim()].length < 2) { setSearchResults([]); return }
    let active = true
    const timer = window.setTimeout(() => void searchCloudUsers(query).then((result) => { if (active) setSearchResults(result) }).catch(() => { if (active) setSearchResults([]) }), 280)
    return () => { active = false; window.clearTimeout(timer) }
  }, [query])

  const combinedCompanions = useMemo(() => {
    const map = new Map(storedCompanions.map((item) => [item.id, item]))
    companions.forEach((item) => map.set(item.id, item))
    return [...map.values()]
  }, [companions, storedCompanions])
  const selectedCompanion = combinedCompanions.find((item) => item.id === selectedCompanionId)
  const incoming = requests.filter((item) => item.targetUserId === currentUserId && item.status === 'pending')
  const acceptedIncoming = requests.filter((item) => item.targetUserId === currentUserId && item.status === 'accepted')
  const outgoing = requests.filter((item) => item.requesterUserId === currentUserId && item.status === 'pending')
  const userName = (id: string) => users.find((user) => user.id === id)?.nickname ?? 'Taste Map 用户'

  async function sendRequest(target: PublicUser) {
    if (!selectedCompanion) return
    setMessage('')
    await requestCompanionLink(selectedCompanion, target.id)
    setMessage(`已向 ${target.nickname} 发送关联请求`)
    setQuery('')
    await refresh()
  }

  async function respond(request: CompanionLinkRequest, status: 'accepted' | 'rejected') {
    await respondToCompanionLink(request.id, status)
    await refresh()
    if (status === 'accepted') await openHistory(request.id)
  }

  async function openHistory(requestId: string) {
    const result = await fetchCompanionHistory(requestId)
    setHistory({ requestId, facts: result.facts })
    setSelectedFacts(result.facts.map((fact) => fact.sourceVisitId))
  }

  async function importSelected() {
    if (!history || !selectedFacts.length) return
    const result = await importCompanionHistory(history.requestId, selectedFacts)
    setMessage(`已加入 ${result.imported} 条历史到访；评分、笔记、消费和照片均未复制。`)
    setHistory(null)
    onImported?.(`已加入 ${result.imported} 条历史到访`)
  }

  return <section className="companion-link-manager">
    <header><div><strong>饭搭子身份关联</strong><p>把过去记录的名字与真实 Taste Map 用户关联，必须由对方确认。</p></div><Link2 size={18} /></header>
    {incoming.map((request) => <article className="companion-link-request" key={request.id}><div><strong>{userName(request.requesterUserId)} 想把“{request.companionDisplayName}”与你关联</strong><p>{request.visitCount} 次共同用餐 · {request.restaurantCount} 家餐厅</p></div><div><button className="primary-button" onClick={() => void respond(request, 'accepted')} type="button"><Check size={13} />接受</button><button className="text-button" onClick={() => void respond(request, 'rejected')} type="button"><X size={13} />拒绝</button></div></article>)}
    {acceptedIncoming.length ? <div className="companion-history-entries">{acceptedIncoming.map((request) => <button key={request.id} onClick={() => void openHistory(request.id)} type="button"><span>与 {userName(request.requesterUserId)} 的历史共同用餐</span><strong>{request.visitCount} 次 · 查看</strong></button>)}</div> : null}
    <div className="companion-link-form">
      <label><span>过去的饭搭子</span><select onChange={(event) => setSelectedCompanionId(event.target.value)} value={selectedCompanionId}><option value="">请选择</option>{combinedCompanions.map((item) => <option key={item.id} value={item.id}>{item.displayName}{item.linkedUserId ? '（已关联）' : ''}</option>)}</select></label>
      {selectedCompanion?.linkedUserId ? <button className="secondary-button" onClick={() => void unlinkCompanion(selectedCompanion.id).then(refresh)} type="button"><Unlink size={13} />解除关联</button> : <label className="people-search"><Search size={15} /><input disabled={!selectedCompanion} onChange={(event) => setQuery(event.target.value)} placeholder="搜索要关联的用户" value={query} /></label>}
      {query.trim() ? <div className="companion-user-results">{searchResults.map((user) => <button key={user.id} onClick={() => void sendRequest(user)} type="button"><span><strong>{user.nickname}</strong><small>{user.city || '未填写城市'}</small></span><em>发送请求</em></button>)}</div> : null}
      {outgoing.map((request) => <p className="companion-link-pending" key={request.id}>“{request.companionDisplayName}”正在等待 {userName(request.targetUserId)} 确认</p>)}
    </div>
    {history ? <div className="companion-history-picker"><header><strong>发现历史共同用餐</strong><button onClick={() => setHistory(null)} type="button"><X size={15} /></button></header><p>只会创建餐厅与日期等共同事实，不复制对方的评分、笔记、消费或照片。</p><div>{history.facts.map((fact) => <label key={fact.sourceVisitId}><input checked={selectedFacts.includes(fact.sourceVisitId)} onChange={() => setSelectedFacts((current) => current.includes(fact.sourceVisitId) ? current.filter((id) => id !== fact.sourceVisitId) : [...current, fact.sourceVisitId])} type="checkbox" /><span><strong>{fact.restaurant.name}</strong><small>{new Date(fact.visitedAt).toLocaleString('zh-CN')}</small></span></label>)}</div><button className="primary-button" disabled={!selectedFacts.length} onClick={() => void importSelected()} type="button">批量加入去过（{selectedFacts.length}）</button></div> : null}
    {message ? <p className="form-success">{message}</p> : null}
  </section>
}
