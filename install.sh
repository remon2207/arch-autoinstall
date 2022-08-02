#!/usr/bin/env bash

packagelist="base \
base-devel \
linux-zen \
linux-zen-headers \
linux-firmware \
nano \
nano-syntax-highlighting \
sudo \
zsh \
curl \
wget \
fzf \
zip \
unzip \
gufw \
git \
cifs-utils \
openssh \
htop \
man \
ntfs-3g \
exfat-utils \
firefox \
firefox-i18n-ja \
wireplumber \
pipewire \
pipewire-pulse \
pavucontrol \
xdg-user-dirs-gtk \
noto-fonts \
noto-fonts-cjk \
noto-fonts-emoji \
fcitx5 \
fcitx5-im \
fcitx5-mozc \
gnome-keyring \
qt5ct \
kvantum \
docker \
docker-compose \
evince \
gvfs \
github-cli \
discord \
neofetch \
tree \
virtualbox \
virtualbox-host-dkms \
virtualbox-guest-iso \
starship \
lsd \
rsync \
reflector \
xorg-server \
xorg-xinit \
gsmartcontrol \
gparted"

if [ ${#} -lt 8 ] ; then
    echo "Usage:"
    echo "install.sh <disk> <microcode: intel | amd> <DE: xfce | gnome | kde> <GPU: nvidia | amd-dgpu | intel | amd-igpu> <HostName> <UserName> <userPasword> <rootPassword>"
    exit
fi

# intel-ucode or amd-ucode
if [ ${2} = "intel" ] ; then
    packagelist="${packagelist} intel-ucode"
elif [ ${2} = "amd" ] ; then
    packagelist="${packagelist} amd-ucode"
fi

# desktop
if [ ${3} = "xfce" ] ; then
    packagelist="${packagelist} \
    xfce4 \
    xfce4-goodies \
    arc-gtk-theme \
    papirus-icon-theme \
    lightdm \
    lightdm-gtk-greeter \
    lightdm-gtk-greeter-settings \
    xarchiver"
elif [ ${3} = "gnome" ] ; then
    packagelist="${packagelist} \
    gdm \
    gnome-control-center \
    gnome-shell \
    gnome-terminal \
    gnome-tweaks \
    gnome-themes-extra \
    gedit \
    mutter \
    nautilus \
    dconf-editor \
    audacious \
    eog \
    file-roller \
    gnome-backgrounds"
elif [ ${3} = "kde" ] ; then
    packagelist="${packagelist} \
    plasma-meta \
    lightdm \
    lightdm-gtk-greeter \
    lightdm-gtk-greeter-settings"
fi

if [ ${4} = "nvidia" ] ; then
    packagelist="${packagelist} nvidia-dkms nvidia-settings"
elif [ ${4} = "amd-dgpu" ] ; then
    packagelist="${packagelist} vulkan-radeon"
elif [ ${4} = "intel" ] ; then
    packagelist="${packagelist} xorg-server xorg-apps"
elif [ ${4} = "amd-igpu" ] ; then
    packagelist="${packagelist} xf86-video-amdgpu"
fi

# loadkeys jp106
timedatectl set-ntp true

# partitioning
sgdisk -Z ${1}
sgdisk -n 0::+512M -t 0:ef00 -c 0:"EFI System" ${1}
#sgdisk -d 3 $1
#sgdisk -d 2 $1
sgdisk -n 0::+350G -t 0:8300 -c 0:"Linux filesystem" ${1}
sgdisk -n 0:: -t 0:8300 -c 0:"Linux filesystem" ${1}
# sgdisk -n 0:: -t 0:8200 -c 0:"Linux swap" $1

# format
mkfs.fat -F 32 ${1}1
mkfs.ext4 ${1}2
# mkswap ${1}4
# swapon ${1}4
mkfs.ext4 ${1}3

# mount
mount ${1}2 /mnt
mkdir /mnt/boot
mount ${1}1 /mnt/boot
mkdir /mnt/home
mount ${1}3 /mnt/home

# installing
reflector --country Japan --sort rate --save /etc/pacman.d/mirrorlist
pacman -Sy --noconfirm archlinux-keyring
pacstrap /mnt ${packagelist}

# configure
# genfstab -U /mnt >> /mnt/etc/fstab
genfstab -t PARTUUID /mnt >> /mnt/etc/fstab
# arch-chroot /mnt loadkeys jp106
arch-chroot /mnt ln -sf /usr/share/zoneinfo/Asia/Tokyo /etc/localtime
arch-chroot /mnt hwclock --systohc --utc
arch-chroot /mnt sed -i "s/#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/" /etc/locale.gen
arch-chroot /mnt sed -i "s/#ja_JP.UTF-8 UTF-8/ja_JP.UTF-8 UTF-8/" /etc/locale.gen
arch-chroot /mnt locale-gen
echo "LANG=en_US.UTF-8" > /mnt/etc/locale.conf
echo "KEYMAP=us" > /mnt/etc/vconsole.conf
echo ${5} > /mnt/etc/hostname
arch-chroot /mnt sh -c "echo '%wheel ALL=(ALL:ALL) ALL' | EDITOR='tee -a' visudo"
arch-chroot /mnt sh -c "echo 'Defaults editor=/usr/bin/nano' | EDITOR='tee -a' visudo"

ip_address=$(ip -4 a show enp6s0 | grep -oP "(?<=inet\s)\d+(\.\d+){3}")
echo -e "127.0.0.1       localhost\n\
::1             localhost\n\
${ip_address}    ${5}.localdomain        ${5}" >> /mnt/etc/hosts

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
arch-chroot /mnt useradd -m -G wheel -s /bin/bash ${6}

echo "Password for ${6}"
echo "$6:$7" | arch-chroot /mnt chpasswd

echo -e "GTK_IM_MODULE=fcitx5\n\
QT_IM_MODULE=fcitx5\n\
XMODIFIERS=@im=fcitx5" >> /mnt/etc/environment
echo "LANG=ja_JP.UTF-8" > /mnt/etc/locale.conf

arch-chroot /mnt usermod -aG docker ${6}
arch-chroot /mnt gpasswd -a ${6} vboxusers

arch-chroot /mnt systemctl enable docker.service
arch-chroot /mnt systemctl enable fstrim.timer
arch-chroot /mnt systemctl enable ufw.service

arch-chroot /mnt sed -i "s/^#NTP=/NTP=0.asia.pool.ntp.org 1.asia.pool.ntp.org 2.asia.pool.ntp.org 3.asia.pool.ntp.org/" /etc/systemd/timesyncd.conf
arch-chroot /mnt sed -i "s/^#FallbackNTP/FallbackNTP/" /etc/systemd/timesyncd.conf
arch-chroot /mnt sed -i "s/-march=x86-64 -mtune=generic/-march=native/" /etc/makepkg.conf
arch-chroot /mnt sed -i 's/^#MAKEFLAGS="-j2"/MAKEFLAGS="-j$(($(nproc)+1))"/' /etc/makepkg.conf
arch-chroot /mnt sed -i "s/^#BUILDDIR/BUILDDIR/" /etc/makepkg.conf
arch-chroot /mnt sed -i "s/COMPRESSXZ=(xz -c -z -)/COMPRESSXZ=(xz -c -z --threads=0 -)/" /etc/makepkg.conf
arch-chroot /mnt sed -i "s/^#DefaultTimeoutStopSec=90s/DefaultTimeoutStopSec=10s/" /etc/systemd/system.conf
arch-chroot /mnt sed -i "s/^icolor brightnormal/## icolor brightnormal/" /usr/share/nano-syntax-highlighting/nanorc.nanorc

if [ ${3} = "xfce" ] ; then
    arch-chroot /mnt systemctl enable lightdm
elif [ ${3} = "gnome" ] ; then
    arch-chroot /mnt systemctl enable gdm
elif [ ${3} = "kde" ] ; then
    arch-chroot /mnt systemctl enable lightdm
fi

# grub
#arch-chroot /mnt grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=grub --recheck
#arch-chroot /mnt mkdir /boot/EFI/boot
#arch-chroot /mnt cp /boot/EFI/grub/grubx64.efi /boot/EFI/Boot/bootx64.efi
#arch-chroot /mnt sed -i -e '/^GRUB_TIMEOUT=/c\GRUB_TIMEOUT=30' -e '/^GRUB_CMDLINE_LINUX_DEFAULT=/c\GRUB_CMDLINE_LINUX_DEFAULT="loglevel=3 nomodeset nouveau.modeset=0"' -e '/^GRUB_GFXMODE=/c\GRUB_GFXMODE=1920x1080-24' -e '/^GRUB_DISABLE_OS_PROBER=/c\GRUB_DISABLE_OS_PROBER=false' /etc/default/grub
#arch-chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg

# systemd-boot
arch-chroot /mnt bootctl --path=/boot install
echo -e "default    arch\n\
timeout    10\n\
console-mode max\n\
editor     no" >> /mnt/boot/loader/loader.conf

root_partuuid=$(blkid -s PARTUUID -o value ${1}2)

echo -e "title    Arch Linux\n\
linux    /vmlinuz-linux-zen\n\
initrd   /intel-ucode.img\n\
initrd   /initramfs-linux-zen.img\n\
options  root=PARTUUID=${root_partuuid} rw loglevel=3 panic=180 nomodeset i915.modeset=0 nouveau.modeset=0 nvidia-drm.modeset=1" >> /mnt/boot/loader/entries/arch.conf

arch-chroot /mnt systemctl enable systemd-boot-update.service
