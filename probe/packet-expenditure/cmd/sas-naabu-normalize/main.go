package main

import (
	"bufio"
	"encoding/json"
	"flag"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"time"
)

type row struct {
	Timestamp     string `json:"timestamp"`
	Host          string `json:"host"`
	Port          string `json:"port"`
	CybernetSignal string `json:"cybernet_signal,omitempty"`
	Source        string `json:"source"`
}

func loadTxt(path string) ([]row, error) {
	f, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer f.Close()
	var out []row
	sc := bufio.NewScanner(f)
	for sc.Scan() {
		line := strings.TrimSpace(sc.Text())
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		host, port, ok := strings.Cut(line, ":")
		if !ok {
			continue
		}
		out = append(out, row{Host: host, Port: port, Source: "naabu_txt"})
	}
	return out, sc.Err()
}

func loadFollowupSignals(path string) (map[string]string, error) {
	f, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer f.Close()
	signals := map[string]string{}
	sc := bufio.NewScanner(f)
	for sc.Scan() {
		var m map[string]any
		if json.Unmarshal(sc.Bytes(), &m) != nil {
			continue
		}
		host, _ := m["host"].(string)
		port := fmt.Sprint(m["port"])
		sig, _ := m["cybernet_signal"].(string)
		if host != "" && port != "" {
			signals[host+":"+port] = sig
		}
	}
	return signals, sc.Err()
}

func main() {
	naabuPath := flag.String("naabu", "", "naabu txt/json output path")
	followupPath := flag.String("followup", "", "followup JSONL path")
	outPath := flag.String("out", "", "normalized JSONL output")
	summaryPath := flag.String("summary", "", "summary JSON output")
	flag.Parse()

	if *naabuPath == "" || *outPath == "" {
		fmt.Fprintln(os.Stderr, "usage: sas-naabu-normalize -naabu PATH -out PATH [-followup PATH] [-summary PATH]")
		os.Exit(2)
	}

	rows, err := loadTxt(*naabuPath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "load naabu: %v\n", err)
		os.Exit(1)
	}

	signals := map[string]string{}
	if *followupPath != "" {
		signals, err = loadFollowupSignals(*followupPath)
		if err != nil {
			fmt.Fprintf(os.Stderr, "load followup: %v\n", err)
			os.Exit(1)
		}
	}

	if err := os.MkdirAll(filepath.Dir(*outPath), 0o755); err != nil {
		fmt.Fprintf(os.Stderr, "mkdir: %v\n", err)
		os.Exit(1)
	}
	out, err := os.Create(*outPath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "create out: %v\n", err)
		os.Exit(1)
	}
	defer out.Close()

	ts := time.Now().UTC().Format(time.RFC3339)
	enc := json.NewEncoder(out)
	for _, r := range rows {
		r.Timestamp = ts
		if sig, ok := signals[r.Host+":"+r.Port]; ok {
			r.CybernetSignal = sig
		}
		_ = enc.Encode(r)
	}

	if *summaryPath != "" {
		summary := map[string]any{
			"classification": "OK_NAABU_NORMALIZED",
			"row_count":      len(rows),
			"naabu_input":    *naabuPath,
			"generated_at":   ts,
		}
		b, _ := json.MarshalIndent(summary, "", "  ")
		_ = os.WriteFile(*summaryPath, b, 0o644)
	}
}
