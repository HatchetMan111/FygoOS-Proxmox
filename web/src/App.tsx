import { useState } from 'react'
import { CommandPanel } from './components/CommandPanel'
import { Configurator } from './components/Configurator'
import { Features } from './components/Features'
import { Footer } from './components/Footer'
import { Hero } from './components/Hero'
import { IconGithub } from './components/Icons'
import { Troubleshooting } from './components/Troubleshooting'
import { VariantGuide } from './components/VariantGuide'
import { DEFAULTS, type FygoConfig, type Variant } from './lib/config'

export default function App() {
  const [cfg, setCfg] = useState<FygoConfig>(DEFAULTS)
  const patch = (p: Partial<FygoConfig>) => setCfg((c) => ({ ...c, ...p }))
  const pickVariant = (v: Variant) => {
    patch({ variant: v })
    document.getElementById('konfigurator')?.scrollIntoView({ behavior: 'smooth' })
  }

  return (
    <div className="page">
      <nav className="topbar">
        <a className="brand" href="#top">
          <span className="brand-mark" aria-hidden="true">
            ▸_
          </span>
          FygoOS <span className="dim">· Proxmox</span>
        </a>
        <a
          className="btn-ghost"
          href="https://github.com/HatchetMan111/FygoOS-Proxmox"
          target="_blank"
          rel="noreferrer"
        >
          <IconGithub />
          GitHub
        </a>
      </nav>

      <main id="top">
        <Hero />

        <section id="konfigurator" className="section">
          <div className="section-head">
            <h2>Installer-Konfigurator</h2>
            <p>
              Alles einstellen wie im interaktiven Script – der Befehl rechts baut sich live. ENV-Stil für den
              Einzeiler auf dem Host, Flags für ein geklontes Repo.
            </p>
          </div>
          <div className="config-grid">
            <Configurator cfg={cfg} onChange={patch} />
            <CommandPanel cfg={cfg} />
          </div>
        </section>

        <section className="section">
          <div className="section-head">
            <h2>Welche Variante passt zu deiner CPU?</h2>
            <p>Klick setzt die Variante im Konfigurator. Im Zweifel: <strong>auto</strong> lässt das Script per lscpu wählen.</p>
          </div>
          <VariantGuide active={cfg.variant} onPick={pickVariant} />
        </section>

        <section className="section">
          <div className="section-head">
            <h2>Was der Installer macht</h2>
            <p>Sechs Schutz- und Komfortschritte, bevor die VM läuft.</p>
          </div>
          <Features />
        </section>

        <section className="section">
          <div className="section-head">
            <h2>Wenn’s hakt</h2>
            <p>Die bekannten Stolperfallen – ehrlich dokumentiert aus dem Proxmox-Forum.</p>
          </div>
          <Troubleshooting />
        </section>
      </main>

      <Footer />
    </div>
  )
}
