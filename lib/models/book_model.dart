class Book {
  final String id;
  final String title;
  final String filePath;
  final String fileType;
  final String? author;
  final String? coverPath;
  final String? category;
  final int pageCount;
  final int currentPage;
  final DateTime lastOpened;
  final DateTime dateAdded;
  final double progress;

  Book({
    required this.id,
    required this.title,
    required this.filePath,
    required this.fileType,
    this.author,
    this.coverPath,
    this.category,
    this.pageCount = 0,
    this.currentPage = 0,
    required this.lastOpened,
    required this.dateAdded,
    this.progress = 0.0,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'filePath': filePath,
      'fileType': fileType,
      'author': author,
      'coverPath': coverPath,
      'category': category,
      'pageCount': pageCount,
      'currentPage': currentPage,
      'lastOpened': lastOpened.toIso8601String(),
      'dateAdded': dateAdded.toIso8601String(),
      'progress': progress,
    };
  }

  factory Book.fromMap(Map<String, dynamic> map) {
    return Book(
      id: map['id'],
      title: map['title'],
      filePath: map['filePath'],
      fileType: map['fileType'],
      author: map['author'],
      coverPath: map['coverPath'],
      category: map['category'],
      pageCount: map['pageCount'] ?? 0,
      currentPage: map['currentPage'] ?? 0,
      lastOpened: DateTime.parse(map['lastOpened']),
      dateAdded: DateTime.parse(map['dateAdded']),
      progress: map['progress']?.toDouble() ?? 0.0,
    );
  }
}