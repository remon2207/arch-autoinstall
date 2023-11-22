#!/usr/bin/env bash

set -eu

to_arch() { arch-chroot /mnt "${@}"; }

readonly KERNEL='linux-zen'
readonly DISK='/dev/sda'
CPU_INFO="$(grep 'model name' /proc/cpuinfo | awk -F '[ (]' 'NR==1 {print $3}')" && readonly CPU_INFO

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

selection_arguments() {
  case "${CPU_INFO}" in
  'Intel')
    packagelist="${packagelist} intel-ucode"
    ;;
  'AMD')
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
  to_arch reflector --country Japan --age 24 --protocol https --sort rate --save /etc/pacman.d/mirrorlist
  to_arch ln -sf /usr/share/zoneinfo/Asia/Tokyo /etc/localtime
  to_arch hwclock --systohc --utc
  to_arch sed -i -e \
    's/^#\(en_US.UTF-8 UTF-8\)/\1/' -e \
    's/^#\(ja_JP.UTF-8 UTF-8\)/\1/' /etc/locale.gen
  to_arch sed -i -e 's/^#\(ParallelDownloads\)/\1/' /etc/pacman.conf
  to_arch locale-gen
  to_arch sed -e 's/^# \(%wheel ALL=(ALL:ALL) ALL\)/\1/' /etc/sudoers | EDITOR='tee' to_arch visudo &> /dev/null
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

  echo 'root:root' | to_arch chpasswd
  to_arch useradd -m -G wheel -s /bin/bash "${USER_NAME}"
  echo "${USER_NAME}:virt" | to_arch chpasswd
}

replacement() {
  to_arch sed -i -e \
    's/^#\(NTP=\)/\1ntp.nict.jp/' -e \
    's/^#\(FallbackNTP=\).*/\1ntp1.jst.mfeed.ad.jp ntp2.jst.mfeed.ad.jp ntp3.jst.mfeed.ad.jp/' /etc/systemd/timesyncd.conf
  # shellcheck disable=SC2016
  to_arch sed -i -e \
    's/\(-march=\)x86-64 -mtune=generic/\1skylake/' -e \
    's/^#\(MAKEFLAGS=\).*/\1"-j$(($(nproc)+1))"/' -e \
    's/^#\(BUILDDIR\)/\1/' /etc/makepkg.conf
  to_arch sed -i -e \
    's/^# \(--country\) France,Germany/\1 Japan/' -e \
    's/^--latest 5/# &/' -e \
    's/^\(--sort\) age/\1 rate/' /etc/xdg/reflector/reflector.conf
  to_arch sed -i -e 's/^#\(Color\)/\1/' /etc/pacman.conf
  echo -e '\n--age 24' >> /mnt/etc/xdg/reflector/reflector.conf

  to_arch pacman -Syy
}

boot_loader() {
  find_boot() { find /mnt/boot -type f -name "${1}"; }

  to_arch bootctl install

  local -r ROOT_PARTUUID="$(blkid -s PARTUUID -o value "${DISK}2")"
  local -r VMLINUZ="$(find_boot "*vmlinuz*${KERNEL}*" | awk -F '/' '{print $4}')"
  local -r UCODE="$(find_boot '*ucode*' | awk -F '/' '{print $4}')"
  local -r INITRAMFS="$(find_boot "*initramfs*${KERNEL}*" | awk -F '/' 'NR==1 {print $4}')"
  local -r INITRAMFS_FALLBACK="$(find_boot "*initramfs*${KERNEL}*" | awk -F '/' 'END {print $4}')"

  local -r LOADER_CONF="$(
    cat << EOF
timeout      15
console-mode max
editor       no
EOF
  )"

  local -r ENTRIES_CONF="$(
    cat << EOF
title    Arch Linux
linux    /${VMLINUZ}
initrd   /${UCODE}
initrd   /${INITRAMFS}
options  root=PARTUUID=${ROOT_PARTUUID} rw loglevel=3 panic=180
EOF
  )"

  local -r ENTRIES_CONF_FALLBACK="$(
    cat << EOF
title    Arch Linux (fallback initramfs)
linux    /${VMLINUZ}
initrd   /${UCODE}
initrd   /${INITRAMFS_FALLBACK}
options  root=PARTUUID=${ROOT_PARTUUID} rw debug panic=180
EOF
  )"

  echo "${LOADER_CONF}" > /mnt/boot/loader/loader.conf
  echo "${ENTRIES_CONF}" > /mnt/boot/loader/entries/arch.conf
  echo "${ENTRIES_CONF_FALLBACK}" > /mnt/boot/loader/entries/arch_fallback.conf
}

enable_services() {
  to_arch systemctl enable systemd-{boot-update,networkd,resolved}.service reflector.timer
}

main() {
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
