import { useEffect, useRef, type ReactNode } from 'react'
import { createPortal } from 'react-dom'

/** Keep the caller mounted, including its sheets, drafts and scroll offsets. */
export function PremiumReturnLayer({ children, onClose }: { children: ReactNode; onClose: () => void }) {
  const dialog = useRef<HTMLDialogElement>(null)
  const close = useRef(onClose)
  close.current = onClose
  useEffect(() => {
    const element = dialog.current
    element?.showModal()
    element?.focus({ preventScroll: true })
    if (element) element.scrollTop = 0
    const escape = (event: KeyboardEvent) => {
      if (event.key !== 'Escape') return
      event.preventDefault()
      event.stopImmediatePropagation()
      close.current()
    }
    window.addEventListener('keydown', escape, true)
    return () => {
      window.removeEventListener('keydown', escape, true)
      element?.close()
    }
  }, [])
  return createPortal(<dialog ref={dialog} tabIndex={-1} aria-label="Premium 会员权益" className="premium-return-layer" onCancel={event => { event.preventDefault(); close.current() }}>{children}</dialog>, document.body)
}
