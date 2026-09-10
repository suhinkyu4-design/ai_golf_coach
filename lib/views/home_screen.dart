import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/swing_provider.dart';
import '../services/localization_service.dart';
import 'video_input_screen.dart';
import 'history_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<SwingProvider>(context);
    final lang = provider.appLanguage;

    return Scaffold(
      appBar: AppBar(
        title: Text(LocalizationService.tr('app_title', lang)),
        elevation: 0,
        actions: [
          // Language Switch Toggle Button
          TextButton.icon(
            onPressed: () {
              provider.toggleLanguage();
            },
            icon: const Icon(Icons.language, color: Colors.tealAccent, size: 20),
            label: Text(
              lang == AppLanguage.korean ? '🇰🇷 KR' : '🇺🇸 EN',
              style: const TextStyle(color: Colors.tealAccent, fontWeight: FontWeight.bold),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.history),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const HistoryScreen()),
              );
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAlignment.start,
          children: [
            // Banner Card
            Container(
              padding: const EdgeInsets.all(20.0),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF1E3C72), Color(0xFF2A5298)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16.0),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black26,
                    blurRadius: 10,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.white24,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.sports_golf, color: Colors.white, size: 28),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        LocalizationService.tr('banner_title', lang),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    LocalizationService.tr('banner_subtitle', lang),
                    style: const TextStyle(color: Colors.white70, fontSize: 14, height: 1.4),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 30),

            Text(
              LocalizationService.tr('start_new_swing', lang),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),

            // Start Button Card
            InkWell(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const VideoInputScreen()),
                );
              },
              borderRadius: BorderRadius.circular(16),
              child: Ink(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Theme.of(context).cardColor,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.teal.withOpacity(0.4), width: 1.5),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 26,
                      backgroundColor: Colors.teal.withOpacity(0.15),
                      child: const Icon(Icons.video_library_rounded, color: Colors.teal, size: 28),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAlignment.start,
                        children: [
                          Text(
                            LocalizationService.tr('select_video_btn', lang),
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            LocalizationService.tr('select_video_sub', lang),
                            style: const TextStyle(color: Colors.grey, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 30),

            // History Preview
            Column(
              crossAxisAlignment: CrossAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      LocalizationService.tr('recent_history', lang),
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    TextButton(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => const HistoryScreen()),
                        );
                      },
                      child: Text(LocalizationService.tr('view_all', lang)),
                    ),
                  ],
                ),
                if (provider.swingHistory.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(30),
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: Theme.of(context).cardColor,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: [
                        const Icon(Icons.analytics_outlined, size: 40, color: Colors.grey),
                        const SizedBox(height: 8),
                        Text(
                          LocalizationService.tr('no_history', lang),
                          style: const TextStyle(color: Colors.grey),
                        ),
                      ],
                    ),
                  )
                else
                  ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: provider.swingHistory.length,
                    itemBuilder: (context, index) {
                      final swing = provider.swingHistory[index];
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: const Icon(Icons.sports_golf, color: Colors.teal),
                          title: Text('${swing.club} Swing (${swing.view.name})'),
                          subtitle: Text(swing.createdAt.toString().split('.')[0]),
                          trailing: const Icon(Icons.chevron_right),
                        ),
                      );
                    },
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
