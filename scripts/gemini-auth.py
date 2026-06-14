#!/usr/bin/env python3
"""Extract Gemini cookies from Windows Firefox profile (WSL-compatible).
Prints export statements to stdout so they can be eval'd by shell wrappers.
Also sets them directly if --set-env is passed.

Usage:
  eval "$(python3 gemini-auth.py)"            # export to shell
  python3 gemini-auth.py --set-env -- testcmd  # set and run command
"""

import sqlite3, shutil, os, sys, subprocess, glob

def find_firefox_profile():
    """Auto-discover Firefox profile directory (Windows/WSL compatible)."""
    # Try Windows Firefox profiles
    for base in [
        os.path.expanduser("~/AppData/Roaming/Mozilla/Firefox/Profiles"),
        "/mnt/c/Users/*/AppData/Roaming/Mozilla/Firefox/Profiles",
    ]:
        try:
            for profile_dir in glob.glob(os.path.join(base, "*.default*")):
                cookies_db = os.path.join(profile_dir, "cookies.sqlite")
                if os.path.exists(cookies_db):
                    return profile_dir
        except Exception:
            continue
    # Fallback: try Linux Firefox
    for base in [os.path.expanduser("~/.mozilla/firefox")]:
        try:
            for profile_dir in glob.glob(os.path.join(base, "*.default*")):
                cookies_db = os.path.join(profile_dir, "cookies.sqlite")
                if os.path.exists(cookies_db):
                    return profile_dir
        except Exception:
            continue
    return None


def extract_cookies():
    profile = find_firefox_profile()
    if not profile:
        sys.stderr.write("[gemini-auth] No Firefox profile found. Login to gemini.google.com in Firefox first.\n")
        return None, None
    cookies_db = os.path.join(profile, "cookies.sqlite")
    tmp = "/tmp/firefox_gemini_cookies.sqlite"
    try:
        shutil.copy2(cookies_db, tmp)
    except FileNotFoundError:
        sys.stderr.write("[gemini-auth] Firefox cookies.sqlite not found\n")
        return None, None

    conn = sqlite3.connect(tmp)
    sid_row = conn.execute(
        "SELECT value FROM moz_cookies WHERE host='.google.com' AND name='__Secure-1PSID'"
    ).fetchone()
    ts_row = conn.execute(
        "SELECT value FROM moz_cookies WHERE host='.google.com' AND name='__Secure-1PSIDTS'"
    ).fetchone()
    conn.close()

    sid = sid_row[0] if sid_row else None
    ts = ts_row[0] if ts_row else None
    return sid, ts


def main():
    sid, ts = extract_cookies()

    if not sid:
        sys.stderr.write("[gemini-auth] No Gemini cookies found. Login at gemini.google.com in Firefox first.\n")
        sys.exit(1)

    if "--set-env" in sys.argv:
        # Set and run a subcommand
        idx = sys.argv.index("--set-env")
        cmd = sys.argv[idx + 1:]
        if not cmd:
            sys.stderr.write("[gemini-auth] No command after --set-env\n")
            sys.exit(1)
        env = os.environ.copy()
        env["GEMINI_SID"] = sid
        if ts:
            env["GEMINI_TS"] = ts
        result = subprocess.run(cmd, env=env)
        sys.exit(result.returncode)
    else:
        # Print export statements for shell eval
        print(f'export GEMINI_SID="{sid}"')
        print(f'export GEMINI_TS="{ts}"')


if __name__ == "__main__":
    main()
