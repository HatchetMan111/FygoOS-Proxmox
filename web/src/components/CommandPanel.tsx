import { useState } from 'react'
import { buildEnvCommand, buildFlagCommand, computeHints } from '../lib/command'
import type { FygoConfig } from '../lib/config'
import { CopyButton } from './CopyButton'
import { IconError, IconInfo, IconWarn } from './Icons'

const LEVEL_ICON = {
  error: <IconError />,
  warn: <IconWarn />,
  info: <IconInfo />,
} as const

export function CommandPanel({ cfg }: { cfg: FygoConfig }) {
  const [tab, setTab] = useState<'env' | 'flags'>('env')
  const command = tab === 'env' ? buildEnvCommand(cfg) : buildFlagCommand(cfg)
  const hints = computeHints(cfg)
  const errors = hints.filter((h) => h.level === 'error')
  const rest = hints.filter((h) => h.level !== 'error')

  return (
    <aside className="panel">
      <div className="terminal">
        <div className="term-bar">
          <span className="dots" aria-hidden="true">
            <i /> <i /> <i />
          </span>
          <span className="term-title">{tab === 'env' ? 'proxmox-host — root' : 'fygoos.sh (lokal)'}</span>
          <CopyButton text={command} />
        </div>
        <div className="tabs" role="tablist" aria-label="Befehls-Stil">
          <button
            type="button"
            role="tab"
            aria-selected={tab === 'env'}
            className={tab === 'env' ? 'tab on' : 'tab'}
            onClick={() => setTab('env')}
          >
            Einzeiler (ENV)
          </button>
          <button
            type="button"
            role="tab"
            aria-selected={tab === 'flags'}
            className={tab === 'flags' ? 'tab on' : 'tab'}
            onClick={() => setTab('flags')}
          >
            Flags (lokal)
          </button>
        </div>
        <pre className="term-body">
          <code>{command}</code>
        </pre>
      </div>

      {errors.length > 0 && (
        <ul className="hints blocked" aria-label="Blocker">
          {errors.map((h) => (
            <li key={h.text} className={`hint ${h.level}`}>
              {LEVEL_ICON[h.level]}
              <span>{h.text}</span>
            </li>
          ))}
        </ul>
      )}

      <ul className="hints" aria-label="Hinweise">
        {rest.map((h) => (
          <li key={h.text} className={`hint ${h.level}`}>
            {LEVEL_ICON[h.level]}
            <span>{h.text}</span>
          </li>
        ))}
      </ul>

      <p className="need">
        Bedarf: ~2,5 GB Download + ~7 GB entpackt in <code>/var/tmp</code> · {cfg.disk} GB Thin-Volume auf{' '}
        <code>{cfg.storage || 'auto'}</code>. Vorab prüfen: <code>lvs … data_percent</code> – Data% über ~85 % = kritisch.
      </p>
    </aside>
  )
}
