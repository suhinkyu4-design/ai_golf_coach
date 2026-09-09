import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/swing_provider.dart';

class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<SwingProvider>(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('스윙 분석 기록'),
      ),
      body: provider.swingHistory.isEmpty
          ? const Center(
              child: Text('저장된 스윙 분석 기록이 없습니다.', style: TextStyle(color: Colors.grey)),
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
                    title: Text('${swing.club} 스윙 (${swing.view.name})'),
                    subtitle: Text(swing.createdAt.toString().split('.')[0]),
                    trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                  ),
                );
              },
            ),
    );
  }
}
