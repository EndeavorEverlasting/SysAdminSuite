package evidence

import (
	"encoding/json"
	"os"
	"time"

	"github.com/EndeavorEverlasting/SysAdminSuite/probe/packet-expenditure/internal/config"
)

type Record struct {
	Timestamp string         `json:"timestamp"`
	Site      string         `json:"site"`
	Host      string         `json:"host"`
	Port      int            `json:"port,omitempty"`
	Protocol  string         `json:"protocol,omitempty"`
	Scanner   string         `json:"scanner"`
	Profile   map[string]any `json:"profile"`
}

type Summary struct {
	Site                string `json:"site"`
	Classification      string `json:"classification"`
	GeneratedAtUTC      string `json:"generatedAtUtc"`
	TargetCount         int    `json:"targetCount"`
	OpenPortCount       int    `json:"openPortCount"`
	DurationMs          int64  `json:"durationMs"`
	SmartScan           bool   `json:"smartScan"`
	PredictionThreshold int    `json:"predictionThreshold"`
	TopPorts            string `json:"topPorts,omitempty"`
	Threads             int    `json:"threads"`
	Rate                int    `json:"rate"`
	ExcludeCDN          bool   `json:"excludeCdn"`
	DisableUpdateCheck  bool   `json:"disableUpdateCheck"`
	AuditCommand        string `json:"auditCommand"`
	Engine              string `json:"engine"`
	Detail              string `json:"detail,omitempty"`
}

type Writer struct {
	site    string
	profile config.Profile
	file    *os.File
	enc     *json.Encoder
	opens   int
}

func NewWriter(outPath, site string, profile config.Profile) (*Writer, error) {
	if err := os.MkdirAll(dirOf(outPath), 0o755); err != nil {
		return nil, err
	}
	f, err := os.Create(outPath)
	if err != nil {
		return nil, err
	}
	return &Writer{
		site:    site,
		profile: profile,
		file:    f,
		enc:     json.NewEncoder(f),
	}, nil
}

func dirOf(path string) string {
	i := len(path) - 1
	for i >= 0 && path[i] != '/' && path[i] != '\\' {
		i--
	}
	if i <= 0 {
		return "."
	}
	return path[:i]
}

func (w *Writer) profileMap() map[string]any {
	return map[string]any{
		"topPorts":            w.profile.TopPorts,
		"threads":             w.profile.Threads,
		"rate":                w.profile.Rate,
		"smartScan":           w.profile.SmartScan,
		"predictionThreshold": w.profile.PredictionThreshold,
		"excludeCdn":          w.profile.ExcludeCDN,
	}
}

func (w *Writer) WriteHostPort(host string, port int, protocol, scanner string) error {
	w.opens++
	rec := Record{
		Timestamp: time.Now().UTC().Format(time.RFC3339Nano),
		Site:      w.site,
		Host:      host,
		Port:      port,
		Protocol:  protocol,
		Scanner:   scanner,
		Profile:   w.profileMap(),
	}
	return w.enc.Encode(rec)
}

func (w *Writer) Close() error {
	if w.file == nil {
		return nil
	}
	return w.file.Close()
}

func (w *Writer) OpenCount() int { return w.opens }

func WriteSummary(path string, summary Summary) error {
	if path == "" {
		return nil
	}
	if err := os.MkdirAll(dirOf(path), 0o755); err != nil {
		return err
	}
	b, err := json.MarshalIndent(summary, "", "  ")
	if err != nil {
		return err
	}
	b = append(b, '\n')
	return os.WriteFile(path, b, 0o644)
}
