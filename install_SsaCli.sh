#!/bin/bash

echo "👉 Bắt đầu cài đặt Zabbix Agent 2 cho AlmaLinux 9..."
#sudo dnf remove zabbix-agent2 -y
#sudo dnf remove zabbix-release -y
#sudo rm -f /etc/yum.repos.d/zabbix*.repo
#sudo rm -rf /etc/zabbix
#sudo rm -rf /var/log/zabbix

# Cài đặt Zabbix Agent 2
wget https://repo.zabbix.com/zabbix/7.2/release/debian/pool/main/z/zabbix-release/zabbix-release_latest_7.2+debian12_all.deb
dpkg -i zabbix-release_latest_7.2+debian12_all.deb
apt update
apt install zabbix-agent2
apt install zabbix-agent2-plugin-mongodb zabbix-agent2-plugin-mssql zabbix-agent2-plugin-postgresql

# Lấy địa chỉ IP hiện tại của server
SERVER_IP=$(hostname -I | awk '{print $1}')
STATIC_IP="203.188.166.239"
echo "👉 IP của server: $SERVER_IP"
echo "👉 Cấu hình Zabbix với Server=$STATIC_IP,$SERVER_IP và ServerActive=$STATIC_IP"

# Cập nhật file cấu hình Zabbix Agent
sed -i "s/^Server=.*/Server=$STATIC_IP,$SERVER_IP/" /etc/zabbix/zabbix_agent2.conf
sed -i "s/^ServerActive=.*/ServerActive=$STATIC_IP/" /etc/zabbix/zabbix_agent2.conf
sed -i "s/^Hostname=.*/Hostname=$SERVER_IP/" /etc/zabbix/zabbix_agent2.conf

cat <<EOF >> /etc/zabbix/zabbix_agent2.conf
UserParameter=raid.status.custom,/usr/local/bin/check_raid_status_custom.sh
UserParameter=raid.disk_status,/usr/local/bin/check_ssacli_status.sh
EOF

echo "👉 Tạo script kiểm tra RAID..."
cat <<'EOF' > /usr/local/bin/check_raid_status_custom.sh
#!/bin/bash
raid_arrays=$(cat /proc/mdstat | grep ^md | awk '{print $1}')
total_failed_devices=0
for array in $raid_arrays; do
    failed_devices=$(sudo mdadm --detail /dev/$array | grep "Failed Devices" | awk '{print $4}')
    total_failed_devices=$((total_failed_devices + failed_devices))
done
echo $total_failed_devices
EOF


# Tạo script kiểm tra RAID
echo "👉 Tạo script kiểm tra RAID..."
cat <<'EOF' > /usr/local/bin/check_ssacli_status.sh
#!/bin/bash
slot=$(sudo /usr/sbin/ssacli controller all show | grep -oP '(?<=Slot )[0-9]+')
if [ -z "$slot" ]; then
    echo "No RAID controller detected! Please check if the RAID controller is properly recognized."
    exit 1
fi
output=$(sudo /usr/sbin/ssacli controller slot=$slot physicaldrive all show status | grep -E 'physicaldrive' | grep -v 'OK')
if [ -z "$output" ]; then
    echo "OK"
else
    echo "FAIL"
fi
EOF

# Cấp quyền thực thi cho các script
chmod +x /usr/local/bin/check_ssacli_status.sh
chmod +x /usr/local/bin/check_raid_status_custom.sh

# Thêm quyền sudo cho Zabbix để chạy mdadm mà không cần mật khẩu
echo "👉 Cấu hình sudo cho Zabbix..."
echo "zabbix ALL=(ALL) NOPASSWD: /usr/sbin/ssacli" | sudo tee -a /etc/sudoers > /dev/null
echo "zabbix ALL=(ALL) NOPASSWD: /usr/sbin/mdadm" | sudo tee -a /etc/sudoers > /dev/null

# Mở cổng firewall cho Zabbix Agent
echo "👉 Cấu hình firewall..."
sudo apt install ufw -y
sudo ufw enable
sudo ufw allow 10050/tcp


# Khởi động Zabbix Agent 2
echo "👉 Khởi động lại Zabbix Agent 2..."
systemctl enable --now zabbix-agent2
systemctl restart zabbix-agent2
systemctl status zabbix-agent2 --no-pager

echo "✅ Cài đặt Zabbix Agent 2 cho AlmaLinux 9 hoàn tất!"
