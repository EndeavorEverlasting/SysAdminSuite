package main

import (
	"context"
	"flag"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/EndeavorEverlasting/SysAdminSuite/probe/packet-expenditure/internal/config"
	"github.com/EndeavorEverlasting/SysAdminSuite/probe/packet-expenditure/internal/evidence"
	"github.com/EndeavorEverlasting/SysAdminSuite/probe/packet-expenditure/internal/preflight"
	"github.com/EndeavorEverlasting/SysAdminSuite/probe/packet-expenditure/internal/runner"
	"github.com/EndeavorEverlasting/SysAdminSuite/probe/packet-expenditure/internal/targets"
)

func main() {
	site := flag.String("site", "", "Site label for evidence records")
	listPath := flag.String("list", "", "Approved target list (one host/IP per line)")
	profilePath := flag.String("profile", "", "JSON profile path (default: Config/cybernet-packet-profile.json under repo root)")
	outPath := flag.String("out", "", "JSONL evidence output path")
	summaryPath := flag.String("summary", "", "Summary JSON path")
	engine := flag.String("engine", "cli", "Scan engine: cli (default) or library (requires -tags naabu_lib build)")
	dryRun := flag.Bool("dry-run", false, "Validate inputs and print audit command only")
	allowPublic := flag.Bool("allow-public", false, "Permit public IPs in target list")
	naabuPath := flag.String("naabu", "", "Override naabu binary path (cli engine)")
	flag.Parse()

	if *site == "" || *listPath == "" {
		fmt.Fprintln(os.Stderr, "usage: sas-packet-probe -site SITE -list PATH [-profile PATH] [-out PATH] [-summary PATH] [-engine library|cli] [-dry-run]")
		os.Exit(2)
	}

	profileFile := *profilePath
	if profileFile == "" {
		profileFile = defaultProfilePath()
	}

	profile, err := config.LoadProfile(profileFile)
	if err != nil {
		fail("load profile", err)
	}
	if err := profile.Validate(); err != nil {
		fail("validate profile", err)
	}
	if !isSupportedEngine(*engine) {
		fail("validate engine", fmt.Errorf("unknown engine %q", *engine))
	}

	allow := profile.AllowPublicTargets || *allowPublic
	hosts, err := targets.Load(*listPath, profile.MaxTargets, allow)
	if err != nil {
		fail("load targets", err)
	}

	if *outPath == "" {
		*outPath = filepath.Join("logs", "nmap", fmt.Sprintf("%s_packet_probe.jsonl", sanitize(*site)))
	}
	if *summaryPath == "" {
		*summaryPath = strings.TrimSuffix(*outPath, filepath.Ext(*outPath)) + "_summary.json"
	}

	audit := profile.AuditCLI(*listPath, *outPath)
	if *dryRun {
		fmt.Println(audit)
		if err := writeDrySummary(*summaryPath, *site, len(hosts), audit, *engine, profile); err != nil {
			fail("write summary", err)
		}
		return
	}

	var pf preflight.Result
	bin := *naabuPath
	if strings.EqualFold(*engine, "cli") && bin == "" {
		var err error
		pf, err = preflight.CheckNaabuCLI()
		if err != nil {
			fail("preflight", err)
		}
		bin = pf.NaabuPath
	}
	if strings.EqualFold(*engine, "cli") && *naabuPath != "" {
		bin = *naabuPath
	}

	w, err := evidence.NewWriter(*outPath, *site, profile)
	if err != nil {
		fail("open evidence writer", err)
	}
	defer w.Close()

	start := time.Now()
	usedEngine, err := runner.Run(context.Background(), *engine, bin, *listPath, *outPath, profile, w)
	if err != nil {
		fail("run scan", err)
	}

	summary := evidence.Summary{
		Site:                *site,
		Classification:      "OK_NAABU_PACKET_PROBE",
		GeneratedAtUTC:      time.Now().UTC().Format(time.RFC3339),
		TargetCount:         len(hosts),
		OpenPortCount:       w.OpenCount(),
		DurationMs:          time.Since(start).Milliseconds(),
		SmartScan:           profile.SmartScan,
		PredictionThreshold: profile.PredictionThreshold,
		TopPorts:            profile.TopPorts,
		Threads:             profile.Threads,
		Rate:                profile.Rate,
		ExcludeCDN:          profile.ExcludeCDN,
		DisableUpdateCheck:  profile.DisableUpdateCheck,
		AuditCommand:        audit,
		Engine:              usedEngine,
	}
	if len(pf.Notes) > 0 {
		summary.Detail = strings.Join(pf.Notes, "; ")
	}
	if err := evidence.WriteSummary(*summaryPath, summary); err != nil {
		fail("write summary", err)
	}
}

func defaultProfilePath() string {
	cwd, _ := os.Getwd()
	for dir := cwd; dir != "" && dir != filepath.Dir(dir); dir = filepath.Dir(dir) {
		candidate := filepath.Join(dir, "Config", "cybernet-packet-profile.json")
		if _, err := os.Stat(candidate); err == nil {
			return candidate
		}
	}
	return "Config/cybernet-packet-profile.json"
}

func sanitize(site string) string {
	out := strings.Builder{}
	for _, r := range strings.ToLower(site) {
		switch {
		case r >= 'a' && r <= 'z', r >= '0' && r <= '9', r == '-', r == '_':
			out.WriteRune(r)
		}
	}
	if out.Len() == 0 {
		return "site"
	}
	return out.String()
}

func isSupportedEngine(engine string) bool {
	return strings.EqualFold(engine, "cli") || strings.EqualFold(engine, "library")
}

func writeDrySummary(path, site string, targetCount int, audit, engine string, profile config.Profile) error {
	summary := evidence.Summary{
		Site:                site,
		Classification:      "OK_NAABU_PACKET_PROBE_PLANNED",
		GeneratedAtUTC:      time.Now().UTC().Format(time.RFC3339),
		TargetCount:         targetCount,
		SmartScan:           profile.SmartScan,
		PredictionThreshold: profile.PredictionThreshold,
		TopPorts:            profile.TopPorts,
		Threads:             profile.Threads,
		Rate:                profile.Rate,
		ExcludeCDN:          profile.ExcludeCDN,
		DisableUpdateCheck:  profile.DisableUpdateCheck,
		AuditCommand:        audit,
		Engine:              engine,
		Detail:              "no packets sent",
	}
	return evidence.WriteSummary(path, summary)
}

func fail(step string, err error) {
	fmt.Fprintf(os.Stderr, "sas-packet-probe %s: %v\n", step, err)
	os.Exit(1)
}
