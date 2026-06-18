import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shimmer/shimmer.dart';
import 'package:adaptive_theme/adaptive_theme.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/book_model.dart';
import '../database/database_helper.dart';
import '../services/file_scanner_service.dart';
import '../widgets/book_card.dart';
import '../widgets/category_chip.dart';
import 'reader_screen.dart';
import 'about_screen.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  final DatabaseHelper _db = DatabaseHelper();
  final FileScannerService _scanner = FileScannerService();

  List<Book> _books = [];
  List<Book> _filteredBooks = [];
  List<String> _categories = [];
  String? _selectedCategory;
  bool _isLoading = true;
  bool _isScanning = false;
  List<String> _savedPaths = [];
  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadLibrary();
    _loadSavedPaths();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadSavedPaths() async {
    final paths = await _scanner.getUserAddedPaths();
    setState(() => _savedPaths = paths);
  }

  Future<void> _loadLibrary() async {
    setState(() => _isLoading = true);
    await _loadBooks();
    await _loadCategories();
    setState(() => _isLoading = false);
  }

  Future<void> _loadBooks() async {
    final allBooks = await _db.getAllBooks();
    setState(() {
      _books = allBooks;
      _applyFilters();
    });
  }

  Future<void> _loadCategories() async {
    final categories = await _db.getAllCategories();
    setState(() {
      _categories = ['Tümü', ...categories];
    });
  }

  void _applyFilters() {
    List<Book> filtered = _books;
    if (_selectedCategory != null) {
      filtered = filtered.where((b) => b.category == _selectedCategory).toList();
    }
    if (_searchController.text.isNotEmpty) {
      final query = _searchController.text.toLowerCase();
      filtered = filtered.where((b) =>
      b.title.toLowerCase().contains(query) ||
          (b.author?.toLowerCase().contains(query) ?? false)
      ).toList();
    }
    setState(() => _filteredBooks = filtered);
  }

  Future<void> _scanLibrary() async {
    setState(() => _isScanning = true);
    try {
      await _scanner.scanLibrary();
      await _loadLibrary();
      await _loadSavedPaths();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('📚 Kütüphane taranıp güncellendi!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ Tarama hatası: $e'), backgroundColor: Colors.red),
        );
      }
    }
    setState(() => _isScanning = false);
  }

  Future<void> _addFolder() async {
    try {
      String? selectedDirectory = await FilePicker.platform.getDirectoryPath();
      if (selectedDirectory == null) return;
      setState(() => _isScanning = true);
      await _scanner.addUserPath(selectedDirectory);
      await _loadSavedPaths();
      final books = await _scanner.scanDirectory(selectedDirectory);
      await _loadLibrary();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('📂 ${books.length} dosya bulundu ve klasör kaydedildi!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ Hata: $e'), backgroundColor: Colors.red),
        );
      }
    }
    setState(() => _isScanning = false);
  }

  Future<void> _removeFolder(String path) async {
    await _scanner.removeUserPath(path);
    await _loadSavedPaths();
    await _scanLibrary();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('🗑️ Klasör kaldırıldı ve kitaplık güncellendi.'),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  Future<void> _showManagedPaths() async {
    final paths = await _scanner.getUserAddedPaths();
    final isDark = AdaptiveTheme.of(context).mode == AdaptiveThemeMode.dark;
    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? const Color(0xFF1A1A1A) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        height: 420,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.folder, color: Colors.blue[300]),
                const SizedBox(width: 12),
                Text(
                  '📂 Eklenen Klasörler',
                  style: GoogleFonts.inter(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black,
                  ),
                ),
                const Spacer(),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: Icon(Icons.close, color: isDark ? Colors.white : Colors.black),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Bu klasörler her açılışta otomatik taranır.',
              style: GoogleFonts.inter(
                color: isDark ? Colors.grey[400] : Colors.grey[600],
                fontSize: 13,
              ),
            ),
            Divider(
              color: isDark ? Colors.grey[800] : Colors.grey[300],
              height: 24,
            ),
            Expanded(
              child: paths.isEmpty
                  ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.folder_open, size: 48, color: Colors.grey[600]),
                    const SizedBox(height: 12),
                    Text(
                      'Henüz eklenmiş klasör yok.',
                      style: GoogleFonts.inter(
                        color: isDark ? Colors.grey[500] : Colors.grey[700],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '📂 "Klasör Ekle" butonunu kullanarak ekleme yapabilirsin.',
                      style: GoogleFonts.inter(
                        color: isDark ? Colors.grey[600] : Colors.grey[500],
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              )
                  : ListView.builder(
                itemCount: paths.length,
                itemBuilder: (context, index) {
                  final path = paths[index];
                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.grey[900] : Colors.grey[100],
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: ListTile(
                      leading: Icon(Icons.folder, color: Colors.blue[400]),
                      title: Text(
                        path,
                        style: GoogleFonts.inter(
                          color: isDark ? Colors.white : Colors.black,
                          fontSize: 13,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: IconButton(
                        icon: Icon(Icons.delete_outline, color: Colors.red[400]),
                        onPressed: () {
                          Navigator.pop(context);
                          _removeFolder(path);
                        },
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      _addFolder();
                    },
                    icon: const Icon(Icons.add, color: Colors.white),
                    label: const Text(
                      'Yeni Klasör Ekle',
                      style: TextStyle(color: Colors.white),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue[800],
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickFileAndScanFolder() async {
    try {
      setState(() => _isScanning = true);
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: FileType.custom,
        allowedExtensions: ['pdf', 'epub', 'docx', 'pptx', 'doc', 'ppt', 'xlsx', 'xls'],
      );
      if (result == null) {
        setState(() => _isScanning = false);
        return;
      }
      Set<String> folderPaths = {};
      for (var file in result.files) {
        if (file.path != null) {
          final path = file.path!;
          final folder = path.substring(0, path.lastIndexOf('/'));
          folderPaths.add(folder);
        }
      }
      if (folderPaths.isEmpty) {
        setState(() => _isScanning = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Dosya yolu bulunamadı!'), backgroundColor: Colors.orange),
        );
        return;
      }
      int totalBooks = 0;
      for (var folderPath in folderPaths) {
        await _scanner.addUserPath(folderPath);
        final books = await _scanner.scanDirectory(folderPath);
        totalBooks += books.length;
      }
      await _loadLibrary();
      await _loadSavedPaths();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('📂 ${totalBooks} dosya bulundu ve klasörler kaydedildi!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      debugPrint('❌ Dosya seçme hatası: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ Hata: $e'), backgroundColor: Colors.red),
        );
      }
    }
    setState(() => _isScanning = false);
  }

  Future<void> _confirmClearLibrary() async {
    final isDark = AdaptiveTheme.of(context).mode == AdaptiveThemeMode.dark;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Kütüphaneyi Temizle'),
        content: Text(
          'Tüm kitaplar ve kapak resimleri silinecek. Bu işlem geri alınamaz. Devam etmek istediğinize emin misiniz?',
          style: GoogleFonts.inter(
            color: isDark ? Colors.white : Colors.black,
          ),
        ),
        backgroundColor: isDark ? Colors.grey[900] : Colors.white,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('İptal', style: GoogleFonts.inter(color: Colors.grey[500])),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              'Temizle',
              style: GoogleFonts.inter(color: Colors.red[400]),
            ),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await _clearLibrary();
    }
  }

  Future<void> _clearLibrary() async {
    setState(() => _isScanning = true);
    try {
      await _scanner.clearLibrary();
      await _loadLibrary();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('🗑️ Kütüphane başarıyla temizlendi.'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ Temizleme hatası: $e'), backgroundColor: Colors.red),
        );
      }
    }
    setState(() => _isScanning = false);
  }

  void _toggleTheme() {
    final currentMode = AdaptiveTheme.of(context).mode;
    if (currentMode == AdaptiveThemeMode.dark) {
      AdaptiveTheme.of(context).setLight();
    } else {
      AdaptiveTheme.of(context).setDark();
    }
  }

  void _toggleSearch() {
    setState(() {
      _isSearching = !_isSearching;
      if (!_isSearching) {
        _searchController.clear();
        _applyFilters();
      }
    });
  }

  void _openBook(Book book) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => ReaderScreen(book: book)),
    ).then((_) => _loadLibrary());
  }

  @override
  Widget build(BuildContext context) {
    final isDark = AdaptiveTheme.of(context).mode == AdaptiveThemeMode.dark;
    final themeColor = isDark ? Colors.blue[400] : Colors.blue[700];

    return Scaffold(
      backgroundColor: isDark ? Colors.black : Colors.grey[50],
      body: CustomScrollView(
        cacheExtent: 500,  // ✅ Optimize: önbellek alanı daraltıldı
        slivers: [
          SliverAppBar(
            expandedHeight: _isSearching ? 180 : 140,
            floating: true,
            pinned: true,
            backgroundColor: isDark ? Colors.black : Colors.white,
            foregroundColor: isDark ? Colors.white : Colors.black,
            flexibleSpace: FlexibleSpaceBar(
              title: _isSearching
                  ? null
                  : Text(
                '📚 Kitaplığım',
                style: GoogleFonts.inter(
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : Colors.black,
                ),
              ),
              background: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: isDark
                        ? [Colors.blue[900]!.withValues(alpha: 0.4), Colors.black]
                        : [Colors.blue[100]!.withValues(alpha: 0.4), Colors.white],
                  ),
                ),
              ),
            ),
            actions: [
              IconButton(
                icon: Icon(Icons.delete_sweep, color: Colors.red[400]),
                onPressed: _confirmClearLibrary,
                tooltip: 'Kütüphaneyi Temizle',
              ),
              IconButton(
                icon: Icon(Icons.info_outline, color: themeColor),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const AboutScreen()),
                  );
                },
                tooltip: 'Hakkında',
              ),
              IconButton(
                icon: Icon(
                  isDark ? Icons.light_mode : Icons.dark_mode,
                  color: themeColor,
                ),
                onPressed: _toggleTheme,
                tooltip: isDark ? 'Açık Tema' : 'Koyu Tema',
              ),
              IconButton(
                icon: Icon(
                  _isSearching ? Icons.close : Icons.search,
                  color: themeColor,
                ),
                onPressed: _toggleSearch,
                tooltip: 'Ara',
              ),
              IconButton(
                icon: Icon(Icons.folder, color: themeColor),
                onPressed: _showManagedPaths,
                tooltip: 'Klasör Yönetimi',
              ),
              IconButton(
                icon: _isScanning
                    ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.blue,
                  ),
                )
                    : Icon(Icons.refresh, color: themeColor),
                onPressed: _isScanning ? null : _scanLibrary,
                tooltip: 'Kütüphaneyi Tara',
              ),
            ],
            bottom: _isSearching
                ? PreferredSize(
              preferredSize: const Size.fromHeight(60),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: TextField(
                  controller: _searchController,
                  autofocus: true,
                  style: GoogleFonts.inter(
                    color: isDark ? Colors.white : Colors.black,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Kitap veya yazar ara...',
                    hintStyle: GoogleFonts.inter(
                      color: isDark ? Colors.grey[500] : Colors.grey[600],
                    ),
                    prefixIcon: Icon(Icons.search, color: themeColor),
                    filled: true,
                    fillColor: isDark ? Colors.grey[900] : Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  onChanged: (value) => _applyFilters(),
                ),
              ),
            )
                : null,
          ),
          SliverToBoxAdapter(
            child: Container(
              height: 50,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: _categories.length,
                itemBuilder: (context, index) {
                  final category = _categories[index];
                  final isSelected = (index == 0 && _selectedCategory == null) ||
                      category == _selectedCategory;
                  return CategoryChip(
                    label: category,
                    isSelected: isSelected,
                    onTap: () {
                      setState(() {
                        _selectedCategory = index == 0 ? null : category;
                      });
                      _applyFilters();
                    },
                  );
                },
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.all(8),
            sliver: _isLoading
                ? _buildShimmerGrid()
                : _filteredBooks.isEmpty
                ? SliverFillRemaining(child: _buildEmptyState())
                : SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                childAspectRatio: 0.75,  // ✅ Optimize: daha az yük
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
              ),
              delegate: SliverChildBuilderDelegate(
                    (context, index) => RepaintBoundary(
                  child: BookCard(
                    book: _filteredBooks[index],
                    onTap: () => _openBook(_filteredBooks[index]),
                  ),
                ),
                childCount: _filteredBooks.length,
                addRepaintBoundaries: true,
                addAutomaticKeepAlives: true,
                addSemanticIndexes: false,  // ✅ Optimize
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: Container(
        margin: const EdgeInsets.only(bottom: 16),
        child: FloatingActionButton.extended(
          onPressed: _isScanning ? null : _pickFileAndScanFolder,
          icon: const Icon(Icons.add, color: Colors.white),
          label: Text(
            'Dosya Ekle',
            style: GoogleFonts.inter(color: Colors.white),
          ),
          backgroundColor: Colors.blue[800],
          elevation: 4,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
    );
  }

  Widget _buildShimmerGrid() {
    final isDark = AdaptiveTheme.of(context).mode == AdaptiveThemeMode.dark;
    return SliverGrid(
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 0.75,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
      ),
      delegate: SliverChildBuilderDelegate(
            (context, index) => Shimmer.fromColors(
          baseColor: isDark ? Colors.grey[900]! : Colors.grey[300]!,
          highlightColor: isDark ? Colors.grey[800]! : Colors.grey[100]!,
          child: Container(
            decoration: BoxDecoration(
              color: isDark ? Colors.grey[900] : Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
        childCount: 6,
      ),
    );
  }

  Widget _buildEmptyState() {
    final isDark = AdaptiveTheme.of(context).mode == AdaptiveThemeMode.dark;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.library_books, size: 80, color: isDark ? Colors.grey[700] : Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            _searchController.text.isNotEmpty ? 'Sonuç Bulunamadı' : 'Kitaplığın Boş',
            style: GoogleFonts.inter(
              fontSize: 22,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white : Colors.black,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _searchController.text.isNotEmpty
                ? '🔍 "${_searchController.text}" ile eşleşen kitap yok.'
                : '📂 İndirilenler klasörü otomatik taranır.\n"Dosya Ekle" butonu ile başka klasörler ekleyebilirsin.',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              color: isDark ? Colors.grey[400] : Colors.grey[600],
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 32),
          if (_searchController.text.isEmpty) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton.icon(
                  onPressed: _addFolder,
                  icon: const Icon(Icons.folder_open, color: Colors.white),
                  label: Text(
                    'Klasör Ekle',
                    style: GoogleFonts.inter(color: Colors.white),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue[800],
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: _scanLibrary,
                  icon: Icon(Icons.refresh, color: isDark ? Colors.blue[300] : Colors.blue[700]),
                  label: Text(
                    'Tümünü Tara',
                    style: GoogleFonts.inter(
                      color: isDark ? Colors.white : Colors.black,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: isDark ? Colors.blue[300]! : Colors.blue[700]!),
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}