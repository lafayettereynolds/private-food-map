import { useCallback, useEffect, useMemo, useState } from 'react'
import { BarChart3, Check, ChevronDown, ChevronRight, Images, LoaderCircle, RefreshCw, Sparkles, UsersRound, WandSparkles } from 'lucide-react'
import type { MembershipTier } from '../types/domain'
import type { MembershipSelfResponse } from '../types/membership'
import { MEMBERSHIP_CHANGED_EVENT, MembershipService } from '../services/membershipService'
import { membershipStatusPresentation } from '../services/membershipPresentation'
import { annualSavingsPercent, MembershipStore, type MembershipStorePlan } from '../services/membershipStore'
import { PREMIUM_PAYWALL_OPEN_EVENT, PREMIUM_SOURCE_COPY, trackPremiumEvent, type PremiumSourceFeatureKey } from '../services/premiumPaywall'
import { ModalShell } from './ModalShell'

const BENEFITS = [
  ['完整口味档案', '预算、场景、评分风格与口味变化', BarChart3],
  ['深度个性化推荐', '更多推荐依据、解释与跨城市匹配', WandSparkles],
  ['同味能力', '同味之选、同味评分与相似用户洞察', UsersRound],
  ['最佳饭搭子与谁最会种草', '验证谁和你最合拍、谁的推荐最准', Sparkles],
  ['长期回顾', '完整月度回顾与年度食味年鉴', RefreshCw],
  ['高级筛选与更多照片', '高级推荐筛选，每次到访最多 20 张照片', Images],
] as const

const COMPARISON = [
  ['到访、去过与想去', '包含', '包含'],
  ['好友评分、重复到访与跨城市推荐', '包含', '包含'],
  ['那年今日', '包含', '包含'],
  ['每次 Visit 图片', '3 张', '20 张'],
  ['为你推荐', '基础推荐', '深度推荐'],
  ['完整口味档案与同味能力', '—', '包含'],
  ['饭搭子、推荐来源与消费分析', '—', '包含'],
  ['月度、年度回顾', '—', '包含'],
  ['高级地图筛选、饭搭子选餐、自定义头像', '—', '包含'],
] as const

export function PremiumPaywallHost({ membershipTier }: { membershipTier: MembershipTier }) {
  const [sourceFeatureKey, setSourceFeatureKey] = useState<PremiumSourceFeatureKey | null>(null)
  useEffect(() => {
    function open(event: Event) {
      const source = (event as CustomEvent<{ sourceFeatureKey?: PremiumSourceFeatureKey }>).detail?.sourceFeatureKey ?? 'profile_entry'
      setSourceFeatureKey(source)
      trackPremiumEvent({ event: 'paywall_viewed', sourceFeatureKey: source })
    }
    window.addEventListener(PREMIUM_PAYWALL_OPEN_EVENT, open)
    return () => window.removeEventListener(PREMIUM_PAYWALL_OPEN_EVENT, open)
  }, [])
  return sourceFeatureKey ? <PremiumPaywall membershipTier={membershipTier} onClose={() => setSourceFeatureKey(null)} sourceFeatureKey={sourceFeatureKey} /> : null
}

function PremiumPaywall({ membershipTier, sourceFeatureKey, onClose }: { membershipTier: MembershipTier; sourceFeatureKey: PremiumSourceFeatureKey; onClose: () => void }) {
  const [plans, setPlans] = useState<MembershipStorePlan[]>([])
  const [selectedPlanId, setSelectedPlanId] = useState('')
  const [loadingPlans, setLoadingPlans] = useState(false)
  const [plansLoaded, setPlansLoaded] = useState(false)
  const [membershipLoading, setMembershipLoading] = useState(true)
  const [planError, setPlanError] = useState('')
  const [busy, setBusy] = useState<'purchase' | 'restore' | 'manage' | null>(null)
  const [message, setMessage] = useState('')
  const [membership, setMembership] = useState<MembershipSelfResponse | null>(null)
  const [showBenefits, setShowBenefits] = useState(false)

  const loadMembership = useCallback(async () => {
    setMembershipLoading(true)
    try { setMembership(await MembershipService.getEntitlement()) }
    catch { setMembership(null) }
    finally { setMembershipLoading(false) }
  }, [])

  const loadPlans = useCallback(async () => {
    setLoadingPlans(true)
    setPlanError('')
    try {
      const nextPlans = await MembershipStore.loadPlans()
      setPlans(nextPlans)
      setSelectedPlanId(nextPlans.find((plan) => plan.period === 'yearly')?.id ?? nextPlans[0]?.id ?? '')
    } catch (error) {
      setPlanError(error instanceof Error ? error.message : '暂时无法获取订阅信息')
    } finally {
      setPlansLoaded(true)
      setLoadingPlans(false)
    }
  }, [])

  useEffect(() => {
    void loadMembership()
    window.addEventListener(MEMBERSHIP_CHANGED_EVENT, loadMembership)
    return () => window.removeEventListener(MEMBERSHIP_CHANGED_EVENT, loadMembership)
  }, [loadMembership])

  const status = membershipStatusPresentation(membership?.entitlement ?? null, membershipTier)
  useEffect(() => {
    if (!membershipLoading && !status.isPremium && !plansLoaded && !loadingPlans) void loadPlans()
  }, [loadPlans, loadingPlans, membershipLoading, plansLoaded, status.isPremium])

  const monthly = plans.find((plan) => plan.period === 'monthly')
  const yearly = plans.find((plan) => plan.period === 'yearly')
  const savings = useMemo(() => annualSavingsPercent(monthly, yearly), [monthly, yearly])

  async function purchase() {
    if (!selectedPlanId) return
    setBusy('purchase'); setMessage(''); trackPremiumEvent({ event: 'purchase_started', sourceFeatureKey, planId: selectedPlanId })
    try {
      const result = await MembershipStore.purchase(selectedPlanId)
      if (!result.success) throw new Error('购买未完成。')
      setMembership(await MembershipService.refresh())
      setMessage('Premium 已开通，会员功能已立即刷新。')
      trackPremiumEvent({ event: 'purchase_succeeded', sourceFeatureKey, planId: selectedPlanId })
    } catch (error) {
      const nextMessage = error instanceof Error ? error.message : '购买失败，请重试。'
      setMessage(nextMessage); trackPremiumEvent({ event: 'purchase_failed', sourceFeatureKey, planId: selectedPlanId, message: nextMessage })
    } finally { setBusy(null) }
  }

  async function restore() {
    setBusy('restore'); setMessage(''); trackPremiumEvent({ event: 'restore_started', sourceFeatureKey })
    try {
      const result = await MembershipStore.restorePurchases()
      if (!result.success) throw new Error('没有找到可恢复的购买。')
      setMembership(await MembershipService.refresh())
      setMessage('购买已恢复，会员状态已刷新。')
      trackPremiumEvent({ event: 'restore_succeeded', sourceFeatureKey })
    } catch (error) {
      const nextMessage = error instanceof Error ? error.message : '恢复购买失败，请重试。'
      setMessage(nextMessage); trackPremiumEvent({ event: 'restore_failed', sourceFeatureKey, message: nextMessage })
    } finally { setBusy(null) }
  }

  async function manage() {
    setBusy('manage'); setMessage(''); trackPremiumEvent({ event: 'manage_started', sourceFeatureKey })
    try {
      await MembershipStore.manageSubscriptions()
      trackPremiumEvent({ event: 'manage_succeeded', sourceFeatureKey })
    } catch (error) {
      const nextMessage = error instanceof Error ? error.message : '暂时无法打开订阅管理。'
      setMessage(nextMessage); trackPremiumEvent({ event: 'manage_failed', sourceFeatureKey, message: nextMessage })
    } finally { setBusy(null) }
  }

  if (membershipLoading && !membership) return <ModalShell onClose={onClose} size="large" title="Taste Map Premium"><p className="premium-plan-state"><LoaderCircle className="spin" size={17} />正在确认会员状态…</p></ModalShell>

  if (status.isPremium) return <ModalShell description="查看当前会员方案、有效期和已解锁权益。" onClose={onClose} size="large" title="Taste Map Premium">
    <div className="premium-status-page">
      <section className="premium-status-page__summary">
        <span><Check size={26} /></span>
        <div><small>Taste Map Premium</small><h2>已开通</h2><p>{status.planLabel}</p></div>
      </section>
      <section className="premium-status-page__details">
        <div><small>当前方案</small><strong>{status.planLabel}</strong></div>
        <div><small>开通方式</small><strong>{status.sourceLabel}</strong></div>
        {status.dateLabel && status.dateValue ? <div><small>{status.dateLabel}</small><strong>{status.dateValue}</strong></div> : null}
      </section>
      <button className="premium-status-page__benefit-toggle" onClick={() => setShowBenefits((value) => !value)} type="button"><span>查看 Premium 权益</span><ChevronDown className={showBenefits ? 'is-open' : ''} size={18} /></button>
      {showBenefits ? <section className="premium-paywall__benefits">{BENEFITS.map(([title, description, Icon]) => <article key={title}><span><Icon size={19} /></span><div><strong>{title}</strong><small>{description}</small></div></article>)}</section> : null}
      <section className="premium-status-page__actions">
        {status.canManageAppStoreSubscription ? <button className="premium-status-page__manage" disabled={busy !== null} onClick={() => void manage()} type="button">{busy === 'manage' ? '正在打开…' : '管理 App Store 订阅'}<ChevronRight size={17} /></button> : null}
        <button disabled={busy !== null} onClick={() => void restore()} type="button">{busy === 'restore' ? '正在恢复…' : '恢复购买'}</button>
      </section>
      {message ? <p className="premium-paywall__message">{message}</p> : null}
      <p className="premium-paywall__data-note">会员到期后不会删除任何餐厅、到访或已上传照片；仅暂停新增 Premium 内容和深度分析。</p>
    </div>
  </ModalShell>

  return <ModalShell description={PREMIUM_SOURCE_COPY[sourceFeatureKey]} onClose={onClose} size="large" title="Taste Map Premium">
    <div className="premium-paywall">
      <section className="premium-paywall__hero"><Sparkles size={25} /><div><h2>把长期记录，变成更懂你的分析。</h2><p>解锁完整口味档案、深度推荐、最佳饭搭子与谁最会种草，让每一次真实记录都变得更有价值。</p></div></section>
      <section className="premium-paywall__benefits">{BENEFITS.map(([title, description, Icon]) => <article key={title}><span><Icon size={19} /></span><div><strong>{title}</strong><small>{description}</small></div></article>)}</section>
      <section className="premium-paywall__comparison"><h3>免费版与 Premium</h3><div className="premium-comparison-row is-head"><span>功能</span><span>免费版</span><span>Premium</span></div>{COMPARISON.map((row) => <div className="premium-comparison-row" key={row[0]}>{row.map((cell) => <span key={cell}>{cell === '包含' ? <><Check size={13} />包含</> : cell}</span>)}</div>)}</section>
      <section className="premium-paywall__plans">
        <header><div><h3>选择方案</h3><p>价格由 App Store 按你的地区和币种提供。</p></div></header>
        {loadingPlans ? <p className="premium-plan-state"><LoaderCircle className="spin" size={17} />正在获取价格…</p> : planError ? <p className="premium-plan-state is-error">{planError}<button onClick={() => void loadPlans()} type="button">重试</button></p> : <div className="premium-plan-grid">{plans.map((plan) => <button className={selectedPlanId === plan.id ? 'is-selected' : ''} key={plan.id} onClick={() => { setSelectedPlanId(plan.id); trackPremiumEvent({ event: 'plan_selected', sourceFeatureKey, planId: plan.id }) }} type="button"><span>{plan.period === 'yearly' ? '年度方案' : '月度方案'}{plan.period === 'yearly' ? <b>推荐</b> : null}</span><strong>{plan.displayPrice}</strong><small>{plan.description || (plan.period === 'yearly' ? '按年订阅' : '按月订阅')}</small>{plan.period === 'yearly' && savings ? <em>比月付节省 {savings}%</em> : null}</button>)}</div>}
        {plans.length ? <button className="premium-purchase-button" disabled={busy !== null || !selectedPlanId} onClick={() => void purchase()} type="button">{busy === 'purchase' ? '购买中…' : '开通 Premium'}<ChevronRight size={17} /></button> : null}
        {message ? <p className="premium-paywall__message">{message}</p> : null}
        <div className="premium-paywall__links"><button disabled={busy !== null} onClick={() => void restore()} type="button">{busy === 'restore' ? '正在恢复…' : '恢复购买'}</button><a href="/terms" target="_blank">用户协议</a><a href="/privacy" target="_blank">隐私政策</a></div>
        <p className="premium-subscription-note">订阅由 App Store 管理并按所选周期自动续订；可随时在系统订阅设置中取消。购买或恢复后，Taste Map 会重新验证账号权益。</p>
      </section>
    </div>
  </ModalShell>
}
