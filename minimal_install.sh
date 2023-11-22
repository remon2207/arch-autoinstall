#!/usr/bin/env bash

set -eu

usage() {
  cat << EOF
USAGE:
  ${0} <OPTIONS>
OPTIONS:
  -d        Path of disk
  -m        microcode value [intel, amd]
  -g        gpu value [intel, amd]
  -u        Password of user
  -r        Password of root
  -h        See Help
EOF
}

if [[ ${#} -eq 0 ]]; then
  usage
  exit 1
fi

readonly KERNEL='linux-zen'

packagelist="base \
  base-devel \
  ${KERNEL} \
  ${KERNEL}-headers \
  linux-firmware \
  vi \
  sudo \
  curl \
  wget \
  man-db \
  man-pages \
  reflector"

while getopts 'd:m:g:u:r:h' opt; do
  case "${opt}" in
  'd')
    readonly DISK="${OPTARG}"
    ;;
  'm')
    readonly MICROCODE="${OPTARG}"
    ;;
  'g')
    readonly GPU="${OPTARG}"
    ;;
  'u')
    readonly USER_PASSWORD="${OPTARG}"
    ;;
  'r')
    readonly ROOT_PASSWORD="${OPTARG}"
    ;;
  'h')
    usage
    exit 0
    ;;
  *)
    usage
    exit 1
    ;;
  esac
done

check_variables() {
  case "${MICROCODE}" in
  'intel') ;;
  'amd') ;;
  *)
    echo -e '\e[31mmicrocode typo\e[m'
    exit 1
    ;;
  esac
  case "${GPU}" in
  'intel') ;;
  'amd') ;;
  *)
    echo -e '\e[31mgpu typo\e[m'
    exit 1
    ;;
  esac
}

selection_arguments() {
  case "${MICROCODE}" in
  'intel')
    packagelist="${packagelist} intel-ucode"
    ;;
  'amd')
    packagelist="${packagelist} amd-ucode"
    ;;
  esac
}

time_setting() {
  hwclock --systohc --utc
  timedatectl set-ntp true
}

partitioning() {
  local -r EFI_PART_TYPE="$(sgdisk -L | grep 'ef00' | awk '{print $6,$7,$8}')"
  local -r NORMAL_PART_TYPE="$(sgdisk -L | grep '8300' | awk '{print $2,$3}')"

  sgdisk -Z "${DISK}"
  sgdisk -n 0::+512M -t 0:ef00 -c "0:${EFI_PART_TYPE}" "${DISK}"
  sgdisk -n 0:: -t 0:8300 -c "0:${NORMAL_PART_TYPE}" "${DISK}"

  # format
  mkfs.fat -F 32 "${DISK}1"
  mkfs.ext4 "${DISK}2"

  # mount
  mount "${DISK}2" /mnt
  mount -m -o fmask=0077,dmask=0077 "${DISK}1" /mnt/boot
}

installation() {
  reflector --country Japan --age 24 --protocol https --sort rate --save /etc/pacman.d/mirrorlist
  sed -i -e 's/^#\(ParallelDownloads\)/\1/' /etc/pacman.conf
  # shellcheck disable=SC2086
  pacstrap -K /mnt ${packagelist}
  genfstab -t PARTUUID /mnt >> /mnt/etc/fstab
}

configuration() {
  arch-chroot /mnt reflector --country Japan --age 24 --protocol https --sort rate --save /etc/pacman.d/mirrorlist
  arch-chroot /mnt ln -sf /usr/share/zoneinfo/Asia/Tokyo /etc/localtime
  arch-chroot /mnt hwclock --systohc --utc
  arch-chroot /mnt sed -i -e 's/^#\(en_US.UTF-8 UTF-8\)/\1/' -e \
    's/^#\(ja_JP.UTF-8 UTF-8\)/\1/' /etc/locale.gen
  arch-chroot /mnt sed -i -e 's/^#\(ParallelDownloads\)/\1/' /etc/pacman.conf
  arch-chroot /mnt locale-gen
  arch-chroot /mnt sed -e 's/^# \(%wheel ALL=(ALL:ALL) ALL\)/\1/' /etc/sudoers | EDITOR='tee' arch-chroot /mnt visudo &> /dev/null
  echo 'LANG=en_US.UTF-8' > /mnt/etc/locale.conf
  echo 'KEYMAP=us' >> /mnt/etc/vconsole.conf
  echo 'virtualbox' > /mnt/etc/hostname
}

networking() {
  local -r NET_INTERFACE="$(ip -br link show | awk 'NR==2 {print $1}')"

  local -r HOSTS="$(
    cat << EOF
127.0.0.1       localhost
::1             localhost
EOF
  )"

  local -r WIRED="[Match]
Name=${NET_INTERFACE}

[Network]
DHCP=yes
DNS=8.8.8.8
DNS=8.8.4.4"

  echo "${HOSTS}" >> /mnt/etc/hosts
  echo "${WIRED}" > /mnt/etc/systemd/network/20-wired.network
  ln -sf /run/systemd/resolve/stub-resolv.conf /mnt/etc/resolv.conf
}

create_user() {
  local -r USER_NAME='virt'

  echo "root:${ROOT_PASSWORD}" | arch-chroot /mnt chpasswd
  arch-chroot /mnt useradd -m -G wheel -s /bin/bash "${USER_NAME}"
  echo "${USER_NAME}:${USER_PASSWORD}" | arch-chroot /mnt chpasswd
}

replacement() {
  arch-chroot /mnt sed -i -e 's/^#\(NTP=\)/\1ntp.nict.jp/' -e \
    's/^#\(FallbackNTP=\).*/\1ntp1.jst.mfeed.ad.jp ntp2.jst.mfeed.ad.jp ntp3.jst.mfeed.ad.jp/' /etc/systemd/timesyncd.conf
  # shellcheck disable=SC2016
  arch-chroot /mnt sed -i -e 's/\(-march=\)x86-64 -mtune=generic/\1skylake/' -e \
    's/^#\(MAKEFLAGS=\).*/\1"-j$(($(nproc)+1))"/' -e \
    's/^#\(BUILDDIR\)/\1/' /etc/makepkg.conf
  arch-chroot /mnt sed -i -e 's/^# \(--country\) France,Germany/\1 Japan/' -e \
    's/^--latest 5/# &/' -e \
    's/^\(--sort\) age/\1 rate/' /etc/xdg/reflector/reflector.conf
  arch-chroot /mnt sed -i -e 's/^#\(Color\)/\1/' /etc/pacman.conf
  echo -e '\n--age 24' >> /mnt/etc/xdg/reflector/reflector.conf

  arch-chroot /mnt pacman -Syy
}

boot_loader() {
  arch-chroot /mnt bootctl install

  local -r ROOT_PARTUUID="$(blkid -s PARTUUID -o value "${DISK}2")"
  local -r VMLINUZ="$(find /mnt/boot -name "*vmlinuz*${KERNEL}*" -type f | awk -F '/' '{print $4}')"
  local -r UCODE="$(find /mnt/boot -name '*ucode*' -type f | awk -F '/' '{print $4}')"
  local -r INITRAMFS="$(find /mnt/boot -name "*initramfs*${KERNEL}*" -type f | head -n 1 | awk -F '/' '{print $4}')"
  local -r INITRAMFS_FALLBACK="$(find /mnt/boot -name "*initramfs*${KERNEL}*" -type f | tail -n 1 | awk -F '/' '{print $4}')"

  local -r LOADER_CONF="$(
    cat << EOF
timeout      15
console-mode max
editor       no
EOF
  )"

  local -r AMD_CONF="$(
    cat << EOF
title    Arch Linux
linux    /${VMLINUZ}
initrd   /${UCODE}
initrd   /${INITRAMFS}
options  root=PARTUUID=${ROOT_PARTUUID} rw loglevel=3 panic=180 i915.modeset=0
EOF
  )"

  local -r AMD_FALLBACK_CONF="$(
    cat << EOF
title    Arch Linux (fallback initramfs)
linux    /${VMLINUZ}
initrd   /${UCODE}
initrd   /${INITRAMFS_FALLBACK}
options  root=PARTUUID=${ROOT_PARTUUID} rw debug panic=180 i915.modeset=0
EOF
  )"

  local -r INTEL_CONF="$(
    cat << EOF
title    Arch Linux
linux    /${VMLINUZ}
initrd   /${UCODE}
initrd   /${INITRAMFS}
options  root=PARTUUID=${ROOT_PARTUUID} rw loglevel=3 panic=180
EOF
  )"

  local -r INTEL_FALLBACK_CONF="$(
    cat << EOF
title    Arch Linux (fallback initramfs)
linux    /${VMLINUZ}
initrd   /${UCODE}
initrd   /${INITRAMFS_FALLBACK}
options  root=PARTUUID=${ROOT_PARTUUID} rw debug panic=180
EOF
  )"

  echo "${LOADER_CONF}" > /mnt/boot/loader/loader.conf
  case "${GPU}" in
  'amd')
    echo "${AMD_CONF}" > /mnt/boot/loader/entries/arch.conf
    echo "${AMD_FALLBACK_CONF}" > /mnt/boot/loader/entries/arch_fallback.conf
    ;;
  'intel')
    echo "${INTEL_CONF}" > /mnt/boot/loader/entries/arch.conf
    echo "${INTEL_FALLBACK_CONF}" > /mnt/boot/loader/entries/arch_fallback.conf
    ;;
  esac
}

enable_services() {
  arch-chroot /mnt systemctl enable systemd-{boot-update,networkd,resolved}.service
  arch-chroot /mnt systemctl enable reflector.timer
}

main() {
  check_variables
  selection_arguments
  time_setting
  partitioning
  installation
  configuration
  networking
  create_user
  replacement
  boot_loader
  enable_services
}

main "${@}"
