import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preference_app_group/shared_preference_app_group.dart';

class StorageService {
  final FlutterSecureStorage _storage;
  
  // ✅ 替換成你在 Xcode 中設定的 App Group ID (必須與 Swift 裡的一致)
  static const String _appGroupID = 'group.com.phdev.chat2mex';

  StorageService() : _storage = const FlutterSecureStorage();

  Future<void> save(String key, String value) async {
    await _storage.write(key: key, value: value);
    
    // ✅ 如果存的是 token，額外寫一份到 App Group 讓 iOS Extension 可以讀取
    if (key == 'jwt_token') {
      try {
        await SharedPreferenceAppGroup.setAppGroup(_appGroupID);
        await SharedPreferenceAppGroup.setString(key, value);
      } catch (e) {
        debugPrint('Failed to save token to App Group: $e');
      }
    }
  }

  Future<String?> read(String key) async {
    return await _storage.read(key: key);
  }

  Future<void> delete(String key) async {
    await _storage.delete(key: key);
    
    // ✅ 登出時，同步刪除 App Group 裡的 token 確保安全
    if (key == 'jwt_token') {
      try {
        await SharedPreferenceAppGroup.setAppGroup(_appGroupID);
        await SharedPreferenceAppGroup.remove(key);
      } catch (e) {
        debugPrint('Failed to remove token from App Group: $e');
      }
    }
  }

  Future<void> deleteAll() async {
    await _storage.deleteAll();
    
    // ✅ 清除所有資料時，也清掉 App Group 裡的 token
    try {
      await SharedPreferenceAppGroup.setAppGroup(_appGroupID);
      await SharedPreferenceAppGroup.remove('jwt_token');
    } catch (e) {
      debugPrint('Failed to clear App Group: $e');
    }
  }
}

final storageServiceProvider = Provider<StorageService>((ref) {
  return StorageService();
});