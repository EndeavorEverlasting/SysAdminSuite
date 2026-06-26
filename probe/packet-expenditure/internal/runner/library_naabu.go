//go:build naabu_lib

package runner

import (
	"context"
	"fmt"

	"github.com/EndeavorEverlasting/SysAdminSuite/probe/packet-expenditure/internal/config"
	"github.com/EndeavorEverlasting/SysAdminSuite/probe/packet-expenditure/internal/evidence"
	"github.com/projectdiscovery/naabu/v2/pkg/result"
	"github.com/projectdiscovery/naabu/v2/pkg/runner"
)

func RunLibrary(ctx context.Context, listPath string, p config.Profile, w *evidence.Writer) error {
	_ = ctx
	opts := &runner.Options{
		HostsFile:           listPath,
		Threads:             p.Threads,
		Rate:                p.Rate,
		ScanType:            p.ScanType,
		JSON:                true,
		Silent:              true,
		ExcludeCDN:          p.ExcludeCDN,
		DisableUpdateCheck:  p.DisableUpdateCheck,
		Stream:              p.Stream,
		Passive:             p.Passive,
		SmartScan:           p.SmartScan,
		PredictionThreshold: p.PredictionThreshold,
	}
	if p.PortMode == "explicit" {
		opts.Ports = p.ExplicitPortList()
	} else {
		opts.TopPorts = p.TopPorts
	}
	opts.OnResult = func(hr *result.HostResult) {
		for _, port := range hr.Ports {
			_ = w.WriteHostPort(hr.Host, port.Port, port.Protocol.String(), "naabu-library")
		}
	}
	r, err := runner.NewRunner(opts)
	if err != nil {
		return fmt.Errorf("naabu library runner: %w", err)
	}
	defer r.Close()
	if err := r.RunEnumeration(ctx); err != nil {
		return fmt.Errorf("naabu enumeration: %w", err)
	}
	return nil
}
