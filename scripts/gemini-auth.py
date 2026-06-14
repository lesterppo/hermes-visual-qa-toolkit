#!/usr/bin/env python3
"""Extract Gemini cookies from Windows Firefox profile (WSL-compatible).
Prints export statements to stdout so they can be eval'd by shell wrappers.
Also sets them directly if --set-env is passed.

Usage:
  eval "$(python3 gemini-auth.py)"            # export to shell
  python3 gemini-auth.py --set-env -- testcmd  # set and run command
"""

import sqlite3, shutil, os, sys, subprocess

FIREFOX_PROFILE = "/mnt/c/Users/Peter/AppData/Roaming/Mozilla/Firefox/Profiles/jzkf87zc.default-1467441358099"
COOKIES_DB = os.path.join(FIREFOX_PROFILE, "cookies.sqlite")


def extract_cookies():
    tmp = "/tmp/firefox_gemini_cookies.sqlite"
    try:
        shutil.copy2(COOKIES_DB, tmp)
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
