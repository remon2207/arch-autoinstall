#!/usr/bin/env bash

packagelist="base \
    base-devel \
    linux-zen \
    linux-zen-headers \
    linux-firmware \
    vi \
    vim \
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
    audacious \
    gnome-keyring \
    qt5ct \
    kvantum \
    docker \
    docker-compose \
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
    bat \
    rsync \
    reflector \
    xorg-server \
    xorg-xinit \
    gsmartcontrol \
    gparted"

if [ ${#} -lt 11 ]; then
    echo "Usage:"
    echo "install.sh \
<disk> <microcode: intel | amd> <DE: xfce | gnome | kde> \
<GPU: nvidia | amd | intel> <HostName> <UserName> \
<userPasword> <rootPassword> <partition-table-destroy: yes | no-exclude-efi | no-root-only | skip> \
<boot-loader: systemd-boot | grub> <network: static-ip | dhcp>"
    exit
fi

check_variables() {
    if [ "${2}" != "intel" ] && [ "${2}" != "amd" ]; then
        echo "Missing argument or misspelled..."
        return 1
    elif [ "${3}" != "xfce" ] && [ "${3}" != "gnome" ] && [ "${3}" != "kde" ]; then
        echo "Missing argument or misspelled..."
        return 1
    elif [ "${4}" != "nvidia" ] && [ "${4}" != "amd" ] && [ "${4}" != "intel" ]; then
        echo "Missing argument or misspelled..."
        return 1
    elif [ "${9}" != "yes" ] && [ "${9}" != "no-exclude-efi" ] && [ "${9}" != "no-root-only" ] && [ "${9}" != "skip" ]; then
        echo "Missing argument or misspelled..."
        return 1
    elif [ "${10}" != "systemd-boot" ] && [ "${10}" != "grub" ]; then
        echo "Missing argument or misspelled..."
        return 1
    elif [ "${11}" != "static-ip" ] && [ "${11}" != "dhcp" ]; then
        echo "Missing argument or misspelled..."
        return 1
    fi
}

selection_arguments() {
    # intel-ucode or amd-ucode
    if [ "${2}" = "intel" ]; then
        packagelist="${packagelist} intel-ucode"
    elif [ "${2}" = "amd" ]; then
        packagelist="${packagelist} amd-ucode"
    else
        echo "error in selection_arguments function"
        exit 1
    fi

    # desktop
    if [ "${3}" = "xfce" ]; then
        packagelist="${packagelist} \
            xfce4 \
            xfce4-goodies \
            arc-gtk-theme \
            papirus-icon-theme \
            lightdm \
            lightdm-gtk-greeter \
            lightdm-gtk-greeter-settings \
            lxappearance-gtk3 \
            evince \
            xarchiver"
    elif [ "${3}" = "gnome" ]; then
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
            papirus-icon-theme \
            eog \
            file-roller \
            evince \
            gnome-backgrounds"
    elif [ "${3}" = "kde" ]; then
        packagelist="${packagelist} \
            plasma-meta \
            lxappearance-gtk3 \
            lightdm \
            lightdm-gtk-greeter \
            lightdm-gtk-greeter-settings"
    fi

    if [ "${4}" = "nvidia" ]; then
        packagelist="${packagelist} nvidia-dkms nvidia-settings"
    elif [ "${4}" = "amd" ]; then
        packagelist="${packagelist} xf86-video-amdgpu libva-mesa-driver mesa-vdpau"
    elif [ "${4}" = "intel" ]; then
        echo "Already declared."
    fi

    if [ "${11}" = "dhcp" ]; then
        packagelist="${packagelist} dhcpcd"
    fi
}

time_setting() {
    timedatectl set-ntp true
}

partitioning() {
    if [ "${9}" = "yes" ]; then
        sgdisk -Z ${1}
        sgdisk -n 0::+512M -t 0:ef00 -c 0:"EFI System" ${1}
        sgdisk -n 0::+15G -t 0:8300 -c 0:"Linux filesystem" ${1}
        sgdisk -n 0:: -t 0:8300 -c 0:"Linux filesystem" ${1}

        # format
        mkfs.fat -F 32 ${1}1
        mkfs.ext4 ${1}2
        mkfs.ext4 ${1}3
    elif [ "${9}" = "no-exclude-efi" ]; then
        sgdisk -d 3 $1
        sgdisk -d 2 $1
        sgdisk -n 0::+350G -t 0:8300 -c 0:"Linux filesystem" ${1}
        sgdisk -n 0:: -t 0:8300 -c 0:"Linux filesystem" ${1}

        # format
        mkfs.ext4 ${1}2
        mkfs.ext4 ${1}3
    elif [ "${9}" = "no-root-only" ]; then
        # format
        mkfs.ext4 ${1}2
    elif [ "${9}" = "skip" ]; then
        echo "Skip partitioning"

        # format
        mkfs.ext4 ${1}2
        mkfs.ext4 ${1}3
    else
        echo "Not specified or misspelled..."
        exit 1
    fi

    # mount
    mount ${1}2 /mnt
    mkdir /mnt/boot
    mount ${1}1 /mnt/boot
    mkdir /mnt/home
    mount ${1}3 /mnt/home
}

installing() {
    reflector --country Japan --sort rate --save /etc/pacman.d/mirrorlist
    pacman -Sy --noconfirm archlinux-keyring
    pacstrap /mnt ${packagelist}
    genfstab -t PARTUUID /mnt >> /mnt/etc/fstab
}

configuration() {
    arch-chroot /mnt ln -sf /usr/share/zoneinfo/Asia/Tokyo /etc/localtime
    arch-chroot /mnt hwclock --systohc --utc
    arch-chroot /mnt sed -i "s/#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/" /etc/locale.gen
    arch-chroot /mnt sed -i "s/#ja_JP.UTF-8 UTF-8/ja_JP.UTF-8 UTF-8/" /etc/locale.gen
    arch-chroot /mnt locale-gen
    echo "LANG=en_US.UTF-8" > /mnt/etc/locale.conf
    echo "KEYMAP=us" > /mnt/etc/vconsole.conf
    echo ${5} > /mnt/etc/hostname
    arch-chroot /mnt sh -c "echo '%wheel ALL=(ALL:ALL) ALL' | EDITOR='tee -a' visudo"
    arch-chroot /mnt sh -c "echo 'Defaults editor=/usr/bin/vim' | EDITOR='tee -a' visudo"
}

network() {
        if [ ${11} = "static-ip" ]; then
        ip_address=$(ip -4 a show enp6s0 | grep -oP "(?<=inet\s)\d+(\.\d+){3}")
        # echo -e "127.0.0.1       localhost\n\
        # ::1             localhost\n\
        # ${ip_address}    ${5}.localdomain        ${5}" >> /mnt/etc/hosts

        cat << EOF >> /mnt/etc/hosts
127.0.0.1       localhost
::1             localhost
${ip_address}    ${5}.localdomain        ${5}
EOF

        arch-chroot /mnt systemctl enable systemd-{networkd,resolved}.service
        # echo -e "[Match]\n\
        # Name=enp6s0\n\
        # \n\
        # [Network]\n\
        # Address=${ip_address}/24\n\
        # Gateway=192.168.1.1\n\
        # DNS=8.8.8.8\n\
        # DNS=8.8.4.4" > /mnt/etc/systemd/network/20-wired.network

        cat << EOF > /mnt/etc/systemd/network/20-wired.network
[Match]
Name=enp6s0

[Network]
Address=${ip_address}/24
Gateway=192.168.1.1
DNS=8.8.8.8
DNS=8.8.4.4
EOF

        ln -sf /run/systemd/resolve/stub-resolv.conf /mnt/etc/resolv.conf
    elif [ ${11} = "dhcp" ]; then
        arch-chroot /mnt systemctl enable dhcpcd.service
    else
        echo "Not specified or misspelled..."
        exit 1
    fi
}

create_user() {
    echo "root:$8" | arch-chroot /mnt chpasswd
    arch-chroot /mnt useradd -m -G wheel -s /bin/bash ${6}
    echo "$6:$7" | arch-chroot /mnt chpasswd
}


japanese_input() {
    # echo -e "GTK_IM_MODULE=fcitx5\n\
    # QT_IM_MODULE=fcitx5\n\
    # XMODIFIERS=@im=fcitx5" >> /mnt/etc/environment
    cat << EOF >> /mnt/etc/environment
GTK_IM_MODULE=fcitx5
QT_IM_MODULE=fcitx5
XMODIFIERS=@im=fcitx5
EOF
    echo "LANG=ja_JP.UTF-8" > /mnt/etc/locale.conf
}

add_to_group() {
    arch-chroot /mnt gpasswd -a ${6} docker
    arch-chroot /mnt gpasswd -a ${6} vboxusers
}

replacement() {
    arch-chroot /mnt sed -i "s/^#NTP=/NTP=0.asia.pool.ntp.org 1.asia.pool.ntp.org 2.asia.pool.ntp.org 3.asia.pool.ntp.org/" /etc/systemd/timesyncd.conf
    arch-chroot /mnt sed -i "s/^#FallbackNTP/FallbackNTP/" /etc/systemd/timesyncd.conf
    arch-chroot /mnt sed -i "s/-march=x86-64 -mtune=generic/-march=native/" /etc/makepkg.conf
    arch-chroot /mnt sed -i 's/^#MAKEFLAGS="-j2"/MAKEFLAGS="-j$(($(nproc)+1))"/' /etc/makepkg.conf
    arch-chroot /mnt sed -i "s/^#BUILDDIR/BUILDDIR/" /etc/makepkg.conf
    arch-chroot /mnt sed -i "s/COMPRESSXZ=(xz -c -z -)/COMPRESSXZ=(xz -c -z --threads=0 -)/" /etc/makepkg.conf
    arch-chroot /mnt sed -i "s/^#DefaultTimeoutStopSec=90s/DefaultTimeoutStopSec=10s/" /etc/systemd/system.conf
}


boot_loader() {
    if [ ${10} = "grub" ]; then
        # grub
        arch-chroot /mnt grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=grub --recheck
        arch-chroot /mnt mkdir /boot/EFI/boot
        arch-chroot /mnt cp /boot/EFI/grub/grubx64.efi /boot/EFI/Boot/bootx64.efi
        arch-chroot /mnt sed -i '/^GRUB_TIMEOUT=/c\GRUB_TIMEOUT=10' /etc/default/grub
        if [ ${4} = "nvidia" ]; then
        arch-chroot /mnt sed -i '/^GRUB_CMDLINE_LINUX_DEFAULT=/c\GRUB_CMDLINE_LINUX_DEFAULT="loglevel=3 panic=180 nomodeset i915.modeset=0 nouveau.modeset=0 nvidia-drm.modeset=1"' /etc/default/grub
        elif [ ${4} = "amd" ]; then
            arch-chroot /mnt sed -i '/^GRUB_CMDLINE_LINUX_DEFAULT=/c\GRUB_CMDLINE_LINUX_DEFAULT="loglevel=3 panic=180"' /etc/default/grub
        elif [ ${4} = "intel" ]; then
            arch-chroot /mnt sed -i '/^GRUB_CMDLINE_LINUX_DEFAULT=/c\GRUB_CMDLINE_LINUX_DEFAULT="loglevel=3 panic=180"' /etc/default/grub
        else
            echo "Missing argument or misspelled..."
            exit 1
        fi
        arch-chroot /mnt sed -i '/^GRUB_GFXMODE=/c\GRUB_GFXMODE=1920x1080-24' /etc/default/grub
        arch-chroot /mnt sed -i '/^GRUB_DISABLE_OS_PROBER=/c\GRUB_DISABLE_OS_PROBER=false' /etc/default/grub
        arch-chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg
    elif [ ${10} = "systemd-boot" ]; then
        # systemd-boot
        arch-chroot /mnt bootctl --path=/boot install
        # echo -e "default    arch\n\
        # timeout    10\n\
        # console-mode max\n\
        # editor     no" >> /mnt/boot/loader/loader.conf
        cat << EOF >> /mnt/boot/loader/loader.conf
default      arch
timeout      10
console-mode max
editor       no
EOF

        root_partuuid=$(blkid -s PARTUUID -o value ${1}2)

        # echo -e "title    Arch Linux\n\
        # linux    /vmlinuz-linux-zen\n\
        # initrd   /intel-ucode.img\n\
        # initrd   /initramfs-linux-zen.img\n\
        # options  root=PARTUUID=${root_partuuid} rw loglevel=3 panic=180 nomodeset i915.modeset=0 nouveau.modeset=0 nvidia-drm.modeset=1" >> /mnt/boot/loader/entries/arch.conf
        if [ ${4} = "nvidia" ]; then
            cat << EOF >> /mnt/boot/loader/entries/arch.conf
title    Arch Linux
linux    /vmlinuz-linux-zen
initrd   /intel-ucode.img
initrd   /initramfs-linux-zen.img
options  root=PARTUUID=${root_partuuid} rw loglevel=3 panic=180 nomodeset i915.modeset=0 nouveau.modeset=0 nvidia-drm.modeset=1
EOF
        elif [ ${4} = "amd" ]; then
            cat << EOF >> /mnt/boot/loader/entries/arch.conf
title    Arch Linux
linux    /vmlinuz-linux-zen
initrd   /intel-ucode.img
initrd   /initramfs-linux-zen.img
options  root=PARTUUID=${root_partuuid} rw loglevel=3 panic=180
EOF
        elif [ ${4} = "intel" ]; then
            cat << EOF >> /mnt/boot/loader/entries/arch.conf
title    Arch Linux
linux    /vmlinuz-linux-zen
initrd   /intel-ucode.img
initrd   /initramfs-linux-zen.img
options  root=PARTUUID=${root_partuuid} rw loglevel=3 panic=180
EOF
        else
            echo "Missing argument or misspelled..."
            exit 1
        fi
        arch-chroot /mnt systemctl enable systemd-boot-update.service
    else
        echo "Missing argument or misspelled..."
        exit 1
    fi
}

enable_services() {
    arch-chroot /mnt systemctl enable docker.service
    arch-chroot /mnt systemctl enable fstrim.timer
    arch-chroot /mnt systemctl enable ufw.service

    if [ ${3} = "xfce" ]; then
        arch-chroot /mnt systemctl enable lightdm
    elif [ ${3} = "gnome" ]; then
        arch-chroot /mnt systemctl enable gdm
    elif [ ${3} = "kde" ]; then
        arch-chroot /mnt systemctl enable lightdm
    fi
}

# check_variables
selection_arguments $(2) $(3) $(4) $(11)
time_setting
partitioning
installation
configuration
networking
create_user
japanese_input
add_to_group
replacement
boot_loader
enable_services
