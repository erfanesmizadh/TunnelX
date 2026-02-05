#!/bin/bash

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

[[ $EUID -ne 0 ]] && echo "Run as root" && exit 1

SERVICE="/etc/systemd/system/dvhost-tunnel.service"
START_SCRIPT="/usr/local/bin/dvhost-tunnel.sh"

install_requirements(){

apt update -y
apt install -y socat jq curl

}

menu(){

clear

SERVER_IP=$(hostname -I | awk '{print $1}')
SERVER_COUNTRY=$(curl -s ip-api.com/json/$SERVER_IP | jq -r '.country')
SERVER_ISP=$(curl -s ip-api.com/json/$SERVER_IP | jq -r '.isp')

echo "+------------------------------------------------+"
echo "            DVHOST Tunnel Manager"
echo "+------------------------------------------------+"
echo "Server Country : $SERVER_COUNTRY"
echo "Server IP      : $SERVER_IP"
echo "Server ISP     : $SERVER_ISP"
echo "+------------------------------------------------+"
echo "1 - Setup Tunnel"
echo "2 - Remove Tunnel"
echo "3 - Status"
echo "0 - Exit"
echo "+------------------------------------------------+"

}

make_persistent(){

cat <<EOF > $SERVICE
[Unit]
Description=DVHOST Persistent Tunnel
After=network.target

[Service]
Type=simple
ExecStart=$START_SCRIPT
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable dvhost-tunnel
systemctl restart dvhost-tunnel

}

setup_tunnel(){

read -p "Enter destination IPv6 address: " dest_ipv6
read -p "Enter ports (comma-separated): " ports

IFS=',' read -r -a port_array <<< "$ports"

echo "#!/bin/bash" > $START_SCRIPT

echo "ip tunnel del isatap1 2>/dev/null" >> $START_SCRIPT
echo "ip tunnel add isatap1 mode isatap local $(hostname -I | awk '{print $1}')" >> $START_SCRIPT
echo "ip link set isatap1 up" >> $START_SCRIPT
echo "sysctl -w net.ipv6.conf.all.forwarding=1" >> $START_SCRIPT

for port in "${port_array[@]}"; do

pkill -f "socat TCP6-LISTEN:$port" 2>/dev/null

echo "socat TCP6-LISTEN:$port,fork TCP6:[$dest_ipv6]:$port &" >> $START_SCRIPT

done

chmod +x $START_SCRIPT

make_persistent

echo -e "${GREEN}Tunnel Installed + Persistent Enabled${NC}"

}

remove_tunnel(){

systemctl stop dvhost-tunnel 2>/dev/null
systemctl disable dvhost-tunnel 2>/dev/null

rm -f $SERVICE
rm -f $START_SCRIPT

ip tunnel del isatap1 2>/dev/null

systemctl daemon-reload

echo -e "${RED}Tunnel Removed${NC}"

}

status_check(){

systemctl status dvhost-tunnel --no-pager

}

install_requirements

while true; do

menu

read -p "Choice: " choice

case $choice in

1) setup_tunnel ;;
2) remove_tunnel ;;
3) status_check ;;
0) exit ;;
*) echo "Invalid"; sleep 1;;

esac

done
