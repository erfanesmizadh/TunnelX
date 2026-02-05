#!/bin/bash

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

[[ $EUID -ne 0 ]] && echo -e "${RED}Run as root${NC}" && exit 1

SERVICE_FILE="/etc/systemd/system/tunnelx.service"
START_SCRIPT="/usr/local/bin/tunnelx-start.sh"

install_dep(){
apt update -y
apt install -y socat jq curl
}

menu(){

clear
SERVER_IP=$(hostname -I | awk '{print $1}')

echo "===================================="
echo "        TunnelX Manager"
echo "===================================="
echo "Server IP : $SERVER_IP"
echo "===================================="
echo "1 - Setup Tunnel"
echo "2 - Remove Tunnel"
echo "3 - Status"
echo "0 - Exit"
echo "===================================="

}

create_service(){

cat <<EOF > $SERVICE_FILE
[Unit]
Description=TunnelX Persistent Tunnel
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
systemctl enable tunnelx

}

setup_tunnel(){

read -p "Local IPv4: " LOCAL_IP
read -p "Remote IPv4: " REMOTE_IP
read -p "Destination IPv6: " DEST_IPV6
read -p "Ports (comma separated): " PORTS

LOCAL_HEX=$(echo $LOCAL_IP | awk -F. '{printf("%02x%02x:%02x%02x",$1,$2,$3,$4)}')

LOCAL_IPV6="fe80::200:5efe:$LOCAL_HEX"

IFS=',' read -r -a PORT_ARRAY <<< "$PORTS"

echo "#!/bin/bash" > $START_SCRIPT

echo "ip tunnel del isatap1 2>/dev/null" >> $START_SCRIPT
echo "ip tunnel add isatap1 mode isatap local $LOCAL_IP" >> $START_SCRIPT
echo "ip link set isatap1 up" >> $START_SCRIPT
echo "ip -6 addr add $LOCAL_IPV6/64 dev isatap1" >> $START_SCRIPT
echo "sysctl -w net.ipv6.conf.all.forwarding=1" >> $START_SCRIPT

for port in "${PORT_ARRAY[@]}"; do
echo "socat TCP6-LISTEN:$port,fork TCP6:[$DEST_IPV6]:$port &" >> $START_SCRIPT
done

chmod +x $START_SCRIPT

create_service

systemctl restart tunnelx

echo -e "${GREEN}Tunnel Installed + Persistent Enabled${NC}"

}

remove_tunnel(){

systemctl stop tunnelx 2>/dev/null
systemctl disable tunnelx 2>/dev/null

rm -f $SERVICE_FILE
rm -f $START_SCRIPT

ip tunnel del isatap1 2>/dev/null

systemctl daemon-reload

echo -e "${RED}Tunnel Removed${NC}"

}

status(){

systemctl status tunnelx --no-pager

}

install_dep

while true; do

menu
read -p "Choice: " choice

case $choice in

1) setup_tunnel ;;
2) remove_tunnel ;;
3) status ;;
0) exit ;;
*) echo "Invalid"; sleep 1;;

esac

done
