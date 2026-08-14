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
  TkStats? _stats;

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
    await _engine!.loadHistory();
    _refreshStats();
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

  void _refreshStats() {
    if (!mounted) return;
    setState(() => _stats = _engine!.stats);
  }

  void _pickSubject(String subject) {
    setState(() {
      _subject = subject;
      _engineEpoch++; // 새 주제로 채팅 초기화
    });
    _saveSettings();
  }

  Future<void> _addCustomSubject() async {
    final result = await showDialog<String>(
      context: context,
      builder: (context) => const _SubjectDialog(),
    );
    if (result == null || result.isEmpty || !mounted) return;
    _pickSubject(result);
  }

  Future<void> _resetAll() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('학습 기록 초기화'),
        content: const Text('대화 기록과 통계를 초기화할까요?\n(최고 streak 기록은 유지됩니다)'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('초기화'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _engine!.reset();
    if (!mounted) return;
    setState(() {
      _engineEpoch++;
      _rebuildEngine();
    });
    await _engine!.loadHistory();
    _refreshStats();
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
    await _engine!.loadHistory();
    _refreshStats();
    _saveSettings();
  }

  @override
  Widget build(BuildContext context) {
    final stats = _stats;
    // 기본 주제 + 사용자가 직접 추가한 주제 칩
    final subjectChips = [
      ..._subjects,
      if (!_subjects.contains(_subject)) _subject,
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('🎯 TikiTaka'),
        actions: [
          IconButton(
            icon: const Icon(Icons.bar_chart),
            tooltip: '학습 통계',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => StatsPage(engine: _engine!),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.delete_sweep),
            tooltip: '학습 기록 초기화',
            onPressed: _resetAll,
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Ollama 연결 설정',
            onPressed: _openSettings,
          ),
        ],
      ),
      body: Column(
        children: [
          // 학습 통계 (연속 streak 등)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            color: Colors.orange.shade50,
            child: Row(
              children: [
                const Icon(Icons.local_fire_department,
                    size: 16, color: Colors.deepOrange),
                Text(' ${stats?.streakDays ?? 0}일 연속',
                    style: const TextStyle(fontSize: 12)),
                const SizedBox(width: 14),
                const Icon(Icons.emoji_events,
                    size: 16, color: Colors.amber),
                Text(' 최고 ${stats?.bestStreak ?? 0}일',
                    style: const TextStyle(fontSize: 12)),
                const SizedBox(width: 14),
                const Icon(Icons.forum, size: 16, color: Colors.teal),
                Text(' 질문 ${stats?.totalQuestions ?? 0}개',
                    style: const TextStyle(fontSize: 12)),
              ],
            ),
          ),
          // 주제 선택
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                for (final s in subjectChips)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: ChoiceChip(
                      label: Text(s),
                      selected: _subject == s,
                      onSelected: (_) => _pickSubject(s),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: ActionChip(
                    avatar: const Icon(Icons.add, size: 16),
                    label: const Text('직접 입력'),
                    onPressed: _addCustomSubject,
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
              onActivity: _refreshStats,
            ),
          ),
        ],
      ),
    );
  }
}

/// 새 학습 주제 입력 다이얼로그 — controller 수명을 위젯이 소유해
/// 닫힘 애니메이션 중 use-after-dispose를 방지한다.
class _SubjectDialog extends StatefulWidget {
  const _SubjectDialog();

  @override
  State<_SubjectDialog> createState() => _SubjectDialogState();
}

class _SubjectDialogState extends State<_SubjectDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('새 학습 주제'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: const InputDecoration(
          hintText: '예: 물리, 한국사, 프로그래밍',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('취소'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _controller.text.trim()),
          child: const Text('추가'),
        ),
      ],
    );
  }
}

/// 과목별 학습 통계 화면
class StatsPage extends StatefulWidget {
  final TikiTakaLfm engine;

  const StatsPage({super.key, required this.engine});

  @override
  State<StatsPage> createState() => _StatsPageState();
}

class _StatsPageState extends State<StatsPage> {
  Map<String, TkStats>? _all;
  int? _totalQuestions;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final all = await widget.engine.allStats();
    final total =
        all.values.fold<int>(0, (sum, s) => sum + s.totalQuestions);
    if (!mounted) return;
    setState(() {
      _all = all;
      _totalQuestions = total;
    });
  }

  static String _label(String subject) => subject.isEmpty ? '기본' : subject;

  @override
  Widget build(BuildContext context) {
    final all = _all;
    return Scaffold(
      appBar: AppBar(title: const Text('학습 통계')),
      body: all == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.insights),
                    title: Text('전체 질문 ${_totalQuestions ?? 0}개'),
                    subtitle: Text('${all.length}개 과목'),
                  ),
                ),
                for (final e in (all.entries.toList()
                  ..sort((a, b) => _label(a.key).compareTo(_label(b.key)))))
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.auto_stories),
                      title: Text(_label(e.key)),
                      subtitle: Text(
                        '🔥 ${e.value.streakDays}일 연속 · '
                        '🏆 최고 ${e.value.bestStreak}일 · '
                        '💬 ${e.value.totalQuestions}개',
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}
