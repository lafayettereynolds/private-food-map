/** Conservative, versioned rules; report review remains necessary for contextual abuse and images.
 * Never logs submitted text. NFKC/zero-width normalization prevents trivial evasion.
 * Food criticism, negative ratings, and ordinary links are not prohibited.
 */
export const UGC_TEXT_POLICY_VERSION = 1
const rules: ReadonlyArray<readonly [string, RegExp]> = [
  ['direct_threat', /(?:我要|我会|老子要)(?:杀死|弄死|杀了)你|\b(?:i will|i'm going to) (?:kill|murder) you\b/i],
  ['targeted_abuse', /你(?:全家|一家)(?:都)?(?:去死|死光)|\bkill yourself\b/i],
  ['sexual_exploitation', /幼女裸照|儿童色情|未成年裸聊|\bchild porn(?:ography)?\b/i],
  ['commercial_spam', /(?:刷单返利|博彩代理|代开(?:发票|票)|色情服务).{0,24}(?:加我|联系|微信|vx|QQ)|(?:加我|联系|微信|vx|QQ).{0,24}(?:刷单返利|博彩代理|代开发票|色情服务)/i],
]

export function prohibitedUGCText(text: string): string | null {
  const normalized = text.normalize('NFKC').replace(/[\u200B-\u200D\uFEFF]/g, '').replace(/\s+/g, ' ')
  return rules.find(([, pattern]) => pattern.test(normalized))?.[0] ?? null
}
