#!/usr/bin/env bash
# Remove only a manually installed 3proxy; retain a private recovery archive.
set -euo pipefail
umask 077
[[ ${1:-} == --apply ]] || { echo 'Usage: bash remove-3proxy.sh --apply'; exit 2; }
[[ $EUID == 0 ]] || { echo 'Run as root.' >&2; exit 1; }
for command in systemctl tar dpkg-query ss python3; do command -v "$command" >/dev/null; done
unit=$(systemctl show 3proxy.service -p FragmentPath --value)
[[ $unit == /etc/systemd/system/3proxy.service ]] || {
  echo "Unexpected unit location: $unit; nothing changed." >&2; exit 1;
}
enabled=$(systemctl is-enabled 3proxy.service || true)
active=$(systemctl is-active 3proxy.service || true)
case "$enabled" in enabled|disabled|static) ;; *) echo "Unsupported enable state: $enabled" >&2; exit 1;; esac
case "$active" in active|inactive|failed) ;; *) echo "Unexpected active state: $active" >&2; exit 1;; esac
paths=(/etc/systemd/system/3proxy.service /usr/local/bin/3proxy)
for path in /etc/systemd/system/3proxy.service.d /etc/3proxy /etc/3proxy.cfg /usr/local/etc/3proxy; do
  if [[ -e $path || -L $path ]]; then paths+=("$path"); fi
done
python3 - "${paths[@]}" <<'PY'
import pathlib, subprocess, sys
for name in sys.argv[1:]:
    path = pathlib.Path(name)
    if path.is_symlink() or any(p.is_symlink() for p in path.parents):
        raise SystemExit(f'Refusing symlink path: {name}')
    if not path.exists(): raise SystemExit(f'Missing expected file: {name}')
    entries = [path] + (list(path.rglob('*')) if path.is_dir() else [])
    for entry in entries:
        if entry.is_symlink(): raise SystemExit(f'Refusing nested symlink: {entry}')
        if not (entry.is_file() or entry.is_dir()): raise SystemExit(f'Unsupported file: {entry}')
        if entry.is_file():
            result = subprocess.run(['dpkg-query','-S',str(entry)],capture_output=True, timeout=10)
            if result.returncode == 0: raise SystemExit(f'Package-owned file: {entry}; use package removal instead')
            if result.returncode != 1: raise SystemExit('Package ownership lookup failed')
PY
# Refuse extra drop-in files outside the preserved directory.
dropins=$(systemctl show 3proxy.service -p DropInPaths --value)
for path in $dropins; do
  [[ $path == /etc/systemd/system/3proxy.service.d/* ]] || {
    echo "Unexpected drop-in: $path; nothing changed." >&2; exit 1;
  }
done
backup=$(mktemp -d /root/3proxy-backup-XXXXXXXX)
chmod 700 "$backup"
relative=()
for path in "${paths[@]}"; do relative+=("${path#/}"); done
tar -C / -cpf "$backup/files.tar" -- "${relative[@]}"
tar -C / -df "$backup/files.tar"
printf '%s\n' "$enabled" > "$backup/enabled"
printf '%s\n' "$active" > "$backup/active"
cat > "$backup/restore.sh" <<'RESTORE'
#!/usr/bin/env bash
set -euo pipefail
dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# Explicit recovery may overwrite newer files at the archived locations.
tar -C / -xpf "$dir/files.tar"
systemctl daemon-reload
if [[ $(cat "$dir/enabled") == enabled ]]; then systemctl enable 3proxy.service; fi
if [[ $(cat "$dir/active") == active ]]; then systemctl start 3proxy.service; fi
RESTORE
printf 'Private backup (contains proxy credentials): %s\n' "$backup"
printf 'Rollback: bash %q\n' "$backup/restore.sh"
rollback() {
  result=$?
  trap - ERR
  echo 'Removal failed; attempting restoration.' >&2
  bash "$backup/restore.sh" || echo "Restoration failed: use $backup/restore.sh" >&2
  exit "$result"
}
trap rollback ERR
systemctl stop 3proxy.service
if [[ $enabled == enabled ]]; then systemctl disable 3proxy.service; fi
for path in "${paths[@]}"; do
  if [[ -d $path ]]; then rm -r -- "$path"; else rm -- "$path"; fi
done
systemctl daemon-reload
if systemctl is-active --quiet 3proxy.service; then
  echo '3proxy is still active.' >&2; false
fi
listeners=$(ss -H -lnt 'sport = :1080')
[[ -z $listeners ]] || { echo 'TCP 1080 still has a listener; restoring for diagnosis.' >&2; false; }
trap - ERR
echo 'Removed 3proxy unit, binary and discovered configuration. TCP 1080 has no listener.'
echo 'Backup retained locally; do not upload it. Historical logs are preserved.'
