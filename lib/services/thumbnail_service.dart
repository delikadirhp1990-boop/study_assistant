import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

class ThumbnailService {
  static const MethodChannel _channel = MethodChannel('com.example.okuyombenya/thumbnail');

  static Future<String?> generateThumbnail(String filePath) async {
    try {
      if (kIsWeb) return null;
      final String? coverPath = await _channel.invokeMethod('generateThumbnail', {
        'filePath': filePath,
      });
      return coverPath;
    } on PlatformException catch (e) {
      debugPrint('❌ Native thumbnail hatası: ${e.message}');
      return null;
    } catch (e) {
      debugPrint('❌ Bilinmeyen hata: $e');
      return null;
    }
  }

  static Future<Map<String, dynamic>?> getFileInfo(String filePath) async {
    try {
      if (kIsWeb) return null;
      final Map<dynamic, dynamic>? result = await _channel.invokeMethod('getFileInfo', {
        'filePath': filePath,
      });
      return result?.cast<String, dynamic>();
    } on PlatformException catch (e) {
      debugPrint('❌ Native file info hatası: ${e.message}');
      return null;
    } catch (e) {
      debugPrint('❌ Bilinmeyen hata: $e');
      return null;
    }
  }
}