import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// **Validates: Requirements 1.6**
/// 
/// Bug Condition Exploration Test for Deprecated API Warnings
/// 
/// CRITICAL: This test MUST FAIL on unfixed code - failure confirms the bug exists
/// DO NOT attempt to fix the test or the code when it fails
/// NOTE: This test encodes the expected behavior - it will validate the fix when it passes after implementation
/// GOAL: Surface counterexamples that demonstrate the bug exists
/// 
/// Scoped PBT Approach: Scope to Color.withOpacity() usage and unnecessary foundation.dart imports
/// 
/// This test verifies that Flutter code produces deprecation warnings for:
/// - Color.withOpacity() usage (should use .withValues(alpha: ...) instead)
/// - Unnecessary import 'package:flutter/foundation.dart'
/// - Other deprecated API usage (e.g., Radio widget properties)
/// 
/// EXPECTED OUTCOME: Test FAILS on unfixed code (this proves the bug exists)
/// After fix: Test PASSES (no deprecation warnings)
void main() {
  group('Bug Condition 6: Deprecated API Warnings', () {
    late ProcessResult analyzeResult;

    setUpAll(() async {
      // Run flutter analyze to check for deprecation warnings
      print('\n=== Running Flutter Analyze for Deprecated API Warnings ===');
      analyzeResult = await Process.run(
        'flutter',
        ['analyze', '--no-pub'],
        workingDirectory: Directory.current.path,
      );
    });

    test('Property 1: Bug Condition - No deprecated API warnings should exist', () {
      final output = analyzeResult.stdout.toString() + analyzeResult.stderr.toString();
      
      print('\n=== Checking for Deprecated API Warnings ===');
      print('Testing that Flutter compilation produces no deprecation warnings\n');
      
      // Parse all deprecated_member_use warnings
      final lines = output.split('\n');
      final deprecatedWarnings = <Map<String, String>>[];
      
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        if (line.contains('deprecated_member_use') || 
            line.contains('deprecated') && line.contains('info')) {
          // Extract file path and line number
          final match = RegExp(r'•\s+(.+?):(\d+):(\d+)\s+•\s+deprecated').firstMatch(line);
          if (match != null) {
            final file = match.group(1)!;
            final lineNum = match.group(2)!;
            
            // Get the deprecation message from the line
            final messageMatch = RegExp(r"'(.+?)'\s+is deprecated").firstMatch(line);
            final apiName = messageMatch?.group(1) ?? 'unknown';
            
            deprecatedWarnings.add({
              'file': file,
              'line': lineNum,
              'api': apiName,
              'fullMessage': line.trim(),
            });
          }
        }
      }
      
      // Check for Color.withOpacity() usage specifically
      print('Checking for Color.withOpacity() usage:');
      final withOpacityWarnings = deprecatedWarnings.where((w) => 
        w['api']!.contains('withOpacity')
      ).toList();
      
      if (withOpacityWarnings.isEmpty) {
        print('✓ No Color.withOpacity() deprecation warnings found');
      } else {
        print('✗ Found ${withOpacityWarnings.length} Color.withOpacity() warning(s):');
        for (final warning in withOpacityWarnings) {
          print('  ${warning['file']}:${warning['line']} - ${warning['api']}');
        }
      }
      
      // Check for other deprecated API usage
      print('\nChecking for other deprecated API usage:');
      final otherWarnings = deprecatedWarnings.where((w) => 
        !w['api']!.contains('withOpacity')
      ).toList();
      
      if (otherWarnings.isEmpty) {
        print('✓ No other deprecated API warnings found');
      } else {
        print('✗ Found ${otherWarnings.length} other deprecated API warning(s):');
        for (final warning in otherWarnings) {
          print('  ${warning['file']}:${warning['line']} - ${warning['api']}');
        }
      }
      
      // Document counterexamples
      if (deprecatedWarnings.isNotEmpty) {
        print('\n=== COUNTEREXAMPLES FOUND ===');
        print('The following deprecated API warnings exist in the codebase:\n');
        
        for (final warning in deprecatedWarnings) {
          print('File: ${warning['file']}');
          print('Line: ${warning['line']}');
          print('Deprecated API: ${warning['api']}');
          print('Full Message: ${warning['fullMessage']}');
          print('');
        }
        
        print('Total counterexamples: ${deprecatedWarnings.length}');
        print('=== END OF COUNTEREXAMPLES ===\n');
      }

      // CRITICAL: This assertion verifies no deprecation warnings exist
      // On UNFIXED code, this test WILL FAIL (expected behavior - proves bug exists)
      // After fix, this test WILL PASS (no deprecation warnings)
      expect(
        deprecatedWarnings.isEmpty,
        isTrue,
        reason: 'Flutter code should not produce deprecated API warnings. '
                'Found ${deprecatedWarnings.length} deprecation warning(s). '
                'This failure confirms the bug exists in the unfixed codebase.',
      );
      
      print('✓ SUCCESS: All deprecated API warnings have been fixed!');
      print('Flutter compilation produces no deprecation warnings.\n');
    });

    test('Property 2: Bug Condition - No unnecessary foundation.dart imports', () {
      final output = analyzeResult.stdout.toString() + analyzeResult.stderr.toString();
      
      print('\n=== Checking for Unnecessary foundation.dart Imports ===');
      
      // Check for unnecessary_import warnings related to foundation.dart
      final lines = output.split('\n');
      final unnecessaryImports = <Map<String, String>>[];
      
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        if (line.contains('unnecessary_import') && 
            (line.contains('foundation.dart') || 
             lines.length > i + 1 && lines[i + 1].contains('foundation.dart'))) {
          // Extract file path
          final match = RegExp(r'•\s+(.+?):(\d+):(\d+)\s+•\s+unnecessary_import').firstMatch(line);
          if (match != null) {
            unnecessaryImports.add({
              'file': match.group(1)!,
              'line': match.group(2)!,
              'message': line.trim(),
            });
          }
        }
      }
      
      // Also check by searching for files with foundation.dart imports
      // and cross-reference with analyze output
      print('Searching for foundation.dart imports in codebase...');
      
      final grepResult = Process.runSync(
        'grep',
        ['-r', '-n', "import 'package:flutter/foundation.dart'", 'lib/'],
        workingDirectory: Directory.current.path,
      );
      
      final foundationImports = <String>[];
      if (grepResult.exitCode == 0) {
        final grepOutput = grepResult.stdout.toString();
        final importLines = grepOutput.split('\n').where((l) => l.isNotEmpty).toList();
        foundationImports.addAll(importLines);
      }
      
      print('Found ${foundationImports.length} foundation.dart import(s) in lib/ directory');
      
      if (foundationImports.isNotEmpty) {
        print('\nFiles with foundation.dart imports:');
        for (final import in foundationImports) {
          final parts = import.split(':');
          if (parts.length >= 2) {
            print('  ${parts[0]}:${parts[1]}');
          }
        }
      }
      
      // Document findings
      if (unnecessaryImports.isNotEmpty) {
        print('\n=== COUNTEREXAMPLES: Unnecessary foundation.dart Imports ===');
        for (final import in unnecessaryImports) {
          print('File: ${import['file']}');
          print('Line: ${import['line']}');
          print('Message: ${import['message']}');
          print('');
        }
        print('Total unnecessary imports: ${unnecessaryImports.length}');
        print('=== END OF COUNTEREXAMPLES ===\n');
      }
      
      // Note: This test is informational for foundation.dart imports
      // The main issue is whether they are actually unnecessary (unused)
      // Flutter analyze will flag them as unnecessary_import if they're not used
      
      if (unnecessaryImports.isEmpty && foundationImports.isEmpty) {
        print('✓ No unnecessary foundation.dart imports found');
      } else if (unnecessaryImports.isEmpty && foundationImports.isNotEmpty) {
        print('ℹ Found ${foundationImports.length} foundation.dart import(s), but none flagged as unnecessary by analyzer');
        print('  This suggests they are being used in the code.');
      } else {
        print('✗ Found ${unnecessaryImports.length} unnecessary foundation.dart import(s)');
      }
      
      // CRITICAL: This assertion verifies no unnecessary imports exist
      // On UNFIXED code with unnecessary imports, this test WILL FAIL
      // After fix, this test WILL PASS
      expect(
        unnecessaryImports.isEmpty,
        isTrue,
        reason: 'Flutter code should not have unnecessary foundation.dart imports. '
                'Found ${unnecessaryImports.length} unnecessary import(s). '
                'This failure confirms the bug exists in the unfixed codebase.',
      );
      
      print('✓ SUCCESS: No unnecessary foundation.dart imports!\n');
    });

    test('Summary: Document all deprecation warnings for reference', () {
      final output = analyzeResult.stdout.toString() + analyzeResult.stderr.toString();
      
      print('\n=== SUMMARY: All Deprecation-Related Issues ===');
      
      // Extract all deprecation-related lines
      final lines = output.split('\n');
      final deprecationLines = lines.where((line) => 
        line.contains('deprecated') || 
        line.contains('unnecessary_import')
      ).toList();
      
      if (deprecationLines.isEmpty) {
        print('✓ No deprecation warnings or unnecessary imports found!');
      } else {
        print('Found ${deprecationLines.length} deprecation-related issue(s):\n');
        for (final line in deprecationLines) {
          if (line.trim().isNotEmpty) {
            print(line);
          }
        }
      }
      
      print('\n=== END OF SUMMARY ===\n');
      
      // This test always passes - it's just for documentation
      expect(true, isTrue);
    });
  });
}
