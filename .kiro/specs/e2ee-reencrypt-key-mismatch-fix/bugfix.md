# Bugfix Requirements Document

## Introduction

This document describes the fix for a JSON key mismatch bug in the E2EE Auto-Resend logic within the `ChatRoomViewModel` class. The bug occurs when the sender and receiver use different JSON keys to transmit and receive re-encrypted message content, causing the receiver to read a null value and trigger a "missing content" error.

The sender (`_handleReEncryptRequest`) attaches the re-encrypted content using the key `'re_encrypted_content'`, but the receiver (`_handleReEncryptResponse`) attempts to read it using the key `'content'`. This mismatch prevents successful message re-decryption after key rotation events.

## Bug Analysis

### Current Behavior (Defect)

1.1 WHEN the receiver processes a `re_encrypt_response` payload in `_handleReEncryptResponse` THEN the system reads from the key `'content'` which is null

1.2 WHEN the receiver reads a null value from `payload['content']` THEN the system logs "Invalid re_encrypt_response: missing content" and returns early without re-decrypting the message

1.3 WHEN the key mismatch occurs THEN the message remains in `decryptingRetry` status indefinitely and the user cannot read the message

### Expected Behavior (Correct)

2.1 WHEN the receiver processes a `re_encrypt_response` payload in `_handleReEncryptResponse` THEN the system SHALL read from the key `'re_encrypted_content'` to match the sender's key

2.2 WHEN the receiver reads the re-encrypted content successfully THEN the system SHALL proceed with decryption and update the message status to `delivered`

2.3 WHEN the receiver reads from `'re_encrypted_content'` THEN the system SHALL also support a fallback to `'content'` for backward compatibility with older message formats

### Unchanged Behavior (Regression Prevention)

3.1 WHEN the receiver encounters a missing `message_id` in the payload THEN the system SHALL CONTINUE TO log an error and return early

3.2 WHEN the receiver encounters a `receiver_id` that does not match the current user THEN the system SHALL CONTINUE TO log a security warning and return early

3.3 WHEN the receiver encounters a message not in `decryptingRetry` status THEN the system SHALL CONTINUE TO skip processing and log the current status

3.4 WHEN the receiver successfully decrypts the re-encrypted content THEN the system SHALL CONTINUE TO update LocalDB and UI state as before

3.5 WHEN the receiver encounters decryption errors THEN the system SHALL CONTINUE TO maintain the `decryptingRetry` status without marking the message as permanently failed
