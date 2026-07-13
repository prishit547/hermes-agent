"""Tests for the device alarm tool module."""

import json
import os
from unittest.mock import patch, MagicMock

from tools.device_alarm_tool import device_alarm_tool


class TestDeviceAlarmTool:
    @patch("tools.device_alarm_tool.urllib.request.urlopen")
    @patch("tools.device_alarm_tool.os.getenv")
    @patch("tools.device_alarm_tool._load_env_vars")
    def test_device_alarm_success(self, mock_load, mock_getenv, mock_urlopen):
        # Configure env mocks
        def getenv_side_effect(key, default=None):
            if key == "NTFY_TOPIC":
                return "test-topic"
            if key == "NTFY_SERVER_URL":
                return "https://test.ntfy.sh"
            return default

        mock_getenv.side_effect = getenv_side_effect

        # Mock HTTP Response
        mock_resp = MagicMock()
        mock_resp.status = 200
        mock_urlopen.return_value.__enter__.return_value = mock_resp

        # Call tool
        res_str = device_alarm_tool(time="2026-07-13T07:30:00+05:30", title="Test Alarm")
        res = json.loads(res_str)

        assert res["status"] == "success"
        assert res["time"] == "2026-07-13T07:30:00+05:30"
        assert res["title"] == "Test Alarm"

        # Verify request setup
        assert mock_urlopen.called
        req = mock_urlopen.call_args[0][0]
        assert req.full_url == "https://test.ntfy.sh/test-topic"
        assert req.get_header("Title") == "Create Device Alarm"
        assert req.get_header("Priority") == "5"

    @patch("tools.device_alarm_tool.os.getenv")
    @patch("tools.device_alarm_tool._load_env_vars")
    def test_device_alarm_missing_topic(self, mock_load, mock_getenv):
        mock_getenv.return_value = None

        res_str = device_alarm_tool(time="2026-07-13T07:30:00+05:30", title="Test Alarm")
        assert "error" in res_str
        assert "No NTFY_TOPIC" in res_str
