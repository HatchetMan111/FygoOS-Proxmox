export type Variant = 'auto' | 'apu' | 'iris' | 'slim' | 'legacy'
export type Nic = 'virtio' | 'e1000'
export type Bios = 'ovmf' | 'seabios'
export type BootDisk = 'sata' | 'virtio' | 'scsi'
export type Vga = 'std' | 'virtio' | 'none'

/** Spiegelt die Defaults aus install/fygoos.sh – Änderungen immer doppelt pflegen. */
export interface FygoConfig {
  vmid: string
  name: string
  cores: number
  ram: number // MB
  disk: number // GB
  storage: string // '' = Auto-Erkennung
  bridge: string // '' = Auto-Erkennung
  nic: Nic
  cpuType: string
  variant: Variant
  bios: Bios
  bootDisk: BootDisk
  vga: Vga
  grubTweak: boolean
  serialConsole: boolean
  headless: boolean
  dryRun: boolean
  unattended: boolean
  imageUrl: string
}

export const DEFAULTS: FygoConfig = {
  vmid: '',
  name: 'fygoos',
  cores: 4,
  ram: 8192,
  disk: 32,
  storage: '',
  bridge: '',
  nic: 'virtio',
  cpuType: 'host',
  variant: 'auto',
  bios: 'ovmf',
  bootDisk: 'sata',
  vga: 'std',
  grubTweak: true,
  serialConsole: false,
  headless: false,
  dryRun: false,
  unattended: false,
  imageUrl: '',
}

export const ONE_LINER =
  'bash -c "$(wget -qLO - https://raw.githubusercontent.com/HatchetMan111/FygoOS-Proxmox/main/install/fygoos.sh)"'

export interface VariantInfo {
  key: Variant
  label: string
  cpu: string
  gpu: string
  note: string
}

export const VARIANTS: VariantInfo[] = [
  {
    key: 'auto',
    label: 'auto',
    cpu: 'jede CPU',
    gpu: 'automatisch',
    note: 'Erkennt per lscpu: AMD → apu, Celeron/Pentium → slim, sonst Intel → iris. Standard-Empfehlung.',
  },
  {
    key: 'apu',
    label: 'apu',
    cpu: 'AMD ab ~2011 oder Intel + AMD-GPU',
    gpu: 'AMD-Grafik',
    note: 'v23-Direktlink, SHA-256-Prüfung aktiv.',
  },
  {
    key: 'iris',
    label: 'iris',
    cpu: 'Intel Core 6.–14. Gen',
    gpu: 'HD/UHD/Xe',
    note: 'v23-Direktlink, SHA-256-Prüfung aktiv.',
  },
  {
    key: 'slim',
    label: 'slim',
    cpu: 'Intel Celeron/Pentium ~2015–2019 (z. B. J4105)',
    gpu: 'UHD 600',
    note: 'v23-Direktlink, SHA-256-Prüfung aktiv.',
  },
  {
    key: 'legacy',
    label: 'legacy',
    cpu: 'Intel Core 3.–5. Gen',
    gpu: 'HD 2500–5500',
    note: 'Kein Direktlink: .bin.zip manuell laden, per scp nach /var/tmp, dann IMAGE_URL=file:///var/tmp/<datei>.bin.zip.',
  },
]
