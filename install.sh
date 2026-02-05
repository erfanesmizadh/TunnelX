#!/bin/bash

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
plain='\033[0m'
NC='\033[0m'

[[ $EUID -ne 0 ]] && echo -e "${RED}Please run as root${plain}" && exit 1

SERVICE="/etc/systemd/system/dvhost-tunnel.service"
RESTORE_SCRIPT="/usr/local/bin/dvhost_restore.sh"

DVHOST_CLOUD_install_jq() {
    command -v jq >/dev/null || apt-get update && apt-get install -y jq
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

    echo "+-----------------------------------------+"
    echo "|       DVHOST Tunnel Manager             |"
    echo "+-----------------------------------------+"
    echo "| Server IP : $SERVER_IP"
    echo "| Country   : $SERVER_COUNTRY"
    echo "| ISP       : $SERVER_ISP"
    echo "+-----------------------------------------+"
    echo -e "$1"
    echo "+-----------------------------------------+"
}

DVHOST_CLOUD_MAIN(){
    DVHOST_CLOUD_menu "1 - Get IPv6\n2 - Setup Tunnel\n3 - Status\n0 - Exit"
    read -p "Choice: " choice
    case $choice in
        1) DVHOST_CLOUD_GET_LOCAL_IP ;;
        2) DVHOST_CLOUD_TUNNEL ;;
        3) DVHOST_CLOUD_check_status ;;
        0) exit ;;
        *) echo "Invalid choice"; read -p "Press any key..." ;;
    esac
}

DVHOST_CLOUD_TUNNEL(){
    DVHOST_CLOUD_menu "1 - Setup Tunnel\n2 - Remove Tunnel\n0 - Exit"
    read -p "Choice: " choice
    case $choice in
        1) DVHOST_CLOUD_setup_tunnel_and_forward ;;
        2) DVHOST_CLOUD_cleanup_socat_tunnel ;;
        0) exit ;;
        *) echo "Invalid choice"; read -p "Press any key..." ;;
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

    echo "Tunnel created: $this_ipv6"
}

DVHOST_CLOUD_setup_tunnel_and_forward(){
    read -p "Destination IPv6: " dest_ipv6
    read -p "Ports (comma-separated): " ports

    # Generate restore script
    echo "#!/bin/bash" > $RESTORE_SCRIPT
    echo "ip tunnel del isatap1 2>/dev/null" >> $RESTORE_SCRIPT
    echo "ip tunnel add isatap1 mode isatap local $(hostname -I | awk '{print \$1}')" >> $RESTORE_SCRIPT
    echo "ip link set isatap1 up" >> $RESTORE_SCRIPT
    echo "sysctl -w net.ipv6.conf.all.forwarding=1" >> $RESTORE_SCRIPT

    IFS=',' read -r -a port_array <<< "$ports"
    for port in "${port_array[@]}"; do
        echo "pkill -f 'socat TCP6-LISTEN:$port' 2>/dev/null" >> $RESTORE_SCRIPT
        echo "socat TCP6-LISTEN:$port,fork TCP6:[$dest_ipv6]:$port &" >> $RESTORE_SCRIPT
    done

    chmod +x $RESTORE_SCRIPT

    # Create systemd service
    cat <<EOF > $SERVICE
[Unit]
Description=DVHOST Persistent Tunnel
After=network.target

[Service]
ExecStart=$RESTORE_SCRIPT
Restart=always

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable dvhost-tunnel
    systemctl restart dvhost-tunnel

    echo -e "${GREEN}Tunnel persistent enabled ✔${NC}"
}

DVHOST_CLOUD_cleanup_socat_tunnel(){
    systemctl stop dvhost-tunnel
    systemctl disable dvhost-tunnel
    rm -f $SERVICE
    rm -f $RESTORE_SCRIPT
    ip tunnel del isatap1 2>/dev/null
    systemctl daemon-reload
    echo "Tunnel removed."
}

DVHOST_CLOUD_require_command

while true; do
    DVHOST_CLOUD_MAIN
done
