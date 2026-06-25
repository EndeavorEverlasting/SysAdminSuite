package main

import (
	"bufio"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"net"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"time"
)

type profile struct {
	PortMode            string `json:"portMode"`
	TopPorts            string `json:"topPorts"`
	Ports               string `json:"ports"`
	Threads             int    `json:"threads"`
	Rate                int    `json:"rate"`
	SmartScan           bool   `json:"smartScan"`
	PredictionThreshold int    `json:"predictionThreshold"`
	ScanType            string `json:"scanType"`
	MaxTargets          int    `json:"maxTargets"`
	RequireApprovedFile bool   `json:"requireApprovedTargetFile"`
	AllowPublicTargets  bool   `json:"allowPublicTargets"`
	ExcludeCDN          bool   `json:"excludeCdn"`
	DisableUpdateCheck  bool   `json:"disableUpdateCheck"`
	Stream              bool   `json:"stream"`
	Passive             bool   `json:"passive"`
	Output              output `json:"output"`
}

type output struct {
	JSONL  bool `json:"jsonl"`
	Silent bool `json:"silent"`
}

type summary struct {
	Classification        string `json:"classification"`
	GeneratedAt           string `json:"generated_at"`
	Site                  string `json:"site,omitempty"`
	TargetCount           int    `json:"target_count"`
	Output                string `json:"output"`
	AuditCommand          string `json:"audit_command"`
	TopPorts              string `json:"topPorts,omitempty"`
	Ports                 string `json:"ports,omitempty"`
	Threads               int    `json:"threads"`
	Rate                  int    `json:"rate"`
	SmartScan             bool   `json:"smartScan"`
	PredictionThreshold   int    `json:"predictionThreshold"`
	ExcludeCDN            bool   `json:"excludeCdn"`
	Silent                bool   `json:"silent"`
	JSON                  bool   `json:"json"`
	DisableUpdateCheck    bool   `json:"disableUpdateCheck"`
	DryRun                bool   `json:"dryRun"`
	EnvironmentBlockCause string `json:"environment_block_cause,omitempty"`
}

func defaultProfilePath() string {
	return filepath.Clean(filepath.Join("Config", "cybernet-packet-profile.json"))
}

func loadProfile(path string) (profile, error) {
	var p profile
	data, err := os.ReadFile(path)
	if err != nil {
		return p, err
	}
	if err := json.Unmarshal(data, &p); err != nil {
		return p, err
	}
	if p.MaxTargets == 0 {
		p.MaxTargets = 256
	}
	return p, validateProfile(p)
}

func validateProfile(p profile) error {
	if p.Stream && p.SmartScan {
		return errors.New("smartScan cannot be combined with stream mode")
	}
	if p.Passive && p.SmartScan {
		return errors.New("smartScan cannot be combined with passive mode")
	}
	if !p.ExcludeCDN {
		return errors.New("excludeCdn must be true for packet-probe profiles")
	}
	if !p.Output.Silent {
		return errors.New("output.silent must be true")
	}
	if !p.Output.JSONL {
		return errors.New("output.jsonl must be true")
	}
	if p.PortMode == "" {
		return errors.New("portMode is required")
	}
	switch p.PortMode {
	case "top":
		if p.TopPorts == "" {
			return errors.New("top port mode requires topPorts")
		}
	case "explicit":
		if p.Ports == "" {
			return errors.New("explicit port mode requires ports")
		}
	default:
		return fmt.Errorf("unsupported portMode: %s", p.PortMode)
	}
	if p.Threads <= 0 || p.Rate <= 0 {
		return errors.New("threads and rate must be positive")
	}
	if p.SmartScan && (p.PredictionThreshold < 0 || p.PredictionThreshold > 100) {
		return errors.New("predictionThreshold must be 0-100")
	}
	return nil
}

func loadTargets(path string, maxTargets int, allowPublic bool) ([]string, error) {
	f, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer f.Close()

	var targets []string
	sc := bufio.NewScanner(f)
	for sc.Scan() {
		line := strings.TrimSpace(strings.SplitN(sc.Text(), "#", 2)[0])
		if line == "" {
			continue
		}
		if strings.Contains(line, "/") {
			return nil, fmt.Errorf("target list must not contain CIDR lines: %s", line)
		}
		if ip := net.ParseIP(line); ip != nil && !allowPublic && !isApprovedLocalIP(ip) {
			return nil, fmt.Errorf("public target requires explicit allow-public gate: %s", line)
		}
		targets = append(targets, line)
		if len(targets) > maxTargets {
			return nil, fmt.Errorf("target count %d exceeds maxTargets %d", len(targets), maxTargets)
		}
	}
	if err := sc.Err(); err != nil {
		return nil, err
	}
	if len(targets) == 0 {
		return nil, errors.New("target list is empty")
	}
	return targets, nil
}

func isApprovedLocalIP(ip net.IP) bool {
	return ip.IsPrivate() || ip.IsLoopback() || ip.IsLinkLocalUnicast()
}

func buildNaabuArgs(list, out string, p profile) []string {
	args := []string{"-list", list}
	if p.PortMode == "top" {
		args = append(args, "-tp", p.TopPorts)
	} else {
		args = append(args, "-p", p.Ports)
	}
	args = append(args, "-c", strconv.Itoa(p.Threads), "-rate", strconv.Itoa(p.Rate))
	if p.SmartScan {
		args = append(args, "-ss", "-pt", strconv.Itoa(p.PredictionThreshold))
	}
	if p.ExcludeCDN {
		args = append(args, "-ec")
	}
	if p.Output.Silent {
		args = append(args, "-silent")
	}
	if p.Output.JSONL {
		args = append(args, "-json")
	}
	if p.DisableUpdateCheck {
		args = append(args, "-duc")
	}
	args = append(args, "-o", out)
	return args
}

func auditCommand(args []string) string {
	quoted := make([]string, 0, len(args)+1)
	quoted = append(quoted, "naabu")
	for _, arg := range args {
		if strings.ContainsAny(arg, " \t") {
			quoted = append(quoted, strconv.Quote(arg))
		} else {
			quoted = append(quoted, arg)
		}
	}
	return strings.Join(quoted, " ")
}

func writeSummary(path string, s summary) error {
	if path == "" {
		return nil
	}
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return err
	}
	data, err := json.MarshalIndent(s, "", "  ")
	if err != nil {
		return err
	}
	data = append(data, '\n')
	return os.WriteFile(path, data, 0o644)
}

func findNaabu(explicit string) (string, error) {
	if explicit != "" {
		return explicit, nil
	}
	if p, err := exec.LookPath("naabu.exe"); err == nil {
		return p, nil
	}
	if p, err := exec.LookPath("naabu"); err == nil {
		return p, nil
	}
	local := filepath.Join("bin", "naabu.exe")
	if _, err := os.Stat(local); err == nil {
		return local, nil
	}
	return "", errors.New("naabu not found; run survey/sas-ensure-naabu.sh or pass -naabu")
}

func main() {
	list := flag.String("list", "", "approved target file (one IP/hostname per line)")
	out := flag.String("out", "", "naabu JSONL output path")
	summaryPath := flag.String("summary", "", "summary JSON output path")
	profilePath := flag.String("profile", defaultProfilePath(), "packet profile JSON path")
	site := flag.String("site", "", "site label")
	dryRun := flag.Bool("dry-run", false, "print planned command and write summary; no packets")
	verbose := flag.Bool("verbose", false, "print resolved decisions to stderr")
	allowPublic := flag.Bool("allow-public", false, "permit public IP targets")
	naabuPath := flag.String("naabu", "", "naabu binary path")
	flag.Parse()

	if *list == "" || *out == "" {
		fmt.Fprintln(os.Stderr, "usage: sas-packet-probe -list PATH -out PATH [-summary PATH] [-site SITE] [-dry-run]")
		os.Exit(2)
	}

	p, err := loadProfile(*profilePath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "load profile: %v\n", err)
		os.Exit(1)
	}
	targets, err := loadTargets(*list, p.MaxTargets, p.AllowPublicTargets || *allowPublic)
	if err != nil {
		fmt.Fprintf(os.Stderr, "load targets: %v\n", err)
		os.Exit(1)
	}
	args := buildNaabuArgs(*list, *out, p)
	audit := auditCommand(args)
	now := time.Now().UTC().Format(time.RFC3339)
	s := summary{
		Classification:      "OK_NAABU_PACKET_PROBE_PLANNED",
		GeneratedAt:         now,
		Site:                *site,
		TargetCount:         len(targets),
		Output:              *out,
		AuditCommand:        audit,
		TopPorts:            p.TopPorts,
		Ports:               p.Ports,
		Threads:             p.Threads,
		Rate:                p.Rate,
		SmartScan:           p.SmartScan,
		PredictionThreshold: p.PredictionThreshold,
		ExcludeCDN:          p.ExcludeCDN,
		Silent:              p.Output.Silent,
		JSON:                p.Output.JSONL,
		DisableUpdateCheck:  p.DisableUpdateCheck,
		DryRun:              *dryRun,
	}
	if *dryRun {
		fmt.Println(audit)
		if err := writeSummary(*summaryPath, s); err != nil {
			fmt.Fprintf(os.Stderr, "write summary: %v\n", err)
			os.Exit(1)
		}
		return
	}

	bin, err := findNaabu(*naabuPath)
	if err != nil {
		s.Classification = "ENVIRONMENT_BLOCKED_POLICY"
		s.EnvironmentBlockCause = err.Error()
		_ = writeSummary(*summaryPath, s)
		fmt.Fprintf(os.Stderr, "%v\n", err)
		os.Exit(1)
	}
	if *verbose {
		fmt.Fprintf(os.Stderr, "[sas-packet-probe] %s\n", audit)
	}
	if err := os.MkdirAll(filepath.Dir(*out), 0o755); err != nil {
		fmt.Fprintf(os.Stderr, "mkdir output: %v\n", err)
		os.Exit(1)
	}
	cmd := exec.Command(bin, args...)
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	if err := cmd.Run(); err != nil {
		s.Classification = "NAABU_PACKET_PROBE_FAILED"
		_ = writeSummary(*summaryPath, s)
		fmt.Fprintf(os.Stderr, "naabu failed: %v\n", err)
		os.Exit(1)
	}
	s.Classification = "OK_NAABU_PACKET_PROBE"
	if err := writeSummary(*summaryPath, s); err != nil {
		fmt.Fprintf(os.Stderr, "write summary: %v\n", err)
		os.Exit(1)
	}
}
