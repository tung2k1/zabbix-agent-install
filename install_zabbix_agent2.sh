#!/bin/bash

echo "👉 Bắt đầu cài đặt Zabbix Agent 2 cho AlmaLinux 9..."
sudo dnf remove zabbix-agent2 -y
sudo rm -rf /etc/zabbix
sudo rm -rf /var/log/zabbix

# Cài đặt Zabbix Agent 2
rpm -Uvh https://repo.zabbix.com/zabbix/7.0/alma/9/x86_64/zabbix-release-latest-7.0.el9.noarch.rpm
dnf clean all
dnf install zabbix-agent2
dnf install zabbix-agent2-plugin-mongodb zabbix-agent2-plugin-mssql zabbix-agent2-plugin-postgresql
# Lấy địa chỉ IP hiện tại của server
SERVER_IP=$(hostname -I | awk '{print $1}')
STATIC_IP="37.48.124.207"
echo "👉 IP của server: $SERVER_IP"
echo "👉 Cấu hình Zabbix với Server=$STATIC_IP,$SERVER_IP và ServerActive=$STATIC_IP"

# Cập nhật file cấu hình Zabbix Agent
sed -i "s/^Server=.*/Server=$STATIC_IP,$SERVER_IP/" /etc/zabbix/zabbix_agent2.conf
sed -i "s/^ServerActive=.*/ServerActive=$STATIC_IP/" /etc/zabbix/zabbix_agent2.conf
sed -i "s/^Hostname=.*/Hostname=$SERVER_IP/" /etc/zabbix/zabbix_agent2.conf

cat <<EOF >> /etc/zabbix/zabbix_agent2.conf
UserParameter=raid.status.custom,/usr/local/bin/check_raid_status_custom.sh
UserParameter=raid.status,cat /proc/mdstat | grep -E '\[.*_.*\]' | wc -l
UserParameter=network.discovery,/usr/local/bin/discover_network_interfaces.sh
EOF

# Tạo script kiểm tra RAID
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

# Tạo script phát hiện interface mạng
echo "👉 Tạo script phát hiện interface mạng..."
cat <<'EOF' > /usr/local/bin/discover_network_interfaces.sh
#!/bin/bash
ip -br link | awk '$2 == "UP" {print $1}' | jq -R -s -c 'split("\n")[:-1] | map({"{#IFNAME}": .})'
EOF

# Cấp quyền thực thi cho các script
chmod +x /usr/local/bin/check_raid_status_custom.sh
chmod +x /usr/local/bin/discover_network_interfaces.sh

# Thêm quyền sudo cho Zabbix để chạy mdadm mà không cần mật khẩu
echo "👉 Cấu hình sudo cho Zabbix..."
echo "zabbix ALL=(ALL) NOPASSWD: /usr/sbin/mdadm" | sudo tee -a /etc/sudoers > /dev/null

# Mở cổng firewall cho Zabbix Agent
echo "👉 Cấu hình firewall..."
sudo firewall-cmd --permanent --add-port=10050/tcp
sudo firewall-cmd --reload

# Khởi động Zabbix Agent 2
echo "👉 Khởi động lại Zabbix Agent 2..."
systemctl enable --now zabbix-agent2
systemctl restart zabbix-agent2
systemctl status zabbix-agent2 --no-pager

echo "✅ Cài đặt Zabbix Agent 2 cho AlmaLinux 9 hoàn tất!"
