import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class MediaService {
  final ImagePicker _picker = ImagePicker();
  final AudioRecorder _audioRecorder = AudioRecorder();

  Future<File?> pickImage(ImageSource source) async {
    final XFile? image = await _picker.pickImage(source: source);
    if (image != null) {
      return File(image.path);
    }
    return null;
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
      await _audioRecorder.start(const RecordConfig(), path: path);
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
