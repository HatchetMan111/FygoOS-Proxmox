import { VARIANTS, type Variant } from '../lib/config'

interface Props {
  active: Variant
  onPick: (v: Variant) => void
}

export function VariantGuide({ active, onPick }: Props) {
  return (
    <div className="variant-grid">
      {VARIANTS.map((v) => (
        <button
          key={v.key}
          type="button"
          className={active === v.key ? 'variant-card on' : 'variant-card'}
          onClick={() => onPick(v.key)}
          aria-pressed={active === v.key}
        >
          <span className="variant-key">{v.label}</span>
          <span className="variant-cpu">{v.cpu}</span>
          <span className="variant-gpu">GPU: {v.gpu}</span>
          <span className="variant-note">{v.note}</span>
        </button>
      ))}
    </div>
  )
}
