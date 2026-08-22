import { useState, type ChangeEvent } from 'react'
import { ChevronDown, ImagePlus, Plus, Star, Trash2, UtensilsCrossed } from 'lucide-react'
import type { StarRating, VisitDish } from '../types/domain'
import { optimizeMarkerImage } from '../utils/images'
import { SyncedImage } from './SyncedImage'

interface DishEditorProps {
  value: VisitDish[]
  onChange: (value: VisitDish[]) => void
}

function createDish(): VisitDish {
  return {
    id: 'randomUUID' in crypto ? crypto.randomUUID() : `${Date.now()}-${Math.random()}`,
    name: '',
    taste: '',
    rating: null,
    price: null,
    imageData: null,
    photoId: null,
  }
}

export function DishEditor({ value, onChange }: DishEditorProps) {
  const [expanded, setExpanded] = useState(value.length > 0)
  const [error, setError] = useState('')

  function updateDish(id: string, changes: Partial<VisitDish>) {
    onChange(value.map((dish) => (dish.id === id ? { ...dish, ...changes } : dish)))
  }

  async function handleImage(dishId: string, event: ChangeEvent<HTMLInputElement>) {
    const file = event.target.files?.[0]
    event.target.value = ''
    if (!file) return
    setError('')
    try {
      updateDish(dishId, { imageData: await optimizeMarkerImage(file), photoId: null })
    } catch (imageError) {
      setError(imageError instanceof Error ? imageError.message : '图片处理失败。')
    }
  }

  function addDish() {
    setExpanded(true)
    onChange([...value, createDish()])
  }

  return (
    <section className="dish-editor">
      <header className="dish-editor__header">
        <button className="dish-editor__toggle" disabled={!value.length} onClick={() => setExpanded((current) => !current)} type="button">
          <span><UtensilsCrossed size={15} /><strong>菜品</strong>{value.length ? <b>{value.length}</b> : null}</span>
          {value.length ? <ChevronDown className={expanded ? 'is-open' : ''} size={15} /> : null}
        </button>
        <button className="dish-editor__quick-add" onClick={addDish} type="button"><Plus size={13} /> 添加</button>
      </header>

      {expanded ? (
        <div className="dish-editor__content">
          {value.map((dish, index) => (
            <article className="dish-row" key={dish.id}>
              <label className="dish-image-input">
                {dish.imageData || dish.photoId ? <SyncedImage alt="" photoId={dish.photoId} source={dish.imageData} /> : <ImagePlus size={18} />}
                <input accept="image/*" hidden onChange={(event) => handleImage(dish.id, event)} type="file" />
              </label>
              <label className="field"><span>菜名 {index + 1}</span><input onChange={(event) => updateDish(dish.id, { name: event.target.value })} placeholder="例如：寿喜烧" value={dish.name} /></label>
              <label className="field dish-taste-field"><span>口味</span><input onChange={(event) => updateDish(dish.id, { taste: event.target.value })} placeholder="例如：甜香浓郁" value={dish.taste} /></label>
              <fieldset className="dish-rating-field"><legend>星级</legend><div>{([1, 2, 3, 4, 5] as StarRating[]).map((star) => <button aria-label={`${star} 星`} className={dish.rating !== null && star <= dish.rating ? 'is-active' : ''} key={star} onClick={() => updateDish(dish.id, { rating: dish.rating === star ? null : star })} type="button"><Star fill={dish.rating !== null && star <= dish.rating ? 'currentColor' : 'none'} size={14} /></button>)}</div></fieldset>
              <label className="field dish-price-field"><span>价格</span><input inputMode="decimal" min="0" onChange={(event) => updateDish(dish.id, { price: event.target.value ? Number(event.target.value) : null })} placeholder="¥" step="0.01" type="number" value={dish.price ?? ''} /></label>
              <button className="plain-icon-button" aria-label={`删除第 ${index + 1} 道菜`} onClick={() => onChange(value.filter((item) => item.id !== dish.id))} type="button"><Trash2 size={14} /></button>
            </article>
          ))}
          {error ? <p className="form-error">{error}</p> : null}
        </div>
      ) : null}
    </section>
  )
}
