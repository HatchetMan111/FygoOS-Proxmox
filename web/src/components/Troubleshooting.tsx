import type { ReactNode } from 'react'

interface Item {
  summary: string
  children: ReactNode
}

function Item({ summary, children }: Item) {
  return (
    <details className="trouble-item">
      <summary>
        {summary}
        <span className="chev" aria-hidden="true" />
      </summary>
      <div className="trouble-body">{children}</div>
    </details>
  )
}

function Cmd({ children }: { children: string }) {
  return (
    <pre className="cmd">
      <code>{children}</code>
    </pre>
  )
}

export function Troubleshooting() {
  return (
    <div className="trouble-list">
      <Item summary="Schwarzer Bildschirm / Boot hängt beim Grafik-Init">
        <p>
          FydeOS supportet offiziell nur VMware; unter KVM bleibt der Boot teils beim Grafik-Init stehen
          (2 GB → Reboot-Loop, viel RAM → teils Stillstand). Bewährt:
        </p>
        <Cmd>{`qm set 100 --cpu host      # falls nicht schon host
qm set 100 --memory 8192   # mehr RAM
qm set 100 --vga none      # internes VGA aus + echte GPU per PCI-Passthrough
lspci | grep -i vga        # PCI-Adresse suchen
qm set 100 --hostpci0 <PCI>,pcie=1   # Forum: RX550 funktioniert`}</Cmd>
        <p>Ohne GPU-Passthrough kann der Installer das nicht lösen – FygoOS ist ein Desktop-OS.</p>
      </Item>

      <Item summary="VM hat kein Netz">
        <p>VirtIO wird meist erkannt. Falls nicht: auf e1000 wechseln und neu starten.</p>
        <Cmd>{`qm set 100 --delete net0
qm set 100 --net0 e1000,bridge=vmbr0
qm start 100`}</Cmd>
        <p>
          In FygoOS: <kbd>Strg</kbd>+<kbd>Alt</kbd>+<kbd>F2</kbd> → Shell → <code>ifconfig eth0</code>.
        </p>
      </Item>

      <Item summary="Kernel-Log mitlesen (Serial Console)">
        <p>Mit Serial-Console hängt der Installer console=ttyS0,115200n8 an alle syslinux-Appends (idempotent):</p>
        <Cmd>{`bash fygoos.sh --serial-console
qm terminal 100     # Kernel-Log live (beenden: Strg+O)
timeout 60 socat - UNIX-CONNECT:/var/run/qemu-server/100.serial   # nicht-interaktiv`}</Cmd>
        <p>
          Die letzten Zeilen vor dem Stillstand nennen die echte Ursache (<code>Waiting for root device</code>,{' '}
          <code>Kernel panic</code>, Treiber-Fehler).
        </p>
      </Item>

      <Item summary="Neu installieren / Variante wechseln">
        <p>Ein In-Place-Upgrade gibt es nicht – neue VM aus neuem Image:</p>
        <Cmd>{`qm stop 100 && qm destroy 100 --purge   # spart Thin-Pool-Platz
VARIANT=auto NIC=e1000 VGA=virtio BIOS=seabios bash -c "$(wget -qLO - \\
  https://raw.githubusercontent.com/HatchetMan111/FygoOS-Proxmox/main/install/fygoos.sh)"`}</Cmd>
      </Item>

      <Item summary="Reboot-Sicherheit belegen">
        <Cmd>{`qm reboot 100
sleep 90
qm status 100    # erwartet: status: running (onboot=1 ist gesetzt)`}</Cmd>
      </Item>

      <Item summary="VM wieder loswerden">
        <Cmd>{`qm stop 100 && qm destroy 100 --purge`}</Cmd>
        <p>Gibt Disk und efidisk im Thin-Pool frei. Das Download-Cache-Verzeichnis <code>/var/tmp/fygoos-install</code> räumt der Installer selbst auf.</p>
      </Item>
    </div>
  )
}
