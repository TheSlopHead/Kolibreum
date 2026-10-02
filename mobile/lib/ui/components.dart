import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../app/library_controller.dart';
import '../domain/book.dart';
import 'theme.dart';

class ArchiveMark extends StatelessWidget {
  const ArchiveMark({super.key, this.size = 36});
  final double size;
  @override
  Widget build(BuildContext context) => Image.asset(
    'assets/branding/mut.png',
    width: size,
    height: size,
    color: MutColors.accent,
    colorBlendMode: BlendMode.srcIn,
    errorBuilder: (_, error, stack) =>
        Icon(Icons.local_library_outlined, size: size, color: MutColors.accent),
  );
}

class Glass extends StatelessWidget {
  const Glass({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.radius = 18,
    this.color = MutColors.surface,
  });
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final Color color;
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: MutColors.edge),
    ),
    child: Padding(padding: padding, child: child),
  );
}

class SquareAction extends StatelessWidget {
  const SquareAction(
    this.icon, {
    super.key,
    required this.label,
    required this.onPressed,
  });
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 44,
    height: 44,
    child: IconButton(
      style: IconButton.styleFrom(
        backgroundColor: MutColors.surface,
        side: const BorderSide(color: MutColors.edge),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      tooltip: label,
      onPressed: onPressed,
      icon: Icon(icon, size: 22, color: MutColors.accent),
    ),
  );
}

class ScreenHeading extends StatelessWidget {
  const ScreenHeading(this.title, this.subtitle, {super.key, this.action});
  final String title, subtitle;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 4),
              Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
        ?action,
      ],
    ),
  );
}

class BookCover extends StatefulWidget {
  const BookCover(
    this.book, {
    super.key,
    this.index = 0,
    this.thumbnail = false,
    this.controller,
  });
  final Book book;
  final int index;
  final bool thumbnail;
  final LibraryController? controller;
  @override
  State<BookCover> createState() => _BookCoverState();
}

class _BookCoverState extends State<BookCover> {
  ui.Image? _image;
  int _request = 0, _session = -1;
  Book get book => widget.book;
  int get index => widget.index;
  bool get thumbnail => widget.thumbnail;

  @override
  void initState() {
    super.initState();
    widget.controller?.addListener(_sessionChanged);
    _load();
  }

  @override
  void didUpdateWidget(BookCover oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller ||
        oldWidget.book.id != book.id ||
        oldWidget.book.coverObjectId != book.coverObjectId) {
      oldWidget.controller?.removeListener(_sessionChanged);
      widget.controller?.addListener(_sessionChanged);
      _discardImage();
      _load();
    }
  }

  void _discardImage() {
    _request++;
    _image?.dispose();
    _image = null;
  }

  void _sessionChanged() {
    final controller = widget.controller!;
    if (controller.status != LibraryStatus.unlocked) {
      if (_session != -1) {
        setState(() {
          _discardImage();
          _session = -1;
        });
      }
    } else if (_session != controller.sessionGeneration) {
      setState(_discardImage);
      _load();
    }
  }

  Future<void> _load() async {
    final controller = widget.controller;
    if (controller == null || controller.status != LibraryStatus.unlocked) {
      return;
    }
    final request = ++_request;
    _session = controller.sessionGeneration;
    bool valid() =>
        mounted &&
        request == _request &&
        controller.status == LibraryStatus.unlocked &&
        _session == controller.sessionGeneration;
    Uint8List? bytes;
    ui.Codec? codec;
    try {
      bytes = await controller.cover(book.id);
      if (bytes == null || !valid()) return;
      // Use a widget-owned image: private thumbnails never enter ImageCache.
      codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      if (!valid()) {
        frame.image.dispose();
        return;
      }
      setState(() {
        _image?.dispose();
        _image = frame.image;
      });
    } catch (_) {
      // Preserve the existing text card on a read/decode failure.
    } finally {
      codec?.dispose();
      bytes?.fillRange(0, bytes.length, 0);
    }
  }

  @override
  void dispose() {
    widget.controller?.removeListener(_sessionChanged);
    _discardImage();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    label: '${book.title}, ${book.author}',
    image: true,
    child: Glass(
      color: MutColors.covers[index % MutColors.covers.length],
      radius: thumbnail ? 12 : 16,
      padding: _image == null
          ? EdgeInsets.all(thumbnail ? 8 : 12)
          : EdgeInsets.zero,
      child: _image != null
          ? ClipRRect(
              borderRadius: BorderRadius.circular(thumbnail ? 12 : 16),
              child: SizedBox.expand(
                child: RawImage(image: _image, fit: BoxFit.contain),
              ),
            )
          : thumbnail
          ? Center(
              child: Text(
                book.initials,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'K—${(index + 1).toString().padLeft(2, '0')}\n${book.format}',
                  style: const TextStyle(
                    fontSize: 10,
                    height: 1.5,
                    letterSpacing: 1.2,
                  ),
                ),
                Text(
                  book.title,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 22,
                    height: 1.1,
                    fontWeight: FontWeight.w500,
                    letterSpacing: -.66,
                  ),
                ),
                Text(
                  book.author.isEmpty
                      ? 'PERSONAL ARCHIVE'
                      : book.author.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 10, letterSpacing: 1),
                ),
              ],
            ),
    ),
  );
}

class BookRow extends StatelessWidget {
  const BookRow(
    this.book, {
    super.key,
    required this.onTap,
    this.index = 0,
    this.controller,
  });
  final Book book;
  final VoidCallback onTap;
  final int index;
  final LibraryController? controller;
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Row(
        children: [
          SizedBox(
            width: 72,
            height: 96,
            child: BookCover(
              book,
              index: index,
              thumbnail: true,
              controller: controller,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  book.title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  book.author.isEmpty ? book.format : book.author,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 6),
                Text(
                  book.progress == 0
                      ? 'Not started'
                      : '${(book.progress * 100).round()}% · ${book.format}',
                  style: const TextStyle(fontSize: 12, color: MutColors.accent),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          const SizedBox(
            width: 20,
            child: Icon(Icons.chevron_right, size: 20, color: MutColors.accent),
          ),
        ],
      ),
    ),
  );
}

void showFailure(BuildContext context, Object failure) =>
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(failure.toString()),
        duration: const Duration(seconds: 5),
      ),
    );
String sizeLabel(int bytes) => bytes >= 1048576
    ? '${(bytes / 1048576).toStringAsFixed(1)} MB'
    : '${(bytes / 1024).toStringAsFixed(0)} KB';
