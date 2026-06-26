package main

import "testing"

func TestSupportedEngines(t *testing.T) {
	for _, engine := range []string{"cli", "CLI", "library", "Library"} {
		if !isSupportedEngine(engine) {
			t.Fatalf("expected %q to be supported", engine)
		}
	}
	if isSupportedEngine("passive") {
		t.Fatal("unexpected support for passive engine")
	}
}

func TestSanitizeSite(t *testing.T) {
	if got := sanitize("SSUH West/1"); got != "ssuhwest1" {
		t.Fatalf("sanitize = %q, want ssuhwest1", got)
	}
	if got := sanitize("!!!"); got != "site" {
		t.Fatalf("empty sanitize fallback = %q, want site", got)
	}
}
