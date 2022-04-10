#!/bin/sh

packagelist='base base-devel linux-zen linux-zen-headers linux-firmware vi sudo grub dosfstools efibootmgr zsh curl wget bat fzf gufw git cifs-utils openssh htop man netctl os-prober ntfs-3g firefox firefox-i18n pulseaudio pavucontrol lsd xdg-user-dirs-gtk noto-fonts noto-fonts-cjk noto-fonts-emoji noto-fonts-extra adobe-source-han-sans-jp-fonts fcitx-mozc fcitx-im fcitx-configtool xorg-server xorg-xinit xorg-apps neovim'

if [ $# -lt 8 ] ; then
    echo 'Usage:'
    echo 'install.sh <DISK> <microcode:intel|amd|-> <DE:xfce|gnome|mate|cinnamon|kde|i3> <GPU:NVIDIA|AMD> <HostName> <UserName> <userPasword> <rootPassword>'
    exit
fi




# intel-ucode or amd-ucode
if [ "$2" = "intel" ] ; then
    packagelist="$packagelist intel-ucode"
elif [ "$2" = "amd" ] ; then
    packagelist="$packagelist amd-ucode"
elif [ "$2" = "-" ] ; then
    packagelist="$packagelist"
fi

# desktop
if [ "$3" = "xfce" ] ; then
    packagelist="$packagelist lightdm lightdm-gtk-greeter xfce4 xfce4-goodies xarchiver arc-gtk-theme papirus-icon-theme"
elif [ "$3" = "gnome" ] ; then
    packagelist="$packagelist gdm gnome xarchiver arc-gtk-theme papirus-icon-theme"
elif [ "$3" = "mate" ] ; then
    packagelist="$packagelist mate mate-extra xarchiver arc-gtk-theme papirus-icon-theme"
elif [ "$3" = "cinnamon" ] ; then
    packagelist="$packagelist cinnamon xarchiver arc-gtk-theme papirus-icon-theme"
elif [ "$3" = "kde" ] ; then
    packagelist="$packagelist plasma alacritty arc-gtk-theme papirus-icon-theme"
elif [ "$3" = "i3" ] ; then
    packagelist="$packagelist lightdm lightdm-gtk-greeter alacritty i3-gaps i3blocks i3lock i3status dmenu rofi mpd ncmpcpp ranger feh picom"
fi

if [ "$4" = "nvidia" ] ; then
    packagelist=$packagelist nvidia-dkms nvidia-settings
elif [ "$4" = "amd" ] ; then
    packagelist=$packagelist 
fi

loadkeys jp106
timedatectl set-ntp true

# partitioning
# sgdisk -Z $1
# sgdisk -n 0::+512M -t 0:ef00 -c 0:"EFI System" $1
sgdisk -d 3 $1
sgdisk -d 2 $1
sgdisk -n 0::+232G -t 0:8300 -c 0:"Linux filesystem" $1
sgdisk -n 0::+232G -t 0:8300 -c 0:"Linux filesystem" $1
# sgdisk -n 0::+16G -t 0:8200 -c 0:"Linux swap" $1

# format
# mkfs.vfat -F32 ${1}1
mkfs.ext4 ${1}2
# mkswap ${1}3
# swapon ${1}3
mkfs.ext4 ${1}3

# mount
mount ${1}2 /mnt
mkdir -p /mnt/boot
mount ${1}1 /mnt/boot
mkdir /mnt/home
mount ${1}3 /mnt/home

# installing
reflector --country Japan --sort rate --save /etc/pacman.d/mirrorlist
pacstrap /mnt $packagelist

# configure
genfstab -U /mnt >> /mnt/etc/fstab
arch-chroot /mnt loadkeys jp106
arch-chroot /mnt ln -sf /usr/share/zoneinfo/Asia/Tokyo /etc/localtime
arch-chroot /mnt hwclock --systohc --utc
arch-chroot /mnt sed -i -e 's/#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/g' -e 's/#ja_JP.UTF-8 UTF-8/ja_JP.UTF-8 UTF-8/g' /etc/locale.gen
arch-chroot /mnt locale-gen
echo LANG=en_US.UTF-8 > /mnt/etc/locale.conf
echo KEYMAP=jp106 > /mnt/etc/vconsole.conf
echo $4 > /mnt/etc/hostname
arch-chroot /mnt sh -c "echo '%wheel ALL=(ALL) ALL' | EDITOR='tee -a' visudo"

ip_address=$(ip -4 a show enp6s0 | grep -oP '(?<=inet\s)\d+(\.\d+){3}')
echo -e "127.0.0.1       localhost\n::1             localhost\n${ip_address}    $4.localdomain        $4" >> /mnt/etc/hosts
arch-chroot /mnt cp /etc/netctl/examples/ethernet-static /etc/netctl/enp6s0
dns="'8.8.8.8' '8.8.4.4'"
google_dns="$dns"
arch-chroot /mnt sed -i -e "/^Interface/s/eth0/enp6s0/" -e "/^Address/c\Address=('${ip_address}/24')" -e "/^DNS/c\DNS=(${google_dns})" /etc/netctl/enp6s0
arch-chroot /mnt netctl enable enp6s0

arch-chroot /mnt sh -c "echo '%wheel ALL=(ALL) ALL' | EDITOR='tee -a' visudo"
#sed -i -e "s/# %wheel ALL=(ALL) ALL/%wheel ALL=(ALL) ALL/" /mnt/etc/sudoers
echo ------------------------------------------------------------------
echo "Password for root"
# arch-chroot /mnt passwd
echo "root:$7" | chpasswd
arch-chroot /mnt useradd -m -g users -G wheel -s /bin/bash $5

# echo "Password for $5"
# arch-chroot /mnt passwd $5
echo "$5:$6" | arch-chroot /mnt chpasswd

arch-chroot /mnt sudo -u $5 mkdir /home/$5/appimage
#arch-chroot /mnt sudo -u $5 wget -O /home/$5/appimage/nvim.appimage https://github.com/neovim/neovim/releases/download/stable/nvim.appimage
#arch-chroot /mnt sudo -u $5 chmod u+x /home/$5/appimage/nvim.appimage

echo -e "clear lock\nclear control\nkeycode 66 = Control_L\nadd control = Control_L Control_R" > /mnt/home/$5/.Xmodmap
arch-chroot /mnt chown $5:users /home/$5/.Xmodmap
arch-chroot /mnt chmod 644 /home/$5/.Xmodmap
arch-chroot /mnt sudo -u $5 xmodmap /home/$5/.Xmodmap

echo -e "export GTK_IM_MODULE=fcitx\nexport QT_IM_MODULE=fcitx\nexport XMODIFIERS=@im=fcitx" > /mnt/home/$5/.xprofile
arch-chroot /mnt chown $5:users /home/$5/.xprofile
arch-chroot /mnt chmod 644 /home/$5/.xprofile
arch-chroot /mnt mkdir /home/$5/git
arch-chroot /mnt chown $5:users /home/$5/git
arch-chroot /mnt chmod 755 /home/$5/git
arch-chroot /mnt sed -i -e 's/en_US.UTF-8 UTF-8/#en_US.UTF-8 UTF-8/g' /etc/locale.gen
arch-chroot /mnt locale-gen
echo LANG=ja_JP.UTF-8 > /mnt/etc/locale.conf
git clone https://github.com/remon2207/dotfiles.git /mnt/home/$5/git/dotfiles
arch-chroot /mnt chown -R $5:users /home/$5/git/dotfiles
arch-chroot /mnt sudo -u $5 ./home/$5/git/dotfiles/arch_setup.sh
arch-chroot /mnt sudo -u $5 ./home/$5/git/dotfiles/install.sh

git clone --depth=1 https://github.com/adi1090x/polybar-themes.git /mnt/home/$5/git/polybar-themes
arch-chroot /mnt chown -R $5:users /home/$5/git/polybar-themes
arch-chroot /mnt chmod +x /home/$5/git/polybar-themes/setup.sh
arch-chroot /mnt sudo -u $5 ./home/$5/git/polybar-themes/setup.sh

if [ $3 = "xfce" ] ; then
    arch-chroot /mnt systemctl enable lightdm
elif [ $3 = "gnome" ] ; then
    arch-chroot /mnt systemctl enable gdm
elif [ $3 = "mate" ] ; then
    arch-chroot /mnt systemctl enable lightdm
elif [ $3 = "cinnamon" ] ; then
    arch-chroot /mnt systemctl enable lightdm
elif [ $3 = "kde" ] ; then
    arch-chroot /mnt systemctl enable sddm
elif [ $3 = "i3" ] ; then
    arch-chroot /mnt systemctl enable lightdm
fi

arch-chroot /mnt grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=grub
arch-chroot /mnt mkdir /boot/EFI/boot
arch-chroot /mnt cp /boot/EFI/grub/grubx64.efi /boot/EFI/Boot/bootx64.efi
arch-chroot /mnt sed -i -e '/^GRUB_TIMEOUT=/c\GRUB_TIMEOUT=30' -e '/^GRUB_CMDLINE_LINUX_DEFAULT=/c\GRUB_CMDLINE_LINUX_DEFAULT="loglevel=3 nomodeset nouveau.modeset=0"' -e '/^GRUB_GFXMODE=/c\GRUB_GFXMODE=1920x1080-24' -e '/^GRUB_DISABLE_OS_PROBER=/c\GRUB_DISABLE_OS_PROBER=false' /etc/default/grub
arch-chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg

umount -R /mnt
systemctl reboot
