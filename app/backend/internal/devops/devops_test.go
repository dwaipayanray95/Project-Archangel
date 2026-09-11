package devops

import (
	"testing"
)

func TestListServices(t *testing.T) {
	services, err := ListServices()
	if err != nil {
		t.Fatalf("ListServices error: %v", err)
	}
	if len(services) == 0 {
		t.Logf("no services returned on this test runner")
	}
}

func TestListScheduled(t *testing.T) {
	items, err := ListScheduled()
	if err != nil {
		t.Fatalf("ListScheduled error: %v", err)
	}
	t.Logf("Found %d scheduled items", len(items))
}

func TestListProxy(t *testing.T) {
	items, err := ListProxy()
	if err != nil {
		t.Fatalf("ListProxy error: %v", err)
	}
	t.Logf("Found %d proxy items", len(items))
}

func TestListDeployments(t *testing.T) {
	items, err := ListDeployments()
	if err != nil {
		t.Fatalf("ListDeployments error: %v", err)
	}
	t.Logf("Found %d deployment items", len(items))
}
