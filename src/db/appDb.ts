import Dexie, { type EntityTable } from 'dexie'
import { calculatePricePerPerson } from '../types/domain'
import type { Restaurant, Visit } from '../types/domain'

const restaurantSchema =
  'id, &amapPoiId, name, city, status, preferenceLevel, *tags, createdAt, updatedAt'
const visitSchema = 'id, restaurantId, visitedAt, createdAt, updatedAt'

class FoodMapDatabase extends Dexie {
  restaurants!: EntityTable<Restaurant, 'id'>
  visits!: EntityTable<Visit, 'id'>

  constructor() {
    super('private-food-map')

    this.version(1).stores({
      restaurants:
        'id, &amapPoiId, name, city, status, preferenceLevel, createdAt, updatedAt',
    })

    this.version(2)
      .stores({ restaurants: restaurantSchema, visits: visitSchema })
      .upgrade(async (transaction) => {
        await transaction.table('restaurants').toCollection().modify((restaurant) => {
          restaurant.markerType ??= 'emoji'
          restaurant.markerImageData ??= null
          restaurant.merchantImageUrl ??= null
          restaurant.markerEmoji ??= '🍽️'
          restaurant.tags ??= []
          restaurant.pricePerPerson ??= null
        })
      })

    this.version(3)
      .stores({ restaurants: restaurantSchema, visits: visitSchema })
      .upgrade(async (transaction) => {
        await transaction.table('visits').toCollection().modify((visit) => {
          visit.companions ??= []
          visit.partySize ??= Math.max(1, visit.companions.length + 1)
        })
      })

    this.version(4)
      .stores({ restaurants: restaurantSchema, visits: visitSchema })
      .upgrade(async (transaction) => {
        await transaction.table('visits').toCollection().modify((visit) => {
          visit.queueDuration ??= null
        })
      })

    this.version(5)
      .stores({ restaurants: restaurantSchema, visits: visitSchema })
      .upgrade(async (transaction) => {
        await transaction.table('visits').toCollection().modify((visit) => {
          visit.companions ??= []
          visit.partySize ??= Math.max(1, visit.companions.length + 1)
          visit.queueDuration ??= null
          const dishes = Array.isArray(visit.dishes) ? visit.dishes : []
          visit.dishes = dishes.map((dish: unknown, index: number) => {
            if (typeof dish === 'string') {
              return {
                id: `${visit.id}-dish-${index}`,
                name: dish,
                taste: '',
                price: null,
                imageData: null,
              }
            }
            const storedDish = dish as Record<string, unknown>
            return {
              id: typeof storedDish.id === 'string' ? storedDish.id : `${visit.id}-dish-${index}`,
              name: typeof storedDish.name === 'string' ? storedDish.name : '',
              taste: typeof storedDish.taste === 'string' ? storedDish.taste : '',
              price: typeof storedDish.price === 'number' ? storedDish.price : null,
              imageData: typeof storedDish.imageData === 'string' ? storedDish.imageData : null,
            }
          })
        })

        await transaction.table('restaurants').toCollection().modify((restaurant) => {
          restaurant.markerType ??= 'emoji'
          restaurant.markerImageData ??= null
          restaurant.merchantImageUrl ??= null
          restaurant.markerEmoji ??= '🍽️'
          restaurant.tags ??= []
          restaurant.pricePerPerson ??= null
        })
      })

    this.version(6)
      .stores({ restaurants: restaurantSchema, visits: visitSchema })
      .upgrade(async (transaction) => {
        await transaction.table('visits').toCollection().modify((visit) => {
          visit.companions ??= []
          visit.partySize ??= Math.max(1, visit.companions.length + 1)
          const legacyEnteredPrice =
            typeof visit.totalPrice === 'number'
              ? visit.totalPrice
              : typeof visit.pricePerPerson === 'number'
                ? visit.pricePerPerson
                : null
          visit.totalPrice = legacyEnteredPrice
          visit.pricePerPerson = calculatePricePerPerson(legacyEnteredPrice, visit.partySize)
          visit.photos = Array.isArray(visit.photos) ? visit.photos : []
        })

        const migratedVisits = await transaction.table('visits').toArray()
        const pricesByRestaurant = new Map<string, number[]>()
        migratedVisits.forEach((visit) => {
          if (typeof visit.pricePerPerson !== 'number') return
          const prices = pricesByRestaurant.get(visit.restaurantId) ?? []
          prices.push(visit.pricePerPerson)
          pricesByRestaurant.set(visit.restaurantId, prices)
        })

        await transaction.table('restaurants').toCollection().modify((restaurant) => {
          const prices = pricesByRestaurant.get(restaurant.id)
          if (prices?.length) {
            restaurant.pricePerPerson = Math.round(
              prices.reduce((sum, price) => sum + price, 0) / prices.length,
            )
          }
        })
      })

    this.version(7)
      .stores({ restaurants: restaurantSchema, visits: visitSchema })
      .upgrade(async (transaction) => {
        await transaction.table('visits').toCollection().modify((visit) => {
          visit.dishes = Array.isArray(visit.dishes)
            ? visit.dishes.map((dish: Record<string, unknown>) => ({
                ...dish,
                taste: typeof dish.taste === 'string' ? dish.taste : '',
              }))
            : []
        })
      })
  }
}

export const db = new FoodMapDatabase()
