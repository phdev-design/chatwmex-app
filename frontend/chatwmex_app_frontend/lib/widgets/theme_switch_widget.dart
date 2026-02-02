import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/theme_provider.dart';

// 簡單的主題切換按鈕
class ThemeToggleButton extends StatelessWidget {
  const ThemeToggleButton({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeProvider>(
      builder: (context, themeProvider, child) {
        return IconButton(
          onPressed: themeProvider.toggleTheme,
          icon: AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            transitionBuilder: (child, animation) {
              return RotationTransition(
                turns: animation,
                child: child,
              );
            },
            child: Icon(
              themeProvider.currentThemeIcon,
              key: ValueKey(themeProvider.themeMode),
            ),
          ),
          tooltip: '切換主題',
        );
      },
    );
  }
}

// 主題切換浮動按鈕
class ThemeFloatingActionButton extends StatelessWidget {
  const ThemeFloatingActionButton({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeProvider>(
      builder: (context, themeProvider, child) {
        return FloatingActionButton.small(
          onPressed: themeProvider.toggleTheme,
          tooltip: '切換主題',
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            transitionBuilder: (child, animation) {
              return ScaleTransition(
                scale: animation,
                child: child,
              );
            },
            child: Icon(
              themeProvider.currentThemeIcon,
              key: ValueKey(themeProvider.themeMode),
            ),
          ),
        );
      },
    );
  }
}

// 主題選擇器下拉菜單
class ThemeDropdownButton extends StatelessWidget {
  const ThemeDropdownButton({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeProvider>(
      builder: (context, themeProvider, child) {
        return PopupMenuButton<ThemeMode>(
          icon: Icon(themeProvider.currentThemeIcon),
          tooltip: '選擇主題',
          onSelected: (ThemeMode mode) {
            themeProvider.setThemeMode(mode);
          },
          itemBuilder: (BuildContext context) => [
            PopupMenuItem<ThemeMode>(
              value: ThemeMode.light,
              child: Row(
                children: [
                  const Icon(Icons.light_mode),
                  const SizedBox(width: 8),
                  const Text('淺色模式'),
                  if (themeProvider.themeMode == ThemeMode.light)
                    const Spacer(),
                  if (themeProvider.themeMode == ThemeMode.light)
                    Icon(
                      Icons.check,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                ],
              ),
            ),
            PopupMenuItem<ThemeMode>(
              value: ThemeMode.dark,
              child: Row(
                children: [
                  const Icon(Icons.dark_mode),
                  const SizedBox(width: 8),
                  const Text('深色模式'),
                  if (themeProvider.themeMode == ThemeMode.dark)
                    const Spacer(),
                  if (themeProvider.themeMode == ThemeMode.dark)
                    Icon(
                      Icons.check,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                ],
              ),
            ),
            PopupMenuItem<ThemeMode>(
              value: ThemeMode.system,
              child: Row(
                children: [
                  const Icon(Icons.settings_brightness),
                  const SizedBox(width: 8),
                  const Text('跟隨系統'),
                  if (themeProvider.themeMode == ThemeMode.system)
                    const Spacer(),
                  if (themeProvider.themeMode == ThemeMode.system)
                    Icon(
                      Icons.check,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

// 主題狀態顯示卡片
class ThemeStatusCard extends StatelessWidget {
  const ThemeStatusCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeProvider>(
      builder: (context, themeProvider, child) {
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    themeProvider.currentThemeIcon,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '當前主題',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      Text(
                        themeProvider.currentThemeName,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ],
                  ),
                ),
                ThemeToggleButton(),
              ],
            ),
          ),
        );
      },
    );
  }
}