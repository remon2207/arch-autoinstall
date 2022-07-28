#!/usr/bin/env bash

packagelist='base base-devel linux-zen linux-zen-headers linux-firmware vi nano nano-syntax-highlighting sudo zsh curl wget fzf zip unzip gufw git cifs-utils openssh htop man ntfs-3g exfat-utils firefox firefox-i18n-ja wireplumber pipewire pipewire-pulse pavucontrol rustup xdg-user-dirs-gtk noto-fonts noto-fonts-cjk noto-fonts-emoji fcitx5 fcitx5-im fcitx5-mozc gnome-keyring qt5ct kvantum docker docker-compose evince gvfs github-cli xarchiver discord neofetch xarchiver'

if [ $# -lt 8 ] ; then
    echo 'Usage:'
    echo 'install.sh <DISK> <microcode: intel | amd> <DE: xfce | gnome | mate | cinnamon | kde | i3> <GPU: NVIDIA | AMD> <HostName> <UserName> <userPasword> <rootPassword>'
    exit
fi

# intel-ucode or amd-ucode
if [ "$2" = "intel" ] ; then
    packagelist="$packagelist intel-ucode"
elif [ "$2" = "amd" ] ; then
    packagelist="$packagelist amd-ucode"
fi

# desktop
if [ "$3" = "xfce" ] ; then
    packagelist="$packagelist lightdm lightdm-gtk-greeter lightdm-gtk-greeter-settings xfce4 xfce4-goodies xarchiver arc-gtk-theme papirus-icon-theme"
elif [ "$3" = "gnome" ] ; then
    packagelist="$packagelist gdm gnome-control-center gnome-shell gnome-terminal mutter nautilus dconf-editor gnome-tweaks audacious gnome-themes-extra"
elif [ "$3" = "mate" ] ; then
    packagelist="$packagelist mate mate-extra xarchiver lightdm lightdm-gtk-greeter alacritty arc-gtk-theme papirus-icon-theme"
elif [ "$3" = "cinnamon" ] ; then
    packagelist="$packagelist cinnamon xarchiver arc-gtk-theme papirus-icon-theme"
elif [ "$3" = "kde" ] ; then
    packagelist="$packagelist plasma lightdm lightdm-gtk-greeter alacritty arc-gtk-theme papirus-icon-theme"
elif [ "$3" = "i3" ] ; then
    packagelist="$packagelist lightdm lightdm-gtk-greeter alacritty i3-gaps i3blocks i3lock i3status dmenu rofi mpd ncmpcpp ranger feh picom"
fi

if [ "$4" = "nvidia" ] ; then
    packagelist="$packagelist nvidia-dkms nvidia-settings"
elif [ "$4" = "amd-dgpu" ] ; then
    packagelist="$packagelist vulkan-radeon"
elif [ "$4" = "intel" ] ; then
    packagelist="$packagelist xorg-server xorg-apps"
elif [ "$4" = "amd-igpu" ] ; then
    packagelist="$packagelist xf86-video-amdgpu"
fi

# loadkeys jp106
timedatectl set-ntp true

# partitioning
sgdisk -Z $1
sgdisk -n 0::+512M -t 0:ef00 -c 0:"EFI System" $1
#sgdisk -d 3 $1
#sgdisk -d 2 $1
sgdisk -n 0::+350G -t 0:8300 -c 0:"Linux filesystem" $1
sgdisk -n 0:: -t 0:8300 -c 0:"Linux filesystem" $1
# sgdisk -n 0:: -t 0:8200 -c 0:"Linux swap" $1

# format
mkfs.fat -F 32 ${1}1
mkfs.ext4 ${1}2
# mkswap ${1}4
# swapon ${1}4
mkfs.ext4 ${1}3

# mount
mount ${1}2 /mnt
mkdir -p /mnt/boot
mount ${1}1 /mnt/boot
mkdir /mnt/home
mount ${1}3 /mnt/home

# installing
reflector --country Japan --sort rate --save /etc/pacman.d/mirrorlist
# pacman -Sy --noconfirm archlinux-keyring && pacman -Su --noconfirm
pacman -Sy --noconfirm archlinux-keyring
pacstrap /mnt $packagelist

# configure
genfstab -U /mnt >> /mnt/etc/fstab
# arch-chroot /mnt loadkeys jp106
arch-chroot /mnt ln -sf /usr/share/zoneinfo/Asia/Tokyo /etc/localtime
arch-chroot /mnt hwclock --systohc --utc
arch-chroot /mnt sed -i 's/#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/g' /etc/locale.gen
arch-chroot /mnt sed -i 's/#ja_JP.UTF-8 UTF-8/ja_JP.UTF-8 UTF-8/g' /etc/locale.gen
arch-chroot /mnt locale-gen
echo LANG=en_US.UTF-8 > /mnt/etc/locale.conf
echo KEYMAP=us > /mnt/etc/vconsole.conf
echo $5 > /mnt/etc/hostname
arch-chroot /mnt sh -c "echo '%wheel ALL=(ALL:ALL) ALL' | EDITOR='tee -a' visudo"

ip_address=$(ip -4 a show enp6s0 | grep -oP '(?<=inet\s)\d+(\.\d+){3}')
echo -e "127.0.0.1       localhost\n::1             localhost\n${ip_address}    $5.localdomain        $5" >> /mnt/etc/hosts

arch-chroot /mnt systemctl enable systemd-{networkd,resolved}.service
echo -e "[Match]\n\
Name=enp6s0\n\
\n\
[Network]\n\
Address=${ip_address}/24\n\
Gateway=192.168.1.1\n\
DNS=8.8.8.8\n\
DNS=8.8.4.4" > /mnt/etc/systemd/network/20-wired.network

ln -sf /run/systemd/resolve/stub-resolv.conf /mnt/etc/resolv.conf

echo ------------------------------------------------------------------
echo "Password for root"
# arch-chroot /mnt passwd
echo "root:$8" | arch-chroot /mnt chpasswd
arch-chroot /mnt useradd -m -G wheel -s /bin/bash $6

echo "Password for ${6}"
echo "$6:$7" | arch-chroot /mnt chpasswd

echo -e "GTK_IM_MODULE=fcitx5\nQT_IM_MODULE=fcitx5\nXMODIFIERS=@im=fcitx5" >> /mnt/etc/environment
echo LANG=ja_JP.UTF-8 > /mnt/etc/locale.conf

arch-chroot /mnt cp -r /usr/share/pipewire /etc/pipewire

arch-chroot /mnt usermod -aG docker $6
arch-chroot /mnt systemctl enable docker.service

arch-chroot /mnt systemctl enable fstrim.timer

arch-chroot /mnt sed -i "s/^#NTP=/NTP=0.asia.pool.ntp.org 1.asia.pool.ntp.org 2.asia.pool.ntp.org 3.asia.pool.ntp.org/" /etc/systemd/timesyncd.conf
arch-chroot /mnt sed -i "s/^#FallbackNTP/FallbackNTP/" /etc/systemd/timesyncd.conf

if [ $3 = "xfce" ] ; then
    arch-chroot /mnt systemctl enable lightdm
elif [ $3 = "gnome" ] ; then
    arch-chroot /mnt systemctl enable gdm
elif [ $3 = "mate" ] ; then
    arch-chroot /mnt systemctl enable lightdm
elif [ $3 = "cinnamon" ] ; then
    arch-chroot /mnt systemctl enable lightdm
elif [ $3 = "kde" ] ; then
    arch-chroot /mnt systemctl enable lightdm
elif [ $3 = "i3" ] ; then
    arch-chroot /mnt systemctl enable lightdm
fi

# grub
#arch-chroot /mnt grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=grub
#arch-chroot /mnt mkdir /boot/EFI/boot
#arch-chroot /mnt cp /boot/EFI/grub/grubx64.efi /boot/EFI/Boot/bootx64.efi
#arch-chroot /mnt sed -i -e '/^GRUB_TIMEOUT=/c\GRUB_TIMEOUT=30' -e '/^GRUB_CMDLINE_LINUX_DEFAULT=/c\GRUB_CMDLINE_LINUX_DEFAULT="loglevel=3 nomodeset nouveau.modeset=0"' -e '/^GRUB_GFXMODE=/c\GRUB_GFXMODE=1920x1080-24' -e '/^GRUB_DISABLE_OS_PROBER=/c\GRUB_DISABLE_OS_PROBER=false' /etc/default/grub
#arch-chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg

# systemd-boot
arch-chroot /mnt bootctl --path=/boot install
echo -e "default    arch\ntimeout    10\nconsole-mode max\neditor     no" >> /mnt/boot/loader/loader.conf
root_partuuid=`blkid -s PARTUUID -o value ${1}2`
echo -e "title    Arch Linux\nlinux    /vmlinuz-linux-zen\ninitrd   /intel-ucode.img\ninitrd   /initramfs-linux-zen.img\noptions  root=PARTUUID=${root_partuuid} rw loglevel=3 panic=180 nomodeset i915.modeset=0 nouveau.modeset=0 nvidia-drm.modeset=1" >> /mnt/boot/loader/entries/arch.conf
arch-chroot /mnt systemctl enable systemd-boot-update.service

# efi_uuid=`blkid -s UUID -o value ${1}1`
# efi_uuid=`cat /mnt/etc/fstab | grep -E '^UUID' | awk -F '=' '{print $2}' | awk -F ' ' '{print $1}'`
root_uuid=`blkid -s UUID -o value ${1}2`
home_uuid=`blkid -s UUID -o value ${1}3`
# swap_uuid=`blkid -s UUID -o value ${1}4`

# efi_partuuid=`blkid -s PARTUUID -o value ${1}1`
root_partuuid=`blkid -s PARTUUID -o value ${1}2`
home_partuuid=`blkid -s PARTUUID -o value ${1}3`
# swap_partuuid=`blkid -s PARTUUID -o value ${1}4`

# arch-chroot /mnt sed -i "s/UUID=${efi_uuid}/PARTUUID=${efi_partuuid}/" /etc/fstab
arch-chroot /mnt sed -i "s/UUID=${root_uuid}/PARTUUID=${root_partuuid}/" /etc/fstab
arch-chroot /mnt sed -i "s/UUID=${home_uuid}/PARTUUID=${home_partuuid}/" /etc/fstab
# arch-chroot /mnt sed -i "s/UUID=${swap_uuid}/PARTUUID=${swap_partuuid}/" /etc/fstab


echo ''
echo '==================================='
echo 'Change UUID in /etc/fstab to PARTUUID'
echo '==================================='
echo ''
