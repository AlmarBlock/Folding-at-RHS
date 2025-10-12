#Build ISO
build-simple-cdd --conf simple-cdd.conf --debug
cd tmp/cd-build/bookworm
FILE="boot1/isolinux/menu.cfg"

if [ -f "$FILE" ]; then
  # Entferne die letzten zwei Zeilen und speichere die Änderungen
  sed -i '' -e :a -e '$d;N;2,2ba' -e 'P;D' "$FILE"
  echo "Die letzten zwei Zeilen wurden aus $FILE entfernt."
else
  echo "Die Datei $FILE existiert nicht."
  nano boot1/isolinux/menu.cfg
fi

xorriso -as mkisofs -r -checksum_algorithm_iso sha256,sha512 -V 'Debian 12 amd64 1' -o /home/debian/images/debian-12-amd64-CD-1.iso -J -joliet-long -cache-inodes -isohybrid-mbr syslinux/usr/lib/ISOLINUX/isohdpfx.bin -b isolinux/isolinux.bin -c isolinux/boot.cat -boot-load-size 4 -boot-info-table -no-emul-boot -eltorito-alt-boot -e boot/grub/efi.img -no-emul-boot -isohybrid-gpt-basdat -isohybrid-apm-hfsplus boot1 CD1
