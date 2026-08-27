export function PremiumBurgerBadge({ className = '', title = 'Taste Map 会员' }: { className?: string; title?: string }) {
  return <span aria-label={title} className={`premium-burger-badge${className ? ` ${className}` : ''}`} role="img" title={title}>
    <svg aria-hidden="true" fill="none" viewBox="0 0 24 24">
      <path className="premium-burger-badge__bun" d="M4.7 10.2c.4-3.4 3.2-5.7 7.3-5.7s6.9 2.3 7.3 5.7H4.7Z" />
      <path className="premium-burger-badge__greens" d="M4.5 12h15l-2 2.2-2.5-1.3-2.8 1.5-2.6-1.5-2.4 1.3L4.5 12Z" />
      <path className="premium-burger-badge__patty" d="M5.2 15.2h13.6v2.1H5.2z" />
      <path className="premium-burger-badge__bottom" d="M5.5 18.2h13v.3a1.7 1.7 0 0 1-1.7 1.7H7.2a1.7 1.7 0 0 1-1.7-1.7v-.3Z" />
      <path className="premium-burger-badge__seeds" d="M8.7 7.6h.1M12 6.7h.1M15.2 7.6h.1" />
    </svg>
  </span>
}
