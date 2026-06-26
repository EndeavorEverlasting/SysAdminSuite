//go:build !naabu_lib

package runner

import (
	"context"
	"fmt"

	"github.com/EndeavorEverlasting/SysAdminSuite/probe/packet-expenditure/internal/config"
	"github.com/EndeavorEverlasting/SysAdminSuite/probe/packet-expenditure/internal/evidence"
)

func RunLibrary(ctx context.Context, listPath string, p config.Profile, w *evidence.Writer) error {
	_ = ctx
	_ = listPath
	_ = p
	_ = w
	return fmt.Errorf("naabu library engine not compiled: rebuild with -tags naabu_lib after go mod tidy, or use -engine cli")
}
