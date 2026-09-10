import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/swing_provider.dart';
import '../services/localization_service.dart';

class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<SwingProvider>(context);
    final lang = provider.appLanguage;

    return Scaffold(
      appBar: AppBar(
        title: Text(LocalizationService.tr('recent_history', lang)),
      ),
      body: provider.swingHistory.isEmpty
          ? Center(
              child: Text(
                LocalizationService.tr('no_history', lang),
                style: const TextStyle(color: Colors.grey),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: provider.swingHistory.length,
              itemBuilder: (context, index) {
                final swing = provider.swingHistory[index];
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    leading: const CircleAvatar(
                      backgroundColor: Colors.teal,
                      child: Icon(Icons.sports_golf, color: Colors.white),
                    ),
                    title: Text('${swing.club} Swing (${swing.view.name})'),
                    subtitle: Text(swing.createdAt.toString().split('.')[0]),
                    trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                  ),
                );
              },
            ),
    );
  }
}
