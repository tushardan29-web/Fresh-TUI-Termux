#!/usr/bin/env python3
"""Run fresh in a headless PTY, capturing escape output and exit status."""
import os, pty, sys, time, select, signal

cmd = sys.argv[1:]
if not cmd:
    sys.exit("usage: run_pty.py <cmd...> [--timeout SECS]")
timeout = 8.0
if "--timeout" in cmd:
    i = cmd.index("--timeout")
    timeout = float(cmd[i + 1])
    cmd = cmd[:i] + cmd[i + 2:]

env = dict(os.environ)
env.setdefault("TERM", "xterm-256color")
env["FRESH_LOG_LEVEL"] = "trace"

pid, master = pty.fork()
if pid == 0:
    try:
        os.execvpe(cmd[0], cmd, env)
    except OSError as e:
        sys.stderr.write(f"exec failed: {e}\n")
        os._exit(127)

start = time.time()
data = b""
status = None
while time.time() - start < timeout:
    r, _, _ = select.select([master], [], [], 0.2)
    if r:
        try:
            chunk = os.read(master, 65536)
        except OSError:
            break
        if not chunk:
            break
        data += chunk
    wpid, wstatus = os.waitpid(pid, os.WNOHANG)
    if wpid == pid:
        status = wstatus
        while True:
            r, _, _ = select.select([master], [], [], 0.2)
            if not r:
                break
            try:
                chunk = os.read(master, 65536)
            except OSError:
                break
            if not chunk:
                break
            data += chunk
        break

if status is None:
    os.kill(pid, signal.SIGTERM)
    time.sleep(0.3)
    try:
        os.kill(pid, signal.SIGKILL)
    except ProcessLookupError:
        pass
    wpid, wstatus = os.waitpid(pid, 0)
    status = wstatus

out = data.decode("utf-8", "replace")
sys.stdout.write(out)
sys.stderr.write(f"\n[status: {status} killed_by_sig={status and os.WIFSIGNALED(status)}\n")
if status:
    sys.exit(0)