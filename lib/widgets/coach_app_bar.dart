import '../models/assistant_screen_context.dart';
export '../models/assistant_screen_context.dart';
import 'package:flutter/material.dart';
import '../views/assistant_screen.dart';

class CoachAppBar extends AppBar {
  CoachAppBar({super.key, super.title, super.leading,
    super.automaticallyImplyLeading = true, List<Widget>? actions,
    bool camera = false, AssistantScreenContext? situation}) : super(actions: [
      Builder(builder: (context) => IconButton(
        tooltip: 'AI 코치와 대화',
        icon: const CoachIcon(),
        onPressed: () => showCoachPopup(context, camera: camera, situation: situation))),
      ...?actions,
    ]);
}

bool _showing = false;
Future<void> showCoachPopup(BuildContext context, {bool camera = false, AssistantScreenContext? situation}) async {
  if (_showing) return;
  _showing = true;
  try {
    await showDialog<void>(context: context, builder: (context) => Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 24),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: SizedBox(width: 620,
        height: MediaQuery.sizeOf(context).height * .85,
        child: AssistantScreen(popup: true, cameraContext: camera, situation: situation)),
    ));
  } finally { _showing = false; }
}

class CoachIcon extends StatelessWidget {
  const CoachIcon({super.key});
  @override
  Widget build(BuildContext context) => Container(
    width: 36, height: 36,
    decoration: BoxDecoration(
      color: Theme.of(context).brightness == Brightness.dark ? const Color(0xFFB8F3D1) : const Color(0xFF174D39),
      shape: BoxShape.circle,
      border: Border.all(color: const Color(0xFFA6F0C5), width: 1.5)),
    child: Icon(Icons.smart_toy_rounded, color: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF12291D) : Colors.white, size: 26),
  );
}
