import 'package:flutter/material.dart';
import '../app/library_controller.dart';
import '../domain/book.dart';
import '../ui/components.dart';
import '../ui/theme.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({
    super.key,
    required this.controller,
    required this.onBook,
    required this.onImport,
    required this.onSearch,
  });
  final LibraryController controller;
  final ValueChanged<Book> onBook;
  final VoidCallback onImport, onSearch;
  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  int filter = 0;
  @override
  Widget build(BuildContext context) {
    final books = widget.controller.books;
    final filtered = books
        .where(
          (b) => switch (filter) {
            1 => b.progress > 0 && b.progress < 1,
            2 => b.progress == 0,
            _ => true,
          },
        )
        .toList();
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: ScreenHeading(
            'All books',
            '${books.length} books · sorted by last read',
            action: SquareAction(
              Icons.add,
              label: 'Import file',
              onPressed: widget.controller.busy ? null : widget.onImport,
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: InkWell(
              onTap: widget.onSearch,
              borderRadius: BorderRadius.circular(18),
              child: const Glass(
                child: Row(
                  children: [
                    Icon(Icons.search, size: 20, color: MutColors.accent),
                    SizedBox(width: 10),
                    Text(
                      'Search the archive',
                      style: TextStyle(color: MutColors.muted),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
            child: Row(
              children: [
                for (final (i, text) in [
                  'All · ${books.length}',
                  'Reading · ${books.where((b) => b.progress > 0 && b.progress < 1).length}',
                  'Unread · ${books.where((b) => b.progress == 0).length}',
                ].indexed)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(text),
                      selected: filter == i,
                      showCheckmark: false,
                      labelStyle: TextStyle(
                        fontSize: 12,
                        color: filter == i
                            ? MutColors.background
                            : MutColors.accent,
                      ),
                      onSelected: (_) => setState(() => filter = i),
                    ),
                  ),
              ],
            ),
          ),
        ),
        if (filtered.isEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(32, 48, 32, 24),
              child: Column(
                children: [
                  const Icon(
                    Icons.auto_stories_outlined,
                    size: 48,
                    color: MutColors.accent,
                  ),
                  const SizedBox(height: 20),
                  Text(
                    books.isEmpty
                        ? 'A home for your books'
                        : 'No books in this view',
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Import any file to preserve it. Read EPUB, FB2 and PDF here.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: MutColors.muted, height: 1.5),
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: widget.controller.busy ? null : widget.onImport,
                    icon: const Icon(Icons.add),
                    label: const Text('Add a file'),
                  ),
                ],
              ),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            sliver: SliverLayoutBuilder(
              builder: (context, constraints) {
                final columns = (constraints.crossAxisExtent / 165)
                    .floor()
                    .clamp(2, 6);
                return SliverGrid.builder(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columns,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 16,
                    mainAxisExtent: 280,
                  ),
                  itemCount: filtered.length,
                  itemBuilder: (context, i) {
                    final b = filtered[i];
                    return InkWell(
                      onTap: () => widget.onBook(b),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: SizedBox(
                              width: double.infinity,
                              child: BookCover(b, index: books.indexOf(b)),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            b.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${b.author.isEmpty ? b.format : b.author}${b.progress > 0 ? ' · ${(b.progress * 100).round()}%' : ''}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              color: MutColors.muted,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
        const SliverToBoxAdapter(child: SizedBox(height: 170)),
      ],
    );
  }
}

class ShelvesScreen extends StatefulWidget {
  const ShelvesScreen({
    super.key,
    required this.controller,
    required this.onBook,
  });
  final LibraryController controller;
  final ValueChanged<Book> onBook;
  @override
  State<ShelvesScreen> createState() => _ShelvesScreenState();
}

class _ShelvesScreenState extends State<ShelvesScreen> {
  String shelf = 'Bedtime';
  @override
  Widget build(BuildContext context) {
    final shelves = {
      'Bedtime',
      'Essays & notes',
      'Travel',
      'No shelf',
      ...widget.controller.books.expand((b) => b.shelves),
    }.toList();
    final books = widget.controller.books
        .where(
          (b) => shelf == 'No shelf'
              ? b.shelves.isEmpty
              : b.shelves.contains(shelf),
        )
        .toList();
    return ListView(
      children: [
        const ScreenHeading('Shelves', 'Your own way to keep books'),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Row(
            children: [
              for (final s in shelves)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(s),
                    showCheckmark: false,
                    selected: s == shelf,
                    labelStyle: TextStyle(
                      color: s == shelf
                          ? MutColors.background
                          : MutColors.accent,
                      fontSize: 12,
                    ),
                    onSelected: (_) => setState(() => shelf = s),
                  ),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                shelf,
                style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                shelf == 'Bedtime'
                    ? 'A little quiet before the day ends.'
                    : '${books.length} books on this shelf.',
                style: const TextStyle(color: MutColors.muted),
              ),
            ],
          ),
        ),
        if (books.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Move a book here from its details screen.',
              style: TextStyle(color: MutColors.muted),
            ),
          ),
        for (final (i, b) in books.indexed) ...[
          const Divider(height: 1),
          BookRow(b, index: i, onTap: () => widget.onBook(b)),
        ],
        const SizedBox(height: 170),
      ],
    );
  }
}

class SearchScreen extends StatefulWidget {
  const SearchScreen({
    super.key,
    required this.controller,
    required this.onBook,
  });
  final LibraryController controller;
  final ValueChanged<Book> onBook;
  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final query = TextEditingController();
  int mode = 0;
  @override
  void dispose() {
    query.clear();
    query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final q = query.text.trim().toLowerCase();
    final books = widget.controller.books
        .where(
          (b) =>
              q.isNotEmpty &&
              (mode == 1
                      ? b.title
                      : mode == 2
                      ? b.author
                      : '${b.title} ${b.author}')
                  .toLowerCase()
                  .contains(q),
        )
        .toList();
    return ListView(
      children: [
        const ScreenHeading('Search', 'Find a title or an author'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: TextField(
            controller: query,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: 'Title or author',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: IconButton(
                tooltip: 'Clear search',
                onPressed: () => setState(query.clear),
                icon: const Icon(Icons.close),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Wrap(
            spacing: 8,
            children: [
              for (final (i, name) in ['All', 'Titles', 'Authors'].indexed)
                ChoiceChip(
                  label: Text(name),
                  selected: mode == i,
                  showCheckmark: false,
                  labelStyle: TextStyle(
                    color: mode == i ? MutColors.background : MutColors.accent,
                  ),
                  onSelected: (_) => setState(() => mode = i),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
          child: Text(
            q.isEmpty
                ? 'Search your unlocked library'
                : '${books.length} books found',
            style: const TextStyle(color: MutColors.muted),
          ),
        ),
        for (final b in books) ...[
          const Divider(height: 1),
          BookRow(b, onTap: () => widget.onBook(b)),
        ],
        const Divider(height: 1),
        const Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Search stays on this device',
                style: TextStyle(fontWeight: FontWeight.w500),
              ),
              SizedBox(height: 8),
              Text(
                'Titles and authors are available while your archive is unlocked.',
                style: TextStyle(
                  color: MutColors.muted,
                  fontSize: 13,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 170),
      ],
    );
  }
}
