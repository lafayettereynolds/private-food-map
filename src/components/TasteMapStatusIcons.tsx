import type { ComponentProps } from 'react'
import { Check } from 'lucide-react'

type VisitedIconProps = Omit<ComponentProps<typeof Check>, 'aria-label'>

/**
 * The one product-semantic glyph for an already-visited Restaurant.
 *
 * Visit count/history, dining decoration, and the add-Visit action deliberately
 * use their own symbols; they are different concepts from visited state.
 */
export function TasteMapVisitedIcon(props: VisitedIconProps) {
  return <Check {...props} aria-hidden="true" data-tastemap-semantic-icon="visited" />
}
