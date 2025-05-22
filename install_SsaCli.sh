#!/bin/bash

echo "👉 Bắt đầu cài đặt Zabbix Agent 2 cho AlmaLinux 9..."
sudo dnf remove zabbix-agent2 -y
sudo rm -rf /etc/zabbix
sudo rm -rf /var/log/zabbix

# Cài đặt Zabbix Agent 2
rpm -Uvh https://repo.zabbix.com/zabbix/7.0/alma/8/x86_64/zabbix-release-latest-7.0.el8.noarch.rpm
dnf clean all
dnf install zabbix-agent2
dnf install zabbix-agent2-plugin-mongodb zabbix-agent2-plugin-mssql zabbix-agent2-plugin-postgresql -y
# Lấy địa chỉ IP hiện tại của server
SERVER_IP=$(hostname -I | awk '{print $1}')
STATIC_IP="103.253.21.236"
echo "👉 IP của server: $SERVER_IP"
echo "👉 Cấu hình Zabbix với Server=$STATIC_IP,$SERVER_IP và ServerActive=$STATIC_IP"

# Cập nhật file cấu hình Zabbix Agent
sed -i "s/^Server=.*/Server=$STATIC_IP,$SERVER_IP/" /etc/zabbix/zabbix_agent2.conf
sed -i "s/^ServerActive=.*/ServerActive=$STATIC_IP/" /etc/zabbix/zabbix_agent2.conf
sed -i "s/^Hostname=.*/Hostname=$SERVER_IP/" /etc/zabbix/zabbix_agent2.conf

cat <<EOF >> /etc/zabbix/zabbix_agent2.conf
UserParameter=raid.disk_status,/usr/local/bin/check_ssacli_status.sh
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

# Thêm quyền sudo cho Zabbix để chạy mdadm mà không cần mật khẩu
echo "👉 Cấu hình sudo cho Zabbix..."
echo "zabbix ALL=(ALL) NOPASSWD: /usr/sbin/ssacli" | sudo tee -a /etc/sudoers > /dev/null

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
