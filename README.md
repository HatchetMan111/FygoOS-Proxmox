# FygoOS auf Proxmox – Einzeiler-Installation (Community-Scripts-Stil, VM)

> Upstream: `https://fygonas.com/open-source` (FygoOS, ehem. FydeOS – nur Kernel-Source publiziert) + Images von `https://fydeos.io/download/` bzw. `https://fygonas.com/download`.
> Dieses Repo enthält **nur den Proxmox-Installer** (`install/fygoos.sh`). Die Methode folgt dem Forum-Thread `https://forum.proxmox.com/threads/install-fydeos-in-proxmox-ve.149345/` (Post #10, justinclift): `.img.xz` laden → `xz -d` → `qm disk import` → als SATA einhängen.
> Läuft vollständig lokal, keine Cloud nötig.

## Einzeiler (auf dem Proxmox-Host als root)

```bash
bash -c "$(wget -qLO - https://raw.githubusercontent.com/HatchetMan111/FygoOS-Proxmox/main/install/fygoos.sh)"
```

Anpassungen (VMID immer **nächste freie**, außer gesetzt):

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
| Image | FydeOS-for-PC, per `VARIANT` gewählt: `auto` (Default, `lscpu`: AMD→`apu`, Intel→`iris`), `apu` (AMD-Grafik), `iris` (Intel 6.-14. Gen), `legacy` (nur mit eigener `--image-url`) – eigene URL schlägt die Variante immer |
| Image-Format | v18 `.img.xz` (Direkt-Link, `xz -d`) oder v20+ `.bin.zip` (per `unzip`, z. B. eigene URL) – **kein** `.ova` (nur VMware, bootet unter KVM meist nicht) |
| Standard-Ressourcen | 4 vCPU (Typ `host`) / 8192 MB RAM / 32 GB Disk (RAM bewusst hoch: 2 GB = Reboot-Loop, 4096 teils Hänger) |
| NIC | `virtio` (Default), Fallback `--nic e1000` falls die VM kein Netz bekommt |
| VMID | immer die **nächste freie ID** (`pvesh get /cluster/nextid`), außer `--vmid` gesetzt |
| BIOS / Disk | UEFI (`ovmf` + efidisk), Bootdisk `sata0`, `onboot: 1` (reboot-sicher) |

Das Skript (`set -euo pipefail`, `trap ERR` mit Befehl+Zeile+Exit-Code):
1. prüft root/`qm`/`pvesh`/`pvesm`/`xz`, nimmt die nächste freie VMID, erkennt Storage (`local-lvm` > `local-zfs` > `local`) und Bridge (`vmbr0`),
2. erstellt die VM (`ostype l26`, `cpu host`, UEFI, VirtIO-Net, `vga std`, Guest-Agent aus),
3. lädt das `.img.xz` nach `/var/tmp/fygoos-install`, prüft mit `xz -t`, entpackt, importiert per `qm disk import` und hängt als `sata0` mit `boot order=sata0` ein,
4. verifiziert `qm config` (sata0 + onboot) und `qm status` (running) und gibt Start-/Stopp-/Konsolen-Hinweise aus.

Erwartete Schlussausgabe (Beispiel):

```text
[OK] Bootdisk sata0 vorhanden.
[OK] onboot gesetzt (reboot-sicher).
[OK] VM läuft (qm status = running).

════════════════ FYGOOS VM ERSTELLT ════════════════
  VM       : 100 (fygoos) – 4 vCPU (host) / 4096 MB / 32G
  Storage  : local-lvm (sata0, Boot order=sata0, BIOS=ovmf, onboot=1)
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
