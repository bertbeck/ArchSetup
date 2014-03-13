# Arch install step3

pacman -S -y --noconfirm mono
pacman -S -y --noconfirm xsp
pacman -S -y --noconfirm nginx
pacman -S -y --noconfirm mariadb
systemctl start mysqld.service
systemctl start nginx
