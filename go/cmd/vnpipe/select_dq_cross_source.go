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

func parseDQCrossSourceArgs(args []string) (time.Time, error) {
	f := flag.NewFlagSet("select-dq-cross-source", flag.ContinueOnError)
	date := f.String("date", "", "Tier A and bar date YYYY-MM-DD")
	if err := f.Parse(args); err != nil {
		return time.Time{}, err
	}
	if len(f.Args()) != 0 || *date == "" {
		return time.Time{}, errors.New("select-dq-cross-source requires --date YYYY-MM-DD")
	}
	day, err := time.Parse("2006-01-02", *date)
	if err != nil || day.Format("2006-01-02") != *date {
		return time.Time{}, errors.New("--date must be a valid YYYY-MM-DD date")
	}
	return day, nil
}

func runSelectDQCrossSource(args []string) error {
	day, err := parseDQCrossSourceArgs(args)
	if err != nil {
		return err
	}
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Minute)
	defer cancel()
	db, err := openPostgres(ctx, os.Getenv("DATABASE_URL"))
	if err != nil {
		return err
	}
	defer db.Close()
	result, err := dq.SelectCrossSourceFromPostgres(ctx, db, day)
	if err != nil {
		return err
	}
	encoded, err := json.MarshalIndent(result, "", "  ")
	if err != nil {
		return err
	}
	fmt.Println(string(encoded))
	return nil
}
