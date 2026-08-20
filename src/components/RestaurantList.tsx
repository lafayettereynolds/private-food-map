import { ChevronRight, MapPin, Plus, Star } from 'lucide-react'
import { RestaurantAvatar } from './RestaurantAvatar'
import { scoreColor, type RestaurantSummary } from '../types/domain'

interface RestaurantListProps {
  restaurants: RestaurantSummary[]
  selectedId?: string
  isLoading: boolean
  query: string
  activeList: 'visited' | 'wantToGo' | 'recommended'
  onSelect: (restaurant: RestaurantSummary) => void
  onAdd: () => void
}

export function RestaurantList({
  restaurants,
  selectedId,
  isLoading,
  query,
  activeList,
  onSelect,
  onAdd,
}: RestaurantListProps) {
  if (isLoading) {
    return <div className="list-loading" aria-label="正在读取本地餐厅"><i /><i /><i /></div>
  }

  if (restaurants.length === 0) {
    return (
      <div className="empty-list">
        <div className="empty-icon"><MapPin size={22} /></div>
        <h2>{query ? '没有匹配的餐厅' : activeList === 'visited' ? '还没有去过的餐厅' : activeList === 'wantToGo' ? '还没有想去的餐厅' : '还没有足够信息推荐'}</h2>
        <p>{query ? '试试搜索其他名称、标签或饭搭子。' : activeList === 'visited' ? '记录第一家吃过的餐厅，慢慢建立自己的味觉地图。' : activeList === 'wantToGo' ? '把惦记的餐厅先放进来，下次出门不用再翻收藏夹。' : '多记录几家餐厅的评分和标签，推荐会越来越贴合你的口味。'}</p>
        {!query ? <button className="text-button" onClick={onAdd} type="button"><Plus size={16} /> 添加一家餐厅</button> : null}
      </div>
    )
  }

  return (
    <div className="restaurant-list">
      {restaurants.map((restaurant) => (
        <button className={`restaurant-row${selectedId === restaurant.id ? ' is-selected' : ''}`} key={restaurant.id} onClick={() => onSelect(restaurant)} type="button">
          <RestaurantAvatar restaurant={restaurant} />
          <span className="restaurant-row__body">
            <strong>{restaurant.name}</strong>
            <span>
              {restaurant.scoreOutOfTen !== null ? <b style={{ color: scoreColor(restaurant.scoreOutOfTen) }}><Star fill="currentColor" size={10} /> {restaurant.scoreOutOfTen.toFixed(1)} 分</b> : null}
              {displayPrice(restaurant) !== null ? ` · ¥${displayPrice(restaurant)}/人` : ''}
              {restaurant.status === 'visited' ? ` · ${restaurant.visitCount} 次` : ''}
            </span>
            {restaurant.recommendationReason ? <small className="recommendation-reason">{restaurant.recommendationReason}</small> : restaurant.tags.length ? <small>{restaurant.tags.slice(0, 3).join(' · ')}</small> : null}
          </span>
          <ChevronRight size={16} />
        </button>
      ))}
    </div>
  )
}

function displayPrice(restaurant: RestaurantSummary) {
  return restaurant.status === 'visited'
    ? restaurant.averagePricePerPerson
    : restaurant.pricePerPerson
}
