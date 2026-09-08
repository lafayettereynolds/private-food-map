import { useCallback, useEffect, useRef, useState, type FormEvent } from 'react'
import { createPortal } from 'react-dom'
import { Building2, ChevronsUpDown } from 'lucide-react'
import { ModalShell } from './ModalShell'
import { restaurantCityComparisonKey, restaurantCityFilterOptions } from '../services/restaurantCity'

/** Query labels only; never rewrites stored Restaurant or GPS city fields. */
export function discoveryCityQuery(value: string, suggestions: readonly string[] = []): string {
  const query = value.normalize('NFKC').trim().replace(/\s+/gu, ' ')
  if (!query) return ''
  // Preserve the server's known spelling (杭州/杭州市) without restricting
  // free entry to that list. Unknown cities remain the user's explicit query.
  return suggestions.find((candidate) => restaurantCityComparisonKey(candidate) === restaurantCityComparisonKey(query))?.trim() ?? query
}

export function TasteMapCitySearch({ city, suggestions, onChange }: {
  city: string
  suggestions: readonly string[]
  onChange: (city: string) => void
}) {
  const [open, setOpen] = useState(false)
  const [draft, setDraft] = useState(city)
  const form = useRef<HTMLFormElement>(null)
  const returnScroll = useRef({ top: 0, left: 0 })
  const restoreFrame = useRef<number | null>(null)
  const closing = useRef(false)
  useEffect(() => () => {
    if (restoreFrame.current !== null) cancelAnimationFrame(restoreFrame.current)
    form.current?.querySelector('input')?.blur()
  }, [])
  const close = useCallback((onClosed?: () => void) => {
    if (closing.current) return
    closing.current = true
    // WKWebView may scroll the document while revealing the keyboard. Release
    // focus before removing the portal, then wait for its scroll lock cleanup.
    form.current?.querySelector('input')?.blur()
    setOpen(false)
    restoreFrame.current = requestAnimationFrame(() => {
      restoreFrame.current = requestAnimationFrame(() => {
        restoreFrame.current = null
        window.scrollTo({ ...returnScroll.current, behavior: 'instant' })
        // Apply the query after restoration: any caller-owned scroll-to-top
        // rule wins, and no delayed restoration fights the user's next scroll.
        onClosed?.()
      })
    })
  }, [])
  const options = restaurantCityFilterOptions(suggestions)
  const select = (value: string) => {
    const query = discoveryCityQuery(value, suggestions)
    close(() => onChange(query))
  }
  const submit = (event: FormEvent) => { event.preventDefault(); select(draft) }
  return <>
    <button aria-label={city ? `搜索城市，当前${city}` : '搜索城市'} aria-haspopup="dialog" aria-expanded={open}
      className={city ? 'is-active' : ''} type="button" onClick={() => {
        if (restoreFrame.current !== null) cancelAnimationFrame(restoreFrame.current)
        closing.current = false
        returnScroll.current = { top: window.scrollY, left: window.scrollX }
        setDraft(city); setOpen(true)
      }}>
      <Building2 aria-hidden="true" size={14} /><span>{city || '搜索城市'}</span><ChevronsUpDown aria-hidden="true" size={12} />
    </button>
    {open ? createPortal(<ModalShell title="搜索城市" eyebrow={null} description="输入你想探索的城市，不限于下面已出现的城市。" onClose={() => close()} size="small" backdropClassName="tm-discovery-filter-sheet">
      <form ref={form} onSubmit={submit}>
        <div className="discovery-filter-grid">
          <label><span>城市名称</span><input aria-label="城市名称" autoComplete="off" maxLength={80} value={draft} onChange={(event) => setDraft(event.target.value)} placeholder="例如：成都、杭州市、东京" /></label>
          {options.length ? <fieldset><legend>已出现的城市</legend>{options.map((value) => <button type="button" key={value} aria-pressed={restaurantCityComparisonKey(value) === restaurantCityComparisonKey(draft)} onClick={() => select(value)}>{value}</button>)}</fieldset> : null}
        </div>
        <div className="modal-actions"><button type="button" onClick={() => select('')}>重置城市</button><button type="submit">搜索</button></div>
      </form>
    </ModalShell>, document.body) : null}
  </>
}
