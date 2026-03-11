# vpn-bypass

Split tunneling for F5 BIG-IP VPN on macOS. Routes only specified subnets through VPN while keeping all other traffic direct.

## Problem

F5 BIG-IP Edge Client forces a full tunnel — all traffic goes through VPN by routing `0.0.0.0/1` and `128.0.0.0/1` via the VPN interface. The client actively prevents split tunneling by:

- Resetting any manual route changes in real-time
- Intercepting packets below the routing table level via its `f5vpnhelper` daemon

This makes the internet unusably slow when you only need VPN access to specific hosts.

## Solution

Replace the F5 client with [`openconnect`](https://www.infradead.org/openconnect/) (which supports the F5 protocol) combined with [`vpn-slice`](https://github.com/dlenski/vpn-slice) for client-side split tunneling.

Since `openconnect` may not handle F5's complex 2FA flows, we authenticate via browser and pass the session cookie to `openconnect`.

## Prerequisites

```bash
brew install openconnect
pip install vpn-slice
```

**Important:** If you have other VPN extensions installed (e.g., Proton VPN), disable their Network Extensions to avoid packet interference:

> System Settings → General → Login Items & Extensions → Network Extensions

## Usage

### 1. Authenticate in browser

Log in to your F5 VPN portal (e.g., `https://vpn.postech.ac.kr/`) and complete 2FA.

### 2. Copy the session cookie

After login, copy the `MRHSession` cookie value using one of these methods:

**Method A — Bookmarklet (recommended)**

Create a browser bookmark with this URL:

```
javascript:void(navigator.clipboard.writeText(document.cookie.split(';').map(c=>c.trim()).find(c=>c.startsWith('MRHSession=')).split('=')[1]).then(()=>alert('MRHSession copied!')))
```

Click it after login to copy the cookie to your clipboard.

**Method B — DevTools**

1. Open DevTools (`F12` or `Cmd+Option+I`)
2. Go to **Application → Cookies → your VPN domain**
3. Copy the `MRHSession` value

### 3. Connect

```bash
sudo ./vpn-connect.sh <MRHSession value>

# Or using clipboard directly (macOS):
sudo ./vpn-connect.sh $(pbpaste)
```

### 4. Verify

In another terminal:

```bash
# Should route through VPN
ssh your-server

# Should be fast and direct (not through VPN)
ping 8.8.8.8
curl ifconfig.me
```

### 5. Disconnect

Press `Ctrl+C` in the terminal running `vpn-connect.sh`.

## Configuration

Edit the variables at the top of `vpn-connect.sh` or use environment variables:

```bash
# Connect to a different F5 server
VPN_SERVER="https://vpn.example.com/" sudo ./vpn-connect.sh <cookie>

# Route a different subnet through VPN
VPN_SUBNET="10.0.0.0/8" sudo ./vpn-connect.sh <cookie>

# Multiple subnets: edit the script and pass multiple args to vpn-slice
# e.g., vpn-slice 10.0.0.0/8 172.16.0.0/12
```

## How it works

1. **Browser login** handles F5's 2FA authentication and produces an `MRHSession` session cookie
2. **openconnect** uses the `--protocol=f5` flag to speak F5's VPN protocol, authenticating with the browser cookie
3. **vpn-slice** replaces the default VPN script (`vpnc-script`) and only adds routes for the specified subnets, leaving the default route untouched

This gives you a VPN tunnel that only carries traffic to the specified subnets. All other traffic goes through your normal internet connection.

## Troubleshooting

### Cookie expired
MRHSession cookies have a limited lifetime. If `openconnect` fails to connect, log in again via browser and get a fresh cookie.

### Other VPN extensions interfering
If you experience high packet loss or latency, check for other VPN-related Network Extensions:
```bash
systemextensionsctl list
```
Disable any active VPN extensions in System Settings.

### openconnect authentication fails
If passing `--user` and `--passwd-on-stdin` doesn't work with your F5 portal (common with complex 2FA), the browser cookie method described above is the recommended workaround.

## License

MIT
