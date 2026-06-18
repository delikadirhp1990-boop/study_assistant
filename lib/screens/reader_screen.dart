import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'package:open_filex/open_filex.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:epub_pro/epub_pro.dart';
import 'package:docx_file_viewer/docx_file_viewer.dart';
import '../models/book_model.dart';
import '../database/database_helper.dart';

class ReaderScreen extends StatefulWidget {
  final Book book;
  const ReaderScreen({super.key, required this.book});

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> {
  final DatabaseHelper _db = DatabaseHelper();
  late Future<bool> _fileExistsFuture;
  bool _isLoading = true;
  final PdfViewerController _pdfController = PdfViewerController();

  @override
  void initState() {
    super.initState();
    _fileExistsFuture = File(widget.book.filePath).exists();
    _updateLastOpened();
  }

  Future<void> _updateLastOpened() async {
    final updated = Book(
      id: widget.book.id,
      title: widget.book.title,
      filePath: widget.book.filePath,
      fileType: widget.book.fileType,
      author: widget.book.author,
      coverPath: widget.book.coverPath,
      category: widget.book.category,
      pageCount: widget.book.pageCount,
      currentPage: widget.book.currentPage,
      lastOpened: DateTime.now(),
      dateAdded: widget.book.dateAdded,
      progress: widget.book.progress,
    );
    await _db.updateBook(updated);
    if (mounted) setState(() => _isLoading = false);
  }

  void _updateProgress(double progress) async {
    if (progress > 0) {
      final updated = Book(
        id: widget.book.id,
        title: widget.book.title,
        filePath: widget.book.filePath,
        fileType: widget.book.fileType,
        author: widget.book.author,
        coverPath: widget.book.coverPath,
        category: widget.book.category,
        pageCount: widget.book.pageCount,
        currentPage: (progress * widget.book.pageCount).round(),
        lastOpened: widget.book.lastOpened,
        dateAdded: widget.book.dateAdded,
        progress: progress,
      );
      await _db.updateBook(updated);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return FutureBuilder<bool>(
      future: _fileExistsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (!snapshot.hasData || snapshot.data == false) {
          return Scaffold(
            appBar: AppBar(
              title: const Text('Dosya Bulunamadı'),
              backgroundColor: Colors.black,
              foregroundColor: Colors.white,
            ),
            body: const Center(
              child: Text(
                'Dosya silinmiş veya taşınmış.',
                style: TextStyle(color: Colors.grey),
              ),
            ),
          );
        }

        final file = File(widget.book.filePath);
        switch (widget.book.fileType.toLowerCase()) {
          case 'pdf':
            return _buildPdfViewer(file);
          case 'epub':
            return _buildEpubViewer(file);
          case 'docx':
          case 'doc':
            return _buildWordViewer(file);
          case 'pptx':
          case 'ppt':
          case 'xlsx':
          case 'xls':
            return _buildOfficeViewer(file);
          default:
            return _buildUnsupportedViewer(file);
        }
      },
    );
  }

  // 📄 PDF Görüntüleyici
  Widget _buildPdfViewer(File file) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.book.title,
          style: const TextStyle(color: Colors.white),
        ),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SfPdfViewer.file(
        file,
        controller: _pdfController,
        onPageChanged: (details) {
          if (widget.book.pageCount > 0) {
            final progress = details.newPageNumber / widget.book.pageCount;
            _updateProgress(progress);
          }
        },
      ),
    );
  }

  // 📖 EPUB Okuyucu
  Widget _buildEpubViewer(File file) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.book.title,
          style: const TextStyle(color: Colors.white),
        ),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: FutureBuilder<String>(
        future: _loadEpubContent(file),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError || snapshot.data == null) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.error_outline, size: 64, color: Colors.grey[600]),
                  const SizedBox(height: 16),
                  Text(
                    'EPUB içeriği yüklenemedi.',
                    style: TextStyle(color: Colors.grey[400]),
                  ),
                ],
              ),
            );
          }
          return WebViewWidget(
            controller: WebViewController()
              ..setJavaScriptMode(JavaScriptMode.unrestricted)
              ..loadHtmlString(snapshot.data!),
          );
        },
      ),
    );
  }

  Future<String> _loadEpubContent(File file) async {
    try {
      final bytes = await file.readAsBytes();
      final book = await EpubReader.readBook(bytes);
      if (book.chapters.isNotEmpty) {
        final chapter = book.chapters.first;
        return chapter.htmlContent ?? '<p>İçerik boş</p>';
      }
      return '<p>Bölüm bulunamadı</p>';
    } catch (e) {
      return '<p>EPUB okuma hatası: $e</p>';
    }
  }

  // 📄 WORD (DOCX) – docx_file_viewer ile uygulama içi
  Widget _buildWordViewer(File file) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.book.title,
          style: const TextStyle(color: Colors.white),
        ),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.open_in_new, color: Colors.white),
            onPressed: () async {
              final result = await OpenFilex.open(file.path);
              if (result.type != ResultType.done && mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Dosya açılamadı: ${result.message}'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            tooltip: 'Dış Uygulamada Aç',
          ),
        ],
      ),
      body: DocxView.file(
        file,
        config: DocxViewConfig(
          enableZoom: true,
          enableSearch: true,
          pageMode: DocxPageMode.continuous,
          theme: DocxViewTheme.dark(),
          backgroundColor: Colors.black,
        ),
      ),
    );
  }

  // 📂 Office Dosyaları (PPTX, XLSX) – dış uygulamada aç
  Widget _buildOfficeViewer(File file) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.book.title,
          style: const TextStyle(color: Colors.white),
        ),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              _getOfficeIcon(widget.book.fileType),
              size: 80,
              color: _getOfficeColor(widget.book.fileType),
            ),
            const SizedBox(height: 24),
            Text(
              widget.book.title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.white),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              '${widget.book.fileType.toUpperCase()} dosyası',
              style: TextStyle(color: Colors.grey[400]),
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: () async {
                final result = await OpenFilex.open(file.path);
                if (result.type != ResultType.done && mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Dosya açılamadı: ${result.message}'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              },
              icon: const Icon(Icons.open_in_new, color: Colors.white),
              label: const Text(
                'Dış Uygulamada Aç',
                style: TextStyle(color: Colors.white),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: _getOfficeColor(widget.book.fileType),
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Bu dosya türü doğrudan görüntülenemiyor.\nCihazınızdaki uygun uygulama ile açılacaktır.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[500], fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  IconData _getOfficeIcon(String fileType) {
    switch (fileType.toLowerCase()) {
      case 'pptx':
      case 'ppt': return Icons.slideshow;
      case 'xlsx':
      case 'xls': return Icons.table_chart;
      default: return Icons.insert_drive_file;
    }
  }

  Color _getOfficeColor(String fileType) {
    switch (fileType.toLowerCase()) {
      case 'pptx':
      case 'ppt': return Colors.orange[800]!;
      case 'xlsx':
      case 'xls': return Colors.green[800]!;
      default: return Colors.blue[800]!;
    }
  }

  // ⛔ Desteklenmeyen dosya türleri
  Widget _buildUnsupportedViewer(File file) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.book.title,
          style: const TextStyle(color: Colors.white),
        ),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.info_outline, size: 64, color: Colors.grey[600]),
            const SizedBox(height: 16),
            Text(
              'Bu dosya türü (${widget.book.fileType.toUpperCase()}) henüz desteklenmiyor.',
              style: TextStyle(color: Colors.grey[400]),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'PDF, EPUB, Word, Excel, PowerPoint dosyalarını görüntüleyebilirsiniz.',
              style: TextStyle(color: Colors.grey[500], fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}