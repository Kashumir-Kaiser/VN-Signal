// vnpipe is the offline-first single-user VN-Signal pipeline controller.
package main

import (
	"context"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"os"
	"path/filepath"
	"time"

	"github.com/Kashumir-Kaiser/VN-Signal/go/internal/quota"
	"github.com/Kashumir-Kaiser/VN-Signal/go/internal/worker"
)

func usage() {
	fmt.Println(`vnpipe (bootstrap) - VN-Signal
Usage:
  vnpipe probe [--active] [--out DIR]  Local vnstock status/usage and optional live route probe
  vnpipe budget --daily N --monthly N --days N --rpm N
  vnpipe version
Live ingestion, training, recommendation and the desktop app are NOT implemented.`)
}

func main() {
	if err := run(os.Args[1:]); err != nil {
		fmt.Fprintln(os.Stderr, "vnpipe:", err)
		os.Exit(1)
	}
}
func run(args []string) error {
	if len(args) == 0 {
		usage()
		return nil
	}
	switch args[0] {
	case "-h", "--help", "help":
		usage()
		return nil
	case "version":
		fmt.Println("vnpipe bootstrap 0.1.0; no model/recommendations")
		return nil
	case "probe":
		f := flag.NewFlagSet("probe", flag.ContinueOnError)
		active := f.Bool("active", false, "opt in to live vnstock route calls")
		out := f.String("out", filepath.Join("..", "docs", "probe"), "report directory")
		if err := f.Parse(args[1:]); err != nil {
			return err
		}
		if len(f.Args()) > 0 {
			return errors.New("unexpected arguments")
		}
		ctx, cancel := context.WithTimeout(context.Background(), 3*time.Minute)
		defer cancel()
		result, err := worker.Invoke(ctx, worker.Python(), worker.ScriptPath(), map[string]any{
			"id": "local-probe", "op": "probe", "active": *active,
		})
		if err != nil {
			return err
		}
		if !result.OK {
			return fmt.Errorf("worker probe error: %+v", result.Error)
		}
		// A probe may succeed while some routes are unavailable; record that honestly.
		if err = os.MkdirAll(*out, 0700); err != nil {
			return err
		}
		today := time.Now().Format("2006-01-02")
		name := filepath.Join(*out, today+".json")
		var data any
		if err = json.Unmarshal(result.Data, &data); err != nil {
			return err
		}
		pretty, err := json.MarshalIndent(data, "", "  ")
		if err != nil {
			return err
		}
		// reports are untracked: potential account/device diagnostics never go to GitHub.
		if err = os.WriteFile(name, append(pretty, '\n'), 0600); err != nil {
			return err
		}
		fmt.Printf("Probe report: %s (active=%v). Review data; this does NOT certify entitlement.\n", name, *active)
		return nil
	case "budget":
		f := flag.NewFlagSet("budget", flag.ContinueOnError)
		daily := f.Int("daily", -1, "absolute daily calls remaining")
		monthly := f.Int("monthly", -1, "absolute monthly calls remaining")
		days := f.Int("days", -1, "trading days remaining in month")
		rpm := f.Int("rpm", 0, "verified tier requests/minute")
		if err := f.Parse(args[1:]); err != nil {
			return err
		}
		if len(f.Args()) > 0 {
			return errors.New("unexpected arguments")
		}
		b, err := quota.Budget(*daily, *monthly, *days)
		if err != nil {
			return err
		}
		if _, err = quota.NewPacer(*rpm, b); err != nil {
			return err
		}
		fmt.Printf("Maximum planned calls today: %d; pacing: 85%% of %d verified req/min\n", b, *rpm)
		return nil
	default:
		return fmt.Errorf("unknown command %q", args[0])
	}
}
