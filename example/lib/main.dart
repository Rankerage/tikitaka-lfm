import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tikitaka_lfm/tikitaka_chat.dart';
import 'package:tikitaka_lfm/tikitaka_lfm.dart';

/// 정기 학습 알림 (flutter_local_notifications 래퍼)
final FlutterLocalNotificationsPlugin _notifications =
    FlutterLocalNotificationsPlugin();
const int _reminderId = 1001;

/// 매일 반복 학습 알림을 예약한다 (실패 시 false).
Future<bool> scheduleDailyReminder(String message) async {
  if (kIsWeb) return false;
  try {
    const init = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    );
    await _notifications.initialize(settings: init);
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'tikitaka_reminder',
        '학습 알림',
        channelDescription: '정기 학습 시간 알림',
        importance: Importance.high,
        priority: Priority.high,
      ),
    );
    await _notifications.periodicallyShow(
      id: _reminderId,
      title: '🎯 TikiTaka',
      body: message,
      repeatInterval: RepeatInterval.daily,
      notificationDetails: details,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    );
    return true;
  } catch (_) {
    return false;
  }
}

Future<void> cancelDailyReminder() async {
  if (kIsWeb) return;
  try {
    await _notifications.cancel(id: _reminderId);
  } catch (_) {}
}

/// TikiTaka LFM2.5 예제 앱 — 온디바이스 AI 학습 파트너
const String kAppVersion = '1.2.0';

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
  static const _kReminder = 'tikitaka.reminder';

  static const _subjects = ['수학', '영어', '과학', '역사', '코딩'];

  String _host = '127.0.0.1';
  int _port = 11434;
  String _model = 'lfm2.5-thinking:1.2b';
  String _subject = '수학';
  bool _remindersOn = false;

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
      _remindersOn = prefs.getBool(_kReminder) ?? false;
    });
    if (_remindersOn) {
      // 같은 id로 다시 예약하면 기존 일정을 대체한다 (멱등)
      unawaited(scheduleDailyReminder('$_subject 공부할 시간이에요! 🔥'));
    }
    await _engine!.loadHistory();
    _refreshStats();
  }

  /// 학습 알림 켜기/끄기
  Future<void> _setReminders(bool on) async {
    var success = false;
    if (on) {
      success = await scheduleDailyReminder('$_subject 공부할 시간이에요! 🔥');
    } else {
      await cancelDailyReminder();
      success = true;
    }
    if (!mounted) return;
    if (!success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('알림을 설정할 수 없습니다 (플랫폼 미지원)')),
      );
      return;
    }
    setState(() => _remindersOn = on);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kReminder, on);
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
            const SizedBox(height: 8),
            StatefulBuilder(
              builder: (context, setSheetState) => SwitchListTile(
                title: const Text('학습 알림 (매일)'),
                subtitle: const Text('공부할 시간에 로컬 알림을 보냅니다'),
                contentPadding: EdgeInsets.zero,
                value: _remindersOn,
                onChanged: (v) async {
                  setSheetState(() {}); // 진행 표시용 즉시 리빌드
                  await _setReminders(v);
                  if (mounted) setSheetState(() {});
                },
              ),
            ),
            const SizedBox(height: 12),
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
            icon: const Icon(Icons.info_outline),
            tooltip: '앱 정보',
            onPressed: () => showAboutDialog(
              context: context,
              applicationName: 'TikiTaka',
              applicationVersion: kAppVersion,
              applicationIcon: const Icon(Icons.sports_soccer,
                  size: 48, color: Colors.teal),
              children: [
                const Text(
                  '온디바이스 AI 학습 파트너 (LFM2.5 + Ollama)\n'
                  '모든 대화가 기기 안에서 처리됩니다.',
                  style: TextStyle(fontSize: 13),
                ),
                const SizedBox(height: 8),
                Text(
                  '엔진: tikitaka_lfm v1.1.0\n'
                  '기본 모델: lfm2.5-thinking:1.2b',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                ),
              ],
            ),
          ),
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

/// 오답노트 복습 — 플래시카드 방식으로 틀린 문제를 순환하며 푼다
class MistakeReviewPage extends StatefulWidget {
  final TikiTakaLfm engine;

  const MistakeReviewPage({super.key, required this.engine});

  @override
  State<MistakeReviewPage> createState() => _MistakeReviewPageState();
}

class _MistakeReviewPageState extends State<MistakeReviewPage> {
  TkMistake? _current;
  bool _revealed = false;
  int _reviewed = 0;

  @override
  void initState() {
    super.initState();
    _next();
  }

  void _next() {
    final m = widget.engine.nextMistakeReview();
    setState(() {
      _current = m;
      _revealed = false;
      if (m != null) _reviewed++;
    });
  }

  /// 맞았어요 — 오답노트에서 제거하고 다음 문제
  void _gotIt() {
    final current = _current;
    if (current == null) return;
    widget.engine
        .removeMistake(widget.engine.mistakes.indexOf(current));
    _next();
  }

  @override
  Widget build(BuildContext context) {
    final current = _current;
    final remaining = widget.engine.mistakes.length;
    return Scaffold(
      appBar: AppBar(title: const Text('오답노트 복습')),
      body: current == null
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.bookmark_border,
                      size: 48, color: Colors.grey),
                  const SizedBox(height: 12),
                  const Text('오답노트가 비어 있습니다'),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('닫기'),
                  ),
                ],
              ),
            )
          : Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '남은 오답 $remaining개 · 복습한 문제 $_reviewed개',
                    style: Theme.of(context).textTheme.bodySmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  Card(
                    color: Colors.teal.shade50,
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        children: [
                          const Text('Q',
                              style: TextStyle(
                                  fontSize: 12, color: Colors.teal)),
                          const SizedBox(height: 8),
                          Text(current.question,
                              style: const TextStyle(fontSize: 18, height: 1.4)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (!_revealed)
                    FilledButton.icon(
                      icon: const Icon(Icons.visibility),
                      label: const Text('정답 보기'),
                      onPressed: () => setState(() => _revealed = true),
                    )
                  else ...[
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          children: [
                            const Text('A',
                                style: TextStyle(
                                    fontSize: 12, color: Colors.grey)),
                            const SizedBox(height: 8),
                            Text(current.answer,
                                style: const TextStyle(
                                    fontSize: 16, height: 1.4)),
                            if (current.note != null &&
                                current.note!.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Text('📝 ${current.note}',
                                  style: const TextStyle(
                                      fontSize: 13, color: Colors.grey)),
                            ],
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _next,
                            child: const Text('다음'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton.icon(
                            icon: const Icon(Icons.check),
                            label: const Text('맞았어요'),
                            onPressed: _gotIt,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
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
  List<TkMistake> _mistakes = const [];

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
      _mistakes = widget.engine.mistakes;
    });
  }

  void _deleteMistake(int index) {
    widget.engine.removeMistake(index);
    setState(() => _mistakes = widget.engine.mistakes);
  }

  /// 과목 데이터 삭제 (확인 후)
  Future<void> _confirmDeleteSubject(String subject) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('"${_label(subject)}" 데이터 삭제'),
        content: const Text('이 과목의 대화 기록·오답노트·통계를 모두 삭제할까요?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await widget.engine.deleteSubject(subject);
    if (!mounted) return;
    await _load();
  }

  /// 최근 대화를 AI로 요약해 대화상자로 보여준다.
  Future<void> _summarize() async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(const SnackBar(content: Text('요약 생성 중...')));
    try {
      final summary = await widget.engine.summarize(maxLines: 5);
      if (!mounted) return;
      messenger.hideCurrentSnackBar();
      if (summary.isEmpty) {
        messenger.showSnackBar(
          const SnackBar(content: Text('아직 대화 기록이 없습니다')),
        );
        return;
      }
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('오늘의 학습 요약'),
          content: SingleChildScrollView(
            child: SelectableText(summary),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('닫기'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(content: Text('⚠️ 요약 실패: ${e.toString().split('\n').first}')),
      );
    }
  }

  static String _label(String subject) => subject.isEmpty ? '기본' : subject;

  static String _dayLabel(String dateKey) {
    final d = DateTime.tryParse(dateKey);
    if (d == null) return dateKey;
    const weekdays = ['월', '화', '수', '목', '금', '토', '일'];
    return weekdays[d.weekday - 1];
  }

  @override
  Widget build(BuildContext context) {
    final all = _all;
    return Scaffold(
      appBar: AppBar(
        title: const Text('학습 통계'),
        actions: [
          IconButton(
            icon: const Icon(Icons.summarize),
            tooltip: 'AI 학습 요약',
            onPressed: _summarize,
          ),
          IconButton(
            icon: const Icon(Icons.copy_all),
            tooltip: '기록을 마크다운으로 내보내기 (클립보드)',
            onPressed: () async {
              final md = widget.engine.exportHistory();
              await Clipboard.setData(ClipboardData(text: md));
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('학습 기록을 클립보드에 복사했습니다 (Obsidian에 붙여넣기 가능)'),
                  duration: Duration(seconds: 3),
                ),
              );
            },
          ),
        ],
      ),
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
                // 최근 7일 활동 그래프
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('최근 7일 활동',
                            style: Theme.of(context).textTheme.titleSmall),
                        const SizedBox(height: 12),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            for (final e
                                in widget.engine.weeklyActivity.entries) ...[
                              Expanded(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text('${e.value}',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall),
                                    const SizedBox(height: 4),
                                    Container(
                                      height: (8 + (e.value * 16).clamp(0, 96))
                                          .toDouble(),
                                      decoration: BoxDecoration(
                                        color: e.value > 0
                                            ? Colors.teal
                                            : Colors.teal.shade100,
                                        borderRadius:
                                            const BorderRadius.vertical(
                                                top: Radius.circular(4)),
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(_dayLabel(e.key),
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall),
                                  ],
                                ),
                              ),
                              if (e.key !=
                                  widget.engine.weeklyActivity.keys.last)
                                const SizedBox(width: 6),
                            ],
                          ],
                        ),
                      ],
                    ),
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
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline),
                        tooltip: '과목 데이터 삭제',
                        onPressed: () => _confirmDeleteSubject(e.key),
                      ),
                    ),
                  ),
                // 오답노트 (현재 과목)
                Padding(
                  padding: const EdgeInsets.only(top: 16, bottom: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '오답노트 (${_label(widget.engine.subject)} · '
                          '${_mistakes.length}개)',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                      ),
                      TextButton.icon(
                        icon: const Icon(Icons.style, size: 18),
                        label: const Text('복습'),
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute<void>(
                            builder: (_) => MistakeReviewPage(
                                engine: widget.engine),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (_mistakes.isEmpty)
                  const Card(
                    child: ListTile(
                      leading: Icon(Icons.bookmark_border),
                      title: Text('오답노트가 비어 있습니다'),
                      subtitle: Text('채팅에서 "오답" 버튼으로 틀린 문제를 저장하세요'),
                    ),
                  )
                else
                  for (var i = 0; i < _mistakes.length; i++)
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.bookmark, color: Colors.redAccent),
                        title: Text(_mistakes[i].question,
                            maxLines: 2, overflow: TextOverflow.ellipsis),
                        subtitle: Text('A: ${_mistakes[i].answer}',
                            maxLines: 2, overflow: TextOverflow.ellipsis),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline),
                          tooltip: '삭제',
                          onPressed: () => _deleteMistake(i),
                        ),
                      ),
                    ),
              ],
            ),
    );
  }
}
