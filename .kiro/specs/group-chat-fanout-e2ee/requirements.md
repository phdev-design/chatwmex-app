# Requirements Document

## Introduction

This document specifies requirements for implementing Client-Side Fan-out End-to-End Encryption (E2EE) for group chats in a Flutter messaging system. The system currently supports E2EE for one-to-one private messages using X25519 + AES-GCM encryption. This feature extends E2EE to group chats using a fan-out strategy where the sender encrypts the message once for each recipient using their individual public keys.

The fan-out approach ensures that each group member receives a unique ciphertext, the server cannot decrypt any messages (zero-knowledge), and the encryption/decryption process is transparent to users.

## Glossary

- **Chat_Room_Provider**: The Flutter provider managing chat room state and message operations
- **Crypto_Service**: The service providing X25519 + AES-GCM encryption/decryption operations
- **Public_Key_Cache_Service**: The service managing cached public keys for users
- **Fan_Out_Payload**: A JSON structure containing encrypted ciphertexts for multiple recipients
- **Group_Message**: A message where isRoom flag is true, indicating a group chat context
- **Private_Message**: A message where isRoom flag is false, indicating one-to-one chat
- **E2EE_Toggle**: A room-level setting controlling whether encryption is enabled
- **Ciphertext_Map**: A JSON object mapping member IDs to their encrypted message content
- **Sender**: The user who creates and encrypts a message
- **Recipient**: A group member who receives and decrypts a message
- **Member_List**: The collection of user IDs belonging to a group chat at a specific time
- **Link_Preview**: Metadata about URLs in messages displayed as rich previews

## Requirements

### Requirement 1: Fan-out Message Encryption

**User Story:** As a sender, I want my group messages encrypted individually for each member, so that each recipient can only decrypt their own copy and the server cannot read the content.

#### Acceptance Criteria

1. WHEN a user sends a Group_Message AND the E2EE_Toggle is enabled, THE Chat_Room_Provider SHALL retrieve the Member_List for the group
2. WHEN the Member_List is retrieved, THE Chat_Room_Provider SHALL fetch the public key for each member from the Public_Key_Cache_Service
3. FOR EACH member with a valid public key, THE Chat_Room_Provider SHALL encrypt the plaintext message using Crypto_Service with that member's public key
4. WHEN all encryptions complete, THE Chat_Room_Provider SHALL construct a Fan_Out_Payload containing the Ciphertext_Map
5. THE Fan_Out_Payload SHALL include the field "is_fanout" set to true
6. THE Fan_Out_Payload SHALL include the field "ciphertexts" containing a JSON object mapping member IDs to base64-encoded ciphertexts
7. THE Chat_Room_Provider SHALL serialize the Fan_Out_Payload to a JSON string and send it as the message content via WebSocket


### Requirement 2: Fan-out Message Decryption

**User Story:** As a recipient, I want to decrypt group messages encrypted for me, so that I can read the original plaintext content.

#### Acceptance Criteria

1. WHEN the Chat_Room_Provider receives a Group_Message, THE Chat_Room_Provider SHALL parse the message content as JSON
2. IF the parsed JSON contains the field "is_fanout" with value true, THEN THE Chat_Room_Provider SHALL extract the Ciphertext_Map from the "ciphertexts" field
3. WHEN the Ciphertext_Map is extracted, THE Chat_Room_Provider SHALL retrieve the ciphertext for the current user's ID
4. IF the current user's ciphertext exists in the Ciphertext_Map, THEN THE Chat_Room_Provider SHALL decrypt it using Crypto_Service with the sender's public key
5. WHEN decryption succeeds, THE Chat_Room_Provider SHALL display the decrypted plaintext to the user
6. IF the current user's ciphertext does not exist in the Ciphertext_Map, THEN THE Chat_Room_Provider SHALL display a fallback message indicating the message is unavailable
7. IF decryption fails, THEN THE Chat_Room_Provider SHALL display "🔒 此訊息無法解密（金鑰已更新）"

### Requirement 3: E2EE Toggle Compliance

**User Story:** As a user, I want group encryption to respect the room's E2EE setting, so that I can control when messages are encrypted.

#### Acceptance Criteria

1. WHEN a user sends a Group_Message, THE Chat_Room_Provider SHALL check the E2EE_Toggle state for the room
2. IF the E2EE_Toggle is disabled, THEN THE Chat_Room_Provider SHALL send the message as plaintext without encryption
3. IF the E2EE_Toggle is enabled, THEN THE Chat_Room_Provider SHALL apply fan-out encryption as specified in Requirement 1
4. WHEN receiving a Group_Message AND the E2EE_Toggle is disabled, THE Chat_Room_Provider SHALL display the message content as plaintext without decryption attempts
5. WHEN receiving a Group_Message AND the E2EE_Toggle is enabled, THE Chat_Room_Provider SHALL attempt fan-out decryption as specified in Requirement 2

### Requirement 4: Public Key Management

**User Story:** As the system, I want to efficiently manage public keys for group members, so that encryption operations have minimal latency.

#### Acceptance Criteria

1. WHEN the Chat_Room_Provider needs to encrypt a Group_Message, THE Public_Key_Cache_Service SHALL provide a method to fetch all member public keys in a single operation
2. THE Public_Key_Cache_Service SHALL cache retrieved public keys to avoid redundant API calls
3. IF a member's public key is not available in the cache, THEN THE Public_Key_Cache_Service SHALL fetch it from the server
4. IF a member's public key cannot be retrieved, THEN THE Chat_Room_Provider SHALL exclude that member from the Ciphertext_Map
5. THE Chat_Room_Provider SHALL use cached public keys for subsequent encryptions within the same session


### Requirement 5: Message Resend with Fan-out Encryption

**User Story:** As a user, I want pending messages to be resent with proper encryption, so that message delivery is reliable even after connection issues.

#### Acceptance Criteria

1. WHEN the Chat_Room_Provider executes resendPendingMessages(), THE Chat_Room_Provider SHALL identify all pending Group_Messages for the room
2. FOR EACH pending Group_Message WHERE the E2EE_Toggle is enabled, THE Chat_Room_Provider SHALL apply fan-out encryption as specified in Requirement 1
3. FOR EACH pending Group_Message WHERE the E2EE_Toggle is disabled, THE Chat_Room_Provider SHALL resend the plaintext content
4. WHEN resending a message with Link_Preview data, THE Chat_Room_Provider SHALL preserve the Link_Preview metadata through the encryption and resend process
5. THE Chat_Room_Provider SHALL use the current Member_List at resend time for encryption

### Requirement 6: Message Retry with Fan-out Encryption

**User Story:** As a user, I want failed messages to be retried with proper encryption, so that temporary failures don't result in lost messages.

#### Acceptance Criteria

1. WHEN the Chat_Room_Provider executes retrySend() for a failed Group_Message, THE Chat_Room_Provider SHALL check the E2EE_Toggle state
2. IF the E2EE_Toggle is enabled, THEN THE Chat_Room_Provider SHALL apply fan-out encryption as specified in Requirement 1
3. IF the E2EE_Toggle is disabled, THEN THE Chat_Room_Provider SHALL retry sending the plaintext content
4. WHEN retrying a message with Link_Preview data, THE Chat_Room_Provider SHALL preserve the Link_Preview metadata through the encryption and retry process
5. THE Chat_Room_Provider SHALL use the current Member_List at retry time for encryption

### Requirement 7: Backward Compatibility with Plaintext Messages

**User Story:** As a user, I want to view old plaintext messages in encrypted rooms, so that enabling encryption doesn't break message history.

#### Acceptance Criteria

1. WHEN the Chat_Room_Provider receives a Group_Message in a room with E2EE_Toggle enabled, THE Chat_Room_Provider SHALL attempt to parse the content as JSON
2. IF the JSON parsing fails OR the "is_fanout" field is absent OR the "is_fanout" field is false, THEN THE Chat_Room_Provider SHALL display the message content as plaintext
3. THE Chat_Room_Provider SHALL display plaintext messages without showing decryption error messages
4. WHEN displaying message history, THE Chat_Room_Provider SHALL correctly render both encrypted and plaintext messages in chronological order


### Requirement 8: Encryption Performance for Group Sizes

**User Story:** As a user, I want message sending to remain responsive in groups, so that encryption doesn't create noticeable delays.

#### Acceptance Criteria

1. WHEN encrypting a Group_Message for a group with up to 50 members, THE Chat_Room_Provider SHALL complete the encryption and send operation within 2000 milliseconds
2. THE Chat_Room_Provider SHALL perform encryption operations asynchronously to avoid blocking the UI thread
3. WHEN encryption is in progress, THE Chat_Room_Provider SHALL display the message in a sending state to provide user feedback
4. IF encryption takes longer than 2000 milliseconds, THEN THE Chat_Room_Provider SHALL still complete the operation without timeout errors

### Requirement 9: Member List Consistency

**User Story:** As a sender, I want messages encrypted for the correct member list, so that all current members can decrypt the message.

#### Acceptance Criteria

1. WHEN the Chat_Room_Provider begins encrypting a Group_Message, THE Chat_Room_Provider SHALL capture the Member_List at that moment
2. THE Chat_Room_Provider SHALL use the captured Member_List for all encryption operations for that message
3. IF a member joins the group after encryption begins, THEN THE Chat_Room_Provider SHALL not include that member in the Ciphertext_Map for that message
4. IF a member leaves the group after encryption begins, THEN THE Chat_Room_Provider SHALL still include that member in the Ciphertext_Map for that message
5. THE Chat_Room_Provider SHALL not retry fetching the Member_List during a single message encryption operation

### Requirement 10: Encryption Error Handling

**User Story:** As a user, I want clear feedback when encryption fails, so that I understand why my message wasn't sent.

#### Acceptance Criteria

1. IF the Chat_Room_Provider cannot retrieve the Member_List, THEN THE Chat_Room_Provider SHALL display an error message and not send the message
2. IF the Chat_Room_Provider cannot retrieve any public keys for group members, THEN THE Chat_Room_Provider SHALL display an error message and not send the message
3. IF encryption fails for all members, THEN THE Chat_Room_Provider SHALL display an error message and not send the message
4. IF encryption succeeds for at least one member, THEN THE Chat_Room_Provider SHALL send the message with the available ciphertexts
5. THE Chat_Room_Provider SHALL log encryption errors for debugging purposes without exposing sensitive key material


### Requirement 11: Decryption Error Handling

**User Story:** As a recipient, I want clear feedback when I cannot decrypt a message, so that I understand the issue.

#### Acceptance Criteria

1. IF the Chat_Room_Provider cannot parse the message content as JSON, THEN THE Chat_Room_Provider SHALL treat the message as plaintext
2. IF the Ciphertext_Map does not contain an entry for the current user, THEN THE Chat_Room_Provider SHALL display a message indicating the content is unavailable for this user
3. IF the Crypto_Service decryption operation fails, THEN THE Chat_Room_Provider SHALL display "🔒 此訊息無法解密（金鑰已更新）"
4. IF the sender's public key is not available, THEN THE Chat_Room_Provider SHALL display "🔒 此訊息無法解密（金鑰已更新）"
5. THE Chat_Room_Provider SHALL log decryption errors for debugging purposes without exposing sensitive key material

### Requirement 12: Zero-Knowledge Server Architecture

**User Story:** As a user, I want the server to be unable to decrypt my messages, so that my privacy is protected even if the server is compromised.

#### Acceptance Criteria

1. THE Chat_Room_Provider SHALL perform all encryption operations on the client device
2. THE Chat_Room_Provider SHALL perform all decryption operations on the client device
3. THE Chat_Room_Provider SHALL send only ciphertexts to the server, never plaintext content when E2EE_Toggle is enabled
4. THE Fan_Out_Payload SHALL contain only encrypted data and metadata, no plaintext message content
5. THE Chat_Room_Provider SHALL not send private keys or key material to the server

### Requirement 13: Link Preview Preservation

**User Story:** As a user, I want link previews to work correctly with encrypted messages, so that I can see rich content for shared URLs.

#### Acceptance Criteria

1. WHEN a Group_Message contains Link_Preview data AND the E2EE_Toggle is enabled, THE Chat_Room_Provider SHALL preserve the Link_Preview metadata separately from the encrypted content
2. WHEN sending an encrypted Group_Message with Link_Preview, THE Chat_Room_Provider SHALL include the Link_Preview data in the message payload alongside the Fan_Out_Payload
3. WHEN receiving an encrypted Group_Message with Link_Preview, THE Chat_Room_Provider SHALL display the Link_Preview after successful decryption
4. WHEN resending or retrying a Group_Message with Link_Preview, THE Chat_Room_Provider SHALL maintain the Link_Preview data through the encryption process
5. THE Chat_Room_Provider SHALL not encrypt Link_Preview metadata, only the message text content


### Requirement 14: Crypto Service Integration

**User Story:** As the system, I want to reuse existing encryption primitives, so that the implementation is consistent and secure.

#### Acceptance Criteria

1. THE Chat_Room_Provider SHALL use Crypto_Service.encryptMessage() for all encryption operations
2. THE Chat_Room_Provider SHALL use Crypto_Service.decryptMessage() for all decryption operations
3. THE Crypto_Service SHALL use X25519 for key exchange operations
4. THE Crypto_Service SHALL use AES-GCM for symmetric encryption operations
5. THE Chat_Room_Provider SHALL not implement custom cryptographic primitives

### Requirement 15: Fan-out Payload Format Validation

**User Story:** As the system, I want to validate fan-out payloads, so that malformed data is rejected early.

#### Acceptance Criteria

1. WHEN constructing a Fan_Out_Payload, THE Chat_Room_Provider SHALL validate that "is_fanout" is set to true
2. WHEN constructing a Fan_Out_Payload, THE Chat_Room_Provider SHALL validate that "ciphertexts" is a non-empty JSON object
3. WHEN constructing a Fan_Out_Payload, THE Chat_Room_Provider SHALL validate that all ciphertext values are valid base64-encoded strings
4. WHEN parsing a received Fan_Out_Payload, THE Chat_Room_Provider SHALL validate the JSON structure before attempting decryption
5. IF validation fails, THEN THE Chat_Room_Provider SHALL treat the message as plaintext or display an error as appropriate

### Requirement 16: Unique Ciphertext per Recipient

**User Story:** As a security-conscious user, I want each group member to receive a unique ciphertext, so that compromising one member's key doesn't compromise others' messages.

#### Acceptance Criteria

1. FOR EACH member in the Member_List, THE Chat_Room_Provider SHALL generate a unique ciphertext using that member's public key
2. THE Chat_Room_Provider SHALL not reuse ciphertexts across different recipients
3. THE Chat_Room_Provider SHALL not use a shared group key for encryption
4. WHEN two members have the same public key, THE Chat_Room_Provider SHALL still perform separate encryption operations for each member ID
5. THE Ciphertext_Map SHALL contain distinct entries for each member ID


### Requirement 17: Transparent User Experience

**User Story:** As a user, I want encryption to work seamlessly in the background, so that I don't need to think about cryptographic details.

#### Acceptance Criteria

1. THE Chat_Room_Provider SHALL perform encryption and decryption operations without requiring user interaction
2. THE Chat_Room_Provider SHALL not display cryptographic details (keys, ciphertexts, algorithms) in the user interface
3. WHEN E2EE_Toggle is enabled, THE Chat_Room_Provider SHALL display messages identically to when E2EE_Toggle is disabled, except for decryption error cases
4. THE Chat_Room_Provider SHALL not require users to manually manage keys or encryption settings beyond the E2EE_Toggle
5. WHEN a message is successfully encrypted and sent, THE Chat_Room_Provider SHALL display it in the chat history as a normal sent message

### Requirement 18: Private Message Compatibility

**User Story:** As a user, I want one-to-one messages to continue working as before, so that the fan-out implementation doesn't break existing functionality.

#### Acceptance Criteria

1. WHEN a user sends a Private_Message, THE Chat_Room_Provider SHALL use the existing one-to-one E2EE implementation
2. THE Chat_Room_Provider SHALL not apply fan-out encryption to Private_Messages
3. WHEN receiving a Private_Message, THE Chat_Room_Provider SHALL use the existing one-to-one decryption logic
4. THE Chat_Room_Provider SHALL determine message type based on the isRoom flag
5. THE Chat_Room_Provider SHALL maintain separate code paths for Group_Messages and Private_Messages

## Testing Considerations

The following scenarios should be validated during implementation:

1. **Group Size Variations**: Test with groups of 2, 10, 25, and 50 members to verify performance and correctness
2. **E2EE Toggle States**: Test message sending and receiving with E2EE enabled and disabled
3. **Message Resend Flow**: Test resendPendingMessages() with encrypted group messages
4. **Message Retry Flow**: Test retrySend() with failed encrypted group messages
5. **Public Key Availability**: Test with members who have public keys and members who don't
6. **Backward Compatibility**: Test receiving old plaintext messages in rooms that now have E2EE enabled
7. **Link Preview Handling**: Test that link previews are preserved through encryption, resend, and retry
8. **Member List Changes**: Test sending messages while members join or leave the group
9. **Decryption Failures**: Test scenarios where decryption fails (wrong key, corrupted data, missing ciphertext)
10. **JSON Parsing Edge Cases**: Test with malformed JSON, missing fields, and invalid data types
11. **Performance Under Load**: Test sending multiple messages rapidly in large groups
12. **Private Message Regression**: Test that one-to-one messages still work correctly after fan-out implementation

