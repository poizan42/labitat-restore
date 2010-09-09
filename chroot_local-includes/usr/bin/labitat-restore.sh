#!/bin/sh
if [[ $(id -u) != 0 ]]; then
	exec sudo "$0"
fi

#TODO: needs errorhandling everywhere...
#VERSION="$(cat /etc/labrestore.ver)"
#IMGVER=""
TABLEFMT=msdos
swapoff -a
echo "Welcome to labitat-restore script v0.1"
echo -n "Enter device to restore to (>5GB required) [/dev/sda]: "
read destdev
if [[ "$destdev" == "" ]]; then
	destdev=/dev/sda
fi
if [[ ! -b "$destdev" ]]; then
	echo "$destdev is not a block device!"
	exit
fi
#TODO: check if value is valid.
#TODO: allow size to be given in GB - note that there is a bug in parted that
#      will make it allocate the wrong size when specifying the end of a
#      partition relative to end of disk in GB
# Another note: parted uses SI prefixes - so 1GB = 1000M
# (when it works correctly at least)
echo -n "Enter swap size{K,M} [1024M]: "
read swapsize
if [[ "$swapsize" == "" ]]; then
	swapsize=1024M
fi
echo "WARNING: continuing will DESTROY ALL DATA on $destdev"
echo -n "Write OK if you want to continue: "
read isok
if [[ "$isok" != "OK" ]]; then
	exit
fi
echo "Writing partition table"
parted --script "$destdev" mktable $TABLEFMT
parted --script "$destdev" mkpartfs -- p ext2 0 -$swapsize
parted --script "$destdev" mkpartfs -- p linux-swap -$swapsize -1s
echo "Formatting swap"
sleep 5 # give the kernel a chance to reload the partition table
#TODO: is there a better way to do this? sync is not helping. Maybe just asking
#      fdisk to write the unchanged table again? Would require us to include
#      fdisk though - and wouldn't be portable to other table formats...
mkswap "${destdev}2"
echo "Restoring filesystem image"
fsarchiver restfs -v /live/image/labitat-0.1.fsa id=0,dest="${destdev}1",mkfs=ext3
echo "Configuring fstab"
mount "${destdev}1" /mnt
rootuuid="$(blkid -o value -s UUID "${destdev}1")"
swapuuid="$(blkid -o value -s UUID "${destdev}2")"
cat > /mnt/etc/fstab <<EOF
# /etc/fstab: static file system information.
#
# Use 'blkid -o value -s UUID' to print the universally unique identifier
# for a device; this may be used with UUID= as a more robust way to name
# devices that works even if disks are added and removed. See fstab(5).
#
# <file system> <mount point>   <type>  <options>       <dump>  <pass>
proc            /proc           proc    nodev,noexec,nosuid 0       0
UUID=$rootuuid /               ext3    errors=remount-ro 0       1
UUID=$swapuuid none            swap    sw              0       0
EOF
echo "Installing GRUB"
mount --bind /proc /mnt/proc
mount --bind /dev /mnt/dev
chroot /mnt /usr/sbin/grub-install --recheck "$destdev"
chroot /mnt /usr/sbin/update-grub
umount /mnt/proc
umount /mnt/dev
echo "Clearing persistent udev rules"
cat > /mnt/etc/udev/rules.d/70-persistent-net.rules <<EOF
# This file maintains persistent names for network interfaces.
# See udev(7) for syntax.
#
# Entries are automatically added by the 75-persistent-net-generator.rules
# file; however you are also free to add your own entries.
EOF
cat > /mnt/etc/udev/rules.d/70-persistent-cd.rules <<EOF
# This file maintains persistent names for CD/DVD reader and writer devices.
# See udev(7) for syntax.
#
# Entries are automatically added by the 75-cd-aliases-generator.rules
# file; however you are also free to add your own entries provided you
# add the ENV{GENERATED}=1 flag to your own rules as well.
EOF
#TODO: check validity of hostname
echo -n "Enter new hostname: "
read hostname
echo $hostname > /mnt/etc/hostname
umount /mnt
echo "Done. You may now restart the system."
