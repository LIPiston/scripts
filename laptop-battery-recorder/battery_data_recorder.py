"""Helpers for the standalone laptop-battery recorder."""

from __future__ import annotations

import os
import subprocess
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import Iterable, Mapping


@dataclass(frozen=True)
class SessionPaths:
    output_dir: Path
    hwinfo_csv: Path
    battery_csv: Path
    summary_json: Path


def should_auto_sleep(battery_percent: float | int | None, power_plugged: bool | int | None, threshold: float) -> bool:
    if battery_percent is None or power_plugged:
        return False
    return float(battery_percent) <= float(threshold)


def create_session_paths(output_dir: str | os.PathLike[str], started_at: datetime | None = None) -> SessionPaths:
    started_at = started_at or datetime.now()
    output = Path(output_dir)
    output.mkdir(parents=True, exist_ok=True)
    stamp = started_at.strftime("%Y%m%d_%H%M%S")
    return SessionPaths(
        output_dir=output,
        hwinfo_csv=output / f"hwinfo_{stamp}.csv",
        battery_csv=output / f"windows_battery_{stamp}.csv",
        summary_json=output / f"battery_summary_{stamp}.json",
    )


def build_hwinfo_command(executable: str | os.PathLike[str], csv_path: str | os.PathLike[str], poll_rate_ms: int) -> list[str]:
    return [
        str(Path(executable)),
        "-log_format=1",
        f"-poll_rate={int(poll_rate_ms)}",
        f"-l{Path(csv_path)}",
    ]


def _parse_timestamp(value: str) -> datetime | None:
    for fmt in ("%Y-%m-%dT%H:%M:%S.%f%z", "%Y-%m-%dT%H:%M:%S%z", "%Y-%m-%d %H:%M:%S"):
        try:
            return datetime.strptime(str(value).strip(), fmt)
        except ValueError:
            continue
    return None


def summarize_battery_samples(samples: Iterable[Mapping[str, object]]) -> dict[str, float | int | None]:
    rows = list(samples)
    if not rows:
        return {
            "sample_count": 0,
            "start_battery_percent": None,
            "end_battery_percent": None,
            "battery_drop_percent": None,
            "duration_minutes": None,
            "drop_percent_per_hour": None,
            "estimated_minutes_to_5_percent": None,
        }
    first, last = rows[0], rows[-1]
    start_battery = float(first["battery_percent"])
    end_battery = float(last["battery_percent"])
    drop = start_battery - end_battery
    start_time = _parse_timestamp(str(first["timestamp"]))
    end_time = _parse_timestamp(str(last["timestamp"]))
    if start_time and end_time:
        if start_time.tzinfo and end_time.tzinfo:
            duration_minutes = (end_time - start_time).total_seconds() / 60
        else:
            duration_minutes = (end_time.replace(tzinfo=None) - start_time.replace(tzinfo=None)).total_seconds() / 60
    else:
        duration_minutes = None
    rate = drop / duration_minutes * 60 if duration_minutes and duration_minutes > 0 else None
    remaining = (end_battery - 5) / rate * 60 if rate and rate > 0 and end_battery > 5 else None
    return {
        "sample_count": len(rows),
        "start_battery_percent": start_battery,
        "end_battery_percent": end_battery,
        "battery_drop_percent": drop,
        "duration_minutes": duration_minutes,
        "drop_percent_per_hour": rate,
        "estimated_minutes_to_5_percent": remaining,
    }


def launch_hwinfo(executable: Path, csv_path: Path, poll_rate_ms: int) -> subprocess.Popen[bytes]:
    return subprocess.Popen(build_hwinfo_command(executable, csv_path, poll_rate_ms), cwd=str(executable.parent))
