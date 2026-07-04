#!/usr/bin/env python3
"""
Download cc-connect Windows release from GitHub.

Usage:
    python download_cc_connect.py [--version VERSION]

Defaults to latest known version. Downloads to system temp directory.
"""

import urllib.request
import os
import sys
import json
import re

# Default version (update as needed)
DEFAULT_VERSION = "v1.4.1"

def get_latest_version():
    """Try to fetch the latest release tag from GitHub API."""
    try:
        url = "https://api.github.com/repos/chenhg5/cc-connect/releases/latest"
        req = urllib.request.Request(url, headers={"User-Agent": "cc-connect-downloader"})
        with urllib.request.urlopen(req, timeout=15) as resp:
            data = json.loads(resp.read().decode())
            return data.get("tag_name", DEFAULT_VERSION)
    except Exception:
        return DEFAULT_VERSION

def main():
    version = sys.argv[sys.argv.index("--version") + 1] if "--version" in sys.argv else get_latest_version()

    # Normalize version (ensure v prefix)
    if not version.startswith("v"):
        version = "v" + version

    filename = f"cc-connect-{version}-windows-amd64.zip"
    url = f"https://github.com/chenhg5/cc-connect/releases/download/{version}/{filename}"
    dest = os.path.join(os.environ.get("TEMP", os.environ.get("TMP", ".")), filename)

    print(f"Downloading cc-connect {version} ...")
    print(f"URL: {url}")
    print(f"Destination: {dest}")

    def reporthook(block_num, block_size, total_size):
        if total_size <= 0:
            return
        downloaded = block_num * block_size
        percent = min(downloaded * 100.0 / total_size, 100.0)
        kb_down = downloaded // 1024
        kb_total = total_size // 1024
        sys.stdout.write(f"\r{percent:.1f}%  ({kb_down} KB / {kb_total} KB)")
        sys.stdout.flush()

    try:
        req = urllib.request.Request(url, headers={"User-Agent": "cc-connect-downloader"})
        with urllib.request.urlopen(req, timeout=120) as resp:
            with open(dest, "wb") as f:
                while True:
                    chunk = resp.read(8192)
                    if not chunk:
                        break
                    f.write(chunk)
                    # Approximate progress
                    downloaded = f.tell()
                    if resp.length and resp.length > 0:
                        percent = min(downloaded * 100.0 / resp.length, 100.0)
                        sys.stdout.write(f"\r{percent:.1f}%  ({downloaded // 1024} KB / {resp.length // 1024} KB)")
                        sys.stdout.flush()
        print()
        file_size = os.path.getsize(dest)
        print(f"Download complete! Size: {file_size} bytes")
        print(f"File: {dest}")
        print(f"\nNext steps:")
        print(f"  1. Extract to C:\\Program Files\\cc-connect\\")
        print(f"  2. Rename exe to cc-connect.exe")
        print(f"  3. Add to PATH")
        sys.exit(0)
    except Exception as e:
        print(f"\nERROR: {e}")
        sys.exit(1)

if __name__ == "__main__":
    main()
