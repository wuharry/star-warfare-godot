"""Run real ENet pairs, two bounded Godot processes at a time; never use real saves."""
from __future__ import annotations

import argparse
from contextlib import ExitStack
from pathlib import Path
import re
import subprocess
import time
import uuid

MODES = ("VS_FFA", "VS_TDM", "CTF_FFA", "CTF_TDM", "VIP", "CMI", "Survival", "Boss")


def stop_process(process: subprocess.Popen) -> int:
    """Bound both graceful termination and forced cleanup."""
    code = process.poll()
    if code is not None:
        return code
    try:
        process.terminate()
    except ProcessLookupError:
        pass
    try:
        return process.wait(timeout=5)
    except subprocess.TimeoutExpired:
        try:
            process.kill()
        except ProcessLookupError:
            pass
        return process.wait(timeout=5)


def run_pair(mode: str, port: int, transport: bool = False, extra: list[str] | None = None, capture: bool = False, combat: bool = False) -> bool:
    if transport and combat:
        raise ValueError("transport and combat are mutually exclusive")
    if mode not in MODES and not (transport and mode == "transport"):
        raise ValueError(f"Unknown mode: {mode}")
    if not 1 <= port <= 65535:
        raise ValueError(f"Invalid port: {port}")
    root = Path(__file__).resolve().parents[1]
    output_dir = root / "test_output"
    output_dir.mkdir(parents=True, exist_ok=True)
    stamp = uuid.uuid4().hex[:10]
    scene = "network_transport_test" if transport else ("network_combat_peer_test" if combat else "network_peer_test")
    expected = "NETWORK_TRANSPORT_PASS" if transport else "NETWORK_PEER_PASS"
    processes = []
    base = ["/opt/homebrew/bin/godot", "--headless", "--single-threaded-scene", "--max-fps", "30",
            "--path", str(root), f"res://tests/{scene}.tscn", "--quit-after", "2400", "--"]
    with ExitStack() as streams:
        try:
            for role in ("host", "client"):
                log = output_dir / f"network_{mode}_{stamp}_{role}.log"
                stream = streams.enter_context(log.open("w", encoding="utf-8"))
                command = base + [f"--role={role}", f"--mode={mode}", f"--port={port}",
                                  f"--test-profile=net_{stamp}_{role}"] + (extra or [])
                if capture and role == "host":
                    command.remove("--headless")
                    capture_file = "network_combat.png" if combat else "network_hud.png"
                    command += [f"--capture={output_dir / capture_file}"]
                process = subprocess.Popen(command, cwd=root, stdout=stream, stderr=subprocess.STDOUT)
                processes.append((role, process, stream, log))
                if role == "host":
                    time.sleep(0.8)
            passed = True
            for role, process, stream, log in processes:
                timed_out = False
                try:
                    code = process.wait(timeout=80)
                except subprocess.TimeoutExpired:
                    timed_out = True
                    code = stop_process(process)
                stream.close()
                output = log.read_text(encoding="utf-8")
                errors = re.findall(r"^.*(?:SCRIPT ERROR|ERROR:|_FAIL).*$", output, re.MULTILINE)
                warnings = re.findall(r"^.*(?:WARNING:|leaked|in use at exit).*$", output, re.MULTILINE)
                ok = not timed_out and code == 0 and expected in output and not errors
                passed = passed and ok
                print(f"{mode} {role}: {'PASS' if ok else 'FAIL'} exit={code} timeout={timed_out} warnings={len(warnings)} {log}", flush=True)
                for line in errors + warnings:
                    print(line, flush=True)
            return passed
        finally:
            cleanup_errors = []
            for _, process, _, _ in processes:
                try:
                    stop_process(process)
                except (OSError, subprocess.TimeoutExpired) as error:
                    cleanup_errors.append(error)
            if cleanup_errors:
                raise RuntimeError("Unable to stop all Godot test processes") from cleanup_errors[0]


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("modes", nargs="*", default=list(MODES))
    parser.add_argument("--port", type=int, default=24760)
    scenarios = parser.add_mutually_exclusive_group()
    scenarios.add_argument("--transport", action="store_true")
    scenarios.add_argument("--combat", action="store_true")
    parser.add_argument("--boss-index", type=int, choices=range(6), default=0)
    parser.add_argument("--source-arena", action="store_true")
    parser.add_argument("--actions", action="store_true")
    parser.add_argument("--capture", action="store_true")
    parser.add_argument("--knockback", action="store_true")
    args = parser.parse_args()
    unknown_modes = [mode for mode in args.modes if mode not in MODES]
    if unknown_modes:
        parser.error("unknown modes: " + ", ".join(unknown_modes))
    pair_count = 1 if args.transport else len(args.modes)
    if not 1 <= args.port <= 65535 or args.port + pair_count - 1 > 65535:
        parser.error("all test ports must be within 1..65535")
    results = []
    for offset, mode in enumerate(["transport"] if args.transport else args.modes):
        extra = [f"--boss-index={args.boss_index}"] + (["--source-arena"] if args.source_arena else [])
        if args.actions:
            extra.append("--actions")
        if args.knockback:
            extra.append("--knockback")
        results.append(run_pair(mode, args.port + offset, args.transport, extra, args.capture, args.combat))
    raise SystemExit(0 if all(results) else 1)
