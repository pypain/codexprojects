#!/usr/bin/env bash
# Local, read-only access checks; never collects response bodies or credentials.
set -uo pipefail
umask 077
report=$(mktemp "${TMPDIR:-/tmp}/host-access-XXXXXXXX.txt") || exit 1
exec 3>&1
exec >"$report" 2>&1
python3 - <<'PY'
import pathlib, shlex, urllib.request, urllib.error, urllib.parse, subprocess
print('=== Unauthenticated local panel requests; no redirect following ===')
class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None
opener = urllib.request.build_opener(urllib.request.ProxyHandler({}), NoRedirect())
for scheme in ('http', 'https'):
    url = f'{scheme}://127.0.0.1:8443/'
    try:
        try:
            response = opener.open(urllib.request.Request(url, headers={'User-Agent':'host-local-audit'}), timeout=5)
        except urllib.error.HTTPError as error:
            response = error
        with response:
            print(url, 'status=', response.code)
            for header in ('Server', 'Content-Type', 'Strict-Transport-Security', 'X-Frame-Options', 'Content-Security-Policy', 'X-Content-Type-Options'):
                value = response.headers.get(header)
                if value: print(header + ':', value)
            print('Set-Cookie present:', bool(response.headers.get('Set-Cookie')))
            auth = response.headers.get('WWW-Authenticate')
            if auth: print('Authentication scheme:', auth.split()[0])
            location = response.headers.get('Location')
            if location:
                parsed = urllib.parse.urlsplit(location)
                print('Redirect destination (query omitted):', parsed.scheme, parsed.hostname, parsed.path)
    except Exception as error:
        print(url, 'failed:', type(error).__name__, str(error))
print('\n=== Selected 3proxy directives; user lists and credentials omitted ===')
for name in ('/etc/3proxy/3proxy.cfg', '/etc/3proxy.cfg', '/usr/local/etc/3proxy/3proxy.cfg'):
    path = pathlib.Path(name)
    if not path.is_file(): continue
    print('File:', name)
    for number, line in enumerate(path.read_text().splitlines(), 1):
        try: fields = shlex.split(line, comments=True)
        except ValueError:
            print('Unparsed line:', number); continue
        if not fields: continue
        key = fields[0].lower()
        if key == 'auth':
            modes = [v if v in ('none','strong','iponly','cache','radius','dnsname') else '[other-mode]' for v in fields[1:]]
            print(number, 'auth', *modes)
        elif key in ('allow', 'deny'):
            # ACL: users, source IPs, destination IPs, ports, operations, weekdays, time.
            print(number, key, '[users omitted]', 'source=', fields[2] if len(fields)>2 else '*',
                  'destination=', fields[3] if len(fields)>3 else '*',
                  'ports=', fields[4] if len(fields)>4 else '*')
        elif key in ('users','include','parent','system','setuid','setgid','socks','proxy','internal','external','flush'):
            print(number, key, '[arguments omitted]')
print('\n=== Effective process UIDs and GIDs ===')
for service in ('3proxy', 'hexary-site-api', 'caseparser'):
    result = subprocess.run(['systemctl','show', service,'-p','MainPID','--value'], capture_output=True, text=True, timeout=5)
    pid = result.stdout.strip()
    if not pid.isdigit() or pid == '0':
        print(service, 'not running or unavailable'); continue
    try:
        for line in (pathlib.Path('/proc') / pid / 'status').read_text().splitlines():
            if line.startswith(('Uid:', 'Gid:', 'NoNewPrivs:')): print(service, line)
    except OSError as error: print(service, error.strerror)
print('\n=== Nginx routing directives (not full configuration) ===')
# Only known routing keys; omit credentials, URL userinfo and query strings.
for path in sorted(pathlib.Path('/etc/nginx/sites-enabled').glob('*')):
    if not path.is_file(): continue
    print('Site file:', path.name)
    for line in path.read_text().splitlines():
        stripped = line.strip()
        if stripped.startswith('#'): continue
        for key in ('listen', 'server_name', 'proxy_pass', 'auth_basic', 'auth_request'):
            if not stripped.startswith(key + ' '): continue
            value = stripped[len(key):].strip().rstrip(';')
            if key == 'proxy_pass':
                parsed = urllib.parse.urlsplit(value)
                try: port = parsed.port
                except ValueError: port = '[unparsed]'
                value = f'{parsed.scheme}://{parsed.hostname}:{port}'
            elif key in ('auth_basic', 'auth_request'):
                value = 'off' if value == 'off' else '[configured]'
            print(key, value)
print('Only sites-enabled examined; included files and application authentication are not evaluated.')
PY
printf '[exit=%s]\n' "$?"
printf 'Report saved: %s\n' "$report" >&3
