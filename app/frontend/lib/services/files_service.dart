import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../data/mock_data.dart';
import '../models/file_entry.dart';
import 'archangeld_connection.dart';

class FilesService extends ChangeNotifier {
  // Empty means "wherever the server's configured files_root is" - the
  // backend maps an empty path query param to that root itself (see
  // ListHandler). A hardcoded path like '/var/log' would 403 on first
  // load for anyone whose files_root doesn't happen to contain it.
  //
  // Only ever set to a path that has actually been LOADED successfully
  // (200, cache hit, or mock fallback) - never to a path a request is
  // merely attempting. A failed load leaves this at the last place the
  // user was actually standing, so breadcrumbs/sidebar selection don't
  // relabel a rejected destination as "current" - see loadDirectory.
  String _currentPath = '';
  String get currentPath => _currentPath;

  // The server's configured files_root, as reported by the listing
  // response the first time the root itself (path == '') is loaded
  // successfully - the frontend has no other way to know this string.
  // Used to label the sidebar's root entry with the real jail boundary
  // instead of a generic "Root".
  String? _rootPath;
  String? get rootPath => _rootPath;

  // Top-level subdirectories of whatever's currently listed - shown as
  // sidebar shortcuts. Derived straight from the current listing (never
  // a separately-tracked/stale list) so it can never point outside
  // files_root: it's built from entries the server itself just
  // returned for a path that was actually allowed.
  List<FileEntryModel> get quickJumpDirs =>
      (_listing?.entries ?? const []).where((e) => e.isDir).take(8).toList();

  bool _showHidden = false;
  bool get showHidden => _showHidden;
  void toggleShowHidden() {
    _showHidden = !_showHidden;
    notifyListeners();
  }

  bool _loading = false;
  bool get loading => _loading;

  String? _error;
  String? get error => _error;

  DirectoryListingModel? _listing;
  DirectoryListingModel? get listing => _listing;

  // In-memory directory cache: path -> listing (for instant navigation)
  final Map<String, DirectoryListingModel> _dirCache = {};

  // File preview cache and state
  String? _activePreviewPath;
  String? get activePreviewPath => _activePreviewPath;

  bool _previewLoading = false;
  bool get previewLoading => _previewLoading;

  FileContentResult? _fileContent;
  FileContentResult? get fileContent => _fileContent;

  ArchangeldConnection? _backend;

  void init(ArchangeldConnection backend) {
    _backend = backend;
    loadDirectory(_currentPath);
  }

  Future<void> loadDirectory(String path, {bool forceRefresh = false}) async {
    // Instant UI render from cache if available - a cache hit is a
    // successful load (of a path we've already been to), so it does
    // commit _currentPath.
    if (!forceRefresh && _dirCache.containsKey(path)) {
      _currentPath = path;
      _listing = _dirCache[path];
      _error = null;
      notifyListeners();
      return;
    }

    _loading = true;
    _error = null;
    notifyListeners();

    final backend = _backend;
    if (backend == null || !backend.isPaired || backend.token == null) {
      _currentPath = path;
      _loadMockDirectory(path);
      notifyListeners();
      return;
    }

    try {
      final res = await http.get(
        backend.filesListHttpUri(path),
        headers: {'X-Archangel-Token': backend.token!},
      );

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final newListing = DirectoryListingModel.fromJson(data);
        _currentPath = path;
        _listing = newListing;
        _dirCache[path] = newListing;
        _error = null;
        if (path.isEmpty) _rootPath = newListing.path;
      } else if (res.statusCode == 403) {
        // A rejected destination is never "where we are" - leave
        // _currentPath (and therefore breadcrumbs/sidebar selection)
        // at the last successfully loaded directory. _error alone
        // carries this failure to the content pane.
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final failedListing = DirectoryListingModel.fromJson(data);
        _error = failedListing.error ?? 'Permission denied';
      } else {
        if (!_dirCache.containsKey(path)) {
          _currentPath = path;
          _loadMockDirectory(path);
        }
      }
    } catch (e) {
      debugPrint('Error listing directory $path: $e');
      if (!_dirCache.containsKey(path)) {
        _currentPath = path;
        _loadMockDirectory(path);
      }
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  void _loadMockDirectory(String path) {
    final mockEntries = dirs[path];
    if (mockEntries != null) {
      final entries = mockEntries.map((e) => FileEntryModel(
        name: e.name,
        path: path == '/' ? '/${e.name}' : '$path/${e.name}',
        kind: e.kind,
        sizeBytes: 0,
        size: e.size,
        perms: e.perms,
        mtime: e.mtime,
      )).toList();

      _listing = DirectoryListingModel(
        path: path,
        parent: path == '/' ? '/' : path.substring(0, path.lastIndexOf('/')),
        entries: entries,
        totalEntries: entries.length,
        readable: true,
      );
      _error = null;
    } else {
      _listing = DirectoryListingModel(
        path: path,
        parent: '/',
        entries: const [],
        totalEntries: 0,
        readable: true,
      );
    }
    if (path.isEmpty) _rootPath ??= '/';
    _loading = false;
  }

  Future<void> openFilePreview(String path) async {
    _activePreviewPath = path;
    _previewLoading = true;
    _fileContent = null;
    notifyListeners();

    final backend = _backend;
    if (backend == null || !backend.isPaired || backend.token == null) {
      _loadMockPreview(path);
      return;
    }

    try {
      final res = await http.get(
        backend.filesReadHttpUri(path, lines: 400),
        headers: {'X-Archangel-Token': backend.token!},
      );

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        _fileContent = FileContentResult.fromJson(data);
      } else {
        _loadMockPreview(path);
      }
    } catch (e) {
      debugPrint('Error reading file preview $path: $e');
      _loadMockPreview(path);
    } finally {
      _previewLoading = false;
      notifyListeners();
    }
  }

  void _loadMockPreview(String path) {
    final fileName = path.split('/').last;
    final mockLines = filePreviews[fileName] ?? const ['(no preview available for this file type)'];
    _fileContent = FileContentResult(
      path: path,
      name: fileName,
      sizeBytes: 1024,
      lines: mockLines,
      lineCount: mockLines.length,
      truncated: false,
      isBinary: false,
      mimeType: 'text/plain',
    );
    _previewLoading = false;
  }

  void closePreview() {
    _activePreviewPath = null;
    _fileContent = null;
    _previewLoading = false;
    notifyListeners();
  }

  Future<Uint8List?> downloadFileBytes(String path) async {
    final backend = _backend;
    if (backend == null || !backend.isPaired || backend.token == null) {
      return null;
    }
    try {
      final res = await http.get(
        backend.filesDownloadHttpUri(path),
        headers: {'X-Archangel-Token': backend.token!},
      );
      if (res.statusCode == 200) {
        return res.bodyBytes;
      }
    } catch (e) {
      debugPrint('Error downloading file $path: $e');
    }
    return null;
  }
}
