import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
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
      theme: ThemeData.dark(),
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

  Map<String, dynamic> toJson() {
    return {
      'path': path,
      'title': title,
      'thumbnailUrl': thumbnailUrl,
    };
  }

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
  final TextEditingController _urlController = TextEditingController();
  final AudioPlayer _audioPlayer = AudioPlayer();

  final Color primaryGreen = const Color(0xFF8B9A6E);
  final Color bgCream = const Color(0xFFF7F2EB);

  bool _isDownloading = false;
  bool _isInputExpanded = false;
  bool _isPlaying = false;

  double _downloadProgress = 0.0;

  String _statusMessage = 'ألصق رابط يوتيوب لتحميل الصوتيات';
  String _currentSongName = 'اختر أغنية من المكتبة';

  String? _currentPlayingPath;
  String? _currentThumbnailUrl;

  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;

  List<File> _offlineSongs = [];
  Map<String, SongMetaData> _songsMetadata = {};

  @override
  void initState() {
    super.initState();

    _initLibrary();

    _audioPlayer.onPlayerStateChanged.listen((state) {
      if (!mounted) return;

      setState(() {
        _isPlaying = state == PlayerState.playing;
      });
    });

    _audioPlayer.onDurationChanged.listen((duration) {
      if (!mounted) return;

      setState(() {
        _duration = duration;
      });
    });

    _audioPlayer.onPositionChanged.listen((position) {
      if (!mounted) return;

      setState(() {
        _position = position;
      });
    });

    _audioPlayer.onPlayerComplete.listen((_) {
      _nextSong();
    });
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _initLibrary() async {
    await _loadMetadata();
    await _loadOfflineSongs();
  }

  Future<Directory> _getMusicDirectory() async {
    final baseDirectory = await getApplicationDocumentsDirectory();

    final musicDirectory = Directory(
      '${baseDirectory.path}/IstamaMusic',
    );

    if (!await musicDirectory.exists()) {
      await musicDirectory.create(recursive: true);
    }

    return musicDirectory;
  }

  Future<void> _loadMetadata() async {
    final prefs = await SharedPreferences.getInstance();

    final metadataRaw = prefs.getString('songs_metadata');

    if (metadataRaw == null || metadataRaw.isEmpty) {
      return;
    }

    try {
      final decoded = jsonDecode(metadataRaw);

      if (decoded is Map<String, dynamic>) {
        final Map<String, SongMetaData> loaded = {};

        decoded.forEach((key, value) {
          if (value is Map<String, dynamic>) {
            loaded[key] = SongMetaData.fromJson(value);
          }
        });

        _songsMetadata = loaded;
      }
    } catch (_) {
      _songsMetadata = {};
    }
  }

  Future<void> _saveMetadata() async {
    final prefs = await SharedPreferences.getInstance();

    final rawMap = <String, dynamic>{};

    _songsMetadata.forEach((key, value) {
      rawMap[key] = value.toJson();
    });

    await prefs.setString(
      'songs_metadata',
      jsonEncode(rawMap),
    );
  }

  Future<void> _loadOfflineSongs() async {
    try {
      final directory = await _getMusicDirectory();

      final entities = directory.listSync();

      final songs = entities
          .whereType<File>()
          .where((file) {
            final path = file.path.toLowerCase();

            return path.endsWith('.mp3') ||
                path.endsWith('.m4a') ||
                path.endsWith('.webm');
          })
          .toList();

      songs.sort(
        (a, b) => a.path.toLowerCase().compareTo(
              b.path.toLowerCase(),
            ),
      );

      if (!mounted) return;

      setState(() {
        _offlineSongs = songs;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _offlineSongs = [];
      });
    }
  }

  String _sanitizeFileName(String name) {
    var clean = name
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    if (clean.length > 50) {
      clean = clean.substring(0, 50).trim();
    }

    if (clean.isEmpty) {
      clean = 'audio_${DateTime.now().millisecondsSinceEpoch}';
    }

    return clean;
  }

  String _getFileNameWithoutExtension(String path) {
    final name = path.split(Platform.pathSeparator).last;

    final dotIndex = name.lastIndexOf('.');

    if (dotIndex > 0) {
      return name.substring(0, dotIndex);
    }

    return name;
  }

  Future<void> _downloadAudio() async {
    final url = _urlController.text.trim();

    if (url.isEmpty) {
      if (!mounted) return;

      setState(() {
        _statusMessage = 'يرجى إدخال الرابط أولاً!';
      });

      return;
    }

    if (!mounted) return;

    setState(() {
      _isDownloading = true;
      _downloadProgress = 0;
      _statusMessage = 'جاري الاتصال واستخراج الصوت...';
    });

    final yt = YoutubeExplode();

    File? tempFile;
    IOSink? outputSink;

    try {
      final video = await yt.videos.get(url);

      final manifest =
          await yt.videos.streamsClient.getManifest(video.id);

      final audioStreamInfo =
          manifest.audioOnly.withHighestBitrate();

      final directory = await _getMusicDirectory();

      final cleanTitle = _sanitizeFileName(video.title);

      final extension = audioStreamInfo.container.name.toLowerCase();

      var finalPath =
          '${directory.path}/$cleanTitle.$extension';

      tempFile = File(finalPath);

      var counter = 1;

      while (await tempFile.exists()) {
        finalPath =
            '${directory.path}/${cleanTitle}_$counter.$extension';

        tempFile = File(finalPath);

        counter++;
      }

      if (!mounted) return;

      setState(() {
        _currentSongName = video.title;
        _currentThumbnailUrl =
            video.thumbnails.highResUrl;
        _statusMessage = 'جاري تنزيل الملف الصوتي...';
      });

      final stream =
          yt.videos.streamsClient.get(audioStreamInfo);

      outputSink = tempFile.openWrite();

      final totalBytes =
          audioStreamInfo.size.totalBytes;

      var receivedBytes = 0;

      await for (final data in stream) {
        receivedBytes += data.length;

        outputSink.add(data);

        if (mounted && totalBytes > 0) {
          setState(() {
            _downloadProgress =
                (receivedBytes / totalBytes)
                    .clamp(0.0, 1.0);
          });
        }
      }

      await outputSink.flush();
      await outputSink.close();

      outputSink = null;

      final downloadedFile = tempFile;

      final metadata = SongMetaData(
        path: downloadedFile.path,
        title: video.title,
        thumbnailUrl: video.thumbnails.highResUrl,
      );

      _songsMetadata[downloadedFile.path] = metadata;

      await _saveMetadata();
      await _loadOfflineSongs();

      if (!mounted) return;

      setState(() {
        _statusMessage = 'تم التحميل بنجاح!';
        _isDownloading = false;
        _isInputExpanded = false;
        _urlController.clear();
      });

      await _playSong(
        downloadedFile.path,
        metadata.title,
        thumbnailUrl: metadata.thumbnailUrl,
      );
    } catch (e) {
      if (outputSink != null) {
        try {
          await outputSink.close();
        } catch (_) {}
      }

      if (tempFile != null) {
        try {
          if (await tempFile.exists()) {
            await tempFile.delete();
          }
        } catch (_) {}
      }

      if (!mounted) return;

      setState(() {
        _isDownloading = false;
        _downloadProgress = 0;
        _statusMessage =
            'فشل الاستخراج: تحقق من الرابط والاتصال بالإنترنت.';
      });
    } finally {
      yt.close();
    }
  }

  Future<void> _playSong(
    String path,
    String songName, {
    String? thumbnailUrl,
  }) async {
    final file = File(path);

    if (!await file.exists()) {
      if (!mounted) return;

      setState(() {
        _statusMessage = 'الملف غير موجود.';
      });

      await _loadOfflineSongs();
      return;
    }

    try {
      await _audioPlayer.stop();

      _currentPlayingPath = path;
      _currentSongName = songName;

      _currentThumbnailUrl =
          thumbnailUrl ??
              _songsMetadata[path]?.thumbnailUrl;

      _position = Duration.zero;
      _duration = Duration.zero;

      await _audioPlayer.play(
        DeviceFileSource(path),
      );

      if (!mounted) return;

      setState(() {});
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _statusMessage =
            'تعذر تشغيل الملف الصوتي.';
        _isPlaying = false;
      });
    }
  }

  Future<void> _togglePlayPause() async {
    if (_isPlaying) {
      await _audioPlayer.pause();
      return;
    }

    if (_currentPlayingPath != null) {
      final file = File(_currentPlayingPath!);

      if (await file.exists()) {
        await _audioPlayer.resume();
        return;
      }
    }

    if (_offlineSongs.isNotEmpty) {
      final firstFile = _offlineSongs.first;
      final metadata =
          _songsMetadata[firstFile.path];

      await _playSong(
        firstFile.path,
        metadata?.title ??
            _getFileNameWithoutExtension(
              firstFile.path,
            ),
        thumbnailUrl: metadata?.thumbnailUrl,
      );
    }
  }

  Future<void> _seek10Seconds(bool forward) async {
    if (_duration == Duration.zero) return;

    var target =
        _position + Duration(seconds: forward ? 10 : -10);

    if (target < Duration.zero) {
      target = Duration.zero;
    }

    if (target > _duration) {
      target = _duration;
    }

    await _audioPlayer.seek(target);
  }

  Future<void> _nextSong() async {
    if (_offlineSongs.isEmpty ||
        _currentPlayingPath == null) {
      return;
    }

    final currentIndex =
        _offlineSongs.indexWhere(
      (file) => file.path == _currentPlayingPath,
    );

    if (currentIndex >= 0 &&
        currentIndex < _offlineSongs.length - 1) {
      final nextFile =
          _offlineSongs[currentIndex + 1];

      final metadata =
          _songsMetadata[nextFile.path];

      await _playSong(
        nextFile.path,
        metadata?.title ??
            _getFileNameWithoutExtension(
              nextFile.path,
            ),
        thumbnailUrl: metadata?.thumbnailUrl,
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
    if (_offlineSongs.isEmpty ||
        _currentPlayingPath == null) {
      return;
    }

    final currentIndex =
        _offlineSongs.indexWhere(
      (file) => file.path == _currentPlayingPath,
    );

    if (currentIndex > 0) {
      final previousFile =
          _offlineSongs[currentIndex - 1];

      final metadata =
          _songsMetadata[previousFile.path];

      await _playSong(
        previousFile.path,
        metadata?.title ??
            _getFileNameWithoutExtension(
              previousFile.path,
            ),
        thumbnailUrl: metadata?.thumbnailUrl,
      );
    }
  }

  Future<void> _deleteSong(String path) async {
    if (_currentPlayingPath == path) {
      await _audioPlayer.stop();

      _currentPlayingPath = null;
      _currentSongName = 'اختر أغنية من المكتبة';
      _currentThumbnailUrl = null;
      _duration = Duration.zero;
      _position = Duration.zero;
      _isPlaying = false;
    }

    final file = File(path);

    try {
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}

    _songsMetadata.remove(path);

    await _saveMetadata();
    await _loadOfflineSongs();

    if (mounted) {
      setState(() {});
    }
  }

  String _formatDuration(Duration duration) {
    final minutes =
        duration.inMinutes.remainder(60).toString().padLeft(2, '0');

    final seconds =
        duration.inSeconds.remainder(60).toString().padLeft(2, '0');

    if (duration.inHours > 0) {
      final hours =
          duration.inHours.toString().padLeft(2, '0');

      return '$hours:$minutes:$seconds';
    }

    return '$minutes:$seconds';
  }

  Widget _glassContainer({
    required Widget child,
    double radius = 24,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color: Colors.white.withOpacity(0.15),
          width: 1.2,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX: 15,
            sigmaY: 15,
          ),
          child: child,
        ),
      ),
    );
  }

  Widget _buildSongList() {
    if (_offlineSongs.isEmpty) {
      return _glassContainer(
        radius: 24,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              Icon(
                Icons.library_music_outlined,
                color: primaryGreen,
                size: 42,
              ),
              const SizedBox(height: 10),
              Text(
                'مكتبتك فارغة',
                style: TextStyle(
                  color: bgCream,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                'أضف رابطاً لتحميل أول صوتية',
                style: TextStyle(
                  color: bgCream.withOpacity(0.55),
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return _glassContainer(
      radius: 24,
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(
          vertical: 8,
        ),
        itemCount: _offlineSongs.length,
        separatorBuilder: (_, __) => Divider(
          color: Colors.white.withOpacity(0.07),
          height: 1,
        ),
        itemBuilder: (context, index) {
          final file = _offlineSongs[index];

          final metadata =
              _songsMetadata[file.path];

          final title =
              metadata?.title ??
                  _getFileNameWithoutExtension(
                    file.path,
                  );

          final thumbnail =
              metadata?.thumbnailUrl ?? '';

          final isCurrent =
              _currentPlayingPath == file.path;

          return ListTile(
            onTap: () {
              _playSong(
                file.path,
                title,
                thumbnailUrl: thumbnail,
              );
            },
            leading: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: thumbnail.isNotEmpty
                  ? Image.network(
                      thumbnail,
                      width: 52,
                      height: 52,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) {
                        return _songIcon();
                      },
                    )
                  : _songIcon(),
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
              isCurrent
                  ? 'شغال حالياً'
                  : 'صوتية محفوظة',
              style: TextStyle(
                color: primaryGreen,
                fontSize: 11,
              ),
            ),
            trailing: PopupMenuButton<String>(
              icon: Icon(
                Icons.more_vert,
                color: bgCream.withOpacity(0.7),
              ),
              onSelected: (value) {
                if (value == 'delete') {
                  _deleteSong(file.path);
                }
              },
              itemBuilder: (_) {
                return const [
                  PopupMenuItem(
                    value: 'delete',
                    child: Text('حذف'),
                  ),
                ];
              },
            ),
          );
        },
      ),
    );
  }

  Widget _songIcon() {
    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        color: primaryGreen.withOpacity(0.2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(
        Icons.music_note_rounded,
        color: primaryGreen,
        size: 28,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final maxDuration =
        _duration.inMilliseconds.toDouble();

    final currentPosition =
        _position.inMilliseconds
            .clamp(
              0,
              maxDuration > 0 ? maxDuration : 1,
            )
            .toDouble();

    return Scaffold(
      body: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  const Color(0xFF192017),
                  primaryGreen.withOpacity(0.4),
                  const Color(0xFF121511),
                ],
                begin: Alignment.topRight,
                end: Alignment.bottomLeft,
              ),
            ),
          ),

          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 10,
              ),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: 10,
                    ),
                    child: Text(
                      'إستمع',
                      style: GoogleFonts.cairo(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        color: bgCream,
                      ),
                    ),
                  ),

                  // إضافة رابط
                  AnimatedContainer(
                    duration:
                        const Duration(milliseconds: 350),
                    curve: Curves.easeInOutCubic,
                    margin: const EdgeInsets.symmetric(
                      ver
