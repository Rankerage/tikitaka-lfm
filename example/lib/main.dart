import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tikitaka_lfm/tikitaka_chat.dart';
import 'package:tikitaka_lfm/tikitaka_lfm.dart';

/// TikiTaka LFM2.5 예제 앱 — 온디바이스 AI 학습 파트너
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const TikiTakaApp());
}

class TikiTakaApp extends StatelessWidget {
  const TikiTakaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TikiTaka',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  static const _kHost = 'tikitaka.host';
  static const _kPort = 'tikitaka.port';
  static const _kModel = 'tikitaka.model';
  static const _kSubject = 'tikitaka.subject';

  static const _subjects = ['수학', '영어', '과학', '역사', '코딩'];

  String _host = '127.0.0.1';
  int _port = 11434;
  String _model = 'lfm2.5-thinking:1.2b';
  String _subject = '수학';

  /// 설정 변경 시 채팅 위젯을 새로 만들기 위한 키
  int _engineEpoch = 0;

  TikiTakaLfm? _engine;

  @override
  void initState() {
    super.initState();
    _rebuildEngine();
    _loadSettings();
  }

  @override
  void dispose() {
    _engine?.dispose();
    super.dispose();
  }

  void _rebuildEngine() {
    _engine?.dispose();
    _engine = TikiTakaLfm(config: _config);
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _host = prefs.getString(_kHost) ?? _host;
      _port = prefs.getInt(_kPort) ?? _port;
      _model = prefs.getString(_kModel) ?? _model;
      _subject = prefs.getString(_kSubject) ?? _subject;
    });
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kHost, _host);
    await prefs.setInt(_kPort, _port);
    await prefs.setString(_kModel, _model);
    await prefs.setString(_kSubject, _subject);
  }

  LfmConfig get _config =>
      LfmConfig(host: _host, port: _port, model: _model);

  void _pickSubject(String subject) {
    setState(() {
      _subject = subject;
      _engineEpoch++; // 새 주제로 채팅 초기화
    });
    _saveSettings();
  }

  void _openSettings() async {
    final hostCtrl = TextEditingController(text: _host);
    final portCtrl = TextEditingController(text: '$_port');
    final modelCtrl = TextEditingController(text: _model);
    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: MediaQuery.of(context).viewInsets.bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Ollama 연결 설정',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            TextField(
              controller: hostCtrl,
              decoration: const InputDecoration(
                labelText: '호스트',
                hintText: '127.0.0.1 또는 10.0.2.2 (에뮬레이터)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: portCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: '포트',
                hintText: '11434',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: modelCtrl,
              decoration: const InputDecoration(
                labelText: '모델',
                hintText: 'lfm2.5-thinking:1.2b',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('저장'),
              ),
            ),
          ],
        ),
      ),
    );

    if (changed != true) {
      hostCtrl.dispose();
      portCtrl.dispose();
      modelCtrl.dispose();
      return;
    }

    final newHost = hostCtrl.text.trim();
    final newPort = int.tryParse(portCtrl.text.trim());
    final newModel = modelCtrl.text.trim();
    hostCtrl.dispose();
    portCtrl.dispose();
    modelCtrl.dispose();

    if (newPort == null || newPort <= 0) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('포트는 양의 정수여야 합니다.')),
      );
      return;
    }
    setState(() {
      _host = newHost.isEmpty ? '127.0.0.1' : newHost;
      _port = newPort;
      _model = newModel.isEmpty ? 'lfm2.5-thinking:1.2b' : newModel;
      _engineEpoch++;
      _rebuildEngine();
    });
    _saveSettings();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('🎯 TikiTaka'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Ollama 연결 설정',
            onPressed: _openSettings,
          ),
        ],
      ),
      body: Column(
        children: [
          // 주제 선택
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                for (final s in _subjects)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: ChoiceChip(
                      label: Text(s),
                      selected: _subject == s,
                      onSelected: (_) => _pickSubject(s),
                    ),
                  ),
              ],
            ),
          ),
          // 채팅 (설정/주제 변경 시 새 엔진으로 재생성)
          Expanded(
            child: TikiTakaChat(
              key: ValueKey('chat-$_engineEpoch-$_subject'),
              engine: _engine!,
              subject: _subject,
            ),
          ),
        ],
      ),
    );
  }
}
