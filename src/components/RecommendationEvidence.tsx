import type { TasteMapHybridDiscoveryItemDTO, TasteMapHybridDiscoveryReasonDTO } from '../platform/TasteMapPlatform'
import { TasteMapRecommendationReasons } from './TasteMapDiscoveryShared'
import './recommendationEvidence.css'

export type RecommendationEvidenceItem = Pick<TasteMapHybridDiscoveryItemDTO, 'id' | 'mode' | 'restaurant' | 'reasons' | 'reason' | 'tasteEvidence' | 'sourceUser'>

/** Preserve supplied wording, but never present duplicate semantic claims as extra evidence. */
export function distinctRecommendationReasons(item: Pick<RecommendationEvidenceItem, 'reasons' | 'reason'>): TasteMapHybridDiscoveryReasonDTO[] {
  const reasons = item.reasons?.length ? item.reasons : item.reason?.trim() ? [{ code: '', text: item.reason }] : []
  const codes = new Set<string>()
  const texts = new Set<string>()
  return reasons.filter(reason => {
    const text = reason.text.trim()
    if (!text || texts.has(text) || (reason.code && codes.has(reason.code))) return false
    texts.add(text)
    if (reason.code) codes.add(reason.code)
    return true
  }).slice(0, 3)
}

const count = (value: number | undefined) => value != null && Number.isSafeInteger(value) && value >= 0 ? value : null
const date = (value: string | undefined) => {
  // Keep the source calendar date; don't invent a timezone or shift a visit to another day.
  const match = value?.match(/^(\d{4})-(\d{2})-(\d{2})(?:T|$)/)
  if (!match || !Number.isFinite(Date.parse(value!))) return '未提供有效日期'
  const calendarDate = new Date(`${match[1]}-${match[2]}-${match[3]}T00:00:00Z`)
  if (!Number.isFinite(calendarDate.getTime()) || calendarDate.toISOString().slice(0, 10) !== value!.slice(0, 10)) return '未提供有效日期'
  return `${match[1]}年${Number(match[2])}月${Number(match[3])}日`
}

function HistoryEvidence({ reason }: { reason: TasteMapHybridDiscoveryReasonDTO }) {
  const evidence = reason.evidence
  if (!evidence) return <p className="tm-recommendation-evidence__missing">当前数据只提供了这条推荐理由，尚未提供样本与记录明细。</p>
  const sample = count(evidence.sampleCount)
  const days = count(evidence.windowDays)
  const mean = evidence.meanOutOfTen
  const dimensions = [...new Set(evidence.dimensions?.map(value => value.trim()).filter(Boolean) ?? [])]
  const sampleLabel = reason.code === 'REPEAT_VISIT_PATTERN' ? '跨日期重复到访的不同餐厅' : reason.code === 'TASTE_TAG_MATCH' ? '高分参考餐厅' : '不同餐厅数'
  return <>
    <dl className="tm-recommendation-evidence__facts">
      <div><dt>{sampleLabel}</dt><dd>{sample == null ? '未提供' : `${sample} 家`}</dd></div>
      <div><dt>统计范围</dt><dd>{days && days > 0 ? `过去 ${days} 天` : '未提供起止时间'}</dd></div>
      {mean != null ? <div><dt>样本平均评分</dt><dd>{Number.isFinite(mean) && mean >= 0 && mean <= 10 ? `${mean.toFixed(1)} / 10` : '未提供有效评分'}</dd></div> : null}
      {reason.code === 'TASTE_TAG_MATCH' ? <div><dt>匹配字段</dt><dd>{dimensions.length ? dimensions.join('、') : '未提供'}</dd></div> : null}
      {evidence.referenceRestaurantID ? <div><dt>参考餐厅关联</dt><dd>已关联参考餐厅；名称与评分见上方原始理由</dd></div> : null}
    </dl>
    {evidence.participants?.length ? <>
      <h3>参与的餐厅记录</h3>
      <ul className="tm-recommendation-evidence__records">{evidence.participants.map(participant => <li key={participant.restaurantID}>
        <strong>{participant.restaurantName || '未提供餐厅名称'}</strong>
        <span>{participant.fields.tags.join('、') || '未提供分类'}</span>
        <span>{participant.fields.meanOutOfTen == null ? '未提供有效个人评分' : `个人代表评分 ${participant.fields.meanOutOfTen.toFixed(1)} / 10`} · {participant.fields.visitCount} 次记录</span>
        {participant.fields.firstVisitedAt ? <span>{date(participant.fields.firstVisitedAt)} — {date(participant.fields.lastVisitedAt ?? undefined)}</span> : null}
        <span>参与字段：分类、评分、到访日期{participant.fields.priceCurrency ? '、实录人均' : ''}</span>
        <small>餐厅记录：{participant.restaurantRecordIDs.join('、') || '未提供'}；代表到访：{participant.visitIDs.join('、') || '未提供'}</small>
      </li>)}</ul>
      {evidence.participantsTruncated ? <p>这里只展示前 {evidence.participants.length} 家，共 {evidence.participantCount} 家参与。</p> : null}
      {evidence.missingFields?.length ? <p className="tm-recommendation-evidence__missing">尚缺：{evidence.missingFields.map(field => ({ complete_visit_list: '完整逐次到访清单', restaurant_identity: '部分餐厅的稳定关联', price_currency: '人均币种' }[field] ?? '部分原始字段')).join('、')}。缺失不代表零次或零分。</p> : null}
    </> : <p className="tm-recommendation-evidence__missing">尚未提供逐店、逐次到访明细，不能在此核对具体记录。未提供的字段不代表零次到访或零分。</p>}
  </>
}

function SimilarEvidence({ item }: { item: RecommendationEvidenceItem }) {
  const evidence = item.tasteEvidence
  if (!evidence) return <p className="tm-recommendation-evidence__missing">当前数据尚未提供共同评分样本与同味用户的到访明细。</p>
  const seen = new Set<string>()
  const records = evidence.records.filter(record => {
    const key = `${record.user.userId}\u0000${record.visitId}`
    if (!record.visitId || seen.has(key)) return false
    seen.add(key)
    return true
  })
  const shared = count(evidence.sharedRestaurantCount)
  const supporters = count(evidence.supporterCount)
  return <>
    <dl className="tm-recommendation-evidence__facts">
      <div><dt>口味证据状态</dt><dd>{evidence.evidenceState === 'sufficient' ? '共同样本已达到充分门槛' : evidence.evidenceState === 'forming' ? '口味关系形成中，样本仍在积累' : '共同样本不足'}</dd></div>
      <div><dt>与你共同评分的不同餐厅</dt><dd>{shared == null ? '未提供' : `${shared} 家`}（{item.sourceUser?.name?.trim() || '来源用户'}与你的共同样本，不是所有用户的合计）</dd></div>
      <div><dt>支持这家店的同味用户</dt><dd>{supporters == null ? '未提供' : `${supporters} 人`}</dd></div>
      <div><dt>汇总方式</dt><dd>{evidence.aggregation === 'equal_user_mean' ? '先计算每位用户的均分，再按用户等权汇总' : '未提供'}</dd></div>
      <div><dt>最新可见到访</dt><dd>{date(evidence.latestVisibleVisitAt)}</dd></div>
    </dl>
    <h3>这家店的可见到访记录</h3>
    <p className="tm-recommendation-evidence__note">以下仅为当前接口提供且你有权查看的记录，不代表完整历史。每条显示该次实际评分，不以餐厅均分代替。</p>
    {records.length ? <ul className="tm-recommendation-evidence__records">{records.map(record => <li key={`${record.user.userId}:${record.visitId}`}>
      <div><strong>{record.user.displayName?.trim() || '未提供用户名称'}</strong><span>{date(record.visitedAt)}</span></div>
      <span>{record.rating != null && Number.isFinite(record.rating) && record.rating > 0 && record.rating <= 5 ? `${(record.rating * 2).toFixed(1)} / 10` : '未提供有效评分'}</span>
    </li>)}</ul> : <p className="tm-recommendation-evidence__missing">尚未提供可展示的到访记录。</p>}
    <p className="tm-recommendation-evidence__missing">共同评分餐厅的逐店清单与统计起止时间尚未提供；上方餐厅数不是到访次数，也不是喜欢概率。</p>
  </>
}

export function RecommendationEvidenceBody({ item }: { item: RecommendationEvidenceItem }) {
  const reasons = distinctRecommendationReasons(item)
  return <div className="tm-recommendation-evidence__body">
    {item.mode === 'similar_taste' ? <>
      <TasteMapRecommendationReasons reasons={reasons.map(reason => reason.text)} />
      <SimilarEvidence item={item} />
    </> : reasons.map((reason, index) => <section className="tm-recommendation-evidence__reason" key={`${reason.code}:${index}`}>
      <h3>{reason.text}</h3><HistoryEvidence reason={reason} />
    </section>)}
  </div>
}

/** Show the supplied reasons directly, without a redundant disclosure action. */
export function RecommendationEvidence({ item }: { item: RecommendationEvidenceItem }) {
  const reasons = distinctRecommendationReasons(item)
  if (!reasons.length) return null
  return <div className="tm-recommendation-evidence">
    <TasteMapRecommendationReasons reasons={reasons.map(reason => reason.text)} evidence={item.mode} className={`is-${item.mode.replace(/_/g, '-')}`} />
  </div>
}
