#
#   ArchLinux Install
#
INSTALL_DRIVE=/dev/sda
BOOT_DRIVE=$INSTALL_DRIVE

PARTITION_BOOT_ID=1
PARTITION_SWAP_ID=2
PARTITION_ROOT_ID=3

PARTITION_BOOT=/boot

LABEL_BOOT=boot
LABEL_SWAP=swap
LABEL_ROOT=root
MOUNT_PATH=/mnt


#
#   Support routines
#

_filesystem_pre_baseinstall () {
_countdown 10 "ERASING $INSTALL_DRIVE"

# Create three partitions:
#
# 1. boot 
# 2. swap
# 3. root
# Note that all of these are on a GUID partition table scheme. This proves
# to be quite clean and simple since we're not doing anything with MBR
# boot partitions and the like.

# disk prep
sgdisk -Z ${INSTALL_DRIVE} # zap all on disk
sgdisk -a 2048 -o ${INSTALL_DRIVE} # new gpt disk 2048 alignment

# create partitions
sgdisk -n ${PARTITION_BOOT_ID}:0:+200M ${INSTALL_DRIVE} # (UEFI BOOT), default start block, 200MB
sgdisk -n ${PARTITION_SWAP_ID}:0:+2G ${INSTALL_DRIVE} # (SWAP), default start block, 2GB
sgdisk -n ${PARTITION_ROOT_ID}:0:0 ${INSTALL_DRIVE}   # (LUKS), default start, remaining space

# set partition types
sgdisk -t ${PARTITION_BOOT_ID}:8300 ${INSTALL_DRIVE}
sgdisk -t ${PARTITION_SWAP_ID}:8200 ${INSTALL_DRIVE}
sgdisk -t ${PARTITION_ROOT_ID}:8300 ${INSTALL_DRIVE}

# label partitions
sgdisk -c ${PARTITION_BOOT_ID}:"${LABEL_BOOT}" ${INSTALL_DRIVE}
sgdisk -c ${PARTITION_SWAP_ID}:"${LABEL_SWAP}" ${INSTALL_DRIVE}
sgdisk -c ${PARTITION_ROOT_ID}:"${LABEL_ROOT}" ${INSTALL_DRIVE}

# make filesystems
mkfs.ext4 ${INSTALL_DRIVE}${PARTITION_BOOT_ID}
mkfs.ext4 ${INSTALL_DRIVE}${PARTITION_ROOT_ID}
mkswap ${INSTALL_DRIVE}${PARTITION_SWAP_ID}
swapon ${INSTALL_DRIVE}${PARTITION_SWAP_ID}

# mount target
mkdir -p ${MOUNT_PATH}
mount ${INSTALL_DRIVE}${PARTITION_ROOT_ID} ${MOUNT_PATH}
mkdir -p ${MOUNT_PATH}${PARTITION_BOOT}
mount ${INSTALL_DRIVE}${PARTITION_BOOT_ID} ${MOUNT_PATH}${PARTITION_BOOT}
}

_filesystem_post_baseinstall () {
# not using genfstab here since it doesn't record partlabel labels
cat > ${MOUNT_PATH}/etc/fstab <<FSTAB_EOF
# /etc/fstab: static file system information
#
# <file system>					<dir>		<type>	<options>				<dump>	<pass>
tmpfs						/tmp		tmpfs	nodev,nosuid				0	0
#/dev/disk/by-partlabel/${LABEL_BOOT_EFI}		$EFI_SYSTEM_PARTITION	vfat	rw,relatime,discard			0	2
/dev/disk/by-partlabel/${LABEL_BOOT_EFI}		$EFI_SYSTEM_PARTITION	vfat	rw,relatime,discard,fmask=0022,dmask=0022,codepage=437,iocharset=iso8859-1,shortname=mixed,errors=remount-ro	0 2
/dev/disk/by-partlabel/${LABEL_SWAP}				none		swap	defaults,discard			0	0
/dev/disk/by-partlabel/${LABEL_ROOT}				/      		ext4	rw,relatime,data=ordered,discard	0	1
FSTAB_EOF
}

_filesystem_pre_chroot ()
{
umount ${MOUNT_PATH}${EFI_SYSTEM_PARTITION};
}

_filesystem_post_chroot ()
{
mount -t vfat ${INSTALL_DRIVE}${PARTITION_EFI_BOOT} ${EFI_SYSTEM_PARTITION} || return 1;
# KERNEL_PARAMS used by BOOTLOADER
# KERNEL_PARAMS="${KERNEL_PARAMS:+${KERNEL_PARAMS} }cryptdevice=/dev/sda3:${LABEL_ROOT_CRYPT} root=/dev/mapper/${LABEL_ROOT_CRYPT} ro rootfstype=ext4"
KERNEL_PARAMS="${KERNEL_PARAMS:+${KERNEL_PARAMS} }root=UUID=$(_get_uuid ${INSTALL_DRIVE}${PARTITION_ROOT}) ro rootfstype=ext4"
}

_countdown ()
{
# countdown 10 "message here"
#
for i in `seq $1 -1 1`; do
echo -en "\r$2 in $i seconds (ctrl-c to cancel and exit) <"
for j in `seq 1 $i`; do echo -n "=="; done; echo -en "     \b\b\b\b\b"
sleep 1; done; echo
}

# DEFAULTVALUE -----------------------------------------------------------
_defaultvalue ()
{
# Assign value to a variable in the install script only if unset.
# Note that *empty* variables that have purposefully been set as empty
# are not changed.
#
# usage:
#
# _defaultvalue VARNAME "value if VARNAME is currently unset or empty"
#
eval "${1}=\"${!1-${2}}\"";
}

# SETVALUE ---------------------------------------------------------------
_setvalue ()
{
# Assign a value to a "standard" bash format variable in a config file
# or script. For example, given a file with path "path/to/file.conf"
# with a variable defined like this:
#
# VARNAME=valuehere
#
# the value can be changed using this function:
#
# _setvalue newvalue VARNAME "path/to/file.conf"
#
valuename="$1" newvalue="$2" filepath="$3";
sed -i "s+^#\?\(${valuename}\)=.*$+\1=${newvalue}+" "${filepath}";
}

# COMMENTOUTVALUE --------------------------------------------------------
_commentoutvalue ()
{
# Comment out a value in "standard" bash format. For example, given a
# file with a variable defined like this:
#
# VARNAME=valuehere
#
# the value can be commented out to look like this:
#
# #VARNAME=valuehere
#
# using this function:
#
# _commentoutvalue VARNAME "path/to/file.conf"
#
valuename="$1" filepath="$2";
sed -i "s/^\(${valuename}.*\)$/#\1/" "${filepath}";
}

# UNCOMMENTVALUE ---------------------------------------------------------
_uncommentvalue ()
{
# Uncomment out a value in "standard" bash format. For example, given a
# file with a commented out variable defined like this:
#
# #VARNAME=valuehere
#
# the value can be UNcommented out to look like this:
#
# VARNAME=valuehere
#
# using this function:
#
# _uncommentoutvalue VARNAME "path/to/file.conf"
#
valuename="$1" filepath="$2";
sed -i "s/^#\(${valuename}.*\)$/\1/" "${filepath}";
}

# ADDTOLIST --------------------------------------------------------------
_addtolistvar ()
{
# Add to an existing list format variable (simple space delimited list)
# such as VARNAME="item1 item2 item3".
#
# Handles lists enclosed by either "quotes" or (parentheses)
#
# Usage (internal variable)
# _addtolist "new item" newitem newitem
#
if [ "$#" -lt 3 ]; then
newitem="$1" listname="$2"
eval "${listname}=\"${!listname} $newitem\""
else # add to list variable in an existing file
newitem="$1" listname="$2" filepath="$3";
sed -i "s_\(${listname}\s*=\s*[^)]*\))_\1 ${newitem})_" "${filepath}";
sed -i "s_\(${listname}\s*=\s*\"[^\"]*\)\"_\1 ${newitem}\"_" "${filepath}";
fi
}

# DAEMONS ADD/REMOVE -----------------------------------------------------
_daemon ()
{
# TODO: make work for systemd
# add|enable|change disable remove
#
# usage:
# daemon add @ntp
# daemon disable network
# daemon remove hwclock
# daemon remove hwclock network
#
! [ -e "/etc/rc.conf" ] && return 0
ACTION="$1"; shift; DAEMON_LIST="$@"
for DAEMON_ITEM in $DAEMON_LIST; do
DAEMON_BASE=$(echo "$DAEMON_ITEM" | sed "s/[!@]*\(.*\)/\1/") # strip any leading characters
case $ACTION in # assign DAEMON_NEW based on action
    add|change|enable|on) DAEMON_NEW="$DAEMON_ITEM" ;;
    disable|off) DAEMON_NEW="!${DAEMON_BASE}" ;; # normalize in case user passes !daemon format as argument
    remove|delete) DAEMON_NEW="" ;;
esac
echo -e "\nTEST: $ACTION $DAEMON_ITEM -> '$DAEMON_NEW'"
cat /etc/rc.conf | grep DAEMONS
# process /etc/rc.conf
if ! egrep -q "^DAEMONS\s*=.*[!@]?${DAEMON_BASE}" /etc/rc.conf; then # no daemon present
    [ $ACTION != remove ] && sed -i "/^\s*DAEMONS/ s_)_ ${DAEMON_NEW})_" /etc/rc.conf
else
    sed -i "/^\s*DAEMONS/ s_[!@]*${DAEMON_BASE}_${DAEMON_NEW}_" /etc/rc.conf
fi
# housekeeping: clean up extraneous spaces
sed -i "/^\s*DAEMONS/ \
s/  / /g
s/( /(/g
s/ )/)/g" /etc/rc.conf
done
}
# convenience functions
_daemon_add () { _daemon add $@ ; }
_daemon_enable () { _daemon enable $@ ; }
_daemon_change () { _daemon change $@ ; }
_daemon_on () { _daemon on $@ ; }
_daemon_disable () { _daemon disable $@ ; }
_daemon_off () { _daemon off $@ ; }
_daemon_remove () { _daemon remove $@ ; }
_daemon_delete () { _daemon delete $@ ; }

# ANYKEY -----------------------------------------------------------------
_anykey ()
{
# Provide an alert (with optional custom preliminary message) and pause.
#
# Usage:
# _anykey "optional custom message"
#
echo -e "\n$@"; read -sn 1 -p "Any key to continue..."; echo;
}

# DOUBLE CHECK UNTIL MATCH -----------------------------------------------
_double_check_until_match ()
{
# ask for input twice for match confirmation; loop until matches
entry1="x" entry2="y"
while [ "$entry1" != "$entry2" -o -z "$entry1" ]; do
read -s -p "${1:-Passphrase}: " entry1
echo
read -s -p "${1:-Passphrase} again: " entry2
echo
if [ "$entry1" != "$entry2" ]; then
    echo -e "\n${1:-Passphrase} entry doesn't match.\n" 
elif [ -z "$entry1" ]; then
    echo -e "\n${1:-Passphrase} cannot be blank.\n" 
fi
done
_DOUBLE_CHECK_RESULT="$entry1"
}

# TRY_UNTIL_SUCCESS
_try_until_success ()
{
# first argument is statement that must evaluate as true in order to continue
# optional second argument specifies number of tries to limit to
_tries=0; _failed=true; while $_failed; do
_tries=$((_tries+1))
eval "$1"
[ $? -eq 0 ] && _failed=false;
[ -n "$2" -a $_tries -gt $2 ] && return 1;
done
return 0
}

# INSTALLPKG -------------------------------------------------------------
_installpkg ()
{
# Install package(s) from official repositories, no confirmation needed.
# Takes single or multiple package names as arguments.
#
# Usage:
# _installpkg pkgname1 [pkgname2] [pkgname3]
#
pacman -S --noconfirm "$@";
}

# INSTALLAUR -------------------------------------------------------------
_installaur ()
{
# Install package(s) from arch user repository, no confirmation needed.
# Takes single or multiple package names as arguments.
#
# Installs default helper first ($AURHELPER)
#
# Usage:
# _installpkg pkgname1 [pkgname2] [pkgname3]
#
_defaultvalue AURHELPER packer
if command -v $AURHELPER >/dev/null 2>&1; then
    $AURHELPER -S --noconfirm "$@";
else
    pkg=$AURHELPER; orig="$(pwd)"; build_dir=/tmp/build/${pkg}; mkdir -p $build_dir; cd $build_dir;
    for req in wget git jshon; do
        command -v $req >/dev/null 2>&1 || _installpkg $req;
    done
    wget "https://aur.archlinux.org/packages/${pkg:0:2}/${pkg}/${pkg}.tar.gz";
    tar -xzvf ${pkg}.tar.gz; cd ${pkg};
    makepkg --asroot -si --noconfirm; cd "$orig"; rm -rf $build_dir;
    $AURHELPER -S --noconfirm "$@";
fi;
}

#  Begin setup step 1

_defaultvalue HOSTNAME archlinux
_defaultvalue USERSHELL /bin/bash
_defaultvalue FONT Lat2-Terminus16
_defaultvalue FONT_MAP 8859-1_to_uni
_defaultvalue LANGUAGE en_US.UTF-8
_defaultvalue KEYMAP us
_defaultvalue TIMEZONE US/Denver
_defaultvalue MODULES ""
_defaultvalue HOOKS "base udev autodetect pata scsi sata filesystems usbinput fsck"
_defaultvalue KERNEL_PARAMS # "quiet" # set/used in FILESYSTEM,INIT,BOOTLOADER blocks
_defaultvalue AURHELPER packer

# make file system and install base ARCH software

_filesystem_pre_baseinstall;
pacstrap ${MOUNT_PATH} base base-devel
genfstab -p /mnt >> /mnt/etc/fstab
#_filesystem_post_baseinstall;
#umount ${MOUNT_PATH}${EFI_SYSTEM_PARTITION};
#_filesystem_pre_chroot          # PROBABLY UNMOUNT OF BOOT IF INSTALLING UEFI MODE
#_chroot_postscript              # CHROOT AND CONTINUE EXECUTION

pacstrap /mnt syslinux

#pacman -S syslinux
#syslinux-install_update -i -a -m
#nano /boot/syslinux/syslinux.cfg



