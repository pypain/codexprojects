#!/usr/bin/env bash
# Read-only inventory. Does not install, update, restart or alter firewall rules.
set -uo pipefail
umask 077
report=$(mktemp "${TMPDIR:-/tmp}/host-audit-XXXXXXXX.txt") || exit 1
exec 3>&1
exec >"$report" 2>&1
check() {
  printf '\n=== %s ===\n' "$1"
  shift
  timeout 30 "$@"
  result=$?
  printf '[exit=%s]\n' "$result"
}
check OS cat /etc/os-release
check Kernel uname -rmo
check Uptime uptime
check Disk df -hT
check Inodes df -ih
check Memory free -h
check Failed-units systemctl --failed --no-pager
check Running-services systemctl list-units --type=service --state=running --no-pager
check Listeners ss -lntup
check SSH-syntax /usr/sbin/sshd -t
printf '\n=== Selected effective SSH settings (without connection-specific Match context) ===\n'
timeout 30 /usr/sbin/sshd -T | awk '$1 ~ /^(port|permitrootlogin|passwordauthentication|pubkeyauthentication|kbdinteractiveauthentication|authenticationmethods|maxauthtries|allowtcpforwarding|gatewayports|x11forwarding)$/ {print}'
printf '[pipeline-exit=%s]\n' "$?"
check UFW ufw status verbose
check IPv4-firewall iptables -S
check IPv4-Docker-forwarding iptables -S DOCKER-USER
check IPv6-firewall ip6tables -S
check Nftables nft list ruleset
check Package-versions dpkg-query -W '-f=${binary:Package}\t${Version}\n' openssh-server nginx docker.io docker-ce containerd.io python3 linux-image-generic unattended-upgrades
check Pending-updates apt list --upgradable
check Update-simulation apt-get -s upgrade
printf '\n=== Package index ages (results may be stale; no apt update performed) ===\n'
find /var/lib/apt/lists -maxdepth 1 -type f -name '*InRelease' -printf '%TY-%Tm-%Td %TH:%TM %f\n'
check Automatic-updates systemctl is-enabled apt-daily.timer apt-daily-upgrade.timer
check Security-maintenance pro security-status
printf '\n=== Reboot required ===\n'
if [[ -f /var/run/reboot-required ]]; then cat /var/run/reboot-required; else printf 'No reboot marker\n'; fi
check Docker-summary docker ps -a --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}'
check Docker-space docker system df
check Nginx-syntax nginx -t
check Fail2ban fail2ban-client status
check Journal-space journalctl --disk-usage
printf '\nReport contains service names, addresses and firewall rules. Review before sharing.\n'
printf 'Report saved: %s\n' "$report" >&3
