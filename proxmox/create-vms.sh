#!/usr/bin/env bash
# Creates all lab VMs on the Proxmox host. Run on the host itself (as root), after
# Phase C (network + storage) is done and the ISOs/cloud image are uploaded to local
# storage. See "VM Migration/Homelab-Migration ....md" for the full sequencing.
#
# Assumes:
#   - Storage `local` holds ISOs, `local-lvm` (or equivalent LVM-thin) holds VM disks
#   - vmbr1 exists (proxmox/interfaces.snippet)
#   - Files present in /var/lib/vz/template/iso/:
#       proxmox-ve_*.iso is irrelevant here (that's what you're already running)
#       ubuntu-24.04-server-cloudimg-amd64.img   (Ubuntu cloud image, not an install ISO)
#       WinServer2025-eval-x64.iso
#       Win11-Pro-x64.iso
#       virtio-win.iso
#       autounattend-dc01.iso, autounattend-ws01.iso  (built below, from this repo)
set -euo pipefail

ISO_DIR="/var/lib/vz/template/iso"
STORAGE="local-lvm"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

# ---------------------------------------------------------------------------
# Build the autounattend ISOs from this repo. Each bundles the XML plus the
# scripts/ folder the XML xcopy's onto the target disk during specialize pass.
build_autounattend_iso() {
    local name=$1 xml=$2
    local staging
    staging=$(mktemp -d)
    cp "$xml" "$staging/autounattend.xml"
    mkdir -p "$staging/scripts"
    cp /root/soc-homelab/ad-lab/scripts/setup-dc01.ps1 "$staging/scripts/" 2>/dev/null || true
    cp /root/soc-homelab/ad-lab/scripts/setup-ws01.ps1 "$staging/scripts/" 2>/dev/null || true
    cp /root/soc-homelab/ad-lab/scripts/create-users.ps1 "$staging/scripts/" 2>/dev/null || true
    cp /root/soc-homelab/ad-lab/scripts/install-sysmon-wazuh-agent.ps1 "$staging/scripts/" 2>/dev/null || true
    genisoimage -o "$ISO_DIR/${name}.iso" -J -r "$staging"
    rm -rf "$staging"
    log "Built $ISO_DIR/${name}.iso"
}

log "Building autounattend ISOs (requires this repo checked out at /root/soc-homelab)"
build_autounattend_iso "autounattend-dc01" /root/soc-homelab/ad-lab/scripts/autounattend-dc01.xml
build_autounattend_iso "autounattend-ws01" /root/soc-homelab/ad-lab/scripts/autounattend-ws01.xml

# ---------------------------------------------------------------------------
# docker01 -- Ubuntu cloud image, cloud-init, no installer, no clicks
log "Creating docker01 (VMID 100)"
qm create 100 --name docker01 --memory 14336 --cores 6 --cpu host \
    --net0 virtio,bridge=vmbr1 --ostype l26 --agent enabled=1

qm importdisk 100 "$ISO_DIR/ubuntu-24.04-server-cloudimg-amd64.img" "$STORAGE"
qm set 100 --scsihw virtio-scsi-pci --scsi0 "${STORAGE}:vm-100-disk-0"
qm resize 100 scsi0 120G
qm set 100 --ide2 "${STORAGE}:cloudinit"
qm set 100 --boot order=scsi0
qm set 100 --serial0 socket --vga serial0
qm set 100 --cicustom "user=local:snippets/cloud-init-docker01.yaml"
qm set 100 --ipconfig0 "ip=192.168.100.30/24,gw=192.168.100.1"
qm set 100 --nameserver 1.1.1.1
# Copy proxmox/cloud-init-docker01.yaml to /var/lib/vz/snippets/ first, and edit the
# ssh_authorized_keys line in it, before this VM's first boot.

log "docker01 created but not started -- edit cloud-init-docker01.yaml's SSH key first, then: qm start 100"

# ---------------------------------------------------------------------------
# DC01 -- Windows Server 2025 Standard, Desktop Experience
# Uses SATA (not virtio-scsi) and e1000 (not virtio-net): Windows Setup has no inbox
# virtio drivers, and PnpCustomizationsWinPE/DriverPaths injection from autounattend.xml
# does not reliably fire for the official Server 2025 eval ISO (confirmed via WinPE
# setupact.log: answer file found and marked usable for pass [windowsPE], but the PnP/
# driver component is never processed -- 0 "pnp"/"vioscsi" mentions in the log even
# though drvload from an interactive cmd.exe loads the same .inf successfully). SATA +
# e1000 are natively supported by Windows Setup with zero driver injection needed.
log "Creating DC01 (VMID 110)"
qm create 110 --name DC01 --memory 6144 --cores 4 --cpu host \
    --net0 e1000,bridge=vmbr1 --ostype win11 --machine q35 --bios ovmf

qm set 110 --sata0 "${STORAGE}:80"
qm set 110 --efidisk0 "${STORAGE}:1,efitype=4m"
qm set 110 --ide0 "local:iso/WinServer2025-eval-x64.iso,media=cdrom"
qm set 110 --ide1 "local:iso/autounattend-dc01.iso,media=cdrom"
qm set 110 --ide2 "local:iso/virtio-win.iso,media=cdrom"
qm set 110 --boot order=sata0\;ide0

log "DC01 created but not started: qm start 110 (fully unattended from here per autounattend-dc01.xml)"

# ---------------------------------------------------------------------------
# WS01 -- Windows 11 Pro (needs TPM 2.0 + Secure Boot)
# SATA + e1000, same rationale as DC01 above (no virtio driver injection required).
log "Creating WS01 (VMID 120)"
qm create 120 --name WS01 --memory 6144 --cores 4 --cpu host \
    --net0 e1000,bridge=vmbr1 --ostype win11 --machine q35 --bios ovmf

qm set 120 --sata0 "${STORAGE}:80"
qm set 120 --efidisk0 "${STORAGE}:1,efitype=4m,pre-enrolled-keys=1"
qm set 120 --tpmstate0 "${STORAGE}:1,version=v2.0"
qm set 120 --ide0 "local:iso/Win11-Pro-x64.iso,media=cdrom"
qm set 120 --ide1 "local:iso/autounattend-ws01.iso,media=cdrom"
qm set 120 --ide2 "local:iso/virtio-win.iso,media=cdrom"
qm set 120 --boot order=sata0\;ide0

log "WS01 created but not started -- start it only after DC01 has finished promotion (phase E ordering)"

# ---------------------------------------------------------------------------
# kali -- deferred (see migration plan: "Kali zurückgestellt"). VM shell only,
# no ISO attached, not started. Install happens separately in Phase 3.
log "Creating kali placeholder (VMID 130) -- definition only, not installed"
qm create 130 --name kali --memory 4096 --cores 4 --cpu host \
    --net0 virtio,bridge=vmbr1 --ostype l26

qm set 130 --scsihw virtio-scsi-pci
qm set 130 --scsi0 "${STORAGE}:60"

log "All VM definitions created. Start order: docker01 first (validates the NAT bridge), then DC01, then WS01 after DC01 finishes."
