package params

// Attack experiment (backup-block propagation timing) configuration.
//
// The whole experiment is driven by environment variables so the same geth
// binary can play any role across the three datacenters. Nothing here changes
// consensus rules (backoff etc.) — it only gates who seals at the attack slot
// and how the two sibling backup blocks (b1/b2) are routed/timed at broadcast.
//
//	ATTACK_SLOT          attack block height t (>0 enables the experiment)
//	ATTACK_REGION        this node's datacenter: "uk" | "us" | "sg"
//	ATTACK_B1            UK backup validator whose block (b1) targets Singapore
//	ATTACK_B2            UK backup validator whose block (b2) targets US
//	ATTACK_INTURN_SILENCE  "true"/"false" — silence the in-turn validator at slot t (default true)
//	LEAD_TIME_MS         extra delay (ms) added before sending b1 -> Singapore
//	ATTACK_SG_IPS        comma-separated public IPs of the Singapore host(s)
//	ATTACK_US_IPS        comma-separated public IPs of the US host(s)
//	ATTACK_UK_IPS        comma-separated public IPs of the UK host(s)

import (
	"net"
	"os"
	"strconv"
	"strings"
	"sync"

	"github.com/ethereum/go-ethereum/common"
)

// AttackConfig holds the parsed, immutable experiment configuration.
type AttackConfig struct {
	Active        bool
	Slot          uint64
	Region        string // "uk" | "us" | "sg" | ""
	B1            common.Address
	B2            common.Address
	InturnSilence bool
	LeadTimeMs    int

	sgIPs map[string]struct{}
	usIPs map[string]struct{}
	ukIPs map[string]struct{}
}

var (
	attackCfg  *AttackConfig
	attackOnce sync.Once
)

// Attack returns the process-wide attack configuration, parsed once from env.
func Attack() *AttackConfig {
	attackOnce.Do(func() { attackCfg = loadAttackConfig() })
	return attackCfg
}

func loadAttackConfig() *AttackConfig {
	c := &AttackConfig{
		Region:        strings.ToLower(strings.TrimSpace(os.Getenv("ATTACK_REGION"))),
		InturnSilence: true,
		sgIPs:         parseIPSet(os.Getenv("ATTACK_SG_IPS")),
		usIPs:         parseIPSet(os.Getenv("ATTACK_US_IPS")),
		ukIPs:         parseIPSet(os.Getenv("ATTACK_UK_IPS")),
	}
	if v, err := strconv.ParseUint(strings.TrimSpace(os.Getenv("ATTACK_SLOT")), 10, 64); err == nil && v > 0 {
		c.Slot = v
		c.Active = true
	}
	if v := strings.TrimSpace(os.Getenv("ATTACK_B1")); v != "" {
		c.B1 = common.HexToAddress(v)
	}
	if v := strings.TrimSpace(os.Getenv("ATTACK_B2")); v != "" {
		c.B2 = common.HexToAddress(v)
	}
	if v := strings.TrimSpace(os.Getenv("ATTACK_INTURN_SILENCE")); v != "" {
		c.InturnSilence = v == "1" || strings.EqualFold(v, "true")
	}
	if v, err := strconv.Atoi(strings.TrimSpace(os.Getenv("LEAD_TIME_MS"))); err == nil {
		c.LeadTimeMs = v
	}
	return c
}

func parseIPSet(raw string) map[string]struct{} {
	set := make(map[string]struct{})
	for _, p := range strings.Split(raw, ",") {
		p = strings.TrimSpace(p)
		if p != "" {
			set[p] = struct{}{}
		}
	}
	return set
}

// ActiveAt reports whether the experiment is enabled and height is the attack slot.
func (c *AttackConfig) ActiveAt(height uint64) bool {
	return c != nil && c.Active && height == c.Slot
}

// IsB1 reports whether addr is the UK backup whose block is routed to Singapore.
func (c *AttackConfig) IsB1(addr common.Address) bool {
	return c != nil && c.B1 != (common.Address{}) && addr == c.B1
}

// IsB2 reports whether addr is the UK backup whose block is routed to the US.
func (c *AttackConfig) IsB2(addr common.Address) bool {
	return c != nil && c.B2 != (common.Address{}) && addr == c.B2
}

// LabelOf maps a block coinbase to the experiment label for logging.
func (c *AttackConfig) LabelOf(addr common.Address) string {
	switch {
	case c.IsB1(addr):
		return "b1"
	case c.IsB2(addr):
		return "b2"
	default:
		return "other"
	}
}

// RegionOfIP classifies a bare IP string into "uk"/"us"/"sg" or "".
func (c *AttackConfig) RegionOfIP(ip string) string {
	if c == nil {
		return ""
	}
	if _, ok := c.sgIPs[ip]; ok {
		return "sg"
	}
	if _, ok := c.usIPs[ip]; ok {
		return "us"
	}
	if _, ok := c.ukIPs[ip]; ok {
		return "uk"
	}
	return ""
}

// RegionOfAddr classifies a peer's remote net.Addr string ("ip:port") by region.
func (c *AttackConfig) RegionOfAddr(addr string) string {
	if addr == "" {
		return ""
	}
	host, _, err := net.SplitHostPort(addr)
	if err != nil {
		host = addr
	}
	return c.RegionOfIP(host)
}
