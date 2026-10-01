import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:google_fonts/google_fonts.dart';

void main() {
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

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _urlController = TextEditingController();
  final AudioPlayer _audioPlayer = AudioPlayer();

  bool _isDownloading = false;
  bool _isInputExpanded = false; // بطاقة مطوية
  double _downloadProgress = 0.0;
  String _statusMessage = 'ألصق رابط يوتيوب لتحميل الصوتيات';

  List<FileSystemEntity> _offlineSongs = [];
  String? _currentPlayingPath;
  String _currentSongName = 'اختر أغنية من المكتبة';
  String? _currentThumbnailUrl;
  bool _isPlaying = false;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;

  // الألوان المستخرجة من الصورة الثانية
  final Color primaryGreen = const Color(0xFF8B9A6E);
  final Color bgCream = const Color(0xFFF7F2EB);
  final Color secondaryBeige = const Color(0xFFEAE2D6);
  final Color lightGrey = const Color(0xFFEEEEEE);

  @override
  void initState() {
    super.initState();
    _loadOfflineSongs();

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

  Future<Directory> _getMusicDirectory() async {
    Directory? dir;
    if (Platform.isAndroid) {
      dir = Directory('/storage/emulated/0/Download/IstamaMusic');
    } else {
      dir = await getApplicationDocumentsDirectory();
    }
    if (!await dir.exists()) {
      dir = await dir.create(recursive: true);
    }
    return dir;
  }

  Future<void> _loadOfflineSongs() async {
    final dir = await _getMusicDirectory();
    if (await dir.exists()) {
      final List<FileSystemEntity> files = dir.listSync();
      setState(() {
        _offlineSongs = files.where((f) => f.path.endsWith('.mp3')).toList();
      });
    }
  }

  Future<void> _downloadAudio() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) {
      setState(() {
        _statusMessage = 'يرجى إدخال الرابط أولاً!';
      });
      return;
    }

    if (Platform.isAndroid) {
      await Permission.storage.request();
      await Permission.manageExternalStorage.request();
    }

    setState(() {
      _isDownloading = true;
      _downloadProgress = 0.0;
      _statusMessage = 'جاري الاتصال واستخراج المقارنة...';
    });

    final yt = YoutubeExplode();

    try {
      final video = await yt.videos.get(url);
      final manifest = await yt.videos.streamsClient.getManifest(video.id);
      final audioStreamInfo = manifest.audioOnly.withHighestBitrate();

      setState(() {
        _currentSongName = video.title;
        _currentThumbnailUrl = video.thumbnails.highResUrl;
        _statusMessage = 'جاري تنزيل الملف الصوتي...';
      });

      final stream = yt.videos.streamsClient.get(audioStreamInfo);
      final dir = await _getMusicDirectory();
      String cleanTitle = video.title.replaceAll(RegExp(r'[^\w\s\u0600-\u06FF]'), '_');
      File file = File('${dir.path}/$cleanTitle.mp3');

      var output = file.openWrite();
      var totalBytes = audioStreamInfo.size.totalBytes;
      var receivedBytes = 0;

      await for (var data in stream) {
        receivedBytes += data.length;
        output.add(data);
        if (mounted) {
          setState(() {
            _downloadProgress = receivedBytes / totalBytes;
          });
        }
      }

      await output.flush();
      await output.close();

      setState(() {
        _statusMessage = 'تم التحميل واكتملت الإضافة!';
        _isDownloading = false;
        _isInputExpanded = false; // إغلاق البطاقة المطوية بعد النجاح
        _urlController.clear();
      });

      await _loadOfflineSongs();
      _playSong(file.path, video.title, thumbnailUrl: video.thumbnails.highResUrl);
    } catch (e) {
      setState(() {
        _statusMessage = 'فشل التحميل، تحقق من الرابط أو الشبكة!';
        _isDownloading = false;
      });
    } finally {
      yt.close();
    }
  }

  Future<void> _playSong(String path, String songName, {String? thumbnailUrl}) async {
    _currentPlayingPath = path;
    _currentSongName = songName;
    if (thumbnailUrl != null) {
      _currentThumbnailUrl = thumbnailUrl;
    }
    await _audioPlayer.stop();
    await _audioPlayer.play(DeviceFileSource(path));
    setState(() {});
  }

  Future<void> _togglePlayPause() async {
    if (_isPlaying) {
      await _audioPlayer.pause();
    } else if (_currentPlayingPath != null) {
      await _audioPlayer.resume();
    } else if (_offlineSongs.isNotEmpty) {
      var firstFile = _offlineSongs.first;
      _playSong(firstFile.path, firstFile.path.split('/').last.replaceAll('.mp3', ''));
    }
  }

  Future<void> _seek10Seconds(bool forward) async {
    int currentMs = _position.inMilliseconds;
    int targetMs = forward ? currentMs + 10000 : currentMs - 10000;
    if (targetMs < 0) targetMs = 0;
    if (targetMs > _duration.inMilliseconds) targetMs = _duration.inMilliseconds;
    await _audioPlayer.seek(Duration(milliseconds: targetMs));
  }

  void _nextSong() {
    if (_offlineSongs.isEmpty || _currentPlayingPath == null) return;
    int currentIndex = _offlineSongs.indexWhere((f) => f.path == _currentPlayingPath);
    if (currentIndex != -1 && currentIndex < _offlineSongs.length - 1) {
      var nextFile = _offlineSongs[currentIndex + 1];
      _playSong(nextFile.path, nextFile.path.split('/').last.replaceAll('.mp3', ''));
    }
  }

  void _previousSong() {
    if (_offlineSongs.isEmpty || _currentPlayingPath == null) return;
    int currentIndex = _offlineSongs.indexWhere((f) => f.path == _currentPlayingPath);
    if (currentIndex > 0) {
      var prevFile = _offlineSongs[currentIndex - 1];
      _playSong(prevFile.path, prevFile.path.split('/').last.replaceAll('.mp3', ''));
    }
  }

  Future<void> _deleteSong(String path) async {
    File file = File(path);
    if (await file.exists()) {
      if (_currentPlayingPath == path) {
        await _audioPlayer.stop();
        _currentPlayingPath = null;
        _currentSongName = 'اختر أغنية من المكتبة';
        _currentThumbnailUrl = null;
      }
      await file.delete();
      await _loadOfflineSongs();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // خلفية iOS أنيقة بالألوان الزيتية مع البيج
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
                  // العنوان بخط كوفي عربي مميز
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
                          shadows: [
                            Shadow(blurRadius: 10, color: primaryGreen.withOpacity(0.5), offset: const Offset(0, 4))
                          ],
                        ),
                      ),
                    ),
                  ),

                  // البطاقة المطوية الرائعة بتأثير الزجاج (iOS Folding Glass Card)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 350),
                    curve: Curves.easeInOutCubic,
                    margin: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: Colors.white.withOpacity(0.15), width: 1.5),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.2),
                          blurRadius: 20,
                          spreadRadius: 1,
                        )
                      ],
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
                                          _isDownloading ? 'جاري الاستخراج...' : 'تحميل واستخراج المقارنة',
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

                  // مشغل الصوتيات الزجاجي الاحترافي (Glassmorphic Audio Player)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(28),
                      border: Border.all(color: Colors.white.withOpacity(0.2), width: 1.5),
                      boxShadow: [
                        BoxShadow(color: Colors.black.withOpacity(0.25), blurRadius: 25, spreadRadius: 2)
                      ],
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
                                  child: _currentThumbnailUrl != null
                                      ? Image.network(_currentThumbnailUrl!, width: 65, height: 65, fit: BoxFit.cover)
                                      : Container(
                                          width: 65,
                                          height: 65,
                                          color: primaryGreen.withOpacity(0.2),
                                          child: Icon(Icons.music_note_rounded, color: primaryGreen, size: 36),
                                        ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        _currentSongName,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: bgCream),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        _isPlaying ? 'شغال حالياً 🎵' : 'متوقف مؤقتاً',
                                        style: TextStyle(fontSize: 12, color: bgCream.withOpacity(0.5)),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            SliderTheme(
                              data: SliderThemeData(
                                trackHeight: 4,
                                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                                activeTrackColor: primaryGreen,
                                inactiveTrackColor: Colors.white24,
                                thumbColor: bgCream,
                              ),
                              child: Slider(
                                min: 0,
                                max: _duration.inSeconds.toDouble() > 0 ? _duration.inSeconds.toDouble() : 1.0,
                                value: _position.inSeconds.toDouble().clamp(0.0, _duration.inSeconds.toDouble()),
                                onChanged: (val) async {
                                  await _audioPlayer.seek(Duration(seconds: val.toInt()));
                                },
                              ),
                            ),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                              children: [
                                IconButton(icon: Icon(Icons.skip_previous_rounded, color: bgCream, size: 28), onPressed: _previousSong),
                                IconButton(icon: Icon(Icons.replay_10_rounded, color: bgCream, size: 26), onPressed: () => _seek10Seconds(false)),
                                
