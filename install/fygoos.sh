#!/usr/bin/env bash
# FygoOS (ehem. FydeOS) als VM auf Proxmox VE – Einzeiler im Community-Scripts-Stil.
# Getestete Methode aus https://forum.proxmox.com/threads/install-fydeos-in-proxmox-ve.149345/
# (Download .img.xz -> xz -d -> qm disk import -> als SATA einhängen).
#
# Gebrauch (auf dem Proxmox-Host als root):
#   bash -c "$(wget -qLO - https://raw.githubusercontent.com/HatchetMan111/FygoOS-Proxmox/main/install/fygoos.sh)"
#   VMID=200 CORES=4 RAM=8192 DISK=32 bash -c "$(wget -qLO - https://raw.githubusercontent.com/HatchetMan111/FygoOS-Proxmox/main/install/fygoos.sh)"
#   bash fygoos.sh --variant iris --vmid 200 --cores 4 --memory 8192 --disk 32 --storage local-lvm --bridge vmbr0 --nic e1000
#   bash fygoos.sh --boot-disk virtio --bios seabios   # alternativen Boot-Pfad testen
#   bash fygoos.sh --image-url https://.../eigenes.img.xz   # eigene URL schlägt --variant immer
#   VARIANT=apu bash fygoos.sh                             # auto erkennt sonst per lscpu (AMD->apu, Intel->iris)
#   bash fygoos.sh --dry-run        # zeigt nur qm-Befehle, ändert nichts
#   bash fygoos.sh --yes            # keine Rückfragen (unattended, Defaults/ENV/Flags)
#   Bei TTY fragt das Script sonst zu Beginn ab (VMID, Name, Kerne, RAM, Disk,
#   Storage, Bridge, Variante, NIC – Community-Scripts-Stil, Enter = Default).
#   bash fygoos.sh --debug          # = bash -x, komplette Fehlermeldungskette + Log unter /tmp/fygoos-install-*.log
#   bash fygoos.sh --manual         # = --no-start: nur VM hinstellen, Start + Konsole manuell
#   bash fygoos.sh --serial-console # Kernel-Log auf seriell (Debug per "qm terminal VMID")
#   bash fygoos.sh --headless       # Server-Modus: VGA=none + serielle Konsole (Zugriff qm terminal/SSH)
#   bash fygoos.sh --no-grub-tweak  # ESP/grub.cfg unverändert lassen (Default: nomodeset-Tweak aktiv)
#
# Warum VM statt LXC: FygoOS ist ein vollständiges ChromeOS-artiges Desktop-OS
# (eigener Kernel, Android-/Linux-Container). Das läuft nicht in einem LXC.
#
# Bekannte Einschränkung (ehrlich, aus dem Forum):
#   FydeOS/FygoOS supportet offiziell nur VMware (.ova) bzw. Bare-Metal-PC-Images.
#   Unter KVM/QEMU bleibt der Boot häufig beim Grafik-Init hängen (mit 2 GB rebootet
#   die VM, mit viel RAM bleibt sie teils stehen). Bewährt: CPU-Typ "host", UEFI/OVMF,
#   viel RAM – und falls der Bildschirm schwarz bleibt: --vga none + physische GPU
#   per PCI-Passthrough (im Forum: RX550). Dieses Script automatisiert den bewährten
#   Pfad, kann fehlenden GPU-Support aber nicht wegzaubern.
set -euo pipefail

# ---------------- Variablen (oben, per ENV oder Flag übersteuerbar) ----------------
VMID="${VMID:-}"                       # leer = nächste freie ID via pvesh get /cluster/nextid
NAME="${NAME:-fygoos}"
CORES="${CORES:-4}"
RAM="${RAM:-8192}"                     # MB; Forum: 2 GB = Reboot-Loop, 4096 teils Hänger -> Default 8192
DISK="${DISK:-32}"                     # GB, Zielgröße nach qm resize
STORAGE="${STORAGE:-}"                 # leer = Auto-Erkennung (local-lvm > local-zfs > local > erstbeste)
BRIDGE="${BRIDGE:-}"                   # leer = vmbr0 falls vorhanden, sonst erste vmbr*
NIC="${NIC:-virtio}"                   # virtio (Default) oder e1000 (Fallback falls FygoOS kein Netz bekommt)
# Welche FydeOS-for-PC-Variante (Host-CPU/GPU passend wählen!):
#   auto   = per lscpu erkennen (AMD -> apu, Celeron/Pentium -> slim, sonst Intel -> iris)
#   apu    = AMD-Grafik (AMD- oder Intel-CPU ab ~2011 + AMD-GPU) – Direkt-Link v18
#   iris   = Intel Modern (Intel Core 6.-14. Gen mit HD/UHD/Xe) – Direkt-Link v18
#   slim   = Intel Slim (Celeron/Pentium ca. 2015-2019, z. B. J4105) – Direkt-Download
#            per Google-Drive-ID (usercontent-Link, ohne Cookies), inkl. SHA-256-Prüfung
#   legacy = Intel Legacy (Core 3.-5. Gen, supportet FydeOS nicht mehr) – KEIN Direkt-Link:
#            .bin.zip manuell laden, per scp nach /var/tmp kopieren und per
#            --image-url file:///var/tmp/<datei>.bin.zip übergeben.
# Eigene URL schlägt die Tabelle immer: --image-url <URL> oder IMAGE_URL=<URL>.
# Aktuelle Releases (v20+) sind .bin.zip via Drive/iCloud (nicht direkt ladbar) –
# dafür eine .bin.zip-URL übergeben (wird per unzip entpackt) oder v18-.img.xz nehmen.
VARIANT="${VARIANT:-auto}"
IMAGE_URL="${IMAGE_URL:-}"
CPU_TYPE="${CPU_TYPE:-host}"           # Forum: "host" löst viele Boot-Hänger
BIOS="${BIOS:-ovmf}"                   # ovmf (UEFI, Standard) oder seabios (Experiment: protective MBR hat meist keinen Bootcode -> Erwartung niedrig)
BOOT_DISK="${BOOT_DISK:-sata}"         # sata (Forum-bewährt) | virtio | scsi – OVMF sieht nicht jeden Controller als Boot-Device
VGA="${VGA:-std}"                      # Falls schwarz: hinterher "qm set VMID --vga none" + GPU-Passthrough
GRUB_TWEAK="${GRUB_TWEAK:-1}"          # 1 = i915.modeset=1 -> "i915.modeset=0 nomodeset" in ESP/grub.cfg (QEMU hat keine Intel-GPU; dm-verity bleibt unangetastet). 0 = ESP unverändert lassen.
SERIAL_CONSOLE="${SERIAL_CONSOLE:-0}"  # 1 = Kernel-Log auf serielle Konsole (syslinux: console=ttyS0,115200n8 + qm serial0) – Debug per "qm terminal VMID". Standard aus.
HEADLESS="${HEADLESS:-0}"              # 1 = Server-Modus ohne Desktop: VGA=none + SERIAL_CONSOLE=1 (Zugriff per "qm terminal VMID" bzw. SSH). Kein noVNC-Bild!
START="${START:-1}"                    # 1 = VM nach Erstellung starten, 0 = nur anlegen
DRY_RUN="${DRY_RUN:-0}"                # 1 = nur Befehle zeigen
YES="${YES:-0}"                        # 1 = keine Rückfragen (unattended). Default: bei TTY interaktiv abfragen
LOG="/tmp/fygoos-install-$(date +%Y%m%d-%H%M%S).log"
TMPDIR_WORK="/var/tmp/fygoos-install"

log()  { echo "[*] $*" | tee -a "$LOG"; }
ok()   { echo "[OK] $*" | tee -a "$LOG"; }
warn() { echo "[!!] $*" | tee -a "$LOG" >&2; }
die()  {
  local code=$?
  echo "[XX] FEHLER (exit=$code) in Befehl: '${BASH_COMMAND}' (Zeile ${BASH_LINENO[0]:-?})" | tee -a "$LOG" >&2
  echo "[XX] Hinweis: Bei Befehlen mit '| tee' nennt die Zeile ggf. das letzte Kettenglied – entscheidend ist die Fehlermeldung direkt darüber." | tee -a "$LOG" >&2
  echo "[XX] $*" | tee -a "$LOG" >&2
  echo "[XX] Voll-Log: $LOG" | tee -a "$LOG" >&2
  echo "[XX] Tipp: DEBUG=1 bash fygoos.sh ...  (oder --debug) für bash -x Trace" | tee -a "$LOG" >&2
  exit "${code:-1}"
}
trap 'die "Abbruch."' ERR

usage() { sed -n '2,30p' "$0"; }

while [ $# -gt 0 ]; do
  case "$1" in
    --vmid) VMID="$2"; shift 2;;
    --name) NAME="$2"; shift 2;;
    --cores) CORES="$2"; shift 2;;
    --memory|--ram) RAM="$2"; shift 2;;
    --disk) DISK="$2"; shift 2;;
    --storage) STORAGE="$2"; shift 2;;
    --bridge) BRIDGE="$2"; shift 2;;
    --nic) NIC="$2"; shift 2;;
    --variant) VARIANT="$2"; shift 2;;
    --bios) BIOS="$2"; shift 2;;
    --boot-disk) BOOT_DISK="$2"; shift 2;;
    --image-url) IMAGE_URL="$2"; shift 2;;
    --cpu) CPU_TYPE="$2"; shift 2;;
    --vga) VGA="$2"; shift 2;;
    --grub-tweak) GRUB_TWEAK="1"; shift;;
    --no-grub-tweak) GRUB_TWEAK="0"; shift;;
    --serial-console) SERIAL_CONSOLE="1"; shift;;
    --headless) HEADLESS="1"; shift;;
    --no-start|--manual) START="0"; shift;;   # nur VM hinstellen, Start + Konsole manuell (wie PBS --manual)
    --dry-run) DRY_RUN="1"; shift;;
    --yes|-y) YES="1"; shift;;
    --debug) DEBUG="1"; set -x; shift;;
    -h|--help) usage; exit 0;;
    *) echo "[XX] Unbekanntes Flag: $1 (siehe --help)" >&2; exit 2;;
  esac
done

if [ "${DEBUG:-0}" = "1" ]; then set -x; fi

[ "$(id -u)" = "0" ] || { echo "[XX] Bitte als root auf dem Proxmox-Host ausführen." >&2; exit 1; }
command -v qm >/dev/null || { echo "[XX] 'qm' nicht gefunden – kein Proxmox-Host?" >&2; exit 1; }
command -v pvesh >/dev/null || { echo "[XX] 'pvesh' nicht gefunden – kein Proxmox-Host?" >&2; exit 1; }
command -v pvesm >/dev/null || { echo "[XX] 'pvesm' nicht gefunden." >&2; exit 1; }
command -v curl >/dev/null || command -v wget >/dev/null || { echo "[XX] curl oder wget erforderlich." >&2; exit 1; }
command -v xz >/dev/null || { echo "[XX] 'xz' erforderlich (apt install xz-utils)." >&2; exit 1; }

# ---------- nächste freie VMID (Default; Kollision wird nach den Prompts geprüft) ----------
ensure_vmid_free() {
  if qm status "$VMID" >/dev/null 2>&1 || [ -e "/etc/pve/qemu-server/${VMID}.conf" ]; then
    FREE_ID="$(pvesh get /cluster/nextid 2>>"$LOG" || true)"
    if [ -n "${FREE_ID:-}" ] && [ "$FREE_ID" != "$VMID" ]; then
      warn "VMID $VMID belegt – weiche auf freie ID $FREE_ID aus."
      VMID="$FREE_ID"
    else
      for cand in $(seq 100 999); do
        if ! qm status "$cand" >/dev/null 2>&1 && [ ! -e "/etc/pve/qemu-server/${cand}.conf" ]; then
          warn "VMID $VMID belegt – weiche auf freie ID $cand aus (Scan)."
          VMID="$cand"
          break
        fi
      done
    fi
  fi
  if qm status "$VMID" >/dev/null 2>&1 || [ -e "/etc/pve/qemu-server/${VMID}.conf" ]; then
    echo "[XX] VMID $VMID ist belegt und keine freie ID gefunden – bitte --vmid <frei> setzen." >&2
    exit 1
  fi
  if [ -e "/etc/pve/qemu-server/${VMID}.conf" ]; then
    echo "[XX] /etc/pve/qemu-server/${VMID}.conf existiert bereits – breche ab (idempotent, nichts überschrieben)." >&2
    exit 1
  fi
}
resolve_boot_dev() {
  case "$BOOT_DISK" in
    sata) BOOT_DEV="sata0";;
    virtio) BOOT_DEV="virtio0";;
    scsi) BOOT_DEV="scsi0";;
  esac
}
if [ -z "$VMID" ]; then
  if VMID="$(pvesh get /cluster/nextid 2>>"$LOG")"; then
    log "VMID (nächste freie): $VMID"
  else
    warn "pvesh nextid fehlgeschlagen – scanne 100..999."
    VMID=""
    for cand in $(seq 100 999); do
      if ! qm status "$cand" >/dev/null 2>&1 && [ ! -e "/etc/pve/qemu-server/${cand}.conf" ]; then
        VMID="$cand"; break
      fi
    done
    [ -n "$VMID" ] || { echo "[XX] Keine freie VMID gefunden." >&2; exit 1; }
  fi
fi

# ---------- Storage Auto-Erkennung ----------
if [ -z "$STORAGE" ]; then
  for cand in local-lvm local-zfs local; do
    if pvesm status --storage "$cand" >/dev/null 2>&1; then STORAGE="$cand"; break; fi
  done
  if [ -z "$STORAGE" ]; then
    STORAGE="$(pvesm status 2>/dev/null | awk 'NR>1 && $1!="Name" && $1!="" {print $1}' | head -n1)"
  fi
  [ -n "${STORAGE:-}" ] || { echo "[XX] Kein Storage gefunden (pvesm status)." >&2; exit 1; }
  log "Storage (auto): $STORAGE"
fi
pvesm status --storage "$STORAGE" >/dev/null 2>&1 || { echo "[XX] Storage '$STORAGE' existiert nicht (pvesm ls)." >&2; exit 1; }

# ---------- Bridge Auto-Erkennung ----------
if [ -z "$BRIDGE" ]; then
  if ip link show vmbr0 >/dev/null 2>&1; then
    BRIDGE="vmbr0"
  else
    BRIDGE="$(ip -o link show 2>/dev/null | awk -F': ' '{print $2}' | grep -E '^vmbr[0-9]+' | head -n1 || true)"
  fi
  [ -n "${BRIDGE:-}" ] || { echo "[XX] Keine vmbr*-Bridge gefunden." >&2; exit 1; }
  log "Bridge (auto): $BRIDGE"
fi

# ---------- Interaktive Abfrage (Community-Scripts-Stil; --yes zum Überspringen) ----------
ask() { # ask VAR "Fragetext" "Default" – Enter übernimmt Default
  local __var="$1" __prompt="$2" __def="$3" __val
  printf '%s [%s]: ' "$__prompt" "$__def"
  read -r __val || __val=""
  if [ -n "$__val" ]; then printf -v "$__var" '%s' "$__val"; else printf -v "$__var" '%s' "$__def"; fi
}
is_num() { [[ "${1:-}" =~ ^[0-9]+$ ]]; }
if [ "${YES:-0}" != "1" ] && [ -t 0 ]; then
  echo ""
  echo "════════ FygoOS VM – Setup (Enter = Default) ════════"
  if command -v lvs >/dev/null 2>&1; then
    echo "--- Thin-Pools (Data% über ~85% = kritisch, dann lieber NICHT installieren) ---"
    lvs --noheadings -o lv_name,vg_name,data_percent 2>/dev/null | awk 'NF>=3 && $3 ~ /%/ {print "  Pool " $2 "/" $1 ": " $3}' | head -5
    echo "  Bedarf: ${DISK} GB Thin-Volume auf $STORAGE plus ~8 GB Download-Cache in /var/tmp"
  fi
  _d="$VMID"; ask VMID "VMID (nächste freie)" "$VMID"
  [ -n "$VMID" ] || { echo "[XX] VMID erforderlich (Zahl oder Abbruch mit Strg+C)." >&2; exit 1; }
  is_num "$VMID" || { warn "Keine Zahl – nehme $_d."; VMID="$_d"; }
  ensure_vmid_free
  ask NAME "VM-Name" "$NAME"
  _d="$CORES"; ask CORES "vCPU-Kerne (min. 2)" "$CORES"
  is_num "$CORES" || { warn "Keine Zahl – nehme $_d."; CORES="$_d"; }
  _d="$RAM"; ask RAM "RAM in MB (min. 8192, FydeOS-Reboot-Loop darunter)" "$RAM"
  is_num "$RAM" || { warn "Keine Zahl – nehme $_d."; RAM="$_d"; }
  _d="$DISK"; ask DISK "Disk in GB (min. 20, Thin-Pool beachten!)" "$DISK"
  is_num "$DISK" || { warn "Keine Zahl – nehme $_d."; DISK="$_d"; }
  ask STORAGE "Storage" "$STORAGE"
  ask BRIDGE "Bridge" "$BRIDGE"
  ask VARIANT "Variante (auto|apu|iris|slim|legacy)" "$VARIANT"
  ask NIC "NIC (virtio|e1000)" "$NIC"
  _d="$BOOT_DISK"; ask BOOT_DISK "Boot-Disk (sata|virtio|scsi)" "$BOOT_DISK"
  case "$BOOT_DISK" in sata|virtio|scsi) ;; *) warn "Unbekannt – nehme $_d."; BOOT_DISK="$_d";; esac
  _d="$BIOS"; ask BIOS "Firmware (ovmf|seabios)" "$BIOS"
  case "$BIOS" in ovmf|seabios) ;; *) warn "Unbekannt – nehme $_d."; BIOS="$_d";; esac
  _d="$SERIAL_CONSOLE"; ask SERIAL_CONSOLE "Serielle Kernel-Konsole für Debug (0|1, lesen per: qm terminal VMID)" "$SERIAL_CONSOLE"
  case "$SERIAL_CONSOLE" in 0|1) ;; *) warn "Unbekannt – nehme $_d."; SERIAL_CONSOLE="$_d";; esac
  _d="$HEADLESS"; ask HEADLESS "Headless Server-Modus ohne Desktop (0|1: VGA=none + serielle Konsole, Zugriff per qm terminal/SSH)" "$HEADLESS"
  case "$HEADLESS" in 0|1) ;; *) warn "Unbekannt – nehme $_d."; HEADLESS="$_d";; esac
  echo ""
  echo "  VM $VMID ($NAME): $CORES vCPU ($CPU_TYPE) / $RAM MB / ${DISK}G auf $STORAGE, Bridge $BRIDGE, Variante $VARIANT, NIC $NIC, Boot $BOOT_DISK, FW $BIOS, Headless $HEADLESS"
  printf 'Installieren? [J/n]: '
  read -r _go || _go=""
  case "$_go" in n|N|nein|NEIN|no|NO) echo "Abgebrochen – nichts geändert."; exit 0;; esac
  echo ""
fi
ensure_vmid_free
resolve_boot_dev
# Headless Server-Modus: keine Grafikkarte, serielle Konsole als Hauptausgabe
if [ "${HEADLESS:-0}" = "1" ]; then
  VGA="none"
  SERIAL_CONSOLE="1"
  log "Headless-Modus: VGA=none, SERIAL_CONSOLE=1 (Zugriff per 'qm terminal $VMID' bzw. SSH – noVNC bleibt schwarz)."
fi

[ "$RAM" -ge 8192 ] 2>/dev/null || warn "RAM=$RAM MB – Forum: 2 GB = Reboot-Loop, 4096 teils Hänger, nimm >= 8192 (Default)."
[ "$NIC" = "virtio" ] || [ "$NIC" = "e1000" ] || { echo "[XX] NIC muss 'virtio' oder 'e1000' sein (gewählt: $NIC)." >&2; exit 1; }
[ "$NIC" = "virtio" ] || warn "NIC=$NIC – e1000 nur als Fallback falls virtio kein Netz bekommt (langsamer)."
[ "$CORES" -ge 2 ] 2>/dev/null || warn "CORES=$CORES – nimm >= 2 (Default 4, Typ host)."
[ "$DISK" -ge 20 ] 2>/dev/null || warn "DISK=$DISK GB – Image ist ~7 GB entpackt, nimm >= 20 (Default 32)."
[ "$CPU_TYPE" = "host" ] || warn "CPU_TYPE=$CPU_TYPE – Forum empfiehlt 'host' gegen Boot-Hänger."
[ "$BIOS" = "ovmf" ] || [ "$BIOS" = "seabios" ] || { echo "[XX] BIOS muss 'ovmf' oder 'seabios' sein (gewählt: $BIOS)." >&2; exit 1; }
[ "$BIOS" = "ovmf" ] || warn "BIOS=$BIOS – Experiment: GPT-Schutz-MBR enthält meist keinen Bootcode, SeaBIOS-Boot unwahrscheinlich. efidisk wird übersprungen."
case "$BOOT_DISK" in
  sata|virtio|scsi) ;;
  *) echo "[XX] BOOT_DISK muss 'sata', 'virtio' oder 'scsi' sein (gewählt: $BOOT_DISK)." >&2; exit 1;;
esac
resolve_boot_dev

# ---------- Variante auflösen (VOR qm create, damit eine falsche URL keine VM-Leiche hinterlässt) ----------
URL_APU="https://download.fydeos.io/FydeOS_for_PC_apu_v18.0-SP1-io-stable.img.xz"
URL_IRIS="https://download.fydeos.io/FydeOS_for_PC_iris_v18.0-SP1-io-stable.img.xz"
# Intel Slim v23.0-SP1 (kein fydeos.io-Direktlink; Google-Drive-Mirror von https://fydeos.io/download/pc/intel-slim/)
GDRIVE_SLIM_ID="1OF0eklHZLyBZftMljybjVf4bNpht2Eu6"
GDRIVE_SLIM_NAME="FydeOS_for_PC_slim_v23.0-SP1-io.bin.zip"
GDRIVE_SLIM_SHA="4679828fcc5300c2006a988076e8846ad5c77d7a7a45eb3c8bfcdc478f1cb2c8"
download_gdrive() { # download_gdrive FILEID DEST – Drive-Direktdownload (confirm=t, ohne Cookies)
  local _id="$1" _dest="$2"
  if [ "$DRY_RUN" = "1" ]; then echo "[DRY] curl -fSL drive.usercontent.google.com/download?id=$_id... -o $_dest"; return 0; fi
  log "Lade Google-Drive-Datei (kann >2 GB sein, dauert je nach Leitung) ..."
  if curl -fSL --retry 2 --retry-delay 10 -o "$_dest" "https://drive.usercontent.google.com/download?id=${_id}&export=download&confirm=t" 2>&1 | tee -a "$LOG"; then
    [ -s "$_dest" ] && return 0
  fi
  rm -f "$_dest"
  echo "[XX] Google-Drive-Download fehlgeschlagen. Fallback: Datei manuell von https://fydeos.io/download/ laden," >&2
  echo "[XX] per scp nach /var/tmp kopieren und per --image-url file:///var/tmp/<datei>.bin.zip übergeben." >&2
  return 1
}
if [ "$VARIANT" = "auto" ]; then
  CPUINFO="$(lscpu 2>/dev/null || cat /proc/cpuinfo 2>/dev/null || true)"
  if echo "$CPUINFO" | grep -qi "AuthenticAMD"; then
    VARIANT="apu"; log "CPU-Erkennung: AMD -> Variante apu"
  elif echo "$CPUINFO" | grep -qiE "celeron|pentium"; then
    VARIANT="slim"; log "CPU-Erkennung: Celeron/Pentium -> Variante slim (Intel Slim, z. B. J4105)"
  elif echo "$CPUINFO" | grep -qi "GenuineIntel"; then
    VARIANT="iris"; log "CPU-Erkennung: Intel -> Variante iris (Core 6.-14. Gen). Bei Core 3.-5. Gen: --variant legacy + IMAGE_URL von https://fydeos.io/download/pc/intel-hd/"
  else
    VARIANT="apu"; warn "CPU-Hersteller nicht erkennbar (lscpu?) – nehme apu (Forum-bewährt). Per --variant apu|iris|slim|legacy übersteuerbar."
  fi
fi
if [ -z "${IMAGE_URL:-}" ]; then
  case "$VARIANT" in
    apu) IMAGE_URL="$URL_APU";;
    iris) IMAGE_URL="$URL_IRIS";;
    slim) GDRIVE_ID="$GDRIVE_SLIM_ID"; GDRIVE_NAME="$GDRIVE_SLIM_NAME"; GDRIVE_SHA="$GDRIVE_SLIM_SHA"
      IMAGE_URL="gdrive:$GDRIVE_ID/$GDRIVE_NAME";;
    legacy) echo "[XX] Variante 'legacy' hat keinen Direkt-Link (FydeOS liefert v20+ nur via Drive/iCloud auf https://fydeos.io/download/)." >&2
      echo "[XX] So geht's: Variante ($VARIANT) als .bin.zip auf einem PC laden, per scp nach /var/tmp kopieren," >&2
      echo "[XX] dann: IMAGE_URL=file:///var/tmp/<datei>.bin.zip bash fygoos.sh  (ZIP-Support ist eingebaut)." >&2
      exit 1;;
    *) echo "[XX] Unbekannte Variante: $VARIANT (erlaubt: auto, apu, iris, slim, legacy + --image-url)." >&2; exit 1;;
  esac
  log "Variante $VARIANT -> $IMAGE_URL"
else
  log "IMAGE_URL manuell gesetzt (schlägt Variante $VARIANT): $IMAGE_URL"
fi
case "$IMAGE_URL" in
  *.zip) command -v unzip >/dev/null || { echo "[XX] 'unzip' erforderlich für .bin.zip-Images (apt install unzip)." >&2; exit 1; };;
esac
# Preflight: URL erreichbar? (Range-Request, lädt nur 1 KB – fängt 404/typo bevor eine VM angelegt wird)
log "Prüfe Image-URL (Preflight) ..."
if [ "$DRY_RUN" = "1" ]; then
  case "$IMAGE_URL" in
    gdrive:*) echo "[DRY] curl -fsSL --max-time 30 -r 0-1023 -o /dev/null drive.usercontent.google.com/download?id=${GDRIVE_ID:-?}...";;
    *) echo "[DRY] curl -fsSL --max-time 30 -r 0-1023 -o /dev/null $IMAGE_URL";;
  esac
else
  case "$IMAGE_URL" in
    gdrive:*)
      GDRIVE_ID="${IMAGE_URL#gdrive:}"; GDRIVE_ID="${GDRIVE_ID%%/*}"
      if curl -fsSL --max-time 30 -r 0-1023 -o /dev/null "https://drive.usercontent.google.com/download?id=${GDRIVE_ID}&export=download&confirm=t" 2>>"$LOG"; then
        ok "Google-Drive-Datei erreichbar."
      else
        echo "[XX] Google-Drive-Datei nicht ladbar (ID $GDRIVE_ID)." | tee -a "$LOG" >&2
        exit 1
      fi;;
    *)
      if command -v curl >/dev/null && curl -fsSL --max-time 30 -r 0-1023 -o /dev/null "$IMAGE_URL" 2>>"$LOG"; then
        ok "Image-URL erreichbar."
      else
        echo "[XX] Image-URL nicht ladbar: $IMAGE_URL" | tee -a "$LOG" >&2
        echo "[XX] Falsche Variante? Aktuell: $VARIANT. Versuche VARIANT=apu|iris|slim oder eine eigene URL von https://fydeos.io/download/ per --image-url." | tee -a "$LOG" >&2
        exit 1
      fi;;
  esac
fi

run() {
  if [ "$DRY_RUN" = "1" ]; then echo "[DRY] $*"; else echo "[+] $*" >>"$LOG"; "$@"; fi
}

log "Lege VM $VMID an ($NAME): $CORES vCPU ($CPU_TYPE) / $RAM MB / ${DISK}G, BIOS=$BIOS, VGA=$VGA, Storage=$STORAGE, Bridge=$BRIDGE"
log "Image: $IMAGE_URL"
log "Log: $LOG"

# ---------- VM anlegen ----------
run qm create "$VMID" --name "$NAME" --ostype l26 \
  --cores "$CORES" --cpu "$CPU_TYPE" --memory "$RAM" --balloon 0 \
  --bios "$BIOS" --machine q35 \
  --scsihw virtio-scsi-pci \
  --net0 "$NIC,bridge=$BRIDGE" \
  --vga "$VGA" \
  --onboot 1 --agent enabled=0

# EFI-Disk für OVMF (nötig zum Booten). Bewusst OHNE pre-enrolled-keys:
# FydeOS-GRUB ist nicht Microsoft-signiert, mit Keys lädt Secure Boot ihn u. U. gar nicht erst.
if [ "$BIOS" = "ovmf" ]; then
  run qm set "$VMID" --efidisk0 "${STORAGE}:1" 2>&1 | tee -a "$LOG" || die "efidisk anlegen fehlgeschlagen."
fi

# Serielle Konsole für Kernel-Log (nur mit --serial-console / SERIAL_CONSOLE=1)
if [ "${SERIAL_CONSOLE:-0}" = "1" ]; then
  if [ "$DRY_RUN" = "1" ]; then
    echo "[DRY] qm set $VMID --serial0 socket  (Kernel-Log lesen: qm terminal $VMID)"
  else
    run qm set "$VMID" --serial0 socket 2>&1 | tee -a "$LOG" || warn "serial0 setzen fehlgeschlagen – Kernel-Log nur per noVNC lesbar."
  fi
fi

# ---------- Image laden + entpacken ----------
mkdir -p "$TMPDIR_WORK"
IMG_BASENAME="$(basename "$IMAGE_URL")"
[ -n "$IMG_BASENAME" ] || { echo "[XX] IMAGE_URL hat keinen Dateinamen: $IMAGE_URL" >&2; exit 1; }
XZ_FILE="$TMPDIR_WORK/$IMG_BASENAME"
ZIP_FILE=""
RAW_FILE="${XZ_FILE%.xz}"
case "$IMG_BASENAME" in
  *.img.xz) RAW_FILE="${XZ_FILE%.xz}";;
  *.bin.zip) ZIP_FILE="$XZ_FILE"; XZ_FILE=""; RAW_FILE="$TMPDIR_WORK/${IMG_BASENAME%.zip}";;
  *.zip) ZIP_FILE="$XZ_FILE"; XZ_FILE=""; RAW_FILE="$TMPDIR_WORK/${IMG_BASENAME%.zip}.bin";;
  *.img|*.raw|*.bin) RAW_FILE="$XZ_FILE"; XZ_FILE="";;
  *.ova) echo "[XX] .ova ist das VMware-Image (nur für VMware supportet, bootet unter KVM meist nicht: 'No bootable device'). Nimm FydeOS-for-PC (VARIANT=auto|apu|iris|slim, siehe --variant)." >&2; exit 1;;
  *) warn "Unerwartete Endung ($IMG_BASENAME) – erwarte .img.xz oder .bin.zip. Versuche es trotzdem."; RAW_FILE="$TMPDIR_WORK/image.img";;
esac

if [ -n "${ZIP_FILE:-}" ]; then
  # v20+: .bin.zip (Drive-Mirror, Direktlink oder manuell per scp nach /var/tmp + file://-URL)
  # Nur Größe prüfen reicht NICHT (abgebrochene Downloads!) – unzip -l liest nur das
  # Zentralverzeichnis am Dateiende und entlarvt Stümpfe in Sekunden.
  NEED_DL=0
  if [ ! -s "$ZIP_FILE" ]; then
    NEED_DL=1
  elif [ "$DRY_RUN" = "1" ]; then
    ok "Image-ZIP vorhanden (Dry-Run, keine Prüfung): $ZIP_FILE"
  elif unzip -l "$ZIP_FILE" >/dev/null 2>>"$LOG"; then
    ok "Image-ZIP bereits vorhanden und Struktur ok: $ZIP_FILE"
  else
    warn "Image-ZIP unvollständig/korrupt (früherer Abbruch?) – lösche und lade neu."
    rm -f "$ZIP_FILE"
    NEED_DL=1
  fi
  if [ "$NEED_DL" = "1" ]; then
    log "Lade Image-ZIP (kann >2 GB sein, dauert) ..."
    if [ "$DRY_RUN" = "1" ]; then
      case "$IMAGE_URL" in
        gdrive:*) echo "[DRY] download_gdrive ${GDRIVE_ID:-?} $ZIP_FILE";;
        *) echo "[DRY] curl -fSL --retry 3 -o $ZIP_FILE $IMAGE_URL";;
      esac
    else
      case "$IMAGE_URL" in
        gdrive:*)
          GDRIVE_ID="${IMAGE_URL#gdrive:}"; GDRIVE_ID="${GDRIVE_ID%%/*}"
          download_gdrive "$GDRIVE_ID" "$ZIP_FILE" || die "Drive-Download fehlgeschlagen."
          if [ -n "${GDRIVE_SHA:-}" ]; then
            GOT_SHA="$(sha256sum "$ZIP_FILE" 2>/dev/null | awk '{print $1}' || true)"
            if [ "${GOT_SHA:-}" = "$GDRIVE_SHA" ]; then
              ok "SHA-256 stimmt: $GOT_SHA"
            else
              warn "SHA-256 weicht ab (erwartet $GDRIVE_SHA, ist ${GOT_SHA:-?}) – weiter auf eigenes Risiko (unzip prüft die Struktur beim Entpacken)."
            fi
          fi;;
        *)
          if command -v curl >/dev/null; then
            curl -fSL --retry 3 --retry-delay 5 -o "$ZIP_FILE" "$IMAGE_URL" 2>&1 | tee -a "$LOG"
          else
            wget -O "$ZIP_FILE" "$IMAGE_URL" 2>&1 | tee -a "$LOG"
          fi;;
      esac
    fi
  fi
  if [ "$DRY_RUN" = "1" ]; then
    echo "[DRY] unzip -o $ZIP_FILE -d $TMPDIR_WORK  # .bin -> $RAW_FILE"
  else
    if [ ! -s "$RAW_FILE" ]; then
      log "Entpacke ZIP ($ZIP_FILE, dauert) ..."
      unzip -o "$ZIP_FILE" -d "$TMPDIR_WORK" 2>&1 | tee -a "$LOG"
      FOUND_BIN="$(find "$TMPDIR_WORK" -maxdepth 1 -name '*.bin' -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -n1 | cut -d' ' -f2- || true)"
      [ -n "${FOUND_BIN:-}" ] || { echo "[XX] Kein .bin im ZIP gefunden (unzip -l $ZIP_FILE prüfen)." >&2; exit 1; }
      [ "$FOUND_BIN" = "$RAW_FILE" ] || mv "$FOUND_BIN" "$RAW_FILE"
    else
      ok "Entpacktes Image vorhanden: $RAW_FILE"
    fi
    log "Image-Typ: $(file -b "$RAW_FILE" 2>/dev/null || echo unbekannt)"
    sha256sum "$RAW_FILE" 2>/dev/null | tee -a "$LOG" || true
  fi
elif [ -n "${XZ_FILE:-}" ]; then
  if [ ! -s "$XZ_FILE" ]; then
    log "Lade Image (kann >1,5 GB sein, dauert je nach Leitung) ..."
    if [ "$DRY_RUN" = "1" ]; then
      echo "[DRY] curl -fSL --retry 3 -o $XZ_FILE $IMAGE_URL"
    else
      if command -v curl >/dev/null; then
        curl -fSL --retry 3 --retry-delay 5 -o "$XZ_FILE" "$IMAGE_URL" 2>&1 | tee -a "$LOG"
      else
        wget -O "$XZ_FILE" "$IMAGE_URL" 2>&1 | tee -a "$LOG"
      fi
    fi
  else
    ok "Image bereits vorhanden: $XZ_FILE"
  fi
  if [ "$DRY_RUN" = "1" ]; then
    echo "[DRY] xz -t $XZ_FILE && xz -dkf $XZ_FILE"
  else
    log "Prüfe xz-Archiv ..."
    if ! xz -t "$XZ_FILE" 2>&1 | tee -a "$LOG"; then
      warn "xz-Archiv korrupt (früherer Abbruch?) – lösche $XZ_FILE."
      rm -f "$XZ_FILE" "$RAW_FILE"
      echo "[XX] Bitte Installer erneut starten – das Archiv wird neu geladen." >&2
      exit 1
    fi
    if [ ! -s "$RAW_FILE" ]; then
      log "Entpacke ($XZ_FILE -> $RAW_FILE, ~7 GB, dauert) ..."
      xz -dkf "$XZ_FILE" 2>&1 | tee -a "$LOG"
    else
      ok "Entpacktes Image vorhanden: $RAW_FILE"
    fi
    log "Image-Typ: $(file -b "$RAW_FILE" 2>/dev/null || echo unbekannt)"
    sha256sum "$RAW_FILE" 2>/dev/null | tee -a "$LOG" || true
  fi
else
  RAW_FILE="$XZ_FILE"
fi

# ---------- Disk importieren + als Bootdisk einhängen ----------
log "Importiere Disk nach $STORAGE (qm disk import, dauert) ..."
if [ "$DRY_RUN" = "1" ]; then
  echo "[DRY] qm disk import $VMID $RAW_FILE $STORAGE"
  echo "[DRY] qm set $VMID --${BOOT_DEV} $STORAGE:vm-$VMID-disk-0 --boot order=${BOOT_DEV}"
  if [ "${GRUB_TWEAK:-1}" = "1" ]; then echo "[DRY] GRUB-Tweak: kpartx ESP mappen, grub.cfg + syslinux/*.cfg sichern, s/i915.modeset=1/i915.modeset=0 nomodeset/"; else echo "[DRY] GRUB-Tweak deaktiviert"; fi
  echo "[DRY] GPT-Backup fixieren (sgdisk -e), falls sgdisk vorhanden"
else
  run qm disk import "$VMID" "$RAW_FILE" "$STORAGE" 2>&1 | tee -a "$LOG"
  UNUSED="$(qm config "$VMID" | grep -oP '^unused0: \K[^,]+' | head -n1 || true)"
  [ -n "${UNUSED:-}" ] || { echo "[XX] unused0 nach 'qm disk import' nicht gefunden (qm config $VMID prüfen)." >&2; exit 1; }
  # Forum-bewährt: als SATA einhängen (SCSI/IDE/VirtIO booten oft gar nicht)
  run qm set "$VMID" --${BOOT_DEV} "$UNUSED" 2>&1 | tee -a "$LOG"
  run qm set "$VMID" --boot "order=${BOOT_DEV}" 2>&1 | tee -a "$LOG"
  # Auf Zielgröße erweitern (Image selbst ist ~7 GB, thin)
  if [ "$DISK" -gt 8 ] 2>/dev/null; then
    run qm resize "$VMID" "$BOOT_DEV" "${DISK}G" 2>&1 | tee -a "$LOG" || warn "qm resize fehlgeschlagen – VM nutzt Image-Größe, läuft trotzdem."
  fi
  # GPT-Backup-Header ans Disk-Ende versetzen (qm resize verschiebt das Ende;
  # parted/kpartx/OVMF meckern sonst über "Alternate GPT header not at end"). Best-effort.
  if command -v sgdisk >/dev/null; then
    DISK_DEV_FIX="$(pvesm path "$UNUSED" 2>/dev/null || true)"
    if [ -n "${DISK_DEV_FIX:-}" ] && [ -e "$DISK_DEV_FIX" ]; then
      sgdisk -e "$DISK_DEV_FIX" >>"$LOG" 2>&1 && ok "GPT-Backup-Header ans Ende versetzt." || warn "sgdisk -e fehlgeschlagen – harmlos (primäre GPT ist intakt), weiter."
    else
      warn "Backing-Device für GPT-Fix nicht auflösbar – übersprungen (harmlos)."
    fi
  else
    warn "sgdisk fehlt (apt install gdisk) – GPT-Backup bleibt versetzt (harmlos, nur Warnungen bei parted/kpartx)."
  fi
  # ---------- GRUB-Tweak auf der ESP (best-effort, bricht Install bei Fehler NICHT ab) ----------
  # Befund: FydeOS-Kernel hängt mit i915.modeset=1 (keine Intel-GPU unter QEMU).
  # Die ESP wird per kpartx gemappt, grub.cfg gesichert + gepatcht, alles wieder aufgeräumt.
  if [ "${GRUB_TWEAK:-1}" != "1" ]; then
    log "GRUB-Tweak deaktiviert (--no-grub-tweak) – ESP bleibt unverändert."
  elif ! command -v kpartx >/dev/null; then
    warn "kpartx fehlt (apt install multipath-tools) – GRUB-Tweak übersprungen."
  else
    DISK_DEV="$(pvesm path "$UNUSED" 2>/dev/null || true)"
    if [ -z "${DISK_DEV:-}" ] || [ ! -e "$DISK_DEV" ]; then
      warn "Backing-Device für $UNUSED nicht auflösbar – GRUB-Tweak übersprungen."
    elif kpartx -av "$DISK_DEV" >>"$LOG" 2>&1; then
      ESP_MAP="$(blkid 2>/dev/null | grep -i 'PARTLABEL="EFI-SYSTEM"' | cut -d: -f1 | head -n1 || true)"
      if [ -z "${ESP_MAP:-}" ]; then
        warn "EFI-SYSTEM-Partition nicht gefunden – GRUB-Tweak übersprungen."
      else
        MNT="$TMPDIR_WORK/esp"
        mkdir -p "$MNT"
        if mount -o rw "$ESP_MAP" "$MNT" 2>>"$LOG"; then
          GRUBCFG="$(find "$MNT" -ipath '*efi/boot/grub.cfg' 2>/dev/null | head -n1 || true)"
          if [ -n "${GRUBCFG:-}" ] && [ -f "$GRUBCFG" ]; then
              cp "$GRUBCFG" "$GRUBCFG.orig"
              sed -i 's/i915\.modeset=1/i915.modeset=0 nomodeset/' "$GRUBCFG" || warn "sed grub.cfg fehlgeschlagen."
              NTWEAK="$(grep -c nomodeset "$GRUBCFG" || true)"
              ok "GRUB-Tweak gesetzt: ${NTWEAK}x nomodeset in $(basename "$(dirname "$GRUBCFG")")/$(basename "$GRUBCFG") (Backup: grub.cfg.orig)."
            else
              warn "efi/boot/grub.cfg nicht auf ESP – GRUB-Teil übersprungen."
            fi
            # SeaBIOS-Pfad bootet via MBR->syslinux (NICHT grub.cfg) -> dort ebenfalls nomodeset
            NSYS=0
            for cfg in "$MNT"/syslinux/*.cfg "$MNT"/syslinux.cfg; do
              [ -f "$cfg" ] || continue
              if grep -q "i915.modeset=1" "$cfg" 2>/dev/null; then
                cp "$cfg" "$cfg.orig" 2>>"$LOG" || true
                if sed -i 's/i915\.modeset=1/i915.modeset=0 nomodeset/' "$cfg" 2>>"$LOG"; then NSYS=$((NSYS+1)); fi
              fi
            done
            ok "syslinux-Tweak: $NSYS cfg-Datei(en) mit nomodeset gepatcht (SeaBIOS-Boot)."
            if [ "${SERIAL_CONSOLE:-0}" = "1" ]; then
              NSER=0
              for cfg in "$MNT"/syslinux/*.cfg "$MNT"/syslinux.cfg; do
                [ -f "$cfg" ] || continue
                if grep -qE '^[[:space:]]*append ' "$cfg" 2>/dev/null && ! grep -q "console=ttyS0" "$cfg" 2>/dev/null; then
                  cp "$cfg" "$cfg.orig" 2>>"$LOG" || true
                  if sed -i 's/^\([[:space:]]*append .*\)/\1 console=ttyS0,115200n8/' "$cfg" 2>>"$LOG"; then NSER=$((NSER+1)); fi
                fi
              done
              ok "Serial-Tweak: $NSER cfg-Datei(en) mit console=ttyS0 (Kernel-Log per 'qm terminal $VMID' lesbar)."
            fi
          umount "$MNT" 2>>"$LOG" || warn "umount $MNT fehlgeschlagen – bitte manuell: umount $MNT"
        else
          warn "ESP-Mount fehlgeschlagen – Tweak übersprungen."
        fi
      fi
      kpartx -d "$DISK_DEV" >>"$LOG" 2>&1 || warn "kpartx -d $DISK_DEV fehlgeschlagen – bitte manuell aufräumen."
    else
      warn "kpartx -av $DISK_DEV fehlgeschlagen – Tweak übersprungen."
    fi
  fi
fi

# ---------- Verifikation ----------
if [ "$DRY_RUN" = "1" ]; then
  echo "[DRY] qm config $VMID | grep -E '$BOOT_DEV|boot|efidisk|onboot'"
else
  log "Verifiziere ..."
  qm config "$VMID" 2>&1 | tee -a "$LOG"
  qm config "$VMID" | grep -q "$BOOT_DEV:" || { echo "[XX] $BOOT_DEV fehlt in qm config $VMID." >&2; exit 1; }
  ok "Bootdisk $BOOT_DEV vorhanden."
  qm config "$VMID" | grep -q "onboot: 1" || warn "onboot nicht gesetzt."
  ok "onboot gesetzt (reboot-sicher)."
fi

# ---------- Start ----------
if [ "$START" = "1" ]; then
  log "Starte VM $VMID ..."
  if [ "$DRY_RUN" = "1" ]; then
    echo "[DRY] qm start $VMID"
    echo "[DRY] qm status $VMID"
  else
    run qm start "$VMID" 2>&1 | tee -a "$LOG" || warn "qm start meldete Fehler – qm status $VMID prüfen (Grafik-Init kann Minuten dauern)."
    sleep 5
    run qm status "$VMID" 2>&1 | tee -a "$LOG"
    if qm status "$VMID" 2>/dev/null | grep -q "status: running"; then
      ok "VM läuft (qm status = running)."
      # IP via ARP/Neightable ermitteln (FygoOS hat keinen qemu-guest-agent,
      # daher DHCP-Lease aus der Host-Neightable der Bridge lesen)
      VM_MAC="$(qm config "$VMID" | grep -oP '^net0:.*?virtio=\K[0-9a-f:]+' | head -n1 || true)"
      if [ -n "${VM_MAC:-}" ]; then
        log "Warte auf DHCP-Lease (ARP-Lookup MAC $VM_MAC, max. 90s) ..."
        VM_IP=""
        for i in $(seq 1 18); do
          sleep 5
          VM_IP="$(ip neigh show dev "$BRIDGE" 2>/dev/null | grep -i "$VM_MAC" | awk '{print $1}' | head -n1 || true)"
          [ -n "$VM_IP" ] && break
          # Ping-Flush erzwingt neue ARP-Einträge im Subnetz der Bridge
          ping -c1 -W1 -I "$BRIDGE" 255.255.255.255 >/dev/null 2>&1 || true
        done
        if [ -n "${VM_IP:-}" ]; then
          ok "VM-IP (via ARP auf $BRIDGE): $VM_IP"
        else
          warn "Keine IP via ARP gefunden (VM hat evtl. noch keine DHCP-Lease oder kein Netz). Konsole nutzen: Proxmox-WebUI -> VM $VMID -> Konsole. Dort:Strg+Alt+F2 -> Shell -> 'ifconfig eth0'."
        fi
      fi
    else
      warn "VM läuft (noch) nicht – Ausgabe oben + Log prüfen: $LOG"
    fi
  fi
fi

# Aufräumen nur bei Erfolg (bei Fehler Dateien für Re-Analyse liegen lassen)
if [ "$DRY_RUN" = "0" ] && [ -n "${RAW_FILE:-}" ] && [ -f "$RAW_FILE" ]; then
  log "Räume $TMPDIR_WORK auf (Image-Cache wird gelöscht, VM-Disk bleibt auf $STORAGE) ..."
  rm -f "$RAW_FILE" ${XZ_FILE:+$XZ_FILE} 2>/dev/null || true
fi

echo ""
echo "════════════════ FYGOOS VM ERSTELLT ════════════════"
echo "  VM       : $VMID ($NAME) – $CORES vCPU ($CPU_TYPE) / $RAM MB / ${DISK}G"
echo "  Storage  : $STORAGE ($BOOT_DEV, Boot order=$BOOT_DEV, BIOS=$BIOS, onboot=1)"
echo "  IP       : ${VM_IP:-<noch keine – Konsole: Proxmox-WebUI -> VM $VMID -> noVNC>}"
echo "  Zugriff  : KEINE Web-UI (FygoOS ist ein Desktop-OS!) – Zugriff über noVNC-Konsole"
echo "             Proxmox-WebUI -> VM $VMID -> Konsole. Erster Boot dauert Minuten."
if [ "${HEADLESS:-0}" = "1" ]; then
echo "  Headless : VGA=none (noVNC bleibt SCHWARZ, normal!) – Zugriff per: qm terminal $VMID"
echo "             SSH sobald Netz + sshd oben sind: ssh <user>@<IP aus ARP-Zeile oben>"
fi
echo "  Starten  : qm start $VMID     Stoppen: qm stop $VMID     Konfig: qm config $VMID"
echo "  GRUB-Tweak: $([ "${GRUB_TWEAK:-1}" = "1" ] && echo "nomodeset aktiv (ESP/grub.cfg + .orig-Backup)" || echo "aus (--no-grub-tweak)")"
if [ "${SERIAL_CONSOLE:-0}" = "1" ]; then
echo "  Kernel-Log: qm terminal $VMID  (oder: timeout 60 socat - UNIX-CONNECT:/var/run/qemu-server/$VMID.serial)"
fi
echo "  Log      : $LOG"
echo ""
echo "  Falls schwarzer Bildschirm / Boot hängt / keine IP (bekannt, siehe Forum):"
echo "    1) Falsche Variante? Script erkennt per lscpu (AMD->apu, Intel->iris). Prüfen: lscpu | grep -i 'model name'."
echo "       Andere Variante erzwingen: VARIANT=apu|iris bash fygoos.sh  (Core 3.-5. Gen braucht --variant legacy + IMAGE_URL von fydeos.io/download/pc/intel-hd/)"
echo "    2) Konsole prüfen (noVNC): Bootlogo/Desktop = ok, nur warten (erster Boot lang)."
echo "    3) Bei Hänger: qm shutdown $VMID && qm wait $VMID && qm start $VMID (RAM ist schon 8192)."
echo "    4) Kein Netz trotz Desktop: qm set $VMID --delete net0 && qm set $VMID --net0 e1000,bridge=$BRIDGE && qm start $VMID"
echo "    5) Weiter schwarz: echte GPU per Passthrough (lspci | grep -i vga -> qm set $VMID --hostpci0 <PCI>,pcie=1) + qm set $VMID --vga none"
echo "       (im Forum: RX550 erfolgreich, integriertes QEMU-VGA bleibt schwarz)"
echo "  Deinstall: qm stop $VMID && qm destroy $VMID --purge"
echo "═════════════════════════════════════════════════════"
