#!/bin/bash
# F5 VPN split tunnel connection using openconnect + vpn-slice
#
# Routes only the specified subnet through VPN, keeping all other traffic direct.
# Authenticates via browser cookie to support 2FA.

set -euo pipefail

# --- Configuration (edit these for your setup) ---
VPN_SERVER="${VPN_SERVER:-https://vpn.postech.ac.kr/}"
VPN_SUBNET="${VPN_SUBNET:-141.223.0.0/16}"
# -------------------------------------------------

VPNSLICE="$(command -v vpn-slice 2>/dev/null || { echo "Error: vpn-slice not found. Install with: pip install vpn-slice"; exit 1; })"

usage() {
    cat <<EOF
Usage: sudo $0 <MRHSession cookie value>

Split-tunnel F5 VPN connection. Only routes ${VPN_SUBNET} through VPN.

Steps:
  1. Log in to ${VPN_SERVER} in your browser (complete 2FA)
  2. Copy the MRHSession cookie value (see README for methods)
  3. Run: sudo $0 <cookie value>

Environment variables:
  VPN_SERVER   F5 VPN server URL (default: ${VPN_SERVER})
  VPN_SUBNET   Subnet to route through VPN (default: ${VPN_SUBNET})
EOF
    exit 1
}

COOKIE="${1:-}"
if [ -z "$COOKIE" ]; then
    usage
fi

echo "Connecting to ${VPN_SERVER}"
echo "Routing ${VPN_SUBNET} through VPN, all other traffic direct."
echo "Press Ctrl+C to disconnect."
echo ""

openconnect \
    --protocol=f5 \
    --cookie="MRHSession=${COOKIE}" \
    -s "$VPNSLICE $VPN_SUBNET" \
    "$VPN_SERVER"
