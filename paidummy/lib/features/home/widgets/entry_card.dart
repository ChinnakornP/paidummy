/// Guest sign-in card — Thai display-name field + gold "เข้าสู่เกม" CTA.
library;

import 'package:flutter/material.dart';

class EntryCard extends StatelessWidget {
  const EntryCard({
    super.key,
    required this.nameController,
    required this.busy,
    required this.onSubmit,
    this.refController,
    this.showRef = false,
    this.onToggleRef,
  });
  final TextEditingController nameController;
  final bool busy;
  final Future<void> Function() onSubmit;
  final TextEditingController? refController;
  final bool showRef;
  final VoidCallback? onToggleRef;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xCC0F2E22), Color(0xCC061A12)],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: const Color(0xFFC89A48).withValues(alpha: 0.45),
          width: 1.5,
        ),
        boxShadow: const [
          BoxShadow(color: Colors.black54, blurRadius: 24, offset: Offset(0, 8)),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.only(left: 4, bottom: 8),
            child: Text(
              'ชื่อผู้เล่น',
              style: TextStyle(
                color: Color(0xFFFFE7A6),
                fontSize: 13,
                letterSpacing: 1.0,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          TextField(
            controller: nameController,
            style: const TextStyle(color: Colors.white, fontSize: 16),
            cursorColor: const Color(0xFFFFE7A6),
            decoration: InputDecoration(
              hintText: 'ตั้งชื่อให้เพื่อนรู้จัก',
              hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.35)),
              filled: true,
              fillColor: Colors.black.withValues(alpha: 0.35),
              prefixIcon: const Icon(Icons.person_outline,
                  color: Color(0xFFFFE7A6)),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: Colors.white.withValues(alpha: 0.08),
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFFFD24A), width: 1.6),
              ),
            ),
          ),
          if (refController != null) ...[
            const SizedBox(height: 10),
            InkWell(
              onTap: onToggleRef,
              borderRadius: BorderRadius.circular(8),
              child: Row(
                children: [
                  Icon(
                    showRef ? Icons.expand_less : Icons.expand_more,
                    color: const Color(0xFFFFE7A6),
                    size: 18,
                  ),
                  const SizedBox(width: 4),
                  const Text(
                    'มีรหัสเชิญจากเพื่อน?',
                    style: TextStyle(
                      color: Color(0xFFFFE7A6),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            if (showRef) ...[
              const SizedBox(height: 6),
              TextField(
                controller: refController,
                style: const TextStyle(color: Colors.white, fontSize: 14),
                cursorColor: const Color(0xFFFFE7A6),
                decoration: InputDecoration(
                  hintText: 'รหัสเชิญ 8 ตัวอักษร',
                  hintStyle:
                      TextStyle(color: Colors.white.withValues(alpha: 0.35)),
                  filled: true,
                  fillColor: Colors.black.withValues(alpha: 0.35),
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ],
          ],
          const SizedBox(height: 16),
          // Primary CTA: gold gradient, glowing when active.
          DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              boxShadow: busy
                  ? null
                  : const [
                      BoxShadow(color: Color(0x66FFD24A), blurRadius: 16),
                    ],
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFFFFD24A), Color(0xFFC8932A)],
              ),
            ),
            child: Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(14),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: busy ? null : () => onSubmit(),
                child: SizedBox(
                  height: 52,
                  child: Center(
                    child: busy
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.4,
                              valueColor: AlwaysStoppedAnimation(
                                Color(0xFF1A1A1A),
                              ),
                            ),
                          )
                        : const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.play_arrow_rounded,
                                  color: Color(0xFF1A1A1A), size: 26),
                              SizedBox(width: 4),
                              Text(
                                'เข้าสู่เกม',
                                style: TextStyle(
                                  color: Color(0xFF1A1A1A),
                                  fontSize: 17,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.8,
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: Text(
              'เล่นแบบผู้เยือน · ไม่ต้องสมัคร',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.55),
                fontSize: 11,
                letterSpacing: 0.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
