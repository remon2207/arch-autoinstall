#!/usr/bin/env bash

set -eu

if [[ $# -eq 0 ]]; then
  cat << EOF
Usage:

# ./install.sh <disk>
  <microcode:intel | amd>
  <DE:i3 | xfce | gnome | kde>
  <GPU:nvidia | amd | intel>
  <HostName>
  <UserName>
  <userPasword>
  <rootPassword>
  <partition-table-destroy:yes | no-exclude-efi | no-root-only | skip>
  <root_partition_size:Numbers only (GiB)>
EOF
  exit 1
fi

packagelist="base \
  base-devel \
  linux-zen \
  linux-zen-headers \
  linux-firmware \
  libva-vdpau-driver \
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
  nftables \
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
  eza \
  profile-sync-daemon \
  vivaldi \
  vivaldi-ffmpeg-codecs \
  pigz \
  pv \
  nfs-utils"

net_interface=$(ip -br link show | grep ' UP ' | awk '{print $1}')

disk="${1}"
microcode="${2}"
de="${3}"
gpu="${4}"
hostname="${5}"
username="${6}"
user_password="${7}"
root_password="${8}"
partition_table="${9}"
root_size="${10}"

check_variables() {
  if [[ "${microcode}" != 'intel' ]] && [[ "${microcode}" != 'amd' ]]; then
    echo 'microcode error'
    exit 1
  elif [[ "${de}" != 'i3' ]] && [[ "${de}" != 'xfce' ]] && [[ "${de}" != 'gnome' ]] && [[ "${de}" != 'kde' ]]; then
    echo 'de error'
    exit 1
  elif [[ "${gpu}" != 'nvidia' ]] && [[ "${gpu}" != 'amd' ]] && [[ "${gpu}" != 'intel' ]]; then
    echo 'gpu error'
    exit 1
  elif [[ "${partition_table}" != 'yes' ]] && [[ "${partition_table}" != 'no-exclude-efi' ]] && [[ "${partition_table}" != 'no-root-only' ]] && [[ "${partition_table}" != 'skip' ]]; then
    echo 'partition table error'
    exit 1
  fi
}

selection_arguments() {
  # intel-ucode or amd-ucode
  if [[ "${microcode}" == 'intel' ]]; then
    packagelist="${packagelist} intel-ucode"
  elif [[ "${microcode}" == 'amd' ]]; then
    packagelist="${packagelist} amd-ucode"
  fi

  # DE
  if [[ "${de}" == 'i3' ]]; then
    packagelist="${packagelist} \
      i3-wm \
      i3lock \
      rofi \
      polybar \
      xautolock \
      polkit \
      scrot \
      lxappearance-gtk3 \
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
      ranger"
  elif [[ "${de}" == 'xfce' ]]; then
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
  elif [[ "${de}" == 'gnome' ]]; then
    packagelist="${packagelist} \
      gnome-control-center \
      gnome-shell \
      gnome-tweaks \
      gnome-themes-extra \
      gnome-terminal \
      gnome-keyring \
      gnome-backgrounds \
      gnome-calculator \
      gedit \
      mutter \
      file-roller \
      nautilus \
      gdm \
      gvfs \
      dconf-editor \
      eog \
      networkmanager \
      gnome-shell-extension-appindicator"
  elif [[ "${de}" == 'kde' ]]; then
    packagelist="${packagelist} \
      plasma-meta \
      packagekit-qt5 \
      dolphin \
      konsole \
      gwenview \
      spectacle \
      kate"
  fi

  if [[ "${gpu}" == 'nvidia' ]]; then
    packagelist="${packagelist} nvidia-dkms nvidia-settings"
  elif [[ "${gpu}" == 'amd' ]]; then
    packagelist="${packagelist} xf86-video-amdgpu libva-mesa-driver mesa-vdpau"
  elif [[ "${gpu}" == 'intel' ]]; then
    echo 'Already declared'
  fi
}

time_setting() {
  timedatectl set-ntp true
}

partitioning() {
  if [[ "${partition_table}" == 'yes' ]]; then
    sgdisk -Z ${disk}
    sgdisk -n 0::+512M -t 0:ef00 -c '0:EFI system partition' ${disk}
    sgdisk -n "0::+${root_size}G" -t 0:8300 -c '0:Linux filesystem' ${disk}
    sgdisk -n 0:: -t 0:8300 -c '0:Linux filesystem' ${disk}

    # format
    mkfs.fat -F 32 "${disk}1"
    mkfs.ext4 "${disk}2"
    mkfs.ext4 "${disk}3"
  elif [[ "${partition_table}" == 'no-exclude-efi' ]]; then
    sgdisk -d 3 ${disk}
    sgdisk -d 2 ${disk}
    sgdisk -n "0::+${root_size}G" -t 0:8300 -c '0:EFI system partition' ${disk}
    sgdisk -n 0:: -t 0:8300 -c '0:Linux filesystem' ${disk}

    # format
    mkfs.ext4 "${disk}2"
    mkfs.ext4 "${disk}3"
  elif [[ "${partition_table}" == 'no-root-only' ]]; then
    # format
    mkfs.ext4 "${disk}2"
  elif [[ "${partition_table}" == 'skip' ]]; then
    echo 'Skip partitioning'

    # format
    mkfs.ext4 "${disk}2"
    mkfs.ext4 "${disk}3"
  fi

  # mount
  mount "${disk}2" /mnt
  mount -m -o fmask=0077,dmask=0077 "${disk}1" /mnt/boot
  mount -m "${disk}3" /mnt/home
}

installation() {
  reflector --country Japan,Australia --age 24 --protocol https --sort rate --save /etc/pacman.d/mirrorlist
  pacman -Sy --noconfirm archlinux-keyring
  pacstrap /mnt ${packagelist}
  genfstab -t PARTUUID /mnt >> /mnt/etc/fstab
}

configuration() {
  arch-chroot /mnt ln -sf /usr/share/zoneinfo/Asia/Tokyo /etc/localtime
  arch-chroot /mnt hwclock --systohc --utc
  arch-chroot /mnt sed -i 's/#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
  arch-chroot /mnt sed -i 's/#ja_JP.UTF-8 UTF-8/ja_JP.UTF-8 UTF-8/' /etc/locale.gen
  arch-chroot /mnt sed -i 's/^#ParallelDownloads/ParallelDownloads/' /etc/pacman.conf
  arch-chroot /mnt locale-gen
  echo 'LANG=en_US.UTF-8' > /mnt/etc/locale.conf
  echo 'KEYMAP=us' > /mnt/etc/vconsole.conf
  echo "${hostname}" > /mnt/etc/hostname
  arch-chroot /mnt sh -c "echo '%wheel ALL=(ALL:ALL) ALL' | EDITOR='tee -a' visudo"
}

networking() {
  ip_address=$(ip -4 a show "${net_interface}" | grep '192.168' | awk '{print $2}' | cut -d '/' -f 1)
  cat << EOF >> /mnt/etc/hosts
127.0.0.1       localhost
::1             localhost
${ip_address}    ${hostname}.home    ${hostname}
EOF

  if [[ "${de}" != 'gnome' ]] && [[ "${de}" != 'kde' ]]; then
    arch-chroot /mnt systemctl enable systemd-{networkd,resolved}.service
    cat << EOF > /mnt/etc/systemd/network/20-wired.network
[Match]
Name=${net_interface}

[Network]
DHCP=yes
DNS=192.168.1.202
EOF
  elif [[ "${de}" != 'i3' ]]; then
    arch-chroot /mnt systemctl enable systemd-resolved.service
    ln -sf /run/NetworkManager/no-stub-resolv.conf /mnt/etc/resolv.conf
  else
    ln -sf /run/systemd/resolve/stub-resolv.conf /mnt/etc/resolv.conf
  fi
}

create_user() {
  echo "root:${root_password}" | arch-chroot /mnt chpasswd
  arch-chroot /mnt useradd -m -G wheel -s /bin/bash ${username}
  echo "${username}:${user_password}" | arch-chroot /mnt chpasswd
}

add_to_group() {
  arch-chroot /mnt gpasswd -a ${username} docker
}

replacement() {
  arch-chroot /mnt sed -i 's/^#NTP=/NTP=ntp.nict.jp/' /etc/systemd/timesyncd.conf
  arch-chroot /mnt sed -i 's/^#FallbackNTP=/FallbackNTP=ntp1.jst.mfeed.ad.jp ntp2.jst.mfeed.ad.jp ntp3.jst.mfeed.ad.jp/' /etc/systemd/timesyncd.conf
  arch-chroot /mnt sed -i 's/-march=x86-64 -mtune=generic/-march=native/' /etc/makepkg.conf
  arch-chroot /mnt sed -i 's/^#MAKEFLAGS="-j2"/MAKEFLAGS="-j$\(\($\(nproc\)+1\)\)"/' /etc/makepkg.conf
  arch-chroot /mnt sed -i 's/^#BUILDDIR/BUILDDIR/' /etc/makepkg.conf
  arch-chroot /mnt sed -i 's/COMPRESSXZ=(xz -c -z -)/COMPRESSXZ=(xz -c -z --threads=0 -)/' /etc/makepkg.conf
  arch-chroot /mnt sed -i 's/^#DefaultTimeoutStopSec=90s/DefaultTimeoutStopSec=10s/' /etc/systemd/system.conf
  arch-chroot /mnt sed -i 's/^#Color/Color/' /etc/pacman.conf
  arch-chroot /mnt sed -i 's/^# --country France,Germany/--country Japan,Australia/' /etc/xdg/reflector/reflector.conf
  arch-chroot /mnt sed -i 's/^--latest 5/# --latest 5/' /etc/xdg/reflector/reflector.conf
  arch-chroot /mnt sed -i 's/^--sort age/--sort rate/' /etc/xdg/reflector/reflector.conf
  cat << EOF >> /mnt/etc/xdg/reflector/reflector.conf

--age 24
EOF
  arch-chroot /mnt sed -i 's/^#HandlePowerKey=poweroff/HandlePowerKey=ignore/' /etc/systemd/logind.conf
  cat << EOF >> /mnt/etc/environment
GTK_IM_MODULE='fcitx5'
QT_IM_MODULE='fcitx5'
XMODIFIERS='@im=fcitx5'

LIBVA_DRIVER_NAME='nvidia'
VDPAU_DRIVER='nvidia'
EOF

  arch-chroot /mnt pacman -Syy
}

boot_loader() {
  arch-chroot /mnt bootctl install
  cat << EOF > /mnt/boot/loader/loader.conf
default      arch.conf
timeout      10
console-mode max
editor       no
EOF

  root_partuuid=$(blkid -s PARTUUID -o value "${disk}2")

  if [[ "${gpu}" == 'nvidia' ]]; then
    cat << EOF > /mnt/boot/loader/entries/arch.conf
title    Arch Linux
linux    /vmlinuz-linux-zen
initrd   /intel-ucode.img
initrd   /initramfs-linux-zen.img
options  root=PARTUUID=${root_partuuid} rw loglevel=3 panic=180 i915.modeset=0 nouveau.modeset=0 nvidia_drm.modeset=1
EOF
  elif [[ "${gpu}" == 'amd' ]]; then
    cat << EOF > /mnt/boot/loader/entries/arch.conf
title    Arch Linux
linux    /vmlinuz-linux-zen
initrd   /amd-ucode.img
initrd   /initramfs-linux-zen.img
options  root=PARTUUID=${root_partuuid} rw loglevel=3 panic=180
EOF
  elif [[ "${gpu}" == 'intel' ]]; then
    cat << EOF > /mnt/boot/loader/entries/arch.conf
title    Arch Linux
linux    /vmlinuz-linux-zen
initrd   /intel-ucode.img
initrd   /initramfs-linux-zen.img
options  root=PARTUUID=${root_partuuid} rw loglevel=3 panic=180
EOF
  fi

  cat << EOF > /mnt/boot/loader/entries/arch_fallback.conf
title    Arch Linux (Fallback)
linux    /vmlinuz-linux-zen
initrd   /intel-ucode.img
initrd   /initramfs-linux-zen-fallback.img
options  root=PARTUUID=${root_partuuid} rw panic=180 debug
EOF
}

enable_services() {
  arch-chroot /mnt systemctl enable docker.service
  arch-chroot /mnt systemctl enable fstrim.timer
  arch-chroot /mnt systemctl enable nftables.service
  arch-chroot /mnt systemctl enable reflector.timer
  arch-chroot /mnt systemctl enable systemd-boot-update.service

  if [[ "${de}" == 'xfce' ]]; then
    arch-chroot /mnt systemctl enable lightdm.service
  elif [[ "${de}" == 'gnome' ]]; then
    arch-chroot /mnt systemctl enable gdm.service
    arch-chroot /mnt systemctl enable NetworkManager.service
  elif [[ "${de}" == 'kde' ]]; then
    arch-chroot /mnt systemctl enable sddm.service
    arch-chroot /mnt systemctl enable NetworkManager.service
  fi
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

main "$@"
