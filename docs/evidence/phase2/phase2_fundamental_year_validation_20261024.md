# Fundamental period year validation

The Go parser accepted annual `0000` and quarterly `0000-Q1` through `0000-Q4`. Go supports astronomical year zero; PostgreSQL `make_date`, used by migration 034, rejects it. This allowed an apparently valid frame to fail during its database commit instead of being rejected by the frame analyzer.

Both parser branches now reject year zero. Existing exact four-digit syntax bounds the upper year to 9999. Regression cases cover annual and quarterly zero rejection, year 0001 acceptance and year 9999 acceptance with exact period-end dates. Required Go tests/vet and Python checks are running; see the `*_fundamental_year_20261024.log` files for terminal results. No live provider request or source-data modification is involved.

Terminal required checks all passed: Go tests exit 0, Go vet exit 0, Python tests exit 0 (31 tests).
