import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

class PdfReader extends StatefulWidget {
  const PdfReader({
    super.key,
    required this.bytes,
    required this.bookId,
    required this.initialPage,
    required this.paginated,
    required this.onPosition,
  });
  final Uint8List bytes;
  final String bookId;
  final int initialPage;
  final bool paginated;
  final void Function(String locator, int page, int total) onPosition;
  @override
  State<PdfReader> createState() => PdfReaderState();
}

class PdfReaderState extends State<PdfReader> {
  PdfDocument? _document;
  PdfDocumentRefDirect? _reference;
  final _viewer = PdfViewerController();
  late PageController _pages;
  late int _page = widget.initialPage;
  bool _failed = false;
  @override
  void initState() {
    super.initState();
    _pages = PageController(initialPage: (_page - 1).clamp(0, 1000000));
    _open();
  }

  Future<void> _open() async {
    try {
      await pdfrxFlutterInitialize();
      if (!mounted) return;
      final document = await PdfDocument.openData(
        widget.bytes,
        sourceName: widget.bookId,
        maxSizeToCacheOnMemory: 32 * 1024 * 1024,
      );
      if (!mounted) {
        await document.dispose();
        return;
      }
      if (document.pages.isEmpty) {
        await document.dispose();
        setState(() => _failed = true);
        return;
      }
      setState(() {
        _document = document;
        _reference = PdfDocumentRefDirect(document, autoDispose: false);
        _page = _page.clamp(1, document.pages.length);
        _pages.dispose();
        _pages = PageController(initialPage: _page - 1);
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _position(_page);
      });
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  void _position(int page) {
    final total = _document?.pages.length;
    if (total == null) return;
    _page = page.clamp(1, total);
    widget.onPosition('pdf-v1:$_page', _page, total);
  }

  Future<void> goToPage(int page) async {
    if (_document == null) return;
    final next = page.clamp(1, _document!.pages.length);
    if (widget.paginated) {
      if (_pages.hasClients) _pages.jumpToPage(next - 1);
      _position(next);
    } else if (_viewer.isReady) {
      await _viewer.goToPage(pageNumber: next);
    }
  }

  @override
  void didUpdateWidget(PdfReader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.paginated && widget.paginated) {
      _pages.dispose();
      _pages = PageController(initialPage: _page - 1);
    }
  }

  @override
  void dispose() {
    _pages.dispose();
    final document = _document;
    if (document != null) unawaited(document.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) return const Center(child: Text('Cannot open this PDF.'));
    if (_document == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (widget.paginated) {
      return PageView.builder(
        controller: _pages,
        itemCount: _document!.pages.length,
        onPageChanged: (index) => _position(index + 1),
        itemBuilder: (context, index) => InteractiveViewer(
          key: ValueKey(index),
          minScale: 1,
          maxScale: 5,
          child: PdfPageView(
            document: _document,
            pageNumber: index + 1,
            maximumDpi: 180,
          ),
        ),
      );
    }
    return PdfViewer(
      _reference!,
      controller: _viewer,
      initialPageNumber: _page,
      params: PdfViewerParams(
        maxImageBytesCachedOnMemory: 32 * 1024 * 1024,
        linkHandlerParams: PdfLinkHandlerParams(
          enableAutoLinkDetection: false,
          onLinkTap: (_) {},
        ),
        onPageChanged: (page) {
          if (page != null && mounted) _position(page);
        },
      ),
    );
  }
}
