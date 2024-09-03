#!/usr/bin/bash

function install {
 cd /
 pacstrap -K /mnt base base-devel linux linux-firmware sof-firmware "$processor" "$btrfs_pkg" efibootmgr sudo neovim git networkmanager greetd thermald fish alsa-utils || { echo "Installation failed, Run the script again"; exit 1; }
 cp -r "$dir"/Source/Linux/. /mnt/
 echo "KEYMAP=$(localectl status | grep 'VC Keymap' | awk '{print $3}')" > /mnt/etc/vconsole.conf
 mkdir -p /mnt/home/"$user"/Clone
 git clone "$dir" /mnt/home/"$user"/Clone
 arch-chroot /mnt bash -c '
 grub-install --efi-directory=/boot/efi --bootloader-id=Arch
 echo "Enter root account password:"
 passwd
 useradd -m -G wheel,video "$user"
 echo "Enter user account password:"
 passwd "$user"
 systemctl enable NetworkManager
 systemctl enable systemd-resolved
 systemctl enable greetd
if [ -d "/sys/class/power_supply" ]; then
 systemctl enable thermald
 systemctl enable pcie_aspm.timer
else
	pacman -Runs thermald
fi
 
 sed -i "s/\"\"/\""$user"\"/" /etc/greetd/config.toml
 chsh -s /usr/bin/fish
 chsh -s /usr/bin/fish "$user"
 echo -e "Insalltion successful\nYou may Reboot now"
 cd /
'
}

dir=$(pwd)
if [ ! -f "$dir"/ran.sh ]; then
echo "Select Processor:"
select yn in Intel Amd; do
    case "$yn" in
        Intel)  processor=intel-ucode
		break
		;;
        Amd)    processor=amd-ucode
		break
		;;
    esac
done
read -p "Enter install device path(/dev/xxx): " device
read -p "Enter efi device path(/dev/xxx): " efi
read -p "Enter swap device path(/dev/xxx): " swap
read -p "Enter the user you would like to create: " user
type=$(blkid -o value -s TYPE "$device")
echo -e "#!/usr/bin/bash\nprocessor="$processor"\ndevice="$device"\nefi="$efi"\nswap="$swap"\nuser="$user"\ntype="$type"" > "$dir"/ran.sh
else
	source "$dir"/ran.sh
fi

if [ "$type" != "btrfs" ]; then

	if [ "$type" = "ext4" ]; then
		mount "$device" /mnt
		cd /mnt
		mkdir -p {boot/efi,etc}
		btrfs_pkg=''
		mount "$efi" /mnt/boot/efi
 		swapon "$swap"
                genfstab -U /mnt >> /mnt/etc/fstab
		install
		exit
	else
		echo "Wrong filesystem - "$type""
		exit
	fi
fi

mount "$device" /mnt
cd /mnt
btrfs subvolume create @
btrfs subvolume create @var-log
btrfs subvolume create @var-pkg
btrfs subvolume create @home
btrfs subvolume create @home-cache
btrfs subvolume create @home-config
btrfs subvolume create @home-dots
btrfs subvolume create @home-down
btrfs subvolume create @.snapshots
cd /
umount /mnt

mount -o subvol=@ "$device" /mnt
cd /mnt
mkdir -p {boot/efi,home,.snapshots,var/cache/pacman/pkg,var/log,etc}
mount -o subvol=@var-log "$device" /mnt/var/log
mount -o subvol=@var-pkg "$device" /mnt/var/cache/pacman/pkg
mount -o subvol=@home "$device" /mnt/home
cp "$dir"/Source/Btrfs-specific/yabsnap /mnt/etc/
btrfs_pkg=grub_btrfs
mount "$efi" /mnt/boot/efi
swapon "$swap"
genfstab -U /mnt >> /mnt/etc/fstab
sed -i 's/,subvolid=[0-9]*\s*//g' /mnt/etc/fstab
install
