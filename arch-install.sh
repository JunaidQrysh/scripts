#!/usr/bin/bash

error_message() {
    echo "$1" >&2
}

info_message() {
    echo "$1"
}

list_timezones() {
    echo "Here is the list of available timezones:"
    echo "Use the arrow keys to scroll, and press 'q' to quit the pager."
    find /usr/share/zoneinfo -type f | sed 's|/usr/share/zoneinfo/||' | sort | less
}

select_timezone() {
    local timezones
    local choice

    timezones=$(mktemp)
    find /usr/share/zoneinfo -type f | sed 's|/usr/share/zoneinfo/||' | sort > "$timezones"

    echo "You will now see a list of available timezones."
    echo "Use the arrow keys to scroll through the list, and press 'q' to exit the pager."
    echo "Please make a note of the timezone you want to select."
    echo
    read -p "Press Enter to continue and view the list of timezones..."

    list_timezones

    echo
    while true; do
        read -p "Enter the timezone from the list (e.g., Europe/Paris): " TIMEZONE

        if grep -q "^$TIMEZONE$" "$timezones"; then
            info_message "Selected timezone: $TIMEZONE"
            break
        else
            error_message "Error: Invalid selection. Please enter a valid timezone from the list."
        fi
    done

    rm "$timezones"
}

function install {
 echo "$host" > /mnt/etc/hostname
 cd /
 cp -rn "$dir"/Source/Linux/. /mnt/
 pacstrap -K /mnt base base-devel linux linux-firmware sof-firmware "$processor" "$btrfs_pkg" efibootmgr sudo neovim git networkmanager greetd thermald fish alsa-utils || { echo "Installation failed, Run the script again"; exit 1; }
 echo "KEYMAP=$(localectl status | grep 'VC Keymap' | awk '{print $3}')" > /mnt/etc/vconsole.conf
 
 arch-chroot /mnt bash -c '
 grub-install --removable --efi-directory=/boot/efi --bootloader-id=Arch
 grubu
 echo "Enter root account password:"
 while [ true ]
 do
 passwd && break
 done
 useradd -m -G wheel,video "$user"
 echo "Enter user account password:"
 while [ true ]
 do
 passwd "$user" && break
 done
 systemctl enable NetworkManager
 systemctl enable systemd-resolved
 systemctl enable greetd
if [ -d "/sys/class/power_supply" ]; then
 systemctl enable thermald
 systemctl enable pcie_aspm.timer
else
	pacman -Runs thermald
fi
 mkdir -p /mnt/home/"$user"/Clone
 git clone "$dir" /mnt/home/"$user"/Clone
select_timezone

echo "Setting timezone to $TIMEZONE..."
ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime

info_message "Timezone set to $TIMEZONE."

locale-gen

 sed -i "s/\"\"/\""$user"\"/" /etc/greetd/config.toml
 chsh -s /usr/bin/fish
 chsh -s /usr/bin/fish "$user"
 echo -e "Insalltion successful\nYou may Reboot now"
 cd /
'
}

dir=$(pwd)
if [ -f "$dir"/ran.sh ]; then
source "$dir"/ran.sh
else



list_disks() {
    echo
    echo "Available disks:"
    lsblk -d -o NAME,SIZE,TYPE | grep "^sd\|^nvme\|^vd" | awk '{print "/dev/" $1 " " $2}'
    echo
}

select_disk() {
    local disks=()
    local choice
    local i=1
    
    mapfile -t disks < <(lsblk -d -o NAME,SIZE,TYPE | grep "^sd\|^nvme\|^vd" | awk '{print "/dev/" $1 " " $2}')
    
    while true; do
        list_disks
        
        for i in "${!disks[@]}"; do
            echo "$((i + 1))) ${disks[$i]}"
        done

        echo
        read -p "Select a disk by number (1-${#disks[@]}): " choice
        
        if [[ "$choice" -ge 1 && "$choice" -le ${#disks[@]} ]]; then
            DISK=${disks[$((choice - 1))]}
            info_message "Selected disk: $DISK"
            break
        else
            error_message "Error: Invalid selection. Please enter a number between 1 and ${#disks[@]}."
        fi
    done
}

get_swap_size() {
    while true; do
        echo
        read -p "Enter the size of the swap partition (e.g., 2G for 2 GB): " SWAP_SIZE
        
        if [[ "$SWAP_SIZE" =~ ^[0-9]+[MGK]?$ ]]; then
            info_message "Swap size: $SWAP_SIZE"
            break
        else
            error_message "Error: Invalid size format. Please enter a size like '2G' or '512M'."
        fi
    done
}

select_disk

get_swap_size

while true; do
    echo
    read -p "Are you sure you want to partition $DISK? This operation will modify the disk. (yes/no): " CONFIRM
    
    if [[ "$CONFIRM" == "yes" ]]; then
        break
    elif [[ "$CONFIRM" == "no" ]]; then
        info_message "Operation cancelled."
        exit 0
    else
        error_message "Please enter 'yes' or 'no'."
    fi
done

DISK_SIZE_SECTORS=$(gdisk -l "$DISK" | grep "Disk size" | awk '{print $4}')
EFI_SIZE_SECTORS=$((100 * 1024 * 2))  # 100 MB in sectors (assuming 512 bytes per sector)

SWAP_SIZE_SECTORS=$(echo "$SWAP_SIZE" | awk '/G/ {print $1 * 2048000} /M/ {print $1 * 409600} /K/ {print $1 * 409.6} /[0-9]/ {print $1 * 2048000}')

LINUX_SIZE_SECTORS=$((REMAINING_SIZE_SECTORS - SWAP_SIZE_SECTORS))

{
    echo
    echo "Creating partitions on $DISK..."
    echo "o"         
    echo "n"        
    echo "1"         
    echo ""          
    echo "+100M"    
    echo "ef00"     
    
    echo "n"        
    echo "2"         
    echo ""          
    echo "+${SWAP_SIZE}" 
    echo "8200"      
    
    echo "n"         
    echo "3"         
    echo ""          
    echo ""          
    echo "8300"      
    
    echo "w"        
} | gdisk "$DISK" || error_message "Failed to partition the disk."

info_message "Partitioning completed successfully."

sleep 2

if [[ "$DISK" =~ ^/dev/nvme ]]; then
    efi="${DISK}p1"
    swap="${DISK}p2"
    device="${DISK}p3"
else
    efi="${DISK}1"
    swap="${DISK}2"
    device="${DISK}3"
fi

mkfs.fat -f -F32 "$efi"
mkfs.btrfs -f "$device"
mkswap -f "$swap"

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
read -p "Enter the user you would like to create: " user
export user="$user"
read -p "Enter the hostname: " host
type=$(blkid -o value -s TYPE "$device")
echo -e "#!/usr/bin/bash\nprocessor="$processor"\ndevice="$device"\nefi="$efi"\nswap="$swap"\nexport user="$user"\ntype="$type"\nhost=$host" > "$dir"/ran.sh
fi

if [ "$type" != "btrfs" ]; then

	if [ "$type" = "ext4" ]; then
		mount "$device" /mnt
		cd /mnt
		mkdir -p {boot/efi,etc}
		btrfs_pkg=''
		mount "$efi" /mnt/boot/efi
 		swapon "$swap"
                genfstab -U /mnt > /mnt/etc/fstab
		install
		exit
	else
		echo "Wrong filesystem - "$type""
		rm "$dir"/ran.sh
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
cp "$dir"/Source/Btrfs-specific/. /mnt/etc/
btrfs_pkg=grub-btrfs
mount "$efi" /mnt/boot/efi
swapon "$swap"
genfstab -U /mnt > /mnt/etc/fstab
sed -i 's/,subvolid=[0-9]*\s*//g' /mnt/etc/fstab
install
