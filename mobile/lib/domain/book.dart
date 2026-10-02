class Book {
  const Book({
    required this.id,
    required this.title,
    required this.author,
    required this.format,
    required this.objectId,
    required this.size,
    this.shelves = const [],
    this.progress = 0,
    this.locator = '',
    this.bookmarks = const [],
    this.hash = '',
    this.updatedAt = '',
    this.metadataRead = false,
    this.coverObjectId = '',
    this.coverChecked = false,
  });
  final String id, title, author, format, objectId, locator, hash, updatedAt;
  final int size;
  final bool metadataRead;
  final String coverObjectId;
  final bool coverChecked;
  final double progress;
  final List<String> shelves, bookmarks;
  bool get readable => const ['EPUB', 'FB2', 'PDF'].contains(format);
  String get initials => title
      .split(RegExp(r'\s+'))
      .where((s) => s.isNotEmpty)
      .take(2)
      .map((s) => s[0])
      .join(' / ')
      .toUpperCase();
  factory Book.fromJson(Map<String, dynamic> j) {
    final p = (j['position'] as Map?) ?? {};
    return Book(
      id: j['id'] as String,
      title: j['title'] as String,
      author: j['author'] as String? ?? '',
      format: j['format'] as String,
      objectId: j['fileobjectid'] as String,
      size: j['filesize'] as int,
      shelves: List<String>.from(j['shelves'] ?? []),
      progress: (p['progress'] as num? ?? 0).toDouble(),
      locator: p['locator'] as String? ?? '',
      updatedAt: p['updateat'] as String? ?? '',
      bookmarks: List<String>.from(j['bookmarks'] ?? []),
      hash: j['sha256'] as String? ?? '',
      metadataRead: j['metadata_read'] as bool? ?? false,
      coverObjectId: j['coverobjectid'] as String? ?? '',
      coverChecked: j['cover_checked'] as bool? ?? false,
    );
  }
  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'author': author,
    'format': format,
    'fileobjectid': objectId,
    'filesize': size,
    'shelves': shelves,
    'bookmarks': bookmarks,
    'sha256': hash,
    'metadata_read': metadataRead,
    'coverobjectid': coverObjectId,
    'cover_checked': coverChecked,
    'position': {
      'progress': progress,
      'locator': locator,
      'updateat': updatedAt,
    },
  };
}

class ReaderChapter {
  const ReaderChapter(this.id, this.title, this.paragraphs);
  final String id, title;
  final List<String> paragraphs;
}

class ReaderDocument {
  const ReaderDocument(this.title, this.author, this.chapters);
  final String title, author;
  final List<ReaderChapter> chapters;
}
