#!/bin/bash
if [[ "$(id -u)" != 0 ]]; then
	exec sudo "$0"
fi

function mkpartforce()
{
	destdev="$1"
	shift
	if ! parted --script "$destdev" mkpart -- "$@"; then
		parted "$destdev" mkpart -- "$@" yes
	fi
	return $?
}

#TODO: needs errorhandling everywhere...
#VERSION="$(cat /etc/labrestore.ver)"
#IMGVER=""
TABLEFMT=msdos
swapoff -a
echo "Welcome to labitat-restore script v0.2"
echo -n "Enter device to restore to (>5GB required) [/dev/sda]: "
read destdev
if [[ "$destdev" == "" ]]; then
	destdev=/dev/sda
fi
if [[ ! -b "$destdev" ]]; then
	echo "$destdev is not a block device!"
	exit
fi
# note: there is a bug in parted that
#      will make it allocate the wrong size when specifying the end of a
#      partition relative to end of disk in GB
# Another note: parted uses SI prefixes - so 1GB = 1000M
# (when it works correctly at least)
# Let's just give sizes to parted in bytes and calculate the correct size
# ourself
ok=0
while [[ $ok == 0 ]]; do
	echo -n "Enter swap size{B,K,M,G,T} [1G]: "
	read swapsize
	if [[ "$swapsize" == "" ]]; then
		swapsize=1G
	fi
	unit="$(echo "$swapsize" | sed -re 's/^[0-9]+//')"
	swapsize="$(echo "$swapsize" | sed -re 's/^([0-9]+).*/\1/')"
	if [[ "$swapsize" == "" ]]; then
		echo "Invalid value \"$unit\""
		continue
	fi
	case "$unit" in
		T)
			swapsize=$[$swapsize*(1024**4)]
		;;
		G)
			swapsize=$[$swapsize*(1024**3)]
		;;
		M)
			swapsize=$[$swapsize*(1024**2)]
		;;
		K)
			swapsize=$[$swapsize*1024]
		;;
		B)
		;;
		*)
			echo "Unknown unit \"$unit\". Use one of B,K,M,G or T."
			continue
		;;
	esac
	ok=1
done
unset ok
#echo "\$swapsize=$swapsize" 
#exit

echo "WARNING: continuing will DESTROY ALL DATA on $destdev"
echo -n "Write OK if you want to continue: "
read isok
if [[ "$isok" != "OK" ]]; then
	exit
fi
echo "Writing partition table"
embedareasize=$[1024**2]
parted --script "$destdev" mktable $TABLEFMT
mkpartforce "$destdev" p ext2 ${embedareasize}B -${swapsize}B
mkpartforce "$destdev" p linux-swap -${swapsize}B -1s
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
