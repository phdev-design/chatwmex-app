import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:app/core/network/network_service.dart';

class AudioMessageBubble extends StatefulWidget {
  final String audioUrl;

  const AudioMessageBubble({super.key, required this.audioUrl});

  @override
  State<AudioMessageBubble> createState() => _AudioMessageBubbleState();
}

class _AudioMessageBubbleState extends State<AudioMessageBubble> {
  late final AudioPlayer _player;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  bool _isPlaying = false;
  late String _resolvedUrl;

  @override
  void initState() {
    super.initState();
    _player = AudioPlayer();
    _resolvedUrl = NetworkService.resolveUrl(widget.audioUrl);
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
        _isPlaying = false;
        _position = Duration.zero;
      });
    });
  }

  @override
  void didUpdateWidget(covariant AudioMessageBubble oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.audioUrl != widget.audioUrl) {
      _resolvedUrl = NetworkService.resolveUrl(widget.audioUrl);
      _player.stop();
      setState(() {
        _isPlaying = false;
        _position = Duration.zero;
        _duration = Duration.zero;
      });
    }
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _togglePlay() async {
    if (_isPlaying) {
      await _player.pause();
      setState(() => _isPlaying = false);
    } else {
      await _player.play(UrlSource(_resolvedUrl));
      setState(() => _isPlaying = true);
    }
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
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
            icon: Icon(_isPlaying ? Icons.pause : Icons.play_arrow),
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
                      final isHead = index == movingHead && _isPlaying;
                      return Expanded(
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 1),
                          height: height,
                          decoration: BoxDecoration(
                            color: isHead
                                ? colorScheme.secondary
                                : (isActive
                                    ? colorScheme.primary
                                    : colorScheme.outlineVariant),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      );
                    }),
                  ),
                ),
                Slider(
                  value: value,
                  max: maxMs,
                  onChanged: (newValue) async {
                    if (_duration == Duration.zero) return;
                    final position = Duration(milliseconds: newValue.toInt());
                    await _player.seek(position);
                  },
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
                style: TextStyle(fontSize: 11, color: colorScheme.onSurface),
              ),
              Text(
                '-${_formatDuration(remainingSafe)}',
                style: TextStyle(fontSize: 11, color: colorScheme.outline),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
