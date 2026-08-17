#!/usr/bin/env bash
# Build a stopped, immutable HAOS Proxmox template. This intentionally remains
# outside Terraform so a normal apply cannot download or reflash HAOS.
set -Eeuo pipefail

readonly DEFAULT_VERSION="18.2"
readonly DEFAULT_IMAGE_URL="https://github.com/home-assistant/operating-system/releases/download/18.2/haos_ova-18.2.qcow2.xz"
readonly DEFAULT_IMAGE_SHA256="254e53f354df0739e3afc09be5431a07df53f0df6b703885404f665c454f254e"

usage() {
  cat <<'EOF'
Usage: build-haos-template.sh --template-vmid VMID [options]

Required:
  --template-vmid VMID         Unused Proxmox VMID for the HAOS template

Options:
  --pve-host HOST              SSH host (default: pve1)
  --template-name NAME         Template name (default: haos-18.2)
  --storage STORAGE            Proxmox image storage (default: ssd-zfs)
  --haos-version VERSION       HAOS release version (default: 18.2)
  --image-url URL              Pinned HAOS QCOW2 XZ URL
  --image-sha256 SHA256        Expected compressed-image SHA-256
  --disk-size SIZE             Root disk size after import (default: 100G)
  --cores COUNT                Template CPU cores (default: 2)
  --memory-mb MIB              Template memory in MiB (default: 6144)
  --balloon-mb MIB             Template balloon memory in MiB (default: 3072)
  --bridge BRIDGE              Proxmox bridge (default: vmbr0)
  --vlan-id ID                 VLAN tag (default: 20)
  --interface NAME             HAOS NIC name (default: enp6s18)
  --static-address CIDR        Static IPv4 CIDR (default: 192.168.20.10/24)
  --gateway ADDRESS            IPv4 gateway (default: 192.168.20.1)
  --dns ADDRESS                DNS server (default: 192.168.10.2)
  --dry-run                    Print inputs without connecting to Proxmox
  --verify                     Verify the existing template only
  -h, --help                   Show this help

The HAOS release provides no official checksum or signature asset. The default
digest is a locally recorded reproducibility pin and must be reviewed with its
URL whenever the HAOS release changes.
EOF
}

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

PVE_HOST="pve1"
TEMPLATE_VMID=""
TEMPLATE_NAME="haos-${DEFAULT_VERSION}"
STORAGE="ssd-zfs"
HAOS_VERSION="$DEFAULT_VERSION"
IMAGE_URL="$DEFAULT_IMAGE_URL"
IMAGE_SHA256="$DEFAULT_IMAGE_SHA256"
DISK_SIZE="100G"
CORES="2"
MEMORY_MB="6144"
BALLOON_MB="3072"
BRIDGE="vmbr0"
VLAN_ID="20"
INTERFACE_NAME="enp6s18"
STATIC_ADDRESS="192.168.20.10/24"
GATEWAY="192.168.20.1"
DNS_SERVER="192.168.10.2"
MODE="build"

while (($# > 0)); do
  case "$1" in
    --pve-host) PVE_HOST=${2:?"--pve-host requires a value"}; shift 2 ;;
    --template-vmid) TEMPLATE_VMID=${2:?"--template-vmid requires a value"}; shift 2 ;;
    --template-name) TEMPLATE_NAME=${2:?"--template-name requires a value"}; shift 2 ;;
    --storage) STORAGE=${2:?"--storage requires a value"}; shift 2 ;;
    --haos-version) HAOS_VERSION=${2:?"--haos-version requires a value"}; shift 2 ;;
    --image-url) IMAGE_URL=${2:?"--image-url requires a value"}; shift 2 ;;
    --image-sha256) IMAGE_SHA256=${2:?"--image-sha256 requires a value"}; shift 2 ;;
    --disk-size) DISK_SIZE=${2:?"--disk-size requires a value"}; shift 2 ;;
    --cores) CORES=${2:?"--cores requires a value"}; shift 2 ;;
    --memory-mb) MEMORY_MB=${2:?"--memory-mb requires a value"}; shift 2 ;;
    --balloon-mb) BALLOON_MB=${2:?"--balloon-mb requires a value"}; shift 2 ;;
    --bridge) BRIDGE=${2:?"--bridge requires a value"}; shift 2 ;;
    --vlan-id) VLAN_ID=${2:?"--vlan-id requires a value"}; shift 2 ;;
    --interface) INTERFACE_NAME=${2:?"--interface requires a value"}; shift 2 ;;
    --static-address) STATIC_ADDRESS=${2:?"--static-address requires a value"}; shift 2 ;;
    --gateway) GATEWAY=${2:?"--gateway requires a value"}; shift 2 ;;
    --dns) DNS_SERVER=${2:?"--dns requires a value"}; shift 2 ;;
    --dry-run) MODE="dry-run"; shift ;;
    --verify) MODE="verify"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown option: $1" ;;
  esac
done

if ! [[ "$TEMPLATE_VMID" =~ ^[0-9]+$ ]] || ((TEMPLATE_VMID < 100)); then
  die "--template-vmid must be an integer of at least 100"
fi
if ! [[ "$VLAN_ID" =~ ^[0-9]+$ ]] || ((VLAN_ID < 1 || VLAN_ID > 4094)); then
  die "VLAN ID must be between 1 and 4094"
fi
if ! [[ "$CORES" =~ ^[0-9]+$ ]] || ((CORES < 2)); then
  die "cores must be at least 2"
fi
if ! [[ "$MEMORY_MB" =~ ^[0-9]+$ ]] || ((MEMORY_MB < 2048)); then
  die "memory must be at least 2048 MiB"
fi
if ! [[ "$BALLOON_MB" =~ ^[0-9]+$ ]] || ((BALLOON_MB > MEMORY_MB)); then
  die "balloon memory cannot exceed configured memory"
fi
[[ "$IMAGE_SHA256" =~ ^[[:xdigit:]]{64}$ ]] || die "image SHA-256 must contain 64 hexadecimal characters"
[[ "$PVE_HOST" =~ ^[A-Za-z0-9][A-Za-z0-9_.-]*$ ]] || die "PVE host contains unsupported characters"
[[ "$TEMPLATE_NAME" =~ ^[A-Za-z0-9][A-Za-z0-9_.-]*$ ]] || die "template name contains unsupported characters"
[[ "$STORAGE" =~ ^[A-Za-z0-9_.-]+$ ]] || die "storage contains unsupported characters"
[[ "$BRIDGE" =~ ^[A-Za-z0-9_.-]+$ ]] || die "bridge contains unsupported characters"
[[ "$INTERFACE_NAME" =~ ^[A-Za-z0-9_.-]+$ ]] || die "interface contains unsupported characters"

if [[ "$MODE" == "dry-run" ]]; then
  cat <<EOF
Would build HAOS ${HAOS_VERSION} template on ${PVE_HOST}:
  VMID: ${TEMPLATE_VMID}; name: ${TEMPLATE_NAME}; storage: ${STORAGE}
  image: ${IMAGE_URL}
  sha256: ${IMAGE_SHA256}
  resources: ${CORES} cores, ${MEMORY_MB} MiB, ${DISK_SIZE}
  network: ${BRIDGE} VLAN ${VLAN_ID}, ${STATIC_ADDRESS} via ${GATEWAY}, DNS ${DNS_SERVER}
EOF
  exit 0
fi

ssh "$PVE_HOST" bash -s -- \
  "$MODE" "$TEMPLATE_VMID" "$TEMPLATE_NAME" "$STORAGE" "$HAOS_VERSION" "$IMAGE_URL" "$IMAGE_SHA256" \
  "$DISK_SIZE" "$CORES" "$MEMORY_MB" "$BALLOON_MB" "$BRIDGE" "$VLAN_ID" "$INTERFACE_NAME" \
  "$STATIC_ADDRESS" "$GATEWAY" "$DNS_SERVER" <<'REMOTE'
set -Eeuo pipefail

MODE=$1
TEMPLATE_VMID=$2
TEMPLATE_NAME=$3
STORAGE=$4
HAOS_VERSION=$5
IMAGE_URL=$6
IMAGE_SHA256=$7
DISK_SIZE=$8
CORES=$9
MEMORY_MB=${10}
BALLOON_MB=${11}
BRIDGE=${12}
VLAN_ID=${13}
INTERFACE_NAME=${14}
STATIC_ADDRESS=${15}
GATEWAY=${16}
DNS_SERVER=${17}

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

[[ $(id -u) -eq 0 ]] || die "SSH user must be root"
for command in qm pvesm curl xz sha256sum qemu-nbd kpartx mount umount modprobe udevadm awk grep tail mktemp; do
  command -v "$command" >/dev/null || die "required command is unavailable: $command"
done

if qm status "$TEMPLATE_VMID" >/dev/null 2>&1; then
  config=$(qm config "$TEMPLATE_VMID")
  if grep -qx 'template: 1' <<<"$config" && grep -qx "name: ${TEMPLATE_NAME}" <<<"$config"; then
    printf 'Matching template %s (VMID %s) already exists; no import will run.\n' "$TEMPLATE_NAME" "$TEMPLATE_VMID"
    exit 0
  fi
  die "VMID ${TEMPLATE_VMID} exists but is not the expected ${TEMPLATE_NAME} template"
fi

[[ "$MODE" == "build" ]] || die "expected template ${TEMPLATE_NAME} (VMID ${TEMPLATE_VMID}) does not exist"

cache_dir=/var/lib/vz/template/cache
cache_file="${cache_dir}/$(basename "$IMAGE_URL")"
work_dir=$(mktemp -d)
qcow2_file="${work_dir}/haos_ova-${HAOS_VERSION}.qcow2"
mount_dir="${work_dir}/boot"
nbd_device=""
vm_created=false

cleanup() {
  status=$?
  set +e
  [[ -d "$mount_dir" ]] && umount "$mount_dir" >/dev/null 2>&1
  [[ -n "$nbd_device" ]] && kpartx -d "$nbd_device" >/dev/null 2>&1
  [[ -n "$nbd_device" ]] && udevadm settle >/dev/null 2>&1
  [[ -n "$nbd_device" ]] && qemu-nbd --disconnect "$nbd_device" >/dev/null 2>&1
  if [[ "$vm_created" == true ]] && qm status "$TEMPLATE_VMID" >/dev/null 2>&1; then
    qm destroy "$TEMPLATE_VMID" --purge 1 >/dev/null 2>&1
  fi
  rm -rf "$work_dir"
  exit "$status"
}
trap cleanup EXIT

mkdir -p "$cache_dir"
if [[ -f "$cache_file" ]] && ! printf '%s  %s\n' "$IMAGE_SHA256" "$cache_file" | sha256sum -c - >/dev/null; then
  rm -f "$cache_file"
fi
[[ -f "$cache_file" ]] || curl --fail --location --retry 3 --output "$cache_file" "$IMAGE_URL"
printf '%s  %s\n' "$IMAGE_SHA256" "$cache_file" | sha256sum -c -
xz -t "$cache_file"
xz -dc "$cache_file" >"$qcow2_file"

modprobe nbd max_part=16
for candidate in /dev/nbd{0..15}; do
  [[ -b "$candidate" ]] || continue
  if [[ ! -s "/sys/block/${candidate##*/}/pid" ]]; then
    nbd_device=$candidate
    break
  fi
done
[[ -n "$nbd_device" ]] || die "no unused /dev/nbd device is available"
qemu-nbd --connect="$nbd_device" --format=qcow2 "$qcow2_file"
udevadm settle
kpartx -avs "$nbd_device"
udevadm settle

boot_partition="/dev/mapper/${nbd_device##*/}p1"
for _ in {1..20}; do
  [[ -b "$boot_partition" ]] && break
  udevadm settle
  sleep 0.25
done
[[ -b "$boot_partition" ]] || die "unable to create the HAOS boot partition device"
udevadm wait --timeout=10 "$boot_partition"
[[ -b "$boot_partition" ]] || die "HAOS boot partition is not a block device: $boot_partition"

mkdir -p "$mount_dir"
mount "$boot_partition" "$mount_dir"
mkdir -p "$mount_dir/CONFIG/network"
cat >"$mount_dir/CONFIG/network/20-home-assistant" <<EOF
[connection]
id=home-assistant-static
type=ethernet
interface-name=${INTERFACE_NAME}
autoconnect=true

[ipv4]
method=manual
address1=${STATIC_ADDRESS},${GATEWAY}
dns=${DNS_SERVER};

[ipv6]
method=auto
EOF
sync
umount "$mount_dir"
kpartx -d "$nbd_device"
udevadm settle
qemu-nbd --disconnect "$nbd_device"
nbd_device=""

qm create "$TEMPLATE_VMID" --name "$TEMPLATE_NAME" --machine q35 --bios ovmf --ostype l26 \
  --cores "$CORES" --memory "$MEMORY_MB" --balloon "$BALLOON_MB" --scsihw virtio-scsi-pci \
  --net0 "virtio,bridge=${BRIDGE},tag=${VLAN_ID}" --agent enabled=1 --tablet 0 --localtime 1 --tags haos-template
vm_created=true

import_output=$(qm disk import "$TEMPLATE_VMID" "$qcow2_file" "$STORAGE" --format raw 2>&1)
printf '%s\n' "$import_output"
disk_ref=$(printf '%s\n' "$import_output" | grep -oE "${STORAGE}:vm-${TEMPLATE_VMID}-disk-[0-9]+" | tail -n 1 || true)
if [[ -z "$disk_ref" ]]; then
  disk_ref=$(pvesm list "$STORAGE" --vmid "$TEMPLATE_VMID" | awk 'NR > 1 { print $1 }' | tail -n 1)
fi
[[ -n "$disk_ref" ]] || die "unable to determine the imported HAOS disk volume"

qm set "$TEMPLATE_VMID" --efidisk0 "${STORAGE}:0,efitype=4m,pre-enrolled-keys=0" \
  --scsi0 "${disk_ref},ssd=1,discard=on" --boot order=scsi0 --serial0 socket
qm resize "$TEMPLATE_VMID" scsi0 "$DISK_SIZE"
qm template "$TEMPLATE_VMID"
vm_created=false
printf 'Created HAOS template %s (VMID %s).\n' "$TEMPLATE_NAME" "$TEMPLATE_VMID"
REMOTE
