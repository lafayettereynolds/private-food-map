import { useEffect, useState, type CSSProperties, type ReactNode } from 'react'
import { X } from 'lucide-react'

interface ModalShellProps {
  title: string
  description?: string
  onClose: () => void
  children: ReactNode
  size?: 'small' | 'medium' | 'large'
  backdropClassName?: string
}

export function ModalShell({
  title,
  description,
  onClose,
  children,
  size = 'medium',
  backdropClassName = '',
}: ModalShellProps) {
  const [viewportMetrics, setViewportMetrics] = useState<{ height: number; offsetTop: number } | null>(null)

  useEffect(() => {
    const handleKeyDown = (event: KeyboardEvent) => {
      if (event.key === 'Escape') onClose()
    }
    document.addEventListener('keydown', handleKeyDown)
    document.body.classList.add('modal-open')
    return () => {
      document.removeEventListener('keydown', handleKeyDown)
      document.body.classList.remove('modal-open')
    }
  }, [onClose])

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
        aria-describedby={description ? 'modal-description' : undefined}
        aria-labelledby="modal-title"
        aria-modal="true"
        className={`modal modal--${size}`}
        onMouseDown={(event) => event.stopPropagation()}
        role="dialog"
      >
        <header className="modal-header">
          <div>
            <span className="eyebrow">私人餐厅库</span>
            <h2 id="modal-title">{title}</h2>
            {description ? <p id="modal-description">{description}</p> : null}
          </div>
          <button className="close-button" aria-label="关闭" onClick={onClose} type="button">
            <X size={18} />
          </button>
        </header>
        <div className="modal-content">{children}</div>
      </section>
    </div>
  )
}
