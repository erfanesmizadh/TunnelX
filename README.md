# 🚀 DVHOST Tunnel Manager

DVHOST Tunnel Manager is a powerful Bash-based tool designed to create persistent IPv4 ↔ IPv6 tunnels with automatic port forwarding and auto-restart capabilities.

This project allows you to easily deploy stable tunnels that survive server reboot using systemd.

---

## ✨ Features

- ✅ ISATAP IPv6 Tunnel Creation
- ✅ Multi-Port Forwarding (socat)
- ✅ Persistent Tunnel (Auto Start after Reboot)
- ✅ Systemd Service Integration
- ✅ Auto Restart if Tunnel Stops
- ✅ Simple Interactive Menu
- ✅ Lightweight & Fast
- ✅ Designed for VPS and Tunnel Routing

---

## ⚙️ Requirements

- Ubuntu / Debian based systems
- Root access
- Internet connection

Dependencies will be installed automatically:

- socat
- jq
- curl

---

## 📥 Installation

Clone the project:

```bash
git clone https://github.com/erfanesmizadh/YOUR_REPO.git
cd YOUR_REPO
chmod +x tunnel.sh
bash tunnel.sh
