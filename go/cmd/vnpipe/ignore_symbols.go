package main

import (
	"bufio"
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

// Missing/invalid ignore files fail closed rather than silently spend quota.
// This is a collection filter only: no stored symbol, bar, or raw observation
// is deleted or relabelled.
func readIgnoredSymbols(path string) (map[string]bool, error) {
	f, err := os.Open(path)
	if err != nil {
		return nil, fmt.Errorf("open ignored symbols: %w", err)
	}
	defer f.Close()
	ignored := make(map[string]bool)
	scanner := bufio.NewScanner(f)
	for line := 1; scanner.Scan(); line++ {
		sym := strings.TrimSpace(scanner.Text())
		if sym == "" || strings.HasPrefix(sym, "#") {
			continue
		}
		if len(sym) > 12 {
			return nil, fmt.Errorf("invalid ignored symbol at line %d", line)
		}
		for _, c := range sym {
			if !((c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9')) {
				return nil, fmt.Errorf("invalid ignored symbol at line %d", line)
			}
		}
		if ignored[sym] {
			return nil, fmt.Errorf("duplicate ignored symbol at line %d", line)
		}
		ignored[sym] = true
	}
	if err := scanner.Err(); err != nil {
		return nil, fmt.Errorf("read ignored symbols: %w", err)
	}
	return ignored, nil
}
func loadIgnoredSymbols() (map[string]bool, error) {
	return readIgnoredSymbols(filepath.Join(filepath.Dir(configPath()), "ignored_symbols.txt"))
}
func filterIgnoredSymbols(in []string, ignored map[string]bool) ([]string, int) {
	out := make([]string, 0, len(in))
	skipped := 0
	for _, sym := range in {
		if ignored[sym] {
			skipped++
			continue
		}
		out = append(out, sym)
	}
	return out, skipped
}
func requireNotIgnoredSymbol(symbol string, ignored map[string]bool) error {
	if ignored[symbol] {
		return fmt.Errorf("symbol %s is excluded by config/ignored_symbols.txt", symbol)
	}
	return nil
}
