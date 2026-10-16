// Package config reads the deliberately restricted, declarative default TOML
// profile. Unsupported TOML expressions fail closed; use no silent defaults.
package config

import (
	"bufio"
	"fmt"
	"os"
	"strconv"
	"strings"
	"time"
)

type Config struct{ Values map[string]map[string]string }

func Load(path string) (Config, error) {
	file, err := os.Open(path)
	if err != nil {
		return Config{}, err
	}
	defer file.Close()
	c := Config{Values: make(map[string]map[string]string)}
	s := bufio.NewScanner(file)
	sec := ""
	line := 0
	for s.Scan() {
		line++
		raw := strings.TrimSpace(s.Text())
		if raw == "" || strings.HasPrefix(raw, "#") {
			continue
		}
		if strings.HasPrefix(raw, "[") && strings.HasSuffix(raw, "]") {
			sec = strings.TrimSuffix(strings.TrimPrefix(raw, "["), "]")
			if sec == "" || c.Values[sec] != nil {
				return Config{}, fmt.Errorf("line %d: duplicate/empty section", line)
			}
			c.Values[sec] = map[string]string{}
			continue
		}
		k, v, ok := strings.Cut(raw, "=")
		k = strings.TrimSpace(k)
		v = strings.TrimSpace(v)
		if !ok || sec == "" || k == "" || v == "" || strings.ContainsAny(k, " \t") {
			return Config{}, fmt.Errorf("line %d: invalid key/value", line)
		}
		if _, exists := c.Values[sec][k]; exists {
			return Config{}, fmt.Errorf("line %d: repeated key", line)
		}
		c.Values[sec][k] = v
	}
	if err := s.Err(); err != nil {
		return Config{}, err
	}
	return c, c.Validate()
}
func (c Config) str(section, key string) (string, error) {
	v, ok := c.Values[section][key]
	if !ok {
		return "", fmt.Errorf("missing %s.%s", section, key)
	}
	return v, nil
}
func (c Config) number(section, key string) (float64, error) {
	v, e := c.str(section, key)
	if e != nil {
		return 0, e
	}
	f, e := strconv.ParseFloat(v, 64)
	if e != nil {
		return 0, fmt.Errorf("invalid %s.%s numeric: %w", section, key, e)
	}
	return f, nil
}
func (c Config) integer(section, key string) (int, error) {
	v, e := c.str(section, key)
	if e != nil {
		return 0, e
	}
	n, e := strconv.Atoi(v)
	if e != nil {
		return 0, fmt.Errorf("invalid %s.%s integer: %w", section, key, e)
	}
	return n, nil
}
func (c Config) quoted(section, key string) (string, error) {
	v, e := c.str(section, key)
	if e != nil {
		return "", e
	}
	s, e := strconv.Unquote(v)
	if e != nil {
		return "", fmt.Errorf("invalid %s.%s string: %w", section, key, e)
	}
	return s, nil
}
func (c Config) rangeNumber(s, k string, min, max float64) error {
	f, e := c.number(s, k)
	if e != nil {
		return e
	}
	if !(f >= min && f <= max) {
		return fmt.Errorf("%s.%s outside [%g,%g]", s, k, min, max)
	}
	return nil
}
func (c Config) rangeInt(s, k string, min, max int) error {
	v, e := c.integer(s, k)
	if e != nil {
		return e
	}
	if v < min || v > max {
		return fmt.Errorf("%s.%s outside [%d,%d]", s, k, min, max)
	}
	return nil
}
func (c Config) Validate() error {
	expected := map[string][]string{
		"vnstock":         {"tier_rate_utilisation", "quota_soft_ceiling"},
		"universe":        {"investable_n", "exit_rank", "min_sessions_listed", "min_adv20_vnd"},
		"labels":          {"horizons", "entry", "benchmark"},
		"validation":      {"min_train_years", "embargo_sessions", "test_block"},
		"portfolio":       {"max_positions", "max_weight", "max_industry_weight", "rebalance_every_sessions", "order_to_adv_cap", "risk_off_gross_cap"},
		"costs":           {"commission_per_side", "sale_tax", "slippage_base_bps", "slippage_impact_bps", "survivorship_haircut_per_year"},
		"exchange_limits": {"HOSE", "HNX", "UPCOM"},
		"schedule":        {"timezone", "daily_trigger", "retry_until"},
	}
	if len(c.Values) != len(expected) {
		return fmt.Errorf("unexpected or missing sections")
	}
	for sec, keys := range expected {
		if len(c.Values[sec]) != len(keys) {
			return fmt.Errorf("unknown or missing key in %s", sec)
		}
		for _, k := range keys {
			if _, e := c.str(sec, k); e != nil {
				return e
			}
		}
	}
	nums := [][4]any{
		{"vnstock", "tier_rate_utilisation", 0.01, 0.85}, {"vnstock", "quota_soft_ceiling", 0.01, 0.8},
		{"universe", "min_adv20_vnd", 0.0, 1e15}, {"portfolio", "max_weight", 0.001, 1.0},
		{"portfolio", "max_industry_weight", 0.001, 1.0}, {"portfolio", "order_to_adv_cap", 0.001, 0.05},
		{"portfolio", "risk_off_gross_cap", 0.0, 1.0},
		{"costs", "commission_per_side", 0.0, .1}, {"costs", "sale_tax", 0.0, .1},
		{"costs", "slippage_base_bps", 0.0, 1000.0}, {"costs", "slippage_impact_bps", 0.0, 1000.0},
		{"costs", "survivorship_haircut_per_year", 0.0, 1.0},
		{"exchange_limits", "HOSE", 0.001, 0.5}, {"exchange_limits", "HNX", 0.001, 0.5},
		{"exchange_limits", "UPCOM", 0.001, 0.5},
	}
	for _, spec := range nums {
		if e := c.rangeNumber(spec[0].(string), spec[1].(string), spec[2].(float64), spec[3].(float64)); e != nil {
			return e
		}
	}
	ints := [][4]any{{"universe", "investable_n", 1, 10000}, {"universe", "exit_rank", 1, 10000}, {"universe", "min_sessions_listed", 1, 20000}, {"portfolio", "max_positions", 1, 1000}, {"portfolio", "rebalance_every_sessions", 1, 1000}, {"validation", "min_train_years", 1, 50}, {"validation", "embargo_sessions", 1, 1000}}
	for _, spec := range ints {
		if e := c.rangeInt(spec[0].(string), spec[1].(string), spec[2].(int), spec[3].(int)); e != nil {
			return e
		}
	}
	u, _ := c.integer("universe", "investable_n")
	x, _ := c.integer("universe", "exit_rank")
	n, _ := c.integer("portfolio", "max_positions")
	w, _ := c.number("portfolio", "max_weight")
	ind, _ := c.number("portfolio", "max_industry_weight")
	if x < u || n > u || float64(n)*w < 1e-12 || ind < w {
		return fmt.Errorf("inconsistent universe/portfolio constraints")
	}
	tz, e := c.quoted("schedule", "timezone")
	if e != nil {
		return e
	}
	if tz != "Asia/Ho_Chi_Minh" {
		return fmt.Errorf("schedule timezone must be Asia/Ho_Chi_Minh")
	}
	if _, e := time.LoadLocation(tz); e != nil {
		return e
	}
	start, e := c.quoted("schedule", "daily_trigger")
	if e != nil {
		return e
	}
	end, e := c.quoted("schedule", "retry_until")
	if e != nil {
		return e
	}
	a, e := time.Parse("15:04", start)
	if e != nil {
		return e
	}
	b, e := time.Parse("15:04", end)
	if e != nil || !b.After(a) {
		return fmt.Errorf("invalid retry schedule")
	}
	entry, e := c.quoted("labels", "entry")
	if e != nil || entry != "next_open" {
		return fmt.Errorf("unsupported entry")
	}
	benchmark, e := c.quoted("labels", "benchmark")
	if e != nil || benchmark != "VNINDEX" {
		return fmt.Errorf("unsupported benchmark")
	}
	block, e := c.quoted("validation", "test_block")
	if e != nil || block != "1M" {
		return fmt.Errorf("unsupported test block")
	}
	horizons, e := c.str("labels", "horizons")
	if e != nil {
		return e
	}
	compact := strings.ReplaceAll(horizons, " ", "")
	if compact != "[5,20]" {
		return fmt.Errorf("unsupported label horizons")
	}
	return nil
}
