# Important
**All steps have been translated and aided to create by AI so take everything with a grain of sand and may ask your favorit AI, if questions arise!**

---

Here is a compact tutorial to set up your Debian machine so that:

- it connects to the WLAN via WPA2-Enterprise (PEAP/MSCHAPv2)
- your LAN port serves as a router for other devices
- all LAN traffic is tunneled through Cloudflare WARP

All steps are ordered so you can go through them cleanly once.

***

## 1. Check Prerequisites

Determine interface names:

```bash
ip a
```

In your setup, the relevant ones were:

- WLAN: `wlp2s0` (WPA2-Enterprise uplink)
- LAN inward: `eno1` (192.168.50.1, DHCP for clients)
- additional WAN-LAN: `enp1s0f1` (direct internet connection, optional)
- WARP interface: `CloudflareWARP` (172.16.0.2/32)

Install system packages:

```bash
sudo apt update
sudo apt install wpa_supplicant dnsmasq iptables iptables-persistent
```

Permanently enable IP forwarding:

```bash
echo 'net.ipv4.ip_forward=1' | sudo tee -a /etc/sysctl.conf
sudo sysctl -p
```

***

## 2. Set up WPA2-Enterprise (PEAP/MSCHAPv2)

Create configuration file for `wpa_supplicant`, e.g.:

```bash
sudo nano /etc/wpa_supplicant/wpa_supplicant-wlp2s0.conf
```

Content (adapt to your data):

```conf
ctrl_interface=DIR=/var/run/wpa_supplicant GROUP=netdev
update_config=1
eapol_version=1
ap_scan=1
fast_reauth=1

network={
    ssid="YOUR_SSID"
    scan_ssid=1
    key_mgmt=WPA-EAP
    eap=PEAP
    identity="your_username@realm.de"
    password="your_password"
    phase1="peaplabel=1"
    phase2="auth=MSCHAPV2"
    pairwise=CCMP TKIP
}
```

Adjust permissions:

```bash
sudo chmod 600 /etc/wpa_supplicant/wpa_supplicant-wlp2s0.conf
```

Enable systemd service:

```bash
sudo systemctl enable --now wpa_supplicant@wlp2s0.service
```

Get IP via DHCP (if not automatic):

```bash
sudo dhclient wlp2s0
```

Test connection:

```bash
ping -c 3 8.8.8.8 -I wlp2s0
```

***

## 3. Install and Activate Cloudflare WARP

Add repository and install WARP client:

```bash
curl https://pkg.cloudflareclient.com/pubkey.gpg \
  | sudo gpg --yes --dearmor --output /usr/share/keyrings/cloudflare-warp-archive-keyring.gpg

echo "deb [signed-by=/usr/share/keyrings/cloudflare-warp-archive-keyring.gpg] https://pkg.cloudflareclient.com/ bookworm main" \
  | sudo tee /etc/apt/sources.list.d/cloudflare-client.list

sudo apt update
sudo apt install cloudflare-warp
```

Register and connect WARP:

```bash
sudo warp-cli register
sudo warp-cli mode warp     # Full tunnel
sudo warp-cli connect
```

Check status:

```bash
warp-cli status
ip a show CloudflareWARP
```

***

## 4. Configure LAN Interface as Internal Network

Static IP for `eno1`:

```bash
sudo nano /etc/network/interfaces
```

Insert:

```conf
auto eno1
iface eno1 inet static
    address 192.168.50.1
    netmask 255.255.255.0
```

Bring up interface:

```bash
sudo ifup eno1
# alternatively, if necessary:
# sudo ip addr add 192.168.50.1/24 dev eno1
# sudo ip link set eno1 up
```

Check:

```bash
ip a show eno1
```

***

## 5. dnsmasq as DHCP Server for LAN

Configure dnsmasq so it is only responsible for the internal LAN, does not occupy a local DNS port (so WARP can use DNS), but provides DNS to clients.

Edit configuration:

```bash
sudo nano /etc/dnsmasq.conf
```

Minimal content suitable for the setup:

```conf
interface=eno1
bind-interfaces

# No local DNS on port 53, so WARP can take over system-wide DNS
port=0

# DHCP range
dhcp-range=192.168.50.10,192.168.50.100,12h

# Default gateway
dhcp-option=option:router,192.168.50.1

# Provide DNS to clients – they query 192.168.50.1, the system resolves via WARP
dhcp-option=option:dns-server,192.168.50.1
```

Restart service:

```bash
sudo systemctl restart dnsmasq
sudo systemctl status dnsmasq
```

Now, e.g., your MacBook or other devices should be able to get an address like `192.168.50.38` via DHCP.

***

## 6. NAT: Tunnel LAN Traffic through CloudflareWARP

Set NAT rule so all clients from 192.168.50.0/24 go to the internet via the WARP interface:

```bash
sudo iptables -t nat -A POSTROUTING -s 192.168.50.0/24 -o CloudflareWARP -j MASQUERADE
```

Save rules permanently:

```bash
sudo netfilter-persistent save
```

Check rules:

```bash
sudo iptables -t nat -L -n -v | grep 192.168.50
```

***

## 7. Policy Routing: Explicitly Bind LAN Traffic to WARP

So that only traffic from your LAN goes securely through CloudflareWARP (and the host itself keeps its standard routes), create a separate routing table and bind the LAN to it.

Define routing tables:

```bash
sudo nano /etc/iproute2/rt_tables
```

Add to the end:

```text
100 warp-lan
```

Routing rule for the LAN network:

```bash
sudo ip rule add from 192.168.50.0/24 table 100 priority 50
```

Fill table 100 with WARP default route:

```bash
sudo ip route add 192.168.50.0/24 dev eno1 table 100
sudo ip route add default dev CloudflareWARP src 172.16.0.2 table 100
```

Check:

```bash
ip rule show | grep 192.168
ip route show table 100
```

You should see:

- a rule `from 192.168.50.0/24 lookup 100`
- and in table 100: `default dev CloudflareWARP` as well as the 192.168.50.0/24 route via `eno1`.

***

## 8. Control DNS for Clients (optional)

If you want to assign specific DNS servers to certain devices (e.g., MacBook → Cloudflare DNS), you can do this in `dnsmasq.conf` by MAC address.

Example: MacBook with MAC `34:29:8f:91:1c:b2` should get 1.1.1.1/1.0.0.1:

```conf
# add to /etc/dnsmasq.conf:
dhcp-host=34:29:8f:91:1c:b2,set:macbook,dns-server,1.1.1.1,1.0.0.1

# Fallback DNS for all others:
dhcp-option=option:dns-server,192.168.50.1
```

Then:

```bash
sudo systemctl restart dnsmasq
```

Renew lease on the client (e.g., on macOS):

```bash
# Disconnect/reconnect network briefly or:
sudo ipconfig set en0 DHCP   # depending on interface
```

***

## 9. Function Tests

### On the Debian Router

- WARP status:

```bash
warp-cli status
```

- IP forwarding:

```bash
sysctl net.ipv4.ip_forward
```

- Routes:

```bash
ip a show eno1
ip a show CloudflareWARP
ip rule show | grep 192.168
ip route show table 100
```

### On a LAN Client (e.g., MacBook)

- Check IP/DNS:

```bash
# IP (should be 192.168.50.x)
# on macOS: System Settings → Network → Details
```

- Public IP (must be Cloudflare IP):

```bash
curl ifconfig.me
```

- WARP status (indirect):

```bash
curl https://www.cloudflare.com/cdn-cgi/trace/ | grep warp
# Output should contain warp=on
```

If all this fits, all traffic from LAN devices goes via the internal interface `eno1` to the Debian router and from there through the Cloudflare WARP tunnel to the internet.

***

## 10. Ensure Autostart

The following services should start automatically on boot:

```bash
sudo systemctl enable wpa_supplicant@wlp2s0
sudo systemctl enable dnsmasq
# WARP starts its service automatically, if necessary once:
warp-cli enable-always-on
```

If WARP or policy routing is not reliably active after a reboot, you can create a small script at `/etc/network/if-up.d/warp-lan`:

```bash
sudo nano /etc/network/if-up.d/warp-lan
```

Content:

```bash
#!/bin/sh
# Executed when an interface goes "up"

# Safely connect WARP
warp-cli connect 2>/dev/null

# Re-set policy routing for LAN
ip rule add from 192.168.50.0/24 table 100 priority 50 2>/dev/null
ip route replace 192.168.50.0/24 dev eno1 table 100 2>/dev/null
ip route replace default dev CloudflareWARP src 172.16.0.2 table 100 2>/dev/null
```

Make executable:

```bash
sudo chmod +x /etc/network/if-up.d/warp-lan
```
