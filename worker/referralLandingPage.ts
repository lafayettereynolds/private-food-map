import { normalizeReferralCode } from './referralsV1'

export function referralLandingPage(rawCode: string) {
  const code=normalizeReferralCode(rawCode)
  if(!code) return new Response('邀请码无效。',{status:404})
  // Code is strictly hex; no user HTML, scripts, tokens or automatic attribution.
  return new Response(`<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Taste Map 邀请</title><main><h1>一起用 Taste Map 记录美食</h1><p>通过邀请创建新账号并完成首次有效到访，可获得一次性 14 天 Premium。</p><h2>你的邀请码</h2><p><code>${code}</code></p><p>已安装 Taste Map：在支持通用链接的 App 中打开此链接。尚未安装：安装后前往“我的 → 设置 → 邀请好友”，在 Apple 注册前填写此邀请码。</p><p>每个新用户只能绑定一位邀请人。已有账号不参与新用户奖励。</p></main></html>`,{headers:{'Content-Type':'text/html; charset=utf-8','Cache-Control':'no-store','Content-Security-Policy':"default-src 'none'; frame-ancestors 'none'; base-uri 'none'; form-action 'none'",'X-Content-Type-Options':'nosniff'}})
}
