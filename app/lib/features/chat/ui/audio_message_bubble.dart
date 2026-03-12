import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:app/core/media/audio_cache_service.dart';
import 'package:app/models/message.dart';

enum AudioPlaybackState {
  stopped,
  loading,
  playing,
  paused,
  error,
}

class AudioMessageBubble extends ConsumerStatefulWidget {
  final Message message;

  const AudioMessageBubble({super.key, required this.message});

  @override
  ConsumerState<AudioMessageBubble> createState() => _AudioMessageBubbleState();
}

class _AudioMessageBubbleState extends ConsumerState<AudioMessageBubble> {
  late final AudioPlayer _player;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  AudioPlaybackState _playbackState = AudioPlaybackState.stopped;
  String? _error;
  String? _cachedFilePath;

  @override
  void initState() {
    super.initState();
    _player = AudioPlayer();
    
    _player.onDurationChanged.listen((duration) {
      if (!mounted) return;
      setState(() => _duration = duration);
    });
    
    _player.onPositionChanged.listen((position) {
      if (!mounted) return;
      setState(() => _position = position);
    });
    
    _player.onPlayerComplete.listen((_) {
      if (!mounted) return;
      setState(() {
        _playbackState = AudioPlaybackState.stopped;
        _position = Duration.zero;
      });
    });
  }

  @override
  void didUpdateWidget(covariant AudioMessageBubble oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.message.id != widget.message.id) {
      _player.stop();
      setState(() {
        _playbackState = AudioPlaybackState.stopped;
        _position = Duration.zero;
        _duration = Duration.zero;
        _cachedFilePath = null;
        _error = null;
      });
    }
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _togglePlay() async {
    if (_playbackState == AudioPlaybackState.playing) {
      await _player.pause();
      setState(() => _playbackState = AudioPlaybackState.paused);
      return;
    }

    if (_playbackState == AudioPlaybackState.paused) {
      await _player.resume();
      setState(() => _playbackState = AudioPlaybackState.playing);
      return;
    }

    // Load and play audio
    await _loadAndPlay();
  }

  Future<void> _loadAndPlay() async {
    setState(() {
      _playbackState = AudioPlaybackState.loading;
      _error = null;
    });

    try {
      final audioCacheService = ref.read(audioCacheServiceProvider);
      final fileKey = widget.message.fileKey;
      final audioUrl = widget.message.content;
      
      if (fileKey == null || fileKey.isEmpty) {
        // Legacy unencrypted audio - download and cache
        final localPath = await _downloadAndCacheLegacyAudio(
          audioCacheService,
          audioUrl,
        );
        
        _cachedFilePath = localPath;
        await _player.play(DeviceFileSource(localPath));
        
        if (!mounted) return;
        setState(() => _playbackState = AudioPlaybackState.playing);
        return;
      }

      // Encrypted audio - use existing flow
      final localPath = await audioCacheService.getOrDownloadAudio(
        messageId: widget.message.id,
        audioUrl: audioUrl,
        fileKey: fileKey,
      );

      _cachedFilePath = localPath;
      await _player.play(DeviceFileSource(localPath));
      
      if (!mounted) return;
      setState(() => _playbackState = AudioPlaybackState.playing);
    } on AudioCacheException catch (e) {
      if (!mounted) return;
      setState(() {
        _playbackState = AudioPlaybackState.error;
        _error = _getErrorMessage(e);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _playbackState = AudioPlaybackState.error;
        _error = 'Failed to play audio: ${e.toString()}';
      });
    }
  }

  /// Downloads and caches legacy unencrypted audio
  Future<String> _downloadAndCacheLegacyAudio(
    AudioCacheService cacheService,
    String audioUrl,
  ) async {
    // Use message ID as cache key for legacy audio
    final cacheKey = 'legacy_${widget.message.id}';
    
    // Check if already cached
    if (await cacheService.isCached(cacheKey)) {
      final cachedPath = await cacheService.getCacheFilePath(cacheKey);
      final file = File(cachedPath);
      if (await file.exists()) {
        debugPrint('✅ Legacy audio cache hit for message: ${widget.message.id}');
        return cachedPath;
      }
    }
    
    debugPrint('⬇️ Downloading legacy audio for message: ${widget.message.id}');
    
    // Download audio directly (no decryption needed)
    final dio = Dio();
    final response = await dio.get<List<int>>(
      audioUrl,
      options: Options(
        responseType: ResponseType.bytes,
        receiveTimeout: const Duration(seconds: 30),
      ),
    );
    
    if (response.data == null) {
      throw AudioCacheException(
        type: AudioCacheErrorType.networkError,
        message: 'Download failed: empty response',
      );
    }
    
    // Save to cache
    final cachedPath = await cacheService.getCacheFilePath(cacheKey);
    final file = File(cachedPath);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(response.data!);
    
    debugPrint('✅ Legacy audio cached successfully: $cachedPath');
    return cachedPath;
  }

  String _getErrorMessage(AudioCacheException e) {
    switch (e.type) {
      case AudioCacheErrorType.networkError:
        return 'Network error. Tap to retry.';
      case AudioCacheErrorType.decryptionError:
        return 'Cannot decrypt audio.';
      case AudioCacheErrorType.fileIOError:
        return 'File error. Tap to retry.';
      case AudioCacheErrorType.invalidFormat:
        return 'Invalid audio format.';
    }
  }

  Future<void> _retry() async {
    await _loadAndPlay();
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    // 👇 讓語音模塊自動讀取父元件 (MessageBubble) 所設定的文字顏色，以適應藍色/灰色背景
    final defaultTextColor =
        DefaultTextStyle.of(context).style.color ?? colorScheme.onSurface;
    final subtleTextColor = defaultTextColor.withValues(alpha: 0.6);

    // Show error state
    if (_playbackState == AudioPlaybackState.error) {
      return SizedBox(
        width: 240,
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.error_outline),
              color: colorScheme.error,
              onPressed: _retry,
              visualDensity: VisualDensity.compact,
            ),
            Expanded(
              child: Text(
                _error ?? 'Error playing audio',
                style: TextStyle(
                  fontSize: 12,
                  color: colorScheme.error,
                ),
              ),
            ),
          ],
        ),
      );
    }

    // Show loading state
    if (_playbackState == AudioPlaybackState.loading) {
      return SizedBox(
        width: 240,
        child: Row(
          children: [
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(defaultTextColor),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Loading...',
                style: TextStyle(fontSize: 12, color: subtleTextColor),
              ),
            ),
          ],
        ),
      );
    }

    // Normal playback UI
    final maxMs = _duration.inMilliseconds == 0
        ? 1.0
        : _duration.inMilliseconds.toDouble();
    final value = _position.inMilliseconds.clamp(0, maxMs.toInt()).toDouble();
    final bars = [6, 10, 14, 8, 12, 16, 10, 6, 14, 8];
    final progress = _duration.inMilliseconds == 0
        ? 0.0
        : _position.inMilliseconds / _duration.inMilliseconds;
    final activeCount = (bars.length * progress).round();
    final movingHead = (progress * bars.length).floor();
    final remaining = _duration - _position;
    final remainingSafe = remaining.isNegative ? Duration.zero : remaining;

    return SizedBox(
      width: 240,
      child: Row(
        children: [
          IconButton(
            icon: Icon(
              _playbackState == AudioPlaybackState.playing
                  ? Icons.pause
                  : Icons.play_arrow,
            ),
            color: defaultTextColor,
            onPressed: _togglePlay,
            visualDensity: VisualDensity.compact,
          ),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  height: 18,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: List.generate(bars.length, (index) {
                      final height = bars[index].toDouble();
                      final isActive = index < activeCount;
                      final isHead = index == movingHead &&
                          _playbackState == AudioPlaybackState.playing;
                      return Expanded(
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 1),
                          height: height,
                          decoration: BoxDecoration(
                            color: isHead
                                ? colorScheme.secondary
                                : (isActive
                                    ? defaultTextColor
                                    : defaultTextColor.withValues(alpha: 0.3)),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      );
                    }),
                  ),
                ),
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    thumbColor: defaultTextColor,
                    activeTrackColor: defaultTextColor.withValues(alpha: 0.8),
                    inactiveTrackColor: defaultTextColor.withValues(alpha: 0.3),
                  ),
                  child: Slider(
                    value: value,
                    max: maxMs,
                    onChanged: (newValue) async {
                      if (_duration == Duration.zero) return;
                      final position = Duration(milliseconds: newValue.toInt());
                      await _player.seek(position);
                    },
                  ),
                ),
              ],
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                _formatDuration(_position),
                style: TextStyle(fontSize: 11, color: defaultTextColor),
              ),
              Text(
                '-${_formatDuration(remainingSafe)}',
                style: TextStyle(fontSize: 11, color: subtleTextColor),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
