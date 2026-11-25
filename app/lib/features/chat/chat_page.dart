/// 主页：AI 对话框。自然语言完成记录与查询（服务端 Agent + coachpal 工具集）。
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../core/settings.dart';
import '../../core/theme/palette.dart';

class ChatMedia {
  final String url; // 相对路径 /media/videos/xxx.gif
  final String caption;
  final List<String> steps;
  const ChatMedia(this.url, this.caption, this.steps);
}

class ChatMessage {
  final String role; // user / assistant
  final String content;
  final List<String> actions; // 已执行动作（如 记录体重）
  final bool? actionOk;
  final List<ChatMedia> media; // 动画演示等附件
  const ChatMessage(this.role, this.content,
      {this.actions = const [], this.actionOk, this.media = const []});
}

class ChatPage extends ConsumerStatefulWidget {
  const ChatPage({super.key});

  @override
  ConsumerState<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends ConsumerState<ChatPage> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _settings = AppSettings();
  final List<ChatMessage> _messages = [
    const ChatMessage(
        'assistant',
        '你好！我是 CoachPal 教练 💪\n\n'
        '直接跟我说就行，比如：\n'
        '· 「今天体重 77.9，体脂 21.4」\n'
        '· 「午饭吃了 150g 鸡胸肉、200g 米饭」\n'
        '· 「卧推 80kg 做了 5 组，RPE 8」\n'
        '· 「这周复盘一下」/「我该吃多少热量」'),
  ];
  bool _sending = false;
  bool _configured = false;
  bool _checked = false;

  @override
  void initState() {
    super.initState();
    _settings.isConfigured().then((v) {
      if (mounted) {
        setState(() {
          _configured = v;
          _checked = true;
        });
      }
    });
  }

  void _scrollDown() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut);
      }
    });
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    final url = await _settings.serverUrl();
    final token = await _settings.token();
    if (url == null || url.isEmpty || token == null || token.isEmpty) {
      setState(() => _configured = false);
      return;
    }
    setState(() {
      _messages.add(ChatMessage('user', text));
      _sending = true;
    });
    _input.clear();
    _scrollDown();

    try {
      final history = _messages
          .take(_messages.length - 1)
          .map((m) => {'role': m.role, 'content': m.content})
          .toList();
      final r = await http.post(
        Uri.parse('$url/api/agent/chat'),
        headers: {'Authorization': 'Bearer $token',
                  'Content-Type': 'application/json'},
        body: jsonEncode({'message': text, 'history': history}),
      );
      if (r.statusCode != 200) {
        setState(() {
          _messages.add(ChatMessage('assistant',
              '服务返回 ${r.statusCode}：${r.body.length > 200 ? '${r.body.substring(0, 200)}…' : r.body}',
              actionOk: false));
          _sending = false;
        });
        _scrollDown();
        return;
      }
      final data = jsonDecode(r.body) as Map<String, dynamic>;
      final actions = ((data['actions'] as List?) ?? [])
          .map((a) {
            final ok = a['ok'] == true;
            final name = _toolLabel(a['tool'] as String? ?? '');
            return '${ok ? '✓' : '✗'} $name';
          })
          .toList();
      final serverUrl = url;
      final media = ((data['media'] as List?) ?? [])
          .map((m) => ChatMedia(
                '$serverUrl${m['url']}',
                (m['caption'] as String?) ?? '',
                ((m['steps'] as List?) ?? []).cast<String>(),
              ))
          .toList();
      setState(() {
        _messages.add(ChatMessage(
          'assistant',
          (data['reply'] as String?) ?? '（无回复）',
          actions: actions,
          actionOk: actions.isNotEmpty &&
              actions.every((a) => a.startsWith('✓')),
          media: media,
        ));
        _sending = false;
      });
      _scrollDown();
    } catch (e) {
      setState(() {
        _messages.add(ChatMessage('assistant', '连接失败：$e\n\n'
            '请检查「我的」页里的服务器地址是否可达。', actionOk: false));
        _sending = false;
      });
      _scrollDown();
    }
  }

  String _toolLabel(String tool) {
    final labels = {
      'record_weight': '记录体重', 'record_measurements': '记录围度',
      'record_meal': '记录饮食', 'record_strength': '记录力量',
      'record_workout': '记录训练', 'set_goal': '设置目标',
      'update_profile': '更新档案', 'get_today': '查询今日',
      'get_status': '查询状态', 'get_targets': '计算目标',
      'get_report': '周复盘', 'list_goals': '查询目标',
      'query_food': '查食物', 'search_exercises': '搜动作',
      'exercise_detail': '动作详情', 'list_workouts': '查训练',
      'list_strength': '查力量', 'list_measurements': '查围度',
      'list_meals': '查饮食',
    };
    return labels[tool] ?? tool;
  }

  @override
  Widget build(BuildContext context) {
    if (!_checked) {
      return const Center(child: CircularProgressIndicator());
    }
    if (!_configured) {
      return _SetupHint(onRetry: () async {
        final v = await _settings.isConfigured();
        if (mounted) {
          setState(() {
            _configured = v;
            _checked = true;
          });
        }
      });
    }
    return SafeArea(
      child: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.all(12),
              itemCount: _messages.length + (_sending ? 1 : 0),
              itemBuilder: (context, i) {
                if (i >= _messages.length) {
                  return const Padding(
                    padding: EdgeInsets.all(16),
                    child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text('正在思考…',
                            style: TextStyle(color: Colors.grey))),
                  );
                }
                final m = _messages[i];
                return _Bubble(message: m);
              },
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: _input,
                  minLines: 1,
                  maxLines: 4,
                  onSubmitted: (_) => _send(),
                  decoration: const InputDecoration(
                    hintText: '说说今天吃了什么、练了什么…',
                    border: InputBorder.none,
                  ),
                ),
              ),
              IconButton(
                onPressed: _sending ? null : _send,
                icon: const Icon(Icons.send),
              ),
            ]),
          ),
        ],
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  final ChatMessage message;
  const _Bubble({required this.message});

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == 'user';
    final theme = Theme.of(context);
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.82),
        decoration: BoxDecoration(
          color: isUser
              ? theme.colorScheme.primary
              : theme.colorScheme.surface,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(14),
            topRight: const Radius.circular(14),
            bottomLeft: Radius.circular(isUser ? 14 : 4),
            bottomRight: Radius.circular(isUser ? 4 : 14),
          ),
          border: isUser
              ? null
              : Border.all(color: theme.dividerColor.withValues(alpha: 0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              message.content,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: isUser
                    ? theme.colorScheme.onPrimary
                    : theme.textTheme.bodyMedium?.color,
              ),
            ),
            if (message.media.isNotEmpty) ...[
              const SizedBox(height: 8),
              for (final m in message.media)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.network(
                          m.url,
                          width: 220,
                          fit: BoxFit.contain,
                          errorBuilder: (_, __, ___) => const SizedBox(
                            width: 220,
                            height: 80,
                            child: Center(
                                child: Text('动画加载失败',
                                    style: TextStyle(
                                        fontSize: 11, color: Colors.grey))),
                          ),
                          loadingBuilder: (_, child, progress) =>
                              progress == null
                                  ? child
                                  : const SizedBox(
                                      width: 220,
                                      height: 80,
                                      child: Center(
                                          child: SizedBox(
                                              width: 18,
                                              height: 18,
                                              child:
                                                  CircularProgressIndicator(
                                                      strokeWidth: 2)))),
                        ),
                      ),
                      if (m.steps.isNotEmpty)
                        for (final st in m.steps)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text('· $st',
                                style: const TextStyle(fontSize: 11)),
                          ),
                    ],
                  ),
                ),
            ],
            if (message.actions.isNotEmpty) ...[
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                children: [
                  for (final a in message.actions)
                    Chip(
                      visualDensity: VisualDensity.compact,
                      label: Text(a, style: const TextStyle(fontSize: 11)),
                      backgroundColor: message.actionOk == true
                          ? AppPalette.statusGood.withValues(alpha: 0.15)
                          : AppPalette.statusBad.withValues(alpha: 0.15),
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

class _SetupHint extends StatelessWidget {
  final VoidCallback onRetry;
  const _SetupHint({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_outlined, size: 48, color: Colors.grey),
            const SizedBox(height: 12),
            const Text('还没有连接同步服务'),
            const Text('在「我的」页配置服务器地址并登录后，\n就可以用对话完成所有记录。',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey)),
            const SizedBox(height: 16),
            TextButton(onPressed: onRetry, child: const Text('我配置好了，重新检查')),
          ],
        ),
      ),
    );
  }
}
