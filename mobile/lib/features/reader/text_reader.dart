import 'package:flutter/material.dart';
import '../../domain/book.dart';
import 'text_pagination.dart';

class TextReader extends StatefulWidget {
  const TextReader({
    super.key,
    required this.document,
    required this.fontSize,
    required this.lineHeight,
    required this.ink,
    required this.paginated,
    required this.initialLocator,
    required this.onPosition,
  });
  final ReaderDocument document;
  final double fontSize, lineHeight;
  final Color ink;
  final bool paginated;
  final String initialLocator;
  final void Function(String locator, int page, int total) onPosition;
  @override
  State<TextReader> createState() => TextReaderState();
}

class TextReaderState extends State<TextReader> {
  List<TextReaderPage> _pages = [];
  Object? _layoutKey;
  int _generation = 0, _index = 0;
  late String _locator = widget.initialLocator;
  PageController? _horizontal;
  ScrollController? _vertical;
  double _extent = 1;
  bool _layingOut = false;
  String? _error;

  void goToLocator(String locator) =>
      goToPage(pageForLocator(_pages, locator) + 1);

  void goToPage(int page) {
    if (_pages.isEmpty) return;
    final index = (page - 1).clamp(0, _pages.length - 1);
    if (_horizontal?.hasClients == true) _horizontal!.jumpToPage(index);
    if (_vertical?.hasClients == true) _vertical!.jumpTo(index * _extent);
    _position(index);
  }

  void _position(int index) {
    if (_layingOut || _pages.isEmpty) return;
    _index = index.clamp(0, _pages.length - 1);
    _locator = _pages[_index].locator;
    widget.onPosition(_locator, _index + 1, _pages.length);
  }

  void _attachControllers() {
    _horizontal?.dispose();
    _vertical?.dispose();
    _horizontal = PageController(initialPage: _index);
    _vertical = ScrollController(initialScrollOffset: _index * _extent)
      ..addListener(_scroll);
  }

  void _scroll() {
    if (_vertical!.hasClients && _pages.isNotEmpty) {
      final next = (_vertical!.offset / _extent).floor().clamp(
        0,
        _pages.length - 1,
      );
      if (next != _index) _position(next);
    }
  }

  Future<void> _layout(
    Size size,
    TextScaler scaler,
    TextDirection direction,
    int generation,
  ) async {
    try {
      final pages = await paginateText(
        widget.document,
        size: size,
        fontSize: widget.fontSize,
        lineHeight: widget.lineHeight,
        scaler: scaler,
        direction: direction,
        cancelled: () => !mounted || generation != _generation,
      );
      if (!mounted || generation != _generation) return;
      setState(() {
        _pages = pages;
        _index = pageForLocator(pages, _locator);
        _extent = size.height;
        _layingOut = false;
        _attachControllers();
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && generation == _generation) _position(_index);
      });
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() {
          _layingOut = false;
          _error = 'Cannot lay out this book. Try a smaller text size.';
        });
      }
    }
  }

  @override
  void didUpdateWidget(TextReader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.paginated != widget.paginated &&
        _pages.isNotEmpty &&
        !_layingOut) {
      // The view in this mode is detached, so its controller can be replaced
      // without repeating pagination or disturbing the attached view.
      if (widget.paginated) {
        _horizontal?.dispose();
        _horizontal = PageController(initialPage: _index);
      } else {
        _vertical?.dispose();
        _vertical = ScrollController(initialScrollOffset: _index * _extent)
          ..addListener(_scroll);
      }
    }
  }

  @override
  void dispose() {
    _generation++;
    _horizontal?.dispose();
    _vertical?.dispose();
    super.dispose();
  }

  Widget _page(int index) => Padding(
    padding: const EdgeInsets.all(24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (i, fragment) in _pages[index].fragments.indexed)
          Padding(
            padding: EdgeInsets.only(
              bottom: i == _pages[index].fragments.length - 1
                  ? 0
                  : fragment.gap,
            ),
            child: fragment.kind == FragmentKind.divider
                ? Container(
                    width: 88,
                    height: 2,
                    color: widget.ink.withValues(alpha: .2),
                  )
                : Text(
                    fragment.text,
                    style:
                        readerStyle(
                          fragment.kind,
                          widget.fontSize,
                          widget.lineHeight,
                        ).copyWith(
                          color: fragment.kind == FragmentKind.label
                              ? widget.ink.withValues(alpha: .7)
                              : widget.ink,
                        ),
                  ),
          ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final size = constraints.biggest;
      final scaler = MediaQuery.textScalerOf(context);
      final direction = Directionality.of(context);
      final key = (
        size,
        widget.document,
        widget.fontSize,
        widget.lineHeight,
        scaler,
        direction,
      );
      if (_layoutKey != key) {
        _layoutKey = key;
        _layingOut = true;
        _error = null;
        final generation = ++_generation;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && generation == _generation) {
            _layout(size, scaler, direction, generation);
          }
        });
      }
      if (_error != null) return Center(child: Text(_error!));
      if (_layingOut || _pages.isEmpty) {
        return const Center(child: CircularProgressIndicator());
      }
      return widget.paginated
          ? PageView.builder(
              key: ValueKey((_generation, true)),
              controller: _horizontal,
              itemCount: _pages.length,
              onPageChanged: _position,
              itemBuilder: (context, index) => _page(index),
            )
          : ListView.builder(
              key: ValueKey((_generation, false)),
              controller: _vertical,
              itemExtent: _extent,
              itemCount: _pages.length,
              itemBuilder: (context, index) => _page(index),
            );
    },
  );
}
