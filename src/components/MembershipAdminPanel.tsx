import { Sparkles } from 'lucide-react'
import { openPremiumPaywall } from '../services/premiumPaywall'

// Gift administration is a separate authenticated server page, not an App feature.
export function MembershipAdminEntry() {
  return <button className="account-setting-button" onClick={() => openPremiumPaywall('settings_entry')} type="button"><span><strong>会员与订阅</strong><small>查看会员状态、订阅方案与恢复购买</small></span><Sparkles size={17} /></button>
}
