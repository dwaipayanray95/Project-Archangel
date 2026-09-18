package devops

// ServiceItem represents a systemd service unit.
type ServiceItem struct {
	Name        string   `json:"name"`
	Description string   `json:"description"`
	LoadState   string   `json:"load_state"`
	ActiveState string   `json:"active_state"`
	SubState    string   `json:"sub_state"`
	Status      string   `json:"status"` // "active", "inactive", "failed"
	Meta        string   `json:"meta"`   // uptime, since date, or error reason
	Ok          bool     `json:"ok"`
	Actions     []string `json:"actions"` // "Restart", "Stop", "Start", "Logs"
}

// ScheduledItem represents a scheduled timer or cron task.
type ScheduledItem struct {
	Name     string   `json:"name"`
	Schedule string   `json:"schedule"` // e.g. "0 4 * * *" or "daily"
	LastRun  string   `json:"last_run"`
	NextRun  string   `json:"next_run"`
	Status   string   `json:"status"` // "ok", "failed", "pending"
	Meta     string   `json:"meta"`
	Ok       bool     `json:"ok"`
	Actions  []string `json:"actions"` // "Run now", "Edit"
}

// ProxyItem represents a reverse proxy route from Caddy.
type ProxyItem struct {
	Domain   string   `json:"domain"`
	Upstream string   `json:"upstream"`
	TLS      string   `json:"tls"`
	Status   string   `json:"status"` // "valid", "warning", "down"
	Meta     string   `json:"meta"`
	Ok       bool     `json:"ok"`
	Actions  []string `json:"actions"` // "Test", "Edit"
}

// DeploymentItem represents a deploy script or webhook task.
type DeploymentItem struct {
	Name     string   `json:"name"`
	Target   string   `json:"target"`
	LastRun  string   `json:"last_run"`
	Duration string   `json:"duration"`
	Status   string   `json:"status"` // "success", "failed", "running"
	Meta     string   `json:"meta"`
	Ok       bool     `json:"ok"`
	Actions  []string `json:"actions"` // "Run", "Logs"
}

// ActionResponse represents standard execution feedback.
type ActionResponse struct {
	Success bool   `json:"success"`
	Message string `json:"message"`
	Output  string `json:"output,omitempty"`
}

// CreateDeploymentRequest contains the filename and content for a deployment script.
type CreateDeploymentRequest struct {
	Name    string `json:"name"`
	Content string `json:"content"`
}

// DeploymentContentResponse contains the script content for editing.
type DeploymentContentResponse struct {
	Name    string `json:"name"`
	Content string `json:"content"`
}
