import { ChevronDown, ChevronUp, UserRound } from 'lucide-react'
import { useRef, useState } from 'react'
import { splitCompanions } from '../utils/companions'

interface CompanionPickerProps {
  onChange: (value: string) => void
  options: string[]
  value: string
}

export function CompanionPicker({ onChange, options, value }: CompanionPickerProps) {
  const [showAll, setShowAll] = useState(false)
  const inputRef = useRef<HTMLInputElement>(null)
  const selectedCompanions = splitCompanions(value)
  const orderedOptions = [...options].sort((left, right) => Number(selectedCompanions.includes(right)) - Number(selectedCompanions.includes(left)))
  const visibleOptions = showAll ? orderedOptions : orderedOptions.slice(0, 5)

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
        <input aria-label="饭搭子" onChange={(event) => onChange(event.target.value)} placeholder="小王、妈妈" ref={inputRef} value={value} />
      </div>
      {options.length ? (
        <section aria-label="常用饭搭子" className="companion-picker__options">
          {visibleOptions.map((name) => (
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
          <button className="companion-picker__more" onClick={() => { if (options.length > 5) setShowAll((current) => !current); else inputRef.current?.focus() }} type="button">{showAll ? <ChevronUp size={12} /> : options.length > 5 ? <ChevronDown size={12} /> : null}{showAll ? '收起' : options.length > 5 ? '更多' : '添加'}</button>
        </section>
      ) : <button className="companion-picker__empty-add" onClick={() => inputRef.current?.focus()} type="button">添加饭搭子</button>}
    </div>
  )
}
