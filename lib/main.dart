import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const IstamaApp());
}

class IstamaApp extends StatelessWidget {
  const IstamaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'إستمع',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(brightness: Brightness.dark, useMaterial3: true),
      builder: (context, child) => Directionality(
        textDirection: TextDirection.rtl,
        child: child ?? const SizedBox.shrink(),
      ),
      home: const HomeScreen(),
    );
  }
}

class SongMetaData {
  final String path;
  final String title;
  final String thumbnailUrl;

  const SongMetaData({
    required this.path,
    required this.title,
    required this.thumbnailUrl,
  });

  Map<String, dynamic> toJson() => {
        'path': path,
        'title': title,
        'thumbnailUrl': thumbnailUrl,
      };

  factory SongMetaData.fromJson(Map<String, dynamic> json) {
    return SongMetaData(
      path: json['path']?.toString() ?? '',
      title: json['title']?.toString() ?? 'عنوان غير معروف',
      thumbnailUrl: json['thumbnailUrl']?.toString() ?? '',
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const String _emptyTitle = 'اختر أغنية من المكتبة';

  final TextEditingController _urlController = TextEditingController();
  final AudioPlayer _audioPlayer = AudioPlayer();

  final Color primaryGreen = const Color(0xFF8B9A6E);
  final Color bgCream = const Color(0xFFF7F2EB);

  bool _isDownloading = false;
  bool _isPlaying = false;

  double _downloadProgress = 0.0;

  String _statusMessage = 'ألصق رابط يوتيوب لتحميل الصوتيات';
  String _currentSongName = _emptyTitle;

  String? _currentPlayingPath;
  String? _currentThumbnailUrl;

  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;

  List<File> _offlineSongs = <File>[];
  Map<String, SongMetaData> _songsMetadata = <String, SongMetaData>{};

  String _key(String path) => path.split(Platform.pathSeparator).last;

  @override
  void initState() {
    super.initState();
    _initialize();

    _audioPlayer.onPlayerStateChanged.listen((state) {
      if (!mounted) return;
      setState(() => _isPlaying = state == PlayerState.playing);
    });

    _audioPlayer.onDurationChanged.listen((d) {
      if (!mounted) return;
      setState(() => _duration = d);
    });

    _audioPlayer.onPositionChanged.listen((p) {
      if (!mounted) return;
      setState(() => _position = p);
    });

    _audioPlayer.onPlayerComplete.listen((_) {
      _nextSong();
    });
  }

  Future<void> _initialize() async {
    await _loadMetadata();
    await _loadOfflineSongs();
  }

  @override
  void dispose() {
    _urlController.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  Future<Directory> _getMusicDirectory() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/IstamaMusic');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<void> _loadMetadata() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('songs_metadata');
      if (raw == null || raw.isEmpty) return;

      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;

      final loaded = <String, SongMetaData>{};
      for (final entry in decoded.entries) {
        final value = entry.value;
        if (value is Map) {
          loaded[_key(entry.key.toString())] =
              SongMetaData.fromJson(Map<String, dynamic>.from(value));
        }
      }
      _songsMetadata = loaded;
    } catch (_) {
      _songsMetadata = <String, SongMetaData>{};
    }
  }

  Future<void> _saveMetadata() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final rawMap = <String, dynamic>{};
      for (final entry in _songsMetadata.entries) {
        rawMap[entry.key] = entry.value.toJson();
      }
      await prefs.setString('songs_metadata', jsonEncode(rawMap));
    } catch (_) {}
  }

  Future<void> _loadOfflineSongs() async {
    try {
      final directory = await _getMusicDirectory();
      final songs = directory.listSync().whereType<File>().where((file) {
        final p = file.path.toLowerCase();
        return p.endsWith('.mp3') ||
            p.endsWith('.m4a') ||
            p.endsWith('.mp4') ||
            p.endsWith('.webm') ||
            p.endsWith('.opus') ||
            p.endsWith('.aac');
      }).toList();

      songs.sort(
        (a, b) => a.path.toLowerCase().compareTo(b.path.toLowerCase()),
      );

      if (!mounted) return;
      setState(() => _offlineSongs = songs);
    } catch (_) {
      if (!mounted) return;
      setState(() => _offlineSongs = <File>[]);
    }
  }

  String _sanitizeFileName(String name) {
    var clean = name
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    if (clean.length > 60) {
      clean = clean.substring(0, 60).trim();
    }
    if (clean.isEmpty) {
      clean = 'audio_${DateTime.now().millisecondsSinceEpoch}';
    }
    return clean;
  }

  String _getFileNameWithoutExtension(String path) {
    final name = _key(path);
    final dot = name.lastIndexOf('.');
    return dot > 0 ? name.substring(0, dot) : name;
  }

  String _titleFor(File file) {
    return _songsMetadata[_key(file.path)]?.title ??
        _getFileNameWithoutExtension(file.path);
  }

  Future<void> _downloadAudio() async {
    final url = _urlController.text.trim();

    if (url.isEmpty) {
      setState(() => _statusMessage = 'يرجى إدخال رابط يوتيوب أولاً');
      return;
    }

    if (!url.contains('youtube.com') && !url.contains('youtu.be')) {
      setState(() => _statusMessage = 'الرابط يجب أن يكون من يوتيوب');
      return;
    }

    setState(() {
      _isDownloading = true;
      _downloadProgress = 0.0;
      _statusMessage = 'جاري الاتصال بيوتيوب...';
    });

    final yt = YoutubeExplode();

    File? tempFile;
    IOSink? outputSink;

    try {
      final video = await yt.videos.get(url);

      if (!mounted) return;
      setState(() {
        _statusMessage = 'جاري العثور على أفضل جودة صوت...';
      });

      final manifest = await yt.videos.streamsClient.getManifest(video.id);

      final mp4Streams = manifest.audioOnly
          .where((s) => s.container == StreamContainer.mp4)
          .toList();

      final AudioStreamInfo audioStreamInfo = mp4Streams.isNotEmpty
          ? mp4Streams.withHighestBitrate()
          : manifest.audioOnly.withHighestBitrate();

      final directory = await _getMusicDirectory();
      final cleanTitle = _sanitizeFileName(video.title);

      final extension = audioStreamInfo.container == StreamContainer.mp4
          ? 'm4a'
          : audioStreamInfo.container.name.toLowerCase();

      var candidate = File('${directory.path}/$cleanTitle.$extension');
      var counter = 1;
      while (await candidate.exists()) {
        candidate =
            File('${directory.path}/${cleanTitle}_$counter.$extension');
        counter++;
      }

      final downloadedFile = candidate;
      tempFile = downloadedFile;

      if (!mounted) return;
      setState(() => _statusMessage = 'جاري تنزيل الصوت...');

      final stream = yt.videos.streamsClient.get(audioStreamInfo);
      final sink = downloadedFile.openWrite();
      outputSink = sink;

      final totalBytes = audioStreamInfo.size.totalBytes;
      var receivedBytes = 0;
      var lastUiUpdate = 0.0;

      await for (final data in stream) {
        receivedBytes += data.length;
        sink.add(data);

        if (totalBytes > 0) {
          final progress = (receivedBytes / totalBytes).clamp(0.0, 1.0);
          if (mounted && progress - lastUiUpdate >= 0.01) {
            lastUiUpdate = progress;
            setState(() => _downloadProgress = progress);
          }
        }
      }

      await sink.flush();
      await sink.close();
      outputSink = null;
      tempFile = null;

      _songsMetadata[_key(downloadedFile.path)] = SongMetaData(
        path: _key(downloadedFile.path),
        title: video.title,
        thumbnailUrl: video.thumbnails.highResUrl,
      );

      await _saveMetadata();
      await _loadOfflineSongs();

      if (!mounted) return;
      setState(() {
        _statusMessage = 'تم التحميل بنجاح!';
        _isDownloading = false;
        _downloadProgress = 1.0;
        _urlController.clear();
      });

      await _playSong(
        downloadedFile.path,
        video.title,
        thumbnailUrl: video.thumbnails.highResUrl,
      );
    } catch (_) {
      try {
        await outputSink?.close();
      } catch (_) {}

      try {
        final f = tempFile;
        if (f != null && await f.exists()) {
          await f.delete();
        }
      } catch (_) {}

      if (mounted) {
        setState(() {
          _isDownloading = false;
          _downloadProgress = 0.0;
          _statusMessage = 'فشل التحميل. تأكد من الرابط والاتصال بالإنترنت.';
        });
      }
    } finally {
      yt.close();
    }
  }

  Future<void> _playSong(
    String path,
    String songName, {
    String? thumbnailUrl,
  }) async {
    if (!await File(path).exists()) {
      if (!mounted) return;
      setState(() => _statusMessage = 'الملف غير موجود');
      await _loadOfflineSongs();
      return;
    }

    try {
      await _audioPlayer.stop();

      if (!mounted) return;
      setState(() {
        _currentPlayingPath = path;
        _currentSongName = songName;
        _currentThumbnailUrl =
            thumbnailUrl ?? _songsMetadata[_key(path)]?.thumbnailUrl;
        _position = Duration.zero;
        _duration = Duration.zero;
      });

      await _audioPlayer.play(DeviceFileSource(path));

      if (!mounted) return;
      setState(() => _statusMessage = 'يتم تشغيل الصوت');
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isPlaying = false;
        _statusMessage = 'تعذر تشغيل الملف الصوتي';
      });
    }
  }

  Future<void> _togglePlayPause() async {
    if (_isPlaying) {
      await _audioPlayer.pause();
      return;
    }

    final current = _currentPlayingPath;
    if (current != null && await File(current).exists()) {
      await _audioPlayer.resume();
      return;
    }

    if (_offlineSongs.isNotEmpty) {
      final first = _offlineSongs.first;
      await _playSong(
        first.path,
        _titleFor(first),
        thumbnailUrl: _songsMetadata[_key(first.path)]?.thumbnailUrl,
      );
    }
  }

  Future<void> _seekSeconds(int seconds) async {
    if (_duration == Duration.zero) return;

    var target = _position + Duration(seconds: seconds);
    if (target < Duration.zero) target = Duration.zero;
    if (target > _duration) target = _duration;

    await _audioPlayer.seek(target);
  }

  Future<void> _nextSong() async {
    if (_offlineSongs.isEmpty || _currentPlayingPath == null) return;

    final index =
        _offlineSongs.indexWhere((f) => f.path == _currentPlayingPath);

    if (index >= 0 && index < _offlineSongs.length - 1) {
      final next = _offlineSongs[index + 1];
      await _playSong(
        next.path,
        _titleFor(next),
        thumbnailUrl: _songsMetadata[_key(next.path)]?.thumbnailUrl,
      );
    } else {
      await _audioPlayer.stop();
      if (!mounted) return;
      setState(() {
        _isPlaying = false;
        _position = Duration.zero;
      });
    }
  }

  Future<void> _previousSong() async {
    if (_offlineSongs.isEmpty || _currentPlayingPath == null) return;

    final index =
        _offlineSongs.indexWhere((f) => f.path == _currentPlayingPath);

    if (index > 0) {
      final prev = _offlineSongs[index - 1];
      await _playSong(
        prev.path,
        _titleFor(prev),
        thumbnailUrl: _songsMetadata[_key(prev.path)]?.thumbnailUrl,
      );
    }
  }

  Future<void> _deleteSong(String path) async {
    if (_currentPlayingPath == path) {
      await _audioPlayer.stop();
      if (mounted) {
        setState(() {
          _currentPlayingPath = null;
          _currentSongName = _emptyTitle;
          _currentThumbnailUrl = null;
          _duration = Duration.zero;
          _position = Duration.zero;
          _isPlaying = false;
        });
      }
    }

    try {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}

    _songsMetadata.remove(_key(path));

    await _saveMetadata();
    await _loadOfflineSongs();

    if (!mounted) return;
    setState(() => _statusMessage = 'تم حذف الصوتية');
  }

  String _formatDuration(Duration duration) {
    final minutes =
        duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds =
        duration.inSeconds.remainder(60).toString().padLeft(2, '0');

    if (duration.inHours > 0) {
      final hours = duration.inHours.toString().padLeft(2, '0');
      return '$hours:$minutes:$seconds';
    }
    return '$minutes:$seconds';
  }

  Widget _glassContainer({required Widget child, double radius = 24}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.14),
          width: 1,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: child,
        ),
      ),
    );
  }

  Widget _songIcon({double size = 52}) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: primaryGreen.withValues(alpha: 0.20),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Icon(
        Icons.music_note_rounded,
        color: primaryGreen,
        size: size * 0.52,
      ),
    );
  }

  Widget _thumb(String? url, double size) {
    if (url == null || url.isEmpty) return _songIcon(size: size);
    return Image.network(
      url,
      width: size,
      height: size,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => _songIcon(size: size),
    );
  }

  Widget _buildLibrary() {
    if (_offlineSongs.isEmpty) {
      return _glassContainer(
        child: Padding(
          padding: const EdgeInsets.all(26),
          child: Center(
            child: Column(
              children: [
                _songIcon(size: 64),
                const SizedBox(height: 14),
                Text(
                  'مكتبتك فارغة',
                  style: TextStyle(
                    color: bgCream,
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'أضف رابط يوتيوب لتحميل أول صوتية',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: bgCream.withValues(alpha: 0.55),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return _glassContainer(
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: _offlineSongs.length,
        separatorBuilder: (_, __) => Divider(
          height: 1,
          color: Colors.white.withValues(alpha: 0.07),
        ),
        itemBuilder: (context, index) {
          final file = _offlineSongs[index];
          final metadata = _songsMetadata[_key(file.path)];
          final title = _titleFor(file);
          final thumbnail = metadata?.thumbnailUrl ?? '';
          final isCurrent = _currentPlayingPath == file.path;

          return ListTile(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            onTap: () => _playSong(
              file.path,
              title,
              thumbnailUrl: thumbnail,
            ),
            leading: ClipRRect(
              borderRadius: BorderRadius.circular(13),
              child: _thumb(thumbnail, 52),
            ),
            title: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: bgCream,
                fontWeight: FontWeight.w600,
              ),
            ),
            subtitle: Text(
              isCurrent ? 'يعمل الآن' : 'محفوظ Offline',
              style: TextStyle(color: primaryGreen, fontSize: 11),
            ),
            trailing: PopupMenuButton<String>(
              icon: Icon(
                Icons.more_vert_rounded,
                color: bgCream.withValues(alpha: 0.65),
              ),
              onSelected: (value) {
                if (value == 'delete') {
                  _deleteSong(file.path);
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem<String>(
                  value: 'delete',
                  child: Text('حذف'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildPlayer() {
    final maxMilliseconds = _duration.inMilliseconds;
    final maxValue = maxMilliseconds > 0 ? maxMilliseconds.toDouble() : 1.0;
    final currentValue =
        _position.inMilliseconds.toDouble().clamp(0.0, maxValue);

    return _glassContainer(
      radius: 28,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: _thumb(_currentThumbnailUrl, 160),
            ),
            const SizedBox(height: 16),
            Text(
              _currentSongName,
              maxLines: 2,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: bgCream,
                fontSize: 17,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Slider(
              value: currentValue,
              max: maxValue,
              activeColor: primaryGreen,
              inactiveColor: Colors.white24,
              onChanged: maxMilliseconds > 0
                  ? (v) => _audioPlayer.seek(Duration(milliseconds: v.toInt()))
                  : null,
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _formatDuration(_position),
                    style: TextStyle(color: bgCream.withValues(alpha: 0.6)),
                  ),
                  Text(
                    _formatDuration(_duration),
                    style: TextStyle(color: bgCream.withValues(alpha: 0.6)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton
