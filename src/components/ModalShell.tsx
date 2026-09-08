import { useEffect, useRef, useState, type CSSProperties, type ReactNode } from 'react'
import { X } from 'lucide-react'
import { PageBackIconButton } from './TasteMapHybridShared'

// Every shared modal participates in one background lock. A nested sheet closing
// must not expose the page navigation or unlock scrolling beneath its parent.
const modalCountAttribute = 'data-tm-open-modals'

interface ModalShellProps {
  title: string
  /** Override the legacy private-library context; null hides it explicitly. */
  eyebrow?: string | null
  description?: string
  onClose: () => void
  children: ReactNode
  size?: 'small' | 'medium' | 'large'
  backdropClassName?: string
  dismissAction?: 'close' | 'back'
  dismissDisabled?: boolean
}

export function ModalShell({
  title,
  eyebrow = '私人餐厅库',
  description,
  onClose,
  children,
  size = 'medium',
  backdropClassName = '',
  dismissAction = 'close',
  dismissDisabled = false,
}: ModalShellProps) {
  const [viewportMetrics, setViewportMetrics] = useState<{ height: number; offsetTop: number } | null>(null)
  const modalRef = useRef<HTMLElement>(null)

  useEffect(() => {
    const handleKeyDown = (event: KeyboardEvent) => {
      if (event.key === 'Escape') onClose()
    }
    document.addEventListener('keydown', handleKeyDown)
    return () => {
      document.removeEventListener('keydown', handleKeyDown)
    }
  }, [onClose])

  useEffect(() => {
    const count = () => Number(document.body.getAttribute(modalCountAttribute) ?? 0)
    document.body.setAttribute(modalCountAttribute, String(count() + 1))
    document.body.classList.add('modal-open')
    return () => {
      const remaining = Math.max(0, count() - 1)
      if (remaining) document.body.setAttribute(modalCountAttribute, String(remaining))
      else {
        document.body.removeAttribute(modalCountAttribute)
        document.body.classList.remove('modal-open')
      }
    }
  }, [])

  useEffect(() => {
    // Keyboard resizing must scroll the form's own content, never the whole
    // document/header. Do not refocus, blur, or disturb native text selection.
    const frame = requestAnimationFrame(() => {
      const focused = document.activeElement
      if (!(focused instanceof HTMLElement) || !modalRef.current?.contains(focused)) return
      const scroller = focused.closest<HTMLElement>('.sticky-action-form__content, .modal-content')
      if (!scroller) return
      const field = focused.getBoundingClientRect()
      const bounds = scroller.getBoundingClientRect()
      if (field.height > bounds.height) return
      if (field.bottom > bounds.bottom) scroller.scrollTop += field.bottom - bounds.bottom
      else if (field.top < bounds.top) scroller.scrollTop -= bounds.top - field.top
    })
    return () => cancelAnimationFrame(frame)
  }, [viewportMetrics])

  useEffect(() => {
    const viewport = window.visualViewport
    const updateViewportMetrics = () => setViewportMetrics({
      height: viewport?.height ?? window.innerHeight,
      offsetTop: viewport?.offsetTop ?? 0,
    })
    updateViewportMetrics()
    viewport?.addEventListener('resize', updateViewportMetrics)
    viewport?.addEventListener('scroll', updateViewportMetrics)
    window.addEventListener('resize', updateViewportMetrics)
    return () => {
      viewport?.removeEventListener('resize', updateViewportMetrics)
      viewport?.removeEventListener('scroll', updateViewportMetrics)
      window.removeEventListener('resize', updateViewportMetrics)
    }
  }, [])

  return (
    <div
      className={`modal-backdrop${backdropClassName ? ` ${backdropClassName}` : ''}`}
      role="presentation"
      onMouseDown={onClose}
      style={viewportMetrics ? {
        '--modal-viewport-height': `${viewportMetrics.height}px`,
        '--modal-viewport-offset-top': `${viewportMetrics.offsetTop}px`,
      } as CSSProperties : undefined}
    >
      <section
        ref={modalRef}
        aria-describedby={description ? 'modal-description' : undefined}
        aria-labelledby="modal-title"
        aria-modal="true"
        className={`modal modal--${size}`}
        onMouseDown={(event) => event.stopPropagation()}
        role="dialog"
      >
        <header className={`modal-header${dismissAction === 'back' ? ' modal-header--back' : ''}`}>
          {dismissAction === 'back' ? <PageBackIconButton disabled={dismissDisabled} onBack={onClose} /> : null}
          <div>
            {eyebrow ? <span className="eyebrow">{eyebrow}</span> : null}
            <h2 id="modal-title">{title}</h2>
            {description ? <p id="modal-description">{description}</p> : null}
          </div>
          {dismissAction === 'close' ? <button className="close-button" aria-label="关闭" disabled={dismissDisabled} onClick={onClose} type="button">
            <X size={18} />
          </button> : null}
        </header>
        <div className="modal-content">{children}</div>
      </section>
    </div>
  )
}
