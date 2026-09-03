package version

// Version is injected dynamically at build time from the root VERSION file
// via -ldflags "-X 'github.com/dwaipayanray95/project-archangel/backend/internal/version.Version=...'".
var Version = "1.1.0"
