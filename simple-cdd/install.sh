if [[ $EUID -ne 0 ]]; then
  echo "You must be root to run this script. Us 'su' to become root" >&2
  exit 1
fi
apt update && apt upgrade -y
apt install simple-cdd sudo
read -p "Pleas type the username of your defualt user (non root): " CURRENT_USER
sudo adduser $CURRENT_USER sudo
echo "$CURRENT_USER ALL=(ALL:ALL) ALL" >> /etc/sudoers
#sudo apt-get install --reinstall debian-archive-keyring
