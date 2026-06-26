package targets

import (
	"os"
	"path/filepath"
	"testing"
)

func TestLoadPrivateOnly(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "targets.txt")
	if err := os.WriteFile(path, []byte("10.0.0.1\n10.0.0.2\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	got, err := Load(path, 10, false)
	if err != nil {
		t.Fatalf("load: %v", err)
	}
	if len(got) != 2 {
		t.Fatalf("expected 2 targets, got %d", len(got))
	}
}

func TestRejectPublicIP(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "targets.txt")
	if err := os.WriteFile(path, []byte("8.8.8.8\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	if _, err := Load(path, 10, false); err == nil {
		t.Fatal("expected public IP rejection")
	}
}

func TestAllowPublicIP(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "targets.txt")
	if err := os.WriteFile(path, []byte("8.8.8.8\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	if _, err := Load(path, 10, true); err != nil {
		t.Fatalf("allow public: %v", err)
	}
}
