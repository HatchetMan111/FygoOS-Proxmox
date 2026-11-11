import { DEFAULTS, type Bios, type BootDisk, type FygoConfig, type Nic, type Vga } from '../lib/config'
import { Field, Segmented, Slider, Toggle } from './ui'

interface Props {
  cfg: FygoConfig
  onChange: (patch: Partial<FygoConfig>) => void
}

export function Configurator({ cfg, onChange }: Props) {
  return (
    <div className="config-form">
      <div className="form-group">
        <h3>Ressourcen</h3>
        <div className="field-row">
          <Field label="VMID" hint="leer = nächste freie">
            <input
              type="text"
              inputMode="numeric"
              placeholder="auto"
              value={cfg.vmid}
              onChange={(e) => onChange({ vmid: e.target.value.replace(/[^0-9]/g, '') })}
            />
          </Field>
          <Field label="VM-Name">
            <input type="text" value={cfg.name} onChange={(e) => onChange({ name: e.target.value })} />
          </Field>
        </div>
        <Slider
          label="vCPU"
          hint="min. 2, empfohlen 4"
          min={1}
          max={16}
          step={1}
          value={cfg.cores}
          display={`${cfg.cores} Kerne`}
          onChange={(cores) => onChange({ cores })}
        />
        <Slider
          label="RAM"
          hint="8192 MB – darunter Reboot-Loop-Gefahr"
          min={2048}
          max={32768}
          step={1024}
          value={cfg.ram}
          display={`${cfg.ram} MB · ${(cfg.ram / 1024).toLocaleString('de-DE')} GB`}
          onChange={(ram) => onChange({ ram })}
        />
        <Slider
          label="Disk"
          hint="Thin-Pool beachten"
          min={10}
          max={128}
          step={1}
          value={cfg.disk}
          display={`${cfg.disk} GB`}
          onChange={(disk) => onChange({ disk })}
        />
        <Field label="CPU-Typ" hint="„host“ löst viele Boot-Hänger">
          <input type="text" value={cfg.cpuType} onChange={(e) => onChange({ cpuType: e.target.value })} />
        </Field>
      </div>

      <div className="form-group">
        <h3>Storage &amp; Netzwerk</h3>
        <div className="field-row">
          <Field label="Storage" hint="leer = Auto">
            <input
              type="text"
              list="storage-list"
              placeholder="local-lvm"
              value={cfg.storage}
              onChange={(e) => onChange({ storage: e.target.value })}
            />
            <datalist id="storage-list">
              <option value="local-lvm" />
              <option value="local-zfs" />
              <option value="local" />
            </datalist>
          </Field>
          <Field label="Bridge" hint="leer = vmbr0">
            <input
              type="text"
              list="bridge-list"
              placeholder="vmbr0"
              value={cfg.bridge}
              onChange={(e) => onChange({ bridge: e.target.value })}
            />
            <datalist id="bridge-list">
              <option value="vmbr0" />
              <option value="vmbr1" />
            </datalist>
          </Field>
        </div>
        <Segmented<Nic>
          label="NIC"
          hint="e1000 nur als Fallback"
          value={cfg.nic}
          options={[
            { value: 'virtio', label: 'virtio (Standard)' },
            { value: 'e1000', label: 'e1000 (Fallback)' },
          ]}
          onChange={(nic) => onChange({ nic })}
        />
      </div>

      <div className="form-group">
        <h3>Image &amp; Boot</h3>
        <Segmented
          label="Variante"
          hint="auto erkennt die CPU per lscpu"
          value={cfg.variant}
          options={[
            { value: 'auto', label: 'auto' },
            { value: 'apu', label: 'apu · AMD' },
            { value: 'iris', label: 'iris · Intel' },
            { value: 'slim', label: 'slim · Celeron' },
            { value: 'legacy', label: 'legacy · Core 3–5' },
          ]}
          onChange={(variant) => onChange({ variant })}
        />
        <Field label="Eigene Image-URL" hint="schlägt die Variante immer; file:/// für lokal">
          <input
            type="text"
            placeholder="https://… .bin.zip oder file:///var/tmp/…"
            value={cfg.imageUrl}
            onChange={(e) => onChange({ imageUrl: e.target.value })}
          />
        </Field>
        <div className="field-row">
          <Segmented<Bios>
            label="Firmware"
            value={cfg.bios}
            options={[
              { value: 'ovmf', label: 'OVMF (UEFI)' },
              { value: 'seabios', label: 'SeaBIOS' },
            ]}
            onChange={(bios) => onChange({ bios })}
          />
          <Segmented<BootDisk>
            label="Boot-Disk"
            value={cfg.bootDisk}
            options={[
              { value: 'sata', label: 'sata' },
              { value: 'virtio', label: 'virtio' },
              { value: 'scsi', label: 'scsi' },
            ]}
            onChange={(bootDisk) => onChange({ bootDisk })}
          />
        </div>
        <Segmented<Vga>
          label="Grafik"
          hint="none nur für GPU-Passthrough"
          value={cfg.vga}
          options={[
            { value: 'std', label: 'std' },
            { value: 'virtio', label: 'virtio' },
            { value: 'none', label: 'none' },
          ]}
          onChange={(vga) => onChange({ vga })}
        />
      </div>

      <div className="form-group">
        <h3>Modus &amp; Tweaks</h3>
        <div className="toggle-grid">
          <Toggle
            label="GRUB-/syslinux-Tweak"
            desc="nomodeset auf der ESP (QEMU hat keine Intel-GPU), Backup als *.orig"
            checked={cfg.grubTweak}
            onChange={(grubTweak) => onChange({ grubTweak })}
          />
          <Toggle
            label="Serielle Konsole"
            desc="Kernel-Log per „qm terminal VMID“ mitlesen"
            checked={cfg.serialConsole}
            onChange={(serialConsole) => onChange({ serialConsole })}
          />
          <Toggle
            label="Headless-Modus"
            desc="VGA=none + serielle Konsole – Zugriff per qm terminal / SSH"
            checked={cfg.headless}
            onChange={(headless) => onChange({ headless })}
          />
          <Toggle
            label="Dry-Run"
            desc="zeigt nur die qm-Befehle, ändert nichts"
            checked={cfg.dryRun}
            onChange={(dryRun) => onChange({ dryRun })}
          />
          <Toggle
            label="Unattended (--yes)"
            desc="keine Rückfragen am Terminal – Defaults/ENV/Flags gelten"
            checked={cfg.unattended}
            onChange={(unattended) => onChange({ unattended })}
          />
        </div>
      </div>

      <button type="button" className="btn-reset" onClick={() => onChange({ ...DEFAULTS })}>
        Zurücksetzen auf Defaults
      </button>
    </div>
  )
}
