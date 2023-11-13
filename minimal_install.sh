#!/usr/bin/env bash

set -eu

readonly HELP="USAGE:
${0} <disk>
  <microcode:intel | amd>
  <gpu:intel | amd>
  <HostName>
  <UserName>
  <userPasword>
  <rootPassword>"

if [[ $# -eq 0 ]]; then
  echo "${HELP}"
  exit 1
fi

packagelist="base \
  base-devel \
  linux-zen \
  linux-zen-headers \
  linux-firmware \
  vi \
  sudo \
  curl \
  wget \
  man-db \
  man-pages \
  reflector"

NET_INTERFACE=$(ip -br link show | grep ' UP ' | awk '{print $1}')
readonly NET_INTERFACE

readonly DISK="${1}"
readonly MICROCODE="${2}"
readonly GPU="${3}"
readonly HOSTNAME="${4}"
readonly USERNAME="${5}"
readonly USER_PASSWORD="${6}"
readonly ROOT_PASSWORD="${7}"

LOADER_CONF=$(
  cat << EOF
default      arch.conf
timeout      10
console-mode max
editor       no
EOF
)
readonly LOADER_CONF

readonly HOSTS='127.0.0.1 localhost
::1 localhost'

readonly WIRED="[Match]
Name=${NET_INTERFACE}

[Network]
DHCP=yes
DNS=8.8.8.8
DNS=8.8.4.4"

check_variables() {
  if [[ "${MICROCODE}" != 'intel' ]] && [[ "${MICROCODE}" != 'amd' ]]; then
    echo 'microcode error'
    exit 1
  elif [[ "${GPU}" != 'amd' ]] && [[ "${GPU}" != 'intel' ]]; then
    echo 'gpu error'
    exit 1
  fi
}

selection_arguments() {
  if [[ "${MICROCODE}" == 'intel' ]]; then
    packagelist="${packagelist} intel-ucode"
  elif [[ "${MICROCODE}" == 'amd' ]]; then
    packagelist="${packagelist} amd-ucode"
  fi
}

time_setting() {
  timedatectl set-ntp true
}

partitioning() {
  sgdisk -Z "${DISK}"
  sgdisk -n 0::+512M -t 0:ef00 -c '0:EFI system partition' "${DISK}"
  sgdisk -n 0:: -t 0:8300 -c '0:Linux filesystem' "${DISK}"

  # format
  mkfs.fat -F 32 "${DISK}1"
  mkfs.ext4 "${DISK}2"

  # mount
  mount "${DISK}2" /mnt
  mount -m -o fmask=0077,dmask=0077 "${DISK}1" /mnt/boot
}

installation() {
  reflector --country Japan --age 24 --protocol https --sort rate --save /etc/pacman.d/mirrorlist
  sed -i 's/^#ParallelDownloads/ParallelDownloads/' /etc/pacman.conf
  pacstrap -K /mnt ${packagelist}
  genfstab -t PARTUUID /mnt >> /mnt/etc/fstab
}

configuration() {
  arch-chroot /mnt ln -sf /usr/share/zoneinfo/Asia/Tokyo /etc/localtime
  arch-chroot /mnt hwclock --systohc --utc
  arch-chroot /mnt sed -i 's/^#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
  arch-chroot /mnt sed -i 's/^#ja_JP.UTF-8 UTF-8/ja_JP.UTF-8 UTF-8/' /etc/locale.gen
  arch-chroot /mnt sed -i 's/^#ParallelDownloads/ParallelDownloads/' /etc/pacman.conf
  arch-chroot /mnt locale-gen
  arch-chroot /mnt sh -c "echo '%wheel ALL=(ALL:ALL) ALL' | EDITOR='tee -a' visudo"
  echo 'LANG=en_US.UTF-8' > /mnt/etc/locale.conf
  echo 'KEYMAP=us' >> /mnt/etc/vconsole.conf
  echo "${HOSTNAME}" > /mnt/etc/hostname
}

networking() {
  echo "${HOSTS}" >> /mnt/etc/hosts
  echo "${WIRED}" > /mnt/etc/systemd/network/20-wired.network
  ln -sf /run/systemd/resolve/stub-resolv.conf /mnt/etc/resolv.conf
}

create_user() {
  echo "root:${ROOT_PASSWORD}" | arch-chroot /mnt chpasswd
  arch-chroot /mnt useradd -m -G wheel -s /bin/bash "${USERNAME}"
  echo "${USERNAME}:${USER_PASSWORD}" | arch-chroot /mnt chpasswd
}

replacement() {
  arch-chroot /mnt sed -i 's/^#NTP=/NTP=ntp.nict.jp/' /etc/systemd/timesyncd.conf
  arch-chroot /mnt sed -i 's/^#FallbackNTP=/FallbackNTP=ntp1.jst.mfeed.ad.jp ntp2.jst.mfeed.ad.jp ntp3.jst.mfeed.ad.jp/' /etc/systemd/timesyncd.conf
  arch-chroot /mnt sed -i 's/-march=x86-64 -mtune=generic/-march=skylake/' /etc/makepkg.conf
  arch-chroot /mnt sed -i 's/^#MAKEFLAGS="-j2"/MAKEFLAGS="-j$(($(nproc)+1))"/' /etc/makepkg.conf
  arch-chroot /mnt sed -i 's/^#BUILDDIR/BUILDDIR/' /etc/makepkg.conf
  arch-chroot /mnt sed -i 's/^#Color/Color/' /etc/pacman.conf
  arch-chroot /mnt sed -i 's/^# --country France,Germany/--country Japan/' /etc/xdg/reflector/reflector.conf
  arch-chroot /mnt sed -i 's/^--latest 5/# &/' /etc/xdg/reflector/reflector.conf
  arch-chroot /mnt sed -i 's/^--sort age/--sort rate/' /etc/xdg/reflector/reflector.conf
  echo -e '\n--age 24' >> /mnt/etc/xdg/reflector/reflector.conf

  arch-chroot /mnt pacman -Syy
}

boot_loader() {
  arch-chroot /mnt bootctl install

  ROOT_PARTUUID=$(blkid -s PARTUUID -o value "${DISK}2")
  VMLINUZ=$(find /mnt/boot/*vmlinuz* | awk -F '/' '{print $4}')
  UCODE=$(find /mnt/boot/*ucode* | awk -F '/' '{print $4}')
  INITRAMFS=$(find /mnt/boot/*initramfs* | tail -n 1 | awk -F '/' '{print $4}')
  INITRAMFS_FALLBACK=$(find /mnt/boot/*initramfs* | head -n 1 | awk -F '/' '{print $4}')

  AMD_CONF=$(
    cat << EOF
title    Arch Linux
linux    /${VMLINUZ}
initrd   /${UCODE}
initrd   /${INITRAMFS}
options  root=PARTUUID=${ROOT_PARTUUID} rw loglevel=3 panic=180 i915.modeset=0
EOF
  )
  readonly AMD_CONF

  AMD_FALLBACK_CONF=$(
    cat << EOF
title    Arch Linux (fallback initramfs)
linux    /${VMLINUZ}
initrd   /${UCODE}
initrd   /${INITRAMFS_FALLBACK}
options  root=PARTUUID=${ROOT_PARTUUID} rw debug panic=180 i915.modeset=0
EOF
  )
  readonly AMD_FALLBACK_CONF

  INTEL_CONF=$(
    cat << EOF
title    Arch Linux
linux    /${VMLINUZ}
initrd   /${UCODE}
initrd   /${INITRAMFS}
options  root=PARTUUID=${ROOT_PARTUUID} rw loglevel=3 panic=180
EOF
  )
  readonly INTEL_CONF

  INTEL_FALLBACK_CONF=$(
    cat << EOF
title    Arch Linux (fallback initramfs)
linux    /${VMLINUZ}
initrd   /${UCODE}
initrd   /${INITRAMFS_FALLBACK}
options  root=PARTUUID=${ROOT_PARTUUID} rw debug panic=180
EOF
  )
  readonly INTEL_FALLBACK_CONF

  echo "${LOADER_CONF}" > /mnt/boot/loader/loader.conf
  if [[ "${GPU}" == 'amd' ]]; then
    echo "${AMD_CONF}" > /mnt/boot/loader/entries/arch.conf
    echo "${AMD_FALLBACK_CONF}" > /mnt/boot/loader/entries/arch_fallback.conf
  elif [[ "${GPU}" == 'intel' ]]; then
    echo "${INTEL_CONF}" > /mnt/boot/loader/entries/arch.conf
    echo "${INTEL_FALLBACK_CONF}" > /mnt/boot/loader/entries/arch_fallback.conf
  fi
}

enable_services() {
  arch-chroot /mnt systemctl enable reflector.timer
  arch-chroot /mnt systemctl enable systemd-{boot-update,networkd,resolved}.service
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

main "$@"
