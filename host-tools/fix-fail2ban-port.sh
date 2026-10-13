#!/usr/bin/env bash
# Explicit, narrow change: point the existing sshd jail at port 2222.
# Does not change SSH authentication, sshd configuration, or global firewall policy.
set -euo pipefail
umask 077
[[ ${1:-} == --apply ]] || { echo 'Usage: bash fix-fail2ban-port.sh --apply'; exit 2; }
[[ $EUID == 0 ]] || { echo 'Run as root.' >&2; exit 1; }
for tool in fail2ban-client iptables python3; do command -v "$tool" >/dev/null; done
ports=$(/usr/sbin/sshd -T | awk '$1 == "port" {print $2}')
[[ $ports == 2222 ]] || { echo 'Expected SSH port 2222; refusing to guess.' >&2; exit 1; }
fail2ban-client ping
fail2ban-client status sshd
target=/etc/fail2ban/jail.d/zzzz-host-tools-ssh-port.local
[[ ! -L $target ]] || { echo 'Refusing symlink target.' >&2; exit 1; }
backup=$(mktemp -d /root/fail2ban-port-backup-XXXXXXXX)
chmod 700 "$backup"
if [[ -e $target ]]; then
  [[ -f $target ]] || exit 1
  cp -p -- "$target" "$backup/previous.local"
fi
cat > "$backup/restore.sh" <<'RESTORE'
#!/usr/bin/env bash
set -euo pipefail
dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
target=/etc/fail2ban/jail.d/zzzz-host-tools-ssh-port.local
[[ ! -L $target ]] || exit 1
if [[ -f $dir/previous.local ]]; then
  cp -p -- "$dir/previous.local" "$target"
else
  rm -f -- "$target"
fi
fail2ban-client -t
fail2ban-client reload --restart sshd
RESTORE
printf 'Rollback: bash %q\n' "$backup/restore.sh"
rollback() {
  result=$?
  trap - ERR
  echo 'Change failed; attempting rollback.' >&2
  bash "$backup/restore.sh" || echo "Rollback failed; use $backup/restore.sh from provider console." >&2
  exit "$result"
}
trap rollback ERR
printf '[sshd]\nport = 2222\n' > "$target"
chmod 600 "$target"
fail2ban-client -t
fail2ban-client reload --restart sshd
# Verify the actual input rule, not merely configuration or a running service.
iptables -S INPUT | python3 -c '
import shlex, sys
rules = [shlex.split(line) for line in sys.stdin]
assert any("f2b-sshd" in r and "--dports" in r and
           "2222" in r[r.index("--dports") + 1].split(",") for r in rules), "No Fail2ban input rule protecting TCP 2222"
print("Verified: Fail2ban input rule protects port 2222")
'
fail2ban-client status sshd
trap - ERR
echo 'SSH passwords and root login unchanged. Keep this session open and test a second SSH login.'
