import 'dart0:io';
import 'package:flutter/material.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

void main() {
  runApp(const AstamaApp());
}

class AstamaApp extends StatelessWidget {
  const AstamaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Astama Music',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF121212),
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurple,
          brightness: Brightness.dark,
        ),
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
  bool _isDownloading = false;
  double _progress = 0.0;
  String _statusMessage = 'ألصق رابط يوتيوب للتحميل';

  Future<void> _downloadAudio() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) {
      setState(() {
        _statusMessage = 'يرجى أدخال رابط صالح أولاً!';
      });
      return;
    }

    var status = await Permission.storage.request();
    if (!status.isGranted) {
      await Permission.manageExternalStorage.request();
    }

    setState(() {
      _isDownloading = true;
      _progress = 0.0;
      _statusMessage = 'جاري استخراج معلومات المقطع...';
    });

    final yt = YoutubeExplode();

    try {
      var video = await yt.videos.get(url);
      var manifest = await yt.videos.streamsClient.getManifest(video.id);
      var audioStreamInfo = manifest.audioOnly.withHighestBitrate();
      var stream = yt.videos.streamsClient.get(audioStreamInfo);

      Directory? dir = Directory('/storage/emulated/0/Download');
      if (!await dir.exists()) {
        dir = await getExternalStorageDirectory();
      }

      String cleanTitle = video.title.replaceAll(RegExp(r'[^\w\s\u0600-\u06FF]'), '');
      File file = File('${dir!.path}/$cleanTitle.mp3');

      var output = file.openWrite();
      var len = audioStreamInfo.size.totalBytes;
      var count = 0;

      setState(() {
        _statusMessage = 'جاري تحميل الصوت: ${video.title}';
      });

      await for (var data in stream) {
        count += data.length;
        output.add(data);
        setState(() {
          _progress = count / len;
        });
      }

      await output.flush();
      await output.close();

      setState(() {
        _statusMessage = 'تم التحميل بنجاح! تم الحفظ في مجلد Download';
        _isDownloading = false;
        _progress = 1.0;
      });
    } catch (e) {
      setState(() {
        _statusMessage = 'حدث خطأ أثناء التحميل: الرابط غير صحيح أو انقطع الاتصال';
        _isDownloading = false;
      });
    } finally {
      yt.close();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Astama Music 🎵', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        backgroundColor: Colors.deepPurple.shade900,
        elevation: 4,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.music_note_rounded, size: 80, color: Colors.deepPurpleAccent),
            const SizedBox(height: 20),
            TextField(
              controller: _urlController,
              decoration: InputDecoration(
                hintText: 'ضع رابط يوتيوب هنا...',
                prefixIcon: const Icon(Icons.link),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(15)),
                filled: true,
                fillColor: const Color(0xFF1E1E1E),
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: _isDownloading ? null : _downloadAudio,
              icon: const Icon(Icons.download_rounded),
              label: Text(_isDownloading ? 'جاري التحميل...' : 'تحميل الصوت MP3'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 15),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                backgroundColor: Colors.deepPurpleAccent,
                textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 30),
            if (_isDownloading) ...[
              LinearProgressIndicator(value: _progress, color: Colors.deepPurpleAccent),
              const SizedBox(height: 10),
              Text('${(_progress * 100).toStringAsFixed(0)}%'),
              const SizedBox(height: 10),
            ],
            Text(
              _statusMessage,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _statusMessage.contains('نجاح') ? Colors.greenAccent : Colors.white70,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
