"""Dr.Docsis - Docker edition. Runs iPerf3-based fragmentation and throughput tests."""

import json
import logging
import os
import random
import re
import subprocess
import time
from datetime import datetime, timezone
from pathlib import Path

from flask import Flask, jsonify, request

log = logging.getLogger("drdocsis")
logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")

app = Flask(__name__)

DATA_DIR = os.environ.get("DATA_DIR", "/data")
SERVERS_FILE = os.environ.get("SERVERS_FILE", "/app/servers.json")
CONTRACT_DOWN = float(os.environ.get("CONTRACT_DOWN_MBIT", "250"))
CONTRACT_UP = float(os.environ.get("CONTRACT_UP_MBIT", "50"))
SLA_PERCENT = float(os.environ.get("SLA_PERCENT", "90"))
TEST_DURATION = int(os.environ.get("TEST_DURATION", "15"))

Path(DATA_DIR).mkdir(parents=True, exist_ok=True)

_servers = []
_last_result = None
_running = False


def _load_servers():
    global _servers
    try:
        with open(SERVERS_FILE) as f:
            _servers = json.load(f)
        log.info("Loaded %d iperf3 servers", len(_servers))
    except Exception as e:
        log.error("Failed to load servers: %s", e)
        _servers = []


def _pick_server():
    if not _servers:
        _load_servers()
    server = random.choice(_servers)
    port = random.choice(server["ports"])
    return server, port


def _run_iperf(args, timeout=None):
    """Run iperf3 and return (success, stdout)."""
    if timeout is None:
        timeout = TEST_DURATION + 15
    cmd = ["iperf3"] + args
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
        return result.returncode == 0, result.stdout
    except subprocess.TimeoutExpired:
        return False, "timeout"
    except Exception as e:
        return False, str(e)


def _parse_bandwidth(output):
    """Parse receiver bandwidth from iperf3 output."""
    lines = output.strip().split("\n")
    for line in reversed(lines):
        if "receiver" in line.lower():
            m = re.search(r"([\d.]+)\s+(Mbits|Gbits)/sec", line)
            if m:
                val = float(m.group(1))
                if "Gbits" in m.group(2):
                    val *= 1000
                return val
    return None


def _parse_udp_loss(output):
    """Parse UDP packet loss percentage from iperf3 output."""
    m = re.search(r"(\d+)/(\d+)\s+\(([\d.]+)%\)", output)
    if m:
        return float(m.group(3))
    return None


def run_test():
    """Run a full Dr.Docsis test cycle and return results."""
    global _last_result, _running
    if _running:
        return {"error": "test already running"}

    _running = True
    ts = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    server, port = _pick_server()
    host = server["host"]
    country = server["country"]
    dl_bw = f"{int(CONTRACT_DOWN * SLA_PERCENT / 100)}M"
    ul_bw = f"{int(CONTRACT_UP * SLA_PERCENT / 100)}M"

    log.info("Starting test cycle against %s (%s) port %d", host, country, port)
    results = {
        "timestamp": ts,
        "server": host,
        "country": country,
        "port": port,
        "tests": {},
    }

    try:
        # 1. TCP Download (Single Stream)
        log.info("  TCP-DL-Single...")
        ok, out = _run_iperf(["-c", host, "-p", str(port), "-t", str(TEST_DURATION), "-R"])
        bw = _parse_bandwidth(out) if ok else None
        results["tests"]["tcp_dl_single"] = {"success": ok, "mbps": bw}

        time.sleep(2)

        # 2. TCP Download (Multi Stream)
        log.info("  TCP-DL-Multi...")
        ok, out = _run_iperf(["-c", host, "-p", str(port), "-t", str(TEST_DURATION), "-R", "-P", "10"])
        bw = _parse_bandwidth(out) if ok else None
        results["tests"]["tcp_dl_multi"] = {"success": ok, "mbps": bw}

        time.sleep(2)

        # 3. TCP Upload (Single Stream)
        log.info("  TCP-UL-Single...")
        ok, out = _run_iperf(["-c", host, "-p", str(port), "-t", str(TEST_DURATION)])
        bw = _parse_bandwidth(out) if ok else None
        results["tests"]["tcp_ul_single"] = {"success": ok, "mbps": bw}

        time.sleep(2)

        # 4. UDP Fragmentation Test (1473 bytes = forces fragmentation)
        log.info("  UDP-Frag (1473B)...")
        ok, out = _run_iperf(["-c", host, "-p", str(port), "-u", "-b", ul_bw,
                              "-l", "1473", "-t", str(TEST_DURATION)])
        loss = _parse_udp_loss(out) if ok else None
        results["tests"]["udp_frag"] = {"success": ok, "packet_loss_pct": loss}

        time.sleep(2)

        # 5. UDP Reference Test (1472 bytes = no fragmentation)
        log.info("  UDP-Ref (1472B)...")
        ok, out = _run_iperf(["-c", host, "-p", str(port), "-u", "-b", ul_bw,
                              "-l", "1472", "-t", str(TEST_DURATION)])
        loss = _parse_udp_loss(out) if ok else None
        results["tests"]["udp_ref"] = {"success": ok, "packet_loss_pct": loss}

        # Diagnosis
        frag_loss = results["tests"]["udp_frag"].get("packet_loss_pct")
        ref_loss = results["tests"]["udp_ref"].get("packet_loss_pct")
        single = results["tests"]["tcp_dl_single"].get("mbps")
        multi = results["tests"]["tcp_dl_multi"].get("mbps")

        diagnosis = "incomplete"
        if frag_loss is not None and ref_loss is not None:
            if frag_loss > 5 and (ref_loss or 0) < 1:
                diagnosis = "fragmentation_failure"
            elif frag_loss > 5 and (ref_loss or 0) > 5:
                diagnosis = "general_packet_loss"
            else:
                diagnosis = "healthy"
        elif ref_loss is not None and ref_loss < 1:
            diagnosis = "healthy_partial"

        if single and multi and multi > 0:
            if single < multi * 0.5:
                diagnosis = "single_stream_degradation"

        results["diagnosis"] = diagnosis

        log.info("Test complete: diagnosis=%s", diagnosis)

    except Exception as e:
        log.error("Test failed: %s", e)
        results["error"] = str(e)
    finally:
        _running = False

    _last_result = results

    # Save to disk
    try:
        result_file = os.path.join(DATA_DIR, f"result_{ts.replace(':', '-')}.json")
        with open(result_file, "w") as f:
            json.dump(results, f, indent=2)
    except Exception as e:
        log.warning("Failed to save result: %s", e)

    return results


# --- API ---

@app.route("/api/run", methods=["POST"])
def api_run():
    """Trigger a test run."""
    if _running:
        return jsonify({"status": "busy", "message": "test already running"}), 409
    result = run_test()
    return jsonify(result), 200


@app.route("/api/results", methods=["GET"])
def api_results():
    """Return the latest test result."""
    if _last_result:
        return jsonify(_last_result)
    return jsonify({"message": "no results yet"}), 404


@app.route("/api/status", methods=["GET"])
def api_status():
    """Return service status."""
    return jsonify({
        "running": _running,
        "servers": len(_servers),
        "last_result": _last_result.get("timestamp") if _last_result else None,
    })


@app.route("/health")
def health():
    return jsonify({"status": "ok"})


if __name__ == "__main__":
    _load_servers()
    port = int(os.environ.get("PORT", "8780"))
    app.run(host="0.0.0.0", port=port)
