#!/bin/bash

loadkeys jp106
timedatectl set-ntp true
sgdisk -Z /dev/sda
sgdisk -n 0::+512M -t 0:ef00 -c 0:"EFI System" /dev/sda
sgdisk -n 0:: -t 0:8300 -c 0:"Linux filesystem" /dev/sda
mkfs.vfat -F32 /dev/sda1
mkfs.ext4 /dev/sda2
mount /dev/sda2 /mnt
mkdir /mnt/boot
mount /dev/sda1 /mnt/boot
reflector --country Japan --sort rate --save /etc/pacman.d/mirrorlist
#pacstrap /mnt base base-devel linux-zen linux-zen-headers linux-firmware dhcpcd vi sudo intel-ucode grub dosfstools efibootmgr firefox ufw git cifs-utils openssh pulseaudio pavucontrol htop xdg-user-dirs noto-fonts noto-fonts-cjk noto-fonts-emoji noto-fonts-extra adobe-source-han-sans-jp-fonts otf-ipafont fcitx-mozc fcitx-im fcitx-configtool xfce4 xfce4-goodies xorg-server xorg-xinit xorg-apps lightdm lightdm-gtk-greeter
pacstrap /mnt base base-devel linux-zen linux-zen-headers linux-firmware dhcpcd vi sudo intel-ucode grub dosfstools efibootmgr git otf-ipafont fcitx-mozc fcitx-im fcitx-configtool xfce4 xfce4-goodies xorg-server xorg-xinit xorg-apps lightdm lightdm-gtk-greeter
genfstab -U /mnt >> /mnt/etc/fstab
arch-chroot /mnt loadkeys jp106
arch-chroot /mnt ln -sf /usr/share/zoneinfo/Asia/Tokyo /etc/localtime
arch-chroot /mnt hwclock --systohc --utc
arch-chroot /mnt sed -i -e 's/#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/g' -e 's/#ja_JP.UTF-8 UTF-8/ja_JP.UTF-8 UTF-8/g' /etc/locale.gen
arch-chroot /mnt locale-gen
echo LANG=en_US.UTF-8 > /mnt/etc/locale.conf
echo KEYMAP=jp106 > /mnt/etc/vconsole.conf
echo frontier > /mnt/etc/hostname
echo -e "127.0.0.1       localhost\n::1             localhost\n127.0.1.1    frontier.localdomain        frontier" >> /mnt/etc/hosts
arch-chroot /mnt sh -c "echo '%wheel ALL=(ALL) ALL' | EDITOR='tee -a' visudo"


echo -e "---------------------------------------------------------------\npassword for root"
arch-chroot /mnt passwd
echo ---------------------------------------------------------------
echo -n username:
read user

arch-chroot /mnt useradd -m -g users -G wheel -s /bin/bash $user
echo password for $user
arch-chroot /mnt passwd $user
arch-chroot /mnt grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=grub
arch-chroot /mnt mkdir /boot/EFI/boot
arch-chroot /mnt cp /boot/EFI/grub/grubx64.efi /boot/EFI/boot/bootx64.efi
arch-chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg
arch-chroot /mnt sed -i -e '/^GRUB_TIMEOUT=/c\GRUB_TIMEOUT=30' /etc/default/grub
arch-chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg


#cd /mnt/home/$user
#arch-chroot /mnt su $user -c "echo -e 'export GTK_IM_MODULE=fcitx\nexport QT_IM_MODULE=fcitx\nexport XMODIFIERS=@im=fcitx' > /mnt/home/$user/.xprofile && mkdir /mnt/home/$user/abs && cd /mnt/home/$user/abs && git clone https://aur.archlinux.org/paru.git && cd paru && makepkg -si"
#arch-chroot /mnt echo -e "export GTK_IM_MODULE=fcitx\nexport QT_IM_MODULE=fcitx\nexport XMODIFIERS=@im=fcitx" > /mnt/home/$user/.xprofile
echo -e "export GTK_IM_MODULE=fcitx\nexport QT_IM_MODULE=fcitx\nexport XMODIFIERS=@im=fcitx" > /mnt/home/$user/.xprofile
arch-chroot /mnt chown $user:users /home/$user/.xprofile
arch-chroot /mnt chmod 644 /home/$user/.xprofile
arch-chroot /mnt sudo -u $user mkdir /home/$user/abs
arch-chroot /mnt sudo -u $user git clone https://aur.archlinux.org/paru.git /home/$user/abs/paru


arch-chroot /mnt sed -i -e 's/en_US.UTF-8 UTF-8/#en_US.UTF-8 UTF-8/g' /etc/locale.gen
arch-chroot /mnt locale-gen
echo LANG=ja_JP.UTF-8 > /mnt/etc/locale.conf
arch-chroot /mnt systemctl enable dhcpcd
arch-chroot /mnt systemctl enable lightdm
