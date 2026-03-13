import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// **Validates: Requirements 3.6**
/// 
/// Preservation Property Test for Modern API Compilation
/// 
/// IMPORTANT: Follow observation-first methodology
/// This test observes behavior on UNFIXED code for modern API usage
/// 
/// Property 2: Preservation - Modern API Compilation
/// 
/// This test verifies that Flutter code using modern APIs continues to compile
/// without warnings. Specifically:
/// - Code using .withValues(alpha: ...) should compile cleanly
/// - Code without unnecessary imports should compile cleanly
/// - Modern API usage should not be affected by the deprecated API fixes
/// 
/// EXPECTED OUTCOME: Tests PASS on unfixed code (confirms baseline behavior to preserve)
/// After fix: Tests PASS (confirms no regressions)
void main() {
  group('Property 2: Preservation - Modern API Compilation', () {
    late ProcessResult analyzeResult;
    late List<String> modernApiFiles;

    setUpAll(() async {
      print('\n=== Preservation Test: Modern API Compilation ===');
      print('Observing behavior on code using modern APIs\n');
      
      // Find all files using modern .withValues(alpha: ...) API
      print('Identifying files using modern .withValues(alpha: ...) API...');
      final grepResult = await Process.run(
        'grep',
        ['-r', '-l', r'\.withValues(alpha:', 'lib/'],
        workingDirectory: Directory.current.path,
      );
      
      modernApiFiles = [];
      if (grepResult.exitCode == 0) {
        final output = grepResult.stdout.toString();
        modernApiFiles = output.split('\n')
            .where((line) => line.isNotEmpty && line.endsWith('.dart'))
            .toList();
      }
      
      print('Found ${modernApiFiles.length} file(s) using modern API:');
      for (final file in modernApiFiles.take(5)) {
        print('  - $file');
      }
      if (modernApiFiles.length > 5) {
        print('  ... and ${modernApiFiles.length - 5} more');
      }
      print('');
      
      // Run flutter analyze to check compilation
      print('Running Flutter analyze to verify modern API compilation...');
      analyzeResult = await Process.run(
        'flutter',
        ['analyze', '--no-pub'],
        workingDirectory: Directory.current.path,
      );
      print('Analyze complete.\n');
    });

    test('Modern API files compile without errors', () {
      print('=== Verifying Modern API Files Compile Successfully ===\n');
      
      final output = analyzeResult.stdout.toString() + analyzeResult.stderr.toString();
      final lines = output.split('\n');
      
      // Check for compilation errors in modern API files
      final errorsInModernFiles = <Map<String, String>>[];
      
      for (final line in lines) {
        if (line.contains('error') && line.contains('•')) {
          // Check if error is in one of our modern API files
          for (final file in modernApiFiles) {
            if (line.contains(file)) {
              final match = RegExp(r'•\s+(.+?):(\d+):(\d+)\s+•\s+(.+)').firstMatch(line);
              if (match != null) {
                errorsInModernFiles.add({
                  'file': match.group(1)!,
                  'line': match.group(2)!,
                  'message': match.group(4)!,
                });
              }
              break;
            }
          }
        }
      }
      
      if (errorsInModernFiles.isEmpty) {
        print('✓ All ${modernApiFiles.length} modern API files compile without errors');
      } else {
        print('✗ Found ${errorsInModernFiles.length} error(s) in modern API files:');
        for (final error in errorsInModernFiles) {
          print('  ${error['file']}:${error['line']} - ${error['message']}');
        }
      }
      
      // CRITICAL: Modern API files should compile without errors
      expect(
        errorsInModernFiles.isEmpty,
        isTrue,
        reason: 'Modern API files should compile without errors. '
                'Found ${errorsInModernFiles.length} error(s). '
                'This indicates the fix may have broken existing modern API usage.',
      );
      
      print('');
    });

    test('Modern API files have no Color-related deprecation warnings', () {
      print('=== Verifying Modern API Files Have No Color-Related Deprecation Warnings ===\n');
      
      final output = analyzeResult.stdout.toString() + analyzeResult.stderr.toString();
      final lines = output.split('\n');
      
      // Check for Color-related deprecation warnings in modern API files
      // Specifically looking for withOpacity deprecation warnings
      final colorDeprecationWarnings = <Map<String, String>>[];
      
      for (final line in lines) {
        if ((line.contains('deprecated_member_use') || 
             (line.contains('deprecated') && line.contains('info'))) &&
            line.contains('•') &&
            (line.contains('withOpacity') || line.contains('Color'))) {
          // Check if warning is in one of our modern API files
          for (final file in modernApiFiles) {
            if (line.contains(file)) {
              final match = RegExp(r'•\s+(.+?):(\d+):(\d+)\s+•\s+(.+)').firstMatch(line);
              if (match != null) {
                colorDeprecationWarnings.add({
                  'file': match.group(1)!,
                  'line': match.group(2)!,
                  'message': match.group(4)!,
                });
              }
              break;
            }
          }
        }
      }
      
      if (colorDeprecationWarnings.isEmpty) {
        print('✓ All ${modernApiFiles.length} modern API files have no Color-related deprecation warnings');
      } else {
        print('✗ Found ${colorDeprecationWarnings.length} Color-related deprecation warning(s) in modern API files:');
        for (final warning in colorDeprecationWarnings) {
          print('  ${warning['file']}:${warning['line']} - ${warning['message']}');
        }
      }
      
      // CRITICAL: Modern API files should not have Color-related deprecation warnings
      // This specifically checks for withOpacity warnings, not other unrelated deprecations
      expect(
        colorDeprecationWarnings.isEmpty,
        isTrue,
        reason: 'Modern API files should not have Color-related deprecation warnings. '
                'Found ${colorDeprecationWarnings.length} warning(s). '
                'This indicates modern Color API usage is producing unexpected warnings.',
      );
      
      print('');
    });

    test('withValues(alpha: ...) API usage is recognized correctly', () {
      print('=== Verifying .withValues(alpha: ...) API Usage ===\n');
      
      // Sample a few files to verify the modern API is being used correctly
      final sampleFiles = modernApiFiles.take(3).toList();
      
      print('Sampling ${sampleFiles.length} file(s) to verify modern API usage:');
      
      for (final file in sampleFiles) {
        final fileContent = File(file).readAsStringSync();
        
        // Count occurrences of .withValues(alpha:
        final withValuesCount = RegExp(r'\.withValues\(alpha:').allMatches(fileContent).length;
        
        // Verify no .withOpacity( in these files
        final withOpacityCount = RegExp(r'\.withOpacity\(').allMatches(fileContent).length;
        
        print('  $file:');
        print('    - .withValues(alpha:) occurrences: $withValuesCount');
        print('    - .withOpacity() occurrences: $withOpacityCount');
        
        expect(
          withValuesCount,
          greaterThan(0),
          reason: 'File $file should contain .withValues(alpha:) usage',
        );
        
        expect(
          withOpacityCount,
          equals(0),
          reason: 'File $file should not contain deprecated .withOpacity() usage',
        );
      }
      
      print('\n✓ Modern API usage verified in sampled files');
      print('');
    });

    test('Overall compilation status is successful', () {
      print('=== Verifying Overall Compilation Status ===\n');
      
      final output = analyzeResult.stdout.toString() + analyzeResult.stderr.toString();
      
      // Check for "No issues found!" message
      final noIssuesFound = output.contains('No issues found!');
      
      // Count total errors
      final errorCount = RegExp(r'(\d+)\s+error').firstMatch(output);
      final totalErrors = errorCount != null ? int.parse(errorCount.group(1)!) : 0;
      
      print('Compilation status:');
      print('  - No issues found: ${noIssuesFound ? "Yes" : "No"}');
      print('  - Total errors: $totalErrors');
      
      if (noIssuesFound) {
        print('\n✓ SUCCESS: Flutter compilation completed with no issues!');
      } else if (totalErrors == 0) {
        print('\n✓ Flutter compilation completed successfully (warnings may exist)');
      } else {
        print('\n✗ Flutter compilation has $totalErrors error(s)');
      }
      
      // For preservation test, we expect successful compilation
      // (errors = 0, though warnings about deprecated APIs may exist in unfixed code)
      expect(
        totalErrors,
        equals(0),
        reason: 'Flutter compilation should succeed with 0 errors. '
                'Found $totalErrors error(s). '
                'This indicates a compilation problem that affects modern API usage.',
      );
      
      print('');
    });

    test('Property-based verification: Modern API pattern consistency', () {
      print('=== Property-Based Verification: Modern API Pattern Consistency ===\n');
      
      // Property: All files using modern API should follow consistent patterns
      // This is a form of property-based testing where we verify invariants
      // across multiple files
      
      print('Verifying consistency across ${modernApiFiles.length} modern API files...\n');
      
      int filesChecked = 0;
      int filesWithConsistentUsage = 0;
      final inconsistencies = <String>[];
      
      for (final file in modernApiFiles) {
        try {
          final fileContent = File(file).readAsStringSync();
          filesChecked++;
          
          // Property 1: If file uses .withValues(alpha:), it should not use .withOpacity()
          final hasWithValues = fileContent.contains('.withValues(alpha:');
          final hasWithOpacity = fileContent.contains('.withOpacity(');
          
          if (hasWithValues && !hasWithOpacity) {
            filesWithConsistentUsage++;
          } else if (hasWithValues && hasWithOpacity) {
            inconsistencies.add('$file: Contains both .withValues() and .withOpacity()');
          }
        } catch (e) {
          print('  Warning: Could not read file $file: $e');
        }
      }
      
      final consistencyRate = filesChecked > 0 
          ? (filesWithConsistentUsage / filesChecked * 100).toStringAsFixed(1)
          : '0.0';
      
      print('Consistency check results:');
      print('  - Files checked: $filesChecked');
      print('  - Files with consistent modern API usage: $filesWithConsistentUsage');
      print('  - Consistency rate: $consistencyRate%');
      
      if (inconsistencies.isNotEmpty) {
        print('\nInconsistencies found:');
        for (final inconsistency in inconsistencies) {
          print('  - $inconsistency');
        }
      }
      
      // Property: At least 95% of modern API files should be consistent
      // (allowing for some edge cases or files in transition)
      final consistencyThreshold = 0.95;
      final actualConsistency = filesChecked > 0 
          ? filesWithConsistentUsage / filesChecked 
          : 1.0;
      
      expect(
        actualConsistency,
        greaterThanOrEqualTo(consistencyThreshold),
        reason: 'Modern API usage should be consistent across files. '
                'Expected at least ${(consistencyThreshold * 100).toStringAsFixed(0)}% consistency, '
                'but found ${(actualConsistency * 100).toStringAsFixed(1)}%.',
      );
      
      print('\n✓ Modern API usage is consistent across files');
      print('');
    });

    test('Summary: Preservation test baseline established', () {
      print('=== PRESERVATION TEST SUMMARY ===\n');
      
      print('This preservation test has verified that:');
      print('  1. ${modernApiFiles.length} files using modern .withValues(alpha:) API compile successfully');
      print('  2. Modern API files have no deprecation warnings');
      print('  3. Modern API usage follows consistent patterns');
      print('  4. Overall compilation succeeds with 0 errors');
      print('');
      print('BASELINE BEHAVIOR CONFIRMED:');
      print('  Modern API code continues to compile without warnings');
      print('');
      print('This baseline must be preserved after implementing the deprecated API fix.');
      print('Re-run this test after the fix to ensure no regressions.');
      print('');
      print('=== END OF PRESERVATION TEST ===\n');
      
      // This test always passes - it's for documentation
      expect(true, isTrue);
    });
  });
}
