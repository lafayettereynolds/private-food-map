import { WalletCards } from 'lucide-react'

export function VisitSpendFields({ amount, onAmountChange }: {
  amount: string
  onAmountChange: (value: string) => void
}) {
  return <div className="visit-spend-grid" data-product-contract="automatic-visit-spend">
    <label className="field field-with-leading-icon">
      <span>消费金额（元） <small>可选</small></span>
      <div><WalletCards size={16} /><input aria-label="消费金额（元）" inputMode="decimal" min="0" onChange={(event) => onAmountChange(event.target.value)} placeholder="例如 175.00" step="0.01" type="number" value={amount} /></div>
    </label>
  </div>
}
