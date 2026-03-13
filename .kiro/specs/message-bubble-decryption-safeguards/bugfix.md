# Bugfix Requirements Document

## Introduction

The MessageBubble widget currently only checks for E2EE decryption failures when the message type is an image. When text messages (or other message types) fail decryption or are in the `MessageStatus.decryptingRetry` state, the UI incorrectly attempts to process them as normal content. This causes the system to evaluate `msg.linkPreview` on encrypted content, resulting in Regex errors and empty URL warnings in ImageCacheService. This bugfix broadens the decryption failure safeguards to apply to all message types, ensuring that failed or retrying decryption messages are handled gracefully without attempting to parse or render their encrypted content.

## Bug Analysis

### Current Behavior (Defect)

1.1 WHEN a message has `type == MessageType.text` AND `content.startsWith('🔒')` THEN the system incorrectly processes it as normal text content

1.2 WHEN a message has `status == MessageStatus.failed` AND `type != MessageType.image` THEN the system incorrectly processes it as normal content

1.3 WHEN a message has `status == MessageStatus.decryptingRetry` OR decryption has failed THEN the system evaluates `msg.linkPreview` on encrypted content, causing Regex errors

1.4 WHEN a message has `status == MessageStatus.decryptingRetry` OR decryption has failed THEN the system attempts to resolve image URLs from encrypted content, causing empty URL warnings in ImageCacheService

### Expected Behavior (Correct)

2.1 WHEN a message has `content.startsWith('🔒')` OR `status == MessageStatus.failed` (regardless of message type) THEN the system SHALL display a lock icon with error text in subtle/error color

2.2 WHEN a message has `status == MessageStatus.decryptingRetry` OR `content.startsWith('🔒')` OR `status == MessageStatus.failed` THEN the system SHALL NOT evaluate `msg.linkPreview`

2.3 WHEN a message has `status == MessageStatus.decryptingRetry` OR `content.startsWith('🔒')` OR `status == MessageStatus.failed` THEN the system SHALL NOT attempt to resolve or render image URLs

2.4 WHEN a message has `status == MessageStatus.decryptingRetry` OR decryption has failed THEN the system SHALL set `hasPreview = false` to completely disable link preview processing

2.5 WHEN a message has decryption failure (any type) THEN the system SHALL handle it in a dedicated `else if (isDecryptionFailure)` branch before processing normal message types

### Unchanged Behavior (Regression Prevention)

3.1 WHEN a message has `status == MessageStatus.decryptingRetry` THEN the system SHALL CONTINUE TO display the "🔒 等待對方上線以重新解密..." message with a loading spinner

3.2 WHEN a message is successfully decrypted AND `type == MessageType.image` THEN the system SHALL CONTINUE TO render the image with tap-to-view functionality

3.3 WHEN a message is successfully decrypted AND `type == MessageType.voice` THEN the system SHALL CONTINUE TO render the AudioMessageBubble widget

3.4 WHEN a message is successfully decrypted AND `type == MessageType.file` THEN the system SHALL CONTINUE TO render the file attachment with tap-to-open functionality

3.5 WHEN a message is successfully decrypted AND `type == MessageType.text` AND contains a valid URL THEN the system SHALL CONTINUE TO evaluate and display link previews

3.6 WHEN a message has `isUnsent == true` THEN the system SHALL CONTINUE TO display "此訊息已收回" regardless of decryption status

3.7 WHEN a message is successfully decrypted THEN the system SHALL CONTINUE TO display reactions, reply content, timestamp, and status icons as normal
