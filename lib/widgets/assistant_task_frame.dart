import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Companion controls on assistant-opened pages; never wraps the recording flow.
class AssistantTaskFrame extends StatefulWidget {
  final Widget child;
  const AssistantTaskFrame({super.key, required this.child});
  @override
  State<AssistantTaskFrame> createState() => _AssistantTaskFrameState();
}

class _AssistantTaskFrameState extends State<AssistantTaskFrame>
    with WidgetsBindingObserver {
  static const channel =
      MethodChannel('com.metaoffice.aigolfcoatch/voice_capture');
  bool listening = false;
  String? status;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  Future<void> stop() async {
    if (mounted) setState(() => listening = false);
    await channel.invokeMethod('disable');
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed && listening) stop();
  }

  Future<void> listen() async {
    if (listening) {
      await stop();
      return;
    }
    try {
      if (await channel.invokeMethod<bool>('requestPermission') != true ||
          !mounted) return;
      channel.setMethodCallHandler((call) async {
        if (!mounted || !listening || call.method != 'state') return;
        final m = Map<String, dynamic>.from(call.arguments as Map);
        if (m['status'] == 'transcript') {
          await stop();
          if (!mounted) return;
          final text = (m['text'] as String? ?? '').trim();
          if (text.isNotEmpty) Navigator.pop(context, text);
        } else if ((m['status'] as String? ?? '').startsWith('unavailable')) {
          await stop();
          if (mounted) setState(() => status = '인식하지 못했어요. 다시 말씀해 주세요.');
        }
      });
      setState(() {
        listening = true;
        status = null;
      });
      await channel.invokeMethod('enableConversation');
    } catch (_) {
      if (mounted)
        setState(() {
          listening = false;
          status = '음성 입력을 사용할 수 없어요.';
        });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (listening) channel.invokeMethod('disable');
    channel.setMethodCallHandler(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
          body: Column(children: [
        Expanded(child: widget.child),
        Material(
            color: Theme.of(context).colorScheme.surfaceVariant,
            child: SafeArea(
                top: false,
                child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      if (listening || status != null)
                        Text(listening ? '“이전 화면” 또는 원하는 작업을 말씀하세요.' : status!,
                            style: Theme.of(context).textTheme.bodySmall),
                      Row(children: [
                        Expanded(
                            child: TextButton.icon(
                                onPressed: () => Navigator.pop(context),
                                icon: const Icon(Icons.chat_bubble_outline),
                                label: const Text('대화로 돌아가기'))),
                        IconButton(
                            tooltip: listening ? '음성 입력 중지' : '코치에게 말하기',
                            onPressed: listen,
                            icon: Icon(
                                listening ? Icons.stop_circle : Icons.mic_none))
                      ]),
                    ]))))
      ]));
}
