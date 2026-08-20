import { PREFERENCE_META, type PreferenceLevel } from '../types/domain'

export function PreferencePicker({
  value,
  onChange,
}: {
  value: PreferenceLevel
  onChange: (value: PreferenceLevel) => void
}) {
  return (
    <fieldset className="preference-picker">
      <legend>我的喜好 <small>决定地图颜色，与评分独立</small></legend>
      <div>
        {(Object.entries(PREFERENCE_META) as [PreferenceLevel, (typeof PREFERENCE_META)[PreferenceLevel]][]).map(([level, item]) => (
          <label className={value === level ? 'is-checked' : ''} key={level}>
            <input checked={value === level} name="preference-level" onChange={() => onChange(level)} type="radio" value={level} />
            <i style={{ background: item.color }} />
            {item.shortLabel}
          </label>
        ))}
      </div>
    </fieldset>
  )
}
