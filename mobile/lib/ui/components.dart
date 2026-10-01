import 'package:flutter/material.dart';
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

class BookCover extends StatelessWidget {
  const BookCover(
    this.book, {
    super.key,
    this.index = 0,
    this.thumbnail = false,
  });
  final Book book;
  final int index;
  final bool thumbnail;
  @override
  Widget build(BuildContext context) => Semantics(
    label: '${book.title}, ${book.author}',
    image: true,
    child: Glass(
      color: MutColors.covers[index % MutColors.covers.length],
      radius: thumbnail ? 12 : 16,
      padding: EdgeInsets.all(thumbnail ? 8 : 12),
      child: thumbnail
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
  const BookRow(this.book, {super.key, required this.onTap, this.index = 0});
  final Book book;
  final VoidCallback onTap;
  final int index;
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
            child: BookCover(book, index: index, thumbnail: true),
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
