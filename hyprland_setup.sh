#!/usr/bin/sh

if pacman -Qs paru > /dev/null ; then
echo "Paru is already installed"
else
if [ ! -d "~/Clone" ]; then
  mkdir -p ~/Clone
fi
git clone https://aur.archlinux.org/paru.git ~/Clone/paru
cd ~/Clone/paru
makepkg -si
fi

paru -S hyprland-git xdg-desktop-portal-hyprland-git hyprpicker-git hypridle-git hyprlock-git hyprpaper-git pyprland-git rofi-lbonn-wayland-git wlogout brillo network-manager-applet grimblast-git thorium-browser-bin arqiver-qt6-git qimgv-light || exit

sudo pacman -S pipewire-alsa pipewire-pulse pipewire-jack wireplumber pamixer pavucontrol playerctl xdg-user-dirs xdg-desktop-portal-gtk waybar polkit-gnome dunst parallel fzf ripgrep fd bat fastfetch kitty htop wl-clipboard cliphist qt5ct qt6ct kvantum kvantum-qt5 noto-fonts mpv thunar tumbler gvfs-mtp syncthing obsidian swappy || exit

sudo pacman -D --asexplicit imagemagick

echo "Do you want to enable Auto-Login?"
select yn in Yes No; do
    case $yn in
        Yes)    sudo cp $(pwd)/Source/Linux/etc/greetd/config.toml /etc/greetd/
		sudo sed -i "s/\"\"/\"$(whoami)\"/" /etc/greetd/config.toml
		break
		;;
         No)   	break
		;;
    esac
done
