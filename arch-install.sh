#!/usr/bin/bash

export dir=$(pwd)

error_message() {
    echo "$1" >&2
}

info_message() {
    echo "$1"
}

list_timezones() {
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
	export TIMEZONE

        if grep -q "^$TIMEZONE$" "$timezones"; then
            info_message "Selected timezone: $TIMEZONE"
            break
        else
            error_message "Error: Invalid selection. Please enter a valid timezone from the list."
        fi
    done

    rm "$timezones"
}

pass_set () {
while true; do
    read -sp "Enter new password for $1: " pass1
    echo
    read -sp "Confirm new password: " pass2
    echo

    if [ "$pass1" = "$pass2" ]; then
	break
    else
        echo "Passwords do not match. Please try again."
    fi
done
}

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
                umount -R /mnt > /dev/null 2>&1

                if [[ "$DISK" =~ ^/dev/nvme ]]; then
                    efi="${DISK}p1"
                    swap="${DISK}p2"
                    device="${DISK}p3"
                else
                    efi="${DISK}1"
                    swap="${DISK}2"
                    device="${DISK}3"
                fi

                swapoff "$swap" > /dev/null 2>&1
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

user_main() {
folders=()
for folder in /mnt/@home/*; do
    if [ -d "$folder" ]; then
        folders+=("$(basename "$folder")")
    fi
done

if [ "${#folders[@]}" -gt 1 ]; then
    echo "Multiple folders found in /mnt/@home/home/. Please select the main folder:"
    
    select user in "${folders[@]}"; do
        if [[ -n "$user" ]]; then
            echo "Main folder selected: $user"
	    uid="-u $(stat -c '%u' "/mnt/@home/"$user"")"
            break
        else
            echo "Invalid selection. Please try again."
        fi
    done

elif [ "${#folders[@]}" -eq 1 ]; then
    user="${folders[0]}"
    echo "Only one folder found. Setting '$user' as the main folder."
    uid="-u $(stat -c '%u' "/mnt/@home/"$user"")"
else
    read -p "Enter the user you would like to create: " user
    echo
    uid=''
fi
}

user_set() {
	mount "$device" /mnt
	if [ "$devicefs" = "btrfs" ]; then
		if [ "$scratch" = "yes" ]; then
		read -p "Enter the user you would like to create: " user
		uid=''
		else
		user_main
		fi
	else
		read -p "Enter the user you would like to create: " user
		echo
                uid=''
	fi
	umount /mnt
}

export -f error_message
export -f info_message
export -f list_timezones
export -f select_timezone

if [ -f "$dir"/ran.sh ]; then
    source "$dir"/ran.sh
else	

if grep -q "GenuineIntel" /proc/cpuinfo; then
    processor=intel-ucode
elif grep -q "AuthenticAMD" /proc/cpuinfo; then
    processor=amd-ucode
else
	echo "Select Processor:"
select yn in Intel Amd Other; do
    case "$yn" in
        Intel)
            processor="intel-ucode"
            break
            ;;
        Amd)
            processor="amd-ucode"
            break
            ;;
	Other)
		processor=''
    esac
done
fi

select_disk
echo "Select Filesystem Type: "
select devicefs in "Btrfs(recommended)" "Ext4"; do
    case "$devicefs" in
"Btrfs(recommended)")
            devicefs="btrfs"
            break
            ;;
         "Ext4")
            devicefs="ext4"
            break
            ;;
    esac
done

select instype in "Install from Scratch" "Install Only @(root) subvolume"; do
	case "$instype" in 
		"Install from Scratch") get_swap_size
			scratch="yes"
			break
			;;
      "Install Only @(root) subvolume")
	 		mount "$device" /mnt
    			cd /mnt
       			btrfs subvolume delete @/var/lib/machines
	                btrfs subvolume delete @/var/lib/portables
	  		btrfs subvolume delete @
     			btrfs subvolume create @
     			cd /
			umount /mnt
	      		break
	      		;;
	esac
done

user_set
pass_set $user
echo
echo -e "#!/usr/bin/bash\nuser_pass=$pass1" > "$dir"/pass.sh
pass_set root
echo
echo -e "root_pass=$pass1" >> "$dir"/pass.sh
read -p "Enter the hostname: " host
echo
select_timezone

if [ "$scratch" = "yes" ]; then
while true; do
        echo
        read -p "Are you sure you want to continue? (yes/no): " CONFIRM

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
mkfs."$devicefs" -f "$device"
mkswap -f "$swap"
fi 
mount "$device" /mnt
fi

source "$dir"/pass.sh
export user
export uid
export root_pass
export user_pass

if [ "$devicefs" = "btrfs" ]; then
if [ ! -f "$dir"/ran.sh ]; then
if [ "$scratch" = "yes" ];then
    cd /mnt
    btrfs subvolume create @
    btrfs subvolume create @var-log
    btrfs subvolume create @var-pkg
    btrfs subvolume create @home
    btrfs subvolume create @home-cache
    btrfs subvolume create @home-config
    btrfs subvolume create @home-local
    btrfs subvolume create @home-clone
    btrfs subvolume create @home-down
    btrfs subvolume create @.snapshots
    
fi
cd /
    umount /mnt
    mount -o subvol=@ "$device" /mnt
    cd /mnt
    mkdir -p {boot/efi,home,.snapshots,var/cache/pacman/pkg,var/log,etc,mnt/defvol}
    mount -o subvol=/ "$device" /mnt/mnt/defvol
    mount -o subvol=@var-log "$device" /mnt/var/log
    mount -o subvol=@var-pkg "$device" /mnt/var/cache/pacman/pkg
    mount -o subvol=@home "$device" /mnt/home
    mount -o subvol=@.snapshots "$device" /mnt/.snapshots
    mount "$efi" /mnt/boot/efi
    swapon "$swap"
fi
btrfs_pkg=grub-btrfs
fi

if [ "$devicefs" = "ext4" ]; then
        if [ ! -f "$dir"/ran.sh ]; then
            cd /mnt
            mkdir -p {boot/efi,etc}
            mount "$efi" /mnt/boot/efi
            swapon "$swap"
            genfstab -U /mnt > /mnt/etc/fstab
        fi
        btrfs_pkg=''
fi
echo -e "#!/usr/bin/bash\nprocessor=$processor\ndevice=$device\nefi=$efi\nswap=$swap\ndevicefs=$devicefs\nuser=$user\nuid='$uid'\nTIMEZONE=$TIMEZONE\nhost=$host" > "$dir"/ran.sh

    echo "$host" > /mnt/etc/hostname
    cd /
    sed -i '/^#ParallelDownloads/s/^#//' /etc/pacman.conf
    pacstrap /mnt base base-devel linux linux-firmware sof-firmware $processor $btrfs_pkg efibootmgr sudo neovim git less networkmanager alsa-utils || {
        echo "Installation failed, Run the script again"
        exit 1
    }

    sed -i '/^#en_US.UTF-8/s/^#//' /mnt/etc/locale.gen
    echo "LANG=en_US.UTF-8" > /mnt/etc/locale.conf
    arch-chroot /mnt bash -c '
        sed -i '/^#ParallelDownloads/s/^#//' /etc/pacman.conf
        grub-install --removable --efi-directory=/boot/efi --bootloader-id=Arch
        echo -e "#!/usr/bin/bash\nsudo grub-mkconfig -o /boot/grub/grub.cfg\nsudo sed -i '\''/^[[:space:]]*echo[[:space:]]*'\'''\''Loading/d'\'' /boot/grub/grub.cfg" > /usr/bin/grubu
	chmod +x /usr/bin/grubu
	grubu
        useradd -m -G wheel,video $uid "$user"
	echo "root:"$root_pass"" | chpasswd
	echo ""$user":"$user_pass"" | chpasswd
        systemctl enable NetworkManager
        systemctl enable systemd-resolved
        if [ -d "/sys/class/power_supply" ]; then
	    echo -e "SUBSYSTEM==\"pci\", ATTR{power/control}=\"auto\"" > /etc/udev/rules.d/pci_pm.rules
	    echo -e "options snd_hda_intel power_save=1" > /etc/modprobe.d/audio_powersave.conf
        fi
	

        echo "Setting timezone to $TIMEZONE..."
        ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime

        info_message "Timezone set to $TIMEZONE."

        locale-gen
    '
    sed -i '/^## Uncomment to allow members of group wheel to execute any command/ {n; s/^# //}' /mnt/etc/sudoers

    if [ "$devicefs" = "btrfs" ]; then
	mkdir -p {/mnt/home/$user/.cache,/mnt/home/$user/.config,/mnt/home/$user/.local,/mnt/home/$user/Clone,/mnt/home/$user/Downloads}
        mount -o subvol=@home-cache "$device" /mnt/home/"$user"/.cache
        mount -o subvol=@home-config "$device" /mnt/home/"$user"/.config
	mount -o subvol=@home-local "$device" /mnt/home/"$user"/.local
        mount -o subvol=@home-clone "$device" /mnt/home/"$user"/Clone
        mount -o subvol=@home-down "$device" /mnt/home/"$user"/Downloads
	arch-chroot /mnt bash -c '
	chattr +C /home/"$user"/.cache
	chattr +C /home/"$user"/.config
	chattr +C /home/"$user"/.local
	chattr +C /home/"$user"/Clone
	chattr +C /home/"$user"/Downloads
        chown "$user":"$user" /home/"$user"/.cache
        chown "$user":"$user" /home/"$user"/.config
	chown "$user":"$user" /home/"$user"/.local
	chown "$user":"$user" /home/"$user"/Clone
        chown "$user":"$user" /home/"$user"/Downloads
	'
        genfstab -U /mnt > /mnt/etc/fstab
        sed -i 's/,subvolid=[0-9]*\s*//g' /mnt/etc/fstab
	sed -i 's/relatime/noatime/g' /mnt/etc/fstab
	sed -i '/^HOOKS=/ s/(\(.*\))/(\1 grub-btrfs-overlayfs)/' /mnt/etc/mkinitcpio.conf
    fi
    	arch-chroot /mnt bash -c '
	mkinitcpio -P
	'
	echo -e "Installation successful. Unmount and Reboot Now?"
	select ynr in Yes No; do
		case $ynr in 
			Yes)	umount -R /mnt
				swapoff $swap
				reboot
				;;
			No)	break
				;;
		esac
	done
