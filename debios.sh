#!/usr/bin/env bash
#  ____       _     _
# |  _ \  ___| |__ (_) ___  ___
# | | | |/ _ \ '_ \| |/ _ \/ __|
# | |_| |  __/ |_) | | (_) \__ \
# |____/ \___|_.__/|_|\___/|___/
#
# Chris Iñigo's Bootstrapping Script for Debian 12
# by Chris Iñigo <chris@x1nigo.xyz>

# Things to note:
# - Run this script as ROOT!

### Variables ###

progsfile="https://raw.githubusercontent.com/x1nigo/debios/main/progs.csv"
dotfilesrepo="https://github.com/x1nigo/dotfiles.git"

error() {
	# Log to stderr and exit with failure.
	printf "%s\n" "$1" >&2
	exit 1
}

getdialog() {
	echo "
Updating repositories and installing dependencies...
"
	apt update # Sync and upgrade all packages before starting the main script.
	apt install -y dialog curl rsync || error "Failed to update repositories and install dependencies."
}

openingmsg() {
	dialog --title "Introduction" \
		--msgbox "Welcome to Chris Iñigo's Bootstrapping Script for Debian 12 (Linux)! This will install a fully-functioning linux desktop, which I hope may prove useful to you as it did for me.\\n\\n-Chris" 12 60 || error "Failed to show opening message."
}

getuserandpass(){
	# Prompts user for new username an password.
	name=$(dialog --inputbox "First, please enter a name for the user account." 10 60 3>&1 1>&2 2>&3 3>&1) || exit 1
	while ! echo "$name" | grep -q "^[a-z_][a-z0-9_-]*$"; do
		name=$(dialog --nocancel --inputbox "Username not valid. Give a name beginning with a letter, with only lowercase letters, - or _." 10 60 3>&1 1>&2 2>&3 3>&1)
	done
	pass1=$(dialog --nocancel --passwordbox "Enter a password for that user." 10 60 3>&1 1>&2 2>&3 3>&1)
	pass2=$(dialog --nocancel --passwordbox "Retype password." 10 60 3>&1 1>&2 2>&3 3>&1)
	while ! [ "$pass1" = "$pass2" ]; do
		unset pass2
		pass1=$(dialog --nocancel --passwordbox "Passwords do not match.\\n\\nEnter password again." 10 60 3>&1 1>&2 2>&3 3>&1)
		pass2=$(dialog --nocancel --passwordbox "Retype password." 10 60 3>&1 1>&2 2>&3 3>&1)
	done
}

preinstallmsg() {
	dialog --title "Resolution" \
		--yes-button "Let's go!" \
		--no-button "I...I can barely stand." \
		--yesno "The installation script will be fully automated from this point onwards.\\n\\nAre you ready to begin?" 12 60 || {
		clear
		exit 1
	}
}

adduserandpass() {
	# Adds user `$name` with password $pass1.
	dialog --infobox "Adding user \"$name\"..." 7 50
	useradd -m -s /bin/bash "$name" >/dev/null 2>&1
	export repodir="/home/$name/.local/src"
	mkdir -p "$repodir"
	chown -R "$name":"$name" "$(dirname "$repodir")"
	echo -e "$pass1\n$pass1" | passwd "$name" >/dev/null 2>&1
	unset pass1 pass2
}

permission() {
	echo "$name ALL=(ALL:ALL) NOPASSWD: ALL" > /etc/sudoers.d/00-user-can-sudo
}

finalize () {
	dialog --title "Done!" --msgbox "Installation complete! If you see this message, then there's a pretty good chance that there were no (hidden) errors. You may log out and log back in with your new name.\\n\\n-Chris" 12 60
}

### Main Installation ###

installpkgs() {
	curl -Ls "$progsfile" | sed '/^#/d' > /tmp/progs.csv
	total=$(( $(wc -l < /tmp/progs.csv) ))
	n=0
	while IFS="," read -r tag program description
	do
		n=$(( n + 1 ))
		dialog --infobox "Installing \`$program\` ($n of $total). $description." 8 70
		case $tag in
			G) sudo -u $name git -C "$repodir" clone "$program" >/dev/null 2>&1 ;;
			*) apt install -y "$program" >/dev/null 2>&1 ;;
		esac
	done < /tmp/progs.csv
}

getdotfiles() {
	dialog --infobox "Downloading and installing config files..." 7 60
	sudo -u "$name" git -C "$repodir" clone "$dotfilesrepo" >/dev/null 2>&1
	cd "$repodir"/dotfiles
	shopt -s dotglob && sudo -u "$name" rsync -r * /home/$name/
	# Install the file manager.
	cd /home/$name/.config/lf && chmod +x lfuz scope cleaner && mv lfuz /usr/local/bin/
	# Install Gruvbox GTK theme for the system.
	cd "$repodir"/Gruvbox-GTK-Theme && sudo -u "$name" mv themes /home/$name/.local/share && sudo -u "$name" mv icons /home/$name/.local/share
	# Link specific filed to home directory.
	ln -sf /home/$name/.config/x11/xprofile /home/$name/.xprofile
	ln -sf /home/$name/.config/shell/profile /home/$name/.profile
}

updateudev() {
	mkdir -p /etc/X11/xorg.conf.d
	echo "Section \"InputClass\"
Identifier \"touchpad\"
Driver \"libinput\"
MatchIsTouchpad \"on\"
	Option \"Tapping\" \"on\"
	Option \"NaturalScrolling\" \"on\"
EndSection" > /etc/X11/xorg.conf.d/30-touchpad.conf || error "Failed to update the udev files."
}

compilesl() {
	dialog --infobox "Compiling suckless software..." 7 40
	for dir in $(echo "dwm st dmenu dwmblocks"); do
		cd "$repodir"/"$dir" && sudo make clean install >/dev/null 2>&1
	done
}

removebeep() {
	rmmod pcspkr 2>/dev/null
	echo "blacklist pcspkr" >/etc/modprobe.d/nobeep.conf || error "Failed to remove the beep sound. That's annoying."
}

cleanup() {
	cd # Return to root
 	rm -r ~/debios /tmp/progs.csv
	rm -r "$repodir"/dotfiles "$repodir"/Gruvbox-GTK-Theme
	rm -r /home/$name/.git
	rm -r /home/$name/README.md
 	sudo -u $name mkdir -p /home/$name/.config/gnupg/
	# Give gnupg folder the correct permissions.
  	find /home/$name/.config/gnupg -type f -exec chmod 600 {} \;
	find /home/$name/.config/gnupg -type d -exec chmod 700 {} \;
 	sudo -u $name mkdir -p /home/$name/.config/mpd/playlists/
 	sudo -u $name chmod -R +x /home/$name/.local/bin/* || error "Failed to remove unnecessary files and other cleaning."
	# Remove ifupdown so that NetworkManager actually works.
	! [ -z $(command -v ifupdown) ] && apt remove ifupdown && apt autoremove
	[ -f "/etc/network/interfaces" ] && rm -r /etc/network/interfaces
	# Allow pipewire to function without outside interference
	[ -d "/etc/systemd/users" ] && rm -r /etc/systemd/users
}

depower() {
	echo "$name ALL=(ALL:ALL) ALL" > /etc/sudoers.d/00-user-can-sudo
	echo "$name ALL=(ALL:ALL) NOPASSWD: /usr/bin/shutdown,/usr/bin/poweroff,/usr/bin/reboot,/usr/bin/su,/usr/bin/make clean install,/usr/bin/make install,/usr/bin/mount,/usr/bin/umount,/usr/sbin/cryptsetup,/usr/bin/simple-mtpfs,/usr/bin/fusermount" > /etc/sudoers.d/01-no-password-commands
}

### Main Function ###

# Installs dialog program to run alongside this script.
getdialog

# The opening message.
openingmsg

# Gets the username and password.
getuserandpass || error "Failed to get username and password."

# The pre-install message. Last chance to get out of this.
preinstallmsg|| error "Failed to prompt the user properly."

# Add the username and password given earlier.
adduserandpass || error "Failed to add user and password."

# Grants unlimited permission to the root user (temporarily).
permission || error "Failed to change permissions for user."

# The main installation loop.
installpkgs || error "Failed to install the necessary packages."

# Install the dotfiles in the user's home directory.
getdotfiles || error "Failed to install the user's dotfiles."

# Updates udev rules to allow tapping and natural scrolling, etc.
updateudev

# Compiling suckless software.
compilesl || error "Failed to compile all suckless software."

# Remove the beeping sound of your computer.
removebeep

# Make some finalizing improvements.
cleanup

# De-power the user from infinite greatness.
depower || error "Could not bring back user from his God-like throne of sudo privilege."

# The closing message.
finalize
