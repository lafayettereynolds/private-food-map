import type { PrivateDirectoryDashboard,PrivateDirectoryMutation } from '../contracts/privateDirectoryV1'
import { apiURL } from '../config/apiEnvironment'

export function browserPrivateDirectory() {
  const pending=new Map<string,string>()
  async function request<T>(url:string,body?:unknown):Promise<T> {
    const response=await fetch(apiURL(url),{credentials:'include',cache:'no-store',method:body?'POST':'GET',
      headers:body?{'Content-Type':'application/json'}:undefined,body:body?JSON.stringify(body):undefined})
    if(!response.ok) throw new Error('请登录并联网后重试。')
    return response.json()
  }
  return {
    searchUsers:async(query:string)=>{
      const page=await request<{items:Array<{profile:{userId:string;displayName:string}}>}>('/api/v1/social/users/search?q='+encodeURIComponent(query))
      return page.items.map(x=>({id:x.profile.userId,displayName:x.profile.displayName}))
    },
    dashboard:async()=>{
      pending.clear()
      const result=await request<PrivateDirectoryDashboard>('/api/v1/directory')
      return {...result,entries:result.entries.map(entry=>({...entry,avatarURL:entry.avatarURL?apiURL(entry.avatarURL):null}))}
    },
    mutate:async(input:PrivateDirectoryMutation)=>{
      const avatarData=input.action==='avatar'?(input.photoID?pending.get(input.photoID):null):undefined
      if(input.photoID&&!avatarData) throw new Error('请重新选择头像。')
      const result=await request('/api/v1/directory',{...input,avatarData})
      if(input.photoID)pending.delete(input.photoID)
      return result
    },
    respond:(id:string,action:'accept'|'reject'|'cancel'|'unlink')=>request(`/api/v1/social/companion-links/${encodeURIComponent(id)}`,{action}),
    pickAvatar:()=>new Promise<string|null>((resolve,reject)=>{
      const input=document.createElement('input');input.type='file';input.accept='image/*'
      input.oncancel=()=>resolve(null)
      input.onchange=async()=>{const file=input.files?.[0];if(!file){resolve(null);return}
        try{if(file.size>20_000_000)throw new Error('照片过大。')
          const bitmap=await createImageBitmap(file),canvas=document.createElement('canvas');canvas.width=256;canvas.height=256
          const ctx=canvas.getContext('2d');if(!ctx)throw new Error('无法处理照片。')
          const side=Math.min(bitmap.width,bitmap.height);ctx.drawImage(bitmap,(bitmap.width-side)/2,(bitmap.height-side)/2,side,side,0,0,256,256);bitmap.close()
          const data=canvas.toDataURL('image/jpeg',0.7);if(data.length>90_000)throw new Error('请换一张较小的照片。')
          const id=crypto.randomUUID();pending.clear();pending.set(id,data);resolve(id)
        }catch(e){reject(e)}
      };input.click()
    }),
  }
}
