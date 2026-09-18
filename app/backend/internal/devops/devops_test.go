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

func TestServiceActionRejectsUnmanagedUnits(t *testing.T) {
	for _, name := range []string{"sshd.service", "network.target", "random-thing.service", "--user", ""} {
		if err := ServiceAction(name, "restart"); err == nil {
			t.Errorf("ServiceAction(%q, restart) = nil error, want rejection (not in managedUnits allowlist)", name)
		}
	}
}

func TestServiceActionRejectsUnsupportedAction(t *testing.T) {
	if err := ServiceAction("docker.service", "enable"); err == nil {
		t.Errorf("ServiceAction(docker.service, enable) = nil error, want rejection")
	}
}

func TestTriggerScheduledOnlyAcceptsTimers(t *testing.T) {
	if err := TriggerScheduled("docker.service"); err == nil {
		t.Errorf("TriggerScheduled(docker.service) = nil error, want rejection (not a .timer)")
	}
}

func TestRunDeploymentRejectsTraversalAndBadNames(t *testing.T) {
	for _, name := range []string{"../../etc/passwd", "/etc/passwd", "deploy.sh; rm -rf /", "notascript.txt"} {
		if _, err := RunDeployment(name); err == nil {
			t.Errorf("RunDeployment(%q) = nil error, want rejection", name)
		}
	}
}

func TestTestProxyUpstreamRejectsUnconfiguredDomain(t *testing.T) {
	// Fail-closed: whether or not this test runner has a readable Caddy
	// config, a domain that isn't a known/registered route must never be
	// probed - this is the regression guard for the SSRF gap where an
	// unreadable/empty route list used to skip the allowlist check entirely.
	ok, msg := TestProxyUpstream("169.254.169.254")
	if ok {
		t.Errorf("TestProxyUpstream(169.254.169.254) = ok, want rejected as unconfigured/unverifiable")
	}
	t.Logf("rejection message: %s", msg)
}

func TestTestProxyUpstreamRejectsMalformedDomain(t *testing.T) {
	for _, domain := range []string{"evil.com/../internal", "host name", "user@host"} {
		if ok, _ := TestProxyUpstream(domain); ok {
			t.Errorf("TestProxyUpstream(%q) = ok, want rejected as invalid", domain)
		}
	}
}

func TestDeploymentCRUDAndValidation(t *testing.T) {
	// Bad names should be rejected
	for _, bad := range []string{"../../evil.sh", "deploy;rm -rf.sh", "bad.txt", ""} {
		if err := CreateOrUpdateDeployment(bad, "echo 1"); err == nil {
			t.Errorf("CreateOrUpdateDeployment(%q) expected error, got nil", bad)
		}
		if _, err := GetDeploymentContent(bad); err == nil {
			t.Errorf("GetDeploymentContent(%q) expected error, got nil", bad)
		}
		if err := DeleteDeployment(bad); err == nil {
			t.Errorf("DeleteDeployment(%q) expected error, got nil", bad)
		}
	}

	// Good name can be created, read, and deleted
	testName := "test-archangel-deploy.sh"
	testContent := "#!/bin/sh\necho 'hello deploy'\n"
	err := CreateOrUpdateDeployment(testName, testContent)
	if err != nil {
		t.Logf("CreateOrUpdateDeployment failed (might be read-only filesystem on /srv/deploy): %v", err)
	} else {
		defer DeleteDeployment(testName)

		content, err := GetDeploymentContent(testName)
		if err != nil {
			t.Errorf("GetDeploymentContent failed: %v", err)
		}
		if content != testContent {
			t.Errorf("expected content %q, got %q", testContent, content)
		}

		if err := DeleteDeployment(testName); err != nil {
			t.Errorf("DeleteDeployment failed: %v", err)
		}
	}
}
