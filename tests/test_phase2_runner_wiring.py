import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


class Phase2RunnerWiringTests(unittest.TestCase):
    def test_label_chunks_build_and_hash_derived_targets(self):
        runner = (ROOT / "ops" / "phase2_build.ps1").read_text(encoding="utf-8")
        self.assertIn("ops.phase2_label_target_chunk_input_hash($fromLiteral,$toLiteral)", runner)
        self.assertIn("PERFORM feat.build_phase2_label_targets_v3($fromLiteral,$toLiteral);", runner)
        self.assertIn("ops.phase2_label_targets_chunk_hash($fromLiteral,$toLiteral)", runner)
        self.assertIn(")=v_current_output_hash", runner)
        self.assertIn(
            "IF v_existing_status='done' AND v_existing_hash=v_input_hash AND NOT $forceLiteral THEN\n"
            "        v_current_output_hash := $targetOutputExpr;",
            runner,
        )

    def test_downstream_invalidation_and_windowed_limit_hash_are_present(self):
        derived = (ROOT / "sql" / "migrations" / "061_phase2_label_derived_targets.sql").read_text(encoding="utf-8")
        execution = (ROOT / "sql" / "migrations" / "063_phase2_label_execution_weights.sql").read_text(encoding="utf-8")
        self.assertIn("SET invalidated_at=clock_timestamp()", derived)
        self.assertIn("WHERE date_to>=v_first_signal", derived)
        self.assertIn("p.trade_date BETWEEN w.entry_date AND w.exit_date", execution)

    def test_cache_scaling_uses_fixed_repetitions_before_assertion(self):
        runner = (ROOT / "ops" / "phase2_build.ps1").read_text(encoding="utf-8")
        self.assertEqual(runner.count("SELECT * FROM feat.measure_phase2_cache_scaling();"), 1)
        self.assertLess(runner.index("SELECT * FROM feat.measure_phase2_cache_scaling();"),
                        runner.index("SELECT feat.assert_phase2_adjustment_cache_scaling();"))
        migration = (ROOT / "sql" / "migrations" / "074_phase2_reproducible_cache_probe.sql").read_text(encoding="utf-8")
        self.assertIn("FOR cycle IN 1..10 LOOP", migration)
        self.assertIn("FOR i IN 1..9 LOOP", migration)
        self.assertIn("ceil(avg(duration_ms))", migration)
        self.assertIn("stddev_pop(mean_ms)/avg(mean_ms)>0.20", migration)

    def test_builder_supports_shorter_calendar_chunks(self):
        runner = (ROOT / "ops" / "phase2_build.ps1").read_text(encoding="utf-8")
        self.assertIn("[int]$ChunkMonths = 0", runner)
        self.assertIn("$cursor.AddMonths($ChunkMonths).AddDays(-1)", runner)


if __name__ == "__main__":
    unittest.main()
