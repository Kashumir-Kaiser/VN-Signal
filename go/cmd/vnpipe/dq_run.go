package main

import (
	"context"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"os"
	"time"

	"github.com/Kashumir-Kaiser/VN-Signal/go/internal/dq"
)

func runDQGate(args []string) error {
	f := flag.NewFlagSet("dq-run", flag.ContinueOnError)
	date := f.String("date", "", "verified trading session YYYY-MM-DD")
	if err := f.Parse(args); err != nil {
		return err
	}
	if len(f.Args()) != 0 {
		return errors.New("unexpected arguments")
	}
	if *date == "" {
		return errors.New("--date YYYY-MM-DD is required")
	}
	expected, err := time.Parse("2006-01-02", *date)
	if err != nil || expected.Format("2006-01-02") != *date {
		return errors.New("--date must be a valid YYYY-MM-DD date")
	}
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Minute)
	defer cancel()
	db, err := openPostgres(ctx, os.Getenv("DATABASE_URL"))
	if err != nil {
		return err
	}
	defer db.Close()
	var runID string
	if err = db.QueryRowContext(ctx, `INSERT INTO ops.pipeline_runs(run_id,idempotency_key,status,step)
		VALUES(gen_random_uuid(),'dq-run:'||$1||':'||gen_random_uuid()::text,'RUNNING','data_quality') RETURNING run_id::text`, *date).Scan(&runID); err != nil {
		return err
	}

	_, gateErr := dq.RunPostgresGate(ctx, db, runID, expected)
	if gateErr != nil && !errors.Is(gateErr, dq.ErrBlocked) {
		// The gate may fail before its transactional report update; preserve a
		// terminal audit state when the database still accepts the update.
		_, _ = db.ExecContext(ctx, `UPDATE ops.pipeline_runs SET status='FAILED',step='data_quality',completed_at=now(),error_type='DQ_SETUP',error_message=$2 WHERE run_id=$1 AND status='RUNNING'`, runID, gateErr.Error())
		return gateErr
	}
	var status string
	var persisted []byte
	if err = db.QueryRowContext(ctx, `SELECT status,report FROM ops.dq_gate_results WHERE run_id=$1`, runID).Scan(&status, &persisted); err != nil {
		_, _ = db.ExecContext(ctx, `UPDATE ops.pipeline_runs SET status='FAILED',step='data_quality',completed_at=now(),error_type='DQ_RESULT_MISSING',error_message=$2 WHERE run_id=$1 AND status='RUNNING'`, runID, err.Error())
		return fmt.Errorf("read durable DQ result: %w", err)
	}
	var decoded json.RawMessage
	if err = json.Unmarshal(persisted, &decoded); err != nil {
		return err
	}
	output, err := json.MarshalIndent(struct {
		RunID  string          `json:"run_id"`
		Status string          `json:"status"`
		Report json.RawMessage `json:"report"`
	}{runID, status, decoded}, "", "  ")
	if err != nil {
		return err
	}
	fmt.Println(string(output))
	if gateErr != nil {
		return fmt.Errorf("%w", gateErr)
	}
	if status != "PASSED" {
		return fmt.Errorf("DQ run ended in %s", status)
	}
	return nil
}
