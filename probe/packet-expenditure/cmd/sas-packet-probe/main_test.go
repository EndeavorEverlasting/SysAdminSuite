package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func writeTemp(t *testing.T, name, content string) string {
	t.Helper()
	path := filepath.Join(t.TempDir(), name)
	if err := os.WriteFile(path, []byte(content), 0o644); err != nil {
		t.Fatal(err)
	}
	return path
}

func TestBuildNaabuArgsPreservesDoctrineFlags(t *testing.T) {
	p := profile{
		PortMode:            "top",
		TopPorts:            "1000",
		Threads:             50,
		Rate:                3000,
		SmartScan:           true,
		PredictionThreshold: 20,
		ExcludeCDN:          true,
		DisableUpdateCheck:  true,
		Output:              output{JSONL: true, Silent: true},
	}
	cmd := auditCommand(buildNaabuArgs("targets.txt", "results.json", p))
	for _, want := range []string{"-list targets.txt", "-tp 1000", "-c 50", "-rate 3000", "-ss", "-pt 20", "-ec", "-silent", "-json", "-duc", "-o results.json"} {
		if !strings.Contains(cmd, want) {
			t.Fatalf("audit command missing %q: %s", want, cmd)
		}
	}
}

func TestValidateProfileRejectsUnsafeSmartScanModes(t *testing.T) {
	p := profile{
		PortMode:            "top",
		TopPorts:            "1000",
		Threads:             50,
		Rate:                3000,
		SmartScan:           true,
		PredictionThreshold: 20,
		ExcludeCDN:          true,
		Output:              output{JSONL: true, Silent: true},
		Stream:              true,
	}
	if err := validateProfile(p); err == nil {
		t.Fatal("expected stream + smartScan rejection")
	}
	p.Stream = false
	p.Passive = true
	if err := validateProfile(p); err == nil {
		t.Fatal("expected passive + smartScan rejection")
	}
}

func TestValidateProfileRequiresCdnAndSilentJson(t *testing.T) {
	p := profile{PortMode: "top", TopPorts: "1000", Threads: 50, Rate: 3000, Output: output{JSONL: true, Silent: true}}
	if err := validateProfile(p); err == nil {
		t.Fatal("expected excludeCdn rejection")
	}
	p.ExcludeCDN = true
	p.Output.Silent = false
	if err := validateProfile(p); err == nil {
		t.Fatal("expected silent rejection")
	}
	p.Output.Silent = true
	p.Output.JSONL = false
	if err := validateProfile(p); err == nil {
		t.Fatal("expected jsonl rejection")
	}
}

func TestLoadTargetsRejectsEmptyCidrAndPublic(t *testing.T) {
	if _, err := loadTargets(writeTemp(t, "empty.txt", "\n# none\n"), 10, false); err == nil {
		t.Fatal("expected empty target rejection")
	}
	if _, err := loadTargets(writeTemp(t, "cidr.txt", "10.10.10.0/24\n"), 10, false); err == nil {
		t.Fatal("expected CIDR target rejection")
	}
	if _, err := loadTargets(writeTemp(t, "public.txt", "8.8.8.8\n"), 10, false); err == nil {
		t.Fatal("expected public target rejection")
	}
	targets, err := loadTargets(writeTemp(t, "private.txt", "10.10.10.1\nhost-a\n"), 10, false)
	if err != nil {
		t.Fatalf("private/hostname targets should pass: %v", err)
	}
	if len(targets) != 2 {
		t.Fatalf("target count = %d, want 2", len(targets))
	}
}
