#!/usr/bin/env bash
# Read-only follow-up; no full configs, process arguments or environment dumps.
set -uo pipefail
umask 077
report=$(mktemp "${TMPDIR:-/tmp}/host-followup-XXXXXXXX.txt") || exit 1
exec 3>&1
exec >"$report" 2>&1
check() {
  printf '\n=== %s ===\n' "$1"; shift
  timeout 30 "$@"
  printf '[exit=%s]\n' "$?"
}
check Fail2ban-SSH fail2ban-client status sshd
check Fail2ban-actions fail2ban-client get sshd actions
check Package-consistency dpkg --audit
check Docker-package-state dpkg-query -W '-f=${binary:Package}\t${db:Status-Abbrev}\t${Version}\n' docker.io docker-ce containerd containerd.io
check Held-packages apt-mark showhold
check Upgrade-plan-with-new-dependencies apt-get -s --with-new-pkgs upgrade
check Update-timers systemctl list-timers apt-daily.timer apt-daily-upgrade.timer --no-pager
printf '\n=== Automatic update policy (selected non-secret keys) ===\n'
apt-config dump | awk '/^APT::Periodic::|^Unattended-Upgrade::(Allowed-Origins|Origins-Pattern|Package-Blacklist|Automatic-Reboot)/'
printf '\n=== Unattended-upgrades log dates (contents not collected) ===\n'
find /var/log/unattended-upgrades -maxdepth 1 -type f -printf '%TY-%Tm-%Td %TH:%TM %s %f\n'
check Service-users systemctl show 3proxy caseparser axolotl-account hexary-site-api -p Id -p User -p Group -p MainPID -p NoNewPrivileges -p ProtectSystem
printf '\n=== Listener process metadata (no command arguments) ===\n'
python3 - <<'PY'
import pathlib, re, subprocess
result = subprocess.run(['ss', '-lntup'], text=True, capture_output=True, check=True)
for line in result.stdout.splitlines():
    if not re.search(r':(1080|8443|2223)\s', line):
        continue
    print(line)
    for pid in re.findall(r'pid=(\d+)', line):
        root = pathlib.Path('/proc') / pid
        for name in ('exe', 'cwd'):
            try:
                print(f'pid={pid} {name}={ (root / name).readlink() }')
            except OSError as e:
                print(f'pid={pid} {name}: {e.strerror}')
        try:
            print((root / 'cgroup').read_text())
        except OSError as e:
            print(e.strerror)
PY
printf '[exit=%s]\n' "$?"
printf '\n=== 3proxy authentication mode only (no users/passwords/ACL contents) ===\n'
for config in /etc/3proxy/3proxy.cfg /etc/3proxy.cfg /usr/local/etc/3proxy/3proxy.cfg; do
  if [[ -f $config ]]; then
    printf 'File: %s\n' "$config"
    awk '$1 == "auth" {for (i=2;i<=NF;i++) {if ($i ~ /^#/ ) break; if ($i ~ /^(none|iponly|strong|cache|radius|dnsname)$/) printf "%s ", $i; else printf "[other-mode] "}; print ""}' "$config"
  fi
done
printf 'Report saved: %s\n' "$report" >&3
