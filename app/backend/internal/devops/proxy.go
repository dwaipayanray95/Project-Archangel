package devops

import (
	"bufio"
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"strings"
	"time"
)

// ListProxy inspects Caddy configuration via local API or Caddyfile.
func ListProxy() ([]ProxyItem, error) {
	// 1. Try Caddy local admin API (default: http://localhost:2019/config/apps/http/servers)
	client := &http.Client{Timeout: 1 * time.Second}
	resp, err := client.Get("http://localhost:2019/config/apps/http/servers")
	if err == nil && resp.StatusCode == http.StatusOK {
		defer resp.Body.Close()
		var servers map[string]struct {
			Routes []struct {
				Match []struct {
					Host []string `json:"host"`
				} `json:"match"`
				Handle []struct {
					Handler   string `json:"handler"`
					Upstreams []struct {
						Dial string `json:"dial"`
					} `json:"upstreams"`
				} `json:"handle"`
			} `json:"routes"`
		}
		if err := json.NewDecoder(resp.Body).Decode(&servers); err == nil {
			var items []ProxyItem
			for _, srv := range servers {
				for _, r := range srv.Routes {
					for _, m := range r.Match {
						for _, host := range m.Host {
							upstream := "reverse_proxy"
							for _, h := range r.Handle {
								if len(h.Upstreams) > 0 {
									upstream = h.Upstreams[0].Dial
								}
							}
							items = append(items, ProxyItem{
								Domain:   host,
								Upstream: "→ " + upstream,
								TLS:      "managed",
								Status:   "valid",
								Meta:     "→ " + upstream + " · TLS active",
								Ok:       true,
								Actions:  []string{"Test"},
							})
						}
					}
				}
			}
			if len(items) > 0 {
				return items, nil
			}
		}
	}

	// 2. Parse /etc/caddy/Caddyfile or /srv/Caddyfile if present
	caddyPaths := []string{"/etc/caddy/Caddyfile", "/srv/docker/caddy/Caddyfile", "/srv/caddy/Caddyfile"}
	for _, cp := range caddyPaths {
		if f, err := os.Open(cp); err == nil {
			defer f.Close()
			return parseCaddyfile(f), nil
		}
	}

	return []ProxyItem{}, nil
}

func parseCaddyfile(f *os.File) []ProxyItem {
	var items []ProxyItem
	scanner := bufio.NewScanner(f)

	currentDomain := ""
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}

		if strings.HasSuffix(line, "{") {
			domain := strings.TrimSpace(strings.TrimSuffix(line, "{"))
			if !strings.HasPrefix(domain, ":") && !strings.Contains(domain, " ") {
				currentDomain = domain
			}
		} else if strings.HasPrefix(line, "reverse_proxy") && currentDomain != "" {
			parts := strings.Fields(line)
			upstream := "upstream"
			if len(parts) >= 2 {
				upstream = parts[1]
			}
			items = append(items, ProxyItem{
				Domain:   currentDomain,
				Upstream: "→ " + upstream,
				TLS:      "auto HTTPS",
				Status:   "valid",
				Meta:     "→ " + upstream + " · cert managed",
				Ok:       true,
				Actions:  []string{"Test"},
			})
			currentDomain = ""
		}
	}
	return items
}

// TestProxyUpstream checks reachability of a configured proxy domain.
func TestProxyUpstream(domain string) (bool, string) {
	// Guard against SSRF: check domain syntax first
	domain = strings.TrimSpace(domain)
	if domain == "" || strings.Contains(domain, "/") || strings.Contains(domain, " ") || strings.Contains(domain, "@") {
		return false, "invalid domain name"
	}

	// Verify that the domain actually belongs to our configured reverse proxy routes
	activeRoutes, err := ListProxy()
	if err == nil && len(activeRoutes) > 0 {
		matched := false
		for _, r := range activeRoutes {
			if strings.EqualFold(r.Domain, domain) {
				matched = true
				break
			}
		}
		if !matched {
			return false, "unconfigured domain: only registered proxy routes can be tested"
		}
	}

	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()

	req, err := http.NewRequestWithContext(ctx, http.MethodHead, "http://"+domain, nil)
	if err != nil {
		return false, err.Error()
	}

	client := &http.Client{
		Timeout: 2 * time.Second,
		CheckRedirect: func(req *http.Request, via []*http.Request) error {
			return http.ErrUseLastResponse // Don't follow redirects to arbitrary internal hosts
		},
	}
	resp, err := client.Do(req)
	if err != nil {
		return false, "timeout or unreachable: " + err.Error()
	}
	defer resp.Body.Close()

	return resp.StatusCode < 500, fmt.Sprintf("HTTP %d OK", resp.StatusCode)
}
