package config

import (
	"encoding/json"
	"fmt"
	"os"
)

type OutputConfig struct {
	JSONL  bool `json:"jsonl"`
	Silent bool `json:"silent"`
}

type Profile struct {
	PortMode                  string       `json:"portMode"`
	TopPorts                  string       `json:"topPorts"`
	Ports                     string       `json:"ports"`
	ExplicitPorts             string       `json:"explicitPorts"`
	Threads                   int          `json:"threads"`
	Rate                      int          `json:"rate"`
	SmartScan                 bool         `json:"smartScan"`
	PredictionThreshold       int          `json:"predictionThreshold"`
	ScanType                  string       `json:"scanType"`
	MaxTargets                int          `json:"maxTargets"`
	RequireApprovedTargetFile bool         `json:"requireApprovedTargetFile"`
	AllowPublicTargets        bool         `json:"allowPublicTargets"`
	ExcludeCDN                bool         `json:"excludeCdn"`
	DisableUpdateCheck        bool         `json:"disableUpdateCheck"`
	Stream                    bool         `json:"stream"`
	Passive                   bool         `json:"passive"`
	Output                    OutputConfig `json:"output"`
}

func DefaultProfile() Profile {
	return Profile{
		PortMode:            "top",
		TopPorts:            "1000",
		Threads:             50,
		Rate:                3000,
		SmartScan:           true,
		PredictionThreshold: 20,
		ScanType:            "s",
		MaxTargets:          256,
		ExcludeCDN:          true,
		DisableUpdateCheck:  true,
		Output:              OutputConfig{JSONL: true, Silent: true},
	}
}

func LoadProfile(path string) (Profile, error) {
	p := DefaultProfile()
	if path == "" {
		return p, nil
	}
	b, err := os.ReadFile(path)
	if err != nil {
		return Profile{}, err
	}
	if err := json.Unmarshal(b, &p); err != nil {
		return Profile{}, err
	}
	return p, nil
}

func (p Profile) Validate() error {
	if p.Threads <= 0 {
		return fmt.Errorf("threads must be > 0")
	}
	if p.Rate <= 0 {
		return fmt.Errorf("rate must be > 0")
	}
	if p.MaxTargets <= 0 {
		return fmt.Errorf("maxTargets must be > 0")
	}
	if p.SmartScan && p.Stream {
		return fmt.Errorf("smartScan is not compatible with stream mode")
	}
	if p.SmartScan && p.Passive {
		return fmt.Errorf("smartScan is not compatible with passive mode")
	}
	if p.PredictionThreshold < 0 || p.PredictionThreshold > 100 {
		return fmt.Errorf("predictionThreshold must be 0-100")
	}
	if p.PortMode == "top" && p.TopPorts == "" {
		return fmt.Errorf("topPorts required when portMode is top")
	}
	if p.PortMode == "explicit" && p.ExplicitPorts == "" {
		if p.Ports == "" {
			return fmt.Errorf("ports or explicitPorts required when portMode is explicit")
		}
	}
	if p.ScanType == "" {
		return fmt.Errorf("scanType is required")
	}
	if !p.ExcludeCDN {
		return fmt.Errorf("excludeCdn must be true for packet-probe profiles")
	}
	if !p.DisableUpdateCheck {
		return fmt.Errorf("disableUpdateCheck must be true for packet-probe profiles")
	}
	if !p.Output.Silent {
		return fmt.Errorf("output.silent must be true")
	}
	if !p.Output.JSONL {
		return fmt.Errorf("output.jsonl must be true")
	}
	return nil
}

func (p Profile) AuditCLI(listPath, outPath string) string {
	cmd := fmt.Sprintf("%s -list %s", "naabu", listPath)
	if p.PortMode == "explicit" {
		cmd += fmt.Sprintf(" -p %s", p.ExplicitPortList())
	} else {
		cmd += fmt.Sprintf(" -tp %s", p.TopPorts)
	}
	cmd += fmt.Sprintf(" -c %d -rate %d", p.Threads, p.Rate)
	if p.SmartScan {
		cmd += fmt.Sprintf(" -ss -pt %d", p.PredictionThreshold)
	}
	cmd += fmt.Sprintf(" -s %s", p.ScanType)
	if p.ExcludeCDN {
		cmd += " -ec"
	}
	if p.Output.JSONL {
		cmd += " -json"
	}
	if p.Output.Silent {
		cmd += " -silent"
	}
	if p.DisableUpdateCheck {
		cmd += " -duc"
	}
	cmd += fmt.Sprintf(" -o %s", outPath)
	return cmd
}

func (p Profile) ExplicitPortList() string {
	if p.ExplicitPorts != "" {
		return p.ExplicitPorts
	}
	return p.Ports
}
