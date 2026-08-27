import { Plus } from 'lucide-react'
import type { ButtonHTMLAttributes, MouseEvent } from 'react'

export type PlusActionContext = 'global' | 'restaurant'
export type PlusActionType = 'ADD_RESTAURANT' | 'ADD_VISIT'

interface PlusActionProps extends Omit<ButtonHTMLAttributes<HTMLButtonElement>, 'children' | 'onClick' | 'type'> {
  actionType: PlusActionType
  context: PlusActionContext
  label: string
  onAction: () => void
  showLabel?: boolean
  stopPropagation?: boolean
}

/**
 * The shared entry point for creating a Restaurant or Visit.
 * Restaurant-context actions own their click so a surrounding card never opens first.
 */
export function PlusAction({
  actionType,
  className = '',
  context,
  label,
  onAction,
  showLabel = false,
  stopPropagation = context === 'restaurant',
  ...buttonProps
}: PlusActionProps) {
  const handleClick = (event: MouseEvent<HTMLButtonElement>) => {
    if (stopPropagation) {
      event.preventDefault()
      event.stopPropagation()
    }
    onAction()
  }

  return <button
    {...buttonProps}
    aria-label={buttonProps['aria-label'] ?? label}
    className={`plus-action plus-action--${context}${className ? ` ${className}` : ''}`}
    data-action-type={actionType}
    onClick={handleClick}
    title={buttonProps.title ?? label}
    type="button"
  >
    <Plus aria-hidden="true" size={context === 'global' ? 21 : 18} strokeWidth={2} />
    {showLabel ? <span>{label}</span> : null}
  </button>
}
