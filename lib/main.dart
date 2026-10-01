import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF1E231B),
      ),
      home: const HomeScreen(),
    );
  }
}

class SongMetaData {
  final String path;
  final String title;
  final String thumbnailUrl;

  SongMetaData({required this.path, required this.title, required this.thumbnailUrl});

  Map<String, dynamic> toJson() => {
        'path': path,
        'title': title,
        'thumbnailUrl': thumbnailUrl,
      };

  factory SongMetaData.fromJson(Map<String, dynamic> json) => SongMetaData(
        path: json['path'] ?? '',
        title: json['title'] ?? 'عنوان غير معروف',
        thumbnailUrl: json['thumbnailUrl'] ?? '',
      );
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _urlController = TextEditingController();
  final AudioPlayer _audioPlayer = AudioPlayer();

  bool _isDownloading = false;
  bool _isInputExpanded = false;
  double _downloadProgress = 0.0;
  String _statusMessage = 'ألصق رابط يوتيوب لتحميل الصوتيات';

  List<File> _offlineSongs = [];
  Map<String, SongMetaData> _songsMetadata = {};

  String? _currentPlayingPath;
  String _currentSongName = 'اختر أغنية من المكتبة';
  String? _currentThumbnailUrl;
  bool _isPlaying = false;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;

  final Color primaryGreen = const Color(0xFF8B9A6E);
  final Color bgCream = const Color(0xFFF7F2EB);

  @override
  void initState() {
    super.initState();
    _initLibrary();

    _audioPlayer.onPlayerStateChanged.listen((state) {
      if (mounted) {
        setState(() {
          _isPlaying = state == PlayerState.playing;
        });
      }
    });

    _audioPlayer.onDurationChanged.listen((newDuration) {
      if (mounted) {
        setState(() {
          _duration = newDuration;
        });
      }
    });

    _audioPlayer.onPositionChanged.listen((newPosition) {
      if (mounted) {
        setState(() {
          _position = newPosition;
        });
      }
    });

    _audioPlayer.onPlayerComplete.listen((event) {
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
    final baseDir = await getApplicationDocumentsDirectory();
    final musicDir = Directory('${baseDir.path}/IstamaMusic');
    if (!await musicDir.exists()) {
      await musicDir.create(recursive: true);
    }
    return musicDir;
  }

  Future<void> _loadMetadata() async {
    final prefs = await SharedPreferences.getInstance();
    final String? metadataRaw = prefs.getString('songs_metadata');
    if (metadataRaw != null) {
      try {
        final Map<String, dynamic> decoded = jsonDecode(metadataRaw);
        _songsMetadata = decoded.map(
          (key, value) => MapEntry(key, SongMetaData.fromJson(value)),
        );
      } catch (_) {}
    }
  }

  Future<void> _saveMetadata() async {
    final prefs = await SharedPreferences.getInstance();
    final Map<String, dynamic> rawMap = _songsMetadata.map(
      (key, value) => MapEntry(key, value.toJson()),
    );
    await prefs.setString('songs_metadata', jsonEncode(rawMap));
  }

  Future<void> _loadOfflineSongs() async {
    final dir = await _getMusicDirectory();
    if (await dir.exists()) {
      final List<FileSystemEntity> files = dir.listSync();
      final List<File> songFiles = files
          .whereType<File>()
          .where((f) => f.path.endsWith('.m4a') || f.path.endsWith('.mp3') || f.path.endsWith('.webm'))
          .toList();

      // ترتيب الأغاني أبجدياً لثبات القائمة
      songFiles.sort((a, b) => a.path.compareTo(b.path));

      if (mounted) {
        setState(() {
          _offlineSongs = songFiles;
        });
      }
    }
  }

  String _sanitizeFileName(String name) {
    String clean = name.replaceAll(RegExp(r'[^\w\s\u0600-\u06FF]'), '_').trim();
    if (clean.length > 50) {
      clean = clean.substring(0, 50);
    }
    if (clean.isEmpty) {
      clean = 'audio_${DateTime.now().millisecondsSinceEpoch}';
    }
    return clean;
  }

  Future<void> _downloadAudio() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) {
      if (mounted) {
        setState(() => _statusMessage = 'يرجى إدخال الرابط أولاً!');
      }
      return;
    }

    if (Platform.isAndroid) {
      await Permission.storage.request();
    }

    if (mounted) {
      setState(() {
        _isDownloading = true;
        _downloadProgress = 0.0;
        _statusMessage = 'جاري الاتصال واستخراج الصوت...';
      });
    }

    final yt = YoutubeExplode();
    File? tempFile;
    IOSink? outputSink;

    try {
      final video = await yt.videos.get(url);
      final manifest = await yt.videos.streamsClient.getManifest(video.id);
      final audioStreamInfo = manifest.audioOnly.withHighestBitrate();

      final String containerExtension = audioStreamInfo.container.name; // m4a or webm
      final dir = await _getMusicDirectory();
      String cleanTitle = _sanitizeFileName(video.title);
      
      String finalFilePath = '${dir.path}/$cleanTitle.$containerExtension';
      tempFile = File(finalFilePath);

      // التعامل مع الملفات المكررة
      int counter = 1;
      while (await tempFile.exists()) {
        finalFilePath = '${dir.path}/${cleanTitle}_$counter.$containerExtension';
        tempFile = File(finalFilePath);
        counter++;
      }

      if (mounted) {
        setState(() {
          _currentSongName = video.title;
          _currentThumbnailUrl = video.thumbnails.highResUrl;
          _statusMessage = 'جاري تنزيل الملف الصوتي...';
        });
      }

      final stream = yt.videos.streamsClient.get(audioStreamInfo);
      outputSink = tempFile.openWrite();
      var totalBytes = audioStreamInfo.size.totalBytes;
      var receivedBytes = 0;

      await for (var data in stream) {
        receivedBytes += data.length;
        outputSink.add(data);
        if (mounted && totalBytes > 0) {
          setState(() {
            _downloadProgress = (receivedBytes / totalBytes).clamp(0.0, 1.0);
          });
        }
      }

      await outputSink.flush();
      await outputSink.close();
      outputSink = null;

      // حفظ الـ Metadata محلياً
      final meta = SongMetaData(
        path: tempFile.path,
        title: video.title,
        thumbnailUrl: video.thumbnails.highResUrl,
      );
      _songsMetadata[tempFile.path] = meta;
      await _saveMetadata();

      if (mounted) {
        setState(() {
          _statusMessage = 'تم التحميل واكتملت الإضافة!';
          _isDownloading = false;
          _isInputExpanded = false;
          _urlController.clear();
        });
      }

      await _loadOfflineSongs();
      _playSong(tempFile.path, meta.title, thumbnailUrl: meta.thumbnailUrl);

    } catch (e) {
      if (outputSink != null) {
        await outputSink.close();
      }
      if (tempFile != null && await tempFile.exists()) {
        await tempFile.delete();
      }
      if (mounted) {
        setState(() {
          _statusMessage = 'فشل الاستخراج: تأكد من صحة الرابط أو الشبكة!';
          _isDownloading = false;
        });
      }
    } finally {
      yt.close();
    }
  }

  Future<void> _playSong(String path, String songName, {String? thumbnailUrl}) async {
    _currentPlayingPath = path;
    _currentSongName = songName;
    _currentThumbnailUrl = thumbnailUrl ?? _songsMetadata[path]?.thumbnailUrl;

    await _audioPlayer.stop();
    await _audioPlayer.play(DeviceFileSource(path));
    if (mounted) setState(() {});
  }

  Future<void> _togglePlayPause() async {
    if (_isPlaying) {
      await _audioPlayer.pause();
    } else if (_currentPlayingPath != null) {
      await _audioPlayer.resume();
    } else if (_offlineSongs.isNotEmpty) {
      var firstFile = _offlineSongs.first;
      var meta = _songsMetadata[firstFile.path];
      _playSong(
        firstFile.path,
        meta?.title ?? firstFile.path.split('/').last,
        thumbnailUrl: meta?.thumbnailUrl,
      );
    }
  }

  Future<void> _seek10Seconds(bool forward) async {
    if (_duration == Duration.zero) return;
    int currentMs = _position.inMilliseconds;
    int targetMs = forward ? currentMs + 10000 : currentMs - 10000;
    targetMs = targetMs.clamp(0, _duration.inMilliseconds);
    await _audioPlayer.seek(Duration(milliseconds: targetMs));
  }

  void _nextSong() {
    if (_offlineSongs.isEmpty || _currentPlayingPath == null) return;
    int currentIndex = _offlineSongs.indexWhere((f) => f.path == _currentPlayingPath);
    if (currentIndex != -1 && currentIndex < _offlineSongs.length - 1) {
      var nextFile = _offlineSongs[currentIndex + 1];
      var meta = _songsMetadata[nextFile.path];
      _playSong(
        nextFile.path,
        meta?.title ?? nextFile.path.split('/').last,
        thumbnailUrl: meta?.thumbnailUrl,
      );
    } else {
      _audioPlayer.stop();
      if (mounted) setState(() => _isPlaying = false);
    }
  }

  void _previousSong() {
    if (_offlineSongs.isEmpty || _currentPlayingPath == null) return;
    int currentIndex = _offlineSongs.indexWhere((f) => f.path == _currentPlayingPath);
    if (currentIndex > 0) {
      var prevFile = _offlineSongs[currentIndex - 1];
      var meta = _songsMetadata[prevFile.path];
      _playSong(
        prevFile.path,
        meta?.title ?? prevFile.path.split('/').last,
        thumbnailUrl: meta?.thumbnailUrl,
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
    }

    File file = File(path);
    if (await file.exists()) {
      await file.delete();
    }

    _songsMetadata.remove(path);
    await _saveMetadata();
    await _loadOfflineSongs();
  }

  @override
  Widget build(BuildContext context) {
    double maxDurationSec = _duration.inSeconds.toDouble();
    double currentPosSec = _position.inSeconds.toDouble().clamp(0.0, maxDurationSec > 0 ? maxDurationSec : 1.0);

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
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 10),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Text(
                      'إِ سْـ تَـ مِـ عَ',
                      style: GoogleFonts.reey(
                        textStyle: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                          color: bgCream,
                          letterSpacing: 2,
                        ),
                      ),
                    ),
                  ),

                  // Collapsible Card
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 350),
                    curve: Curves.easeInOutCubic,
                    margin: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: Colors.white.withOpacity(0.15), width: 1.5),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(24),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                        child: Column(
                          children: [
                            InkWell(
                              onTap: () {
                                setState(() {
                                  _isInputExpanded = !_isInputExpanded;
                                });
                              },
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Row(
                                      children: [
                                        Icon(Icons.link_rounded, color: primaryGreen),
                                        const SizedBox(width: 10),
                                        Text(
                                          'إضافة رابط جديد',
                                          style: TextStyle(color: bgCream, fontWeight: FontWeight.w600, fontSize: 15),
                                        ),
                                      ],
                                    ),
                                    Icon(
                                      _isInputExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                                      color: bgCream.withOpacity(0.7),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            if (_isInputExpanded)
                              Padding(
                                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                                child: Column(
                                  children: [
                                    const Divider(color: Colors.white10, height: 1),
                                    const SizedBox(height: 12),
                                    TextField(
                                      controller: _urlController,
                                      style: TextStyle(color: bgCream),
                                      decoration: InputDecoration(
                                        hintText: 'ضع رابط يوتيوب هنا...',
                                        hintStyle: TextStyle(color: bgCream.withOpacity(0.4)),
                                        filled: true,
                                        fillColor: Colors.black.withOpacity(0.25),
                                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(16),
                                          borderSide: BorderSide.none,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    SizedBox(
                                      width: double.infinity,
                                      height: 46,
                                      child: ElevatedButton.icon(
                                        onPressed: _isDownloading ? null : _downloadAudio,
                                        icon: const Icon(Icons.download_rounded, color: Colors.black87),
                                        label: Text(
                                          _isDownloading ? 'جاري الاستخراج...' : 'تحميل واستخراج الصوت',
                                          style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.bold),
                                        ),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: primaryGreen,
                                          elevation: 0,
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                        ),
                                      ),
                                    ),
                                    if (_isDownloading)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 10),
                                        child: ClipRRect(
                                          borderRadius: BorderRadius.circular(8),
                                          child: LinearProgressIndicator(value: _downloadProgress, color: primaryGreen, backgroundColor: Colors.white10),
                                        ),
                                      ),
                                    const SizedBox(height: 8),
                                    Text(_statusMessage, style: TextStyle(fontSize: 12, color: bgCream.withOpacity(0.6))),
                                  ],
                                ),
                              )
                          ],
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 10),

                  // Player View
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(28),
                      border: Border.all(color: Colors.white.withOpacity(0.2), width: 1.5),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(28),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(16),
                                  child: (_currentThumbnailUrl != null && _currentThumbnailUrl!.isNotEmpty)
                                      ? Image.network(_currentThumbnailUrl!, width: 65, height: 65, fit: BoxFit.cover, errorBuilder: (_, __, ___) {
                                          return Container(
                                            width: 65,
                                            height: 65,
                                            color: primaryGreen.withOpacity(0.2),
                       
