import { ONE_LINER } from '../lib/config'
import { CopyButton } from './CopyButton'

export function Hero() {
  return (
    <header className="hero">
      <div className="badges">
        <span className="badge">Proxmox VE</span>
        <span className="badge">FydeOS/FygoOS v23.0-SP1</span>
        <span className="badge">UEFI/OVMF + efidisk</span>
        <span className="badge">Bash · keine Abhängigkeiten</span>
      </div>
      <h1>
        FygoOS auf Proxmox VE<span className="accent">.</span> Ein Befehl.
      </h1>
      <p className="lead">
        ChromeOS-artiges Desktop-OS (FygoOS, ehem. FydeOS) als VM installieren – nach der bewährten
        Foren-Methode: <code>.img/.bin.zip</code> laden, entpacken, <code>qm disk import</code>, als SATA einhängen.
        Der Installer prüft vorab URL, SHA-256 und Thin-Pool und patcht <code>nomodeset</code> auf die ESP.
      </p>
      <div className="terminal hero-terminal">
        <div className="term-bar">
          <span className="dots" aria-hidden="true">
            <i /> <i /> <i />
          </span>
          <span className="term-title">proxmox-host — root</span>
          <CopyButton text={ONE_LINER} />
        </div>
        <pre className="term-body">
          <code>{ONE_LINER}</code>
        </pre>
      </div>
      <a className="btn-primary" href="#konfigurator">
        Konfigurator öffnen ↓
      </a>
    </header>
  )
}
