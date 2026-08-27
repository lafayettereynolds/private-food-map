import { Bookmark, Dices } from 'lucide-react'
import type { MouseEvent } from 'react'
import { PlusAction } from './PlusAction'

interface RestaurantQuickActionsProps {
  restaurantName: string
  visitedActive?: boolean
  wantActive?: boolean
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

  return <div className={`restaurant-quick-actions${className ? ` ${className}` : ''}`} aria-label={`${restaurantName} 快捷操作`}>
    {onRecordVisit ? <PlusAction
      actionType="ADD_VISIT"
      aria-label={`${visitedActive ? '再次记录到访' : '记录这家餐厅'} ${restaurantName}`}
      context="restaurant"
      label={visitedActive ? '再次记录到访' : '记录这家餐厅'}
      onAction={onRecordVisit}
    /> : null}
    {onToggleWant ? <button
      aria-label={`${wantActive ? '移出想吃' : '加入想吃'} ${restaurantName}`}
      aria-pressed={wantActive}
      className={wantActive ? 'is-selected' : ''}
      onClick={(event) => handleAction(event, onToggleWant)}
      title={wantActive ? '移出想吃' : '加入想吃'}
      type="button"
    ><Bookmark fill={wantActive ? 'currentColor' : 'none'} size={18} /></button> : null}
    {onToggleWheel ? <button
      aria-label={`${wheelActive ? '移出抽签' : '加入抽签'} ${restaurantName}`}
      aria-pressed={wheelActive}
      className={wheelActive ? 'is-selected' : ''}
      onClick={(event) => handleAction(event, onToggleWheel)}
      title={wheelActive ? '移出抽签' : '加入抽签'}
      type="button"
    ><Dices size={18} /></button> : null}
  </div>
}
