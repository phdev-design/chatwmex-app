import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path/path.dart' as p;

class MediaService {
  final ImagePicker _picker = ImagePicker();
  final AudioRecorder _audioRecorder = AudioRecorder();

  /// 選擇圖片並自動壓縮
  /// 
  /// 會自動將 HEIC 等格式轉換為 JPEG，並壓縮到 5MB 以下
  Future<File?> pickImage(ImageSource source) async {
    final XFile? image = await _picker.pickImage(
      source: source,
      // 設定最大寬度，避免過大的圖片
      maxWidth: 1920,
      maxHeight: 1920,
      // 圖片品質 (0-100)，85 是一個平衡品質和大小的好選擇
      imageQuality: 85,
    );
    
    if (image == null) return null;
    
    // 壓縮圖片
    final compressedFile = await compressImage(File(image.path));
    return compressedFile;
  }

  /// 壓縮圖片到 5MB 以下
  /// 
  /// 自動將 HEIC 等格式轉換為 JPEG
  /// 如果圖片已經小於 5MB，則不進行壓縮
  Future<File> compressImage(File imageFile) async {
    final fileSize = await imageFile.length();
    const maxSize = 5 * 1024 * 1024; // 5MB
    
    // 如果檔案已經小於 5MB，檢查格式
    if (fileSize < maxSize) {
      final ext = p.extension(imageFile.path).toLowerCase();
      // 如果是支援的格式，直接返回
      if (ext == '.jpg' || ext == '.jpeg' || ext == '.png' || ext == '.webp') {
        return imageFile;
      }
    }
    
    // 需要壓縮或轉換格式
    final dir = await getTemporaryDirectory();
    final targetPath = p.join(
      dir.path,
      'compressed_${DateTime.now().millisecondsSinceEpoch}.jpg',
    );
    
    // 計算壓縮品質
    int quality = 85;
    if (fileSize > maxSize) {
      // 根據檔案大小動態調整品質
      final ratio = maxSize / fileSize;
      quality = (85 * ratio).clamp(50, 85).toInt();
    }
    
    // 壓縮圖片
    final result = await FlutterImageCompress.compressAndGetFile(
      imageFile.path,
      targetPath,
      quality: quality,
      format: CompressFormat.jpeg,
      // 如果圖片太大，進一步縮小尺寸
      minWidth: fileSize > maxSize * 2 ? 1280 : 1920,
      minHeight: fileSize > maxSize * 2 ? 1280 : 1920,
    );
    
    if (result == null) {
      throw Exception('圖片壓縮失敗');
    }
    
    final compressedFile = File(result.path);
    final compressedSize = await compressedFile.length();
    
    // 如果壓縮後仍然超過 5MB，進一步降低品質
    if (compressedSize > maxSize) {
      final secondTargetPath = p.join(
        dir.path,
        'compressed2_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
      
      final secondResult = await FlutterImageCompress.compressAndGetFile(
        compressedFile.path,
        secondTargetPath,
        quality: 50,
        format: CompressFormat.jpeg,
        minWidth: 1280,
        minHeight: 1280,
      );
      
      if (secondResult != null) {
        return File(secondResult.path);
      }
    }
    
    return compressedFile;
  }

  Future<bool> hasMicrophonePermission() async {
    var status = await Permission.microphone.status;
    if (!status.isGranted) {
      status = await Permission.microphone.request();
    }
    return status.isGranted;
  }

  Future<void> startRecording(String path) async {
    if (await hasMicrophonePermission()) {
      await _audioRecorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc, // iOS + Android 通用 m4a
          bitRate: 128000,
          sampleRate: 44100,
          numChannels: 1,
        ),
        path: path,
      );
    } else {
      throw Exception('Microphone permission not granted');
    }
  }

  Future<String?> stopRecording() async {
    return await _audioRecorder.stop();
  }

  Future<String> getTemporaryAudioPath() async {
    final directory = await getTemporaryDirectory();
    return '${directory.path}/audio_${DateTime.now().millisecondsSinceEpoch}.m4a';
  }

  void dispose() {
    _audioRecorder.dispose();
  }
}

final mediaServiceProvider = Provider<MediaService>((ref) {
  final service = MediaService();
  ref.onDispose(() => service.dispose());
  return service;
});
