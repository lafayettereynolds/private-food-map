import { ChevronRight, MapPin, Star } from 'lucide-react'
import { PlusAction } from './PlusAction'
import { RestaurantAvatar } from './RestaurantAvatar'
import { RestaurantQuickActions } from './RestaurantQuickActions'
import { scoreColor, type RestaurantSummary } from '../types/domain'

interface RestaurantListProps {
  restaurants: RestaurantSummary[]
  selectedId?: string
  isLoading: boolean
  query: string
  activeList: 'visited' | 'wantToGo' | 'recommended'
  emptyMessage?: string
  emptyTitle?: string
  emptyActionLabel?: string
  onEmptyAction?: () => void
  onSelect: (restaurant: RestaurantSummary) => void
  onAdd: () => void
  onMarkVisited: (restaurant: RestaurantSummary) => void
  onAddToWant: (restaurant: RestaurantSummary) => void
  onAddToRoulette: (restaurant: RestaurantSummary) => void
}

export function RestaurantList({
  restaurants,
  selectedId,
  isLoading,
  query,
  activeList,
  emptyMessage,
  emptyTitle,
  emptyActionLabel,
  onEmptyAction,
  onSelect,
  onAdd,
  onMarkVisited,
  onAddToWant,
  onAddToRoulette,
}: RestaurantListProps) {
  if (isLoading) {
    return <div className="list-loading" aria-label="正在读取本地餐厅"><i /><i /><i /></div>
  }

  if (restaurants.length === 0) {
    return (
      <div className="empty-list">
        <div className="empty-icon"><MapPin size={22} /></div>
        <h2>{emptyTitle || (query ? '没有匹配的餐厅' : activeList === 'visited' ? '还没有去过的餐厅' : activeList === 'wantToGo' ? '还没有想去的餐厅' : '还没有足够信息推荐')}</h2>
        <p>{emptyMessage || (query ? '试试搜索其他餐厅名称、城市或饭搭子。' : activeList === 'visited' ? '记录第一家吃过的餐厅，慢慢建立自己的味觉地图。' : activeList === 'wantToGo' ? '把惦记的餐厅先放进来，下次出门不用再翻收藏夹。' : '多记录餐厅评分和菜品星级，推荐会越来越贴合你的口味。')}</p>
        {emptyActionLabel && onEmptyAction ? <button className="secondary-button recommendation-relax-button" onClick={onEmptyAction} type="button">{emptyActionLabel}</button> : null}
        {!query && !emptyActionLabel ? <PlusAction actionType="ADD_RESTAURANT" className="empty-list__add" context="global" label="添加一家餐厅" onAction={onAdd} showLabel /> : null}
      </div>
    )
  }

  return (
    <div className="restaurant-list">
      {restaurants.map((restaurant) => <div className={`restaurant-row${selectedId === restaurant.id ? ' is-selected' : ''}`} key={restaurant.id}>
        <button aria-label={`查看 ${restaurant.name}`} className="restaurant-row__select" onClick={() => onSelect(restaurant)} type="button">
          <RestaurantAvatar restaurant={restaurant} />
          <span className="restaurant-row__body">
            <strong>{restaurant.name}</strong>
            <span>
              {restaurant.scoreOutOfTen !== null ? <b style={{ color: scoreColor(restaurant.scoreOutOfTen) }}><Star fill="currentColor" size={10} /> {restaurant.scoreOutOfTen.toFixed(1)} 分</b> : null}
              {displayPrice(restaurant) !== null ? ` · ¥${displayPrice(restaurant)}/人` : ''}
              {restaurant.status === 'visited' ? ` · ${restaurant.visitCount} 次` : ''}
            </span>
            <small className="restaurant-row__location"><MapPin size={10} />{[restaurant.city, restaurant.address].filter(Boolean).join(' · ')}</small>
            {restaurant.recommendationReason ? <small className="recommendation-reason">{restaurant.recommendationReason}</small> : null}
          </span>
          <ChevronRight size={15} />
        </button>
        <RestaurantQuickActions
          className="restaurant-row__quick-actions"
          onRecordVisit={() => onMarkVisited(restaurant)}
          onToggleWant={() => onAddToWant(restaurant)}
          onToggleWheel={() => onAddToRoulette(restaurant)}
          restaurantName={restaurant.name}
          visitedActive={restaurant.status === 'visited'}
          wantActive={restaurant.status === 'wantToGo'}
        />
      </div>)}
    </div>
  )
}

function displayPrice(restaurant: RestaurantSummary) {
  return restaurant.status === 'visited'
    ? restaurant.averagePricePerPerson
    : restaurant.pricePerPerson
}
