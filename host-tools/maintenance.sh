#!/usr/bin/env bash
# Ubuntu 22.04 package maintenance. May restart services; never reboots automatically.
set -euo pipefail
umask 077
[[ ${1:-} == --apply ]] || { echo 'Usage: bash maintenance.sh --apply'; exit 2; }
[[ $EUID == 0 ]] || { echo 'Run as root.' >&2; exit 1; }
. /etc/os-release
[[ $ID == ubuntu && $VERSION_ID == 22.04 ]] || { echo 'Expected Ubuntu 22.04.' >&2; exit 1; }
for tool in apt-get dpkg tar systemctl docker tee; do command -v "$tool" >/dev/null; done
[[ $(df --output=avail -B1 / | tail -1) -gt 3221225472 ]] || { echo 'Need at least 3 GiB free on /.' >&2; exit 1; }
audit=$(dpkg --audit)
[[ -z $audit ]] || { printf '%s\n' "$audit"; echo 'Resolve package inconsistency before upgrading.'; exit 1; }
work=$(mktemp -d /root/host-maintenance-XXXXXXXX)
chmod 700 "$work"
exec > >(tee "$work/update.log") 2>&1
trap 'echo "Maintenance failed. No automatic rollback of package upgrades. Local log: $work/update.log"' ERR
echo "Private maintenance directory: $work"
echo 'Configuration backup is NOT a backup of databases, mail or Docker volumes.'
tar -C / -cpf "$work/etc.tar" etc
tar -tf "$work/etc.tar" >/dev/null
dpkg-query -W '-f=${binary:Package}\t${Version}\t${db:Status-Abbrev}\n' > "$work/packages-before.tsv"
apt-mark showhold > "$work/holds-before.txt"
systemctl list-units --type=service --state=running --no-pager > "$work/services-before.txt"
systemctl --failed --no-pager > "$work/failed-before.txt"
docker ps -a --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}' > "$work/docker-before.txt"
ss -lntup > "$work/listeners-before.txt"
export DEBIAN_FRONTEND=noninteractive
apt-get --error-on=any update
apt-get -s --with-new-pkgs --no-remove upgrade > "$work/upgrade-plan.txt"
echo 'Applying package upgrades; service interruptions are possible.'
apt-get -y --with-new-pkgs --no-remove \
  -o Dpkg::Options::=--force-confdef \
  -o Dpkg::Options::=--force-confold upgrade
dpkg --audit > "$work/package-audit-after.txt"
[[ ! -s $work/package-audit-after.txt ]] || { cat "$work/package-audit-after.txt"; false; }
systemctl --failed --no-pager > "$work/failed-after.txt"
docker ps -a --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}' > "$work/docker-after.txt"
ss -lntup > "$work/listeners-after.txt"
{
  echo '=== Failed units before ==='; cat "$work/failed-before.txt"
  echo '=== Failed units after ==='; cat "$work/failed-after.txt"
  echo '=== Containers before ==='; cat "$work/docker-before.txt"
  echo '=== Containers after (healthchecks may still be starting) ==='; cat "$work/docker-after.txt"
  echo '=== SSH syntax ==='; /usr/sbin/sshd -t
  echo '=== Nginx syntax ==='; nginx -t
  echo '=== Fail2ban ==='; fail2ban-client status sshd
  echo '=== SSH port protection ==='; iptables -S INPUT
  echo '=== Remaining upgrades ==='; apt-get -s --with-new-pkgs --no-remove upgrade
  echo '=== Reboot marker ==='
  if [[ -f /var/run/reboot-required ]]; then cat /var/run/reboot-required; else echo 'No reboot marker'; fi
  echo '=== Currently running kernel ==='; uname -r
} > "$work/summary.txt" 2>&1
cat "$work/summary.txt"
echo "Share only the reviewed summary: $work/summary.txt"
echo 'Keep etc.tar private: it contains credentials. No container images were pulled.'
echo 'No automatic reboot performed; verify SSH and application functionality first.'
