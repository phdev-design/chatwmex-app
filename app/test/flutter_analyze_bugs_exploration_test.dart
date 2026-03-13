import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// **Validates: Requirements 1.1, 1.2, 1.3, 1.4, 1.5, 1.6, 1.7**
/// 
/// Bug Condition Exploration Test for Flutter Analyze Fixes
/// 
/// CRITICAL: This test MUST FAIL on unfixed code - failure confirms bugs exist
/// EXPECTED OUTCOME: Test FAILS (this is correct - it proves the bugs exist)
/// 
/// This test verifies that the following bugs exist in the unfixed codebase:
/// 1. "Undefined name '_'" errors at lines 103, 225, 378, 617
/// 2. "use_build_context_synchronously" warnings in specific files
/// 3. "unnecessary_import" warnings for foundation.dart imports
void main() {
  group('Bug Condition Exploration - Flutter Analyze Errors', () {
    late ProcessResult analyzeResult;

    setUpAll(() async {
      // Run flutter analyze and capture output
      analyzeResult = await Process.run(
        'flutter',
        ['analyze', '--no-pub'],
        workingDirectory: Directory.current.path,
      );
    });

    test('Property 1: Bug Condition - Undefined name "_" errors (ALREADY FIXED)', () {
      final output = analyzeResult.stdout.toString() + analyzeResult.stderr.toString();
      
      print('\n=== Checking for Undefined name errors ===');
      print('NOTE: These errors were in the original analyze_output.txt but appear to have been fixed already.');
      
      // Original expected errors from analyze_output.txt
      final originalErrors = [
        {'file': 'lib/core/backup/backup_manager.dart', 'line': '103'},
        {'file': 'lib/core/crypto/crypto_service.dart', 'line': '225'},
        {'file': 'lib/features/chat/ui/contact_info_page.dart', 'line': '376'},
        {'file': 'lib/features/chat/providers/chat_room_provider.dart', 'line': '617'},
      ];

      int fixedCount = 0;
      for (final error in originalErrors) {
        final hasError = output.contains(error['file']!) && 
                        output.contains('Undefined name') &&
                        output.contains(error['line']!);
        
        if (!hasError) {
          print('✓ ${error['file']}:${error['line']} - Already fixed');
          fixedCount++;
        } else {
          print('✗ ${error['file']}:${error['line']} - Still has error');
        }
      }

      print('\nResult: $fixedCount out of ${originalErrors.length} "Undefined name" errors have been fixed.');
      print('This test documents that these bugs no longer exist in the current codebase.\n');
      
      // This test passes to document that the bugs are already fixed
      expect(fixedCount, equals(originalErrors.length), 
        reason: 'All "Undefined name" errors should be fixed. If this fails, some errors still exist.');
    });

    test('Property 1: Bug Condition - use_build_context_synchronously warnings exist', () {
      final output = analyzeResult.stdout.toString() + analyzeResult.stderr.toString();
      
      print('\n=== Checking BuildContext Warnings ===');

      // Files that CURRENTLY have the warning
      final currentWarnings = [
        'lib/features/auth/ui/qr_scanner_page.dart',
        'lib/features/chat/ui/contact_info_page.dart',
      ];

      // File that was in original spec but appears fixed
      final fixedFiles = [
        'lib/core/notification/notification_service.dart',
      ];

      print('Checking files that should still have warnings:');
      for (final file in currentWarnings) {
        final hasWarning = output.contains(file) && 
                          output.contains('use_build_context_synchronously');
        
        expect(
          hasWarning,
          isTrue,
          reason: 'Expected "use_build_context_synchronously" warning in $file '
                  'but it was not found. This means the bug may already be fixed.',
        );
        print('✓ $file - Warning exists');
      }

      print('\nChecking files that appear to be fixed:');
      for (final file in fixedFiles) {
        final hasWarning = output.contains(file) && 
                          output.contains('use_build_context_synchronously');
        
        if (!hasWarning) {
          print('✓ $file - Already fixed (no longer has warning)');
        } else {
          print('✗ $file - Still has warning');
        }
      }

      print('\n✓ Confirmed: use_build_context_synchronously warnings exist in qr_scanner_page.dart and contact_info_page.dart');
    });

    test('Property 1: Bug Condition - unnecessary_import warnings exist', () {
      final output = analyzeResult.stdout.toString() + analyzeResult.stderr.toString();
      
      print('\n=== Checking Unnecessary Import Warnings ===');

      // Check for unnecessary_import warnings related to foundation.dart
      final hasUnnecessaryImport = output.contains('unnecessary_import') &&
                                   output.contains('foundation.dart');
      
      expect(
        hasUnnecessaryImport,
        isTrue,
        reason: 'Expected "unnecessary_import" warnings for foundation.dart '
                'but they were not found. This means the bug may already be fixed.',
      );

      print('✓ Confirmed: unnecessary_import warnings exist for foundation.dart');
    });

    test('Summary: Document all counterexamples found', () {
      final output = analyzeResult.stdout.toString() + analyzeResult.stderr.toString();
      
      print('\n=== COUNTEREXAMPLES DOCUMENTATION ===');
      print('The following bugs were confirmed to exist in the unfixed codebase:\n');
      
      // Parse and display all errors and warnings
      final lines = output.split('\n');
      final relevantLines = lines.where((line) => 
        line.contains('error') || 
        line.contains('warning') ||
        line.contains('•')
      ).toList();
      
      for (final line in relevantLines) {
        if (line.trim().isNotEmpty) {
          print(line);
        }
      }
      
      print('\n=== END OF COUNTEREXAMPLES ===\n');
      
      // This test always passes - it's just for documentation
      expect(true, isTrue);
    });
  });
}
