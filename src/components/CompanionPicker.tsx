import { UserRound } from 'lucide-react'
import { splitCompanions } from '../utils/companions'

interface CompanionPickerProps {
  onChange: (value: string) => void
  options: string[]
  value: string
}

export function CompanionPicker({ onChange, options, value }: CompanionPickerProps) {
  const selectedCompanions = splitCompanions(value)

  function toggleCompanion(name: string) {
    const nextCompanions = selectedCompanions.includes(name)
      ? selectedCompanions.filter((companion) => companion !== name)
      : [...selectedCompanions, name]
    onChange(nextCompanions.join('、'))
  }

  return (
    <div className="field field-with-leading-icon companion-picker">
      <span>饭搭子</span>
      <div className="companion-picker__input">
        <UserRound size={16} />
        <input aria-label="饭搭子" onChange={(event) => onChange(event.target.value)} placeholder="小王、妈妈" value={value} />
      </div>
      {options.length ? (
        <section aria-label="常用饭搭子" className="companion-picker__options">
          {options.map((name) => (
            <button
              aria-pressed={selectedCompanions.includes(name)}
              className={selectedCompanions.includes(name) ? 'is-selected' : ''}
              key={name}
              onClick={() => toggleCompanion(name)}
              type="button"
            >
              {name}
            </button>
          ))}
        </section>
      ) : <small className="companion-picker__hint">使用过的人会自动出现在这里，之后可以直接点选。</small>}
    </div>
  )
}
