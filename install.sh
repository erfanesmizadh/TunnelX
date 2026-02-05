#!/bin/bash

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

# check root
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}Fatal error: Please run as root${NC}"
    exit 1
fi

RESTORE_SCRIPT="/usr/local/bin/dvhost-restore-tunnel.sh"
SERVICE="/etc/systemd/system/dvhost-tunnel.service"

# Install dependencies
apt update
apt install -y socat python3-pip pv

# Menu
echo "+-----------------------------------------+"
echo "|       DVHOST Tunnel Manager             |"
echo "+-----------------------------------------+"
SERVER_IP=$(hostname -I | awk '{print $1}')
echo "| Server IP : $SERVER_IP"
echo "| Country   : Iran"
echo "| ISP       : Pars Abr Toseeh Ertebatat LTD"
echo "+-----------------------------------------+"
echo "1 - Setup Tunnel"
echo "2 - Remove Tunnel"
echo "0 - Exit"
echo "+-----------------------------------------+"
read -p "Choice: " CHOICE

case $CHOICE in
1)
    read -p "Destination IPv6: " DEST_IPV6
    read -p "Ports (comma-separated): " PORTS

    LOCAL_IP=$(hostname -I | awk '{print $1}')

    # Create restore script
    cat > $RESTORE_SCRIPT <<EOL
#!/bin/bash
ip tunnel del isatap1 2>/dev/null
ip tunnel add isatap1 mode isatap local $LOCAL_IP
ip link set isatap1 up
sysctl -w net.ipv6.conf.all.forwarding=1
EOL

    IFS=',' read -r -a PORT_ARRAY <<< "$PORTS"
    for PORT in "${PORT_ARRAY[@]}"; do
        echo "pkill -f 'socat TCP6-LISTEN:$PORT' 2>/dev/null" >> $RESTORE_SCRIPT
        echo "socat TCP6-LISTEN:$PORT,fork TCP6:[$DEST_IPV6]:$PORT &" >> $RESTORE_SCRIPT
    done

    chmod +x $RESTORE_SCRIPT

    # Create systemd service
    cat > $SERVICE <<EOL
[Unit]
Description=DVHOST Persistent Tunnel
After=network.target

[Service]
ExecStart=$RESTORE_SCRIPT
Restart=always

[Install]
WantedBy=multi-user.target
EOL

    systemctl daemon-reload
    systemctl enable dvhost-tunnel
    systemctl restart dvhost-tunnel

    echo -e "${GREEN}Tunnel persistent enabled ✔${NC}"
    ;;

2)
    read -p "Ports to stop (comma-separated): " PORTS
    IFS=',' read -r -a PORT_ARRAY <<< "$PORTS"
    for PORT in "${PORT_ARRAY[@]}"; do
        echo "Stopping port $PORT..."
        pids=$(pgrep -f "socat TCP6-LISTEN:$PORT")
        [ -n "$pids" ] && kill $pids
    done
    ip tunnel del isatap1 2>/dev/null
    systemctl disable --now dvhost-tunnel
    echo -e "${RED}Tunnel removed${NC}"
    ;;

0)
    echo "Exiting..."
    exit 0
    ;;

*)
    echo "Invalid choice"
    ;;
esac
