import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/swing_provider.dart';
import 'video_input_screen.dart';
import 'history_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI 온디바이스 골프 코치'),
        elevation: 0,
        actions: [
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
                      const Text(
                        '무료 온디바이스 AI 분석',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    '스마트폰 안에서 안전하고 빠른 자세 수치화 및 스크린 OCR 통합 피드백을 제공합니다.',
                    style: TextStyle(color: Colors.white70, fontSize: 14, height: 1.4),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 30),

            const Text(
              '새 스윙 분석 시작',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
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
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAlignment.start,
                        children: [
                          Text(
                            '스윙 영상 선택 및 촬영',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                          SizedBox(height: 4),
                          Text(
                            '정면/후방 스윙 영상 불러오기',
                            style: TextStyle(color: Colors.grey, fontSize: 13),
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
            Consumer<SwingProvider>(
              builder: (context, provider, child) {
                return Column(
                  crossAxisAlignment: CrossAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          '최근 분석 기록',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        TextButton(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (context) => const HistoryScreen()),
                            );
                          },
                          child: const Text('전체보기'),
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
                        child: const Column(
                          children: [
                            Icon(Icons.analytics_outlined, size: 40, color: Colors.grey),
                            SizedBox(height: 8),
                            Text(
                              '아직 분석된 스윙 기록이 없습니다.',
                              style: TextStyle(color: Colors.grey),
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
                              title: Text('${swing.club} 스윙 (${swing.view.name})'),
                              subtitle: Text(swing.createdAt.toString().split('.')[0]),
                              trailing: const Icon(Icons.chevron_right),
                            ),
                          );
                        },
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
