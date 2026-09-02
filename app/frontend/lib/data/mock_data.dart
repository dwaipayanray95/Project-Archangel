// Static mock data mirroring Archangel.dc.html's CONTAINERS / PROCS / DIRS /
// DEV / FEED_POOL / TERM_SESSIONS fixtures. Swap for real archangeld API
// calls behind the same shapes when the backend milestones land.
import 'package:flutter/material.dart';
import '../theme/tokens.dart';

class ContainerInfo {
  final String name;
  final String image;
  final String stack;
  final String state; // running | stopped
  final String uptime;
  final double cpu;
  final int memMb;
  final String memLabel;
  final String ports;
  final String cid;

  const ContainerInfo({
    required this.name,
    required this.image,
    required this.stack,
    required this.state,
    required this.uptime,
    required this.cpu,
    required this.memMb,
    required this.memLabel,
    required this.ports,
    required this.cid,
  });

  bool get running => state == 'running';
}

const stackMeta = <String, String>{
  'platform': 'caddy · postgres · pgbackrest',
  'immich': 'compose stack · 2 services',
  'media': 'compose stack · 1 service',
  'observability': 'compose stack · 2 services',
  'git': 'compose stack · 1 service',
  'home': 'compose stack · 1 service',
};

const stackOrder = <String>[
  'platform',
  'immich',
  'media',
  'observability',
  'git',
  'home',
];

const containers = <ContainerInfo>[
  ContainerInfo(name: 'caddy', image: 'caddy:2.8-alpine', stack: 'platform', state: 'running', uptime: 'up 42d', cpu: 0.4, memMb: 38, memLabel: '38 MB', ports: '80,443', cid: 'a91f4c2e8b17'),
  ContainerInfo(name: 'postgres', image: 'postgres:16.3-alpine', stack: 'platform', state: 'running', uptime: 'up 42d', cpu: 1.2, memMb: 412, memLabel: '412 MB', ports: '5432', cid: '7d3b0af5119c'),
  ContainerInfo(name: 'immich-server', image: 'ghcr.io/immich-app/immich-server:v1.108', stack: 'immich', state: 'running', uptime: 'up 12d', cpu: 3.8, memMb: 1430, memLabel: '1.4 GB', ports: '2283', cid: 'c04e7fa2d883'),
  ContainerInfo(name: 'immich-ml', image: 'ghcr.io/immich-app/immich-machine-learning:v1.108', stack: 'immich', state: 'running', uptime: 'up 12d', cpu: 0.9, memMb: 986, memLabel: '986 MB', ports: '—', cid: 'e5518bb7043a'),
  ContainerInfo(name: 'jellyfin', image: 'jellyfin/jellyfin:10.9.7', stack: 'media', state: 'running', uptime: 'up 8d', cpu: 2.1, memMb: 604, memLabel: '604 MB', ports: '8096', cid: '2b6c9d1e77f4'),
  ContainerInfo(name: 'forgejo', image: 'codeberg.org/forgejo/forgejo:7.0', stack: 'git', state: 'running', uptime: 'up 31d', cpu: 0.3, memMb: 218, memLabel: '218 MB', ports: '3000,2222', cid: 'f7a2130cd569'),
  ContainerInfo(name: 'homeassistant', image: 'ghcr.io/home-assistant/home-assistant:2026.8', stack: 'home', state: 'running', uptime: 'up 19d', cpu: 1.6, memMb: 512, memLabel: '512 MB', ports: '8123', cid: '9c41e6b2aa08'),
  ContainerInfo(name: 'grafana', image: 'grafana/grafana:11.1.0', stack: 'observability', state: 'running', uptime: 'up 42d', cpu: 0.5, memMb: 164, memLabel: '164 MB', ports: '3001', cid: '31d8ff70b4e2'),
  ContainerInfo(name: 'prometheus', image: 'prom/prometheus:v2.53.0', stack: 'observability', state: 'running', uptime: 'up 42d', cpu: 0.8, memMb: 386, memLabel: '386 MB', ports: '9090', cid: 'ba5c2e91d370'),
  ContainerInfo(name: 'pgbackrest', image: 'pgbackrest/pgbackrest:2.52', stack: 'platform', state: 'stopped', uptime: 'exited 6h', cpu: 0, memMb: 0, memLabel: '—', ports: '—', cid: '48e0c7135b9a'),
];

class ProcInfo {
  final int pid;
  final String name;
  final String user;
  final double cpu;
  final double mem;
  final String state; // R | S

  const ProcInfo({required this.pid, required this.name, required this.user, required this.cpu, required this.mem, required this.state});
}

const procs = <ProcInfo>[
  ProcInfo(pid: 1, name: 'systemd', user: 'root', cpu: 0.1, mem: 0.1, state: 'S'),
  ProcInfo(pid: 728, name: 'wg-crypt-wg0', user: 'root', cpu: 0.4, mem: 0.0, state: 'S'),
  ProcInfo(pid: 811, name: 'sshd', user: 'root', cpu: 0.0, mem: 0.1, state: 'S'),
  ProcInfo(pid: 987, name: 'dockerd', user: 'root', cpu: 1.9, mem: 1.4, state: 'S'),
  ProcInfo(pid: 1142, name: 'caddy', user: 'caddy', cpu: 0.6, mem: 0.3, state: 'S'),
  ProcInfo(pid: 1330, name: 'postgres: writer', user: 'postgres', cpu: 1.3, mem: 2.6, state: 'S'),
  ProcInfo(pid: 1418, name: 'node /app/dist/main', user: 'immich', cpu: 6.4, mem: 8.9, state: 'R'),
  ProcInfo(pid: 1502, name: 'python3 -m homeassistant', user: 'hass', cpu: 2.2, mem: 3.2, state: 'S'),
  ProcInfo(pid: 1689, name: 'jellyfin', user: 'jellyfin', cpu: 3.1, mem: 3.8, state: 'S'),
  ProcInfo(pid: 1744, name: 'prometheus', user: 'nobody', cpu: 0.9, mem: 2.4, state: 'S'),
  ProcInfo(pid: 1810, name: 'grafana-server', user: 'grafana', cpu: 0.5, mem: 1.0, state: 'S'),
  ProcInfo(pid: 1902, name: 'node_exporter', user: 'nobody', cpu: 0.2, mem: 0.2, state: 'S'),
  ProcInfo(pid: 2044, name: 'archangeld', user: 'root', cpu: 0.7, mem: 0.6, state: 'R'),
  ProcInfo(pid: 2210, name: 'containerd-shim', user: 'root', cpu: 0.1, mem: 0.2, state: 'S'),
];

class FsEntry {
  final String name;
  final String kind; // dir | file | log
  final String size;
  final String perms;
  final String mtime;
  const FsEntry({required this.name, required this.kind, required this.size, required this.perms, required this.mtime});
}

final Map<String, List<FsEntry>> dirs = {
  '/': const [
    FsEntry(name: 'etc', kind: 'dir', size: '—', perms: 'drwxr-xr-x', mtime: 'Aug 28 09:14'),
    FsEntry(name: 'home', kind: 'dir', size: '—', perms: 'drwxr-xr-x', mtime: 'Jul 22 03:11'),
    FsEntry(name: 'opt', kind: 'dir', size: '—', perms: 'drwxr-xr-x', mtime: 'Aug 12 21:02'),
    FsEntry(name: 'srv', kind: 'dir', size: '—', perms: 'drwxr-xr-x', mtime: 'Aug 30 17:45'),
    FsEntry(name: 'var', kind: 'dir', size: '—', perms: 'drwxr-xr-x', mtime: 'Sep 02 04:00'),
  ],
  '/var/log': const [
    FsEntry(name: 'caddy', kind: 'dir', size: '—', perms: 'drwxr-x---', mtime: 'Sep 02 06:12'),
    FsEntry(name: 'journal', kind: 'dir', size: '—', perms: 'drwxr-sr-x', mtime: 'Sep 02 06:14'),
    FsEntry(name: 'auth.log', kind: 'log', size: '1.4 MB', perms: '-rw-r-----', mtime: 'Sep 02 05:58'),
    FsEntry(name: 'dpkg.log', kind: 'log', size: '318 KB', perms: '-rw-r--r--', mtime: 'Sep 01 05:31'),
    FsEntry(name: 'immich.log', kind: 'log', size: '22.7 MB', perms: '-rw-r--r--', mtime: 'Sep 02 06:14'),
    FsEntry(name: 'kern.log', kind: 'log', size: '4.1 MB', perms: '-rw-r-----', mtime: 'Sep 02 03:44'),
    FsEntry(name: 'syslog', kind: 'log', size: '9.6 MB', perms: '-rw-r-----', mtime: 'Sep 02 06:14'),
    FsEntry(name: 'unattended-upgrades.log', kind: 'log', size: '88 KB', perms: '-rw-r--r--', mtime: 'Sep 01 05:32'),
    FsEntry(name: 'wtmp', kind: 'file', size: '46 KB', perms: '-rw-rw-r--', mtime: 'Sep 02 01:20'),
  ],
  '/var/log/caddy': const [
    FsEntry(name: 'access.log', kind: 'log', size: '61.2 MB', perms: '-rw-r-----', mtime: 'Sep 02 06:14'),
    FsEntry(name: 'access.log.1.gz', kind: 'file', size: '7.8 MB', perms: '-rw-r-----', mtime: 'Sep 01 00:00'),
    FsEntry(name: 'error.log', kind: 'log', size: '212 KB', perms: '-rw-r-----', mtime: 'Sep 02 04:21'),
  ],
  '/etc': const [
    FsEntry(name: 'caddy', kind: 'dir', size: '—', perms: 'drwxr-xr-x', mtime: 'Aug 30 17:45'),
    FsEntry(name: 'docker', kind: 'dir', size: '—', perms: 'drwx------', mtime: 'Jul 22 03:10'),
    FsEntry(name: 'systemd', kind: 'dir', size: '—', perms: 'drwxr-xr-x', mtime: 'Aug 28 09:14'),
    FsEntry(name: 'wireguard', kind: 'dir', size: '—', perms: 'drwx------', mtime: 'Jul 22 03:09'),
    FsEntry(name: 'fstab', kind: 'file', size: '742 B', perms: '-rw-r--r--', mtime: 'Jul 22 03:08'),
    FsEntry(name: 'hostname', kind: 'file', size: '15 B', perms: '-rw-r--r--', mtime: 'Jul 22 03:08'),
  ],
  '/home': const [
    FsEntry(name: 'ops', kind: 'dir', size: '—', perms: 'drwxr-x---', mtime: 'Sep 02 01:20'),
  ],
  '/srv/docker': const [
    FsEntry(name: 'immich', kind: 'dir', size: '—', perms: 'drwxr-xr-x', mtime: 'Aug 21 19:03'),
    FsEntry(name: 'jellyfin', kind: 'dir', size: '—', perms: 'drwxr-xr-x', mtime: 'Aug 25 11:40'),
    FsEntry(name: 'forgejo', kind: 'dir', size: '—', perms: 'drwxr-xr-x', mtime: 'Aug 02 08:15'),
    FsEntry(name: 'compose.yaml', kind: 'file', size: '6.4 KB', perms: '-rw-r--r--', mtime: 'Aug 30 17:45'),
    FsEntry(name: '.env', kind: 'file', size: '1.1 KB', perms: '-rw-------', mtime: 'Aug 30 17:44'),
  ],
};

final Map<String, List<String>> filePreviews = {
  'access.log': const [
    '10.8.0.4 - - [02/Sep/2026:06:14:02 +0000] "GET /api/asset/thumbnail/9f2c HTTP/2" 200 18422',
    '10.8.0.4 - - [02/Sep/2026:06:14:02 +0000] "GET /api/asset/thumbnail/a1d8 HTTP/2" 200 21044',
    '10.8.0.1 - - [02/Sep/2026:06:14:05 +0000] "POST /api/auth/validateToken HTTP/2" 200 41',
    '93.184.216.34 - - [02/Sep/2026:06:14:11 +0000] "GET /.env HTTP/1.1" 403 0',
    '93.184.216.34 - - [02/Sep/2026:06:14:11 +0000] "GET /wp-login.php HTTP/1.1" 403 0',
    '10.8.0.4 - - [02/Sep/2026:06:14:19 +0000] "GET /web/index.html HTTP/2" 200 3810',
  ],
  'error.log': const [
    '{"level":"error","ts":1789020112.4,"logger":"tls.obtain","msg":"will retry","error":"no OCSP staple"}',
    '{"level":"warn","ts":1789020341.9,"logger":"http.log.access","msg":"upstream roundtrip","status":502}',
    '{"level":"info","ts":1789020402.1,"logger":"tls","msg":"certificate obtained","identifier":"tv.mk1.dev"}',
  ],
  'compose.yaml': const [
    'services:',
    '  caddy:',
    '    image: caddy:2.8-alpine',
    '    restart: unless-stopped',
    '    ports: ["80:80", "443:443"]',
  ],
};

class LogLine {
  final String ts;
  final String level;
  final String source;
  final String text;
  const LogLine(this.ts, this.level, this.source, this.text);
}

final Map<String, List<LogLine>> containerLogs = {
  'caddy': const [
    LogLine('06:14:02', 'INFO', 'http.log.access', 'handled request GET /api/asset/thumbnail/9f2c status=200 dur=18ms'),
    LogLine('06:14:05', 'INFO', 'http.log.access', 'handled request POST /api/auth/validateToken status=200 dur=4ms'),
    LogLine('06:14:11', 'WARN', 'http.log.access', 'blocked probe GET /.env status=403 remote=93.184.216.34'),
    LogLine('06:14:19', 'INFO', 'http.log.access', 'handled request GET /web/index.html status=200 dur=2ms'),
    LogLine('06:14:26', 'INFO', 'reverse_proxy', 'upstream jellyfin:8096 selected policy=least_conn'),
    LogLine('06:14:38', 'INFO', 'tls.handshake', 'served certificate identifier=photos.mk1.dev sni_match=true'),
    LogLine('06:14:51', 'INFO', 'tls', 'certificate renewal check ok next=2026-11-14T00:00Z'),
  ],
  'postgres': const [
    LogLine('06:12:44', 'LOG', 'checkpoint', 'checkpoint starting: time'),
    LogLine('06:12:51', 'LOG', 'checkpoint', 'checkpoint complete: wrote 412 buffers (2.5%); sync=0.021 s'),
    LogLine('06:13:58', 'LOG', 'connection', 'connection authorized user=immich database=immich SSL off'),
  ],
};

class DevRow {
  final String name;
  final String meta;
  final String status;
  final bool ok;
  final List<String> actions;
  const DevRow({required this.name, required this.meta, required this.status, required this.ok, required this.actions});
}

const devServices = <DevRow>[
  DevRow(name: 'caddy.service', meta: 'enabled · active (running) since Jul 22 03:12 · 42d', status: 'active', ok: true, actions: ['Restart', 'Logs']),
  DevRow(name: 'docker.service', meta: 'enabled · active (running) since Jul 22 03:11 · 42d', status: 'active', ok: true, actions: ['Restart', 'Logs']),
  DevRow(name: 'postgresql.service', meta: 'enabled · active (running) since Jul 22 03:12 · 42d', status: 'active', ok: true, actions: ['Restart', 'Logs']),
  DevRow(name: 'wg-quick@wg0.service', meta: 'enabled · active (exited) since Jul 22 03:09 · 42d', status: 'active', ok: true, actions: ['Restart', 'Logs']),
  DevRow(name: 'archangeld.service', meta: 'enabled · active (running) since Aug 28 09:14 · 5d', status: 'active', ok: true, actions: ['Restart', 'Logs']),
  DevRow(name: 'unattended-upgrades.service', meta: 'enabled · inactive (dead) · last run Sep 01 05:31', status: 'inactive', ok: false, actions: ['Start', 'Logs']),
];

const devScheduled = <DevRow>[
  DevRow(name: 'pg_dump immich', meta: '15 2 * * * · last Sep 02 02:15 (ok, 41s) · next Sep 03 02:15', status: 'ok', ok: true, actions: ['Run now', 'Edit']),
  DevRow(name: 'restic backup /srv', meta: '0 4 * * * · last Sep 02 04:00 (ok, 6m 12s) · next Sep 03 04:00', status: 'ok', ok: true, actions: ['Run now', 'Edit']),
  DevRow(name: 'immich thumbnail prune', meta: '40 3 * * * · last Sep 02 03:40 (ok, 18s) · next Sep 03 03:40', status: 'ok', ok: true, actions: ['Run now', 'Edit']),
  DevRow(name: 'docker image prune -af', meta: '0 6 * * 0 · last Aug 30 06:00 (freed 2.1 GB) · next Sep 06 06:00', status: 'ok', ok: true, actions: ['Run now', 'Edit']),
];

const devProxy = <DevRow>[
  DevRow(name: 'mk1.dev', meta: '→ 127.0.0.1:8080 · cert valid 73d · HTTP/3 on', status: 'valid', ok: true, actions: ['Edit', 'Test']),
  DevRow(name: 'photos.mk1.dev', meta: '→ immich-server:2283 · cert valid 73d · 12.4k req/24h', status: 'valid', ok: true, actions: ['Edit', 'Test']),
  DevRow(name: 'tv.mk1.dev', meta: '→ jellyfin:8096 · cert valid 73d · 1.8k req/24h', status: 'valid', ok: true, actions: ['Edit', 'Test']),
  DevRow(name: 'git.mk1.dev', meta: '→ forgejo:3000 · cert valid 73d · 402 req/24h', status: 'valid', ok: true, actions: ['Edit', 'Test']),
];

const devDeployments = <DevRow>[
  DevRow(name: 'deploy-mk1-site', meta: 'main@4f2c9ab · Sep 01 21:44 · 38s · triggered by forgejo hook', status: 'success', ok: true, actions: ['Run', 'Output']),
  DevRow(name: 'deploy-archangeld', meta: 'main@a17de40 · Aug 28 09:14 · 1m 04s · manual', status: 'success', ok: true, actions: ['Run', 'Output']),
  DevRow(name: 'compose-pull-all', meta: 'Aug 30 17:45 · 2m 51s · pulled 4 images', status: 'success', ok: true, actions: ['Run', 'Output']),
];

class FeedItem {
  final String actor;
  final String text;
  final String detail;
  final Color color;
  final String ago;
  const FeedItem(this.actor, this.text, this.detail, this.color, this.ago);
}

final feedPool = <FeedItem>[
  FeedItem('caddy', 'renewed certificate for', 'tv.mk1.dev · valid until 2026-11-14', AxColors.accent, '2m'),
  FeedItem('immich-server', 'finished thumbnail batch', '4 assets · 812ms', AxColors.info, '4m'),
  FeedItem('restic', 'completed backup of /srv', '2.4 GB new · 6m 12s', AxColors.accent, '11m'),
  FeedItem('wg0', 'peer handshake from', '84.22.19.7:47311 · macbook', AxColors.accent, '18m'),
  FeedItem('postgres', 'autovacuum on immich.exif', 'removed 2841 row versions', AxColors.info, '26m'),
  FeedItem('caddy', 'blocked probe request', 'GET /.env · 403 · 93.184.216.34', AxColors.warn, '31m'),
  FeedItem('archangeld', 'heartbeat ok', 'agent 0.9.4 · rtt 12ms', AxColors.accent, '38m'),
  FeedItem('docker', 'health check passed', '9 containers · all healthy', AxColors.accent, '52m'),
];

class TermSession {
  final String label;
  final Color dot;
  final String meta;
  final String prompt;
  final List<List<String>> lines; // [text, kind] kind: p(rompt)/o(utput)/h(eader)
  const TermSession({required this.label, required this.dot, required this.meta, required this.prompt, required this.lines});
}

final termSessions = <TermSession>[
  TermSession(
    label: 'ops@MK1: ~',
    dot: AxColors.accent,
    meta: 'pty/0 · 148×38 · bash 5.2',
    prompt: 'ops@Archangel-MK1:~\$ ',
    lines: const [
      ['ops@Archangel-MK1:~\$ uptime', 'p'],
      [' 06:15:12 up 42 days,  6:18,  1 user,  load average: 0.34, 0.41, 0.38', 'o'],
      ['ops@Archangel-MK1:~\$ docker compose -f /srv/docker/compose.yaml ps', 'p'],
      ['NAME             IMAGE                          STATUS         PORTS', 'h'],
      ['caddy            caddy:2.8-alpine              Up 42 days     0.0.0.0:80->80/tcp', 'o'],
      ['postgres         postgres:16.3-alpine          Up 42 days     5432/tcp', 'o'],
      ['immich-server    immich-server:v1.108          Up 12 days     2283/tcp', 'o'],
      ['ops@Archangel-MK1:~\$ ', 'p'],
    ],
  ),
  TermSession(
    label: 'root@MK1: /var/log',
    dot: AxColors.warn,
    meta: 'pty/1 · 148×38 · bash 5.2',
    prompt: 'root@Archangel-MK1:/var/log# ',
    lines: const [
      ['root@Archangel-MK1:/var/log# journalctl -u caddy -n 3 --no-pager', 'p'],
      ['Sep 02 06:14:11 Archangel-MK1 caddy[1142]: blocked probe path=/.env', 'o'],
      ['Sep 02 06:14:31 Archangel-MK1 caddy[1142]: handled request status=200', 'o'],
      ['root@Archangel-MK1:/var/log# wg show wg0', 'p'],
      ['interface: wg0', 'h'],
      ['  latest handshake: 41 seconds ago', 'o'],
      ['root@Archangel-MK1:/var/log# ', 'p'],
    ],
  ),
];
