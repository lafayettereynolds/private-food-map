import { LoaderCircle } from 'lucide-react'

interface StickyFormActionBarProps {
  primaryLabel: string
  primaryAction?: () => void
  primaryDisabled?: boolean
  primaryLoading?: boolean
  secondaryLabel?: string
  secondaryAction?: () => void
  statusMessage?: string
  statusTone?: 'neutral' | 'error' | 'success'
}

export function StickyFormActionBar({
  primaryLabel,
  primaryAction,
  primaryDisabled = false,
  primaryLoading = false,
  secondaryLabel = '取消',
  secondaryAction,
  statusMessage = '',
  statusTone = 'neutral',
}: StickyFormActionBarProps) {
  return (
    <footer className="sticky-form-action-bar" aria-busy={primaryLoading}>
      {statusMessage ? <p className={`sticky-form-action-bar__status is-${statusTone}`} role={statusTone === 'error' ? 'alert' : 'status'}>{statusMessage}</p> : null}
      <div className="sticky-form-action-bar__buttons">
        {secondaryAction ? <button className="secondary-button" disabled={primaryLoading} onClick={secondaryAction} type="button">{secondaryLabel}</button> : null}
        <button className="primary-button" disabled={primaryDisabled || primaryLoading} onClick={primaryAction} type={primaryAction ? 'button' : 'submit'}>
          {primaryLoading ? <LoaderCircle className="spin" size={17} /> : null}
          {primaryLoading ? '保存中…' : primaryLabel}
        </button>
      </div>
    </footer>
  )
}
