#!/usr/bin/bash

echo "READ vm-config.txt AFTER reboot, Continue?"
select yn in Ok No; do
    case $yn in
        Ok)    break
		;;
        No)    exit
		;;
    esac
done

sudo pacman -S --needed go linux-headers dkms cmake qemu-base qemu-chardev-spice qemu-audio-spice qemu-hw-display-qxl virt-manager dnsmasq iptables-nft || exit

echo "Install looking glass?"
select lg in Yes No; do
case "$lg" in 
Yes)if [ ! -d ~/Clone/looking-glass ]; then 
curl https://looking-glass.io/artifact/bleeding/source -o looking-glass.tar.gz || exit
mkdir -p ~/Clone/looking-glass
tar -xf looking-glass.tar.gz --strip-component=1 -C ~/Clone/looking-glass
rm looking-glass.tar.gz
fi
cd ~/Clone/looking-glass
mkdir client/build
cd client/build
cmake ../
make
sudo make install
cd ~/Clone/looking-glass/module
sudo dkms install "."
echo -e "options kvmfr static_size_mb=128" | sudo tee /etc/modprobe.d/kvmfr.conf
echo -e "kvmfr" | sudo tee /etc/modules-load.d/kvmfr.conf
echo -e "SUBSYSTEM==\"kvmfr\", OWNER=\"$(whoami)\", GROUP=\"kvm\", MODE=\"0660\"" | sudo tee /etc/udev/rules.d/99-kvmfr.rules
echo -e "[Desktop Entry]\nName=Windows\nIcon=windows\nType=Application\nExec=/usr/bin/bash -c 'virsh start win11; looking-glass-client'" > ~/.local/share/applications/windows.desktop
break
;;
No)break
   ;;
esac
done

echo "Setup Gpu Passthrough?"
select gp in Yes No; do
case "$gp" in
Yes)git clone https://github.com/HikariKnight/quickpassthrough.git ~/Clone/quickpassthrough
cd ~/Clone/quickpassthrough || exit
go mod download
CGO_ENABLED=0 go build -ldflags="-X github.com/HikariKnight/quickpassthrough/internal/version.Version=$(git rev-parse --short HEAD)" -o quickpassthrough cmd/main.go
./quickpassthrough
break
;;
No)break
   ;;
esac
done

if [ ! -d ~/.vm ]; then
	       mkdir -p ~/.vm
fi
device=$(findmnt -no SOURCE / | sed 's/\[.*\]//')
if [ $(findmnt -n -o FSTYPE -T /) = btrfs ]; then
	cd /mnt/defvol
	if ! sudo btrfs subvolume list /mnt/defvol | grep -q "@vm"; then
	sudo btrfs subvolume create @vm
	fi
	if ! mountpoint -q ~/.vm; then
	sudo mount -o subvol=@vm "$device" ~/.vm
	sudo chown $(whoami):$(whoami) ~/.vm
			chattr +C ~/.vm
	fi
	if ! grep -q "$HOME/.vm" /etc/fstab; then
	UUID=$(grep "UUID=" /etc/fstab | grep "btrfs" | head -n 1 | awk '{print $1}' | cut -d'=' -f2)
        MOUNT_OPTIONS=$(grep "UUID=" /etc/fstab | grep "btrfs" | head -n 1 | awk '{print $4}' | sed 's/,\?subvol=[^,]*//')
	NEW_ENTRY="UUID=$UUID\t$HOME/.vm\tbtrfs\t$MOUNT_OPTIONS,subvol=@vm\t0 0"
	echo -e "\n#$device " | sudo tee -a /etc/fstab
	echo -e "$NEW_ENTRY" | sudo tee -a /etc/fstab
	echo "New mount point added to fstab."
	echo "Please check /etc/fstab to ensure everything is correct."
	fi
fi

echo -e "unix_sock_group = \"libvirt\"\nunix_sock_rw_perms = \"0770\"" | sudo tee /etc/libvirt/libvirt.conf
sudo mkdir -p /etc/libvirt/hooks/
echo -e "#!/usr/bin/bash
command=\$2

if [ \"\$command\" = \"started\" ]; then
    systemctl set-property --runtime -- system.slice AllowedCPUs=0,1,8,9
    systemctl set-property --runtime -- user.slice AllowedCPUs=0,1,8,9
    systemctl set-property --runtime -- init.scope AllowedCPUs=0,1,8,9
elif [ \"\$command\" = \"release\" ]; then
    systemctl set-property --runtime -- system.slice AllowedCPUs=0-15
    systemctl set-property --runtime -- user.slice AllowedCPUs=0-15
    systemctl set-property --runtime -- init.scope AllowedCPUs=0-15
fi" | sudo tee /etc/libvirt/hooks/qemu

sudo usermod -a -G libvirt $(whoami)
sudo systemctl enable libvirtd

sudo pacman -Runs go cmake
sudo rm -rf ~/go

echo "Edit the file /etc/libvirt/qemu.conf and uncomment the cgroup_device_acl block, adding /dev/kvmfr0" 
read -p "Press enter to open /etc/libvirt/qemu.conf..."
sudoedit /etc/libvirt/qemu.conf
echo "Reboot to complete installation"
select yn in Reboot Wait; do
    case $yn in
        Reboot) break
		;;
          Wait)	;;
    esac
done
sudo reboot
