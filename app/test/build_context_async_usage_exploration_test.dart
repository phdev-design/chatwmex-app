import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// **Validates: Requirements 1.5**
/// 
/// Bug Condition Exploration Test for BuildContext Usage After Async
/// 
/// CRITICAL: This test MUST FAIL on unfixed code - failure confirms the bug exists
/// DO NOT attempt to fix the test or the code when it fails
/// NOTE: This test encodes the expected behavior - it will validate the fix when it passes after implementation
/// GOAL: Surface counterexamples that demonstrate the bug exists
/// 
/// Scoped PBT Approach: Scope to BuildContext usage after await in:
/// - contact_info_page.dart
/// - notification_service.dart
/// - qr_scanner_page.dart
/// 
/// This test verifies that accessing BuildContext after await causes crash when widget is unmounted.
/// The test assertions verify context.mounted check prevents crash.
/// 
/// EXPECTED OUTCOME: Test FAILS on unfixed code (this proves the bug exists)
/// After fix: Test PASSES (all async BuildContext usage has mounted checks)
void main() {
  group('Bug Condition 5: BuildContext Usage After Async Operations', () {
    test('Property 1: Bug Condition - Unmounted Context Access Crash', () async {
      print('\n=== Analyzing BuildContext Usage After Async Operations ===');
      print('Checking for missing context.mounted checks in async functions\n');
      
      // Define the files to check based on bug report
      final filesToCheck = [
        'lib/features/chat/ui/contact_info_page.dart',
        'lib/core/notification/notification_service.dart',
        'lib/features/auth/ui/qr_scanner_page.dart',
      ];
      
      final List<Map<String, dynamic>> counterexamples = [];
      
      for (final filePath in filesToCheck) {
        final file = File(filePath);
        
        if (!await file.exists()) {
          print('⚠ File not found: $filePath');
          continue;
        }
        
        final content = await file.readAsString();
        final lines = content.split('\n');
        
        print('Analyzing: $filePath');
        
        // Find async functions that use context after await
        final violations = _findContextUsageViolations(lines, filePath);
        
        if (violations.isNotEmpty) {
          counterexamples.addAll(violations);
          print('  ✗ Found ${violations.length} violation(s)');
          for (final violation in violations) {
            print('    Line ${violation['line']}: ${violation['context']}');
          }
        } else {
          print('  ✓ No violations found');
        }
        print('');
      }
      
      // Document counterexamples
      if (counterexamples.isNotEmpty) {
        print('=== COUNTEREXAMPLES FOUND ===');
        print('The following async functions use BuildContext after await without mounted checks:\n');
        
        for (final example in counterexamples) {
          print('File: ${example['file']}');
          print('Line: ${example['line']}');
          print('Function: ${example['function']}');
          print('Issue: ${example['issue']}');
          print('Context: ${example['context']}');
          print('');
        }
        
        print('Total counterexamples: ${counterexamples.length}');
        print('=== END OF COUNTEREXAMPLES ===\n');
      }
      
      // CRITICAL: This assertion verifies all async BuildContext usage has mounted checks
      // On UNFIXED code, this test WILL FAIL (expected behavior - proves bug exists)
      // After fix, this test WILL PASS (all usage has proper checks)
      expect(
        counterexamples.isEmpty,
        isTrue,
        reason: 'All async functions should check context.mounted before using BuildContext after await. '
                'Found ${counterexamples.length} violation(s). '
                'This failure confirms the bug exists in the unfixed codebase.',
      );
      
      print('✓ SUCCESS: All async BuildContext usage has proper mounted checks!');
      print('No unmounted context access risks detected.\n');
    });
  });
}

/// Analyzes code lines to find BuildContext usage violations after await
List<Map<String, dynamic>> _findContextUsageViolations(
  List<String> lines,
  String filePath,
) {
  final violations = <Map<String, dynamic>>[];
  
  // Track state as we scan through the file
  String? currentFunction;
  int? functionStartLine;
  bool inAsyncFunction = false;
  bool hasSeenAwait = false;
  bool hasMountedCheck = false;
  
  for (int i = 0; i < lines.length; i++) {
    final line = lines[i].trim();
    final lineNumber = i + 1;
    
    // Detect function declarations
    if (_isFunctionDeclaration(line)) {
      // Save previous function violations if any
      if (inAsyncFunction && hasSeenAwait && !hasMountedCheck && currentFunction != null) {
        // Check if there was any context usage after await
        final contextUsages = _findContextUsagesInFunction(
          lines,
          functionStartLine!,
          i,
        );
        
        if (contextUsages.isNotEmpty) {
          for (final usage in contextUsages) {
            violations.add({
              'file': filePath,
              'line': usage['line'],
              'function': currentFunction,
              'issue': 'BuildContext used after await without mounted check',
              'context': usage['code'],
            });
          }
        }
      }
      
      // Reset for new function
      currentFunction = _extractFunctionName(line);
      functionStartLine = lineNumber;
      inAsyncFunction = line.contains('async');
      hasSeenAwait = false;
      hasMountedCheck = false;
      continue;
    }
    
    // Track await statements
    if (inAsyncFunction && line.contains('await')) {
      hasSeenAwait = true;
    }
    
    // Track mounted checks
    if (line.contains('context.mounted') || 
        line.contains('mounted)') ||
        line.contains('!mounted')) {
      hasMountedCheck = true;
    }
    
    // Detect end of function (closing brace at start of line)
    if (line.startsWith('}') && currentFunction != null) {
      // Check if this function had violations
      if (inAsyncFunction && hasSeenAwait && !hasMountedCheck) {
        final contextUsages = _findContextUsagesInFunction(
          lines,
          functionStartLine!,
          i,
        );
        
        if (contextUsages.isNotEmpty) {
          for (final usage in contextUsages) {
            violations.add({
              'file': filePath,
              'line': usage['line'],
              'function': currentFunction,
              'issue': 'BuildContext used after await without mounted check',
              'context': usage['code'],
            });
          }
        }
      }
      
      // Reset state
      currentFunction = null;
      functionStartLine = null;
      inAsyncFunction = false;
      hasSeenAwait = false;
      hasMountedCheck = false;
    }
  }
  
  return violations;
}

/// Checks if a line is a function declaration
bool _isFunctionDeclaration(String line) {
  // Match various function declaration patterns
  return (line.contains('Future<') || line.contains('void ') || line.contains('Future ')) &&
         (line.contains('(') && !line.contains('=>')) &&
         !line.startsWith('//') &&
         !line.startsWith('*') &&
         !line.contains('return');
}

/// Extracts function name from declaration line
String _extractFunctionName(String line) {
  // Try to extract function name
  final match = RegExp(r'(?:Future<[^>]+>|void|Future)\s+(\w+)\s*\(').firstMatch(line);
  if (match != null) {
    return match.group(1) ?? 'unknown';
  }
  return 'unknown';
}

/// Finds BuildContext usages in a function after await statements
List<Map<String, dynamic>> _findContextUsagesInFunction(
  List<String> lines,
  int startLine,
  int endLine,
) {
  final usages = <Map<String, dynamic>>[];
  bool hasSeenAwait = false;
  bool hasMountedCheckAfterAwait = false;
  
  for (int i = startLine - 1; i < endLine && i < lines.length; i++) {
    final line = lines[i].trim();
    final lineNumber = i + 1;
    
    // Track await
    if (line.contains('await')) {
      hasSeenAwait = true;
      hasMountedCheckAfterAwait = false; // Reset for each await
    }
    
    // Track mounted check after await
    if (hasSeenAwait && (line.contains('context.mounted') || 
                         line.contains('mounted)') ||
                         line.contains('!mounted'))) {
      hasMountedCheckAfterAwait = true;
    }
    
    // Check for context usage after await without mounted check
    if (hasSeenAwait && !hasMountedCheckAfterAwait) {
      // Look for various context usage patterns
      final contextPatterns = [
        'Navigator.of(context)',
        'Navigator.pop(context)',
        'ScaffoldMessenger.of(context)',
        'context.pop(',
        'context.go(',
        'context.push(',
        'showDialog(',
        'showModalBottomSheet(',
        'Theme.of(context)',
      ];
      
      for (final pattern in contextPatterns) {
        if (line.contains(pattern)) {
          usages.add({
            'line': lineNumber,
            'code': line,
          });
          break; // Only report once per line
        }
      }
    }
  }
  
  return usages;
}
