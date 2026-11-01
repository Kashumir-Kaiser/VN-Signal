import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


class Phase2RunnerWiringTests(unittest.TestCase):
    def test_native_psql_stderr_is_captured_without_suppressing_exit_checks(self):
        runner = (ROOT / "ops" / "phase2_build.ps1").read_text(encoding="utf-8")
        invocation = runner.index("$previousErrorActionPreference = $ErrorActionPreference")
        continue_preference = runner.index("$ErrorActionPreference = 'Continue'", invocation)
        restore_preference = runner.index("$ErrorActionPreference = $previousErrorActionPreference", continue_preference)
        exit_check = runner.index("$exitCode = $LASTEXITCODE", restore_preference)
        failure_check = runner.index("if ($exitCode -ne 0)", exit_check)
        self.assertLess(invocation, continue_preference)
        self.assertLess(continue_preference, restore_preference)
        self.assertLess(restore_preference, exit_check)
        self.assertLess(exit_check, failure_check)

    def test_long_psql_output_is_logged_without_unbounded_memory_capture(self):
        runner = (ROOT / "ops" / "phase2_build.ps1").read_text(encoding="utf-8")
        self.assertIn("[string]$OutputLogPath", runner)
        self.assertIn("[System.Collections.Generic.Queue[string]]::new()", runner)
        self.assertIn("[IO.StreamWriter]::new($OutputLogPath, $true", runner)
        self.assertIn("$streamWriter.WriteLine($line)", runner)
        self.assertIn("if ($recentOutput.Count -ge 80)", runner)
        self.assertNotIn("[System.Collections.Generic.List[string]]::new()", runner)
        self.assertIn("-OutputLogPath $runLogPath", runner)

    def test_multiline_sql_uses_a_file_for_windows_native_arguments(self):
        runner = (ROOT / "ops" / "phase2_build.ps1").read_text(encoding="utf-8")
        file_route = runner.index("$Sql.Contains(\"`n\")")
        temp_file_write = runner.index("[IO.File]::WriteAllText($scriptPath, $Sql")
        self.assertLess(file_route, temp_file_write)

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

    def test_label_build_preflights_target_database_and_all_first_date_seeds(self):
        runner = (ROOT / "ops" / "phase2_build.ps1").read_text(encoding="utf-8")
        self.assertIn("[string]$ExpectedDatabaseName = 'vnsignal_phase2_report_20261019'", runner)
        self.assertIn("AND current_database()='$ExpectedDatabaseName'", runner)
        self.assertIn("SELECT v_hash,symbol_id,min(trade_date)", runner)
        self.assertIn("AND position('SELECT v_hash,symbol_id,min(trade_date)' IN", runner)
        self.assertIn("=2*length('SELECT v_hash,s.symbol_id,f.first_date')", runner)
        self.assertIn("DROP TABLE IF EXISTS pg_temp.phase2_weight_values_102;", runner)
        self.assertIn("to_regprocedure('feat.refresh_phase2_execution_weights(date,date,date,bigint[])') IS NOT NULL", runner)
        self.assertIn("pg_get_functiondef('feat.refresh_phase2_execution_weights(date,date,date,bigint[])'::regprocedure)", runner)
        self.assertIn("phase2_weight_unique_sessions_106", runner)
        self.assertIn("phase2_weight_vndirect_payload_rows_108", runner)
        self.assertIn("phase2_weight_payload_rows_selected_109", runner)

    def test_label_rebuild_blocks_downstream_target_invalidation(self):
        runner = (ROOT / "ops" / "phase2_build.ps1").read_text(encoding="utf-8")
        preflight = runner.index("$downstreamTargetDate = Invoke-Phase2Psql -Scalar -Sql")
        stage_loop = runner.index("foreach ($stageName in $stages)")
        self.assertIn("if ($stages -contains 'labels')", runner[:stage_loop])
        self.assertIn("WHERE signal_date>DATE '$($rangeToDate.ToString('yyyy-MM-dd'))'", runner)
        self.assertIn("would invalidate later derived targets", runner)
        self.assertLess(preflight, stage_loop)

    def test_downstream_invalidation_and_windowed_limit_hash_are_present(self):
        derived = (ROOT / "sql" / "migrations" / "061_phase2_label_derived_targets.sql").read_text(encoding="utf-8")
        execution = (ROOT / "sql" / "migrations" / "063_phase2_label_execution_weights.sql").read_text(encoding="utf-8")
        self.assertIn("SET invalidated_at=clock_timestamp()", derived)
        self.assertIn("WHERE date_to>=v_first_signal", derived)
        self.assertIn("p.trade_date BETWEEN w.entry_date AND w.exit_date", execution)

    def test_cache_scaling_warms_before_staged_fixed_repetitions_and_assertion(self):
        runner = (ROOT / "ops" / "phase2_build.ps1").read_text(encoding="utf-8")
        warmups = [runner.index(f"SELECT * FROM feat.probe_phase2_adjustment_cache({size});")
                   for size in (15, 30, 60)]
        adaptive_warmup = runner.index("DO `$phase2_cache_warmup`$")
        warmup_samples = runner.index("CREATE TEMP TABLE phase2_cache_warmup_samples(")
        staged = runner.index("FROM generate_series(1,90) AS samples(sample_no)")
        staged_exec = runner.index("\\gexec", staged)
        validation = runner.index("SELECT feat.validate_phase2_cache_samples();", staged_exec)
        assertion = runner.index("SELECT feat.assert_phase2_adjustment_cache_scaling();", validation)
        self.assertEqual(runner.count("SELECT * FROM feat.measure_phase2_cache_scaling();"), 0)
        self.assertTrue(all(position < staged for position in warmups))
        self.assertLess(max(warmups), warmup_samples)
        self.assertLess(warmup_samples, adaptive_warmup)
        self.assertLess(adaptive_warmup, staged)
        self.assertIn("FOR v_block IN 1..5 LOOP", runner)
        self.assertIn("prior_block.samples=10 AND current_block.samples=10", runner)
        self.assertIn("abs(current_block.mean_ms-prior_block.mean_ms)<=prior_block.mean_ms*0.20", runner)
        self.assertIn("cache warmup did not stabilize after five balanced blocks", runner)
        self.assertIn("pg_stat_checkpointer", runner)
        self.assertIn("pg_stat_bgwriter", runner)
        self.assertIn("means_ms=[15:% 30:% 60:%]", runner)
        self.assertIn("checkpoint_delta=[timed:% requested:% buffers:% write_ms:% sync_ms:%]", runner)
        self.assertIn("CACHE sample {0}/90", runner)
        self.assertIn("$streamWriter.Flush()", runner)
        self.assertIn("CREATE TEMP TABLE phase2_cache_samples(", runner)
        self.assertIn("SELECT * FROM feat.probe_phase2_adjustment_cache(%s)", runner)
        self.assertIn("FROM measured m CROSS JOIN saved s", runner)
        self.assertEqual(runner.count("generate_series(1,90) AS samples(sample_no)"), 1)
        self.assertLess(staged, staged_exec)
        self.assertLess(staged_exec, validation)
        self.assertLess(validation, assertion)
        migration = (ROOT / "sql" / "migrations" / "074_phase2_reproducible_cache_probe.sql").read_text(encoding="utf-8")
        self.assertIn("FOR cycle IN 1..10 LOOP", migration)
        self.assertIn("FOR i IN 1..9 LOOP", migration)
        self.assertIn("ceil(avg(duration_ms))", migration)
        self.assertIn("stddev_pop(mean_ms)/avg(mean_ms)>0.20", migration)

    def test_builder_supports_shorter_calendar_chunks(self):
        runner = (ROOT / "ops" / "phase2_build.ps1").read_text(encoding="utf-8")
        self.assertIn("[int]$ChunkMonths = 0", runner)
        self.assertIn("$cursor.AddMonths($ChunkMonths).AddDays(-1)", runner)

    def test_label_runner_rejects_chunks_over_the_sql_session_limit(self):
        runner = (ROOT / "ops" / "phase2_build.ps1").read_text(encoding="utf-8")
        self.assertIn("$stages -contains 'labels'", runner)
        self.assertIn("-not $CalendarAlignedChunks -and $ChunkMonths -gt 12", runner)
        self.assertIn("$ChunkYears -gt 1", runner)
        self.assertIn("label chunks are limited to 300 trading sessions", runner)

    def test_calendar_month_mode_ends_at_calendar_month_boundary(self):
        runner = (ROOT / "ops" / "phase2_build.ps1").read_text(encoding="utf-8")
        self.assertIn("[switch]$CalendarAlignedChunks", runner)
        self.assertIn("if ($CalendarAlignedChunks -and $ChunkMonths -ne 1)", runner)
        self.assertIn(
            "$chunkEnd = [DateTime]::new($cursor.Year, $cursor.Month, 1).AddMonths(1).AddDays(-1)",
            runner,
        )
        self.assertIn("('Calendar-aligned monthly chunks: ' + $CalendarAlignedChunks)", runner)

    def test_each_runner_invocation_keeps_a_distinct_success_and_failure_log(self):
        runner = (ROOT / "ops" / "phase2_build.ps1").read_text(encoding="utf-8")
        self.assertIn("$runInstance = '{0}-{1}' -f", runner)
        self.assertIn("'phase2_build_' + $BuildId + '_' + $runInstance + '.log'", runner)
        self.assertIn("'phase2_build_' + $BuildId + '.failed.' + $runInstance + '.log'", runner)

    def test_e5_target_attempts_are_linked_to_the_actual_label_build(self):
        migration = (ROOT / "sql" / "migrations" / "090_phase2_label_target_build_association.sql").read_text(encoding="utf-8")
        verifier = (ROOT / "docs" / "evidence" / "phase2" / "phase2_e5_repeatability_verify.sql").read_text(encoding="utf-8")
        runner = (ROOT / "ops" / "phase2_build.ps1").read_text(encoding="utf-8")
        harness = (ROOT / "tests" / "sql" / "test_migration.sh").read_text(encoding="utf-8")
        self.assertIn("ADD COLUMN IF NOT EXISTS label_build_id text", migration)
        self.assertIn("NULLIF(current_setting('vnpipe.phase2_label_build_id',true),'')", migration)
        self.assertNotIn("UPDATE ops.phase2_label_target_chunk_runs", migration)
        self.assertIn("label_build_id=v_a", verifier)
        self.assertIn("label_build_id=v_b", verifier)
        self.assertNotIn("ORDER BY x.run_id DESC LIMIT 2", verifier)
        self.assertIn("SET LOCAL vnpipe.phase2_label_build_id=$buildLiteral;", runner)
        self.assertIn("column_name='label_build_id'", runner)
        self.assertIn("tests/sql/phase2_label_build_link_assertions.sql", harness)

    def test_cache_projection_uses_actual_source_rows_and_preserves_the_guards(self):
        migration = (ROOT / "sql" / "migrations" / "091_phase2_cache_row_weighted_scaling.sql").read_text(encoding="utf-8")
        runner = (ROOT / "ops" / "phase2_build.ps1").read_text(encoding="utf-8")
        self.assertIn("ln(rows_30::double precision/rows_15::double precision)", migration)
        self.assertIn("v_expected_batch_rows", migration)
        self.assertIn("core.bars_daily_sources", migration)
        self.assertIn("IF v_exponent>1.3 THEN", migration)
        self.assertIn("v_budget_minutes:=COALESCE(NULLIF(current_setting('vnpipe.phase2_cache_time_budget_minutes',true),'')::double precision,40.0)", migration)
        self.assertIn("feat.phase2_cache_sample_batch_rows_ms(integer,bigint,double precision,integer,bigint,double precision)", runner)

    def test_failure_keeps_full_evidence_and_bounds_terminal_error(self):
        runner = (ROOT / "ops" / "phase2_build.ps1").read_text(encoding="utf-8")
        self.assertIn("$fullMessage = [string]$_.Exception.Message", runner)
        self.assertIn("$failureLogPath,", runner)
        self.assertIn("$message.Length -gt 4000", runner)
        self.assertIn("throw \"Phase 2 chunk failed: $failedChunkInfo. Full evidence: $failureLogPath. $message\"", runner)

    def test_v3_compute_batch_size_is_separate_from_cache_batch_size(self):
        runner = (ROOT / "ops" / "phase2_build.ps1").read_text(encoding="utf-8")
        self.assertIn("[int]$V3ComputeBatchSize = 5", runner)
        self.assertIn("SET LOCAL vnpipe.phase2_symbol_batch_size='$SymbolBatchSize';", runner)
        self.assertIn("SET LOCAL vnpipe.phase2_v3_compute_batch_size='$V3ComputeBatchSize';", runner)

    def test_execution_weight_audit_can_rerun_successful_quarters_after_data_changes(self):
        runner = (ROOT / "docs" / "evidence" / "phase2" / "run_phase2_execution_weight_setbased_audit_20261030.ps1").read_text(encoding="utf-8")
        self.assertIn("[switch]$RerunSuccessful", runner)
        self.assertIn("if (-not $RerunSuccessful)", runner)
        rerun_branch = runner.index('else {\n        Write-Host "RERUN requested')
        self.assertLess(runner.index("if (-not $RerunSuccessful)"), rerun_branch)
        self.assertLess(rerun_branch, runner.index("if ($successfulStatus)", rerun_branch))

    def test_bsc_limit_fallback_is_label_only_and_fixture_wired(self):
        migration = (ROOT / "sql" / "migrations" / "106_phase2_bsc_archived_price_limits.sql").read_text(encoding="utf-8")
        fixture = (ROOT / "tests" / "sql" / "phase2_bsc_price_limits_assertions.sql").read_text(encoding="utf-8")
        harness = (ROOT / "tests" / "sql" / "test_migration.sh").read_text(encoding="utf-8")
        self.assertIn("core.materialize_bsc_daily_price_limits", migration)
        self.assertIn("core.phase2_execution_limit_evidence", migration)
        self.assertIn("BSC fallback is not admitted when any VNDIRECT limit observation exists", migration)
        self.assertIn("p.source IN (''vndirect'',''bsc'')", migration)
        self.assertIn("feat.phase2_exact_execution_weight", fixture)
        self.assertIn("feat.refresh_phase2_execution_weights", fixture)
        self.assertIn("did not invalidate the label input hash", fixture)
        self.assertIn("phase2_bsc_price_limits_assertions.sql", harness)

    def test_label_manifest_uses_revision_watermarks_for_wide_dependencies(self):
        migration = (ROOT / "sql" / "migrations" / "107_phase2_label_dependency_watermarks.sql").read_text(encoding="utf-8")
        payload_migration = (ROOT / "sql" / "migrations" / "108_phase2_execution_weight_payload_rows.sql").read_text(encoding="utf-8")
        selective_payload_migration = (ROOT / "sql" / "migrations" / "109_phase2_selective_execution_payload_rows.sql").read_text(encoding="utf-8")
        fixture = (ROOT / "tests" / "sql" / "phase2_label_dependency_watermark_assertions.sql").read_text(encoding="utf-8")
        harness = (ROOT / "tests" / "sql" / "test_migration.sh").read_text(encoding="utf-8")
        self.assertIn("ON feat.features_daily", migration)
        self.assertIn("ON core.daily_price_limit_observations", migration)
        self.assertIn("ON raw.landings", migration)
        self.assertIn("phase2_label_dependency_watermark()", migration)
        self.assertIn("phase2_label_input_hash_tx_cache_107", migration)
        self.assertIn("DROP TRIGGER IF EXISTS phase2_label_dependency_labels_daily", payload_migration)
        self.assertIn("output hash", payload_migration)
        self.assertIn("phase2_weight_payload_rows_selected_109", selective_payload_migration)
        self.assertIn("array_agg(source_row ORDER BY source_row)", selective_payload_migration)
        self.assertIn("=ANY(needed.source_rows)", selective_payload_migration)
        self.assertIn("raw-label output mutation invalidated source-input hash cache", fixture)
        self.assertIn("did not invalidate the label input hash", fixture)
        self.assertIn("phase2_label_dependency_watermark_assertions.sql", harness)


if __name__ == "__main__":
    unittest.main()
