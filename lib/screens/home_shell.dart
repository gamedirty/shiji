import 'package:flutter/material.dart';

import '../models.dart';
import '../theme.dart';
import '../widgets/common_widgets.dart';
import 'add_entry_sheet.dart';
import 'foods_screen.dart';
import 'plan_screen.dart';

/// 主框架：饮食计划 / +（记录饮食）/ 食材库
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;
  DateTime _selectedDate = DateTime.now();

  Future<void> _openAdd({MealType? type}) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) =>
          AddEntrySheet(initialDate: _selectedDate, initialType: type),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      body: AppBackground(
        child: IndexedStack(
          index: _tab,
          children: [
            PlanScreen(
              selectedDate: _selectedDate,
              onDateChanged: (d) => setState(() => _selectedDate = d),
              onAdd: ({type}) => _openAdd(type: type),
            ),
            const FoodsScreen(),
          ],
        ),
      ),
      bottomNavigationBar: GlassNavBar(
        index: _tab,
        onTab: (i) => setState(() => _tab = i),
        onAdd: () => _openAdd(),
      ),
    );
  }
}

/// iOS 液态玻璃风格底部导航：左 Tab + 中间蓝色加号 + 右 Tab
class GlassNavBar extends StatelessWidget {
  final int index;
  final ValueChanged<int> onTab;
  final VoidCallback onAdd;

  const GlassNavBar({
    super.key,
    required this.index,
    required this.onTab,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Row(
          children: [
            const Spacer(),
            GlassSurface(
              radius: 32,
              child: SizedBox(
                height: 66,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _tabItem(0, Icons.restaurant_rounded, '饮食计划'),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: PressableScale(
                        onTap: onAdd,
                        child: Container(
                          width: 60,
                          height: 44,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [Color(0xFF35C287), Color(0xFF0E9F6E)],
                            ),
                            borderRadius: BorderRadius.circular(22),
                            border: Border.all(
                              color: const Color(0x66FFFFFF),
                              width: 1,
                            ),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x59129B6C),
                                blurRadius: 14,
                                offset: Offset(0, 5),
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.add_rounded,
                            color: Colors.white,
                            size: 26,
                          ),
                        ),
                      ),
                    ),
                    _tabItem(1, Icons.grid_view_rounded, '食材库'),
                  ],
                ),
              ),
            ),
            const Spacer(),
          ],
        ),
      ),
    );
  }

  Widget _tabItem(int i, IconData icon, String label) {
    final selected = index == i;
    final color = selected ? AppColors.accent : const Color(0xFF6D727B);
    return SizedBox(
      width: 84,
      height: double.infinity,
      child: PressableScale(
        behavior: HitTestBehavior.opaque,
        onTap: () => onTab(i),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
