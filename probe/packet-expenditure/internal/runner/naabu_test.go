package runner

import (
	"testing"

	"github.com/EndeavorEverlasting/SysAdminSuite/probe/packet-expenditure/internal/config"
)

func TestBuildArgvSmartScan(t *testing.T) {
	p := config.DefaultProfile()
	args := BuildArgv("targets.txt", "out.jsonl", p)
	joined := stringsJoin(args)
	want := "-list targets.txt -tp 1000 -c 50 -rate 3000 -ss -pt 20 -s s -ec -json -silent -duc -o out.jsonl"
	if joined != want {
		t.Fatalf("argv mismatch\n got:  %s\n want: %s", joined, want)
	}
}

func stringsJoin(args []string) string {
	out := ""
	for i, a := range args {
		if i > 0 {
			out += " "
		}
		out += a
	}
	return out
}
