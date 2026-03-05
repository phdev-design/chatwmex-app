import 'package:app/models/chat_setting.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:app/core/network/network_service.dart';

final chatSettingServiceProvider = Provider<ChatSettingService>((ref) {
  final network = ref.watch(networkServiceProvider);
  return ChatSettingService(network);
});

class ChatSettingService {
  final NetworkService _network;

  ChatSettingService(this._network);

  Future<ChatSetting> getChatSetting(String chatID) async {
    final res = await _network.client.get('/chats/$chatID/settings');
    final data = res.data;
    if (data is Map<String, dynamic> && data.containsKey('data')) {
      return ChatSetting.fromJson(data['data']);
    }
    return ChatSetting.fromJson(data);
  }

  Future<ChatSetting> updateChatSetting(String chatID, int timerSeconds) async {
    final res = await _network.client.put('/chats/$chatID/settings', data: {
      'disappearing_timer': timerSeconds,
    });
    final data = res.data;
    if (data is Map<String, dynamic> && data.containsKey('data')) {
      return ChatSetting.fromJson(data['data']);
    }
    return ChatSetting.fromJson(data);
  }
}

final chatSettingProvider = FutureProvider.family<ChatSetting, String>((ref, chatID) async {
  final service = ref.watch(chatSettingServiceProvider);
  return service.getChatSetting(chatID);
});
