import 'package:flutter/material.dart';
import 'package:tikitaka_lfm/tikitaka_lfm.dart';

/// 티키타카 채팅 위젯 — LFM2.5 파트너와 대화 UI
class TikiTakaChat extends StatefulWidget {
  final TikiTakaLfm engine;
  final String subject;

  /// 대화가 성공적으로 완료(활동 기록)될 때마다 호출된다.
  /// 예: 호스트 UI가 학습 통계(streak 등)를 갱신하는 용도.
  final VoidCallback? onActivity;

  /// '문제/평가' 빠른 액션 버튼 표시 여부
  final bool showActions;

  const TikiTakaChat({
    super.key,
    required this.engine,
    this.subject = '수학',
    this.onActivity,
    this.showActions = true,
  });

  @override
  State<TikiTakaChat> createState() => _TikiTakaChatState();
}

class _TikiTakaChatState extends State<TikiTakaChat> {
  final _controller = TextEditingController();
  final _scroll = ScrollController();
  List<TkMessage> _messages = [];
  bool _busy = false;
  bool _online = false;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    widget.engine.setSubject(widget.subject);
    _init();
  }

  @override
  void didUpdateWidget(covariant TikiTakaChat oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.subject != widget.subject) {
      widget.engine.setSubject(widget.subject);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    await widget.engine.loadHistory();
    _online = await widget.engine.isAvailable();
    if (mounted) {
      setState(() {
        _messages = widget.engine.history;
        if (_messages.isEmpty) {
          _messages = [
            TkMessage(role: 'assistant', content: widget.engine.proactiveGreeting()),
          ];
        }
      });
      _scrollToBottom();
    }
  }

  /// Ollama 연결 상태만 다시 확인 (기록은 유지)
  Future<void> _recheck() async {
    if (!mounted) return;
    setState(() => _checking = true);
    final online = await widget.engine.isAvailable();
    if (mounted) {
      setState(() {
        _online = online;
        _checking = false;
      });
      if (online) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('LFM2.5 연결 확인됨'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }

  Future<void> _send(String text) async {
    final message = text.trim();
    if (message.isEmpty || _busy) return;
    _controller.clear();
    setState(() {
      _messages.add(TkMessage(role: 'user', content: message));
      // 스트리밍 답변 자리(빈 말풍선) — 델타가 도착하면 실시간으로 채워진다
      _messages.add(TkMessage(role: 'assistant', content: ''));
      _busy = true;
    });
    _scrollToBottom();
    try {
      final buffer = StringBuffer();
      await for (final delta in widget.engine.askStream(message)) {
        buffer.write(delta);
        if (!mounted) return;
        setState(() {
          _messages[_messages.length - 1] =
              TkMessage(role: 'assistant', content: buffer.toString());
        });
        _scrollToBottom();
      }
      if (!mounted) return;
      setState(() => _busy = false);
      widget.onActivity?.call(); // 활동 기록(통계) 후 호스트에 알림
    } catch (e) {
      if (mounted) {
        setState(() {
          // 빈 자리 제거 후 오류 메시지 표시
          _messages.removeLast();
          _messages.add(TkMessage(
              role: 'assistant',
              content: '⚠️ LFM2.5 연결 실패. Ollama 실행 확인: ${e.toString().split('\n').first}'));
          _busy = false;
        });
        _scrollToBottom();
      }
    }
  }

  /// 사용자 메시지가 하나라도 있는지 (평가 버튼 활성 조건)
  bool get _hasUserMessage => _messages.any((m) => m.role == 'user');

  /// 오늘의 문제 — 퀴즈를 히스토리에 기록하고 화면에 표시 (모델 호출 없음)
  void _quiz() {
    if (_busy) return;
    final message = widget.engine.tutorSay(widget.engine.makeQuiz());
    setState(() => _messages.add(message));
    _scrollToBottom();
  }

  /// 맞춤 학습 계획을 생성해 대화상자로 보여준다 (히스토리 비파괴)
  Future<void> _plan() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final plan = await widget.engine.learningPlan();
      if (!mounted) return;
      setState(() => _busy = false);
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('맞춤 학습 계획'),
          content: SingleChildScrollView(
            child: SelectableText(plan),
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
      if (mounted) {
        setState(() {
          _busy = false;
          _messages.add(TkMessage(
              role: 'assistant',
              content: '⚠️ 학습 계획 생성 실패: ${e.toString().split('\n').first}'));
        });
        _scrollToBottom();
      }
    }
  }

  /// 마지막 사용자 답변을 비히스토리 방식으로 평가해 피드백 표시
  Future<void> _evaluate() async {
    if (_busy) return;
    TkMessage? lastUser;
    for (final m in _messages.reversed) {
      if (m.role == 'user') {
        lastUser = m;
        break;
      }
    }
    if (lastUser == null) return;
    setState(() => _busy = true);
    try {
      final feedback = await widget.engine.gradeDirect(lastUser.content);
      if (!mounted) return;
      setState(() {
        _messages.add(TkMessage(role: 'assistant', content: feedback));
        _busy = false;
      });
      _scrollToBottom();
    } catch (e) {
      if (mounted) {
        setState(() {
          _messages.add(TkMessage(
              role: 'assistant',
              content: '⚠️ 평가 실패: ${e.toString().split('\n').first}'));
          _busy = false;
        });
        _scrollToBottom();
      }
    }
  }

  /// 메시지 추가 후 프레임 렌더링이 끝난 시점에 맨 아래로 스크롤
  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // 상태바
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: _online ? Colors.green.shade50 : Colors.orange.shade50,
          child: Row(
            children: [
              Icon(_online ? Icons.check_circle : Icons.wifi_off,
                  size: 16, color: _online ? Colors.green : Colors.orange),
              const SizedBox(width: 8),
              Text(
                _online ? 'LFM2.5 온디바이스 연결됨' : '오프라인 — Ollama 필요',
                style: TextStyle(fontSize: 12, color: _online ? Colors.green.shade700 : Colors.orange.shade800),
              ),
              const Spacer(),
              Text(widget.subject, style: const TextStyle(fontSize: 12, color: Colors.grey)),
              // 연결 다시 확인
              if (_checking)
                const Padding(
                  padding: EdgeInsets.only(left: 8),
                  child: SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              else
                IconButton(
                  icon: const Icon(Icons.refresh, size: 18),
                  tooltip: '연결 다시 확인',
                  visualDensity: VisualDensity.compact,
                  onPressed: _recheck,
                ),
            ],
          ),
        ),
        // 대화 목록
        Expanded(
          child: ListView.builder(
            controller: _scroll,
            padding: const EdgeInsets.all(16),
            itemCount: _messages.length + (_busy ? 1 : 0),
            itemBuilder: (context, i) {
              if (i >= _messages.length) {
                return const Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: EdgeInsets.all(8),
                    child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                  ),
                );
              }
              final m = _messages[i];
              final isUser = m.role == 'user';
              return Align(
                alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
                  decoration: BoxDecoration(
                    color: isUser ? Theme.of(context).colorScheme.primary : Colors.grey.shade100,
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(16),
                      topRight: const Radius.circular(16),
                      bottomLeft: Radius.circular(isUser ? 16 : 4),
                      bottomRight: Radius.circular(isUser ? 4 : 16),
                    ),
                  ),
                  child: Text(
                    m.content,
                    style: TextStyle(
                      color: isUser ? Colors.white : Colors.black87,
                      fontSize: 14,
                      height: 1.4,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        // 액션 버튼 (문제/평가)
        if (widget.showActions)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
            child: Row(
              children: [
                ActionChip(
                  avatar: const Icon(Icons.quiz, size: 16),
                  label: const Text('문제'),
                  onPressed: _busy ? null : _quiz,
                ),
                const SizedBox(width: 8),
                ActionChip(
                  avatar: const Icon(Icons.check_circle_outline, size: 16),
                  label: const Text('평가'),
                  onPressed: (_busy || !_hasUserMessage) ? null : _evaluate,
                ),
                const SizedBox(width: 8),
                ActionChip(
                  avatar: const Icon(Icons.event_note, size: 16),
                  label: const Text('계획'),
                  onPressed: _busy ? null : _plan,
                ),
              ],
            ),
          ),
        // 입력창
        SafeArea(
          top: false,
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8)],
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    onSubmitted: _send,
                    decoration: const InputDecoration(
                      hintText: '대답을 입력하세요...',
                      border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(24))),
                      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: _busy ? null : () => _send(_controller.text),
                  icon: const Icon(Icons.send),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
