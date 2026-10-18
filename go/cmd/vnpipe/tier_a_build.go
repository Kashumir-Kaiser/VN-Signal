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

func runTierABuild(args []string) error {
	f := flag.NewFlagSet("tier-a-build", flag.ContinueOnError)
	date := f.String("date", "", "listing and membership date YYYY-MM-DD")
	if err := f.Parse(args); err != nil {
		return err
	}
	if len(f.Args()) != 0 || *date == "" {
		return errors.New("tier-a-build requires --date YYYY-MM-DD")
	}
	day, err := time.Parse("2006-01-02", *date)
	if err != nil || day.Format("2006-01-02") != *date {
		return errors.New("--date must be a valid YYYY-MM-DD date")
	}
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Minute)
	defer cancel()
	db, err := openPostgres(ctx, os.Getenv("DATABASE_URL"))
	if err != nil {
		return err
	}
	defer db.Close()
	result, err := dq.BuildTierAFromPostgres(ctx, db, day)
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
