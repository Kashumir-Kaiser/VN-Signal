// Package migrate applies numbered PostgreSQL scripts atomically and portably.
// No shell, psql executable or Unix cron is required on the user's machine.
package migrate

import (
	"context"
	"crypto/sha256"
	"database/sql"
	"encoding/hex"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"unicode"
)

// Split understands PostgreSQL dollar quoted function bodies, SQL-escaped
// quotes, and both comment syntaxes. An unmatched delimiter fails closed.
func Split(src string) ([]string, error) {
	var result []string
	var out strings.Builder
	state, dollar := "normal", ""
	blockDepth := 0
	for i := 0; i < len(src); {
		ch := src[i]
		peek := byte(0)
		if i+1 < len(src) {
			peek = src[i+1]
		}
		switch state {
		case "lineComment":
			if ch == '\n' {
				out.WriteByte('\n')
				state = "normal"
			}
			i++
		case "blockComment":
			if ch == '/' && peek == '*' {
				blockDepth++
				i += 2
				continue
			}
			if ch == '*' && peek == '/' {
				blockDepth--
				i += 2
				if blockDepth == 0 {
					state = "normal"
				}
				continue
			}
			i++
		case "single":
			out.WriteByte(ch)
			i++
			if ch == '\'' {
				if i < len(src) && src[i] == '\'' {
					out.WriteByte(src[i])
					i++
				} else {
					state = "normal"
				}
			}
		case "double":
			out.WriteByte(ch)
			i++
			if ch == '"' {
				if i < len(src) && src[i] == '"' {
					out.WriteByte(src[i])
					i++
				} else {
					state = "normal"
				}
			}
		case "dollar":
			if strings.HasPrefix(src[i:], dollar) {
				out.WriteString(dollar)
				i += len(dollar)
				state = "normal"
			} else {
				out.WriteByte(ch)
				i++
			}
		case "normal":
			if ch == '-' && peek == '-' {
				out.WriteByte(' ')
				state = "lineComment"
				i += 2
				continue
			}
			if ch == '/' && peek == '*' {
				out.WriteByte(' ')
				blockDepth = 1
				state = "blockComment"
				i += 2
				continue
			}
			if ch == '\'' {
				state = "single"
				out.WriteByte(ch)
				i++
				continue
			}
			if ch == '"' {
				state = "double"
				out.WriteByte(ch)
				i++
				continue
			}
			if ch == '$' {
				end := i + 1
				for end < len(src) && (unicode.IsLetter(rune(src[end])) || unicode.IsDigit(rune(src[end])) || src[end] == '_') {
					end++
				}
				if end < len(src) && src[end] == '$' {
					dollar = src[i : end+1]
					state = "dollar"
					out.WriteString(dollar)
					i = end + 1
					continue
				}
			}
			if ch == ';' {
				s := strings.TrimSpace(out.String())
				if s != "" {
					result = append(result, s)
				}
				out.Reset()
				i++
				continue
			}
			out.WriteByte(ch)
			i++
		default:
			return nil, errors.New("unrecognized SQL state")
		}
	}
	if state == "lineComment" {
		state = "normal"
	}
	if state != "normal" {
		return nil, fmt.Errorf("unterminated SQL %s", state)
	}
	if s := strings.TrimSpace(out.String()); s != "" {
		result = append(result, s)
	}
	return result, nil
}

func Apply(ctx context.Context, db *sql.DB, dir string) (int, error) {
	if db == nil {
		return 0, errors.New("PostgreSQL required")
	}
	entries, err := os.ReadDir(dir)
	if err != nil {
		return 0, err
	}
	var names []string
	for _, e := range entries {
		name := e.Name()
		if e.IsDir() || len(name) < 5 || !strings.HasSuffix(name, ".sql") {
			continue
		}
		n := strings.SplitN(name, "_", 2)[0]
		if len(n) != 3 {
			continue
		}
		valid := true
		for _, ch := range n {
			if ch < '0' || ch > '9' {
				valid = false
				break
			}
		}
		if valid {
			names = append(names, name)
		}
	}
	sort.Strings(names)
	if len(names) == 0 {
		return 0, errors.New("no numbered PostgreSQL migrations found")
	}
	changed := 0
	for _, name := range names {
		raw, e := os.ReadFile(filepath.Join(dir, name))
		if e != nil {
			return changed, e
		}
		hash := sha256.Sum256(raw)
		digest := hex.EncodeToString(hash[:])
		stmts, e := Split(string(raw))
		if e != nil {
			return changed, fmt.Errorf("%s: %w", name, e)
		}
		tx, e := db.BeginTx(ctx, &sql.TxOptions{Isolation: sql.LevelSerializable})
		if e != nil {
			return changed, e
		}
		// Explicit rollback also covers timeouts halfway through CREATE TABLE.
		_, e = tx.ExecContext(ctx, `CREATE TABLE IF NOT EXISTS public.vnpipe_migrations (
            migration_name text PRIMARY KEY, sha256 text NOT NULL CHECK(length(sha256)=64),
            applied_at timestamptz NOT NULL DEFAULT now())`)
		if e != nil {
			tx.Rollback()
			return changed, e
		}
		var previous string
		e = tx.QueryRowContext(ctx, `SELECT sha256 FROM public.vnpipe_migrations WHERE migration_name=$1`, name).Scan(&previous)
		if e == nil {
			tx.Rollback()
			if previous != digest {
				return changed, fmt.Errorf("migration %s was modified after application", name)
			}
			continue
		}
		if !errors.Is(e, sql.ErrNoRows) {
			tx.Rollback()
			return changed, e
		}
		applied := 0
		for _, stmt := range stmts {
			// Script-level transaction markers are handled by *sql.Tx, not by
			// sending BEGIN/COMMIT across the driver connection.
			u := strings.ToUpper(strings.TrimSpace(stmt))
			if u == "BEGIN" || u == "COMMIT" {
				continue
			}
			if _, e = tx.ExecContext(ctx, stmt); e != nil {
				break
			}
			applied++
		}
		if e == nil && applied == 0 {
			e = errors.New("empty migration")
		}
		if e == nil {
			_, e = tx.ExecContext(ctx, `INSERT INTO public.vnpipe_migrations(migration_name,sha256) VALUES($1,$2)`, name, digest)
		}
		if e != nil {
			tx.Rollback()
			return changed, fmt.Errorf("migration %s failed: %w", name, e)
		}
		if e = tx.Commit(); e != nil {
			return changed, e
		}
		changed++
	}
	return changed, nil
}
