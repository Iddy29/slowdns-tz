# A.I SLOWDNS TZ

SlowDNS + DNSTT SSH Tunnel setup tool for Ubuntu VPS servers.

## Quick Install (Run on VPS)

```bash
wget -qO install.sh https://raw.githubusercontent.com/Iddy29/slowdns-tz/main/INSTALL_COMMAND.sh && sudo bash install.sh
```

Or use the interactive installer:

```bash
wget -qO install.sh https://raw.githubusercontent.com/Iddy29/slowdns-tz/main/one-click-install.sh && sudo bash install.sh
```

## Requirements

- Ubuntu 20.04+ VPS
- Root access
- A registered domain name
- Domain NS records pointed to your VPS IP

## What It Does

- Installs and configures DNSTT server for DNS tunneling
- Sets up SSH-over-DNS tunnel
- User management (create/delete/renew SSH users)
- Automatic iptables configuration
- DNS speed optimization
- Service health monitoring

## After Installation

Run the management menu anytime:

```bash
sudo slowdns-tz
```

Or directly:

```bash
sudo bash /opt/ai-slowdns-tz/SLOWDNS-TZ.sh
```

## Files

| File | Description |
|------|-------------|
| `SLOWDNS-TZ.sh` | Main script - installation, configuration, user management |
| `scripts/ai-monitor.sh` | Service health monitor daemon |
| `scripts/ai-optimizer.py` | DNS speed optimizer daemon |
| `INSTALL_COMMAND.sh` | Quick install script |
| `one-click-install.sh` | Interactive installer |
