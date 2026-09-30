"""Record HWiNFO and Windows battery telemetry during normal laptop use."""

from __future__ import annotations

import argparse
import csv
import json
import signal
import subprocess
import sys
import time
from datetime import datetime
from pathlib import Path

import psutil

from battery_data_recorder import (
    SessionPaths,
    create_session_paths,
    launch_hwinfo,
    should_auto_sleep,
    summarize_battery_samples,
)

BASE_DIR = Path(__file__).resolve().parent
DEFAULT_HWINFO_DIR = Path(r"D:\Program Files\TubaWinUi3\Tools\综合检测\hwinfo")
DEFAULT_OUTPUT_DIR = BASE_DIR / "output"
BATTERY_INTERVAL_SECONDS = 10
HWINFO_POLL_RATE_MS = 2000
AUTO_SLEEP_THRESHOLD_PERCENT = 10


class BatterySession:
    def __init__(self, paths: SessionPaths, interval_seconds: int, auto_sleep: bool, sleep_threshold: float):
        self.paths = paths
        self.interval_seconds = interval_seconds
        self.auto_sleep = auto_sleep
        self.sleep_threshold = sleep_threshold
        self.started_at = datetime.now().astimezone()
        self.stop_requested = False
        self.samples: list[dict[str, object]] = []
        self.hwinfo_process: subprocess.Popen[bytes] | None = None

    def request_stop(self, *_args: object) -> None:
        self.stop_requested = True

    def _battery_sample(self) -> dict[str, object]:
        battery = psutil.sensors_battery()
        sample: dict[str, object] = {
            "timestamp": datetime.now().astimezone().isoformat(timespec="seconds"),
            "unix_timestamp": time.time(),
            "battery_percent": None,
            "power_plugged": None,
            "seconds_left": None,
        }
        if battery is not None:
            sample.update(
                {
                    "battery_percent": battery.percent,
                    "power_plugged": int(battery.power_plugged),
                    "seconds_left": battery.secsleft,
                }
            )
        return sample

    def _request_sleep(self) -> None:
        print(f"[电池] 电量达到 {self.sleep_threshold:g}% 或更低，准备自动休眠。")
        try:
            subprocess.run(["rundll32.exe", "powrprof.dll,SetSuspendState", "0,1,0"], check=True)
        except (OSError, subprocess.CalledProcessError) as error:
            print(f"[电池] 自动休眠失败，请手动处理: {error}")

    def _should_sleep(self, sample: dict[str, object]) -> bool:
        return self.auto_sleep and should_auto_sleep(
            sample.get("battery_percent"), sample.get("power_plugged"), self.sleep_threshold
        )

    def run(self) -> int:
        executable = DEFAULT_HWINFO_DIR / "HWiNFO64.exe"
        if not executable.is_file():
            arm64 = DEFAULT_HWINFO_DIR / "HWiNFO_ARM64.exe"
            executable = arm64 if arm64.is_file() else executable
        if not executable.is_file():
            print(f"[HWiNFO] 未找到可执行文件: {DEFAULT_HWINFO_DIR}", file=sys.stderr)
            return 2

        print(f"[HWiNFO] 可执行文件: {executable}")
        print(f"[输出] {self.paths.output_dir}")
        print("开始记录。请正常使用电脑；按 Ctrl+C 停止并生成摘要。")
        print(f"自动休眠: {'开启' if self.auto_sleep else '关闭'}，阈值: {self.sleep_threshold:g}%")

        fields = ["timestamp", "unix_timestamp", "battery_percent", "power_plugged", "seconds_left"]
        with self.paths.battery_csv.open("w", newline="", encoding="utf-8-sig") as handle:
            writer = csv.DictWriter(handle, fieldnames=fields)
            writer.writeheader()
            sample = self._battery_sample()
            writer.writerow(sample)
            self.samples.append(sample)
            handle.flush()

            if self._should_sleep(sample):
                self.stop_requested = True
                self._request_sleep()

            try:
                self.hwinfo_process = launch_hwinfo(executable, self.paths.hwinfo_csv, HWINFO_POLL_RATE_MS)
                time.sleep(2)
                if self.hwinfo_process.poll() is None:
                    print(f"[HWiNFO] 已启动日志: {self.paths.hwinfo_csv}")
                else:
                    print(f"[HWiNFO] 启动后退出，返回码: {self.hwinfo_process.returncode}")
                    print("[HWiNFO] 可能需要管理员权限，或当前版本/授权不支持命令行自动记录。")
            except OSError as error:
                print(f"[HWiNFO] 启动失败: {error}")
                print("[HWiNFO] 仍继续记录 Windows 电池数据。")

            while not self.stop_requested:
                time.sleep(self.interval_seconds)
                sample = self._battery_sample()
                writer.writerow(sample)
                self.samples.append(sample)
                handle.flush()
                print(
                    f"[{sample['timestamp']}] 电量={sample['battery_percent']}% "
                    f"电源={'接通' if sample['power_plugged'] else '电池'}"
                )
                if self._should_sleep(sample):
                    self.stop_requested = True
                    self._request_sleep()
        return 0

    def finish(self) -> None:
        summary = summarize_battery_samples(
            [sample for sample in self.samples if sample.get("battery_percent") is not None]
        )
        payload = {
            "session_started_at": self.started_at.isoformat(timespec="seconds"),
            "session_finished_at": datetime.now().astimezone().isoformat(timespec="seconds"),
            "battery_csv": str(self.paths.battery_csv),
            "hwinfo_csv": str(self.paths.hwinfo_csv),
            "summary": summary,
        }
        self.paths.summary_json.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
        print(f"[输出] 电池记录: {self.paths.battery_csv}")
        print(f"[输出] HWiNFO记录: {self.paths.hwinfo_csv}")
        print(f"[输出] 摘要: {self.paths.summary_json}")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="记录 HWiNFO 与 Windows 电池数据")
    parser.add_argument("--interval", type=int, default=BATTERY_INTERVAL_SECONDS, help="Windows 电池采样间隔，单位秒")
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT_DIR, help="输出目录")
    parser.add_argument("--no-auto-sleep", action="store_true", help="禁用低电量自动休眠")
    parser.add_argument("--sleep-threshold", type=float, default=AUTO_SLEEP_THRESHOLD_PERCENT, help="自动休眠电量阈值，默认 10%%")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if args.interval < 1 or not 1 <= args.sleep_threshold <= 100:
        print("参数无效：interval 必须大于 0，sleep-threshold 必须在 1 到 100 之间。", file=sys.stderr)
        return 2
    paths = create_session_paths(args.output)
    session = BatterySession(paths, args.interval, not args.no_auto_sleep, args.sleep_threshold)
    signal.signal(signal.SIGINT, session.request_stop)
    if hasattr(signal, "SIGTERM"):
        signal.signal(signal.SIGTERM, session.request_stop)
    try:
        return session.run()
    finally:
        session.finish()


if __name__ == "__main__":
    raise SystemExit(main())
