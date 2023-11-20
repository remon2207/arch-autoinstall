# arch-autoinstall

#### USAGE:
`./arch-autoinstall/install.sh` or

`./arch-autoinstall/install.sh -h` or

`./arch-autoinstall/install.sh --help`

```bash
./arch-autoinstall/install.sh --disk <disk> \
--microcode <microcode> \
--de <de> \
--gpu <gpu> \
--user-password <user-password> \
--root-password <root-password> \
--partition-destroy <partition-destroy> \
--root-size <root-size>

# example
./arch-autoinstall/install.sh --disk /dev/sda \
--microcode intel \
--de gnome \
--gpu nvidia \
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
--user-password <user-password> \
--root-password <root-password>

# example
./arch-autoinstall/minimal_install.sh --disk /dev/sda \
--microcode intel \
--gpu intel \
--user-password virt \
--root-password root
```
