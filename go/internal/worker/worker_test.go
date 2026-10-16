package worker

import (
	"context"
	"testing"
)

func TestRejectMissingID(t *testing.T) {
	_, err := Invoke(context.Background(), "unused", "unused", map[string]any{"op": "health"})
	if err == nil {
		t.Fatal("missing ID must fail")
	}
}
