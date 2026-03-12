# Bugfix Requirements Document

## Introduction

In the Room Media page, the media count displayed in the UI (e.g., "10 media files") does not match the actual number of media items rendered in the grid (e.g., only 7 items shown). This discrepancy occurs because the decryption process in `room_media_provider.dart` may fail for some media items (due to missing encryption keys, 404 errors, or invalid content), and `media_tab_content.dart` filters out items with empty URLs. However, the total count shown to users includes all messages from the backend, regardless of whether they can be successfully decrypted and displayed.

This creates a confusing user experience where the promised count doesn't match what users actually see.

## Bug Analysis

### Current Behavior (Defect)

1.1 WHEN the backend returns 10 media messages but 3 of them fail decryption (resulting in empty URLs after `resolveFullUrl`) THEN the system displays a count of 10 in the UI while only rendering 7 items in the grid

1.2 WHEN media items have invalid encryption keys or missing files (404) THEN the system includes these non-renderable items in the total count displayed to users

1.3 WHEN `_decryptMediaContent` processes messages and some fail validation (empty decrypted content or invalid URLs) THEN the system keeps these messages in the state with their original encrypted content, which later gets filtered out by `resolveFullUrl` returning empty strings

### Expected Behavior (Correct)

2.1 WHEN the backend returns 10 media messages but 3 of them fail decryption (resulting in empty URLs after `resolveFullUrl`) THEN the system SHALL display a count of 7 and render 7 items in the grid

2.2 WHEN media items have invalid encryption keys or missing files (404) THEN the system SHALL exclude these non-renderable items from the total count displayed to users

2.3 WHEN `_decryptMediaContent` processes messages and some fail validation (empty decrypted content or invalid URLs) THEN the system SHALL filter out these invalid messages from the state so they are not counted or displayed

### Unchanged Behavior (Regression Prevention)

3.1 WHEN all media messages decrypt successfully and have valid URLs THEN the system SHALL CONTINUE TO display the correct count matching the number of rendered items

3.2 WHEN loading more media via pagination THEN the system SHALL CONTINUE TO merge new messages correctly without duplicates

3.3 WHEN media messages are already in plaintext format (URLs, relative paths, ObjectIDs) THEN the system SHALL CONTINUE TO process and display them without attempting decryption

3.4 WHEN grouping messages by month for display THEN the system SHALL CONTINUE TO group only the valid, renderable messages

3.5 WHEN displaying the media grid with loading states and error placeholders THEN the system SHALL CONTINUE TO show appropriate UI feedback for network errors during image loading
