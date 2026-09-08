import { Bookmark, Dices } from 'lucide-react'
import type { MouseEvent } from 'react'
import { PlusAction } from './PlusAction'

interface RestaurantQuickActionsProps {
  restaurantName: string
  visitedActive?: boolean
  wantActive?: boolean
  wantPending?: boolean
  wheelActive?: boolean
  onRecordVisit?: () => void
  onToggleWant?: () => void
  onToggleWheel?: () => void
  className?: string
}

/**
 * The single restaurant action group used across discovery and detail surfaces.
 * Each control owns its click so restaurant-card navigation never wins the event.
 */
export function RestaurantQuickActions({
  restaurantName,
  visitedActive = false,
  wantActive = false,
  wantPending = false,
  wheelActive = false,
  onRecordVisit,
  onToggleWant,
  onToggleWheel,
  className = '',
}: RestaurantQuickActionsProps) {
  const handleAction = (event: MouseEvent<HTMLButtonElement>, action?: () => void) => {
    event.preventDefault()
    event.stopPropagation()
    action?.()
  }

  const recordLabel = visitedActive ? '再次添加' : '加入餐厅'
  const savedActive = visitedActive || wantActive
  const saveLabel = visitedActive ? '已收藏餐厅' : wantActive ? '取消收藏餐厅' : '收藏餐厅'
  const wheelLabel = wheelActive ? '移出转盘' : '加入转盘'

  return <div className={`restaurant-quick-actions${className ? ` ${className}` : ''}`} aria-label={`${restaurantName} 快捷操作`}>
    {onRecordVisit ? <PlusAction
      actionType="ADD_VISIT"
      aria-label={`${recordLabel} ${restaurantName}`}
      context="restaurant"
      label={recordLabel}
      onAction={onRecordVisit}
    /> : null}
    {onToggleWant || visitedActive ? <button
      aria-busy={wantPending}
      aria-label={`${saveLabel} ${restaurantName}`}
      aria-pressed={savedActive}
      className={savedActive ? 'is-selected' : ''}
      disabled={visitedActive || wantPending}
      onClick={(event) => handleAction(event, onToggleWant)}
      title={saveLabel}
      type="button"
    ><Bookmark fill={savedActive ? 'currentColor' : 'none'} size={18} /></button> : null}
    {onToggleWheel ? <button
      aria-label={`${wheelLabel} ${restaurantName}`}
      aria-pressed={wheelActive}
      className={wheelActive ? 'is-selected' : ''}
      onClick={(event) => handleAction(event, onToggleWheel)}
      title={wheelLabel}
      type="button"
    ><Dices size={18} /></button> : null}
  </div>
}
