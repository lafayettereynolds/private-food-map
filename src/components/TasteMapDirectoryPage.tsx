import { useEffect,useRef,useState } from 'react'
import type { TasteMapPlatform } from '../platform/TasteMapPlatform'
import type { PrivateDirectoryDashboard,PrivateDirectoryEntry } from '../contracts/privateDirectoryV1'
import { HybridBackButton,HybridPageHeader } from './TasteMapHybridShared'

export function TasteMapDirectoryPage({platform,onBack}:{platform:TasteMapPlatform;onBack:()=>void}) {
  const [data,setData]=useState<PrivateDirectoryDashboard|null>(null),[error,setError]=useState(''),[busy,setBusy]=useState(false)
  const [revision,setRevision]=useState(0),[selected,setSelected]=useState<PrivateDirectoryEntry|null>(null),[query,setQuery]=useState('')
  const [searchUsers,setSearchUsers]=useState<Array<{id:string;displayName:string}>>([])
  const epoch=useRef(0),lock=useRef(false),searchEpoch=useRef(0)
  useEffect(()=>{const generation=++epoch.current;setData(null);setSelected(null)
    Promise.all([platform.auth.sessionStatus(),platform.directory?.dashboard()]).then(([session,result])=>{
      if(epoch.current!==generation)return
      if(session.state!=='authenticated'||!result||result.userID!==session.userID)throw new Error('auth')
      setData(result);setError('')
    }).catch(()=>{if(epoch.current===generation)setError('资料暂时无法加载，请确认已登录并完成同步后重试。')})
    return()=>{epoch.current++}
  },[platform,revision])
  useEffect(()=>{let remove:(()=>Promise<void>)|undefined,active=true
    platform.events.subscribe(event=>{if(event.name==='auth.changed'){epoch.current++;setData(null);setSelected(null);setRevision(x=>x+1)}})
      .then(s=>{if(!active)void s.remove();else remove=()=>s.remove()});return()=>{active=false;void remove?.()}
  },[platform])
  const perform=async(action:()=>Promise<unknown>)=>{
    if(lock.current)return;lock.current=true;setBusy(true);setError('');const generation=epoch.current
    try{await action();if(generation===epoch.current)setRevision(x=>x+1)}
    catch{if(generation===epoch.current)setError('未能保存。请检查同步、网络与双方关系后重试。')}
    finally{lock.current=false;setBusy(false)}
  }
  return <main className="tm-hybrid-page tm-hybrid-settings tm-directory">
    <HybridBackButton onBack={onBack}/><HybridPageHeader title="饭搭子与推荐来源" description="管理你自己的称呼、头像和账号关联"/>
    <p>头像和推荐来源归因仅自己可见。饭搭子关联需对方确认；关联不会自动复制或公开双方的记录。</p>
    {error?<p role="alert">{error}<button disabled={busy} onClick={()=>setRevision(x=>x+1)}>重试</button></p>:!data?<p role="status">正在加载…</p>:null}
    {data&&(['companion','source'] as const).map(kind=><section className="tm-hybrid-settings-section" key={kind}>
      <h2>{kind==='companion'?'饭搭子 · 关联好友与头像':'推荐来源 · 头像与用户关联'}</h2>
      <div>{data.entries.filter(e=>e.kind===kind).map(entry=><article className="tm-directory-row" key={entry.id}>
        {entry.avatarURL?<img src={entry.avatarURL} alt={`${entry.displayName}的私人头像`}/>:<span className="tm-directory-avatar" aria-hidden>{Array.from(entry.displayName)[0]}</span>}
        <div><strong>{entry.displayName}</strong><p>{entry.linkedUserID?'已关联 Taste Map 用户':'未关联账号'}</p>
          <div className="tm-directory-actions"><button disabled={busy} onClick={()=>void perform(async()=>{const generation=epoch.current;const photoID=await platform.directory!.pickAvatar();if(photoID&&generation===epoch.current)await platform.directory!.mutate({kind,id:entry.id,action:'avatar',photoID})})}>自定义头像</button>
          {entry.avatarURL?<button disabled={busy} onClick={()=>void perform(()=>platform.directory!.mutate({kind,id:entry.id,action:'avatar',photoID:null}))}>移除头像</button>:null}
          {!entry.linkedUserID?<button disabled={busy} onClick={()=>{setSelected(entry);setQuery('');setSearchUsers([])}}>{kind==='companion'?'关联好友':'关联用户'}</button>:kind==='source'?<button disabled={busy} onClick={()=>void perform(()=>platform.directory!.mutate({kind,id:entry.id,action:'linkSource',targetUserID:null}))}>解除用户关联</button>:null}</div>
        </div></article>)}
        {!data.entries.some(e=>e.kind===kind)?<p>还没有{kind==='companion'?'饭搭子':'推荐来源'}。在到访记录中添加后同步，即可在这里管理。</p>:null}
      </div>
    </section>)}
    {selected&&data?<section className="tm-hybrid-settings-section"><h2>将「{selected.displayName}」关联到</h2>
      <input aria-label="搜索用户" placeholder={selected.kind==='companion'?'搜索互相关注的好友':'搜索 Taste Map 用户'} value={query} onChange={e=>{searchEpoch.current++;setSearchUsers([]);setQuery(e.target.value)}}/>
      <p>饭搭子从互关好友中选择并发送确认请求；推荐来源也可搜索其他可发现用户，仅修改你的私人归因。</p>
      {selected.kind==='source'?<button disabled={busy||query.trim().length<2} onClick={()=>{const generation=epoch.current,search=++searchEpoch.current;void platform.directory!.searchUsers(query).then(users=>{if(generation===epoch.current&&search===searchEpoch.current)setSearchUsers(users)}).catch(()=>{if(generation===epoch.current&&search===searchEpoch.current)setError('搜索暂时不可用，请重试。')})}}>搜索 Taste Map 用户</button>:null}
      {Array.from(new Map([...data.users.filter(u=>u.displayName.includes(query)),...(selected.kind==='source'?searchUsers:[])].map(u=>[u.id,u])).values()).map(u=><button className="tm-directory-user" disabled={busy} key={u.id} onClick={()=>void perform(()=>platform.directory!.mutate({kind:selected.kind,id:selected.id,action:selected.kind==='companion'?'linkCompanion':'linkSource',targetUserID:u.id}))}>{u.displayName}<span>选择</span></button>)}
      {!data.users.length&&!searchUsers.length?<p>暂无互相关注的好友，请先在好友与关注中建立关系；推荐来源也可搜索其他用户。</p>:null}
      <button disabled={busy} onClick={()=>{searchEpoch.current++;setSelected(null)}}>取消</button>
    </section>:null}
    {data?.links.length?<section className="tm-hybrid-settings-section"><h2>饭搭子关联请求</h2>{Array.from(new Map(data.links.map(l=>[l.id,l])).values()).map(link=><article key={link.id}>
      <p>{link.companionDisplayName} · {link.otherUser.displayName} · {link.status==='accepted'?'已关联':'等待确认'}</p>
      {(link.status==='accepted'?['unlink']:link.targetUserId===data.userID?['accept','reject']:['cancel']).map(action=><button disabled={busy} key={action} onClick={()=>void perform(()=>platform.directory!.respond(link.id,action as 'accept'|'reject'|'cancel'|'unlink'))}>{({accept:'接受',reject:'拒绝',cancel:'取消请求',unlink:'解除关联'} as Record<string,string>)[action]}</button>)}
    </article>)}</section>:null}
  </main>
}
