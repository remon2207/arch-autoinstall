#!/bin/bash

packagelist='base base-devel linux-zen linux-zen-headers linux-firmware vi sudo intel-ucode grub dosfstools efibootmgr zsh curl wget bat ufw git cifs-utils openssh htop man memtest86+ dhcpcd os-prober'

if [ $# -lt 5 ] ; then
    echo 'Usage:'
#    echo 'install.sh <DISK> <microcode:intel|amd> <DE:xfce|gnome|mate|cinnamon|plasma> <HostName> <UserName>'
    echo 'install.sh <DISK> <DE:xfce|gnome|mate|cinnamon|plasma> <HostName> <UserName>'
    exit
fi




# intel-ucode or amd-ucode
#if [ "$2" = "intel" ] ; then
#    packagelist="$packagelist intel-ucode"
#elif [ "$2" = "amd" ] ; then
#    packagelist="$packagelist amd-ucode"
#fi

# desktop
desktop="xfce gnome mate cinnamon plasma"
if [ "$2" = "xfce" ] ; then
    packagelist="$packagelist xfce4 xfce4-goodies firefox pulseaudio pavucontrol lsd xarchiver arc-gtk-theme papirus-icon-theme wmctrl xdotool xdg-user-dirs noto-fonts noto-fonts-cjk noto-fonts-emoji noto-fonts-extra adobe-source-han-sans-jp-fonts otf-ipafont fcitx-mozc fcitx-im fcitx-configtool xorg-server xorg-xinit xorg-apps lightdm lightdm-gtk-greeter"
elif [ "$2" = "gnome" ] ; then
    packagelist="$packagelist gnome firefox pulseaudio pavucontrol lsd xarchiver arc-gtk-theme papirus-icon-theme wmctrl xdotool xdg-user-dirs noto-fonts noto-fonts-cjk noto-fonts-emoji noto-fonts-extra adobe-source-han-sans-jp-fonts otf-ipafont fcitx-mozc fcitx-im fcitx-configtool xorg-server xorg-xinit xorg-apps lightdm lightdm-gtk-greeter"
elif [ "$2" = "mate" ] ; then
    packagelist="$packagelist mate mate-extra firefox pulseaudio pavucontrol lsd xarchiver arc-gtk-theme papirus-icon-theme wmctrl xdotool xdg-user-dirs noto-fonts noto-fonts-cjk noto-fonts-emoji noto-fonts-extra adobe-source-han-sans-jp-fonts otf-ipafont fcitx-mozc fcitx-im fcitx-configtool xorg-server xorg-xinit xorg-apps lightdm lightdm-gtk-greeter"
elif [ "$2" = "cinnamon" ] ; then
    packagelist="$packagelist cinnamon firefox pulseaudio pavucontrol lsd xarchiver arc-gtk-theme papirus-icon-theme wmctrl xdotool xdg-user-dirs noto-fonts noto-fonts-cjk noto-fonts-emoji noto-fonts-extra adobe-source-han-sans-jp-fonts otf-ipafont fcitx-mozc fcitx-im fcitx-configtool xorg-server xorg-xinit xorg-apps lightdm lightdm-gtk-greeter"
elif [ "$2" = "kde" ] ; then
    packagelist="$packagelist plasma kde-applications firefox pulseaudio pavucontrol lsd xarchiver arc-gtk-theme papirus-icon-theme wmctrl xdotool xdg-user-dirs noto-fonts noto-fonts-cjk noto-fonts-emoji noto-fonts-extra adobe-source-han-sans-jp-fonts otf-ipafont fcitx-mozc fcitx-im fcitx-configtool xorg-server xorg-xinit xorg-apps lightdm lightdm-gtk-greeter"
fi

loadkeys jp106
timedatectl set-ntp true

# partitioning
sgdisk -Z $1
sgdisk -n 0::+512M -t 0:ef00 -c 0:"EFI System" $1
sgdisk -n 0:: -t 0:8300 -c 0:"Linux filesystem" $1

# format
mkfs.vfat -F32 ${1}1
mkfs.ext4 ${1}2

# mount
mount ${1}2 /mnt
mkdir -p /mnt/boot
mount ${1}1 /mnt/boot

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
echo $3 > /mnt/etc/hostname
arch-chroot /mnt systemctl enable dhcpcd
arch-chroot /mnt sh -c "echo '%wheel ALL=(ALL) ALL' | EDITOR='tee -a' visudo"
echo ------------------------------------------------------------------
echo "Password for root"
arch-chroot /mnt passwd
arch-chroot /mnt useradd -m -g users -G wheel -s /bin/bash $4
echo ------------------------------------------------------------------
echo "Password for $4"
arch-chroot /mnt passwd $4

arch-chroot /mnt sudo -u $4 mkdir /home/$4/appimage
arch-chroot /mnt sudo -u $4 wget -O /home/$4/appimage/nvim.appimage https://github.com/neovim/neovim/releases/download/stable/nvim.appimage
arch-chroot /mnt sudo -u $4 chmod u+x /home/$4/appimage/nvim.appimage

echo -e "clear lock\nclear control\nkeycode 66 = Control_L\nadd control = Control_L Control_R" > /mnt/home/$4/.Xmodmap
arch-chroot /mnt chown $4:users /home/$4/.Xmodmap
arch-chroot /mnt chmod 644 /home/$4/.Xmodmap


#echo -e "clear lock\nclear control\nkeycode 66 = Control_L\nadd control = Control_L Control_R" | arch-chroot /mnt sudo -u $4 tee /home/$4/.Xmodmap

if [ $2 = "xfce" ] ; then
    arch-chroot /mnt systemctl enable lightdm
fi
if [ $2 = "gnome" ] ; then
    arch-chroot /mnt systemctl enable lightdm
fi
if [ $2 = "mate" ] ; then
    arch-chroot /mnt systemctl enable lightdm
fi
if [ $2 = "cinnamon" ] ; then
    arch-chroot /mnt systemctl enable lightdm
fi
if [ $2 = "plasma" ] ; then
    arch-chroot /mnt systemctl enable lightdm
fi



arch-chroot /mnt grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=grub
arch-chroot /mnt mkdir /boot/EFI/boot
arch-chroot /mnt cp /boot/EFI/grub/grubx64.efi  /boot/EFI/boot/bootx64.efi
arch-chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg
#arch-chroot /mnt sed -i -e '/^GRUB_TIMEOUT=/c\GRUB_TIMEOUT=30' -e '/^GRUB_CMDLINE_LINUX_DEFAULT=/c\GRUB_CMDLINE_LINUX_DEFAULT="loglevel=3 nomodeset nouveau.modeset=0"' -e '/^GRUB_GFXMODE=/c\GRUB_GFXMODE=1920x1080-24' -e '/^GRUB_DISABLE_OS_PROBER=/c\GRUB_DISABLE_OS_PROBER=false' /etc/default/grub
arch-chroot /mnt sed -i -e '/^GRUB_TIMEOUT=/c\GRUB_TIMEOUT=30' -e '/^GRUB_GFXMODE=/c\GRUB_GFXMODE=1920x1080-24' -e '/^GRUB_DISABLE_OS_PROBER=/c\GRUB_DISABLE_OS_PROBER=false' /etc/default/grub
arch-chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg



#echo -e "export GTK_IM_MODULE=fcitx\nexport QT_IM_MODULE=fcitx\nexport XMODIFIERS=@im=fcitx" > ~/.xprofile
#paru -S timeshift ttf-ricty

#umount -R /mnt
#systemctl reboot