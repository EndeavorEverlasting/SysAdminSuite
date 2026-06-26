package targets

import (
	"bufio"
	"fmt"
	"net"
	"os"
	"strings"
)

var docCIDRs = []string{"192.0.2.0/24", "198.51.100.0/24", "203.0.113.0/24"}

func Load(path string, maxTargets int, allowPublic bool) ([]string, error) {
	f, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer f.Close()

	var out []string
	seen := map[string]struct{}{}
	sc := bufio.NewScanner(f)
	for sc.Scan() {
		line := strings.TrimSpace(strings.SplitN(sc.Text(), "#", 2)[0])
		if line == "" {
			continue
		}
		if strings.Contains(line, "/") {
			return nil, fmt.Errorf("CIDR not allowed in target list: %q", line)
		}
		host := line
		if ip := net.ParseIP(host); ip != nil {
			if !allowPublic && isBlockedTargetIP(ip) {
				return nil, fmt.Errorf("public or documentation IP rejected: %s", host)
			}
		}
		if _, ok := seen[host]; ok {
			continue
		}
		seen[host] = struct{}{}
		out = append(out, host)
		if len(out) > maxTargets {
			return nil, fmt.Errorf("target count %d exceeds maxTargets %d", len(out), maxTargets)
		}
	}
	if err := sc.Err(); err != nil {
		return nil, err
	}
	if len(out) == 0 {
		return nil, fmt.Errorf("empty target list")
	}
	return out, nil
}

func isBlockedTargetIP(ip net.IP) bool {
	v4 := ip.To4()
	if v4 == nil {
		return true
	}
	if isPrivateRFC1918(v4) {
		return false
	}
	if v4[0] == 100 && v4[1] >= 64 && v4[1] <= 127 {
		return false
	}
	if v4[0] == 169 && v4[1] == 254 {
		return false
	}
	if v4[0] == 127 {
		return false
	}
	for _, cidr := range docCIDRs {
		_, n, _ := net.ParseCIDR(cidr)
		if n != nil && n.Contains(v4) {
			return true
		}
	}
	if v4[0] >= 224 {
		return true
	}
	return true
}

func isPrivateRFC1918(v4 net.IP) bool {
	if v4[0] == 10 {
		return true
	}
	if v4[0] == 172 && v4[1] >= 16 && v4[1] <= 31 {
		return true
	}
	if v4[0] == 192 && v4[1] == 168 {
		return true
	}
	return false
}
