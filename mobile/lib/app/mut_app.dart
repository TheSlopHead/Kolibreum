import 'dart:async';
import 'package:flutter/material.dart';
import '../domain/book.dart';
import '../domain/library_repository.dart';
import '../features/access_screen.dart';
import '../features/archive_screen.dart';
import '../features/book_details.dart';
import '../features/library_screens.dart';
import '../features/reader_screen.dart';
import '../platform/documents.dart';
import '../ui/components.dart';
import '../ui/theme.dart';
import 'library_controller.dart';

class MutApp extends StatelessWidget {
  const MutApp({super.key, required this.controller, required this.documents});
  final LibraryController controller;
  final Documents documents;
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'mut',
    theme: mutTheme(),
    debugShowCheckedModeBanner: false,
    home: LibraryShell(controller: controller, documents: documents),
  );
}

class LibraryShell extends StatefulWidget {
  const LibraryShell({
    super.key,
    required this.controller,
    required this.documents,
  });
  final LibraryController controller;
  final Documents documents;
  @override
  State<LibraryShell> createState() => _LibraryShellState();
}

class _LibraryShellState extends State<LibraryShell>
    with WidgetsBindingObserver {
  int tab = 0;
  String? selectedId;
  bool reading = false, documentFlow = false, privacyCover = false;
  Timer? inactivity;
  LibraryStatus? _lastStatus;
  LibraryController get controller => widget.controller;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    controller.documents = widget.documents;
    controller.addListener(_state);
    AndroidDocuments.channel.setMethodCallHandler((call) async {
      if (call.method == 'background') await controller.lock();
    });
    _resetTimer();
  }

  void _resetTimer() {
    inactivity?.cancel();
    if (controller.status == LibraryStatus.unlocked) {
      inactivity = Timer(const Duration(minutes: 5), () => controller.lock());
    }
  }

  void _state() {
    if ((controller.status == LibraryStatus.locked &&
            _lastStatus != LibraryStatus.locked) ||
        (controller.status != LibraryStatus.unlocked &&
            _lastStatus == LibraryStatus.unlocked)) {
      selectedId = null;
      reading = false;
      tab = 0;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
      });
    }
    if (_lastStatus != controller.status) {
      _lastStatus = controller.status;
      _resetTimer();
    }
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted) return;
    setState(() => privacyCover = state != AppLifecycleState.resumed);
    if ((state == AppLifecycleState.paused ||
            state == AppLifecycleState.hidden ||
            state == AppLifecycleState.detached) &&
        !documentFlow) {
      unawaited(controller.lock());
    }
  }

  @override
  void dispose() {
    inactivity?.cancel();
    controller.removeListener(_state);
    WidgetsBinding.instance.removeObserver(this);
    AndroidDocuments.channel.setMethodCallHandler(null);
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
    } catch (e) {
      if (mounted) showFailure(context, e);
    }
  }

  Future<T> _documents<T>(Future<T> Function() operation) async {
    documentFlow = true;
    try {
      return await operation();
    } finally {
      documentFlow = false;
    }
  }

  Future<void> _import() => _run(() async {
    final picked = await _documents(() => widget.documents.pick());
    if (picked == null) return;
    try {
      try {
        await controller.task(() async {
          await controller.repository.importFile(picked.name, picked.bytes);
          await controller.refresh();
        });
      } on LibraryFailure catch (e) {
        if (e.code != 'duplicate' || !mounted) rethrow;
        final keep = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Duplicate file'),
            content: const Text(
              'These exact bytes are already preserved. Skip this file or keep another edition?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Skip'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Keep edition'),
              ),
            ],
          ),
        );
        if (keep == true) {
          await controller.task(() async {
            await controller.repository.importFile(
              picked.name,
              picked.bytes,
              keepDuplicate: true,
            );
            await controller.refresh();
          });
        }
      }
    } finally {
      picked.bytes.fillRange(0, picked.bytes.length, 0);
    }
  });
  Future<void> _export(Book book) => _run(() async {
    final generation = controller.sessionGeneration;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Export an unencrypted original?'),
        content: const Text(
          'The file you save will be readable outside mut. Android will let you choose its location. It remains there after the archive is locked.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Choose location'),
          ),
        ],
      ),
    );
    if (confirmed != true || !controller.isCurrentSession(generation)) return;
    await controller.task(() async {
      final bytes = await controller.repository.read(book.id);
      try {
        if (!controller.isCurrentSession(generation)) return;
        await _documents(
          () => widget.documents.save(
            '${book.title}.${book.format.toLowerCase()}',
            bytes,
          ),
        );
      } finally {
        bytes.fillRange(0, bytes.length, 0);
      }
    });
  });
  Future<void> _backup() => _run(
    () => controller.task(() async {
      final generation = controller.sessionGeneration;
      final bytes = await controller.repository.backup();
      if (!controller.isCurrentSession(generation)) return;
      final saved = await _documents(
        () => widget.documents.save(
          'mut-backup-${DateTime.now().toIso8601String().substring(0, 10)}.zip',
          bytes,
          verify: true,
        ),
      );
      if (saved && mounted && controller.isCurrentSession(generation)) {
        controller.backupReport =
            '${controller.books.length} books · saved and reread successfully';
        setState(() {});
      }
    }),
  );
  Future<(String, bool)?> _secret(
    String title, {
    bool allowRecovery = false,
  }) async {
    final text = TextEditingController();
    bool recovery = false;
    final result = await showDialog<(String, bool)>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: Text(title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: text,
                obscureText: true,
                enableSuggestions: false,
                autocorrect: false,
                decoration: InputDecoration(
                  hintText: recovery ? 'Recovery code' : 'Password',
                ),
              ),
              if (allowRecovery)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Use recovery code'),
                  value: recovery,
                  onChanged: (v) => update(() => recovery = v),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, (text.text, recovery)),
              child: const Text('Continue'),
            ),
          ],
        ),
      ),
    );
    text.clear();
    text.dispose();
    return result;
  }

  Future<void> _restore() => _run(() async {
    if (controller.status == LibraryStatus.unlocked) {
      final yes = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Restore a backup?'),
          content: const Text(
            'The copy is verified before replacing your library. The previous encrypted archive will be preserved on this device.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Choose backup'),
            ),
          ],
        ),
      );
      if (yes != true) return;
    }
    final picked = await _documents(() => widget.documents.pick(backup: true));
    if (picked == null || !mounted) return;
    final secret = await _secret('Open the backup', allowRecovery: true);
    if (secret == null) return;
    await controller.restore(picked.bytes, secret.$1, recovery: secret.$2);
  });
  Future<void> _password() => _run(() async {
    final result = await _secret('New archive password');
    if (result == null) return;
    await controller.task(
      () => controller.repository.changePassword(result.$1),
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Password changed. Existing backups retain their old password.',
          ),
        ),
      );
    }
  });
  void _book(Book book) => setState(() {
    selectedId = book.id;
    reading = false;
  });
  Future<void> _read(Book book) => _run(() async {
    await controller.open(book);
    if (mounted &&
        controller.current != null &&
        controller.status == LibraryStatus.unlocked) {
      setState(() {
        selectedId = book.id;
        reading = true;
      });
    }
  });
  Future<void> _back() async {
    if (reading) {
      try {
        await controller.flushPosition();
      } catch (e) {
        if (mounted) showFailure(context, e);
      }
    }
    if (!mounted) return;
    setState(() {
      if (reading) {
        reading = false;
        controller.closeReader();
      } else {
        selectedId = null;
      }
    });
  }

  Widget _dock() {
    final recent = controller.books
        .where((b) => b.progress > 0 && b.progress < 1 && b.readable)
        .firstOrNull;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Glass(
        color: MutColors.dock,
        radius: 24,
        padding: const EdgeInsets.all(8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (recent != null && tab != 3) ...[
              InkWell(
                onTap: () => _read(recent),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(6, 4, 6, 10),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 36,
                        height: 44,
                        child: BookCover(
                          recent,
                          thumbnail: true,
                          controller: controller,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              recent.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            Text(
                              'Continue · ${(recent.progress * 100).round()}%',
                              style: const TextStyle(
                                fontSize: 12,
                                color: MutColors.accent,
                              ),
                            ),
                          ],
                        ),
                      ),
                      SquareAction(
                        Icons.arrow_forward,
                        label: 'Continue reading',
                        onPressed: () => _read(recent),
                      ),
                    ],
                  ),
                ),
              ),
              const Divider(height: 1),
              const SizedBox(height: 8),
            ],
            Row(
              children: [
                for (final (i, icon) in [
                  Icons.grid_view_outlined,
                  Icons.library_books_outlined,
                  Icons.search,
                  Icons.settings_outlined,
                ].indexed)
                  Expanded(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => setState(() {
                        tab = i;
                        selectedId = null;
                      }),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              icon,
                              size: 21,
                              color: tab == i
                                  ? MutColors.text
                                  : MutColors.muted,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              ['Library', 'Shelves', 'Search', 'Archive'][i],
                              style: TextStyle(
                                fontSize: 11,
                                color: tab == i
                                    ? MutColors.text
                                    : MutColors.muted,
                                fontWeight: tab == i
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    Widget content;
    final book = controller.books.where((b) => b.id == selectedId).firstOrNull;
    if (controller.status == LibraryStatus.loading) {
      content = const Center(child: CircularProgressIndicator());
    } else if (controller.status != LibraryStatus.unlocked) {
      content = AccessScreen(controller: controller, onRestore: _restore);
    } else if (reading && controller.current != null) {
      content = ReaderScreen(
        key: ValueKey(controller.current!.id),
        controller: controller,
        onBack: _back,
      );
    } else if (book != null) {
      content = BookDetails(
        book: book,
        controller: controller,
        onBack: _back,
        onRead: () => _read(book),
        onExport: () => _export(book),
      );
    } else {
      content = Stack(
        children: [
          Positioned.fill(
            child: switch (tab) {
              1 => ShelvesScreen(controller: controller, onBook: _book),
              2 => SearchScreen(controller: controller, onBook: _book),
              3 => ArchiveScreen(
                controller: controller,
                onBackup: _backup,
                onRestore: _restore,
                onPassword: _password,
              ),
              _ => LibraryScreen(
                controller: controller,
                onBook: _book,
                onImport: _import,
                onSearch: () => setState(() => tab = 2),
              ),
            },
          ),
          Positioned(left: 0, right: 0, bottom: 0, child: _dock()),
        ],
      );
    }
    return Listener(
      onPointerDown: (_) => _resetTimer(),
      child: PopScope(
        canPop: selectedId == null,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop) _back();
        },
        child: Scaffold(
          body: Stack(
            children: [
              SafeArea(child: content),
              if (controller.busy)
                const Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: LinearProgressIndicator(
                    minHeight: 2,
                    color: MutColors.accent,
                  ),
                ),
              if (privacyCover)
                const Positioned.fill(
                  child: ColoredBox(
                    color: MutColors.background,
                    child: Center(child: ArchiveMark(size: 48)),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
