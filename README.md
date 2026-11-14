# FygoOS auf Proxmox – Einzeiler-Installation (Community-Scripts-Stil, VM)

> Upstream: `https://fygonas.com/open-source` (FygoOS, ehem. FydeOS – nur Kernel-Source publiziert) + Images von `https://fydeos.io/download/` bzw. `https://fygonas.com/download`.
> Dieses Repo enthält **nur den Proxmox-Installer** (`install/fygoos.sh`). Die Methode folgt dem Forum-Thread `https://forum.proxmox.com/threads/install-fydeos-in-proxmox-ve.149345/` (Post #10, justinclift): `.img.xz` laden → `xz -d` → `qm disk import` → als SATA einhängen.
> Läuft vollständig lokal, keine Cloud nötig.

## Web-UI: Installer-Konfigurator

Wer nicht am Terminal tippt: Der [interaktive Konfigurator](https://hatchetman111.github.io/FygoOS-Proxmox/) baut den Befehl live – alle Flags und Varianten, plus die Warnungen des Scripts (RAM/Disk/legacy/SeaBIOS) als Vorschau, mit ENV-Einzeiler- und Flags-Stil zum Kopieren.

Lokal entwickeln:

```bash
cd web && npm install && npm run dev   # Dev-Server
npm run build                          # Produktions-Build nach web/dist
```

Deployment: automatisch per GitHub Actions (`.github/workflows/pages.yml`) auf GitHub Pages.

## Einzeiler (auf dem Proxmox-Host als root)

```bash
bash -c "$(wget -qLO - https://raw.githubusercontent.com/HatchetMan111/FygoOS-Proxmox/main/install/fygoos.sh)"
```

Anpassungen (VMID immer **nächste freie**, außer gesetzt):

```bash
bash fygoos.sh --yes   # keine Rückfragen (unattended, Defaults/ENV/Flags)
```

Ohne `--yes` fragt das Script am Terminal alles ab (Community-Scripts-Stil, Enter = Default): VMID, Name, vCPU, **RAM**, **Disk**, Storage, Bridge, Variante, NIC — vorher zeigt es die **Thin-Pool-Füllstände** (`Data% über ~85% = kritisch`, Lehre aus einem vollgelaufenen `pve/data`) und den Bedarf (`${DISK} GB Thin-Volume + ~8 GB Download-Cache). Mit `n` bei „Installieren?" brichst du ohne Änderung ab. Ohne TTY (z. B. Curie-Pipe) läuft es automatisch mit Defaults weiter.

```bash
VMID=200 CORES=4 RAM=8192 DISK=64 IMAGE_URL=https://download.fydeos.io/<aktuelles>-img.xz bash -c "$(wget -qLO - https://raw.githubusercontent.com/HatchetMan111/FygoOS-Proxmox/main/install/fygoos.sh)"
bash fygoos.sh --vmid 200 --cores 4 --memory 8192 --disk 64 --storage local-lvm --bridge vmbr0 --image-url https://...
bash fygoos.sh --dry-run   # ändert nichts, zeigt nur qm-Befehle
bash fygoos.sh --debug     # = bash -x, komplette Fehlermeldungskette + Log unter /tmp/fygoos-install-*.log
bash fygoos.sh --no-start  # nur anlegen, nicht starten
```

| Eigenschaft | Wert |
|---|---|
| VM-Name | `fygoos` |
| Zweck | FygoOS/FydeOS als Desktop-VM (ChromeOS-artig, inkl. Android-/Linux-Support) |
| Image | FydeOS-for-PC **v23** per `VARIANT`: `auto` (Default, `lscpu`: AMD→`apu`, Celeron/Pentium→`slim`, sonst Intel→`iris`), dazu SHA-256-Prüfung nach Download. `legacy` nur mit eigener `--image-url` (`.bin.zip` manuell laden, per `scp` nach `/var/tmp`, dann `IMAGE_URL=file:///var/tmp/<datei>.bin.zip`) – eigene URL schlägt die Variante immer |
| Image-Format | v23 `.bin.zip` (per `unzip`, inkl. SHA-256-Prüfung); eigene `.img.xz`-URL entpackt per `xz -d` – **kein** `.ova` (nur VMware, bootet unter KVM meist nicht) |
| Standard-Ressourcen | 4 vCPU (Typ `host`) / 8192 MB RAM / 32 GB Disk (RAM bewusst hoch: 2 GB = Reboot-Loop, 4096 teils Hänger) |
| NIC | `virtio` (Default), Fallback `--nic e1000` falls die VM kein Netz bekommt |
| VMID | immer die **nächste freie ID** (`pvesh get /cluster/nextid`), außer `--vmid` gesetzt |
| BIOS / Disk | UEFI (`ovmf` + efidisk **ohne** Secure-Boot-Keys: `pre-enrolled-keys=0`, FydeOS-GRUB ist unsigniert), Bootdisk `sata0`, `onboot: 1` (reboot-sicher) |

Das Skript (`set -euo pipefail`, `trap ERR` mit Befehl+Zeile+Exit-Code):
1. prüft root/`qm`/`pvesh`/`pvesm`/`xz`, nimmt die nächste freie VMID, erkennt Storage (`local-lvm` > `local-zfs` > `local`) und Bridge (`vmbr0`),
2. löst die Variante auf (`auto` per `lscpu`: AMD→`apu`, Intel→`iris`; eigene `--image-url` gewinnt immer) und prüft die URL per Preflight **vor** `qm create`,
3. erstellt die VM (`ostype l26`, `cpu host`, UEFI+efidisk, VirtIO-Net, `vga std`, Guest-Agent aus, `onboot: 1`),
4. lädt das Image (`.img.xz` per `xz -d`, `.bin.zip` per `unzip`), importiert per `qm disk import`, hängt als `sata0` mit `boot order=sata0` ein, erweitert auf Zielgröße,
5. **GRUB-/syslinux-Tweak** (Default an, `--no-grub-tweak` zum Abschalten): mappt die ESP per `kpartx`, sichert `grub.cfg` + `syslinux/*.cfg` (`*.orig`) und ersetzt `i915.modeset=1` durch `i915.modeset=0 nomodeset` (QEMU hat keine Intel-GPU; dm-verity bleibt unangetastet – der syslinux-Teil ist der SeaBIOS-Bootpfad) – best-effort, bricht die Installation bei Fehlern nicht ab. Fehlendes `kpartx` (multipath-tools) wird vor der VM-Erstellung automatisch nachinstalliert, damit der Tweak nie still übersprungen wird,
6. verifiziert `qm config` (Bootdisk + onboot) und `qm status` (running), sucht bis 90 s per ARP die DHCP-IP, liest mit **Boot-Watch** 60 s Kernel-Log seriell ein und wertet es aus (nur mit `SERIAL_CONSOLE=1`) – bekannte Fehlermuster bekommen die Fix-Befehle direkt ins Terminal gedruckt.

## Kernel hängt? Serial-Console-Debug

```bash
bash fygoos.sh --serial-console   # oder SERIAL_CONSOLE=1 ...
qm terminal <VMID>                # Kernel-Log live (Beenden: Ctrl+O)
# nicht-interaktiv mitschneiden:
timeout 60 socat - UNIX-CONNECT:/var/run/qemu-server/<VMID>.serial
```

Das hängt `console=tty0 console=ttyS0,115200n8` an alle syslinux-`append`-Zeilen **und** die Kernel-Zeilen in `grub.cfg` (idempotent: kein Doppel-Eintrag) und legt `serial0` an – das Kernel-Log erscheint dadurch **parallel im noVNC und per `qm terminal`** (nur ttyS0 allein würde noVNC schwarz lassen und wie ein Hänger wirken). Direkt nach dem Start liest ein **Boot-Watch** 60 s Kernel-Log und wertet es aus: bei `Waiting for root device`, Kernel-Panic oder stummer Konsole stehen die passenden Fix-Befehle sofort im Terminal.

## Bestehende VM prüfen: --doctor

```bash
bash fygoos.sh --doctor --vmid 109          # nur prüfen, Fix-Befehle werden ausgegeben
bash fygoos.sh --doctor --vmid 109 --fix    # prüfen + automatisch beheben (RAM, serial0, ESP-Patches)
```

Der Doctor prüft `memory` (Fix: 8192), `efidisk0`-Secure-Boot-Keys, `serial0`, ob `nomodeset` **wirklich** in der `grub.cfg` steht (Fix: nachtragen), ob die Console-Doppelbelegung (tty0+ttyS0) sitzt (Fix: ergänzen), liest 45 s Kernel-Log von der seriellen Konsole und sagt bei `Waiting for root device` / Panic / stummer Konsole exakt, welcher Befehl als Nächstes hilft – fertig zum Kopieren, mit echter VMID und Disk-ID. Kein Neuinstallations-Zwang mehr.

## Headless Server-Modus (ohne Desktop)

```bash
bash fygoos.sh --headless   # oder HEADLESS=1 ... (auch in den Prompts als Frage)
```

Setzt `VGA=none` + `SERIAL_CONSOLE=1`: kein noVNC-Bild (bleibt schwarz — normal!), Zugriff per `qm terminal <VMID>`, SSH sobald Netz oben und `sshd` läuft. Hinweis: FygoOS kennt offiziell keinen Server-Modus — das ist Desktop-OS ohne Grafikkarte. Ob `sshd` läuft und welche Zugangsdaten gelten, zeigt der erste Boot per `qm terminal`.

## Neu installieren / Variante wechseln (ohne Altlasten)

```bash
qm stop <ID> && qm destroy <ID> --purge   # alte VM weg (spart Thin-Pool-Platz)
VARIANT=auto NIC=e1000 VGA=virtio BIOS=seabios bash -c "$(wget -qLO - https://raw.githubusercontent.com/HatchetMan111/FygoOS-Proxmox/main/install/fygoos.sh)"
# VARIANT: auto (Default, lscpu: AMD→apu, Celeron/Pentium→slim, Intel→iris) | apu | iris | slim | legacy
#          slim/legacy haben keinen Direkt-Link → .bin.zip manuell laden, scp nach /var/tmp,
#          dann IMAGE_URL=file:///var/tmp/<datei>.bin.zip ...
# GRUB-Tweak abschalten: GRUB_TWEAK=0 ...  bzw.  bash fygoos.sh --no-grub-tweak
# Weitere Wege: --boot-disk sata|virtio|scsi, --bios ovmf|seabios, --serial-console (Kernel-Log)
```

Erwartete Schlussausgabe (Beispiel):

```text
[OK] Bootdisk sata0 vorhanden.
[OK] onboot gesetzt (reboot-sicher).
[OK] VM läuft (qm status = running).

════════════════ FYGOOS VM ERSTELLT ════════════════
  VM       : 100 (fygoos) – 4 vCPU (host) / 8192 MB / 32G
  Storage  : local-lvm (Bootdisk + Boot-Order je nach --boot-disk, BIOS je nach --bios, onboot=1)
  Starten  : qm start 100     Stoppen: qm stop 100     Konfig: qm config 100
  Konsole  : Proxmox-WebUI -> VM 100 -> Konsole (noVNC). Erster Boot dauert Minuten.
  ...
```

## Wichtig: Grafik / Boot hängt (bekannt aus dem Forum)

FydeOS supportet offiziell nur VMware; unter Proxmox bleibt der Boot oft beim Grafik-Init hängen (2 GB → Reboot-Loop, viel RAM → teils Stillstand). Bewährt:

```bash
qm set 100 --cpu host          # falls nicht schon host
qm set 100 --memory 8192       # mehr RAM
qm set 100 --vga none          # internes VGA aus + echte GPU per PCI-Passthrough (Forum: RX550 ok)
```

## Reboot-Test (Reboot-sicher belegen)

```bash
VM=100
qm reboot $VM
sleep 90
qm status $VM   # erwartet: status: running
```

## Update / Deinstall

```bash
bash fygoos.sh --vmid 100 --image-url https://.../neues.img.xz   # Update: neue VM aus neuem Image (In-Place-Upgrade gibt es nicht)
qm stop 100 && qm destroy 100 --purge                            # Deinstall
```

## Debugging

- Jeder Fehler gibt Befehl + Zeile + Exit-Code aus, Voll-Log unter `/tmp/fygoos-install-*.log`.
- `bash fygoos.sh --debug` für `bash -x`-Trace.
- Häufig: falsche Image-Variante (apu vs intel), SeaBIOS statt OVMF, `cpu: kvm64` statt `host`, zu wenig RAM.

## Dateien

- `install/fygoos.sh` – Proxmox-Einzeiler (Host, root).
- `web/` – React+Vite-Installer-Konfigurator (GitHub Pages, deploy per Workflow).
- `.github/workflows/pages.yml` – baut `web/` und deployt nach GitHub Pages.
