import 'package:xml/xml.dart';
import '../domain/library_repository.dart';

XmlDocument parseBookXml(String text) {
  if (text.length > 8 * 1024 * 1024 ||
      RegExp(r'<!\s*(DOCTYPE|ENTITY)', caseSensitive: false).hasMatch(text)) {
    throw const LibraryFailure(
      'xml',
      'This book contains unsupported XML declarations or oversized text.',
    );
  }
  final document = XmlDocument.parse(text);
  int nodes = 0;
  void inspect(XmlNode node, int depth) {
    if (depth > 64 || ++nodes > 100000) {
      throw const LibraryFailure(
        'limit',
        'Book structure exceeds reader limits.',
      );
    }
    for (final child in node.children) {
      inspect(child, depth + 1);
    }
  }

  inspect(document, 0);
  return document;
}
