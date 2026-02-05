#!/bin/bash

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
plain='\033[0m'
NC='\033[0m' # No Color

# check root
[[ $EUID -ne 0 ]] && echo -e "${RED}Fatal error: ${plain} Please run this script with root privilege \n " && exit 1

RESTORE_SCRIPT="/usr/local/bin/dvhost-restore-tunnel.sh"
SERVICE="/etc/systemd/system/dvhost-tunnel.service"

DVHOST_CLOUD_install_jq() {
    if ! command -v jq &> /dev/null; then
        if command -v apt-get &> /dev/null; then
            echo -e "${RED}jq is not installed. Installing...${NC}"
            sleep 1
            sudo apt-get update
            sudo apt-get install -y jq
        else
            echo -e "${RED}Error: Unsupported package manager. Please install jq manually.${NC}\n"
            read -p "Press any key to continue..."
            exit 1
        fi
    fi
}

DVHOST_CLOUD_require_command(){
    apt install python3-pip -y
    sudo apt-get install socat -y
    DVHOST_CLOUD_install_jq
    if ! command -v pv &> /dev/null; then
        echo "pv could not be found, installing it..."
        sudo apt update
        sudo apt install -y pv
    fi
}

DVHOST_CLOUD_menu(){
    clear
    SERVER_IP=$(hostname -I | awk '{print $1}')
    SERVER_COUNTRY=$(curl -sS "http://ip-api.com/json/$SERVER_IP" | jq -r '.country')
    SERVER_ISP=$(curl -sS "http://ip-api.com/json/$SERVER_IP" | jq -r '.isp')

    echo "+-----------------------------------------------------------------------+"                                                                                                
    echo "|       DVHOST Tunnel Manager             |"
    echo "+-----------------------------------------------------------------------+"
    echo "| Server IP : $SERVER_IP"
    echo "| Country   : $SERVER_COUNTRY"
    echo "| ISP       : $SERVER_ISP"
    echo "+-----------------------------------------------------------------------+"
    echo -e "|${YELLOW}Please choose an option:${NC}"
    echo "+-----------------------------------------------------------------------+"
    echo -e "$1"
    echo "+-----------------------------------------------------------------------+"
}

DVHOST_CLOUD_MAIN(){
    clear
    DVHOST_CLOUD_menu "1 - Setup Tunnel\n2 - Remove Tunnel\n3 - Status\n0 - Exit"
    read -p "Choice: " choice
    
    case $choice in
        1) DVHOST_CLOUD_TUNNEL ;;
        2) DVHOST_CLOUD_cleanup_socat_tunnel ;;
        3) DVHOST_CLOUD_check_status ;;
        0) echo -e "${GREEN}Exiting...${NC}"; exit 0 ;;
        *) echo "Invalid choice."; read -p "Press any key to continue..." ;;
    esac
}

DVHOST_CLOUD_check_status(){
    if ip link show isatap1 &> /dev/null; then
        echo -e "\e[32mTunnel is UP.\e[0m"
    else
        echo -e "\e[31mTunnel is DOWN.\e[0m"
    fi
}

DVHOST_CLOUD_TUNNEL(){
    DVHOST_CLOUD_menu "1 - Setup Tunnel\n2 - Remove Tunnel\n0 - Exit"
    read -p "Choice: " choice
    case $choice in
        1) DVHOST_CLOUD_setup_tunnel_and_forward ;;
        2) DVHOST_CLOUD_cleanup_socat_tunnel ;;
        0) exit 0 ;;
        *) echo "Invalid choice."; read -p "Press any key to continue..." ;;
    esac
}

DVHOST_CLOUD_setup_tunnel_and_forward(){
    read -p "Destination IPv6: " dest_ipv6
    read -p "Ports (comma-separated): " ports

    LOCAL_IP=$(hostname -I | awk '{print $1}')

    # Create restore script
    echo "#!/bin/bash" > $RESTORE_SCRIPT
    echo "ip tunnel del isatap1 2>/dev/null" >> $RESTORE_SCRIPT
    echo "ip tunnel add isatap1 mode isatap local $LOCAL_IP" >> $RESTORE_SCRIPT
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
    read -p "Ports to stop (comma-separated): " ports
    IFS=',' read -r -a port_array <<< "$ports"

    for port in "${port_array[@]}"; do
        echo "Stopping tunnel for port $port..."
        pids=$(pgrep -f "socat TCP6-LISTEN:$port")
        if [ -n "$pids" ]; then
            sudo kill $pids
            echo "Stopped port $port."
        else
            echo "No active tunnel for port $port."
        fi
    done

    # Also remove tunnel
    sudo ip tunnel del isatap1 2>/dev/null
}

DVHOST_CLOUD_require_command
DVHOST_CLOUD_MAIN
