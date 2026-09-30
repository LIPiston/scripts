import tempfile
import unittest
from datetime import datetime
from pathlib import Path

from battery_data_recorder import (
    build_hwinfo_command,
    create_session_paths,
    should_auto_sleep,
    summarize_battery_samples,
)


class BatteryRecorderTest(unittest.TestCase):
    def test_paths_are_created_in_output(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            paths = create_session_paths(Path(temp_dir), datetime(2026, 9, 30, 12, 34, 56))
            self.assertEqual(paths.hwinfo_csv.name, "hwinfo_20260930_123456.csv")
            self.assertEqual(paths.battery_csv.name, "windows_battery_20260930_123456.csv")
            self.assertTrue(paths.output_dir.is_dir())

    def test_command_uses_hwinfopro_logging_parameters(self):
        command = build_hwinfo_command(
            Path(r"D:\Program Files\TubaWinUi3\Tools\综合检测\hwinfo\HWiNFO64.exe"),
            Path(r"D:\output\hwinfo.csv"),
            2000,
        )
        self.assertIn("-log_format=1", command)
        self.assertIn("-poll_rate=2000", command)
        self.assertIn(r"-lD:\output\hwinfo.csv", command)

    def test_summary_calculates_real_battery_drop(self):
        summary = summarize_battery_samples([
            {"timestamp": "2026-09-30T12:00:00+08:00", "battery_percent": 100},
            {"timestamp": "2026-09-30T13:00:00+08:00", "battery_percent": 80},
        ])
        self.assertEqual(summary["battery_drop_percent"], 20.0)
        self.assertEqual(summary["duration_minutes"], 60.0)
        self.assertEqual(summary["drop_percent_per_hour"], 20.0)

    def test_auto_sleep_only_on_battery_at_threshold(self):
        self.assertTrue(should_auto_sleep(10, False, 10))
        self.assertFalse(should_auto_sleep(10, True, 10))
        self.assertFalse(should_auto_sleep(11, False, 10))


if __name__ == "__main__":
    unittest.main()
