#!/usr/bin/env python3
"""Automates F5 VPN login with email OTP and connects via openconnect."""

import os
import sys
import re
import time
import json
import getpass
import subprocess
import datetime

import requests
from dotenv import load_dotenv
from playwright.sync_api import sync_playwright

# Paths
GMAIL_CREDENTIALS = os.path.expanduser("~/.gmail-mcp/credentials.json")
GMAIL_OAUTH_KEYS = os.path.expanduser("~/.gmail-mcp/gcp-oauth.keys.json")

# VPN config (overridable via env)
VPN_URL = os.environ.get("VPN_SERVER", "https://vpn.postech.ac.kr/")
VPN_SUBNET = os.environ.get("VPN_SUBNET", "141.223.0.0/16")


def get_gmail_access_token():
    """Get a fresh Gmail access token using the refresh token."""
    with open(GMAIL_CREDENTIALS) as f:
        creds = json.load(f)
    with open(GMAIL_OAUTH_KEYS) as f:
        oauth = json.load(f)
        keys = oauth.get("web", oauth.get("installed", {}))

    resp = requests.post("https://oauth2.googleapis.com/token", data={
        "client_id": keys["client_id"],
        "client_secret": keys["client_secret"],
        "refresh_token": creds["refresh_token"],
        "grant_type": "refresh_token",
    })
    resp.raise_for_status()
    return resp.json()["access_token"]


def search_otp_email(access_token, after_epoch):
    """Search Gmail for the latest VPN OTP email after a given timestamp."""
    query = f"from:vpn-admin@postech.ac.kr subject:(F5 SSL VPN OTP) after:{after_epoch}"
    resp = requests.get(
        "https://gmail.googleapis.com/gmail/v1/users/me/messages",
        headers={"Authorization": f"Bearer {access_token}"},
        params={"q": query, "maxResults": 1},
    )
    resp.raise_for_status()
    messages = resp.json().get("messages", [])
    if not messages:
        return None

    msg_id = messages[0]["id"]
    resp = requests.get(
        f"https://gmail.googleapis.com/gmail/v1/users/me/messages/{msg_id}",
        headers={"Authorization": f"Bearer {access_token}"},
        params={"format": "metadata", "metadataHeaders": "Subject"},
    )
    resp.raise_for_status()
    msg = resp.json()

    # Extract OTP from subject: "F5 SSL VPN OTP Code : 343721"
    headers = {h["name"]: h["value"] for h in msg["payload"]["headers"]}
    subject = headers.get("Subject", "")
    match = re.search(r"OTP\s*Code\s*:\s*(\d+)", subject, re.IGNORECASE)
    if match:
        return match.group(1)
    return None


def wait_for_otp(access_token, after_epoch, timeout=120, interval=3):
    """Poll Gmail for the OTP email."""
    print("  Waiting for OTP email...", flush=True)
    start = time.time()
    while time.time() - start < timeout:
        otp = search_otp_email(access_token, after_epoch)
        if otp:
            return otp
        elapsed = int(time.time() - start)
        print(f"  ... polling ({elapsed}s)", end="\r", flush=True)
        time.sleep(interval)
    raise TimeoutError("OTP email not received within timeout")


def dump_page_debug(page, label=""):
    """Print debug info about the current page."""
    print(f"\n--- DEBUG {label} ---")
    print(f"  URL: {page.url}")
    print(f"  Title: {page.title()}")
    inputs = page.query_selector_all("input, select")
    for inp in inputs:
        tag = inp.evaluate("el => el.tagName")
        attrs = inp.evaluate("""el => {
            const a = {};
            for (const attr of el.attributes) a[attr.name] = attr.value;
            return a;
        }""")
        print(f"  <{tag.lower()} {' '.join(f'{k}={v!r}' for k,v in attrs.items())}>")
    print("--- END DEBUG ---\n")


def main():
    # Load .env from script directory
    load_dotenv(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".env"))

    headless = "--no-headless" not in sys.argv
    debug = "--debug" in sys.argv

    # Get credentials
    username = os.environ.get("VPN_USERNAME") or input("VPN Username: ")
    password = os.environ.get("VPN_PASSWORD") or getpass.getpass("VPN Password: ")

    # Get Gmail access token
    print("[1/6] Getting Gmail access token...")
    access_token = get_gmail_access_token()
    print("  OK")

    # Record timestamp before login (for filtering OTP emails)
    after_epoch = int(time.time())

    with sync_playwright() as p:
        # Use system Chrome if available, else bundled Chromium
        try:
            browser = p.chromium.launch(headless=headless, channel="chrome")
        except Exception:
            browser = p.chromium.launch(headless=headless)
        context = browser.new_context()
        page = context.new_page()

        # Step 1: Navigate to VPN login page
        print("[2/6] Opening VPN login page...")
        page.goto(VPN_URL, timeout=15000)
        page.wait_for_load_state("networkidle")
        if debug:
            dump_page_debug(page, "LOGIN PAGE")

        # Step 2: Fill in credentials
        print("[3/6] Submitting credentials...")
        page.fill("#input_1", username)
        page.fill("#input_2", password)
        page.select_option("#input_3", "SMTP")
        page.click("input[type='submit']")

        # Wait for OTP page to load
        page.wait_for_load_state("networkidle", timeout=15000)
        time.sleep(2)

        if debug:
            dump_page_debug(page, "AFTER LOGIN SUBMIT")

        # Step 3: Find OTP input field
        # F5 OTP page has: <input type='password' name='OTP' id='input_2'>
        otp_input = (
            page.query_selector("input[name='OTP']")
            or page.query_selector("input[type='password']")
            or page.query_selector("#input_2")
        )

        if not otp_input:
            print("ERROR: Could not find OTP input field on the page.")
            if not debug:
                dump_page_debug(page, "OTP PAGE (error)")
            screenshot = os.path.join(os.path.dirname(os.path.abspath(__file__)), "debug-otp-page.png")
            page.screenshot(path=screenshot)
            print(f"  Screenshot saved to {screenshot}")
            browser.close()
            sys.exit(1)

        # Step 4: Get OTP from Gmail
        print("[4/6] Waiting for OTP from Gmail...")
        otp = wait_for_otp(access_token, after_epoch)
        print(f"  OTP received: {otp}")

        # Step 5: Enter OTP and submit
        print("[5/6] Entering OTP...")
        otp_input.fill(otp)
        page.click("input[type='submit']")
        # F5 portals keep connections open, so don't wait for networkidle
        page.wait_for_load_state("domcontentloaded", timeout=15000)
        time.sleep(3)

        if debug:
            dump_page_debug(page, "AFTER OTP SUBMIT")

        # Step 6: Extract MRHSession cookie
        cookies = context.cookies()
        mrh_cookie = None
        for cookie in cookies:
            if cookie["name"] == "MRHSession":
                mrh_cookie = cookie["value"]
                break

        browser.close()

    if not mrh_cookie:
        print("ERROR: MRHSession cookie not found after login.")
        sys.exit(1)

    print(f"[6/6] MRHSession cookie obtained: {mrh_cookie[:20]}...")

    # Connect VPN
    vpn_script = os.path.join(os.path.dirname(os.path.abspath(__file__)), "vpn-connect.sh")
    print(f"\nStarting VPN connection...")
    print(f"  sudo {vpn_script} <cookie>")
    subprocess.run(["sudo", vpn_script, mrh_cookie])


if __name__ == "__main__":
    main()
