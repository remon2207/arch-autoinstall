# arch-autoinstall

```bash
./arch-autoinstall/install.sh --disk <disk> \
--microcode <microcode> \
--de <de> \
--gpu <gpu> \
--host-name <host-name> \
--user-name <user-name> \
--user-password <user-password> \
--root-password <root-password> \
--partition-destroy <partition-destroy> \
--root-size <root-size>

# example
./arch-autoinstall/install.sh --disk /dev/sda \
--microcode intel \
--de gnome \
--gpu nvidia \
--host-name archlinux \
--user-name master \
--user-password 12345 \
--root-password q1w2e3r4t5y6 \
--partition-destroy yes \
--root-size 256
```

#### minimal_install.sh is for testing on a virtual machine

```bash
./arch-autoinstall/minimal_install.sh --disk <disk> \
--microcode <microcode> \
--gpu <gpu> \
--host-name <virtualbox> \
--user-name <user-name> \
--user-password <user-password> \
--root-password <root-password>

# example
./arch-autoinstall/minimal_install.sh --disk /dev/sda \
--microcode intel \
--gpu intel \
--host-name virtualbox \
--user-name virt \
--user-password virt \
--root-password root
```
