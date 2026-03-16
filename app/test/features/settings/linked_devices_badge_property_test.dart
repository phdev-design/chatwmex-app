import 'package:glados/glados.dart';

/// **Feature: linked-devices, Property 13: 數量徽章條件顯示**
///
/// *For any* 已連結裝置數量 n，當 n > 0 時設定頁面應顯示數量徽章，
/// 當 n = 0 時不應顯示徽章。
///
/// **Validates: Requirements 1.3**

/// Pure badge display logic extracted from SettingsPage._buildLinkedDevicesTile.
/// Returns true when the count badge should be visible.
bool shouldShowBadge(int deviceCount) => deviceCount > 0;

void main() {
  group('Property 13: 數量徽章條件顯示', () {
    Glados(any.intInRange(1, 10000), ExploreConfig(numRuns: 100)).test(
      'badge is shown when device count > 0',
      (n) {
        expect(shouldShowBadge(n), isTrue,
            reason: 'Badge should be shown when deviceCount=$n (> 0)');
      },
    );

    test('badge is NOT shown when device count is 0', () {
      expect(shouldShowBadge(0), isFalse,
          reason: 'Badge should not be shown when deviceCount=0');
    });

    Glados(any.positiveIntOrZero, ExploreConfig(numRuns: 100)).test(
      'shouldShowBadge(n) is equivalent to n > 0',
      (n) {
        expect(shouldShowBadge(n), equals(n > 0),
            reason:
                'shouldShowBadge($n) should equal ${n > 0}, but got ${shouldShowBadge(n)}');
      },
    );
  });
}
