#!/usr/bin/bash

if [ ! -d "~/Clone" ]; then
	mkdir -p ~/Clone
fi

cd ~/Clone
git clone https://github.com/flutter/flutter.git
paru -S android-sdk android-sdk-build-tools android-sdk-cmdline-tools-latest android-platform android-sdk-platform-tools jdk21-openjdk
sudo cp -R /opt/android-sdk ~/Clone
sudo chown -R $(whoami):$(whoami) ~/Clone/android-sdk
flutter --disable-analytics
yes | flutter doctor --android-licenses
echo "Log out and log in again to enable flutter"
