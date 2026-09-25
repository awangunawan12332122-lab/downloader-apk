import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:share_plus/share_plus.dart';

void main() => runApp(const YtDownloaderApp());

class YtDownloaderApp extends StatelessWidget {
  const YtDownloaderApp({super.key});
  
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'YT Downloader Pro',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.red,
            brightness: Brightness.dark,
          ),
          useMaterial3: true,
          scaffoldBackgroundColor: const Color(0xFF0F0F0F),
          appBarTheme: const AppBarTheme(
            backgroundColor: Colors.transparent,
            elevation: 0,
          ),
        ),
        home: const HomePage(),
      );
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _urlCtrl = TextEditingController();
  final _yt = YoutubeExplode();
  Video? _video;
  StreamManifest? _manifest;
  bool _loading = false;
  String _error = '';
  double? _progress;
  String _status = '';
  String _savedPath = '';
  String _downloadSpeed = '';
  final List<_DownloadItem> _recentDownloads = [];

  @override
  void initState() {
    super.initState();
    _checkClipboard();
  }

  @override
  void dispose() {
    _yt.close();
    _urlCtrl.dispose();
    super.dispose();
  }

  Future<void> _checkClipboard() async {
    try {
      final data = await Clipboard.getData('text/plain');
      final text = data?.text ?? '';
      if (text.contains('youtube.com') || text.contains('youtu.be')) {
        setState(() => _urlCtrl.text = text);
      }
    } catch (_) {}
  }

  Future<void> _fetch() async {
    final url = _urlCtrl.text.trim();
    if (url.isEmpty) {
      setState(() => _error = 'URL tidak boleh kosong');
      return;
    }
    if (!url.contains('youtube.com') && !url.contains('youtu.be')) {
      setState(() => _error = 'URL tidak valid');
      return;
    }
    
    FocusScope.of(context).unfocus();
    
    setState(() {
      _loading = true;
      _error = '';
      _video = null;
      _manifest = null;
      _savedPath = '';
      _progress = null;
    });
    
    try {
      final video = await _yt.videos.get(url);
      final manifest = await _yt.videos.streamsClient.getManifest(video.id);
      setState(() {
        _video = video;
        _manifest = manifest;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Gagal ambil info: ${e.toString().split('\n').first}';
        _loading = false;
      });
    }
  }

  // PERBAIKAN DI SINI: Menggunakan .name bukan .label
  String _qualityLabel(VideoQuality q) {
    final h = q.name.toLowerCase();
    if (h.contains('2160') || h.contains('4k')) return '4K';
    if (h.contains('1440')) return '1440p';
    if (h.contains('1080')) return 'FHD';
    if (h.contains('720')) return 'HD';
    if (h.contains('480')) return '480p';
    return q.name.toUpperCase();
  }

  // PERBAIKAN DI SINI: Menggunakan .name bukan .label
  Color _qualityColor(VideoQuality q) {
    final h = q.name.toLowerCase();
    if (h.contains('2160') || h.contains('4k')) return Colors.amber;
    if (h.contains('1440') || h.contains('1080')) return Colors.green;
    if (h.contains('720')) return Colors.blue;
    return Colors.grey;
  }

  Future<void> _download(StreamInfo info, String label) async {
    if (_video == null) return;
    try {
      Directory? dir;
      if (Platform.isAndroid) {
        dir = Directory('/storage/emulated/0/Download');
        if (!await dir.exists()) dir = await getExternalStorageDirectory();
      } else {
        dir = await getApplicationDocumentsDirectory();
      }
      
      if (dir == null) throw Exception('Storage tidak tersedia');
      
      final safe = _video!.title
          .replaceAll(RegExp(r'[^\w\d\-\s]'), '')
          .replaceAll(RegExp(r'\s+'), '_')
          .substring(0, (_video!.title.length > 60 ? 60 : _video!.title.length));
          
      final file = File('${dir.path}/${safe}_$label.${info.container.name}');
      final sink = file.openWrite();
      final stream = _yt.videos.streamsClient.get(info);
      final total = info.size.totalBytes;
      int received = 0;
      final stopwatch = Stopwatch()..start();
      
      setState(() {
        _progress = 0;
        _status = 'Mengunduh $label...';
        _savedPath = '';
        _downloadSpeed = '';
      });
      
      await for (final chunk in stream) {
        sink.add(chunk);
        received += chunk.length;
        final elapsed = stopwatch.elapsedMilliseconds;
        
        if (total > 0) {
          setState(() => _progress = received / total);
        }
        if (elapsed > 0 && elapsed % 500 == 0) {
          final speed = (received / (elapsed / 1000)) / 1024;
          setState(() => _downloadSpeed = speed > 1024
              ? '${(speed / 1024).toStringAsFixed(1)} MB/s'
              : '${speed.toStringAsFixed(0)} KB/s');
        }
      }
      
      await sink.close();
      stopwatch.stop();
      
      setState(() {
        _progress = 1;
        _status = 'Selesai ✔';
        _savedPath = file.path;
        _downloadSpeed = '';
        
        _recentDownloads.insert(0, _DownloadItem(
          title: _video!.title,
          label: label,
          path: file.path,
          size: file.lengthSync(),
        ));
      });
      
    } catch (e) {
      setState(() {
        _progress = null;
        _status = 'Gagal unduh: ${e.toString().split('\n').first}';
        _downloadSpeed = '';
      });
    }
  }

  Widget _buildQualityChip(StreamInfo info, String label, IconData icon) {
    Color color = Colors.purple;
    String qLabel = label;

    if (info is VideoStreamInfo) {
      qLabel = _qualityLabel(info.videoQuality);
      color = _qualityColor(info.videoQuality);
    } else if (info is AudioOnlyStreamInfo) {
      color = Colors.orangeAccent;
    }

    return Card(
      elevation: 0,
      color: Colors.white.withOpacity(0.05),
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: () => _download(info, qLabel),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(qLabel, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 4),
                    Text(
                      '${(info.size.totalBytes / 1048576).toStringAsFixed(1)} MB · ${info.container.name.toUpperCase()}',
                      style: TextStyle(fontSize: 12, color: Colors.grey[400]),
                    ),
                  ],
                ),
              ),
              Icon(Icons.download_rounded, color: color),
            ],
          ),
        ),
      ),
    ).animate().fadeIn(duration: 400.ms).slideX(begin: 0.1);
  }

  @override
  Widget build(BuildContext context) {
    final muxed = _manifest?.muxed.sortByVideoQuality().toList() ?? [];
    final audio = _manifest?.audioOnly.sortByBitrate().toList() ?? [];
    
    return Scaffold(
      body: Stack(
        children: [
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF1F1F1F), Color(0xFF0F0F0F)],
              ),
            ),
          ),
          SafeArea(
            child: ListView(
              padding: const EdgeInsets.all(16),
              physics: const BouncingScrollPhysics(),
              children: [
                Row(
                  children: [
                    const Icon(Icons.youtube_searched_for, color: Colors.red, size: 32),
                    const SizedBox(width: 8),
                    const Text('YT Downloader',
                        style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.history_rounded),
                      onPressed: _showRecentDownloads,
                    ),
                  ],
                ).animate().fadeIn(duration: 600.ms),
                const SizedBox(height: 8),
                const Text('Unduh video/audio YouTube secara instan.',
                    style: TextStyle(fontSize: 12, color: Colors.grey)),
                const SizedBox(height: 16),
                Card(
                  elevation: 0,
                  color: Colors.white.withOpacity(0.05),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        TextField(
                          controller: _urlCtrl,
                          keyboardType: TextInputType.url,
                          decoration: InputDecoration(
                            labelText: 'URL YouTube',
                            hintText: 'https://youtube.com/watch?v=...',
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            suffixIcon: IconButton(
                              icon: const Icon(Icons.content_paste),
                              onPressed: _checkClipboard,
                            ),
                          ),
                          onSubmitted: (_) => _fetch(),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: _loading ? null : _fetch,
                            icon: _loading
                                ? const SizedBox(
                                    width: 18, height: 18,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                : const Icon(Icons.search),
                            label: Text(_loading ? 'Memuat...' : 'Ambil Info'),
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.all(16),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              backgroundColor: Colors.redAccent,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ).animate().fadeIn(duration: 800.ms).slideY(begin: 0.1),
                if (_error.isNotEmpty)
                  Card(
                    elevation: 0,
                    color: Colors.red.withOpacity(0.1),
                    margin: const EdgeInsets.only(top: 16),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline, color: Colors.redAccent),
                          const SizedBox(width: 8),
                          Expanded(child: Text(_error, style: const TextStyle(color: Colors.redAccent))),
                        ],
                      ),
                    ),
                  ).animate().shake().fadeIn(),
                if (_video != null) ...[
                  const SizedBox(height: 16),
                  Card(
                    elevation: 0,
                    color: Colors.white.withOpacity(0.05),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: CachedNetworkImage(
                              imageUrl: _video!.thumbnails.highResUrl,
                              fit: BoxFit.cover,
                              width: double.infinity,
                              height: 200,
                              placeholder: (context, url) => Container(
                                height: 200,
                                color: Colors.grey[900],
                                child: const Center(child: CircularProgressIndicator()),
                              ),
                              errorWidget: (context, url, error) => Container(
                                height: 200,
                                color: Colors.grey[900],
                                child: const Icon(Icons.broken_image, size: 50, color: Colors.grey),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(_video!.title,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                          const SizedBox(height: 4),
                          Text('${_video!.author} · ${_video!.duration ?? Duration.zero}',
                              style: TextStyle(color: Colors.grey[400])),
                        ],
                      ),
                    ),
                  ).animate().fadeIn(duration: 800.ms).slideY(begin: 0.2),
                  const SizedBox(height: 24),
                  
                  const Text('VIDEO (Gambar + Suara)',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white70)),
                  const SizedBox(height: 12),
                  if (muxed.isEmpty)
                    const Text('  (Tidak ada stream video gabungan tersedia)',
                        style: TextStyle(color: Colors.grey)),
                  ...muxed.map((s) => _buildQualityChip(s, 'MP4', Icons.video_library_rounded)),
                  
                  const SizedBox(height: 24),
                  
                  const Text('AUDIO SAJA (Musik)',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white70)),
                  const SizedBox(height: 12),
                  ...audio.map((s) => _buildQualityChip(
                        s, 
                        '${s.bitrate.kiloBitsPerSecond.round()} kbps', 
                        Icons.audiotrack_rounded
                      )),
                ],
                if (_progress != null || _status.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Card(
                    elevation: 0,
                    color: Colors.white.withOpacity(0.05),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (_progress != null) ...[
                            Stack(
                              clipBehavior: Clip.none,
                              children: [
                                LinearProgressIndicator(
                                  value: _progress,
                                  minHeight: 8,
                                  backgroundColor: Colors.white10,
                                  color: Colors.greenAccent,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                if (_downloadSpeed.isNotEmpty)
                                  Positioned(
                                    right: 0,
                                    top: -24,
                                    child: Text(_downloadSpeed,
                                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.greenAccent)),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text('${(_progress! * 100).toStringAsFixed(1)}%',
                                style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.greenAccent)),
                          ],
                          const SizedBox(height: 8),
                          Text(_status),
                          if (_savedPath.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.black26,
                                borderRadius: BorderRadius.circular(8)
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.check_circle, size: 20, color: Colors.green),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(_savedPath,
                                        style: const TextStyle(fontSize: 11, color: Colors.white70),
                                        overflow: TextOverflow.ellipsis),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.share, size: 20, color: Colors.blueAccent),
                                    onPressed: () => Share.shareXFiles([XFile(_savedPath)]),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ).animate().fadeIn().slideY(begin: 0.1),
                ],
                const SizedBox(height: 40),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showRecentDownloads() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.6,
        decoration: const BoxDecoration(
          color: Color(0xFF1F1F1F),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[700],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Download Terbaru',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            ),
            Expanded(
              child: _recentDownloads.isEmpty
                  ? const Center(child: Text('Belum ada file yang diunduh', style: TextStyle(color: Colors.grey)))
                  : ListView.builder(
                      physics: const BouncingScrollPhysics(),
                      itemCount: _recentDownloads.length,
                      itemBuilder: (context, i) {
                        final item = _recentDownloads[i];
                        return ListTile(
                          leading: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.green.withOpacity(0.2),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.download_done, color: Colors.green),
                          ),
                          title: Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text('${item.label} · ${(item.size / 1048576).toStringAsFixed(1)} MB',
                              style: const TextStyle(fontSize: 12)),
                          trailing: IconButton(
                            icon: const Icon(Icons.share_rounded, color: Colors.blueAccent),
                            onPressed: () => Share.shareXFiles([XFile(item.path)]),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DownloadItem {
  final String title;
  final String label;
  final String path;
  final int size;
  
  _DownloadItem({
    required this.title, 
    required this.label, 
    required this.path, 
    required this.size
  });
}