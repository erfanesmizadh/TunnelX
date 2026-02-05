#!/bin/bash

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
plain='\033[0m'
NC='\033[0m'

[[ $EUID -ne 0 ]] && echo -e "${RED}Run as root${plain}" && exit 1

SERVICE="/etc/systemd/system/dvhost-tunnel.service"
RESTORE_SCRIPT="/usr/local/bin/dvhost_restore.sh"

DVHOST_CLOUD_install_jq() {
    command -v jq >/dev/null || apt-get install jq -y
}

DVHOST_CLOUD_require_command(){
    apt update -y
    apt install -y python3-pip socat jq pv curl
}

DVHOST_CLOUD_menu(){

clear

SERVER_IP=$(hostname -I | awk '{print $1}')
SERVER_COUNTRY=$(curl -s ip-api.com/json/$SERVER_IP | jq -r '.country')
SERVER_ISP=$(curl -s ip-api.com/json/$SERVER_IP | jq -r '.isp')

echo "===================================="
echo "        DVHOST Tunnel Manager"
echo "===================================="
echo "Server IP : $SERVER_IP"
echo "===================================="
echo -e $1

}

DVHOST_CLOUD_MAIN(){

DVHOST_CLOUD_menu "1 - Get IPv6
2 - Setup Tunnel
3 - Status
0 - Exit"

read -p "Choice: " choice

case $choice in
1) DVHOST_CLOUD_GET_LOCAL_IP ;;
2) DVHOST_CLOUD_TUNNEL ;;
3) DVHOST_CLOUD_check_status ;;
0) exit ;;
esac

}

DVHOST_CLOUD_TUNNEL(){

DVHOST_CLOUD_menu "1 - Setup Tunnel
2 - Remove Tunnel
0 - Exit"

read -p "Choice: " choice

case $choice in
1) DVHOST_CLOUD_setup_tunnel_and_forward ;;
2) DVHOST_CLOUD_cleanup_socat_tunnel ;;
0) exit ;;
esac

}

DVHOST_CLOUD_check_status(){

systemctl status dvhost-tunnel --no-pager

}

DVHOST_CLOUD_GET_LOCAL_IP(){

read -p "Local IPv4: " server1_ip
read -p "Remote IPv4: " server2_ip

DVHOST_CLOUD_create_tunnel_and_ping $server1_ip $server2_ip

}

DVHOST_CLOUD_create_tunnel_and_ping(){

local this_server_ip=$1
local this_hex=$(echo $this_server_ip | awk -F. '{printf("%02x%02x:%02x%02x",$1,$2,$3,$4)}')
local this_ipv6="fe80::200:5efe:$this_hex"

ip tunnel del isatap1 2>/dev/null

ip tunnel add isatap1 mode isatap local $this_server_ip
ip link set isatap1 up
ip -6 addr add $this_ipv6/64 dev isatap1
sysctl -w net.ipv6.conf.all.forwarding=1

echo "Tunnel created."

}

DVHOST_CLOUD_setup_tunnel_and_forward(){

read -p "Destination IPv6: " dest_ipv6
read -p "Ports (comma-separated): " ports

echo "#!/bin/bash" > $RESTORE_SCRIPT

echo "ip tunnel del isatap1 2>/dev/null" >> $RESTORE_SCRIPT
echo "ip tunnel add isatap1 mode isatap local $(hostname -I | awk '{print
