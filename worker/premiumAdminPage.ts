/** Internal-only web entry, deliberately excluded from the App's React/StoreKit bundle. */
export function premiumAdminPage(): Response {
  const nonce = crypto.randomUUID()
  return new Response(`<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Taste Map 内部会员管理</title>
<style nonce="${nonce}">body{font:16px system-ui;max-width:900px;margin:32px auto;padding:16px;color:#253449;background:#f7f9fc}input,button{font:inherit;padding:12px;margin:4px;min-height:44px;box-sizing:border-box}section,article{background:white;padding:16px;margin:16px 0;border:1px solid #dce2eb;border-radius:12px}small{display:block;overflow-wrap:anywhere}button{cursor:pointer}button:disabled{opacity:.5}label{display:block}#message{white-space:pre-wrap}h1{font-size:24px}</style>
<h1>Taste Map 内部会员管理</h1><form id="login"><label>管理员当前会话 Access Token<input id="token" type="password" autocomplete="off" required></label><button>验证管理员身份</button></form>
<p id="message" role="status"></p><section id="admin" hidden><button id="logout">退出管理</button><form id="search"><label>搜索 Taste Map userID、昵称、邮箱或城市<input id="query"></label><button>搜索</button></form><div id="users"></div><div id="detail"></div></section>
<script nonce="${nonce}">
const $=id=>document.getElementById(id);let session='',generation=0,busy=false;
function clear(){generation++;session='';$('token').value='';$('admin').hidden=true;$('login').hidden=false;$('users').replaceChildren();$('detail').replaceChildren()}
async function api(body,q=''){const response=await fetch('/api/v1/admin/memberships?q='+encodeURIComponent(q),{method:body?'POST':'GET',headers:{'Authorization':'Bearer '+session,'Content-Type':'application/json'},body:body?JSON.stringify(body):undefined,cache:'no-store'});const data=await response.json();if(!response.ok){if(response.status===401||response.status===403)clear();throw Error(data.error||'操作失败')}return data}
function element(tag,text){const e=document.createElement(tag);e.textContent=text;return e}
function button(title,action){const b=element('button',title);b.type='button';b.onclick=()=>run(action);return b}
async function run(action){if(busy)return;busy=true;document.querySelectorAll('button').forEach(b=>b.disabled=true);$('message').textContent='';try{await action()}catch(e){$('message').textContent=e.message}finally{busy=false;document.querySelectorAll('button').forEach(b=>b.disabled=false)}}
async function search(){const epoch=generation;const data=await api(null,$('query').value);if(epoch!==generation)return;$('detail').replaceChildren();$('users').replaceChildren(...data.users.map(u=>button(u.nickname+' · '+u.id,()=>show(u))))}
function show(user){const panel=$('detail');panel.replaceChildren(element('h2',user.nickname),element('small','Taste Map userID: '+user.id),element('p','当前来源: '+(user.entitlement.source||'免费')));const note=element('input','');note.placeholder='管理员备注（最多 160 字）';note.maxLength=160;note.setAttribute('aria-label','管理员备注');panel.append(note);
async function change(body){const epoch=generation;await api({...body,...(note.value || body.action==='note' ? {note:note.value} : {})});if(epoch!==generation)return;const refreshed=await api(null,user.id);if(epoch!==generation)return;const current=refreshed.users.find(u=>u.id===user.id);if(current)show(current);else panel.replaceChildren();$('message').textContent='操作成功，审计日志已保存。'}
panel.append(button('赠送 Premium 1 年',()=>change({action:'grant',userId:user.id,source:'gift_annual'})),button('赠送 Premium 永久',()=>change({action:'grant',userId:user.id,source:'gift_lifetime'})));
for(const item of user.entitlement.entitlements){const row=element('article','');row.append(element('strong',item.source+' · '+item.status),element('small','开始: '+item.startedAt),element('small','到期: '+(item.expiresAt||'永久')),element('small','发放人: '+(item.grantedBy||'—')),element('small','备注: '+item.note),element('small','撤销: '+(item.revokedAt||'—')));if(['gift_annual','gift_lifetime'].includes(item.source)&&item.status==='active'){if(item.source==='gift_annual')row.append(button('延长 1 年',()=>change({action:'extend',entitlementId:item.id})));row.append(button('保存备注',()=>change({action:'note',entitlementId:item.id})),button('撤销 Gift',()=>change({action:'revoke',entitlementId:item.id})));}panel.append(row)}}
$('login').onsubmit=e=>{e.preventDefault();run(async()=>{session=$('token').value.trim();await search();$('token').value='';$('login').hidden=true;$('admin').hidden=false})};$('search').onsubmit=e=>{e.preventDefault();run(search)};$('logout').onclick=clear;window.addEventListener('pagehide',clear);
</script></html>`, { headers: {
    'Content-Type': 'text/html; charset=utf-8', 'Cache-Control': 'no-store',
    'Referrer-Policy': 'no-referrer', 'X-Content-Type-Options': 'nosniff',
    'Content-Security-Policy': `default-src 'none'; script-src 'nonce-${nonce}'; style-src 'nonce-${nonce}'; connect-src 'self'; base-uri 'none'; form-action 'self'; frame-ancestors 'none'`,
  } })
}
