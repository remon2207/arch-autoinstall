#!/usr/bin/env bash

packagelist="base \
    base-devel \
    linux-zen \
    linux-zen-headers \
    linux-firmware \
    efibootmgr \
    vi \
    neovim \
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
    man-db \
    man-pages \
    ntfs-3g \
    exfat-utils \
    firefox \
    firefox-i18n-ja \
    wireplumber \
    pipewire \
    pipewire-pulse \
    xdg-user-dirs-gtk \
    noto-fonts \
    noto-fonts-cjk \
    noto-fonts-emoji \
    fcitx5 \
    fcitx5-im \
    fcitx5-mozc \
    audacious \
    docker \
    docker-compose \
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
    xorg \
    xorg-server \
    xorg-apps \
    xorg-xinit \
    gsmartcontrol \
    bluez \
    fd \
    go \
    ripgrep \
    xclip \
    vlc \
    profile-sync-daemon \
    gparted"

if [ ${#} -lt 12 ]; then
    echo "Usage:"
    echo "# ip -4 a"
    echo "# ./arch-autoinstall/install.sh \
<disk> <microcode: intel | amd> <DE: xfce | gnome | kde> \
<GPU: nvidia | amd | intel> <HostName> <UserName> \
<userPasword> <rootPassword> <partition-table-destroy: yes | no-exclude-efi | no-root-only | skip> \
<boot-loader: systemd-boot | grub> <network: static-ip | dhcp> <root_partition_size: Numbers only (GiB)> <net_interface>"
    exit
fi

disk="${1}"
microcode="${2}"
de="${3}"
gpu="${4}"
hostname="${5}"
username="${6}"
user_password="${7}"
root_password="${8}"
partition_table="${9}"
boot_loader="${10}"
network="${11}"
root_size="${12}"
net_interface="${13}"

check_variables() {
    if [ "${microcode}" != "intel" ] && [ "${microcode}" != "amd" ]; then
        echo "Missing argument or misspelled..."
        return 1
    elif [ "${de}" != "xfce" ] && [ "${de}" != "gnome" ] && [ "${de}" != "kde" ]; then
        echo "Missing argument or misspelled..."
        return 1
    elif [ "${gpu}" != "nvidia" ] && [ "${gpu}" != "amd" ] && [ "${gpu}" != "intel" ]; then
        echo "Missing argument or misspelled..."
        return 1
    elif [ "${partition_table}" != "yes" ] && [ "${partition_table}" != "no-exclude-efi" ] && [ "${partition_table}" != "no-root-only" ] && [ "${partition_table}" != "skip" ]; then
        echo "Missing argument or misspelled..."
        return 1
    elif [ "${boot_loader}" != "systemd-boot" ] && [ "${boot_loader}" != "grub" ]; then
        echo "Missing argument or misspelled..."
        return 1
    elif [ "${network}" != "static-ip" ] && [ "${network}" != "dhcp" ]; then
        echo "Missing argument or misspelled..."
        return 1
    fi
}

selection_arguments() {
    # intel-ucode or amd-ucode
    if [ "${microcode}" = "intel" ]; then
        packagelist="${packagelist} intel-ucode"
    elif [ "${microcode}" = "amd" ]; then
        packagelist="${packagelist} amd-ucode"
    fi

    # desktop
    if [ "${de}" = "xfce" ]; then
        packagelist="${packagelist} \
            xfce4 \
            xfce4-goodies \
            xarchiver \
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
    elif [ "${de}" = "gnome" ]; then
        packagelist="${packagelist} \
            gnome-control-center \
            gnome-shell \
            gnome-tweaks \
            gnome-themes-extra \
            gnome-terminal \
            gnome-keyring \
            gvfs \
            qt5ct \
            kvantum \
            mutter \
            file-roller \
            dconf-editor \
            eog \
            gdm \
            nautilus \
            papirus-icon-theme \
            gnome-shell-extension-appindicator"
    elif [ "${de}" = "kde" ]; then
        packagelist="${packagelist} \
            plasma-meta \
            dolphin \
            konsole \
            gwenview \
            spectacle \
            libappindicator-gtk3"
    fi

    if [ "${gpu}" = "nvidia" ]; then
        packagelist="${packagelist} nvidia-dkms nvidia-settings"
    elif [ "${gpu}" = "amd" ]; then
        packagelist="${packagelist} xf86-video-amdgpu libva-mesa-driver mesa-vdpau"
    elif [ "${gpu}" = "intel" ]; then
	echo "Already declared"
    fi

    if [ "${boot_loader}" = "grub" ]; then
        packagelist="${packagelist} grub efibootmgr dosfstools"
    fi

    if [ "${network}" = "dhcp" ]; then
        packagelist="${packagelist} dhcpcd"
    fi
}

time_setting() {
    timedatectl set-ntp true
}

partitioning() {
    if [ "${partition_table}" = "yes" ]; then
        sgdisk -Z ${disk}
        sgdisk -n 0::+512M -t 0:ef00 -c 0:"EFI System" ${disk}
        sgdisk -n 0::+${root_size}G -t 0:8300 -c 0:"Linux filesystem" ${disk}
        sgdisk -n 0:: -t 0:8300 -c 0:"Linux filesystem" ${disk}

        # format
        mkfs.fat -F 32 ${disk}1
        mkfs.ext4 ${disk}2
        mkfs.ext4 ${disk}3
    elif [ "${partition_table}" = "no-exclude-efi" ]; then
        sgdisk -d 3 ${disk}
        sgdisk -d 2 ${disk}
        sgdisk -n 0::+${root_size}G -t 0:8300 -c 0:"Linux filesystem" ${disk}
        sgdisk -n 0:: -t 0:8300 -c 0:"Linux filesystem" ${disk}

        # format
        mkfs.ext4 ${disk}2
        mkfs.ext4 ${disk}3
    elif [ "${partition_table}" = "no-root-only" ]; then
        # format
        mkfs.ext4 ${disk}2
    elif [ "${partition_table}" = "skip" ]; then
        echo "Skip partitioning"

        # format
        mkfs.ext4 ${disk}2
        mkfs.ext4 ${disk}3
    fi

    # mount
    mount ${disk}2 /mnt
    mount --mkdir ${disk}1 /mnt/boot
    mount --mkdir ${disk}3 /mnt/home
}

installation() {
    reflector --country Japan --protocol http,https --sort rate --save /etc/pacman.d/mirrorlist
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
    echo ${hostname} > /mnt/etc/hostname
    arch-chroot /mnt sh -c "echo '%wheel ALL=(ALL:ALL) ALL' | EDITOR='tee -a' visudo"
}

networking() {
        if [ ${network} = "static-ip" ]; then
	ip_address=$(ip -4 a show ${net_interface} | grep 192.168 | awk '{print $2}' | cut -d "/" -f 1)
        cat << EOF >> /mnt/etc/hosts
127.0.0.1       localhost
::1             localhost
${ip_address}    ${hostname}.localdomain        ${hostname}
EOF

        arch-chroot /mnt systemctl enable systemd-{networkd,resolved}.service
        cat << EOF > /mnt/etc/systemd/network/20-wired.network
[Match]
Name=${net_interface}

[Network]
Address=${ip_address}/24
Gateway=192.168.1.1
DNS=2001:4860:4860::8888
DNS=2001:4860:4860::8844
EOF

        ln -sf /run/systemd/resolve/stub-resolv.conf /mnt/etc/resolv.conf
    elif [ ${network} = "dhcp" ]; then
        arch-chroot /mnt systemctl enable dhcpcd.service
    fi
}

create_user() {
    echo "root:${root_password}" | arch-chroot /mnt chpasswd
    arch-chroot /mnt useradd -m -G wheel -s /bin/bash ${username}
    echo "${username}:${user_password}" | arch-chroot /mnt chpasswd
}


japanese_input() {
    cat << EOF >> /mnt/etc/environment
GTK_IM_MODULE=fcitx5
QT_IM_MODULE=fcitx5
XMODIFIERS=@im=fcitx5
EOF
    echo "LANG=ja_JP.UTF-8" > /mnt/etc/locale.conf
}

add_to_group() {
    arch-chroot /mnt gpasswd -a ${username} docker
    arch-chroot /mnt gpasswd -a ${username} vboxusers
}

replacement() {
    arch-chroot /mnt sed -i "s/^#NTP=/NTP=0.asia.pool.ntp.org 1.asia.pool.ntp.org 2.asia.pool.ntp.org 3.asia.pool.ntp.org/" /etc/systemd/timesyncd.conf
    arch-chroot /mnt sed -i "s/^#FallbackNTP/FallbackNTP/" /etc/systemd/timesyncd.conf
    arch-chroot /mnt sed -i "s/-march=x86-64 -mtune=generic/-march=native/" /etc/makepkg.conf
    arch-chroot /mnt sed -i 's/^#MAKEFLAGS="-j2"/MAKEFLAGS="-j$(($(nproc)+1))"/' /etc/makepkg.conf
    arch-chroot /mnt sed -i "s/^#BUILDDIR/BUILDDIR/" /etc/makepkg.conf
    arch-chroot /mnt sed -i "s/COMPRESSXZ=(xz -c -z -)/COMPRESSXZ=(xz -c -z --threads=0 -)/" /etc/makepkg.conf
    arch-chroot /mnt sed -i "s/^#DefaultTimeoutStopSec=90s/DefaultTimeoutStopSec=10s/" /etc/systemd/system.conf
    arch-chroot /mnt cp /etc/udisks2/mount_options.conf.example /etc/udisks2/mount_options.conf
    arch-chroot /mnt sed -i "7s/^# \[defaults\]/\[defaults\]/" /etc/udisks2/mount_options.conf
    arch-chroot /mnt sed -i "15s/^# ntfs_defaults=uid=\$UID,gid=\$GID,windows_names/ntfs_defaults=uid=\$UID,gid=\$GID,noatime/" /etc/udisks2/mount_options.conf
}


boot_loader() {
    if [ ${boot_loader} = "grub" ]; then
        # grub
        arch-chroot /mnt grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=grub --recheck
        arch-chroot /mnt mkdir /boot/EFI/boot
        arch-chroot /mnt cp /boot/EFI/grub/grubx64.efi /boot/EFI/Boot/bootx64.efi
        arch-chroot /mnt sed -i '/^GRUB_TIMEOUT=/c\GRUB_TIMEOUT=10' /etc/default/grub
        if [ ${gpu} = "nvidia" ]; then
            arch-chroot /mnt sed -i '/^GRUB_CMDLINE_LINUX_DEFAULT=/c\GRUB_CMDLINE_LINUX_DEFAULT="loglevel=3 panic=180 nomodeset i915.modeset=0 nouveau.modeset=0 nvidia-drm.modeset=1"' /etc/default/grub
            arch-chroot /mnt sed -i '/^GRUB_GFXMODE=/c\GRUB_GFXMODE=1920x1080-24' /etc/default/grub
        elif [ ${gpu} = "amd" ]; then
            arch-chroot /mnt sed -i '/^GRUB_CMDLINE_LINUX_DEFAULT=/c\GRUB_CMDLINE_LINUX_DEFAULT="loglevel=3 panic=180"' /etc/default/grub
        elif [ ${gpu} = "intel" ]; then
            arch-chroot /mnt sed -i '/^GRUB_CMDLINE_LINUX_DEFAULT=/c\GRUB_CMDLINE_LINUX_DEFAULT="loglevel=3 panic=180"' /etc/default/grub
        fi
        arch-chroot /mnt sed -i '/^GRUB_DISABLE_OS_PROBER=/c\GRUB_DISABLE_OS_PROBER=false' /etc/default/grub
        arch-chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg
    elif [ ${boot_loader} = "systemd-boot" ]; then
        # systemd-boot
        arch-chroot /mnt bootctl --path=/boot install
        cat << EOF >> /mnt/boot/loader/loader.conf
default      arch
timeout      10
console-mode max
editor       no
EOF

        root_partuuid=$(blkid -s PARTUUID -o value ${disk}2)

        if [ ${gpu} = "nvidia" ]; then
            cat << EOF >> /mnt/boot/loader/entries/arch.conf
title    Arch Linux
linux    /vmlinuz-linux-zen
initrd   /intel-ucode.img
initrd   /initramfs-linux-zen.img
options  root=PARTUUID=${root_partuuid} rw loglevel=3 panic=180 nomodeset i915.modeset=0 nouveau.modeset=0 nvidia-drm.modeset=1
EOF
            cat << EOF >> /mnt/boot/loader/entries/arch_nouveau.conf
title    Arch Linux Nouveau
linux    /vmlinuz-linux-zen
initrd   /intel-ucode.img
initrd   /initramfs-linux-zen.img
options  root=PARTUUID=${root_partuuid} rw loglevel=3 panic=180
EOF
        elif [ ${gpu} = "amd" ]; then
            cat << EOF >> /mnt/boot/loader/entries/arch.conf
title    Arch Linux
linux    /vmlinuz-linux-zen
initrd   /amd-ucode.img
initrd   /initramfs-linux-zen.img
options  root=PARTUUID=${root_partuuid} rw loglevel=3 panic=180
EOF
        elif [ ${gpu} = "intel" ]; then
            cat << EOF >> /mnt/boot/loader/entries/arch.conf
title    Arch Linux
linux    /vmlinuz-linux-zen
initrd   /intel-ucode.img
initrd   /initramfs-linux-zen.img
options  root=PARTUUID=${root_partuuid} rw loglevel=3 panic=180
EOF
        fi

        cat << EOF >> /mnt/boot/loader/entries/arch_fallback.conf
title    Arch Linux Fallback
linux    /vmlinuz-linux-zen
initrd   /intel-ucode.img
initrd   /initramfs-linux-zen-fallback.img
options  root=PARTUUID=${root_partuuid} rw panic=180 debug
EOF
        arch-chroot /mnt systemctl enable systemd-boot-update.service
    fi
}

enable_services() {
    arch-chroot /mnt systemctl enable docker.service
    arch-chroot /mnt systemctl enable fstrim.timer
    arch-chroot /mnt systemctl enable ufw.service
    arch-chroot /mnt systemctl enable bluetooth.service

    if [ "${de}" == "xfce" ]; then
        arch-chroot /mnt systemctl enable lightdm.service
    elif [ "${de}" == "gnome" ]; then
        arch-chroot /mnt systemctl enable gdm.service
    elif [ "${de}" == "kde" ]; then
        arch-chroot /mnt systemctl enable sddm.service
    fi
}

check_variables
selection_arguments
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
