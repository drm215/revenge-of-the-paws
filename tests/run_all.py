"""Runs every check in tests/checks plus the two-device raid, and fails if any of them do.

    python tests/run_all.py [name ...]

A check passes when it prints "0 failure(s)", with no FAIL line and no script error. Each one gets
its own empty user-data folder, so it can never touch real saves, and its own fresh fake server.
Set GODOT to choose the Godot console executable.
"""
import glob
import os
import shutil
import socket
import subprocess
import sys
import tempfile
import threading
import time
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TESTS = ROOT / "tests"
TIMEOUT = 180
DUO_TIMEOUT = 300
WORKERS = max(2, min(6, (os.cpu_count() or 4) // 2))


def find_godot() -> str:
    found = os.environ.get("GODOT") or shutil.which("godot")
    if found:
        return found
    pattern = os.path.expandvars(r"%LOCALAPPDATA%\Microsoft\WinGet\Packages\GodotEngine*\Godot_v*_console.exe")
    matches = glob.glob(pattern)
    if matches:
        return matches[0]
    sys.exit("Godot not found: set GODOT to the console executable.")


def free_port() -> int:
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


class Server:
    """A fresh fake Supabase, up and listening."""

    def __enter__(self) -> str:
        port = free_port()
        self.process = subprocess.Popen([sys.executable, str(TESTS / "fake_supabase.py"), str(port)],
                                        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        deadline = time.time() + 10
        while time.time() < deadline:
            with socket.socket() as s:
                if s.connect_ex(("127.0.0.1", port)) == 0:
                    return f"http://127.0.0.1:{port}"
            time.sleep(0.05)
        raise RuntimeError("fake server didn't start")

    def __exit__(self, *_) -> None:
        self.process.kill()
        self.process.wait()


def environment(url: str, data: str) -> dict:
    env = dict(os.environ, FAKE_SUPABASE_URL=url)
    # Where Godot keeps user:// on Windows and on Linux/Mac.
    env.update(APPDATA=data, XDG_DATA_HOME=data, HOME=data)
    return env


def godot(script: str, env: dict, args: list, timeout: int) -> tuple:
    """Runs a script; returns (output, timed out). A script error ends it at once: after one, a
    check that awaits something may never get to quit."""
    command = [GODOT, "--headless", "--path", str(ROOT), "--script", script]
    if args:
        command += ["--"] + args
    process = subprocess.Popen(command, env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                               text=True, encoding="utf-8", errors="replace")
    timed_out = []
    watchdog = threading.Timer(timeout, lambda: (timed_out.append(True), process.kill()))
    watchdog.start()
    lines = []
    for line in process.stdout:
        lines.append(line)
        if "SCRIPT ERROR" in line or "Parse Error" in line:
            process.kill()
    process.wait()
    watchdog.cancel()
    return "".join(lines), bool(timed_out)


def problems(output: str) -> list:
    return [line.strip() for line in output.splitlines()
            if line.startswith("FAIL") or "SCRIPT ERROR" in line or "Parse Error" in line]


def run_check(name: str) -> tuple:
    start = time.time()
    with tempfile.TemporaryDirectory(prefix="paws_test_") as data, Server() as url:
        output, timed_out = godot(f"res://tests/checks/{name}.gd", environment(url, data), [], TIMEOUT)
    bad = problems(output)
    if timed_out:
        bad.append(f"timed out after {TIMEOUT} s")
    elif "0 failure(s)" not in output and not bad:
        bad.append('never printed "0 failure(s)"')
    return name, bad, time.time() - start


def run_duo() -> tuple:
    """Two devices fight one raid: both must end on exactly the same battle."""
    start = time.time()
    bad = []
    with tempfile.TemporaryDirectory(prefix="paws_test_") as data, Server() as url:
        out = Path(data) / "out"
        out.mkdir()
        script = "res://tests/raid_duo.gd"
        with ThreadPoolExecutor(2) as pool:
            devices = {}
            for role in "AB":
                folder = Path(data) / role
                folder.mkdir()
                devices[role] = pool.submit(godot, script, environment(url, str(folder)), [role, str(out)], DUO_TIMEOUT)
            results = {role: job.result() for role, job in devices.items()}
        lines = {}
        for role, (output, timed_out) in results.items():
            bad += [f"{role}: {p}" for p in problems(output)]
            bad += [f"{role}: {l.strip()}" for l in output.splitlines() if "TIMEOUT" in l]
            if timed_out:
                bad.append(f"{role}: timed out after {DUO_TIMEOUT} s")
            report = out / f"duo_{role}.txt"
            if report.exists():
                lines[role] = report.read_text(encoding="utf-8").splitlines()
            else:
                bad.append(f"{role}: wrote no end state")
    if len(lines) == 2:
        # The third line is each player's own rewards, which differ.
        if lines["A"][:2] != lines["B"][:2]:
            bad.append("the devices ended on different battles")
        if not all("claimed=true" in lines[role][2] for role in lines):
            bad.append("a player didn't collect their share")
    return "raid_duo", bad, time.time() - start


def main() -> int:
    wanted = sys.argv[1:]
    names = sorted(p.stem for p in (TESTS / "checks").glob("*.gd"))
    if wanted:
        names = [n for n in names if n in wanted or n.removesuffix("_check") in wanted]
    start = time.time()
    with ThreadPoolExecutor(WORKERS) as pool:
        jobs = [pool.submit(run_check, name) for name in names]
        if not wanted or "raid_duo" in wanted:
            jobs.append(pool.submit(run_duo))
        failed = 0
        for job in jobs:
            name, bad, seconds = job.result()
            print(f"{'FAIL' if bad else 'ok  '} {name} ({seconds:.0f} s)")
            for line in bad:
                print(f"       {line}")
            failed += 1 if bad else 0
    print(f"{len(jobs) - failed} passed, {failed} failed in {time.time() - start:.0f} s")
    return 1 if failed else 0


GODOT = find_godot()

if __name__ == "__main__":
    sys.exit(main())
