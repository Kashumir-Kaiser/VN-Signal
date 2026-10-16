"""Pure offline unit tests: never import vnstock or make network calls."""
import importlib.util
import math
from pathlib import Path
import unittest

p = Path(__file__).resolve().parents[1] / "py" / "vnstock_worker.py"
spec = importlib.util.spec_from_file_location("vnstock_worker", p)
worker = importlib.util.module_from_spec(spec)
spec.loader.exec_module(worker)


class WorkerTests(unittest.TestCase):
    def test_health(self):
        self.assertEqual(worker.dispatch({"op": "health"})["protocol"], 1)

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


if __name__ == "__main__":
    unittest.main()
