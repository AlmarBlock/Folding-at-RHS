Hier ist ein kompaktes Tutorial, mit dem du deinen Debian‑Rechner so einrichtest, dass:

- er sich per WPA2‑Enterprise (PEAP/MSCHAPv2) ins WLAN einwählt  
- dein LAN‑Port als Router für andere Geräte dient  
- der gesamte LAN‑Traffic durch Cloudflare WARP getunnelt wird  

Alle Schritte sind so sortiert, dass Du sie einmal „sauber“ durchgehen kannst.

***

## 1. Voraussetzungen prüfen

Interface‑Namen ermitteln:

```bash
ip a
```

In deinem Setup waren relevant:

- WLAN: `wlp2s0` (WPA2‑Enterprise uplink)  
- LAN nach innen: `eno1` (192.168.50.1, DHCP für Clients)  
- zusätzliches WAN‑LAN: `enp1s0f1` (direkter Internetanschluss, optional)  
- WARP‑Interface: `CloudflareWARP` (172.16.0.2/32)

Systempakete installieren:

```bash
sudo apt update
sudo apt install wpa_supplicant dnsmasq iptables iptables-persistent
```

IP‑Weiterleitung dauerhaft aktivieren:

```bash
echo 'net.ipv4.ip_forward=1' | sudo tee -a /etc/sysctl.conf
sudo sysctl -p
```

***

## 2. WPA2‑Enterprise (PEAP/MSCHAPv2) einrichten

Konfigurationsdatei für `wpa_supplicant` anlegen, z.B.:

```bash
sudo nano /etc/wpa_supplicant/wpa_supplicant-wlp2s0.conf
```

Inhalt (an deine Daten anpassen):

```conf
ctrl_interface=DIR=/var/run/wpa_supplicant GROUP=netdev
update_config=1
eapol_version=1
ap_scan=1
fast_reauth=1

network={
    ssid="DEINE_SSID"
    scan_ssid=1
    key_mgmt=WPA-EAP
    eap=PEAP
    identity="dein_username@realm.de"
    password="dein_passwort"
    phase1="peaplabel=1"
    phase2="auth=MSCHAPV2"
    pairwise=CCMP TKIP
}
```

Rechte anpassen:

```bash
sudo chmod 600 /etc/wpa_supplicant/wpa_supplicant-wlp2s0.conf
```

Systemd‑Service aktivieren:

```bash
sudo systemctl enable --now wpa_supplicant@wlp2s0.service
```

IP per DHCP holen (falls nicht automatisch):

```bash
sudo dhclient wlp2s0
```

Verbindung testen:

```bash
ping -c 3 8.8.8.8 -I wlp2s0
```

***

## 3. Cloudflare WARP installieren und aktivieren

Repository hinzufügen und WARP‑Client installieren:

```bash
curl https://pkg.cloudflareclient.com/pubkey.gpg \
  | sudo gpg --yes --dearmor --output /usr/share/keyrings/cloudflare-warp-archive-keyring.gpg

echo "deb [signed-by=/usr/share/keyrings/cloudflare-warp-archive-keyring.gpg] https://pkg.cloudflareclient.com/ bookworm main" \
  | sudo tee /etc/apt/sources.list.d/cloudflare-client.list

sudo apt update
sudo apt install cloudflare-warp
```

WARP registrieren und verbinden:

```bash
sudo warp-cli register
sudo warp-cli mode warp     # Voll-Tunnel
sudo warp-cli connect
```

Status prüfen:

```bash
warp-cli status
ip a show CloudflareWARP
```

***

## 4. LAN‑Interface als internes Netz konfigurieren

Statische IP für `eno1`:

```bash
sudo nano /etc/network/interfaces
```

Einfügen:

```conf
auto eno1
iface eno1 inet static
    address 192.168.50.1
    netmask 255.255.255.0
```

Interface hochfahren:

```bash
sudo ifup eno1
# alternativ, falls nötig:
# sudo ip addr add 192.168.50.1/24 dev eno1
# sudo ip link set eno1 up
```

Kontrolle:

```bash
ip a show eno1
```

***

## 5. dnsmasq als DHCP‑Server für das LAN

dnsmasq so konfigurieren, dass es nur für das interne LAN zuständig ist, keinen lokalen DNS‑Port belegt (damit WARP DNS benutzen kann), aber den Clients DNS mitliefert.

Konfiguration bearbeiten:

```bash
sudo nano /etc/dnsmasq.conf
```

Minimaler, zum Setup passender Inhalt:

```conf
interface=eno1
bind-interfaces

# Kein lokaler DNS auf Port 53, damit WARP systemweit DNS übernehmen kann
port=0

# DHCP-Bereich
dhcp-range=192.168.50.10,192.168.50.100,12h

# Standard-Gateway
dhcp-option=option:router,192.168.50.1

# Den Clients DNS mitgeben – sie fragen 192.168.50.1, das System löst dann über WARP
dhcp-option=option:dns-server,192.168.50.1
```

Dienst neu starten:

```bash
sudo systemctl restart dnsmasq
sudo systemctl status dnsmasq
```

Jetzt sollten sich z.B. dein MacBook oder andere Geräte per DHCP eine Adresse wie `192.168.50.38` holen können.

***

## 6. NAT: LAN‑Traffic durch CloudflareWARP tunneln

NAT‑Regel setzen, damit alle Clients aus 192.168.50.0/24 über das WARP‑Interface ins Internet gehen:

```bash
sudo iptables -t nat -A POSTROUTING -s 192.168.50.0/24 -o CloudflareWARP -j MASQUERADE
```

Regeln dauerhaft speichern:

```bash
sudo netfilter-persistent save
```

Regeln prüfen:

```bash
sudo iptables -t nat -L -n -v | grep 192.168.50
```

***

## 7. Policy‑Routing: LAN‑Traffic explizit an WARP binden

Damit nur der Traffic aus deinem LAN sicher über CloudflareWARP geht (und der Host selbst seine Standard‑Routen behalten kann), legst du eine eigene Routing‑Tabelle an und bindest das LAN daran.

Routing‑Tabellen definieren:

```bash
sudo nano /etc/iproute2/rt_tables
```

Ans Ende hinzufügen:

```text
100 warp-lan
```

Routing‑Regel für das LAN‑Netz:

```bash
sudo ip rule add from 192.168.50.0/24 table 100 priority 50
```

Tabelle 100 mit WARP‑Default‑Route füllen:

```bash
sudo ip route add 192.168.50.0/24 dev eno1 table 100
sudo ip route add default dev CloudflareWARP src 172.16.0.2 table 100
```

Kontrolle:

```bash
ip rule show | grep 192.168
ip route show table 100
```

Du solltest sehen:

- eine Regel `from 192.168.50.0/24 lookup 100`  
- und in Tabelle 100: `default dev CloudflareWARP` sowie die 192.168.50.0/24‑Route über `eno1`.

***

## 8. DNS für Clients steuern (optional)

Wenn du bestimmten Geräten eigene DNS‑Server zuweisen willst (z.B. MacBook → Cloudflare DNS), kannst du das in `dnsmasq.conf` per MAC‑Adresse machen.

Beispiel: MacBook mit MAC `34:29:8f:91:1c:b2` soll 1.1.1.1/1.0.0.1 bekommen:

```conf
# in /etc/dnsmasq.conf ergänzen:
dhcp-host=34:29:8f:91:1c:b2,set:macbook,dns-server,1.1.1.1,1.0.0.1

# Fallback-DNS für alle anderen:
dhcp-option=option:dns-server,192.168.50.1
```

Danach:

```bash
sudo systemctl restart dnsmasq
```

Auf dem Client die Lease erneuern (z.B. auf macOS):

```bash
# Netzwerk kurz trennen/verbinden oder:
sudo ipconfig set en0 DHCP   # je nach Interface
```

***

## 9. Funktionstests

### Auf dem Debian‑Router

- WARP‑Status:

```bash
warp-cli status
```

- IP‑Weiterleitung:

```bash
sysctl net.ipv4.ip_forward
```

- Routen:

```bash
ip a show eno1
ip a show CloudflareWARP
ip rule show | grep 192.168
ip route show table 100
```

### Auf einem LAN‑Client (z.B. MacBook)

- IP/DNS prüfen:

```bash
# IP (sollte 192.168.50.x sein)
# unter macOS: Systemeinstellungen → Netzwerk → Details
```

- Öffentliche IP (muss Cloudflare‑IP sein):

```bash
curl ifconfig.me
```

- WARP‑Status (indirekt):

```bash
curl https://www.cloudflare.com/cdn-cgi/trace/ | grep warp
# Ausgabe sollte warp=on enthalten
```

Wenn das alles passt, geht sämtlicher Traffic der LAN‑Geräte über das interne Interface `eno1` zum Debian‑Router und von dort durch den CloudflareWARP‑Tunnel ins Internet.

***

## 10. Autostart sicherstellen

Folgende Dienste sollten beim Booten automatisch starten:

```bash
sudo systemctl enable wpa_supplicant@wlp2s0
sudo systemctl enable dnsmasq
# WARP startet seinen Dienst automatisch, ggf. einmal:
warp-cli enable-always-on
```

Falls WARP oder Policy‑Routing nach einem Reboot nicht zuverlässig aktiv ist, kannst du ein kleines Skript unter `/etc/network/if-up.d/warp-lan` anlegen:

```bash
sudo nano /etc/network/if-up.d/warp-lan
```

Inhalt:

```bash
#!/bin/sh
# Wird ausgeführt, wenn ein Interface "up" geht

# WARP sicher verbinden
warp-cli connect 2>/dev/null

# Policy-Routing für LAN erneut setzen
ip rule add from 192.168.50.0/24 table 100 priority 50 2>/dev/null
ip route replace 192.168.50.0/24 dev eno1 table 100 2>/dev/null
ip route replace default dev CloudflareWARP src 172.16.0.2 table 100 2>/dev/null
```

Ausführbar machen:

```bash
sudo chmod +x /etc/network/if-up.d/warp-lan
```

Damit solltest du nach jedem Neustart wieder das gleiche Verhalten haben:  
WPA2‑Enterprise‑Uplink, WARP‑Tunnel und ein LAN, dessen gesamter Traffic sauber durch Cloudflare WARP geht.