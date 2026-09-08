import { useEffect, useState } from 'react'
import type { TasteMapPlatform } from '../platform/TasteMapPlatform'
import { referralStatusLabel, type ReferralDashboardV1 } from '../contracts/referralsV1'
import { HybridBackButton, HybridEntryRow, HybridPageHeader, HybridState } from './TasteMapHybridShared'
import { Gift, Share2, Users } from 'lucide-react'
import './tasteMapReferralPage.css'

export function TasteMapReferralPage({platform,onBack}:{platform:TasteMapPlatform;onBack:()=>void}) {
  const [data,setData]=useState<ReferralDashboardV1|null>(null)
  const [error,setError]=useState<string|null>(null)
  const [revision,setRevision]=useState(0)
  const [sharing,setSharing]=useState(false)
  const [registering,setRegistering]=useState(false)
  const [code,setCode]=useState('')
  const [registrationMessage,setRegistrationMessage]=useState<string|null>(null)
  useEffect(()=>{
    let active=true, sequence=0
    const refresh=()=>{const request=++sequence;setData(null);setError(null)
      if(!platform.referrals){setError('当前 App 版本不支持邀请，请更新后重试。');return}
      void platform.referrals.dashboard().then(value=>{if(active&&request===sequence)setData(value)})
        .catch(()=>{if(active&&request===sequence)setError('请先登录并联网，再查看邀请奖励。')})}
    refresh()
    const subscription=platform.events.subscribe(event=>{if(event.name==='auth.changed'||event.name==='data.changed'||event.name==='app.lifecycle')refresh()})
    return()=>{active=false;sequence++;void subscription.then(s=>s.remove())}
  },[platform,revision])
  const share=async()=>{if(!data||sharing)return;setSharing(true);try{await platform.share.open({title:'一起用 Taste Map 记录美食',text:'新用户通过邀请注册并完成首次有效到访，可获得 14 天 Premium。',url:data.inviteLink})}catch{setError('未能打开系统分享，请重试。')}finally{setSharing(false)}}
  const prepareRegistration=async()=>{
    if(registering||!code.trim()||!platform.referrals?.prepareRegistration)return
    setRegistering(true);setRegistrationMessage(null)
    try{await platform.referrals.prepareRegistration(code.trim());setRegistrationMessage('邀请码已保存。请返回“我的”，使用 Apple 登录创建新账号。已有账号不参与新用户奖励。')}
    catch{setRegistrationMessage('未能使用邀请码。请检查邀请码；此功能仅限未登录的新用户。')}
    finally{setRegistering(false)}
  }
  return <main className="tm-hybrid-page tm-hybrid-settings tm-referral-page">
    <HybridBackButton onBack={onBack}/><HybridPageHeader eyebrow="REFERRAL" title="邀请好友" description="邀请新朋友一起记录美食，每位用户终身最多成功邀请 5 人。"/>
    {!data&&!error?<HybridState kind="loading" title="读取邀请记录" message="正在确认奖励与待生效余额。"/>:null}
    {data?<>
      <section className="tm-hybrid-settings-section"><h2>我的邀请</h2><div>
        <HybridEntryRow icon={<Users size={18}/>} title={`已成功邀请 ${data.qualifiedCount}/5`} detail="撤销记录不会恢复终身邀请名额"/>
        <HybridEntryRow icon={<Gift size={18}/>} title={`已获得 ${data.earnedDays} 天 Premium`} detail={`待生效奖励 ${data.pendingDays} 天`}/>
        <HybridEntryRow icon={<Gift size={18}/>} title="邀请码" detail={data.code}/><HybridEntryRow icon={<Gift size={18}/>} title="邀请链接" detail={data.inviteLink}/>
        <HybridEntryRow icon={<Share2 size={18}/>} title="分享邀请链接" detail="通过系统分享发送给好友" disabled={sharing} onClick={()=>void share()}/>
      </div></section>
      <section className="tm-hybrid-settings-section"><h2>邀请记录</h2><div>{data.records.length?data.records.map((record,index)=><HybridEntryRow icon={<Users size={18}/>} key={record.id} title={`好友 ${data.records.length-index} · ${referralStatusLabel[record.status]}`} detail={`注册 ${new Date(record.boundAt).toLocaleDateString('zh-CN')}${record.qualifiedAt?` · 达标 ${new Date(record.qualifiedAt).toLocaleDateString('zh-CN')}`:''}`}/>):<HybridEntryRow icon={<Gift size={18}/>} title="还没有邀请记录" detail="好友注册并完成第一条有效到访后，双方自动获得奖励。"/>}</div></section>
    </>:null}
    <section className="tm-hybrid-settings-section"><h2>奖励规则</h2><div><HybridEntryRow icon={<Gift size={18}/>} title="你获得 30 天，好友获得 14 天" detail="仅限通过邀请码或链接注册的新账号，完成首次有效到访后发放。每位新用户只能绑定一位邀请人。"/><HybridEntryRow icon={<Gift size={18}/>} title="App Store 订阅期间保留奖励" detail="不修改 Apple 订阅；奖励在订阅权益结束后生效。普通赠送或奖励会员顺延有效期；永久赠送会员只累计邀请记录，不增加期限。"/></div></section>
    {!data&&platform.referrals?.prepareRegistration?<section className="tm-hybrid-settings-section"><h2>我有好友的邀请码</h2><div>
      <form className="tm-referral-code-form" onSubmit={event=>{event.preventDefault();void prepareRegistration()}}>
        <label htmlFor="referral-registration-code">邀请码</label>
        <input id="referral-registration-code" aria-label="24 位邀请码" aria-describedby="referral-code-help" placeholder="粘贴好友的 24 位邀请码" autoCapitalize="none" autoCorrect="off" spellCheck={false} disabled={registering} value={code} onChange={e=>{setCode(e.target.value);setRegistrationMessage(null)}}/>
        <p id="referral-code-help">仅限新用户。先使用邀请码，再通过 Apple 登录注册。</p>
        <button className="primary-button" type="submit" disabled={registering||!code.trim()}>{registering?'正在保存邀请码…':'使用此邀请码'}</button>
        {registrationMessage?<p className="tm-referral-feedback" role="status">{registrationMessage}</p>:null}
      </form></div></section>:null}
    <section className="tm-referral-refresh" aria-label="邀请记录状态">{error?<p role="status">{error}</p>:null}<button className="tm-hybrid-page-action" onClick={()=>setRevision(v=>v+1)} type="button">刷新邀请记录</button></section>
  </main>
}
