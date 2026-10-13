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
test_ip=192.0.2.254
# TEST-NET-1 address; never use the connected client as a test ban.
ssh_connection=${SSH_CONNECTION:-}
[[ ${ssh_connection%% *} != "$test_ip" ]] || { echo 'Test address matches SSH client.' >&2; exit 1; }
existing_bans=$(fail2ban-client get sshd banip)
if printf '%s\n' "$existing_bans" | grep -qw "$test_ip"; then
  echo 'Test address already banned; refusing to change its state.' >&2
  exit 1
fi
test_ban_added=0
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
  if [[ $test_ban_added == 1 ]]; then fail2ban-client set sshd unbanip "$test_ip" || true; fi
  echo 'Diagnostic: effective action startup command:' >&2
  fail2ban-client get sshd action iptables-multiport actionstart >&2 || true
  iptables -S INPUT >&2 || true
  echo 'Change failed; attempting rollback.' >&2
  bash "$backup/restore.sh" || echo "Rollback failed; use $backup/restore.sh from provider console." >&2
  exit "$result"
}
trap rollback ERR
printf '[sshd]\nport = 2222\n' > "$target"
chmod 600 "$target"
fail2ban-client -t
fail2ban-client reload --restart sshd
# Actions are asynchronous and may start only when the first ban is applied.
test_ban_added=1
fail2ban-client set sshd banip "$test_ip"
python3 - "$test_ip" <<'PY'
import shlex, subprocess, sys, time
deadline = time.monotonic() + 20
test_ip = sys.argv[1]
while True:
    def rules(chain):
        p = subprocess.run(['iptables', '-S', chain], capture_output=True,
                           text=True, timeout=3)
        return [shlex.split(line) for line in p.stdout.splitlines()] if p.returncode == 0 else []
    protects_port = any('f2b-sshd' in r and '--dports' in r and
                        '2222' in r[r.index('--dports') + 1].split(',')
                        for r in rules('INPUT'))
    blocks_test = any('-s' in r and r[r.index('-s') + 1] == test_ip + '/32'
                      and '-j' in r and r[r.index('-j') + 1] in ('REJECT', 'DROP')
                      for r in rules('f2b-sshd'))
    if protects_port and blocks_test:
        print('Verified: Fail2ban protects TCP 2222 and installed the test ban')
        break
    if time.monotonic() >= deadline:
        raise SystemExit('Fail2ban rule verification failed after waiting; rolling back')
    time.sleep(0.5)
PY
fail2ban-client set sshd unbanip "$test_ip"
test_ban_added=0
fail2ban-client status sshd
trap - ERR
echo 'SSH passwords and root login unchanged. Keep this session open and test a second SSH login.'
