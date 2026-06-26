package preflight

import (
	"fmt"
	"os/exec"
	"runtime"
	"strings"
)

type Result struct {
	NaabuPath string
	Notes     []string
}

func CheckNaabuCLI() (Result, error) {
	path, err := exec.LookPath("naabu")
	if err != nil {
		path, err = exec.LookPath("naabu.exe")
	}
	if err != nil {
		return Result{}, fmt.Errorf("naabu not found in PATH (install via survey/sas-ensure-naabu.sh on WAB or pass -naabu)")
	}
	out, err := exec.Command(path, "-version").CombinedOutput()
	if err != nil {
		return Result{}, fmt.Errorf("naabu -version failed: %v (%s)", err, strings.TrimSpace(string(out)))
	}
	notes := []string{strings.TrimSpace(string(out))}
	if runtime.GOOS == "windows" {
		notes = append(notes, "Windows SYN scans require Npcap installed")
	}
	return Result{NaabuPath: path, Notes: notes}, nil
}
