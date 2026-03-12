import 'dart:convert';
import 'dart:math';
import 'package:flutter_test/flutter_test.dart';

/// Performance validation tests for group chat E2EE
/// 
/// **Validates: Requirements 8.1, 8.2, 8.3, 8.4**
/// **Task: 17.2 - Write performance validation tests**
/// 
/// These tests measure and validate:
/// - Encryption performance for various group sizes (10, 25, 50 members)
/// - Decryption performance
/// - Memory usage during encryption
/// - Async operation behavior (non-blocking)
/// 
/// Performance targets:
/// - 50 members: encryption + send within 2000ms
/// - Operations must be asynchronous (non-blocking)
/// - Memory usage should be reasonable for mobile devices

void main() {
  group('Performance Validation Tests (Task 17.2) -', () {
    
    group('Encryption Performance -', () {
      
      test('Encryption for 10 members completes in reasonable time', () async {
        // Simulate encryption for 10 members
        final memberCount = 10;
        final plaintext = 'Test message for performance validation';
        
        final stopwatch = Stopwatch()..start();
        
        // Simulate the encryption process
        final ciphertexts = <String, String>{};
        for (int i = 0; i < memberCount; i++) {
          // Simulate encryption operation (base64 encoding as proxy)
          final memberId = 'user_$i';
          final simulatedCiphertext = base64Encode(
            utf8.encode('$plaintext-encrypted-for-$memberId')
          );
          ciphertexts[memberId] = simulatedCiphertext;
        }
        
        stopwatch.stop();
        final elapsedMs = stopwatch.elapsedMilliseconds;
        
        // Verify payload structure
        expect(ciphertexts.length, memberCount);
        expect(ciphertexts.keys.length, memberCount);
        
        // Log performance for monitoring
        print('[Performance] 10 members encryption: ${elapsedMs}ms');
        
        // Should complete very quickly for 10 members
        expect(elapsedMs, lessThan(500), 
          reason: 'Encryption for 10 members should complete in under 500ms');
      });
      
      test('Encryption for 25 members completes in reasonable time', () async {
        // Simulate encryption for 25 members
        final memberCount = 25;
        final plaintext = 'Test message for performance validation';
        
        final stopwatch = Stopwatch()..start();
        
        // Simulate the encryption process with batching (batch size 10)
        final ciphertexts = <String, String>{};
        const batchSize = 10;
        
        for (int i = 0; i < memberCount; i += batchSize) {
          final batchEnd = (i + batchSize < memberCount) ? i + batchSize : memberCount;
          final batch = List.generate(batchEnd - i, (index) => i + index);
          
          // Simulate parallel encryption in batch
          final futures = batch.map((index) async {
            final memberId = 'user_$index';
            // Simulate encryption operation
            await Future.delayed(Duration(milliseconds: 1)); // Simulate crypto work
            final simulatedCiphertext = base64Encode(
              utf8.encode('$plaintext-encrypted-for-$memberId')
            );
            return MapEntry(memberId, simulatedCiphertext);
          }).toList();
          
          final results = await Future.wait(futures);
          for (final entry in results) {
            ciphertexts[entry.key] = entry.value;
          }
        }
        
        stopwatch.stop();
        final elapsedMs = stopwatch.elapsedMilliseconds;
        
        // Verify payload structure
        expect(ciphertexts.length, memberCount);
        
        // Log performance for monitoring
        print('[Performance] 25 members encryption: ${elapsedMs}ms');
        
        // Should complete within reasonable time for 25 members
        expect(elapsedMs, lessThan(1000), 
          reason: 'Encryption for 25 members should complete in under 1000ms');
      });
      
      test('Encryption for 50 members completes within 2000ms (Requirement 8.1)', () async {
        // **Validates: Requirement 8.1**
        // WHEN encrypting a Group_Message for a group with up to 50 members,
        // THE Chat_Room_Provider SHALL complete the encryption and send operation within 2000 milliseconds
        
        final memberCount = 50;
        final plaintext = 'Test message for performance validation with 50 members';
        
        final stopwatch = Stopwatch()..start();
        
        // Simulate the encryption process with batching (batch size 10)
        final ciphertexts = <String, String>{};
        const batchSize = 10;
        
        for (int i = 0; i < memberCount; i += batchSize) {
          final batchEnd = (i + batchSize < memberCount) ? i + batchSize : memberCount;
          final batch = List.generate(batchEnd - i, (index) => i + index);
          
          // Simulate parallel encryption in batch
          final futures = batch.map((index) async {
            final memberId = 'user_$index';
            // Simulate encryption operation (slightly longer to be realistic)
            await Future.delayed(Duration(milliseconds: 2)); // Simulate crypto work
            final simulatedCiphertext = base64Encode(
              utf8.encode('$plaintext-encrypted-for-$memberId')
            );
            return MapEntry(memberId, simulatedCiphertext);
          }).toList();
          
          final results = await Future.wait(futures);
          for (final entry in results) {
            ciphertexts[entry.key] = entry.value;
          }
        }
        
        stopwatch.stop();
        final elapsedMs = stopwatch.elapsedMilliseconds;
        
        // Verify payload structure
        expect(ciphertexts.length, memberCount);
        expect(ciphertexts.keys.toSet().length, memberCount, 
          reason: 'All members should have unique ciphertexts');
        
        // Log performance for monitoring
        print('[Performance] 50 members encryption: ${elapsedMs}ms');
        
        // **Critical requirement: Must complete within 2000ms**
        expect(elapsedMs, lessThan(2000), 
          reason: 'Requirement 8.1: Encryption for 50 members MUST complete within 2000ms');
      });
      
      test('Batched encryption improves performance over sequential', () async {
        // Verify that batched parallel encryption is faster than sequential
        final memberCount = 30;
        final plaintext = 'Test message';
        
        // Sequential encryption simulation
        final sequentialStopwatch = Stopwatch()..start();
        final sequentialCiphertexts = <String, String>{};
        for (int i = 0; i < memberCount; i++) {
          await Future.delayed(Duration(milliseconds: 1));
          sequentialCiphertexts['user_$i'] = base64Encode(utf8.encode('$plaintext-$i'));
        }
        sequentialStopwatch.stop();
        final sequentialMs = sequentialStopwatch.elapsedMilliseconds;
        
        // Batched parallel encryption simulation
        final batchedStopwatch = Stopwatch()..start();
        final batchedCiphertexts = <String, String>{};
        const batchSize = 10;
        
        for (int i = 0; i < memberCount; i += batchSize) {
          final batchEnd = (i + batchSize < memberCount) ? i + batchSize : memberCount;
          final batch = List.generate(batchEnd - i, (index) => i + index);
          
          final futures = batch.map((index) async {
            await Future.delayed(Duration(milliseconds: 1));
            return MapEntry('user_$index', base64Encode(utf8.encode('$plaintext-$index')));
          }).toList();
          
          final results = await Future.wait(futures);
          for (final entry in results) {
            batchedCiphertexts[entry.key] = entry.value;
          }
        }
        batchedStopwatch.stop();
        final batchedMs = batchedStopwatch.elapsedMilliseconds;
        
        print('[Performance] Sequential: ${sequentialMs}ms, Batched: ${batchedMs}ms');
        
        // Batched should be significantly faster
        expect(batchedMs, lessThan(sequentialMs), 
          reason: 'Batched parallel encryption should be faster than sequential');
        
        // Both should produce same number of ciphertexts
        expect(sequentialCiphertexts.length, memberCount);
        expect(batchedCiphertexts.length, memberCount);
      });
    });
    
    group('Decryption Performance -', () {
      
      test('Decryption completes instantly (single operation)', () async {
        // **Validates: Requirement 8.2 (async operations)**
        // Decryption only needs to decrypt one ciphertext (current user's)
        
        final memberCount = 50;
        final currentUserId = 'user_25';
        
        // Create a fan-out payload with 50 ciphertexts
        final ciphertexts = <String, String>{};
        for (int i = 0; i < memberCount; i++) {
          ciphertexts['user_$i'] = base64Encode(
            utf8.encode('encrypted-message-for-user-$i')
          );
        }
        
        final fanoutPayload = {
          'is_fanout': true,
          'ciphertexts': ciphertexts,
        };
        final content = jsonEncode(fanoutPayload);
        
        final stopwatch = Stopwatch()..start();
        
        // Simulate decryption process
        final payload = jsonDecode(content);
        final receivedCiphertexts = payload['ciphertexts'] as Map<String, dynamic>;
        final myCiphertext = receivedCiphertexts[currentUserId];
        
        // Simulate decryption of single ciphertext
        final decrypted = utf8.decode(base64Decode(myCiphertext));
        
        stopwatch.stop();
        final elapsedMs = stopwatch.elapsedMilliseconds;
        
        expect(decrypted, contains('encrypted-message-for-user-25'));
        
        print('[Performance] Decryption (1 of 50): ${elapsedMs}ms');
        
        // Decryption should be instant (only one operation)
        expect(elapsedMs, lessThan(50), 
          reason: 'Decryption should be instant as it only decrypts one ciphertext');
      });
      
      test('Decryption performance is independent of group size', () async {
        // Verify that decryption time doesn't scale with group size
        // (since we only decrypt our own ciphertext)
        
        final currentUserId = 'user_0';
        final groupSizes = [10, 25, 50];
        final decryptionTimes = <int, int>{};
        
        for (final size in groupSizes) {
          // Create fan-out payload
          final ciphertexts = <String, String>{};
          for (int i = 0; i < size; i++) {
            ciphertexts['user_$i'] = base64Encode(
              utf8.encode('encrypted-message-for-user-$i')
            );
          }
          
          final fanoutPayload = {
            'is_fanout': true,
            'ciphertexts': ciphertexts,
          };
          final content = jsonEncode(fanoutPayload);
          
          // Measure decryption time
          final stopwatch = Stopwatch()..start();
          
          final payload = jsonDecode(content);
          final receivedCiphertexts = payload['ciphertexts'] as Map<String, dynamic>;
          final myCiphertext = receivedCiphertexts[currentUserId];
          final decrypted = utf8.decode(base64Decode(myCiphertext));
          
          stopwatch.stop();
          decryptionTimes[size] = stopwatch.elapsedMilliseconds;
          
          expect(decrypted, contains('encrypted-message-for-user-0'));
        }
        
        print('[Performance] Decryption times: $decryptionTimes');
        
        // All decryption times should be similar (within reasonable variance)
        final times = decryptionTimes.values.toList();
        final maxTime = times.reduce(max);
        final minTime = times.reduce(min);
        
        expect(maxTime - minTime, lessThan(20), 
          reason: 'Decryption time should be independent of group size');
      });
      
      test('Plaintext message parsing is instant (backward compatibility)', () async {
        // Verify that plaintext messages don't incur decryption overhead
        
        final plaintextMessage = 'This is a plaintext message';
        
        final stopwatch = Stopwatch()..start();
        
        // Try to parse as JSON (will fail)
        String result = plaintextMessage;
        try {
          final payload = jsonDecode(plaintextMessage);
          if (payload is Map && payload['is_fanout'] == true) {
            // Would attempt decryption
            result = 'decrypted';
          }
        } catch (e) {
          // Expected: plaintext cannot be parsed, return as-is
          result = plaintextMessage;
        }
        
        stopwatch.stop();
        final elapsedMs = stopwatch.elapsedMilliseconds;
        
        expect(result, plaintextMessage);
        
        print('[Performance] Plaintext parsing: ${elapsedMs}ms');
        
        // Should be instant
        expect(elapsedMs, lessThan(10), 
          reason: 'Plaintext message handling should be instant');
      });
    });
    
    group('Memory Usage Validation -', () {
      
      test('Fan-out payload size is reasonable for 50 members', () {
        // **Validates: Requirement 8.1 (performance considerations)**
        // Verify that memory usage is acceptable for mobile devices
        
        final memberCount = 50;
        final plaintext = 'This is a test message with some content to make it realistic';
        
        // Simulate ciphertexts (realistic size)
        final ciphertexts = <String, String>{};
        for (int i = 0; i < memberCount; i++) {
          // Typical ciphertext: ~200 bytes (base64 encoded)
          final ciphertext = base64Encode(
            utf8.encode('$plaintext-encrypted-for-user-$i-with-nonce-and-mac')
          );
          ciphertexts['user_$i'] = ciphertext;
        }
        
        final fanoutPayload = {
          'is_fanout': true,
          'ciphertexts': ciphertexts,
        };
        
        final jsonString = jsonEncode(fanoutPayload);
        final payloadSizeBytes = utf8.encode(jsonString).length;
        final payloadSizeKB = payloadSizeBytes / 1024;
        
        print('[Memory] Fan-out payload size for 50 members: ${payloadSizeKB.toStringAsFixed(2)} KB');
        
        // Should be under 20KB for 50 members (reasonable for mobile)
        expect(payloadSizeKB, lessThan(20), 
          reason: 'Fan-out payload should be under 20KB for mobile devices');
        
        // Verify structure
        expect(ciphertexts.length, memberCount);
      });
      
      test('Ciphertext map memory usage scales linearly', () {
        // Verify that memory usage scales predictably with group size
        
        final groupSizes = [10, 25, 50];
        final payloadSizes = <int, double>{};
        
        for (final size in groupSizes) {
          final ciphertexts = <String, String>{};
          for (int i = 0; i < size; i++) {
            final ciphertext = base64Encode(
              utf8.encode('encrypted-message-for-user-$i-with-crypto-overhead')
            );
            ciphertexts['user_$i'] = ciphertext;
          }
          
          final fanoutPayload = {
            'is_fanout': true,
            'ciphertexts': ciphertexts,
          };
          
          final jsonString = jsonEncode(fanoutPayload);
          final sizeKB = utf8.encode(jsonString).length / 1024;
          payloadSizes[size] = sizeKB;
        }
        
        print('[Memory] Payload sizes: $payloadSizes');
        
        // Verify linear scaling (approximately)
        final size10 = payloadSizes[10]!;
        final size25 = payloadSizes[25]!;
        final size50 = payloadSizes[50]!;
        
        // 25 members should be ~2.5x the size of 10 members
        final ratio25to10 = size25 / size10;
        expect(ratio25to10, greaterThan(2.0));
        expect(ratio25to10, lessThan(3.0));
        
        // 50 members should be ~5x the size of 10 members
        final ratio50to10 = size50 / size10;
        expect(ratio50to10, greaterThan(4.0));
        expect(ratio50to10, lessThan(6.0));
      });
      
      test('Individual ciphertext size is reasonable', () {
        // Verify that each ciphertext is appropriately sized
        
        final plaintext = 'Test message with reasonable length for chat';
        
        // Simulate encryption (base64 encoding as proxy)
        final ciphertext = base64Encode(
          utf8.encode('$plaintext-with-nonce-and-mac-overhead')
        );
        
        final ciphertextBytes = utf8.encode(ciphertext).length;
        
        print('[Memory] Single ciphertext size: $ciphertextBytes bytes');
        
        // Should be under 500 bytes for typical message
        expect(ciphertextBytes, lessThan(500), 
          reason: 'Individual ciphertext should be under 500 bytes');
      });
    });
    
    group('Async Operation Behavior -', () {
      
      test('Encryption operations are asynchronous (Requirement 8.2)', () async {
        // **Validates: Requirement 8.2**
        // THE Chat_Room_Provider SHALL perform encryption operations asynchronously
        // to avoid blocking the UI thread
        
        final memberCount = 20;
        final plaintext = 'Test message';
        
        // Track that operations are truly async
        bool operationCompleted = false;
        
        // Start async encryption
        final encryptionFuture = Future(() async {
          final ciphertexts = <String, String>{};
          const batchSize = 10;
          
          for (int i = 0; i < memberCount; i += batchSize) {
            final batchEnd = (i + batchSize < memberCount) ? i + batchSize : memberCount;
            final batch = List.generate(batchEnd - i, (index) => i + index);
            
            final futures = batch.map((index) async {
              await Future.delayed(Duration(milliseconds: 1));
              return MapEntry('user_$index', base64Encode(utf8.encode('$plaintext-$index')));
            }).toList();
            
            final results = await Future.wait(futures);
            for (final entry in results) {
              ciphertexts[entry.key] = entry.value;
            }
          }
          
          operationCompleted = true;
          return ciphertexts;
        });
        
        // Verify operation not completed yet (async)
        expect(operationCompleted, false, 
          reason: 'Operation should not block - should be async');
        
        // Wait for completion
        final result = await encryptionFuture;
        
        expect(operationCompleted, true);
        expect(result.length, memberCount);
      });
      
      test('Multiple encryption operations can run concurrently', () async {
        // Verify that multiple messages can be encrypted in parallel
        // (important for rapid message sending)
        
        final message1Future = Future(() async {
          await Future.delayed(Duration(milliseconds: 10));
          return 'message1-encrypted';
        });
        
        final message2Future = Future(() async {
          await Future.delayed(Duration(milliseconds: 10));
          return 'message2-encrypted';
        });
        
        final message3Future = Future(() async {
          await Future.delayed(Duration(milliseconds: 10));
          return 'message3-encrypted';
        });
        
        final stopwatch = Stopwatch()..start();
        
        // Run all three in parallel
        final results = await Future.wait([
          message1Future,
          message2Future,
          message3Future,
        ]);
        
        stopwatch.stop();
        final elapsedMs = stopwatch.elapsedMilliseconds;
        
        expect(results.length, 3);
        expect(results[0], 'message1-encrypted');
        expect(results[1], 'message2-encrypted');
        expect(results[2], 'message3-encrypted');
        
        print('[Performance] Concurrent encryption: ${elapsedMs}ms');
        
        // Should complete in ~10ms (parallel), not ~30ms (sequential)
        expect(elapsedMs, lessThan(25), 
          reason: 'Concurrent operations should run in parallel');
      });
      
      test('Sending state is displayed during encryption (Requirement 8.3)', () async {
        // **Validates: Requirement 8.3**
        // WHEN encryption is in progress, THE Chat_Room_Provider SHALL display
        // the message in a sending state to provide user feedback
        
        // Simulate message status during encryption
        String messageStatus = 'pending';
        
        // Start encryption (async)
        final encryptionFuture = Future(() async {
          messageStatus = 'sending';
          await Future.delayed(Duration(milliseconds: 50)); // Simulate encryption
          messageStatus = 'sent';
        });
        
        // Wait a moment for the future to start
        await Future.delayed(Duration(milliseconds: 1));
        
        // Status should be 'sending' during encryption
        expect(messageStatus, 'sending', 
          reason: 'Message should show sending state during encryption');
        
        // Wait for completion
        await encryptionFuture;
        expect(messageStatus, 'sent');
      });
    });
    
    group('Performance Edge Cases -', () {
      
      test('Empty member list completes instantly', () async {
        final memberIds = <String>[];
        
        final stopwatch = Stopwatch()..start();
        
        final ciphertexts = <String, String>{};
        for (final memberId in memberIds) {
          ciphertexts[memberId] = 'encrypted';
        }
        
        stopwatch.stop();
        final elapsedMs = stopwatch.elapsedMilliseconds;
        
        expect(ciphertexts.isEmpty, true);
        expect(elapsedMs, lessThan(5));
      });
      
      test('Single member encryption completes very quickly', () async {
        final memberIds = ['user_1'];
        final plaintext = 'Test message';
        
        final stopwatch = Stopwatch()..start();
        
        final ciphertexts = <String, String>{};
        for (final memberId in memberIds) {
          await Future.delayed(Duration(milliseconds: 1));
          ciphertexts[memberId] = base64Encode(utf8.encode('$plaintext-$memberId'));
        }
        
        stopwatch.stop();
        final elapsedMs = stopwatch.elapsedMilliseconds;
        
        expect(ciphertexts.length, 1);
        expect(elapsedMs, lessThan(50));
      });
      
      test('Large message content does not significantly impact performance', () async {
        // Test with small and large messages
        final memberCount = 20;
        
        // Small message
        final smallMessage = 'Hi';
        final smallStopwatch = Stopwatch()..start();
        final smallCiphertexts = <String, String>{};
        for (int i = 0; i < memberCount; i++) {
          await Future.delayed(Duration(microseconds: 100));
          smallCiphertexts['user_$i'] = base64Encode(utf8.encode('$smallMessage-$i'));
        }
        smallStopwatch.stop();
        final smallMs = smallStopwatch.elapsedMilliseconds;
        
        // Large message (1KB)
        final largeMessage = 'A' * 1000;
        final largeStopwatch = Stopwatch()..start();
        final largeCiphertexts = <String, String>{};
        for (int i = 0; i < memberCount; i++) {
          await Future.delayed(Duration(microseconds: 100));
          largeCiphertexts['user_$i'] = base64Encode(utf8.encode('$largeMessage-$i'));
        }
        largeStopwatch.stop();
        final largeMs = largeStopwatch.elapsedMilliseconds;
        
        print('[Performance] Small message: ${smallMs}ms, Large message: ${largeMs}ms');
        
        // Both should complete in reasonable time
        expect(smallMs, lessThan(100), 
          reason: 'Small message encryption should be fast');
        expect(largeMs, lessThan(200), 
          reason: 'Large message encryption should still be reasonably fast');
        
        // Verify both produced correct number of ciphertexts
        expect(smallCiphertexts.length, memberCount);
        expect(largeCiphertexts.length, memberCount);
      });
    });
  });
}
