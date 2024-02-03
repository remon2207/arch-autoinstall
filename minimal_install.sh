#!/usr/bin/env bash

set -eu

unalias -a

to_arch() { arch-chroot /mnt "${@}"; }

readonly KERNEL='linux-zen'
readonly DISK='/dev/sda'
readonly CPU_INFO && CPU_INFO="$(grep 'model name' /proc/cpuinfo | awk --field-separator='[ (]' 'NR==1 {print $3}')"

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
  local -r efi_part_type="$(sgdisk --list-types \
    | grep 'ef00' \
    | awk '{print $6,$7,$8}')"
  local -r normal_part_type="$(sgdisk --list-types \
    | grep '8300' \
    | awk '{print $2,$3}')"

  sgdisk --zap-all "${DISK}"
  sgdisk --new='0::+512M' -typecode='0:ef00' --change-name="0:${efi_part_type}" "${DISK}"
  sgdisk --new='0::' --typecode='0:8300' --change-name="0:${normal_part_type}" "${DISK}"

  mkfs.fat -F 32 "${DISK}1"
  mkfs.ext4 "${DISK}2"

  mount "${DISK}2" /mnt
  mount --mkdir --options='fmask=0077,dmask=0077' "${DISK}1" /mnt/boot
}

installation() {
  reflector --country='Japan' --age=24 --protocol='https' --sort='rate' --save='/etc/pacman.d/mirrorlist'
  sed --in-place --expression='s/^#\(ParallelDownloads\)/\1/' /etc/pacman.conf
  # shellcheck disable=SC2086
  pacstrap -K /mnt ${packagelist}
  genfstab -t 'PARTUUID' /mnt >> /mnt/etc/fstab
}

configuration() {
  to_arch reflector --country='Japan' --age=24 --protocol='https' --sort='rate' --save='/etc/pacman.d/mirrorlist'
  to_arch ln --symbolic --force /usr/share/zoneinfo/Asia/Tokyo /etc/localtime
  to_arch hwclock --systohc --utc
  to_arch sed --in-place \
    --expression='s/^#\(en_US.UTF-8 UTF-8\)/\1/' \
    --expression='s/^#\(ja_JP.UTF-8 UTF-8\)/\1/' /etc/locale.gen
  to_arch sed --in-place --expression='s/^#\(ParallelDownloads\)/\1/' /etc/pacman.conf
  to_arch locale-gen
  to_arch sed --expression='s/^# \(%wheel ALL=(ALL:ALL) ALL\)/\1/' /etc/sudoers | EDITOR='tee' to_arch visudo &> /dev/null
  echo 'LANG=en_US.UTF-8' > /mnt/etc/locale.conf
  echo 'KEYMAP=us' >> /mnt/etc/vconsole.conf
  echo 'virtualbox' > /mnt/etc/hostname
}

networking() {
  local -r net_interface="$(ip -br link show | awk 'NR==2 {print $1}')"

  local -r hosts="$(
    cat << EOF
127.0.0.1       localhost
::1             localhost
127.0.1.1       virtualbox.home virtualbox
EOF
  )"

  local -r wired="[Match]
Name=${net_interface}

[Network]
DHCP=yes"

  mkdir /etc/systemd/resolved.conf.d
  ln --symbolic --force /run/systemd/resolve/stub-resolv.conf /mnt/etc/resolv.conf

  echo "${hosts}" >> /mnt/etc/hosts
  echo "${wired}" > /mnt/etc/systemd/network/20-wired.network
}

create_user() {
  local -r user_name='virt'

  echo 'root:root' | to_arch chpasswd
  to_arch useradd --create-home --groups='wheel' --shell='/bin/bash' "${user_name}"
  echo "${user_name}:virt" | to_arch chpasswd
}

replacement() {
  to_arch sed --in-place \
    --expression='s/^#\(NTP=\)/\1ntp.nict.jp/' \
    --expression='s/^#\(FallbackNTP=\).*/\1ntp1.jst.mfeed.ad.jp ntp2.jst.mfeed.ad.jp ntp3.jst.mfeed.ad.jp/' /etc/systemd/timesyncd.conf
  # shellcheck disable=SC2016
  to_arch sed --in-place \
    --expression='s/\(-march=\)x86-64 -mtune=generic/\1skylake/' \
    --expression='s/^#\(MAKEFLAGS=\).*/\1"-j$(($(nproc)+1))"/' \
    --expression='s/^#\(BUILDDIR\)/\1/' /etc/makepkg.conf
  to_arch sed --in-place \
    --expression='s/^# \(--country\) France,Germany/\1 Japan/' \
    --expression='s/^--latest 5/# &/' \
    --expression='s/^\(--sort\) age/\1 rate/' /etc/xdg/reflector/reflector.conf
  to_arch sed --in-place --expression='s/^#\(Color\)/\1/' /etc/pacman.conf
  echo -e '\n--age 24' >> /mnt/etc/xdg/reflector/reflector.conf

  to_arch pacman --sync --refresh --refresh
}

boot_loader() {
  find_boot() { find /mnt/boot -type 'f' -name "${1}"; }

  to_arch bootctl install

  local -r root_partuuid="$(blkid --match-tag='PARTUUID' --output='value' "${DISK}2")"
  local -r vmlinuz="$(find_boot "*vmlinuz*${KERNEL}*" | awk --field-separator='/' '{print $4}')"
  local -r ucode="$(find_boot '*ucode*' | awk --field-separator='/' '{print $4}')"
  local -r initramfs="$(find_boot "*initramfs*${KERNEL}*" | awk --field-separator='/' 'NR==1 {print $4}')"
  local -r initramfs_fallback="$(find_boot "*initramfs*${KERNEL}*" | awk --field-separator='/' 'END {print $4}')"
  local -r kernel_params='rw panic=180'
  local -r entries='/mnt/boot/loader/entries'

  local -r loader_conf="$(
    cat << EOF
timeout      15
console-mode max
editor       no
EOF
  )"

  local -r entries_conf="$(
    cat << EOF
title    Arch Linux
linux    /${vmlinuz}
initrd   /${ucode}
initrd   /${initramfs}
options  root=PARTUUID=${root_partuuid} ${kernel_params} loglevel=3
EOF
  )"

  local -r entries_conf_fallback="$(
    cat << EOF
title    Arch Linux (fallback initramfs)
linux    /${vmlinuz}
initrd   /${ucode}
initrd   /${initramfs_fallback}
options  root=PARTUUID=${root_partuuid} ${kernel_params} debug
EOF
  )"

  echo "${loader_conf}" > /mnt/boot/loader/loader.conf
  echo "${entries_conf}" > "${entries}/arch.conf"
  echo "${entries_conf_fallback}" > "${entries}/arch_fallback.conf"
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
