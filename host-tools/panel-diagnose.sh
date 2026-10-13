#!/usr/bin/env bash
# Read-only process, queue and error-count diagnostics; no log message contents.
set -uo pipefail
umask 077
report=$(mktemp "${TMPDIR:-/tmp}/host-panel-XXXXXXXX.txt") || exit 1
exec 3>&1
exec >"$report" 2>&1
python3 - <<'PY'
import ast, collections, json, pathlib, subprocess
def run(args):
    p = subprocess.run(args, capture_output=True, text=True, timeout=30)
    print('Command:', ' '.join(args), 'exit=',p.returncode)
    return p.stdout
print('=== Service resources ===')
print(run(['systemctl','show','caseparser','-p','MainPID','-p','ActiveState','-p','SubState',
           '-p','NRestarts','-p','TasksCurrent','-p','MemoryCurrent','-p','CPUUsageNSec',
           '-p','LimitNOFILE','-p','TasksMax','-p','MemoryMax']))
pid = run(['systemctl','show','caseparser','-p','MainPID','--value']).strip()
if pid.isdigit() and pid != '0':
    root = pathlib.Path('/proc')/pid
    try:
        print('=== Process state ===')
        for line in (root/'status').read_text().splitlines():
            if line.startswith(('State:','Threads:','VmRSS:','VmSwap:','FDSize:')): print(line)
        print('Open file descriptors:', len(list((root/'fd').iterdir())))
        waits=collections.Counter()
        for task in (root/'task').iterdir():
            try: waits[(task/'wchan').read_text().strip()] += 1
            except OSError: pass
        print('Thread wait channels:',dict(waits))
    except OSError as error: print(type(error).__name__,error.strerror)
print('=== Port 8443 queues and connections ===')
print(run(['ss','-H','-antp','( sport = :8443 )']))
print('=== Last 24h journal counts; message contents omitted ===')
# Bound output and capture only event counts, never print journal messages.
p=subprocess.run(['journalctl','-u','caseparser','--since','24 hours ago','-n','1000','-o','json','--no-pager'],
                 capture_output=True,text=True,timeout=30)
priorities=collections.Counter(); categories=collections.Counter(); count=0
for line in p.stdout.splitlines():
    try: event=json.loads(line)
    except json.JSONDecodeError: continue
    count+=1; priorities[str(event.get('PRIORITY','unknown'))]+=1
    message=str(event.get('MESSAGE','')).lower()
    for term in ('traceback','timeout','timed out','broken pipe','exception','ssl','too many open files'):
        if term in message: categories[term]+=1
print('journal exit=',p.returncode,'events=',count,'max=1000','priorities=',dict(priorities),'categories=',dict(categories))
print('=== Python HTTP server structure; no source contents or string literals ===')
base=pathlib.Path('/opt/caseparser/app')
files=[]
if base.is_dir():
    for path in base.rglob('*.py'):
        if any(part in ('.venv','venv','node_modules','.git','__pycache__') for part in path.relative_to(base).parts): continue
        if path.is_symlink(): continue
        if len(files)>=100: print('File limit reached; inspection incomplete'); break
        files.append(path)
for path in files:
    if path.stat().st_size>1048576: print('Large file skipped:',path.relative_to(base)); continue
    try: tree=ast.parse(path.read_text())
    except (OSError,UnicodeError,SyntaxError): print('Could not parse:',path.relative_to(base)); continue
    found=[]
    for node in ast.walk(tree):
        if isinstance(node,ast.Name) and node.id in ('HTTPServer','ThreadingHTTPServer','ThreadingMixIn','TCPServer','ThreadingTCPServer'):
            found.append((node.lineno,node.id))
        if isinstance(node,ast.Attribute) and node.attr in ('wrap_socket','settimeout','serve_forever','handle_request'):
            found.append((node.lineno,node.attr))
    if found: print(str(path.relative_to(base)), sorted(set(found)))
print('No service restarted or configuration changed.')
PY
printf '[exit=%s]\n' "$?"
printf 'Report saved: %s\n' "$report" >&3
