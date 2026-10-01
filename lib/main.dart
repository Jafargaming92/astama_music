import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:glassmorphism/glassmorphism.dart';

void main() {
  runApp(const AstamaApp());
}

class AstamaApp extends StatelessWidget {
  const AstamaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Astama Music Player',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0B0B0F),
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
  double _downloadProgress = 0.0;
  String _statusMessage = 'ألصق رابط يوتيوب للتحميل والاستماع';

  List<FileSystemEntity> _offlineSongs = [];
  String? _currentPlayingPath;
  String _currentSongName = 'لا توجد أغنية قيد التشغيل';
  String? _currentThumbnailUrl;
  bool _isPlaying = false;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;

  @override
  void initState() {
    super.initState();
    _loadOfflineSongs();

    _audioPlayer.onPlayerStateChanged.listen((state) {
      setState(() {
        _isPlaying = state == PlayerState.playing;
      });
    });

    _audioPlayer.onDurationChanged.listen((newDuration) {
      setState(() {
        _duration = newDuration;
      });
    });

    _audioPlayer.onPositionChanged.listen((newPosition) {
      setState(() {
        _position = newPosition;
      });
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
    Directory? dir = Directory('/storage/emulated/0/Download/AstamaMusic');
    if (!await dir.exists()) {
      dir = await dir.create(recursive: true);
    }
    return dir;
  }

  Future<void> _loadOfflineSongs() async {
    final dir = await _getMusicDirectory();
    final List<FileSystemEntity> files = dir.listSync();
    setState(() {
      _offlineSongs = files.where((f) => f.path.endsWith('.mp3')).toList();
    });
  }

  Future<void> _downloadAudio() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) {
      setState(() {
        _statusMessage = 'يرجى وضع رابط يوتيوب أولاً!';
      });
      return;
    }

    await Permission.storage.request();
    await Permission.manageExternalStorage.request();

    setState(() {
      _isDownloading = true;
      _downloadProgress = 0.0;
      _statusMessage = 'جاري تحليل الرابط واستخراج الصورة والمعلومات...';
    });

    final yt = YoutubeExplode();

    try {
      var video = await yt.videos.get(url);
      var manifest = await yt.videos.streamsClient.getManifest(video.id);
      var audioStreamInfo = manifest.audioOnly.withHighestBitrate();
      var stream = yt.videos.streamsClient.get(audioStreamInfo);

      final dir = await _getMusicDirectory();
      String cleanTitle = video.title.replaceAll(RegExp(r'[^\w\s\u0600-\u06FF]'), '_');
      File file = File('${dir.path}/$cleanTitle.mp3');

      var output = file.openWrite();
      var totalBytes = audioStreamInfo.size.totalBytes;
      var receivedBytes = 0;

      setState(() {
        _currentThumbnailUrl = video.thumbnails.mediumResUrl;
        _statusMessage = 'جاري تحميل: ${video.title}';
      });

      await for (var data in stream) {
        receivedBytes += data.length;
        output.add(data);
        setState(() {
          _downloadProgress = receivedBytes / totalBytes;
        });
      }

      await output.flush();
      await output.close();

      setState(() {
        _statusMessage = 'تم التحميل بنجاح إلى المكتبة!';
        _isDownloading = false;
        _urlController.clear();
      });

      await _loadOfflineSongs();
      _playSong(file.path, video.title);
    } catch (e) {
      setState(() {
        _statusMessage = 'فشل التحميل: تأكد من صحة الرابط أو الاتصال';
        _isDownloading = false;
      });
    } finally {
      yt.close();
    }
  }

  Future<void> _playSong(String path, String songName) async {
    _currentPlayingPath = path;
    _currentSongName = songName;
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
      _playSong(_offlineSongs.first.path, _offlineSongs.first.path.split('/').last.replaceAll('.mp3', ''));
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
        _currentSongName = 'لا توجد أغنية قيد التشغيل';
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
          // Background Gradient
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF1F1C2C), Color(0xFF928DAB)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  const Text(
                    'ASTAMA MUSIC 🎵',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                  const SizedBox(height: 15),

                  // Downloader Glass Box
                  GlassmorphicContainer(
                    width: double.infinity,
                    height: 170,
                    borderRadius: 20,
                    blur: 15,
                    alignment: Alignment.center,
                    border: 2,
                    linearGradient: LinearGradient(
                      colors: [Colors.white.withOpacity(0.15), Colors.white.withOpacity(0.05)],
                    ),
                    borderGradient: LinearGradient(
                      colors: [Colors.white.withOpacity(0.5), Colors.white.withOpacity(0.1)],
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Column(
                        children: [
                          TextField(
                            controller: _urlController,
                            style: const TextStyle(color: Colors.white),
                            decoration: InputDecoration(
                              hintText: 'ضع رابط يوتيوب هنا...',
                              hintStyle: const TextStyle(color: Colors.white54),
                              prefixIcon: const Icon(Icons.link, color: Colors.purpleAccent),
                              filled: true,
                              fillColor: Colors.black.withOpacity(0.3),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                          const SizedBox(height: 10),
                          ElevatedButton.icon(
                            onPressed: _isDownloading ? null : _downloadAudio,
                            icon: const Icon(Icons.download),
                            label: Text(_isDownloading ? 'جاري التحميل...' : 'تحميل واستخراج الصوت'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.purpleAccent,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                          if (_isDownloading)
                            Padding(
                              padding: const EdgeInsets.only(top: 8.0),
                              child: LinearProgressIndicator(value: _downloadProgress, color: Colors.purpleAccent),
                            ),
                          Text(_statusMessage, style: const TextStyle(fontSize: 11, color: Colors.white70)),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 15),

                  // Player Player Glass Box
                  GlassmorphicContainer(
                    width: double.infinity,
                    height: 220,
                    borderRadius: 20,
                    blur: 15,
                    alignment: Alignment.center,
                    border: 2,
                    linearGradient: LinearGradient(
                      colors: [Colors.white.withOpacity(0.2), Colors.white.withOpacity(0.05)],
                    ),
                    borderGradient: LinearGradient(
                      colors: [Colors.purpleAccent.withOpacity(0.5), Colors.white.withOpacity(0.1)],
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Row(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                child: _currentThumbnailUrl != null
                                    ? Image.network(_currentThumbnailUrl!, width: 60, height: 60, fit: BoxFit.cover)
                                    : Container(
                                        width: 60,
                                        height: 60,
                                        color: Colors.black38,
                                        child: const Icon(Icons.music_note, color: Colors.purpleAccent, size: 35),
                                      ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  _currentSongName,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
                                ),
                              ),
                            ],
                          ),
                          Slider(
                            min: 0,
                            max: _duration.inSeconds.toDouble() > 0 ? _duration.inSeconds.toDouble() : 1.0,
                            value: _position.inSeconds.toDouble().clamp(0.0, _duration.inSeconds.toDouble()),
                            activeColor: Colors.purpleAccent,
                            onChanged: (val) async {
                              await _audioPlayer.seek(Duration(seconds: val.toInt()));
                            },
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              IconButton(icon: const Icon(Icons.skip_previous, color: Colors.white), onPressed: _previousSong),
                              IconButton(icon: const Icon(Icons.replay_10, color: Colors.white), onPressed: () => _seek10Seconds(false)),
                              IconButton(
                                iconSize: 40,
                                icon: Icon(_isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled, color: Colors.purpleAccent),
                                onPressed: _togglePlayPause,
                              ),
                              IconButton(icon: const Icon(Icons.forward_10, color: Colors.white), onPressed: () => _seek10Seconds(true)),
                              IconButton(icon: const Icon(Icons.skip_next, color: Colors.white), onPressed: _nextSong),
                            ],
                          )
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 15),
                  const Align(
                    alignment: Alignment.centerRight,
                    child: Text('المكتبة المحلية:', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  ),

                  // Offline Library List
                  Expanded(
                    child: ListView.builder(
                      itemCount: _offlineSongs.length,
                      itemBuilder: (context, index) {
                        final file = _offlineSongs[index];
                        final songName = file.path.split('/').last.replaceAll('.mp3', '');
                        final isCurrent = file.path == _currentPlayingPath;

                        return Container(
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          decoration: BoxDecoration(
                            color: isCurrent ? Colors.purpleAccent.withOpacity(0.3) : Colors.black26,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: ListTile(
                            leading: Icon(Icons.audiotrack, color: isCurrent ? Colors.purpleAccent : Colors.white70),
                            title: Text(songName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white)),
                            onTap: () => _playSong(file.path, songName),
                            trailing: IconButton(
                              icon: const Icon(Icons.delete, color: Colors.redAccent),
                              onPressed: () => _deleteSong(file.path),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
