package ingest

import (
	"encoding/json"
	"errors"
	"strings"
	"testing"
)

func payload(rows string, count int) []byte {
	return payloadWithAttribution(rows, count, `{"source":"vci"}`)
}
func payloadWithAttribution(rows string, count int, attribution string) []byte {
	return []byte(`{"columns":["time","open","high","low","close","volume"],"count":` + jsonNumber(count) + `,"rows":` + rows + `,"attributes":` + attribution + `}`)
}
func jsonNumber(n int) string { b, _ := json.Marshal(n); return string(b) }

const one = `{"time":"2026-10-15T00:00:00","open":100,"high":105,"low":99,"close":103,"volume":0}`
const two = `{"time":"2026-10-16","open":"102","high":107,"low":101,"close":106,"volume":120}`

func TestNormalizeBarsGood(t *testing.T) {
	r, e := NormalizeBars("fpt", payload("["+one+","+two+"]", 2))
	if e != nil || r.Symbol != "FPT" || r.Count != 2 || r.FirstDate != "2026-10-15" || r.LastDate != "2026-10-16" || r.Rows[0].Volume != 0 {
		t.Fatalf("%+v %v", r, e)
	}
}
func TestNormalizeBarsRejectsFaults(t *testing.T) {
	good := string(payload("["+one+"]", 1))
	cases := []string{
		strings.Replace(good, `"count":1`, `"count":2`, 1),
		strings.Replace(good, `"high":105`, `"high":90`, 1),
		strings.Replace(good, `"close":103`, `"close":null`, 1),
		strings.Replace(good, `"volume":0`, `"volume":-1`, 1),
		strings.Replace(good, `"columns":["time"`, `"columns":["oops"`, 1),
		strings.Replace(good, `"time":"2026-10-15T00:00:00"`, `"time":"bogus"`, 1),
		good + "{}", "{}", "[]", strings.Replace(good, `"count":1`, `"count":0`, 1),
		string(payload("["+two+","+one+"]", 2)), string(payload("["+one+","+one+"]", 2)),
	}
	for i, c := range cases {
		_, e := NormalizeBars("FPT", []byte(c))
		if !errors.Is(e, ErrInvalidFrame) {
			t.Fatalf("case %d failed to reject: %v", i, e)
		}
	}
	_, e := NormalizeBars("../bad", []byte(good))
	if !errors.Is(e, ErrInvalidFrame) {
		t.Fatal(e)
	}
}
