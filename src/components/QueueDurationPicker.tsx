import { Clock3 } from 'lucide-react'
import { QUEUE_DURATION_OPTIONS, type QueueDuration } from '../types/domain'

interface QueueDurationPickerProps {
  value: QueueDuration
  onChange: (value: QueueDuration) => void
}

export function QueueDurationPicker({ value, onChange }: QueueDurationPickerProps) {
  return (
    <fieldset className="queue-duration-field">
      <legend><Clock3 size={14} /> 排队时长</legend>
      <div className="queue-duration-options">
        {QUEUE_DURATION_OPTIONS.map((option) => (
          <button
            aria-pressed={value === option.value}
            className={value === option.value ? 'is-active' : ''}
            key={option.value}
            onClick={() => onChange(option.value)}
            type="button"
          >
            {option.label}
          </button>
        ))}
      </div>
    </fieldset>
  )
}
