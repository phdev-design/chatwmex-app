import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/theme_provider.dart';
import '../widgets/theme_switch_widget.dart';

class ThemeSettingsPage extends StatelessWidget {
  const ThemeSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('主題設置'),
        elevation: 0,
      ),
      body: Consumer<ThemeProvider>(
        builder: (context, themeProvider, child) {
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // 當前主題狀態卡片
              const ThemeStatusCard(),
              
              const SizedBox(height: 24),
              
              // 主題選項
              Text(
                '選擇主題',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              
              const SizedBox(height: 16),
              
              // 淺色模式選項
              Card(
                child: RadioListTile<ThemeMode>(
                  title: const Row(
                    children: [
                      Icon(Icons.light_mode),
                      SizedBox(width: 12),
                      Text('淺色模式'),
                    ],
                  ),
                  subtitle: const Text('使用淺色主題'),
                  value: ThemeMode.light,
                  groupValue: themeProvider.themeMode,
                  onChanged: (ThemeMode? value) {
                    if (value != null) {
                      themeProvider.setThemeMode(value);
                    }
                  },
                ),
              ),
              
              const SizedBox(height: 8),
              
              // 深色模式選項
              Card(
                child: RadioListTile<ThemeMode>(
                  title: const Row(
                    children: [
                      Icon(Icons.dark_mode),
                      SizedBox(width: 12),
                      Text('深色模式'),
                    ],
                  ),
                  subtitle: const Text('使用深色主題'),
                  value: ThemeMode.dark,
                  groupValue: themeProvider.themeMode,
                  onChanged: (ThemeMode? value) {
                    if (value != null) {
                      themeProvider.setThemeMode(value);
                    }
                  },
                ),
              ),
              
              const SizedBox(height: 8),
              
              // 跟隨系統選項
              Card(
                child: RadioListTile<ThemeMode>(
                  title: const Row(
                    children: [
                      Icon(Icons.settings_brightness),
                      SizedBox(width: 12),
                      Text('跟隨系統'),
                    ],
                  ),
                  subtitle: const Text('自動根據系統設置切換主題'),
                  value: ThemeMode.system,
                  groupValue: themeProvider.themeMode,
                  onChanged: (ThemeMode? value) {
                    if (value != null) {
                      themeProvider.setThemeMode(value);
                    }
                  },
                ),
              ),
              
              const SizedBox(height: 32),
              
              // 主題預覽區域
              Text(
                '主題預覽',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              
              const SizedBox(height: 16),
              
              // 預覽卡片
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.primary,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(
                              Icons.palette,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '主題預覽',
                                  style: Theme.of(context).textTheme.titleMedium,
                                ),
                                Text(
                                  '這是當前主題的外觀',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      
                      const SizedBox(height: 16),
                      
                      // 按鈕預覽
                      Row(
                        children: [
                          ElevatedButton(
                            onPressed: () {},
                            child: const Text('主要按鈕'),
                          ),
                          const SizedBox(width: 8),
                          OutlinedButton(
                            onPressed: () {},
                            child: const Text('次要按鈕'),
                          ),
                        ],
                      ),
                      
                      const SizedBox(height: 16),
                      
                      // 文字樣式預覽
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '大標題',
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                          Text(
                            '正文內容',
                            style: Theme.of(context).textTheme.bodyLarge,
                          ),
                          Text(
                            '小字說明',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              
              const SizedBox(height: 32),
              
              // 說明文字
              Card(
                color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.3),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Icon(
                        Icons.info_outline,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '主題說明',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '• 淺色模式：適合光線充足的環境\n'
                        '• 深色模式：適合昏暗環境，減少眼部疲勞\n'
                        '• 跟隨系統：自動根據設備設置切換',
                        style: Theme.of(context).textTheme.bodySmall,
                        textAlign: TextAlign.left,
                      ),
                    ],
                  ),
                ),
              ),
              
              const SizedBox(height: 32),
            ],
          );
        },
      ),
    );
  }
}