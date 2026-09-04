//go:build !windows

package system

import "syscall"

func getDiskSpace(path string) (total uint64, free uint64, avail uint64, used uint64, err error) {
	var stat syscall.Statfs_t
	if err := syscall.Statfs(path, &stat); err != nil {
		return 0, 0, 0, 0, err
	}
	total = stat.Blocks * uint64(stat.Bsize)
	free = stat.Bfree * uint64(stat.Bsize)
	avail = stat.Bavail * uint64(stat.Bsize)
	if total > free {
		used = total - free
	}
	return total, free, avail, used, nil
}
