import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/book_model.dart';
import '../database/database_helper.dart';
import 'thumbnail_service.dart';

class FileScannerService {
  final DatabaseHelper _db = DatabaseHelper();
  final _uuid = const Uuid();
  static const String _savedPathsKey = 'scanned_folders';

  static const List<String> supportedExtensions = [
    'pdf', 'epub', 'docx', 'pptx',
    'doc', 'ppt', 'xlsx', 'xls'
  ];

  Future<List<String>> getUserAddedPaths() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_savedPathsKey) ?? [];
  }

  Future<void> addUserPath(String path) async {
    final prefs = await SharedPreferences.getInstance();
    List<String> paths = prefs.getStringList(_savedPathsKey) ?? [];
    if (!paths.contains(path)) {
      paths.add(path);
      await prefs.setStringList(_savedPathsKey, paths);
    }
  }

  Future<void> removeUserPath(String path) async {
    final prefs = await SharedPreferences.getInstance();
    List<String> paths = prefs.getStringList(_savedPathsKey) ?? [];
    paths.remove(path);
    await prefs.setStringList(_savedPathsKey, paths);
  }

  Future<void> clearUserPaths() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_savedPathsKey);
  }

  Future<List<String>> getAllScanPaths() async {
    List<String> paths = [];
    final downloadsPath = await _getDownloadsPath();
    if (downloadsPath != null && await Directory(downloadsPath).exists()) {
      paths.add(downloadsPath);
    }
    final userPaths = await getUserAddedPaths();
    for (var path in userPaths) {
      if (await Directory(path).exists() && !paths.contains(path)) {
        paths.add(path);
      }
    }
    return paths;
  }

  Future<List<Book>> scanLibrary() async {
    List<Book> foundBooks = [];
    List<String> scannedPaths = [];
    try {
      final allPaths = await getAllScanPaths();
      debugPrint('📂 Taranacak klasörler: ${allPaths.join(', ')}');
      for (var path in allPaths) {
        final dir = Directory(path);
        if (await dir.exists()) {
          final books = await _scanDirectory(dir);
          foundBooks.addAll(books);
          scannedPaths.addAll(books.map((b) => b.filePath));
        }
      }
      await _cleanupDeletedBooks(scannedPaths);
    } catch (e) {
      debugPrint('❌ Tarama hatası: $e');
    }
    return foundBooks;
  }

  Future<List<Book>> scanDirectory(String path) async {
    final dir = Directory(path);
    if (!await dir.exists()) {
      debugPrint('❌ Klasör bulunamadı: $path');
      return [];
    }
    debugPrint('📂 Özel tarama başladı: $path');
    final books = await _scanDirectory(dir);
    debugPrint('✅ Özel tarama tamamlandı: ${books.length} dosya bulundu');
    return books;
  }

  Future<void> clearLibrary() async {
    try {
      await _db.deleteAllBooks();
      final appDir = await getApplicationDocumentsDirectory();
      final coversDir = Directory('${appDir.path}/covers');
      if (await coversDir.exists()) {
        await coversDir.delete(recursive: true);
        debugPrint('🗑️ Kapak resimleri silindi.');
      }
      await clearUserPaths();
      debugPrint('✅ Kütüphane tamamen temizlendi.');
    } catch (e) {
      debugPrint('❌ Kütüphane temizleme hatası: $e');
      rethrow;
    }
  }

  Future<String?> _getDownloadsPath() async {
    if (Platform.isAndroid) {
      final downloadsPath = '/storage/emulated/0/Download';
      if (await Directory(downloadsPath).exists()) {
        return downloadsPath;
      }
      final altPath = '/sdcard/Download';
      if (await Directory(altPath).exists()) {
        return altPath;
      }
    } else if (Platform.isIOS) {
      final appDir = await getApplicationDocumentsDirectory();
      return appDir.path;
    }
    return null;
  }

  Future<List<Book>> _scanDirectory(Directory dir) async {
    List<Book> books = [];
    try {
      final List<FileSystemEntity> entities = await dir.list().toList();
      for (var entity in entities) {
        if (entity is File) {
          final extension = entity.path.split('.').last.toLowerCase();
          if (supportedExtensions.contains(extension)) {
            final book = await _processFile(entity);
            if (book != null) books.add(book);
          }
        } else if (entity is Directory) {
          final dirName = entity.path.split('/').last;
          if (dirName == 'data' || dirName == 'obb') continue;
          try {
            final subBooks = await _scanDirectory(entity);
            books.addAll(subBooks);
          } catch (e) {}
        }
      }
    } catch (e) {}
    return books;
  }

  Future<Book?> _processFile(File file) async {
    try {
      final existing = await _db.getBookByPath(file.path);
      if (existing != null) {
        final lastModified = await file.lastModified();
        if (!lastModified.isAfter(existing.lastOpened)) {
          return existing;
        }
      }

      final extension = file.path.split('.').last.toLowerCase();
      final title = file.path.split('/').last;
      final category = _extractCategory(file.path);

      final info = await ThumbnailService.getFileInfo(file.path);
      final pageCount = info?['pageCount'] as int? ?? 0;

      final book = Book(
        id: _uuid.v4(),
        title: title,
        filePath: file.path,
        fileType: extension,
        author: null,
        coverPath: null,
        category: category,
        pageCount: pageCount,
        currentPage: 0,
        lastOpened: DateTime.now(),
        dateAdded: DateTime.now(),
      );

      await _db.insertBook(book);
      debugPrint('✅ Dosya indekslendi: $title ($extension) - $pageCount sayfa');

      _generateThumbnailInBackground(book);

      return book;
    } catch (e) {
      debugPrint('❌ Dosya işleme hatası: ${file.path} - $e');
      return null;
    }
  }

  void _generateThumbnailInBackground(Book book) {
    ThumbnailService.generateThumbnail(book.filePath)
        .then((coverPath) async {
      if (coverPath != null) {
        final updatedBook = Book(
          id: book.id,
          title: book.title,
          filePath: book.filePath,
          fileType: book.fileType,
          author: book.author,
          coverPath: coverPath,
          category: book.category,
          pageCount: book.pageCount,
          currentPage: book.currentPage,
          lastOpened: book.lastOpened,
          dateAdded: book.dateAdded,
          progress: book.progress,
        );
        await _db.updateBook(updatedBook);
        debugPrint('🖼️ Kapak oluşturuldu (native): ${book.title}');
      } else {
        debugPrint('⚠️ Kapak oluşturulamadı: ${book.title}');
      }
    })
        .catchError((e) {
      debugPrint('❌ Native thumbnail hatası: $e');
    });
  }

  String _extractCategory(String filePath) {
    final parts = filePath.split(Platform.pathSeparator);
    if (parts.length > 2) {
      return parts[parts.length - 2];
    }
    return 'Diğer';
  }

  Future<void> _cleanupDeletedBooks(List<String> existingPaths) async {
    final allBooks = await _db.getAllBooks();
    for (var book in allBooks) {
      if (!existingPaths.contains(book.filePath)) {
        if (book.coverPath != null) {
          final coverFile = File(book.coverPath!);
          if (await coverFile.exists()) {
            await coverFile.delete();
          }
        }
        await _db.deleteBook(book.id);
        debugPrint('🗑️ Silinen dosya temizlendi: ${book.title}');
      }
    }
  }
}