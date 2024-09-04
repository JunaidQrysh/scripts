#!/usr/bin/bash

export dir=$(pwd)

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

export -f error_message
export -f info_message
export -f list_timezones
export -f select_timezone

install() {
    echo "$host" > /mnt/etc/hostname
    cd /

    pacstrap -K /mnt base base-devel linux linux-firmware sof-firmware "$processor" "$btrfs_pkg" efibootmgr sudo neovim git networkmanager greetd thermald fish alsa-utils less || {
        echo "Installation failed, Run the script again"
        exit 1
    }

    sed -i '/^#en_US.UTF-8/s/^#//' /mnt/etc/locale.gen
    echo "LANG=en_US.UTF-8" > /mnt/etc/locale.conf
    arch-chroot /mnt bash -c '
        grub-install --removable --efi-directory=/boot/efi --bootloader-id=Arch
        grub-mkconfig -o /boot/grub/grub.cfg
        echo "Enter root account password:"
        while true; do
            passwd && break
        done
        useradd -m -G wheel,video "$user"
        echo "Enter user account password:"
        while true; do
            passwd "$user" && break
        done
        systemctl enable NetworkManager
        systemctl enable systemd-resolved
        systemctl enable greetd
	echo -e "#!/usr/bin/bash\nsudo grub-mkconfig -o /boot/grub/grub.cfg" > /usr/bin/update-grub
        if [ -d "/sys/class/power_supply" ]; then
	    echo -e "SUBSYSTEM==\"pci\", ATTR{power/control}=\"auto\"" > /etc/udev/rules.d/pci_pm.rules
	    echo -e "options snd_hda_intel power_save=1" > /etc/modprobe.d/audio_powersave.conf
            systemctl enable thermald
        else
            pacman -Runs thermald
        fi
        rm /scripts
        mkdir -p {/home/"$user"/.cache/,/home/"$user"/.config/,/home/"$user"/.dotfiles/,/home/"$user"/Download/}
        chown "$user":"$user" /home/"$user"/.cache
        chown "$user":"$user" /home/"$user"/.config
        chown "$user":"$user" /home/"$user"/.dotfiles
        chown "$user":"$user" /home/"$user"/Download
        select_timezone

        echo "Setting timezone to $TIMEZONE..."
        ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime

        info_message "Timezone set to $TIMEZONE."

        locale-gen

        sed -i "s/\"\"/\"$user\"/" /etc/greetd/config.toml
        chsh -s /usr/bin/fish
        chsh -s /usr/bin/fish "$user"
	exit
    '
    sed -i '/^## Uncomment to allow members of group wheel to execute any command/ {n; s/^# //}' /mnt/etc/sudoers

    if [ "$type" = "btrfs" ]; then
        mount -o subvol=@home-cache "$device" /mnt/home/"$user"/.cache
        mount -o subvol=@home-config "$device" /mnt/home/"$user"/.config
        mount -o subvol=@home-dots "$device" /mnt/home/"$user"/.dotfiles
        mount -o subvol=@home-down "$device" /mnt/home/"$user"/Download
        genfstab -U /mnt >> /mnt/etc/fstab
        sed -i 's/,subvolid=[0-9]*\s*//g' /mnt/etc/fstab
	sed -i '/^HOOKS=/ s/(\(.*\))/(\1 grub-btrfs-overlayfs)/' /mnt/etc/mkinitcpio.conf
    fi
    	arch-chroot /mnt bash -c '
	mkinitcpio -P
	exit
	'
	umount -R /mnt
	swapoff $swap
	echo -e "Installation successful\nYou may reboot now"
}

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
                DISK=$(echo ${disks[$((choice - 1))]} | awk '{print $1}')
                umount -R /mnt

                if [[ "$DISK" =~ ^/dev/nvme ]]; then
                    efi="${DISK}p1"
                    swap="${DISK}p2"
                    device="${DISK}p3"
                else
                    efi="${DISK}1"
                    swap="${DISK}2"
                    device="${DISK}3"
                fi

                swapoff "$swap"
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

    {
        echo "o"         
        echo "y"
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
        echo "y"
    } | gdisk "$DISK" || error_message "Failed to partition the disk."

    info_message "Partitioning completed successfully."

    sleep 5

mkfs.fat -F32 "$efi"
mkfs.btrfs -f "$device"
mkswap -f "$swap"

mount "$device" /mnt

echo "Select Processor:"
select yn in Intel Amd; do
    case "$yn" in
        Intel)
            processor=intel-ucode
            break
            ;;
        Amd)
            processor=amd-ucode
            break
            ;;
    esac
done

read -p "Enter the user you would like to create: " user
export user="$user"

read -p "Enter the hostname: " host
type=$(blkid -o value -s TYPE "$device")

if [ "$type" != "btrfs" ]; then
    if [ "$type" = "ext4" ]; then
        if [ ! -f "$dir"/ran.sh ]; then
            cd /mnt
            mkdir -p {boot/efi,etc}
            mount "$efi" /mnt/boot/efi
            swapon "$swap"
            genfstab -U /mnt >> /mnt/etc/fstab
        fi
        echo -e "#!/usr/bin/bash\nprocessor=$processor\ndevice=$device\nefi=$efi\nswap=$swap\nexport user=$user\ntype=$type\nhost=$host" > "$dir"/ran.sh
        btrfs_pkg=''
        install
        exit
    else
        echo "Wrong filesystem - $type"
        rm "$dir"/ran.sh
        exit
    fi
fi

if [ ! -f "$dir"/ran.sh ]; then
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
    mount "$efi" /mnt/boot/efi
    swapon "$swap"
fi

echo -e "#!/usr/bin/bash\nprocessor=$processor\ndevice=$device\nefi=$efi\nswap=$swap\nexport user=$user\ntype=$type\nhost=$host" > "$dir"/ran.sh
btrfs_pkg=grub-btrfs
install
