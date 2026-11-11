const FEATURES = [
  {
    title: 'Preflight vor qm create',
    text: 'Image-URL wird per Range-Request (1 KB) geprüft, bevor irgendetwas angelegt wird – eine falsche Variante hinterlässt keine VM-Leiche.',
  },
  {
    title: 'SHA-256-Prüfung',
    text: 'Die apu/iris/slim-Downloads werden gegen die offiziellen Checksummen geprüft; abgebrochene ZIPs entlarvt unzip -l in Sekunden.',
  },
  {
    title: 'Thin-Pool-Wache',
    text: 'Vor der Abfrage zeigt der Installer die LVM-Thin-Füllstände. Data% über ~85 % = kritisch – Lehre aus einem vollgelaufenen pve/data.',
  },
  {
    title: 'GRUB-/syslinux-Tweak',
    text: 'i915.modeset=0 + nomodeset auf der ESP (QEMU hat keine Intel-GPU). grub.cfg und syslinux/*.cfg werden als *.orig gesichert, dm-verity bleibt unangetastet.',
  },
  {
    title: 'Serial-Console-Debug',
    text: 'Optional console=ttyS0,115200n8 in alle syslinux-Appends (idempotent) + serial0 – Kernel-Log live per qm terminal.',
  },
  {
    title: 'Idempotent & ehrlich',
    text: 'Nächste freie VMID, Abbruch statt Überschreiben, --dry-run, GPT-Backup-Fix nach Resize – und jeder Fehler nennt Befehl, Zeile und Exit-Code.',
  },
]

export function Features() {
  return (
    <div className="feature-grid">
      {FEATURES.map((f) => (
        <article key={f.title} className="feature-card">
          <h3>{f.title}</h3>
          <p>{f.text}</p>
        </article>
      ))}
    </div>
  )
}
