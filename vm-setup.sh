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

sudo pacman -S go linux-headers dkms cmake qemu-base qemu-chardev-spice qemu-hw-usb-host qemu-audio-spice qemu-hw-display-qxl virt-manager dnsmasq iptables-nft || exit

echo -e "unix_sock_group = \"libvirt\"\nunix_sock_rw_perms = \"0770\"" | sudo tee -a /etc/libvirt/libvirt.conf
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

curl https://looking-glass.io/artifact/bleeding/source -o looking-glass.tar.gz
mkdir -p ~/Clone/looking-glass
tar -xf looking-glass.tar.gz --strip-component=1 -C ~/Clone/looking-glass
rm looking-glass.tar.gz
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

git clone https://github.com/HikariKnight/quickpassthrough.git ~/Clone/quickpassthrough
cd ~/Clone/quickpassthrough
go mod download
CGO_ENABLED=0 go build -ldflags="-X github.com/HikariKnight/quickpassthrough/internal/version.Version=$(git rev-parse --short HEAD)" -o quickpassthrough cmd/main.go
./quickpassthrough

sudo usermod -a -G libvirt $(whoami)
sudo systemctl enable libvirtd
sudo virsh net-autostart default

sudo pacman -Runs go cmake
sudo rm -rf ~/go

echo "Edit the file /etc/libvirt/qemu.conf and uncomment the cgroup_device_acl block, adding /dev/kvmfr0" 
echo "Press any key to open /etc/libvirt/qemu.conf..."
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