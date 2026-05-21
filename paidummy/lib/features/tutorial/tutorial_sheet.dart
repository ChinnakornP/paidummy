/// First-run onboarding — a swipeable 4-page how-to for Thai Dummy. Shown
/// once automatically from the lobby and reopenable from the home screen's
/// "วิธีเล่น" button.
library;

import 'package:flutter/material.dart';

Future<void> showTutorial(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: const Color(0xFF12313B),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => const TutorialSheet(),
  );
}

class _Step {
  const _Step(this.emoji, this.title, this.body);
  final String emoji;
  final String title;
  final String body;
}

const _steps = [
  _Step('🎴', 'จั่ว แล้ว ทิ้ง',
      'ทุกตาเริ่มด้วยการจั่วไพ่จากกอง (หรือ "เก็บ" จากกองทิ้ง) แล้วจบตาด้วยการทิ้งไพ่ 1 ใบ'),
  _Step('🃏', 'ลงไพ่เป็นชุด',
      'รวมไพ่ ≥3 ใบเป็นชุด: เลขเดียวกันต่างดอก (เซ็ต) หรือเรียงดอกเดียวกัน (รัน) แล้วกด "ลง"'),
  _Step('➕', 'ฝากไพ่',
      'แตะชุดที่ลงไว้บนโต๊ะ แล้วเลือกไพ่ในมือเพื่อ "ฝาก" ต่อเข้าไปในชุดนั้น เพิ่มแต้ม'),
  _Step('⚡', 'น็อคเพื่อจบรอบ',
      'เมื่อลงไพ่ได้หมดมือเหลือ 1 ใบ ปุ่ม "น็อค" จะสว่าง กดเพื่อจบรอบและรับโบนัส!'),
];

class TutorialSheet extends StatefulWidget {
  const TutorialSheet({super.key});
  @override
  State<TutorialSheet> createState() => _TutorialSheetState();
}

class _TutorialSheetState extends State<TutorialSheet> {
  final _page = PageController();
  int _index = 0;

  @override
  void dispose() {
    _page.dispose();
    super.dispose();
  }

  void _next() {
    if (_index < _steps.length - 1) {
      _page.nextPage(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    } else {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SizedBox(
        height: 380,
        child: Column(
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(top: 8, bottom: 8),
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _page,
                onPageChanged: (i) => setState(() => _index = i),
                itemCount: _steps.length,
                itemBuilder: (_, i) {
                  final s = _steps[i];
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 28),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(s.emoji, style: const TextStyle(fontSize: 64)),
                        const SizedBox(height: 18),
                        Text(
                          s.title,
                          style: const TextStyle(
                            color: Color(0xFFFFE7A6),
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          s.body,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 15,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < _steps.length; i++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: i == _index ? 18 : 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: i == _index
                          ? const Color(0xFFFFD24A)
                          : Colors.white24,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _next,
                  child: Text(
                    _index < _steps.length - 1 ? 'ถัดไป' : 'เริ่มเล่นเลย!',
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
