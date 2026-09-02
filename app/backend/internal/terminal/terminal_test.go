package terminal

import (
	"sync"
	"testing"
)

// TestTryAcquireSessionCapIsHard fires many concurrent acquire attempts at
// once and asserts the count granted never exceeds MaxSessions. This is
// specifically a regression test for a real bug: a naive
// "if Load() >= Max { reject }; Add(1)" check has a window where two
// goroutines can both pass the check before either increments, letting the
// cap slip. tryAcquireSession must check-and-reserve atomically instead.
func TestTryAcquireSessionCapIsHard(t *testing.T) {
	activeSessions.Store(0)
	defer activeSessions.Store(0)

	const attempts = 50
	var wg sync.WaitGroup
	var granted int32Counter

	// A start gate: every goroutine is spun up and parked on the closed
	// channel receive before any of them call tryAcquireSession, so they
	// actually collide on the same instant instead of running one after
	// another - launching goroutines in a plain loop without this very
	// reliably fails to reproduce the race at all (confirmed by hand:
	// the pre-fix naive Load-then-Add version passed 20/20 runs of this
	// test without a start gate).
	start := make(chan struct{})
	wg.Add(attempts)
	for i := 0; i < attempts; i++ {
		go func() {
			defer wg.Done()
			<-start
			if tryAcquireSession() {
				granted.inc()
			}
		}()
	}
	close(start)
	wg.Wait()

	if got := granted.load(); got != MaxSessions {
		t.Fatalf("granted %d sessions concurrently, want exactly %d (MaxSessions)", got, MaxSessions)
	}
	if cur := activeSessions.Load(); cur != MaxSessions {
		t.Fatalf("activeSessions ended at %d, want %d", cur, MaxSessions)
	}
}

// int32Counter is a tiny thread-safe counter, local to this test file - no
// need to pull in a dependency for one counter.
type int32Counter struct {
	mu sync.Mutex
	n  int32
}

func (c *int32Counter) inc() {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.n++
}

func (c *int32Counter) load() int32 {
	c.mu.Lock()
	defer c.mu.Unlock()
	return c.n
}
