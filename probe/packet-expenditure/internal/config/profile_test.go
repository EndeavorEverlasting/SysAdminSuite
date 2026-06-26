package config

import "testing"

func TestDefaultProfileValidate(t *testing.T) {
	p := DefaultProfile()
	if err := p.Validate(); err != nil {
		t.Fatalf("default profile invalid: %v", err)
	}
}

func TestAuditCLI(t *testing.T) {
	p := DefaultProfile()
	got := p.AuditCLI("targets.txt", "out.jsonl")
	want := "naabu -list targets.txt -tp 1000 -c 50 -rate 3000 -ss -pt 20 -s s -ec -json -silent -duc -o out.jsonl"
	if got != want {
		t.Fatalf("audit cli mismatch\n got:  %s\n want: %s", got, want)
	}
}

func TestSmartScanStreamConflict(t *testing.T) {
	p := DefaultProfile()
	p.Stream = true
	if err := p.Validate(); err == nil {
		t.Fatal("expected smartScan/stream conflict")
	}
}

func TestValidateRequiresDoctrineFlags(t *testing.T) {
	p := DefaultProfile()
	p.ExcludeCDN = false
	if err := p.Validate(); err == nil {
		t.Fatal("expected excludeCdn rejection")
	}

	p = DefaultProfile()
	p.DisableUpdateCheck = false
	if err := p.Validate(); err == nil {
		t.Fatal("expected disableUpdateCheck rejection")
	}

	p = DefaultProfile()
	p.Output.Silent = false
	if err := p.Validate(); err == nil {
		t.Fatal("expected output.silent rejection")
	}

	p = DefaultProfile()
	p.Output.JSONL = false
	if err := p.Validate(); err == nil {
		t.Fatal("expected output.jsonl rejection")
	}
}
