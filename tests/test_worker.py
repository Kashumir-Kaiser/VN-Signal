"""Pure offline unit tests: never import vnstock or make network calls."""
import importlib.util
import math
from pathlib import Path
import unittest
from unittest.mock import patch

p = Path(__file__).resolve().parents[1] / "py" / "vnstock_worker.py"
spec = importlib.util.spec_from_file_location("vnstock_worker", p)
worker = importlib.util.module_from_spec(spec)
spec.loader.exec_module(worker)


class WorkerTests(unittest.TestCase):
    def test_health(self):
        self.assertEqual(worker.dispatch({"op": "health"})["protocol"], 1)

    def test_passive_probe_never_fetches_market_data(self):
        with patch.object(worker, "_cli", return_value={"tier": "unknown"}):
            with patch.object(worker, "_fetch", side_effect=AssertionError("market call")):
                result = worker.dispatch({"op": "probe", "active": False})
        self.assertEqual(result["routes"], {})
        self.assertFalse(result["active"])

    def test_unknown_route_rejected(self):
        with self.assertRaises(ValueError):
            worker.dispatch({"op": "eval", "source": "anything"})

    def test_nan_is_json_null(self):
        self.assertIsNone(worker._safe(float("nan")))
        self.assertIsNone(worker._safe(float("inf")))
        self.assertEqual(worker._safe([1, math.nan]), [1, None])

    def test_symbol_validation(self):
        self.assertEqual(worker._symbol({"symbol": "fpt"}), "FPT")
        with self.assertRaises(ValueError):
            worker._symbol({"symbol": "FPT; rm /"})

    def test_frame_preserves_provider_identity_allowlist(self):
        class Frame:
            columns = ["time", "close"]
            attrs = {
                "source": "vci", "route": "equity_ohlcv",
                "source_name": "Provider VCI", "organisation": "Provider One",
                "access_domain": "example.invalid", "private_token": "must-not-leak",
            }

            def to_dict(self, orient):
                self.asserted_orient = orient
                return [{"time": "2026-10-16", "close": 100.0}]

        data = worker._frame(Frame())
        self.assertEqual(data["attributes"]["source"], "vci")
        self.assertEqual(data["attributes"]["organisation"], "Provider One")
        self.assertNotIn("private_token", data["attributes"])


# Integration tests for main() and subprocess failures: offline by construction.
import io
import json
import subprocess
import sys
import types


class FrameTests(unittest.TestCase):
    def run_lines(self, lines, dispatch=None):
        stdin = types.SimpleNamespace(buffer=io.BytesIO(lines))
        stdout = io.StringIO()
        errout = io.StringIO()
        ctx = patch.object(worker, "dispatch", side_effect=dispatch) if dispatch else patch.object(worker, "_fetch", side_effect=AssertionError("unexpected live call"))
        with ctx, patch.object(worker.sys, "stdin", stdin), patch.object(worker.sys, "stdout", stdout), patch.object(worker.sys, "stderr", errout):
            worker.main()
        return [json.loads(s) for s in stdout.getvalue().splitlines()], errout.getvalue()

    def test_malformed_non_object_unknown_and_oversized(self):
        cases = [b"{invalid\n", b"[1,2]\n", b'"hello"\n', b'{"id":"a","op":"shell"}\n', b" " * 70000 + b"\n"]
        for data in cases:
            with self.subTest(data=data[:30]):
                frames, _ = self.run_lines(data)
                self.assertEqual(len(frames), 1)
                self.assertFalse(frames[0]["ok"])
        # An oversized line must be drained, not treated as several frames.
        frames, _ = self.run_lines(b"x" * 70000 + b"\n" + b'{"id":"next","op":"health"}\n')
        self.assertEqual(len(frames), 2)
        self.assertTrue(frames[1]["ok"])

    def test_stdout_from_vnstock_isolated(self):
        def vendor_prints(job):
            print("vendor warning leaked from numpy")
            return {"fine": True}
        frames, err = self.run_lines(b'{"id":"x","op":"health"}\n', vendor_prints)
        self.assertEqual(len(frames), 1)
        self.assertTrue(frames[0]["ok"])
        self.assertIn("vendor warning", err)

    def test_system_exit_is_returned_as_one_safe_frame(self):
        def adapter_exits(_job):
            raise SystemExit("private vendor detail")
        frames, _ = self.run_lines(b'{"id":"x","op":"equity_list"}\n', adapter_exits)
        self.assertEqual(len(frames), 1)
        self.assertFalse(frames[0]["ok"])
        self.assertEqual(frames[0]["error"]["type"], "WorkerSystemExit")
        self.assertNotIn("private vendor detail", json.dumps(frames[0]))

    def test_vietnamese_text_round_trips_on_ascii_stdout(self):
        class ASCIIOnly(io.StringIO):
            def write(self, value):
                value.encode("ascii")
                return super().write(value)

        stdin = types.SimpleNamespace(buffer=io.BytesIO(b'{"id":"x","op":"equity_list"}\n'))
        stdout = ASCIIOnly()
        with patch.object(worker.sys, "stdin", stdin), patch.object(worker.sys, "stdout", stdout), \
                patch.object(worker, "dispatch", return_value={"name": "Công ty Cổ phần"}):
            worker.main()

        wire = stdout.getvalue()
        self.assertIn("\\u", wire)
        self.assertEqual(json.loads(wire)["data"]["name"], "Công ty Cổ phần")

    def test_broken_pipe_terminates_cleanly(self):
        class ClosedStream:
            def write(self, _):
                raise BrokenPipeError()
            def flush(self):
                pass
        with patch.object(worker.sys, "stdin", types.SimpleNamespace(buffer=io.BytesIO(b'{"id":"1","op":"health"}\n'))), patch.object(worker.sys, "stdout", ClosedStream()):
            worker.main()  # must not raise BrokenPipeError

    def test_real_health_subprocess(self):
        proc = subprocess.run([sys.executable, str(p)], input='{"id":"real","op":"health"}\n', capture_output=True, text=True, timeout=5)
        self.assertEqual(proc.returncode, 0, proc.stderr)
        body = json.loads(proc.stdout)
        self.assertEqual(body["id"], "real")
        self.assertEqual(body["data"]["protocol"], 1)


class LocalCLITests(unittest.TestCase):
    def test_fundamental_request_attribution_and_provider_conflicts(self):
        class FakeFrame:
            columns = ["period", "id", "value"]
            attrs = {"source": "vci", "route": "fundamental.equity.income_statement"}
            def to_dict(self, orient):
                return [{"period": "2025-Q1", "id": "fixture", "value": 1}]
        received = {}
        frame = FakeFrame()
        class FakeEquity:
            def income_statement(self, **kwargs):
                received.update(kwargs)
                return frame
        class FakeFundamental:
            def equity(self, symbol):
                received["symbol"] = symbol
                return FakeEquity()
        module = types.SimpleNamespace(Fundamental=FakeFundamental, Market=lambda: None, Reference=lambda: None)
        job = {"op": "income_statement", "symbol": "FPT", "period": "quarter", "source": "vci"}
        with patch.dict(sys.modules, {"vnstock": module}), patch.dict(worker.os.environ, {"VNPIPE_DISABLE_LIVE": "0"}):
            result = worker._fetch(job)
            self.assertEqual(received, {"symbol": "FPT", "period": "quarter", "source": "vci"})
            self.assertEqual(result["attributes"]["symbol"], "FPT")
            self.assertEqual(result["attributes"]["requested_symbol"], "FPT")
            self.assertEqual(result["attributes"]["symbol_basis"], "request")
            frame.attrs = dict(FakeFrame.attrs, symbol=" fpt ")
            self.assertEqual(worker._fetch(job)["attributes"]["symbol_basis"], "provider_and_request")
            for bad in ("OTHER", 123, ""):
                frame.attrs = dict(FakeFrame.attrs, symbol=bad)
                with self.assertRaisesRegex(ValueError, "provider symbol"):
                    worker._fetch(job)

    def test_cli_places_global_json_option_before_subcommand(self):
        result = subprocess.CompletedProcess(
            [], 0, '{"tier":"community"}', "")
        with patch.object(worker.subprocess, "run", return_value=result) as run:
            self.assertEqual(worker._cli("status"), {"tier": "community"})
        args, kwargs = run.call_args
        self.assertEqual(args[0][-2:], ["--json", "status"])
        self.assertTrue(kwargs["capture_output"])

    def test_cli_fatal_cases(self):
        for outcome in (subprocess.TimeoutExpired("vnstock", 30), FileNotFoundError("missing CLI")):
            with patch.object(worker.subprocess, "run", side_effect=outcome):
                self.assertFalse(worker._cli("usage")["available"])
        for result in (subprocess.CompletedProcess([], 3, "", "oops"), subprocess.CompletedProcess([], 0, "not-json", "")):
            with patch.object(worker.subprocess, "run", return_value=result):
                self.assertFalse(worker._cli("status")["available"])

    def test_source_reaches_correct_method(self):
        # v5 documents source= on ohlcv(), not on Market().equity().
        received = {}
        class FakeFrame:
            columns = ["close"]
            attrs = {"source": "kbs"}
            def to_dict(self, orient):
                self_orient = orient
                assert self_orient == "records"
                return [{"close": 100}]
        class FakeEquity:
            def ohlcv(self, **kwargs):
                received.update(kwargs)
                return FakeFrame()
        class FakeMarket:
            def equity(self, symbol):
                self.symbol = symbol
                return FakeEquity()
        module = types.SimpleNamespace(Market=FakeMarket, Fundamental=lambda: None, Reference=lambda: None)
        with patch.dict(sys.modules, {"vnstock": module}), patch.dict(worker.os.environ, {"VNPIPE_DISABLE_LIVE": "0"}):
            out = worker._fetch({"op":"equity_ohlcv", "symbol":"FPT", "start":"2025-01-01", "end":"2025-01-03", "source":"kbs"})
        self.assertEqual(out["count"], 1)
        self.assertEqual(received["source"], "kbs")
        self.assertEqual(received["interval"], "1D")

    def test_raw_prices_passes_floating_none_through_jsonl(self):
        received = {}
        class FakeFrame:
            columns = ["time", "close"]
            attrs = {"source": "vci"}
            def to_dict(self, orient):
                return [{"time": "2026-10-16", "close": 100}]
        class FakeEquity:
            def ohlcv(self, **kwargs):
                received.update(kwargs)
                return FakeFrame()
        class FakeMarket:
            def equity(self, symbol):
                return FakeEquity()
        module = types.SimpleNamespace(Market=FakeMarket, Fundamental=lambda: None, Reference=lambda: None)
        with patch.dict(sys.modules, {"vnstock": module}), patch.dict(worker.os.environ, {"VNPIPE_DISABLE_LIVE": "0"}):
            payload = json.dumps({"id":"raw-probe", "op":"equity_ohlcv", "symbol":"FPT",
                                  "start":"2026-10-16", "end":"2026-10-16", "source":"vci",
                                  "raw_prices":True}) + "\n"
            stdin = types.SimpleNamespace(buffer=io.BytesIO(payload.encode()))
            stdout, stderr = io.StringIO(), io.StringIO()
            with patch.object(worker.sys, "stdin", stdin), patch.object(worker.sys, "stdout", stdout), \
                    patch.object(worker.sys, "stderr", stderr):
                worker.main()
        frames = [json.loads(line) for line in stdout.getvalue().splitlines()]
        self.assertEqual(len(frames), 1)
        self.assertTrue(frames[0]["ok"])
        self.assertIsNone(received["floating"])
        self.assertEqual(received["source"], "vci")

    def test_trade_history_routes_vci_dates_to_documented_method(self):
        received = {}
        class FakeFrame:
            columns = ["trading_date", "total_value"]
            attrs = {"source": "vci", "route": "market.equity.trade_history"}
            def to_dict(self, orient):
                self.asserted_orient = orient
                return [{"trading_date": "2026-10-16", "total_value": 123456.0}]
        frame = FakeFrame()
        class FakeEquity:
            def trade_history(self, **kwargs):
                received.update(kwargs)
                return frame
        class FakeMarket:
            def equity(self, symbol):
                received["symbol"] = symbol
                return FakeEquity()
        module = types.SimpleNamespace(Market=FakeMarket, Fundamental=lambda: None, Reference=lambda: None)
        with patch.dict(sys.modules, {"vnstock": module}), patch.dict(worker.os.environ, {"VNPIPE_DISABLE_LIVE": "0"}):
            out = worker._fetch({"op":"equity_trade_history", "symbol":"FPT", "start":"2026-10-16",
                                 "end":"2026-10-16", "source":"vci"})
        self.assertEqual(out["count"], 1)
        self.assertEqual(out["rows"][0]["total_value"], 123456.0)
        self.assertEqual(received, {"symbol":"FPT", "start":"2026-10-16", "end":"2026-10-16", "source":"vci"})

    def test_default_ohlcv_does_not_override_floating(self):
        received = {}
        class FakeFrame:
            columns = ["time"]
            attrs = {}
            def to_dict(self, orient):
                return [{"time":"2026-10-16"}]
        class FakeEquity:
            def ohlcv(self, **kwargs):
                received.update(kwargs)
                return FakeFrame()
        class FakeMarket:
            def equity(self, symbol):
                return FakeEquity()
        module = types.SimpleNamespace(Market=FakeMarket, Fundamental=lambda: None, Reference=lambda: None)
        with patch.dict(sys.modules, {"vnstock": module}), patch.dict(worker.os.environ, {"VNPIPE_DISABLE_LIVE": "0"}):
            worker._fetch({"op":"equity_ohlcv", "symbol":"FPT", "start":"2026-10-16",
                           "end":"2026-10-16", "source":"vci"})
        self.assertNotIn("floating", received)

    def test_active_probe_is_never_unmetered(self):
        with self.assertRaisesRegex(ValueError, "metered"):
            worker.dispatch({"op":"probe", "active":True})

    def test_offline_env_blocks_direct_route(self):
        with patch.dict(worker.os.environ, {"VNPIPE_DISABLE_LIVE":"1"}):
            with self.assertRaises(PermissionError):
                worker._fetch({"op":"equity_list"})

    def test_fatal_error_classes_safely_framed(self):
        for name in ("EntitlementError", "RateLimitedError", "InputError", "ModuleNotFoundError"):
            failure = type(name, (Exception,), {})("no entitlement / module")
            inp = types.SimpleNamespace(buffer=io.BytesIO(b'{"id":"x","op":"equity_list"}\n'))
            out = io.StringIO()
            with patch.object(worker.sys, "stdin", inp), patch.object(worker.sys, "stdout", out), patch.object(worker, "_fetch", side_effect=failure):
                worker.main()
            payload = json.loads(out.getvalue())
            self.assertFalse(payload["ok"])
            self.assertEqual(payload["error"]["type"], name if name != "ModuleNotFoundError" else "AdapterError")

    def test_safe_numpy_pandas_like_values(self):
        class Missing:
            pass
        Missing.__name__ = "NAType"
        self.assertIsNone(worker._safe(Missing()))
        class Scalar:
            def item(self): return float("nan")
        self.assertIsNone(worker._safe(Scalar()))
        class Array:
            def tolist(self): return [Scalar(), 3]
        self.assertEqual(worker._safe(Array()), [None, 3])


if __name__ == "__main__":
    unittest.main()

class AdapterErrorCauseTests(unittest.TestCase):
    def test_safe_exception_class_survives_without_vendor_text_in_category(self):
        for name in ("AttributeError", "TypeError", "ConnectionError"):
            failure = type(name, (Exception,), {})("vendor private authentication data")
            inp = types.SimpleNamespace(buffer=io.BytesIO(
                b'{"id":"company-1","op":"company_info","symbol":"ABR"}\n'))
            out = io.StringIO()
            with patch.object(worker.sys, "stdin", inp), \
                 patch.object(worker.sys, "stdout", out), \
                 patch.object(worker, "_fetch", side_effect=failure):
                worker.main()
            parsed = json.loads(out.getvalue())
            self.assertFalse(parsed["ok"])
            self.assertEqual(parsed["error"]["type"], "AdapterError")
            self.assertEqual(parsed["error"]["cause"], name)
            self.assertNotIn("vendor private", parsed["error"]["cause"])

class ExtendedAdapterCauseTests(unittest.TestCase):
    def test_unknown_vendor_exception_class_is_retained_without_message(self):
        for name in ("VciLegacyProfileFailure", "ProviderUnlistedError"):
            failure = type(name, (Exception,), {})("secret=example")
            stdin = types.SimpleNamespace(buffer=io.BytesIO(
                b'{"id":"diag","op":"company_info","symbol":"BPW"}\n'))
            stdout = io.StringIO()
            with patch.object(worker.sys, "stdin", stdin), \
                 patch.object(worker.sys, "stdout", stdout), \
                 patch.object(worker, "_fetch", side_effect=failure):
                worker.main()
            result = json.loads(stdout.getvalue())
            self.assertEqual(result["error"]["type"], "AdapterError")
            self.assertEqual(result["error"]["cause"], name)
            self.assertNotIn("secret=example", result["error"]["cause"])

    def test_nonascii_exception_class_is_not_persisted(self):
        failure = type("Secret_日本語", (Exception,), {})("sensitive")
        stdin = types.SimpleNamespace(buffer=io.BytesIO(
            b'{"id":"diag","op":"company_info","symbol":"BPW"}\n'))
        stdout = io.StringIO()
        with patch.object(worker.sys, "stdin", stdin), \
             patch.object(worker.sys, "stdout", stdout), \
             patch.object(worker, "_fetch", side_effect=failure):
            worker.main()
        result = json.loads(stdout.getvalue())
        self.assertEqual(result["error"]["cause"], "UnknownAdapterError")

class VendorMetadataDiagnosticsTests(unittest.TestCase):
    def test_structured_provider_error_metadata_no_vendor_message(self):
        cls = type("ProviderError", (Exception,), {})
        err = cls("https://private.token/secret?key=x")
        err.code = "VNSTOCK_SOURCE_NOT_FOUND"
        err.kind = "provider"
        err.route = "reference.company.info"
        err.provider = "vci"
        err.status = 404
        err.retryable = False
        fake = types.SimpleNamespace(buffer=io.BytesIO(
            b'{"id":"one","op":"company_info","symbol":"BPW"}\n'))
        out = io.StringIO()
        with patch.object(worker.sys, "stdin", fake), \
             patch.object(worker.sys, "stdout", out), \
             patch.object(worker, "_fetch", side_effect=err):
            worker.main()
        result = json.loads(out.getvalue())
        self.assertEqual(result["error"]["type"], "AdapterError")
        self.assertEqual(result["error"]["cause"], "ProviderError")
        self.assertEqual(result["diagnostic"], {
            "code": "VNSTOCK_SOURCE_NOT_FOUND", "kind": "provider",
            "route": "reference.company.info", "provider": "vci",
            "http_status": 404, "retryable": False
        })
        self.assertEqual(result["error"]["message"], "adapter operation failed")
        self.assertNotIn("private.token", json.dumps(result))
        self.assertNotIn("private.token", json.dumps(result["diagnostic"]))

    def test_bad_vendor_metadata_is_omitted(self):
        cls=type("ProviderError",(Exception,),{})
        ex=cls("do not save this")
        ex.code="TOKEN_abc12345"
        ex.kind="password"
        ex.route="https://key:password@server/"
        ex.provider="anotherhost"
        ex.status=999
        ex.retryable="true"
        self.assertEqual(worker._safe_failure_diagnostic(ex), {})
