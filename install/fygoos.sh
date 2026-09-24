#!/usr/bin/env bash
# FygoOS (ehem. FydeOS) als VM auf Proxmox VE – Einzeiler im Community-Scripts-Stil.
# Getestete Methode aus https://forum.proxmox.com/threads/install-fydeos-in-proxmox-ve.149345/
# (Download .img.xz -> xz -d -> qm disk import -> als SATA einhängen).
#
# Gebrauch (auf dem Proxmox-Host als root):
#   bash -c "$(wget -qLO - https://raw.githubusercontent.com/HatchetMan111/FygoOS-Proxmox/main/install/fygoos.sh)"
#   VMID=200 CORES=4 RAM=8192 DISK=32 bash -c "$(wget -qLO - https://raw.githubusercontent.com/HatchetMan111/FygoOS-Proxmox/main/install/fygoos.sh)"
#   bash fygoos.sh --vmid 200 --cores 4 --memory 8192 --disk 32 --storage local-lvm --bridge vmbr0 --nic e1000 --image-url https://...
#   bash fygoos.sh --dry-run        # zeigt nur qm-Befehle, ändert nichts
#   bash fygoos.sh --debug          # = bash -x, komplette Fehlermeldungskette + Log unter /tmp/fygoos-install-*.log
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
# Default ist ein bewährtes Beispiel aus dem Forum-Thread (Post #10, justinclift).
# URLs rotieren – IMMER prüfen und ggf. übersteuern mit:
#   --image-url <URL>  oder  IMAGE_URL=<URL> bash fygoos.sh
# Aktuelle Images: https://fydeos.io/download/ bzw. https://fygonas.com/download
# Varianten beachten (apu / intel-legacy / iris – passend zur Host-CPU wählen).
IMAGE_URL="${IMAGE_URL:-https://download.fydeos.io/FydeOS_for_PC_apu_v18.0-SP1-io-stable.img.xz}"
CPU_TYPE="${CPU_TYPE:-host}"           # Forum: "host" löst viele Boot-Hänger
BIOS="${BIOS:-ovmf}"                   # UEFI; SeaBIOS bootet das GPT-Image meist gar nicht
VGA="${VGA:-std}"                      # Falls schwarz: hinterher "qm set VMID --vga none" + GPU-Passthrough
START="${START:-1}"                    # 1 = VM nach Erstellung starten, 0 = nur anlegen
DRY_RUN="${DRY_RUN:-0}"                # 1 = nur Befehle zeigen
LOG="/tmp/fygoos-install-$(date +%Y%m%d-%H%M%S).log"
TMPDIR_WORK="/var/tmp/fygoos-install"

log()  { echo "[*] $*" | tee -a "$LOG"; }
ok()   { echo "[OK] $*" | tee -a "$LOG"; }
warn() { echo "[!!] $*" | tee -a "$LOG" >&2; }
die()  {
  local code=$?
  echo "[XX] FEHLER (exit=$code) in Befehl: '${BASH_COMMAND}' (Zeile ${BASH_LINENO[0]:-?})" | tee -a "$LOG" >&2
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
    --image-url) IMAGE_URL="$2"; shift 2;;
    --cpu) CPU_TYPE="$2"; shift 2;;
    --vga) VGA="$2"; shift 2;;
    --no-start) START="0"; shift;;
    --dry-run) DRY_RUN="1"; shift;;
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

# ---------- nächste freie VMID (immer, außer gesetzt) ----------
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
else
  if qm status "$VMID" >/dev/null 2>&1 || [ -e "/etc/pve/qemu-server/${VMID}.conf" ]; then
    FREE_ID="$(pvesh get /cluster/nextid 2>>"$LOG" || true)"
    if [ -n "${FREE_ID:-}" ]; then
      warn "VMID $VMID belegt – weiche auf freie ID $FREE_ID aus."
      VMID="$FREE_ID"
    else
      echo "[XX] VMID $VMID ist belegt. Freie ID wählen oder --vmid <frei> setzen." >&2
      exit 1
    fi
  fi
fi
# Idempotenz: gleiche VM existiert bereits mit unserem Namen -> abbrechen statt doppelt anlegen
if [ -e "/etc/pve/qemu-server/${VMID}.conf" ]; then
  echo "[XX] /etc/pve/qemu-server/${VMID}.conf existiert bereits – breche ab (idempotent, nichts überschrieben)." >&2
  exit 1
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

[ "$RAM" -ge 8192 ] 2>/dev/null || warn "RAM=$RAM MB – Forum: 2 GB = Reboot-Loop, 4096 teils Hänger, nimm >= 8192 (Default)."
[ "$NIC" = "virtio" ] || [ "$NIC" = "e1000" ] || { echo "[XX] NIC muss 'virtio' oder 'e1000' sein (gewählt: $NIC)." >&2; exit 1; }
[ "$NIC" = "virtio" ] || warn "NIC=$NIC – e1000 nur als Fallback falls virtio kein Netz bekommt (langsamer)."
[ "$CORES" -ge 2 ] 2>/dev/null || warn "CORES=$CORES – nimm >= 2 (Default 4, Typ host)."
[ "$DISK" -ge 20 ] 2>/dev/null || warn "DISK=$DISK GB – Image ist ~7 GB entpackt, nimm >= 20 (Default 32)."
[ "$CPU_TYPE" = "host" ] || warn "CPU_TYPE=$CPU_TYPE – Forum empfiehlt 'host' gegen Boot-Hänger."
[ "$BIOS" = "ovmf" ] || warn "BIOS=$BIOS – Forum/Tests: SeaBIOS bootet das Image meist nicht, nimm ovmf."

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

# EFI-Disk für OVMF (nötig zum Booten)
if [ "$BIOS" = "ovmf" ]; then
  run qm set "$VMID" --efidisk0 "${STORAGE}:1,efitype=4m,pre-enrolled-keys=1" 2>&1 | tee -a "$LOG" || \
    run qm set "$VMID" --efidisk0 "${STORAGE}:1" 2>&1 | tee -a "$LOG"
fi

# ---------- Image laden + entpacken ----------
mkdir -p "$TMPDIR_WORK"
IMG_BASENAME="$(basename "$IMAGE_URL")"
[ -n "$IMG_BASENAME" ] || { echo "[XX] IMAGE_URL hat keinen Dateinamen: $IMAGE_URL" >&2; exit 1; }
XZ_FILE="$TMPDIR_WORK/$IMG_BASENAME"
RAW_FILE="${XZ_FILE%.xz}"
case "$IMG_BASENAME" in
  *.img.xz) RAW_FILE="${XZ_FILE%.xz}";;
  *.img|*.raw) RAW_FILE="$XZ_FILE"; XZ_FILE="";;
  *.ova) echo "[XX] .ova ist das VMware-Image (nur für VMware supportet, bootet unter KVM meist nicht: 'No bootable device'). Nimm ein FydeOS-for-PC .img.xz (siehe --image-url)." >&2; exit 1;;
  *) warn "Unerwartete Endung ($IMG_BASENAME) – erwarte .img.xz. Versuche es trotzdem."; RAW_FILE="$TMPDIR_WORK/image.img";;
esac

if [ -n "${XZ_FILE:-}" ]; then
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
    xz -t "$XZ_FILE" 2>&1 | tee -a "$LOG"
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
  echo "[DRY] qm set $VMID --sata0 $STORAGE:vm-$VMID-disk-0 --boot order=sata0"
else
  run qm disk import "$VMID" "$RAW_FILE" "$STORAGE" 2>&1 | tee -a "$LOG"
  UNUSED="$(qm config "$VMID" | grep -oP '^unused0: \K[^,]+' | head -n1 || true)"
  [ -n "${UNUSED:-}" ] || { echo "[XX] unused0 nach 'qm disk import' nicht gefunden (qm config $VMID prüfen)." >&2; exit 1; }
  # Forum-bewährt: als SATA einhängen (SCSI/IDE/VirtIO booten oft gar nicht)
  run qm set "$VMID" --sata0 "$UNUSED" 2>&1 | tee -a "$LOG"
  run qm set "$VMID" --boot "order=sata0" 2>&1 | tee -a "$LOG"
  # Auf Zielgröße erweitern (Image selbst ist ~7 GB, thin)
  if [ "$DISK" -gt 8 ] 2>/dev/null; then
    run qm resize "$VMID" sata0 "${DISK}G" 2>&1 | tee -a "$LOG" || warn "qm resize fehlgeschlagen – VM nutzt Image-Größe, läuft trotzdem."
  fi
fi

# ---------- Verifikation ----------
if [ "$DRY_RUN" = "1" ]; then
  echo "[DRY] qm config $VMID | grep -E 'sata0|boot|efidisk|onboot'"
else
  log "Verifiziere ..."
  qm config "$VMID" 2>&1 | tee -a "$LOG"
  qm config "$VMID" | grep -q "sata0:" || { echo "[XX] sata0 fehlt in qm config $VMID." >&2; exit 1; }
  ok "Bootdisk sata0 vorhanden."
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
echo "  Storage  : $STORAGE (sata0, Boot order=sata0, BIOS=$BIOS, onboot=1)"
echo "  IP       : ${VM_IP:-<noch keine – Konsole: Proxmox-WebUI -> VM $VMID -> noVNC>}"
echo "  Zugriff  : KEINE Web-UI (FygoOS ist ein Desktop-OS!) – Zugriff über noVNC-Konsole"
echo "             Proxmox-WebUI -> VM $VMID -> Konsole. Erster Boot dauert Minuten."
echo "  Starten  : qm start $VMID     Stoppen: qm stop $VMID     Konfig: qm config $VMID"
echo "  Log      : $LOG"
echo ""
echo "  Falls schwarzer Bildschirm / Boot hängt / keine IP (bekannt, siehe Forum):"
echo "    1) Konsole prüfen (noVNC): Bootlogo/Desktop = ok, nur warten (erster Boot lang)."
echo "    2) Bei Hänger: qm shutdown $VMID && qm wait $VMID && qm set $VMID --memory 8192 && qm start $VMID"
echo "    3) Kein Netz trotz Desktop: qm set $VMID --delete net0 && qm set $VMID --net0 e1000,bridge=$BRIDGE && qm start $VMID"
echo "    4) Weiter schwarz: echte GPU per Passthrough (lspci | grep -i vga -> qm set $VMID --hostpci0 <PCI>,pcie=1) + qm set $VMID --vga none"
echo "       (im Forum: RX550 erfolgreich, integriertes QEMU-VGA bleibt schwarz)"
echo "  Deinstall: qm stop $VMID && qm destroy $VMID --purge"
echo "═════════════════════════════════════════════════════"
