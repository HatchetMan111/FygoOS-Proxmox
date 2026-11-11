import type { CSSProperties, ReactNode } from 'react'

interface FieldProps {
  label: string
  hint?: string
  children: ReactNode
}

export function Field({ label, hint, children }: FieldProps) {
  return (
    <div className="field">
      <span className="field-label">
        {label}
        {hint && <em>{hint}</em>}
      </span>
      {children}
    </div>
  )
}

interface SegmentedProps<T extends string> {
  label: string
  hint?: string
  value: T
  options: { value: T; label: string }[]
  onChange: (v: T) => void
}

export function Segmented<T extends string>({ label, hint, value, options, onChange }: SegmentedProps<T>) {
  return (
    <div className="field">
      <span className="field-label">
        {label}
        {hint && <em>{hint}</em>}
      </span>
      <div className="segmented" role="radiogroup" aria-label={label}>
        {options.map((o) => (
          <button
            key={o.value}
            type="button"
            role="radio"
            aria-checked={value === o.value}
            className={value === o.value ? 'seg on' : 'seg'}
            onClick={() => onChange(o.value)}
          >
            {o.label}
          </button>
        ))}
      </div>
    </div>
  )
}

interface SliderProps {
  label: string
  hint?: string
  min: number
  max: number
  step: number
  value: number
  display: string
  onChange: (v: number) => void
}

export function Slider({ label, hint, min, max, step, value, display, onChange }: SliderProps) {
  const fill = `${(((value - min) / (max - min)) * 100).toFixed(1)}%`
  return (
    <Field label={label} hint={hint}>
      <div className="slider-row">
        <input
          type="range"
          min={min}
          max={max}
          step={step}
          value={value}
          aria-label={label}
          style={{ '--fill': fill } as CSSProperties}
          onChange={(e) => onChange(Number(e.target.value))}
        />
        <output className="slider-value">{display}</output>
      </div>
    </Field>
  )
}

interface ToggleProps {
  label: string
  desc?: string
  checked: boolean
  onChange: (v: boolean) => void
}

export function Toggle({ label, desc, checked, onChange }: ToggleProps) {
  return (
    <button
      type="button"
      role="switch"
      aria-checked={checked}
      className={checked ? 'toggle on' : 'toggle'}
      onClick={() => onChange(!checked)}
    >
      <span className="switch" aria-hidden="true" />
      <span className="toggle-text">
        <strong>{label}</strong>
        {desc && <small>{desc}</small>}
      </span>
    </button>
  )
}
