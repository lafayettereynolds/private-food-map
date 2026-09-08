import { LockKeyhole } from 'lucide-react'
import { usePremiumAccess } from './PremiumAccess'

/** Keep the feature name visible while communicating its actual access state. */
export function PremiumFeatureLabel({ children }: { children: string }) {
  const allowed = usePremiumAccess()
  return <span className="premium-feature-label">{children}{!allowed ? <LockKeyhole aria-label="会员专享" size={12} /> : null}</span>
}
