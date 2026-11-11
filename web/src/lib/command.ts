import { DEFAULTS, ONE_LINER, type FygoConfig } from './config'

export type Level = 'error' | 'warn' | 'info'

export interface Hint {
  level: Level
  text: string
}

type EnvEntry = [key: string, value: string]

/** Nur nicht-Default-Werte – der generierte Befehl bleibt minimal. */
function envEntries(cfg: FygoConfig): EnvEntry[] {
  const pairs: EnvEntry[] = []
  const push = (key: string, value: string) => pairs.push([key, value])
  if (cfg.vmid.trim() !== '') push('VMID', cfg.vmid.trim())
  if (cfg.name !== DEFAULTS.name) push('NAME', cfg.name)
  if (cfg.cores !== DEFAULTS.cores) push('CORES', String(cfg.cores))
  if (cfg.ram !== DEFAULTS.ram) push('RAM', String(cfg.ram))
  if (cfg.disk !== DEFAULTS.disk) push('DISK', String(cfg.disk))
  if (cfg.storage !== '') push('STORAGE', cfg.storage)
  if (cfg.bridge !== '') push('BRIDGE', cfg.bridge)
  if (cfg.nic !== DEFAULTS.nic) push('NIC', cfg.nic)
  if (cfg.cpuType !== DEFAULTS.cpuType) push('CPU_TYPE', cfg.cpuType)
  if (cfg.variant !== DEFAULTS.variant) push('VARIANT', cfg.variant)
  if (cfg.bios !== DEFAULTS.bios) push('BIOS', cfg.bios)
  if (cfg.bootDisk !== DEFAULTS.bootDisk) push('BOOT_DISK', cfg.bootDisk)
  if (cfg.vga !== DEFAULTS.vga) push('VGA', cfg.vga)
  if (!cfg.grubTweak) push('GRUB_TWEAK', '0')
  if (cfg.serialConsole && !cfg.headless) push('SERIAL_CONSOLE', '1') // --headless erzwingt seriell eh
  if (cfg.headless) push('HEADLESS', '1')
  if (cfg.dryRun) push('DRY_RUN', '1')
  if (cfg.unattended) push('YES', '1')
  if (cfg.imageUrl.trim() !== '') push('IMAGE_URL', cfg.imageUrl.trim())
  return pairs
}

function quoteEnvValue(value: string): string {
  return /[\s"'\\$]/.test(value) ? `"${value.replace(/(["\\$])/g, '\\$1')}"` : value
}

/** Einzeiler-Stil: ENV-Zuweisungen + bash -c "$(wget ...)" – läuft direkt auf dem Host. */
export function buildEnvCommand(cfg: FygoConfig): string {
  const pairs = envEntries(cfg)
  if (pairs.length === 0) return ONE_LINER
  const lines = pairs.map(([k, v]) => `${k}=${quoteEnvValue(v)} \\`)
  lines.push(ONE_LINER)
  return lines.join('\n')
}

type FlagEntry = [flag: string, value?: string]

function flagEntries(cfg: FygoConfig): FlagEntry[] {
  const flags: FlagEntry[] = []
  const push = (flag: string, value?: string) => flags.push([flag, value])
  if (cfg.vmid.trim() !== '') push('--vmid', cfg.vmid.trim())
  if (cfg.name !== DEFAULTS.name) push('--name', cfg.name)
  if (cfg.cores !== DEFAULTS.cores) push('--cores', String(cfg.cores))
  if (cfg.ram !== DEFAULTS.ram) push('--memory', String(cfg.ram))
  if (cfg.disk !== DEFAULTS.disk) push('--disk', String(cfg.disk))
  if (cfg.storage !== '') push('--storage', cfg.storage)
  if (cfg.bridge !== '') push('--bridge', cfg.bridge)
  if (cfg.nic !== DEFAULTS.nic) push('--nic', cfg.nic)
  if (cfg.cpuType !== DEFAULTS.cpuType) push('--cpu', cfg.cpuType)
  if (cfg.variant !== DEFAULTS.variant) push('--variant', cfg.variant)
  if (cfg.bios !== DEFAULTS.bios) push('--bios', cfg.bios)
  if (cfg.bootDisk !== DEFAULTS.bootDisk) push('--boot-disk', cfg.bootDisk)
  if (cfg.vga !== DEFAULTS.vga) push('--vga', cfg.vga)
  if (!cfg.grubTweak) push('--no-grub-tweak')
  if (cfg.serialConsole && !cfg.headless) push('--serial-console') // --headless erzwingt seriell eh
  if (cfg.headless) push('--headless')
  if (cfg.dryRun) push('--dry-run')
  if (cfg.unattended) push('--yes')
  if (cfg.imageUrl.trim() !== '') push('--image-url', cfg.imageUrl.trim())
  return flags
}

function quoteFlagValue(value: string): string {
  return /[\s"'\\$]/.test(value) ? `"${value.replace(/(["\\$])/g, '\\$1')}"` : value
}

/** Lokaler Stil: Repo geklont, bash fygoos.sh mit Flags. */
export function buildFlagCommand(cfg: FygoConfig): string {
  const flags = flagEntries(cfg)
  if (flags.length === 0) return 'bash fygoos.sh'
  const lines: string[] = []
  flags.forEach(([flag, value], i) => {
    const last = i === flags.length - 1
    const continuation = last ? '' : ' \\'
    lines.push(value === undefined ? `${flag}${continuation}` : `${flag} ${quoteFlagValue(value)}${continuation}`)
  })
  return `bash fygoos.sh \\\n  ${lines.join('\n  ')}`
}

/** Dieselben Prüfwarnungen, die das Script selbst ausgibt – nur vorab im Browser. */
export function computeHints(cfg: FygoConfig): Hint[] {
  const hints: Hint[] = []
  const add = (level: Level, text: string) => hints.push({ level, text })

  if (cfg.variant === 'legacy' && cfg.imageUrl.trim() === '') {
    add(
      'error',
      'Variante „legacy“ hat keinen Direktlink: .bin.zip manuell laden, per scp nach /var/tmp kopieren und IMAGE_URL=file:///var/tmp/<datei>.bin.zip setzen.',
    )
  }
  if (cfg.ram < 8192) {
    add(
      'warn',
      `RAM ${cfg.ram} MB: 2 GB führen laut Forum zu Reboot-Loops, 4096 teils zu Hängern – nimm mindestens 8192.`,
    )
  }
  if (cfg.disk < 20) {
    add('warn', `Disk ${cfg.disk} GB: das Image ist ~7 GB entpackt, Updates brauchen Luft – nimm mindestens 20.`)
  }
  if (cfg.cores < 2) {
    add('warn', `${cfg.cores} vCPU: FydeOS ist ein Desktop-OS – nimm mindestens 2 Kerne (empfohlen 4, Typ host).`)
  }
  if (cfg.cpuType !== DEFAULTS.cpuType) {
    add('warn', `CPU-Typ „${cfg.cpuType}“: Forum empfiehlt „host“ gegen Boot-Hänger.`)
  }
  if (cfg.bios === 'seabios') {
    add('warn', 'SeaBIOS ist ein Experiment: der GPT-Schutz-MBR enthält meist keinen Bootcode – OVMF bleibt der verlässliche Weg.')
  }
  if (cfg.nic === 'e1000') {
    add('info', 'e1000 ist der Fallback, falls virtio kein Netz bekommt (langsamer).')
  }
  if (cfg.bootDisk !== 'sata') {
    add('info', 'sata ist der Forum-bewährte Boot-Pfad – OVMF sieht nicht jeden Controller als Boot-Device.')
  }
  if (cfg.vga === 'none' && !cfg.headless) {
    add('info', 'VGA=none: noVNC bleibt schwarz – gedacht für GPU-Passthrough (qm set VMID --hostpci0 <PCI>,pcie=1).')
  }
  if (cfg.headless) {
    add('info', 'Headless: noVNC bleibt schwarz (normal!). Zugriff per „qm terminal VMID“ bzw. SSH, sobald sshd läuft.')
  } else if (cfg.serialConsole) {
    add('info', 'Kernel-Log live mitlesen: qm terminal VMID (beenden mit Strg+O).')
  }
  if (cfg.dryRun) {
    add('info', 'Dry-Run: es wird nichts geändert, nur die qm-Befehle werden gezeigt.')
  }
  if (cfg.variant === 'auto') {
    add('info', 'auto erkennt die CPU per lscpu: AMD → apu, Celeron/Pentium → slim, sonst Intel → iris.')
  }
  if (cfg.imageUrl.trim() !== '') {
    add('info', 'Eigene Image-URL schlägt die Variante immer.')
  }
  if (cfg.vmid.trim() !== '') {
    add('info', `VMID ${cfg.vmid.trim()}: muss frei sein – sonst weicht das Script automatisch auf die nächste freie ID aus.`)
  }
  if (cfg.storage === '') {
    add('info', 'Storage: Auto-Erkennung (local-lvm > local-zfs > local > erstbeste).')
  }
  if (cfg.bridge === '') {
    add('info', 'Bridge: Auto-Erkennung (vmbr0, sonst erste vmbr*).')
  }
  return hints
}
