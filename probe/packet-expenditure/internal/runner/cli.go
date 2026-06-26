package runner

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"strings"

	"github.com/EndeavorEverlasting/SysAdminSuite/probe/packet-expenditure/internal/config"
	"github.com/EndeavorEverlasting/SysAdminSuite/probe/packet-expenditure/internal/evidence"
)

func BuildArgv(listPath, outPath string, p config.Profile) []string {
	args := []string{"-list", listPath}
	if p.PortMode == "explicit" {
		args = append(args, "-p", p.ExplicitPortList())
	} else {
		args = append(args, "-tp", p.TopPorts)
	}
	args = append(args, "-c", fmt.Sprint(p.Threads), "-rate", fmt.Sprint(p.Rate))
	if p.SmartScan {
		args = append(args, "-ss", "-pt", fmt.Sprint(p.PredictionThreshold))
	}
	args = append(args, "-s", p.ScanType)
	if p.ExcludeCDN {
		args = append(args, "-ec")
	}
	if p.Output.JSONL {
		args = append(args, "-json")
	}
	if p.Output.Silent {
		args = append(args, "-silent")
	}
	if p.DisableUpdateCheck {
		args = append(args, "-duc")
	}
	args = append(args, "-o", outPath)
	return args
}

func RunCLI(ctx context.Context, naabuPath, listPath, outPath string, p config.Profile, w *evidence.Writer) error {
	args := BuildArgv(listPath, outPath, p)
	cmd := exec.CommandContext(ctx, naabuPath, args...)
	cmd.Stderr = os.Stderr
	if err := cmd.Run(); err != nil {
		return fmt.Errorf("naabu cli: %w", err)
	}
	return ingestNaabuJSONL(outPath, w, "naabu-cli")
}

func ingestNaabuJSONL(path string, w *evidence.Writer, scanner string) error {
	b, err := os.ReadFile(path)
	if err != nil {
		if os.IsNotExist(err) {
			return nil
		}
		return err
	}
	for _, line := range strings.Split(string(b), "\n") {
		line = strings.TrimSpace(line)
		if line == "" {
			continue
		}
		var rec struct {
			Host     string `json:"host"`
			Port     int    `json:"port"`
			Protocol string `json:"protocol"`
		}
		if err := json.Unmarshal([]byte(line), &rec); err != nil {
			continue
		}
		if rec.Host == "" || rec.Port == 0 {
			continue
		}
		if err := w.WriteHostPort(rec.Host, rec.Port, rec.Protocol, scanner); err != nil {
			return err
		}
	}
	return nil
}

func Run(ctx context.Context, engine, naabuPath, listPath, outPath string, p config.Profile, w *evidence.Writer) (string, error) {
	switch strings.ToLower(engine) {
	case "cli":
		return "naabu-cli", RunCLI(ctx, naabuPath, listPath, outPath, p, w)
	case "library":
		if err := RunLibrary(ctx, listPath, p, w); err != nil {
			return "naabu-library", err
		}
		return "naabu-library", nil
	default:
		return "", fmt.Errorf("unknown engine %q", engine)
	}
}
