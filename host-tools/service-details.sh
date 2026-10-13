#!/usr/bin/env bash
# Read-only service identity and sandbox metadata. No container environment dump.
set -uo pipefail
umask 077
report=$(mktemp "${TMPDIR:-/tmp}/host-services-XXXXXXXX.txt") || exit 1
exec 3>&1
exec >"$report" 2>&1
python3 - <<'PY'
import json, subprocess
def run(args):
    p = subprocess.run(args, capture_output=True, text=True, timeout=30)
    if p.returncode:
        print(f'{args[0]} failed, exit={p.returncode}')
        return None
    return p.stdout
ids = run(['docker', 'ps', '-q'])
if ids:
    # Ask Docker only for selected fields: never retrieve full inspect metadata.
    template = '{{json .Id}} {{json .Name}} {{json .Config.Image}} {{json .HostConfig.NetworkMode}} {{json .Config.User}} {{json .HostConfig.Privileged}} {{json .HostConfig.ReadonlyRootfs}}'
    for cid in ids.split():
        print('Container id/name/image/network/user/privileged/readonly-rootfs:')
        value = run(['docker', 'inspect', '--format', template, cid])
        if value: print(value.strip())
print('\nSelected service sandbox settings:')
value = run(['systemctl', 'show', '3proxy', 'caseparser', 'hexary-site-api',
             '-p', 'Id', '-p', 'User', '-p', 'Group', '-p', 'MainPID',
             '-p', 'NoNewPrivileges', '-p', 'ProtectSystem', '-p', 'ProtectHome',
             '-p', 'PrivateTmp', '-p', 'CapabilityBoundingSet'])
if value: print(value)
PY
printf '[exit=%s]\n' "$?"
printf '\n=== Fail2ban SSH ===\n'
timeout 30 fail2ban-client status sshd
printf '\n=== IPv4 input rules ===\n'
timeout 30 iptables -S INPUT
printf '\n=== IPv6 input rules ===\n'
timeout 30 ip6tables -S INPUT
printf 'Report saved: %s\n' "$report" >&3
