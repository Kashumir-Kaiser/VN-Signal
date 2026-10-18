package dq

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"math"
	"reflect"
	"strings"
	"testing"
)

func TestRankTierAEntryExitLiquidityAndTies(t *testing.T) {
	candidates := make([]TierACandidate, 0, 501)
	for i := 1; i <= 501; i++ {
		candidates = append(candidates, TierACandidate{Symbol: symbolForRank(i), Median20: float64(1000 - i), Average20: TierAMinADV20})
	}
	candidates[400].PriorMember = true // rank 401 remains during hysteresis
	candidates[499].PriorMember = true // rank 500 remains
	candidates[500].PriorMember = true // rank 501 leaves
	candidates[0].Average20 = TierAMinADV20 - 1
	got, err := RankTierA(candidates)
	if err != nil {
		t.Fatal(err)
	}
	if len(got) != TierAEntryRank-1+2 {
		t.Fatalf("selected count=%d, want 401 (rank 1 fails ADV, rank 401 and 500 retained)", len(got))
	}
	for _, symbol := range got {
		if symbol == symbolForRank(501) || symbol == symbolForRank(1) {
			t.Fatalf("unexpected selected symbol %s", symbol)
		}
	}
}

func TestTierATenureRequires250VerifiedPriorTradedSessions(t *testing.T) {
	counts := map[string]int{"TWO50": 250, "TWO49": 249}
	eligible := tenureEligibleSymbols([]listedRow{{symbol: "TWO49"}, {symbol: "TWO50"}, {symbol: "UNKNOWN"}}, counts)
	if !reflect.DeepEqual(eligible, []string{"TWO50"}) {
		t.Fatalf("tenure eligibility=%v, want only TWO50", eligible)
	}
}

func TestCompleteTierAWindowRequiresTwentyFiniteProxyValues(t *testing.T) {
	values := make([]float64, TierABars)
	for i := range values {
		values[i] = float64(i + 1)
	}
	if !completeTierAWindow(values) {
		t.Fatal("complete finite 20-session proxy window rejected")
	}
	if completeTierAWindow(values[:TierABars-1]) {
		t.Fatal("incomplete 20-session proxy window accepted")
	}
	values[7] = math.NaN()
	if completeTierAWindow(values) {
		t.Fatal("non-finite proxy value accepted")
	}
}

func TestVerifiedListingSnapshotRequiresMatchingHashAndRelationalRows(t *testing.T) {
	rows := make([]map[string]any, 1000)
	relational := make([]listedRow, 1000)
	for i := range rows {
		exchange := "HOSE"
		if i == 1 {
			exchange = "HNX"
		} else if i == 2 {
			exchange = "UPCOM"
		}
		symbol := fmt.Sprintf("S%04d", i)
		rows[i] = map[string]any{"symbol": symbol, "exchange": exchange}
		relational[i] = listedRow{symbol: symbol, exchange: exchange}
	}
	frame, err := json.Marshal(map[string]any{
		"columns": []string{"symbol", "exchange"}, "count": len(rows), "rows": rows,
	})
	if err != nil {
		t.Fatal(err)
	}
	digest := sha256.Sum256(frame)
	hexDigest := hex.EncodeToString(digest[:])
	if _, err = verifiedListingSnapshot(frame, hexDigest, relational); err != nil {
		t.Fatalf("valid snapshot rejected: %v", err)
	}
	if _, err = verifiedListingSnapshot(nil, hexDigest, relational); err == nil {
		t.Fatal("missing raw listing evidence accepted")
	}
	if _, err = verifiedListingSnapshot(frame, strings.Repeat("0", 64), relational); err == nil {
		t.Fatal("tampered listing hash accepted")
	}
	changed := append([]listedRow(nil), relational...)
	changed[0].exchange = "HNX"
	if _, err = verifiedListingSnapshot(frame, hexDigest, changed); err == nil {
		t.Fatal("relational listing that differs from source frame accepted")
	}
}

func TestRankTierADeterministicTieBreakAndNoEmptyFallback(t *testing.T) {
	input := []TierACandidate{
		{Symbol: "BBB", Median20: 10, Average20: TierAMinADV20},
		{Symbol: "AAA", Median20: 10, Average20: TierAMinADV20},
		{Symbol: "LOW", Median20: 9, Average20: TierAMinADV20 - 1},
	}
	want := []string{"AAA", "BBB"}
	got, err := RankTierA(input)
	if err != nil {
		t.Fatal(err)
	}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("RankTierA()=%v, want %v", got, want)
	}
	got, err = RankTierA([]TierACandidate{{Symbol: "LOW", Median20: 99, Average20: 1}})
	if err != nil {
		t.Fatal(err)
	}
	if len(got) != 0 {
		t.Fatalf("below-floor universe selected %v", got)
	}
}

func TestRankTierARejectsMalformedAndOverflowedCandidateMetrics(t *testing.T) {
	for _, candidate := range []TierACandidate{
		{Symbol: "bad symbol", Median20: 1, Average20: TierAMinADV20},
		{Symbol: "BAD", Median20: -1, Average20: TierAMinADV20},
		{Symbol: "BAD", Median20: 1, Average20: math.Inf(1)},
		{Symbol: "BAD", Median20: math.NaN(), Average20: TierAMinADV20},
	} {
		if _, err := RankTierA([]TierACandidate{candidate}); !errors.Is(err, ErrInvalidTierACandidate) {
			t.Fatalf("candidate %+v: got err %v", candidate, err)
		}
	}
}

func symbolForRank(i int) string {
	return string(rune('A'+(i-1)/26)) + string(rune('A'+(i-1)%26))
}
