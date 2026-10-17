"""Small, single-purpose vnstock v5 JSONL adapter. No financial logic here."""
from __future__ import annotations

import contextlib
import datetime as dt
import json
import math
import os
import re
from pathlib import Path
import subprocess
import sys
from typing import Any


def _safe(value: Any) -> Any:
    """Convert dataframe values into RFC 8259 compliant JSON."""
    if value is None or type(value).__name__ in ("NAType", "NaTType"):
        return None
    if isinstance(value, (bytes, bytearray)):
        return value.hex()
    if hasattr(value, "tolist") and not hasattr(value, "item"):
        return _safe(value.tolist())
    if value is None:
        return None
    if hasattr(value, "to_pydatetime"):
        value = value.to_pydatetime()
    if hasattr(value, "isoformat"):
        return value.isoformat()
    if hasattr(value, "item"):
        try:
            return _safe(value.item())
        except (ValueError, TypeError):
            pass
    if isinstance(value, float) and not math.isfinite(value):
        return None
    if isinstance(value, (int, float, bool, str)):
        return value
    if isinstance(value, dict):
        return {str(k): _safe(v) for k, v in value.items()}
    if isinstance(value, (tuple, list)):
        return [_safe(v) for v in value]
    if isinstance(value, dt.date):
        return value.isoformat()
    return str(value)


def _frame(df: Any) -> dict[str, Any]:
    if not hasattr(df, "to_dict") or not hasattr(df, "columns"):
        raise TypeError("Expected pandas DataFrame from vnstock")
    rows = df.to_dict(orient="records")
    return {
        "columns": [str(c) for c in df.columns],
        "count": len(rows),
        "rows": _safe(rows),
        "attributes": _safe({k: v for k, v in df.attrs.items()
                             if k in ("source", "route") or k.startswith("tier_cap_")}),
    }


def _cli(op: str) -> Any:
    # Local CLI returns structured JSON on v5; never print stdout/stderr containing secrets.
    executable = Path(sys.executable).with_name("vnstock.exe" if os.name == "nt" else "vnstock")
    cli = str(executable) if executable.is_file() else "vnstock"
    try:
        # --json is a global CLI option and must precede the subcommand.
        p = subprocess.run([cli, "--json", op], capture_output=True,
                           text=True, timeout=30, check=False)
    except (OSError, subprocess.TimeoutExpired) as ex:
        return {"available": False, "error_type": type(ex).__name__}
    if p.returncode:
        return {"available": False, "returncode": p.returncode}
    try:
        return json.loads(p.stdout)
    except ValueError:
        return {"available": False, "error_type": "InvalidJSON"}


def _symbol(job: dict[str, Any]) -> str:
    val = job.get("symbol", "")
    if not isinstance(val, str) or not 1 <= len(val) <= 12 or not val.isalnum():
        raise ValueError("symbol must be a 1-12 character alphanumeric identifier")
    return val.upper()


def _fetch(job: dict[str, Any]) -> dict[str, Any]:
    if os.getenv("VNPIPE_DISABLE_LIVE") == "1":
        raise PermissionError("market calls disabled in offline/hosted CI")
    from vnstock import Fundamental, Market, Reference  # noqa: dynamically installed
    op = job["op"]
    source = job.get("source")
    allowed_sources = {
        "equity_list": {"vci"}, "company_info": {"vci"}, "market_calendar": set(),
        "equity_ohlcv": {"vci", "kbs", "vnd", "mas", "asean"},
        "index_ohlcv": {"vci", "kbs"},
        "income_statement": {"vci", "kbs", "mas"},
        "balance_sheet": {"vci", "kbs", "mas"},
        "cash_flow": {"vci", "kbs", "mas"},
    }
    if source is not None and source not in allowed_sources.get(op, set()):
        raise ValueError("source not allowed for route")
    opts = {"source": source} if source is not None else {}
    if op == "equity_list":
        return _frame(Reference().equity.list_by_exchange())
    if op == "market_calendar":
        return _frame(Reference().events.market())
    if op == "company_info":
        return _frame(Reference().company(_symbol(job)).info(source="vci"))
    if op in ("equity_ohlcv", "index_ohlcv"):
        val = _symbol(job)
        start, end = job.get("start"), job.get("end")
        if not isinstance(start, str) or not isinstance(end, str):
            raise ValueError("start and end ISO dates are required")
        begin = dt.date.fromisoformat(start)
        finish = dt.date.fromisoformat(end)
        if begin > finish:
            raise ValueError("start after end")
        asset = (Market().equity(val) if op == "equity_ohlcv"
                 else Market().index(val))
        return _frame(asset.ohlcv(start=start, end=end, interval="1D", **opts))
    if op in ("income_statement", "balance_sheet", "cash_flow"):
        val = _symbol(job)
        period = job.get("period", "quarter")
        if period not in ("quarter", "year"):
            raise ValueError("invalid statement period")
        return _frame(getattr(Fundamental().equity(val), op)(period=period, **opts))
    raise ValueError("operation not allowed")


def dispatch(job: dict[str, Any]) -> dict[str, Any]:
    if not isinstance(job, dict):
        raise ValueError("job must be an object")
    op = job.get("op")
    if op == "health":
        return {"protocol": 1, "python": sys.version.split()[0], "worker": "vnstock-v5"}
    if op in ("status", "usage"):
        return {"operation": op, "data": _cli(op)}
    if op == "probe":
        active = job.get("active", False) is True
        if active:
            raise ValueError("active probe must be performed by Go's metered live gateway")
        result: dict[str, Any] = {
            "at": dt.datetime.now(dt.timezone.utc).isoformat(),
            "active": active,
            "status": _cli("status"),
            "usage": _cli("usage"),
            "routes": {},
        }
        if active:
            # Explicit single small call per route, no requests in CI/offline mode.
            from zoneinfo import ZoneInfo
            today = dt.datetime.now(ZoneInfo("Asia/Ho_Chi_Minh")).date()
            recent = "2016-01-01"  # Single call per bar route; assess actual accessible depth.
            for route, params in (
                ("equity_list", {}),
                ("equity_ohlcv", {"symbol": "FPT", "start": recent, "end": today.isoformat()}),
                ("index_ohlcv", {"symbol": "VNINDEX", "start": recent, "end": today.isoformat()}),
                ("income_statement", {"symbol": "FPT", "period": "quarter"}),
                ("balance_sheet", {"symbol": "FPT", "period": "quarter"}),
                ("cash_flow", {"symbol": "FPT", "period": "quarter"}),
                ("market_calendar", {}),
            ):
                try:
                    data = _fetch({"op": route, **params})
                    dates = [row.get("time", row.get("date")) for row in data["rows"]]
                    dates = [str(x) for x in dates if x is not None]
                    result["routes"][route] = {
                        "available": bool(data["count"]), "count": data["count"],
                        "first_observed_date": min(dates) if dates else None,
                        "last_observed_date": max(dates) if dates else None,
                        "columns": data["columns"], "attributes": data["attributes"]}
                except Exception as ex:
                    result["routes"][route] = {
                        "available": False, "error_type": type(ex).__name__}
        return result
    allowed = {"equity_list", "company_info", "market_calendar", "equity_ohlcv", "index_ohlcv",
               "income_statement", "balance_sheet", "cash_flow"}
    if op not in allowed:
        raise ValueError("unknown operation")
    return _fetch(job)


# Standard v5 VnstockError attributes give a stable source-failure code
# without leaking exception strings, URLs, API keys, HTML bodies or tracebacks.
def _safe_failure_diagnostic(ex: Exception) -> dict[str, Any]:
    info: dict[str, Any] = {}
    code = getattr(ex, "code", None)
    if isinstance(code, str) and re.fullmatch(r"VNSTOCK_[A-Z0-9_]{1,72}", code):
        info["code"] = code
    kind = getattr(ex, "kind", None)
    if isinstance(kind, str) and kind in {
        "input", "auth", "entitlement", "network", "provider",
        "schema", "unsupported", "internal"
    }:
        info["kind"] = kind
    route = getattr(ex, "route", None)
    if isinstance(route, str) and re.fullmatch(r"[a-z][a-z0-9_.]{0,99}", route):
        info["route"] = route
    provider = getattr(ex, "provider", None)
    if isinstance(provider, str) and provider in {"vci", "kbs"}:
        info["provider"] = provider
    status = getattr(ex, "status", None)
    if type(status) is int and 100 <= status <= 599:
        info["http_status"] = status
    retryable = getattr(ex, "retryable", None)
    if type(retryable) is bool:
        info["retryable"] = retryable
    return info


MAX_INPUT_LINE = 65536


def main() -> None:
    # Each stdin record has an absolute size bound. Consume the remainder of an
    # oversized record before attempting the next, without buffering it in RAM.
    stdin = sys.stdin.buffer
    stdout = sys.stdout
    while True:
        line = stdin.readline(MAX_INPUT_LINE + 1)
        if not line:
            return
        oversized = len(line) > MAX_INPUT_LINE
        if oversized and not line.endswith(b"\n"):
            while True:
                chunk = stdin.readline(MAX_INPUT_LINE + 1)
                if not chunk or chunk.endswith(b"\n"):
                    break
        job = None
        try:
            if oversized:
                raise ValueError("job too large")
            job = json.loads(line)
            if not isinstance(job, dict):
                raise ValueError("job must be an object")
            if not isinstance(job.get("id"), str) or not job["id"]:
                raise ValueError("job id must be a nonempty string")
            # Redirect all library prints (including import-time warnings) away
            # from the JSONL protocol, preserving stdout only for frames.
            with contextlib.redirect_stdout(sys.stderr):
                data = dispatch(job)
            output = {"id": job["id"], "ok": True, "data": data}
        except SystemExit:
            # Third-party adapters must not terminate the supervised process
            # before it can return the required JSONL frame. Keep the exit code
            # and message private; the caller needs only a stable safe label.
            output = {"id": job.get("id") if isinstance(job, dict) else None,
                      "ok": False, "error": {
                          "type": "WorkerSystemExit",
                          "message": "adapter operation attempted to exit the worker"}}
        except Exception as ex:
            cls = type(ex).__name__
            if cls not in ("EntitlementError", "RateLimitedError", "InputError", "ValueError"):
                cls = "AdapterError"
            # Keep a stable, non-sensitive exception category in the wire
            # response. Do not copy vendor error text to probe reports.
            # Only the Python exception *class*, never its value/message,
            # is persisted by Go. This reveals previously hidden vendor
            # exception categories without storing account identifiers,
            # URLs, private arguments or tracebacks.
            cause = type(ex).__name__
            if not re.fullmatch(r"[A-Za-z][A-Za-z0-9_]{0,79}", cause):
                cause = "UnknownAdapterError"
            output = {"id": job.get("id") if isinstance(job, dict) else None,
                      "ok": False, "error": {
                          "type": cls,
                          "message": str(ex)[:280],
                          "cause": cause,
                      }}
            diagnostic = _safe_failure_diagnostic(ex)
            if diagnostic:
                output["diagnostic"] = diagnostic
        try:
                        # ASCII escaping keeps JSONL writes independent of Windows' active
            # console code page while preserving the decoded Unicode values.
            stdout.write(json.dumps(_safe(output), ensure_ascii=True, allow_nan=False) + "\n")
            stdout.flush()
        except (BrokenPipeError, OSError):
            # Go killed the subprocess / closed the transport. Never emit a
            # secondary traceback to stdout or keep ingesting jobs.
            return


if __name__ == "__main__":
    main()
