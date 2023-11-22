#!/usr/bin/env bash

set -eu

usage() {
  cat << EOF
USAGE:
  ${0} <OPTIONS>
OPTIONS:
  -d        Path of disk
  -e        desktop environment or window manager [i3, xfce, gnome, kde]
  -g        gpu value [nvidia, amd, intel]
  -u        Password of user
  -r        Password of root
  -p        partition configration [yes, exclude-efi, root-only, skip]
  -s        size of root, Only the size you want to allocate to the root (omit units)
  -h        See Help
EOF
}

[[ ${#} -eq 0 ]] && usage && exit 1

to_arch() { arch-chroot /mnt "${@}"; }

readonly KERNEL='linux-zen'
readonly USER_NAME='remon'
CPU_INFO="$(grep 'model name' /proc/cpuinfo | awk -F '[ (]' 'NR==1 {print $3}')" && readonly CPU_INFO

packagelist="base \
  base-devel \
  ${KERNEL} \
  ${KERNEL}-headers \
  linux-firmware \
  vi \
  neovim \
  go \
  fd \
  sd \
  tldr \
  ripgrep \
  bat \
  sudo \
  zsh \
  curl \
  wget \
  fzf \
  git \
  openssh \
  htop \
  nmap \
  man-db \
  man-pages \
  xdg-user-dirs \
  wireplumber \
  pipewire \
  pipewire-pulse \
  noto-fonts \
  noto-fonts-cjk \
  noto-fonts-emoji \
  noto-fonts-extra \
  nerd-fonts \
  ttf-hack \
  fcitx5-im \
  fcitx5-mozc \
  docker \
  docker-compose \
  github-cli \
  discord \
  neofetch \
  reflector \
  xorg \
  xorg-apps \
  xorg-xinit \
  silicon \
  starship \
  lsd \
  profile-sync-daemon \
  vivaldi \
  vivaldi-ffmpeg-codecs \
  pigz \
  lbzip2 \
  pv \
  lazygit \
  shfmt \
  shellcheck \
  unzip \
  virtualbox \
  virtualbox-host-dkms \
  virtualbox-guest-iso \
  stylua \
  nfs-utils"

while getopts 'd:e:g:u:r:p:s:h' opt; do
  case "${opt}" in
  'd')
    readonly DISK="${OPTARG}"
    ;;
  'e')
    readonly DE="${OPTARG}"
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
  'p')
    readonly PARTITION_DESTROY="${OPTARG}"
    ;;
  's')
    readonly ROOT_SIZE="${OPTARG}"
    ;;
  'h')
    usage && exit 0
    ;;
  *)
    usage && exit 1
    ;;
  esac
done

check_variables() {
  case "${DE}" in
  'i3') ;;
  'xfce') ;;
  'gnome') ;;
  'kde') ;;
  *)
    echo -e '\e[31mde typo\e[m' && exit 1
    ;;
  esac
  case "${GPU}" in
  'nvidia') ;;
  'intel') ;;
  'amd') ;;
  *)
    echo -e '\e[31mgpu typo\e[m' && exit 1
    ;;
  esac
  case "${PARTITION_DESTROY}" in
  'yes') ;;
  'exclude-efi') ;;
  'root-only') ;;
  'skip') ;;
  *)
    echo -e '\e[31mpartition-destroy typo\e[m' && exit 1
    ;;
  esac
}

selection_arguments() {
  case "${CPU_INFO}" in
  'Intel')
    packagelist="${packagelist} intel-ucode"
    ;;
  'AMD')
    packagelist="${packagelist} amd-ucode"
    ;;
  esac

  case "${DE}" in
  'i3')
    packagelist="${packagelist} \
        i3-wm \
        i3lock \
        rofi \
        polybar \
        xautolock \
        polkit \
        scrot \
        feh \
        picom \
        dunst \
        gnome-keyring \
        qt5ct \
        kvantum \
        arc-gtk-theme \
        papirus-icon-theme \
        pavucontrol \
        alacritty \
        kitty \
        wezterm \
        tmux \
        ttf-font-awesome \
        ranger"
    ;;
  'xfce')
    packagelist="${packagelist} \
      xfce4 \
      xfce4-goodies \
      gnome-keyring \
      gvfs \
      qt5ct \
      kvantum \
      blueman \
      papirus-icon-theme \
      arc-gtk-theme \
      lightdm \
      lightdm-gtk-greeter \
      lightdm-gtk-greeter-settings"
    ;;
  'gnome')
    packagelist="${packagelist} \
      gnome-control-center \
      gnome-shell \
      gnome-tweaks \
      gnome-themes-extra \
      gnome-terminal \
      gnome-keyring \
      gnome-backgrounds \
      gnome-calculator \
      gnome-shell-extension-appindicator \
      gedit \
      mutter \
      file-roller \
      nautilus \
      gdm \
      gvfs \
      dconf-editor \
      eog \
      networkmanager"
    ;;
  'kde')
    packagelist="${packagelist} \
      plasma-meta \
      packagekit-qt5 \
      dolphin \
      konsole \
      gwenview \
      spectacle \
      kate"
    ;;
  esac

  case "${GPU}" in
  'nvidia')
    packagelist="${packagelist} nvidia-dkms nvidia-settings libva-vdpau-driver"
    ;;
  'intel')
    packagelist="${packagelist} libvdpau-va-gl libva-intel-driver"
    ;;
  'amd')
    packagelist="${packagelist} xf86-video-amdgpu libva-mesa-driver mesa-vdpau"
    ;;
  esac
}

time_setting() {
  hwclock --systohc --utc
  timedatectl set-ntp true
}

partitioning() {
  local -r NORMAL_PART_TYPE="$(sgdisk -L | grep '8300' | awk '{print $2,$3}')"

  case "${PARTITION_DESTROY}" in
  'yes')
    local -r EFI_PART_TYPE="$(sgdisk -L | grep 'ef00' | awk '{print $6,$7,$8}')"

    sgdisk -Z "${DISK}"
    sgdisk -n 0::+512M -t 0:ef00 -c "0:${EFI_PART_TYPE}" "${DISK}"
    sgdisk -n "0::+${ROOT_SIZE}G" -t 0:8300 -c "0:${NORMAL_PART_TYPE}" "${DISK}"
    sgdisk -n 0:: -t 0:8300 -c "0:${NORMAL_PART_TYPE}" "${DISK}"

    # format
    mkfs.fat -F 32 "${DISK}1"
    mkfs.ext4 "${DISK}2"
    mkfs.ext4 "${DISK}3"
    ;;
  'exclude-efi')
    sgdisk -d 3 "${DISK}"
    sgdisk -d 2 "${DISK}"
    sgdisk -n "0::+${ROOT_SIZE}G" -t 0:8300 -c "0:${NORMAL_PART_TYPE}" "${DISK}"
    sgdisk -n 0:: -t 0:8300 -c "0:${NORMAL_PART_TYPE}" "${DISK}"

    # format
    mkfs.ext4 "${DISK}2"
    mkfs.ext4 "${DISK}3"
    ;;
  'root-only')
    # format
    mkfs.ext4 "${DISK}2"
    ;;
  'skip')
    # format
    mkfs.ext4 "${DISK}2"
    mkfs.ext4 "${DISK}3"
    ;;
  esac

  # mount
  mount "${DISK}2" /mnt
  mount -m -o fmask=0077,dmask=0077 "${DISK}1" /mnt/boot
  mount -m "${DISK}3" /mnt/home
}

installation() {
  reflector --country Japan --age 24 --protocol https --sort rate --save /etc/pacman.d/mirrorlist
  sed -i -e 's/^#\(ParallelDownloads\)/\1/' /etc/pacman.conf
  # shellcheck disable=SC2086
  pacstrap -K /mnt ${packagelist}
  if [[ "${GPU}" == 'nvidia' ]]; then
    NUMBER_HOOKS="$(grep -n '^HOOKS' ./mkinitcpio.conf)" && readonly NUMBER_HOOKS
    NUMBER="$(echo "${NUMBER_HOOKS}" | awk -F ':' '{print $1}')" && readonly NUMBER
    HOOKS_ORG="$(echo "${NUMBER_HOOKS}" | awk -F ':' '{print $2}')" && readonly HOOKS_ORG
    NEW_NUMBER="$(("${NUMBER}" + 1))" && readonly NEW_NUMBER
    NEW_HOOKS="$(echo "${HOOKS_ORG}" | sed -e 's/\(.*\)kms \(.*\)consolefont \(.*\)/\1\2\3/' -e 's/consolefont //')" && readonly NEW_HOOKS

    to_arch sed -i -e 's/^MODULES=(/&nvidia nvidia_modeset nvidia_uvm nvidia_drm/' -e \
      "${NUMBER}s/^/#/" -e \
      "${NEW_NUMBER}i ${NEW_HOOKS}" /etc/mkinitcpio.conf
    to_arch mkinitcpio -p "${KERNEL}"
  fi
  genfstab -t PARTUUID /mnt >> /mnt/etc/fstab
}

configuration() {
  to_arch reflector --country Japan --age 24 --protocol https --sort rate --save /etc/pacman.d/mirrorlist
  to_arch ln -sf /usr/share/zoneinfo/Asia/Tokyo /etc/localtime
  to_arch hwclock --systohc --utc
  to_arch sed -i -e 's/^#\(en_US.UTF-8 UTF-8\)/\1/' -e \
    's/^#\(ja_JP.UTF-8 UTF-8\)/\1/' /etc/locale.gen
  to_arch sed -i -e 's/^#\(ParallelDownloads\)/\1/' /etc/pacman.conf
  to_arch locale-gen
  echo 'LANG=en_US.UTF-8' > /mnt/etc/locale.conf
  echo 'KEYMAP=us' >> /mnt/etc/vconsole.conf
  echo 'archlinux' > /mnt/etc/hostname
  to_arch sed -e 's/^# \(%wheel ALL=(ALL:ALL) ALL\)/\1/' /etc/sudoers | EDITOR='tee' to_arch visudo &> /dev/null
}

networking() {
  local -r NET_INTERFACE="$(ip -br link show | grep ' UP ' | awk '{print $1}')"

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
DNS=192.168.1.202"

  echo "${HOSTS}" >> /mnt/etc/hosts

  case "${DE}" in
  'i3' | 'xfce')
    ln -sf /run/systemd/resolve/stub-resolv.conf /mnt/etc/resolv.conf
    echo "${WIRED}" > /mnt/etc/systemd/network/20-wired.network
    ;;
  *)
    ln -sf /run/NetworkManager/no-stub-resolv.conf /mnt/etc/resolv.conf
    ;;
  esac
}

create_user() {
  echo "root:${ROOT_PASSWORD}" | to_arch chpasswd
  to_arch useradd -m -G wheel -s /bin/bash "${USER_NAME}"
  echo "${USER_NAME}:${USER_PASSWORD}" | to_arch chpasswd
}

add_to_group() {
  for groups in docker vboxusers; do to_arch gpasswd -a "${USER_NAME}" "${groups}"; done
}

replacement() {
  case "${GPU}" in
  'nvidia')
    local -r ENVIRONMENT="GTK_IM_MODULE='fcitx5'
QT_IM_MODULE='fcitx5'
XMODIFIERS='@im=fcitx5'

LIBVA_DRIVER_NAME='vdpau'
VDPAU_DRIVER='nvidia'"
    ;;
  'intel')
    local -r ENVIRONMENT="GTK_IM_MODULE='fcitx5'
QT_IM_MODULE='fcitx5'
XMODIFIERS='@im=fcitx5'

LIBVA_DRIVER_NAME='i965'
VDPAU_DRIVER='va_gl'"
    ;;
  'amd')
    local -r ENVIRONMENT="GTK_IM_MODULE='fcitx5'
QT_IM_MODULE='fcitx5'
XMODIFIERS='@im=fcitx5'

LIBVA_DRIVER_NAME='radeonsi'
VDPAU_DRIVER='radeonsi'"
    ;;
  esac

  to_arch sed -i -e 's/^#\(NTP=\)/\1ntp.nict.jp/' -e \
    's/^#\(FallbackNTP=\).*/\1ntp1.jst.mfeed.ad.jp ntp2.jst.mfeed.ad.jp ntp3.jst.mfeed.ad.jp/' /etc/systemd/timesyncd.conf
  to_arch sed -i -e 's/^# \(--country\) France,Germany/\1 Japan/' -e \
    's/^--latest 5/# &/' -e \
    's/^\(--sort\) age/\1 rate/' /etc/xdg/reflector/reflector.conf
  # shellcheck disable=SC2016
  to_arch sed -i -e 's/\(-march=\)x86-64 -mtune=generic/\1skylake/' -e \
    's/^#\(MAKEFLAGS=\).*/\1"-j$(($(nproc)+1))"/' -e \
    's/^#\(BUILDDIR\)/\1/' -e \
    's/^\(COMPRESSXZ=\)(xz -c -z -)/\1(xz -c -z --threads=0 -)/' -e \
    's/^\(COMPRESSZST=\)(zstd -c -z -q -)/\1(zstd -c -z -q --threads=0 -)/' -e \
    's/^\(COMPRESSGZ=\)(gzip -c -f -n)/\1(pigz -c -f -n)/' -e \
    's/^\(COMPRESSBZ2=\)(bzip2 -c -f)/\1(lbzip2 -c -f)/' /etc/makepkg.conf
  to_arch sed -i -e 's/^#\(HandlePowerKey=\).*/\1reboot/' /etc/systemd/logind.conf
  to_arch sed -i -e 's/^#\(DefaultTimeoutStopSec=\).*/\110s/' /etc/systemd/system.conf
  to_arch sed -i -e 's/^#\(Color\)/\1/' /etc/pacman.conf
  echo -e '\n--age 24' >> /mnt/etc/xdg/reflector/reflector.conf
  echo "${ENVIRONMENT}" >> /mnt/etc/environment

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
  local -r NVIDIA_PARAMS='rw panic=180 i915.modeset=0 nouveau.modeset=0 nvidia_drm.modeset=1'
  local -r AMD_PARAMS='rw panic=180 i915.modeset=0'
  local -r INTEL_PARAMS='rw panic=180'

  local -r LOADER_CONF="$(
    cat << EOF
timeout      15
console-mode max
editor       no
EOF
  )"

  local -r NVIDIA_CONF="$(
    cat << EOF
title    Arch Linux
linux    /${VMLINUZ}
initrd   /${UCODE}
initrd   /${INITRAMFS}
options  root=PARTUUID=${ROOT_PARTUUID} ${NVIDIA_PARAMS} loglevel=3
EOF
  )"

  local -r NVIDIA_FALLBACK_CONF="$(
    cat << EOF
title    Arch Linux (fallback initramfs)
linux    /${VMLINUZ}
initrd   /${UCODE}
initrd   /${INITRAMFS_FALLBACK}
options  root=PARTUUID=${ROOT_PARTUUID} ${NVIDIA_PARAMS} debug
EOF
  )"

  local -r AMD_CONF="$(
    cat << EOF
title    Arch Linux
linux    /${VMLINUZ}
initrd   /${UCODE}
initrd   /${INITRAMFS}
options  root=PARTUUID=${ROOT_PARTUUID} ${AMD_PARAMS} loglevel=3
EOF
  )"

  local -r AMD_FALLBACK_CONF="$(
    cat << EOF
title    Arch Linux (fallback initramfs)
linux    /${VMLINUZ}
initrd   /${UCODE}
initrd   /${INITRAMFS_FALLBACK}
options  root=PARTUUID=${ROOT_PARTUUID} ${AMD_PARAMS} debug
EOF
  )"

  local -r INTEL_CONF="$(
    cat << EOF
title    Arch Linux
linux    /${VMLINUZ}
initrd   /${UCODE}
initrd   /${INITRAMFS}
options  root=PARTUUID=${ROOT_PARTUUID} ${INTEL_PARAMS} loglevel=3
EOF
  )"

  local -r INTEL_FALLBACK_CONF="$(
    cat << EOF
title    Arch Linux (fallback initramfs)
linux    /${VMLINUZ}
initrd   /${UCODE}
initrd   /${INITRAMFS_FALLBACK}
options  root=PARTUUID=${ROOT_PARTUUID} ${INTEL_PARAMS} debug
EOF
  )"

  echo "${LOADER_CONF}" > /mnt/boot/loader/loader.conf

  case "${GPU}" in
  'nvidia')
    echo "${NVIDIA_CONF}" > /mnt/boot/loader/entries/arch.conf
    echo "${NVIDIA_FALLBACK_CONF}" > /mnt/boot/loader/entries/arch_fallback.conf
    ;;
  'intel')
    echo "${INTEL_CONF}" > /mnt/boot/loader/entries/arch.conf
    echo "${INTEL_FALLBACK_CONF}" > /mnt/boot/loader/entries/arch_fallback.conf
    ;;
  'amd')
    echo "${AMD_CONF}" > /mnt/boot/loader/entries/arch.conf
    echo "${AMD_FALLBACK_CONF}" > /mnt/boot/loader/entries/arch_fallback.conf
    ;;
  esac
}

enable_services() {
  to_arch systemctl enable {iptables,docker,systemd-boot-update}.service {fstrim,reflector}.timer

  case "${DE}" in
  'i3')
    to_arch systemctl enable systemd-{networkd,resolved}.service
    ;;
  'xfce')
    to_arch systemctl enable {lightdm,systemd-{networkd,resolved}}.service
    ;;
  'gnome')
    to_arch systemctl enable {gdm,NetworkManager}.service
    ;;
  'kde')
    to_arch systemctl enable {sddm,NetworkManager}.service
    ;;
  esac
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
  add_to_group
  replacement
  boot_loader
  enable_services
}

main "${@}"
