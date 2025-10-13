# Checks if the script is running as root
if [[ $EUID -ne 0 ]]; then
  echo "You must be root to run this script. Use 'su' to switch to the root account." >&2
  exit 1
fi

# Updates the APT package index and installs available updates
apt update && apt upgrade -y

# Installs the required packages for building the ISO
apt install simple-cdd sudo

# Adds the specified non-root user to the sudo group to allow administrative privileges
read -p "Please enter the username of your default non-root user that will run the build process: " CURRENT_USER
sudo adduser $CURRENT_USER sudo
echo "$CURRENT_USER ALL=(ALL:ALL) ALL" >> /etc/sudoers

## The following command can help resolve errors during the build process,
## but it is usually not required:
# sudo apt-get install --reinstall debian-archive-keyring


chmod +x build.sh
chmod +x simple-cdd.conf
chmod +x profiles/my.downloads
chmod +x profiles/my.excludes
chmod +x profiles/my.packages
chmod +x profiles/my.postinst
chmod +x profiles/my.preseed
chmod +x profiles/my.udebs