import { referralAvailable } from '../config/referralAvailability'
import { useEffect, useRef, useState } from 'react'
import { Archive, Camera, Check, ChevronRight, CircleHelp, Cloud, Database, Download, HardDrive, Image, Info, MapPin, RefreshCw, ShieldCheck, Sparkles, Trash2, UserRound } from 'lucide-react'
import type { TasteMapNativeRouteRequest, TasteMapPermissionsStatusDTO, TasteMapPlatform, TasteMapPremiumProductDTO, TasteMapPremiumStatusDTO, TasteMapProfileDashboardViewModel, TasteMapSyncStatusDTO } from '../platform/TasteMapPlatform'
import { PremiumBurgerBadge } from './PremiumBurgerBadge'
import { TasteMapDirectoryPage } from './TasteMapDirectoryPage'
import { TasteMapReferralPage } from './TasteMapReferralPage'
import { HybridBackButton, HybridEntryRow, HybridPageHeader, HybridState } from './TasteMapHybridShared'

export function TasteMapPremiumPage({ platform, onOpenStore, onBack }: { platform: TasteMapPlatform; onOpenStore?: () => void; onBack?: () => void }) {
  const [status, setStatus] = useState<TasteMapPremiumStatusDTO | null>(null)
  const [products, setProducts] = useState<TasteMapPremiumProductDTO[]>([])
  const [message, setMessage] = useState<string | null>(null)
  const [busy, setBusy] = useState(false)
  const [loadingProducts, setLoadingProducts] = useState(true)
  const [reloadProducts, setReloadProducts] = useState(0)
  const [trialEligible, setTrialEligible] = useState(false)
  const [trialMessage, setTrialMessage] = useState<string | null>(null)
  const sessionRevision = useRef(0)
  const refreshSequence = useRef(0)
  useEffect(() => {
    let active = true
    let remove: (() => Promise<void>) | undefined
    const refresh = () => {
      const sequence = ++refreshSequence.current
      setLoadingProducts(true)
      void platform.premium.products().catch(() => []).then((nextProducts) => {
        if (!active || sequence !== refreshSequence.current) return
        setLoadingProducts(false)
        setProducts(nextProducts.filter((product) => product.period === 'monthly' || product.period === 'annual'))
      })
      void platform.premium.status().catch(() => ({ state: 'unavailable' as const, expiresAt: null })).then((nextStatus) => {
        if (active && sequence === refreshSequence.current) setStatus(nextStatus)
      })
      void platform.premium.trialEligibility().catch(() => ({ eligible: false, trialDays: 7 })).then((trial) => {
        if (active && sequence === refreshSequence.current) setTrialEligible(trial.eligible && trial.trialDays === 7)
      })
    }
    refresh()
    const expiryRefresh = window.setInterval(refresh, 60_000)
    platform.events.subscribe((event) => {
      if (event.name === 'premium.productsChanged') { setProducts([]); refresh(); return }
      if (event.name === 'auth.changed') { sessionRevision.current++; setTrialEligible(false); setTrialMessage(null); setBusy(false); setStatus(null); setProducts([]); setMessage(null); refreshSequence.current++; refresh(); return }
      if (event.name === 'data.changed'
        || (event.name === 'app.lifecycle' && (event.payload.state === 'foreground' || event.payload.state === 'resume'))) {
        refresh()
      }
    }).then((subscription) => { remove = () => subscription.remove() }).catch(() => undefined)
    return () => {
      active = false
      window.clearInterval(expiryRefresh)
      sessionRevision.current++
      void remove?.()
    }
  }, [platform, reloadProducts])
  const premiumAction = async (action: () => Promise<{ outcome: string; status: TasteMapPremiumStatusDTO }>, success: string) => {
    const revision = sessionRevision.current
    setBusy(true); setMessage(null)
    try {
      const result = await action()
      if (revision !== sessionRevision.current) return
      refreshSequence.current++
      setStatus(result.status)
      setMessage(result.outcome === 'cancelled' ? '已取消，没有产生购买。' : result.outcome === 'pending' ? '购买正在等待 App Store 确认。' : success)
    } catch { if (revision === sessionRevision.current) setMessage('订阅服务暂时无法完成这个操作，请稍后再试。') }
    finally { if (revision === sessionRevision.current) setBusy(false) }
  }
  const claimTrial = async () => {
    if (busy) return
    const revision = sessionRevision.current
    setBusy(true); setTrialMessage(null)
    try {
      const result = await platform.premium.claimTrial()
      if (revision !== sessionRevision.current) return
      refreshSequence.current++
      setStatus(result.status); setTrialEligible(false)
      setTrialMessage(`领取成功，7 天 Premium 有效期至 ${new Date(result.expiresAt).toLocaleString('zh-CN')}`)
    } catch (error) {
      if (revision !== sessionRevision.current) return
      setTrialMessage(error instanceof Error ? error.message : '领取暂时无法完成，请稍后重试。')
      const eligibility = await platform.premium.trialEligibility().catch(() => ({ eligible: false }))
      if (revision === sessionRevision.current) setTrialEligible(eligibility.eligible)
    } finally { if (revision === sessionRevision.current) setBusy(false) }
  }
  return <main className="tm-hybrid-page tm-hybrid-premium">
    <HybridBackButton onBack={onBack} />
    <HybridPageHeader description="解锁完整分析、饮食回顾和更多会员权益。" eyebrow="TASTE MAP PREMIUM" title="Premium" />
    {trialEligible || trialMessage ? <section className="tm-hybrid-premium-purchase" aria-label="新用户 Premium 体验">
      {trialEligible ? <><h3>免费体验 Premium 7 天</h3><p>无需订阅，不会自动续费</p><button disabled={busy} onClick={() => void claimTrial()} type="button">{busy ? '正在领取…' : '免费领取 7 天'}</button></> : null}
      {trialMessage ? <p role="status">{trialMessage}</p> : null}
    </section> : null}
    {!status ? <HybridState kind="loading" message="正在读取正式会员权益。" title="确认会员状态" /> : null}
    {status?.state === 'premium' ? <section className="tm-hybrid-premium-active"><PremiumBurgerBadge /><small>Taste Map Premium</small><h2>已开通</h2><p>{status.statusText ?? (status.expiresAt ? `有效期至 ${new Date(status.expiresAt).toLocaleDateString('zh-CN')}` : '当前权益有效')}</p><div><Benefit title="完整口味档案与高级分析" /><Benefit title="最佳饭搭子与谁最会种草" /><Benefit title="本月 / 年度回顾与五类分享海报" /><Benefit title="高级筛选与完整历史洞察" /></div>{status.canManageSubscription === true ? <button disabled={busy} onClick={onOpenStore ?? (() => void premiumAction(() => platform.premium.manage(), '已打开 App Store 订阅管理。'))} type="button">管理订阅<ChevronRight size={17} /></button> : null}<button disabled={busy} onClick={() => void premiumAction(() => platform.premium.restore(), '购买记录已恢复，会员状态已刷新。')} type="button">恢复购买</button>{message ? <p role="status">{message}</p> : null}</section> : <>
      <section className="tm-hybrid-premium-hero"><PremiumBurgerBadge /><div><small>让长期记录更有价值</small><h2>把每一次吃饭，变成真正懂你的口味档案。</h2><p>解锁完整分析、回顾与高质量分享海报。真实价格只在 App Store 商品加载成功后展示。</p></div></section>
      <section className="tm-hybrid-premium-purchase"><h3>开通 Premium</h3><p>{!products.length ? loadingProducts ? '正在获取 App Store 订阅方案…' : '暂时无法获取订阅方案，请检查网络后重试。' : '以下价格由 App Store 按你的地区和币种提供。'}</p>{!products.length && !loadingProducts ? <button disabled={busy} onClick={() => setReloadProducts((value) => value + 1)} type="button">重新加载订阅方案</button> : null}{products.map((product) => <button className="tm-hybrid-premium-plan" disabled={busy} key={product.id} onClick={() => void premiumAction(() => platform.premium.purchase(product.id), '购买已完成，会员状态已刷新。')} type="button"><Sparkles size={17} /><span>{product.period === 'annual' ? '开通年会员' : '开通月会员'}<small>{product.billingPeriodDescription}</small></span><strong>{product.displayPrice}</strong></button>)}<button disabled={busy} onClick={() => void premiumAction(() => platform.premium.restore(), '购买记录已恢复，会员状态已刷新。')} type="button">恢复购买</button>{message ? <p role="status">{message}</p> : null}</section>
      <section className="tm-hybrid-premium-benefits"><Benefit title="完整口味档案" detail="高频菜系、消费、城市、饭搭子、时间与代表餐厅。" /><Benefit title="关系与来源洞察" detail="最佳饭搭子、谁最会种草，以及真实结果证据。" /><Benefit title="月度 / 年度回顾" detail="从长期记录中看见口味变化和城市足迹。" /><Benefit title="五类分享海报" detail="统一 Analysis 视觉家族，9:16 高清导出。" /></section>
      <section className="tm-hybrid-premium-comparison"><h3>免费版与 Premium</h3><div><span>能力</span><span>免费版</span><span>Premium</span></div>{[['基础记录', '包含', '包含'], ['完整分析', '摘要', '完整'], ['回顾海报', '—', '包含'], ['高级筛选', '基础', '完整']].map((row) => <div key={row[0]}>{row.map((value) => <span key={value}>{value === '包含' ? <><Check size={13} />包含</> : value}</span>)}</div>)}</section>

    </>}
  </main>
}

function Benefit({ title, detail }: { title: string; detail?: string }) { return <article><span><Check size={16} /></span><div><strong>{title}</strong>{detail ? <small>{detail}</small> : null}</div></article> }

export function TasteMapSettingsPage({ platform, profile, onOpenPremium, onOpenNativeSettings, onBack, onOpenReferral, onOpenDirectory }: { platform: TasteMapPlatform; profile: TasteMapProfileDashboardViewModel; onOpenPremium?: () => void; onOpenNativeSettings?: (request: TasteMapNativeRouteRequest) => void | Promise<unknown>; onBack?: () => void; onOpenReferral?:()=>void; onOpenDirectory?:()=>void }) {
  const [showDirectory,setShowDirectory] = useState(false)
  const [showReferral,setShowReferral] = useState(false)
  const [sync, setSync] = useState<TasteMapSyncStatusDTO | null>(null)
  const [permissions, setPermissions] = useState<TasteMapPermissionsStatusDTO | null>(null)
  const [message, setMessage] = useState<string | null>(null)
  const [busy, setBusy] = useState(false)
  const actionPending = useRef(false)
  useEffect(() => {
    let active = true
    let refreshSequence = 0
    let remove: (() => Promise<void>) | undefined
    const refresh = () => {
      const sequence = ++refreshSequence
      void Promise.all([
        platform.sync.status().catch(() => ({ state: 'unavailable' as const, pendingMutationCount: 0, lastSuccessfulSyncAt: null, errorCode: null })),
        platform.permissions.status().catch(() => null),
      ]).then(([nextSync, nextPermissions]) => {
        if (!active || sequence !== refreshSequence) return
        setSync(nextSync)
        setPermissions(nextPermissions)
      })
    }
    refresh()
    platform.events.subscribe((event) => {
      if (event.name === 'data.changed'
        || (event.name === 'app.lifecycle' && (event.payload.state === 'foreground' || event.payload.state === 'resume'))) {
        refresh()
      }
    }).then((subscription) => {
      if (!active) void subscription.remove()
      else remove = () => subscription.remove()
    }).catch(() => undefined)
    return () => {
      active = false
      void remove?.()
    }
  }, [platform])
  const perform = async (action: () => Promise<unknown>, success?: string) => {
    if (actionPending.current) return
    actionPending.current = true
    setBusy(true); setMessage(null)
    try { await action(); if (success) setMessage(success) }
    catch { setMessage('当前系统能力暂时不可用，请稍后再试。') }
    finally { actionPending.current = false; setBusy(false) }
  }
  const openNativeSettingsDetail = (route: TasteMapNativeRouteRequest['route'], identifier?: string) => {
    void perform(() => onOpenNativeSettings
      ? Promise.resolve(onOpenNativeSettings({ route, identifier }))
      : platform.navigation.openNative({ route, identifier }))
  }
  const openPermission = (state: TasteMapPermissionsStatusDTO['location'] | undefined) => {
    if (permissions?.canOpenSystemSettings && canAdjustSettingsPermission(state)) {
      void perform(() => platform.permissions.openSystemSettings())
    } else openNativeSettingsDetail('permissions')
  }
  const runSync = () => {
    if (onOpenNativeSettings || (platform.kind === 'native' && (sync?.conflictCount ?? 0) > 0) || (platform.kind === 'native' && (sync?.pendingMutationCount ?? 0) > 0)) openNativeSettingsDetail('dataBackup', 'sync')
    else void perform(async () => {
      const next = await platform.sync.run()
      setSync(next)
      setMessage(next.state === 'error' ? '同步未完成，请重试。' : next.state === 'offline'
        ? '目前离线，记录仍保存在本机，联网后会继续同步。'
        : next.state === 'syncing' ? '正在同步…' : next.state === 'unavailable'
          ? '当前无法同步，请检查登录状态。' : '同步已完成。')
    })
  }
  if (showReferral && referralAvailable()) return <TasteMapReferralPage platform={platform} onBack={()=>setShowReferral(false)}/>
  if(showDirectory)return <TasteMapDirectoryPage platform={platform} onBack={()=>setShowDirectory(false)}/>
  return <main className="tm-hybrid-page tm-hybrid-settings">
    <HybridBackButton onBack={onBack} />
    <HybridPageHeader description="账户、数据、同步、权限与系统信息。高风险操作继续由正式 Native service 承载。" eyebrow="SETTINGS" title="设置" />
    <SettingsSection title="账户"><HybridEntryRow disabled={busy} detail={`${profile.user.nickname} · Taste Map ID、资料与登录安全`} icon={<UserRound size={18} />} onClick={() => openNativeSettingsDetail('accountSettings')} title="账户与安全" value={profile.user.membershipTier === 'member' ? 'Premium' : '免费版'} /></SettingsSection>
    <SettingsSection title="会员权益"><HybridEntryRow disabled={busy} detail={profile.user.membershipTier === 'member' ? '查看当前权益与订阅管理' : '查看会员能力'} icon={<Sparkles size={18} />} onClick={() => void perform(() => onOpenPremium ? Promise.resolve(onOpenPremium()) : platform.navigation.openHybrid({ surface: 'premium' }))} title="Premium" /></SettingsSection>
    {referralAvailable() ? <SettingsSection title="邀请奖励"><HybridEntryRow title="邀请好友" detail="每成功邀请 1 位新用户，获得 30 天 Premium" icon={<UserRound size={18}/>} onClick={onOpenReferral??(()=>setShowReferral(true))}/></SettingsSection> : null}
    <SettingsSection title="私人资料"><HybridEntryRow title="饭搭子与推荐来源" detail="关联好友、设置私人头像与来源用户" icon={<UserRound size={18}/>} onClick={onOpenDirectory??(()=>setShowDirectory(true))}/></SettingsSection>
    <SettingsSection title="数据与备份">
      <HybridEntryRow disabled={busy} detail="Backup v1 不包含照片原图" icon={<Download size={18} />} onClick={() => onOpenNativeSettings ? openNativeSettingsDetail('dataBackup', 'export') : void perform(() => platform.backup.openExport())} title="导出备份" />
      <HybridEntryRow disabled={busy} detail="先检查备份内容，再确认导入" icon={<Archive size={18} />} onClick={() => onOpenNativeSettings ? openNativeSettingsDetail('dataBackup', 'import') : void perform(() => platform.backup.openImport())} title="导入数据" />
      <HybridEntryRow detail={`${profile.restaurants.length} 家餐厅 · ${profile.visits.length} 次到访`} icon={<Database size={18} />} title="本地数据概览" />
      <HybridEntryRow disabled={busy} detail={platform.kind === 'native' ? '清除这台 iPhone，保留账号、个人资料和云端数据' : '仅 iPhone App 支持清除本机业务数据；浏览器图片缓存可在存储中管理'} icon={<Trash2 size={18} />} onClick={platform.kind === 'native' ? () => openNativeSettingsDetail('dataClear') : undefined} title="清除本机数据" />
    </SettingsSection>
    <SettingsSection title="同步"><HybridEntryRow disabled={busy || (!onOpenNativeSettings && (!sync || sync.state === 'syncing' || sync.state === 'unavailable'))} detail={syncDescription(sync)} icon={<Cloud size={18} />} onClick={runSync} title={platform.kind === 'native' && (sync?.conflictCount ?? 0) > 0 ? '处理同步冲突' : onOpenNativeSettings || (platform.kind === 'native' && (sync?.pendingMutationCount ?? 0) > 0) ? '查看同步详情' : sync?.state === 'syncing' ? '正在同步…' : sync?.state === 'error' ? '重试同步' : '立即同步'} value={sync?.state === 'idle' ? '正常' : sync?.state === 'syncing' ? '同步中' : sync?.state === 'error' ? '错误' : undefined} />{sync?.pendingMutationCount ? <HybridEntryRow detail="等待上传的本地更改" icon={<RefreshCw size={18} />} title="待同步记录" value={`${sync.pendingMutationCount}`} /> : null}{sync?.pendingPhotoCount ? <HybridEntryRow detail="联网后继续上传" icon={<RefreshCw size={18} />} title="待上传照片" value={`${sync.pendingPhotoCount}`} /> : null}</SettingsSection>
    <SettingsSection title="隐私与权限"><HybridEntryRow disabled={busy} detail="个人主页、味觉足迹与到访照片同步；食单单独设置" icon={<ShieldCheck size={18} />} onClick={() => openNativeSettingsDetail('privacySettings')} title="隐私" /><HybridEntryRow disabled={busy} detail={permissionDescription(permissions?.location)} icon={<MapPin size={18} />} onClick={() => openPermission(permissions?.location)} title="位置权限" value={permissionLabel(permissions?.location)} /><HybridEntryRow disabled={busy} detail={cameraPermissionDescription(permissions?.camera)} icon={<Camera size={18} />} onClick={() => openPermission(permissions?.camera)} title="相机权限" value={permissionLabel(permissions?.camera)} /><HybridEntryRow disabled={busy} detail={permissionDescription(permissions?.photoAddOnly, true)} icon={<Image size={18} />} onClick={() => openPermission(permissions?.photoAddOnly)} title="照片权限" value={permissionLabel(permissions?.photoAddOnly)} /></SettingsSection>
    <SettingsSection title="存储"><HybridEntryRow disabled={busy} detail="查看本地照片与临时文件占用" icon={<HardDrive size={18} />} onClick={() => openNativeSettingsDetail('storage')} title="存储" /></SettingsSection>
    <SettingsSection title="帮助与关于"><HybridEntryRow disabled={busy} detail="备份、同步、添加餐厅与定位说明" icon={<CircleHelp size={18} />} onClick={() => openNativeSettingsDetail('helpSettings')} title="使用帮助" /><HybridEntryRow disabled={busy} detail="版本与法律信息" icon={<Info size={18} />} onClick={() => openNativeSettingsDetail('aboutSettings')} title="关于 Taste Map" /></SettingsSection>
    {message ? <p className="tm-hybrid-settings__message" role="status">{message}</p> : null}
  </main>
}

export function canAdjustSettingsPermission(value?: TasteMapPermissionsStatusDTO['location']) {
  return value != null && value !== 'notDetermined'
}

function permissionLabel(value?: TasteMapPermissionsStatusDTO['location']) {
  return value === 'allowed' ? '已允许' : value === 'limited' ? '有限' : value === 'denied' ? '已拒绝' : value === 'restricted' ? '受限制' : value === 'notDetermined' ? '未请求' : '查看'
}

function permissionDescription(value?: TasteMapPermissionsStatusDTO['location'], photo = false) {
  if (!value) return photo ? '选择照片时使用系统 PhotosPicker' : '只在使用附近功能时请求'
  if (value === 'allowed') return photo ? '系统允许保存生成的分析海报' : '附近功能可使用系统实际位置'
  if (value === 'limited') return '系统当前只提供有限访问，可前往设置调整'
  if (value === 'denied' || value === 'restricted') return '功能仍保持诚实降级；可前往系统设置调整'
  return photo ? '主动保存海报时才会请求权限' : '使用附近功能时才会请求权限'
}

function cameraPermissionDescription(value?: TasteMapPermissionsStatusDTO['camera']) {
  if (!value || value === 'notDetermined') return '只在主动选择“拍照”时请求相机权限'
  if (value === 'allowed') return '可以拍摄本次到访与菜品照片'
  return '相机保持不可用；可前往系统设置调整'
}

function SettingsSection({ title, children }: { title: string; children: React.ReactNode }) { return <section className="tm-hybrid-settings-section"><h2>{title}</h2><div>{children}</div></section> }

function syncDescription(value: TasteMapSyncStatusDTO | null) {
  if (!value) return '正在读取同步状态'
  if (value.state === 'unavailable') return '在浏览器或未配置环境中不可用'
  if (value.state === 'error') return value.errorCode ? `最近错误：${value.errorCode}` : '最近同步失败'
  if (value.lastSuccessfulSyncAt) return `上次成功：${new Date(value.lastSuccessfulSyncAt).toLocaleString('zh-CN')}`
  return value.state === 'syncing' ? '正在同步' : '尚无成功同步记录'
}
