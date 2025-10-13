# Build ISO
build-simple-cdd --conf simple-cdd.conf --debug # Executes the build-simple-cdd command with the specified configuration file in debug mode, providing detailed information about the build process.

## In tmp/cd-build/bookworm/boot1/isolinux/menu.cfg, there are two lines related to Debian's voice support.
## These lines must be removed to ensure the automated installation process works correctly.
cd tmp/cd-build/bookworm 
FILE="boot1/isolinux/menu.cfg" # Defines the path to the menu.cfg file.

# Checks if the specified file exists. If it does, removes the last two lines from the file.
if [ -f "$FILE" ]; then
  sed -i '' -e :a -e '$d;N;2,2ba' -e 'P;D' "$FILE"
  echo "The last two lines were removed from $FILE."
else
  echo "The file $FILE does not exist."
  nano boot1/isolinux/menu.cfg
fi

# Runs the ISO creation process again using the updated menu.cfg file. 
# If this command changes in future versions, inspect the output of the initial build-simple-cdd command
# and locate a similar command to replace this one accordingly.
xorriso -as mkisofs -r -checksum_algorithm_iso sha256,sha512 -V 'Debian 12 amd64 1' -o /home/debian/images/debian-12-amd64-CD-1.iso -J -joliet-long -cache-inodes -isohybrid-mbr syslinux/usr/lib/ISOLINUX/isohdpfx.bin -b isolinux/isolinux.bin -c isolinux/boot.cat -boot-load-size 4 -boot-info-table -no-emul-boot -eltorito-alt-boot -e boot/grub/efi.img -no-emul-boot -isohybrid-gpt-basdat -isohybrid-apm-hfsplus boot1 CD1
