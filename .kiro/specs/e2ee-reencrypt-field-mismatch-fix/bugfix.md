# Bugfix Requirements Document

## Introduction

This document specifies the requirements for fixing a critical field name mismatch bug in the E2EE (End-to-End Encryption) re-encryption flow. The frontend sends WebSocket messages with the field name `content` while the backend expects `re_encrypted_content`, causing all re-encryption responses to be rejected. This prevents users from viewing decrypted messages and images.

## Bug Analysis

### Current Behavior (Defect)

1.1 WHEN the frontend sends a `re_encrypt_response` WebSocket message with the field name `content` THEN the backend validation fails because it expects `re_encrypted_content`

1.2 WHEN the backend receives a re-encryption response with mismatched field names THEN the backend logs error "Missing required fields in re_encrypt_response" and rejects the response

1.3 WHEN the re-encryption response is rejected THEN messages remain encrypted and cannot be displayed to users

1.4 WHEN messages remain encrypted due to rejected re-encryption THEN images show as broken/missing and content is not visible

### Expected Behavior (Correct)

2.1 WHEN the frontend sends a `re_encrypt_response` WebSocket message THEN the system SHALL use the field name `re_encrypted_content` to match backend expectations

2.2 WHEN the backend receives a re-encryption response with the correct field name `re_encrypted_content` THEN the system SHALL successfully validate and accept the response

2.3 WHEN the re-encryption response is accepted THEN the system SHALL successfully decrypt messages for display

2.4 WHEN messages are successfully decrypted THEN the system SHALL display images and content correctly to users

### Unchanged Behavior (Regression Prevention)

3.1 WHEN the frontend sends other WebSocket message types (not re_encrypt_response) THEN the system SHALL CONTINUE TO process them with their existing field names and validation logic

3.2 WHEN the backend receives valid re-encryption responses with correct field names THEN the system SHALL CONTINUE TO decrypt and store messages using the existing E2EE decryption logic

3.3 WHEN users view messages that were already successfully decrypted before the fix THEN the system SHALL CONTINUE TO display them correctly

3.4 WHEN the re-encryption flow involves other fields in the payload (message_id, room_id, etc.) THEN the system SHALL CONTINUE TO validate and process them unchanged
