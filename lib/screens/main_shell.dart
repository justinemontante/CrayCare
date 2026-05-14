import 'package:flutter/material.dart';
import 'dashboard_screen.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _currentIndex = 0;

  static const List<Widget> _screens = [
    DashboardScreen(),
    PlaceholderScreen(label: 'Analytics'),
    PlaceholderScreen(label: 'Tanks'),
    PlaceholderScreen(label: 'Controls'),
    PlaceholderScreen(label: 'Notifications'),
  ];

  static const List<_NavItem> _navItems = [
    _NavItem(icon: Icons.dashboard_rounded, label: 'Dashboard'),
    _NavItem(icon: Icons.bar_chart_rounded, label: 'Analytics'),
    _NavItem(icon: Icons.inventory_2_rounded, label: 'Tank'),
    _NavItem(icon: Icons.memory_rounded, label: 'Controls'),
    _NavItem(icon: Icons.notifications_rounded, label: 'Notifications'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFFf8ffff), Color(0xFFf2fdfd), Color(0xFFe8fafa), Color(0xFFdaf4f5)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              border: Border(bottom: BorderSide(color: Color(0x0f000000), width: 1)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Image.asset('assets/images/logo.png', width: 42, height: 42),
                    const SizedBox(width: 6),
                    const Text('Cray', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Color(0xFF0B3C49), letterSpacing: -0.3)),
                    const Text('Care', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Color(0xFF1FA5A5), letterSpacing: -0.3)),
                  ],
                ),
                GestureDetector(
                  onTap: () {},
                  child: Container(
                    width: 34,
                    height: 34,
                    decoration: const BoxDecoration(
                      color: Color(0xFF1FA5A5),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.person, color: Colors.white, size: 20),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _screens[_currentIndex],
          ),
          _buildBottomNav(),
        ],
      ),
    );
  }

  Widget _buildBottomNav() {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 10, 8, 10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.85),
        boxShadow: const [BoxShadow(color: Color(0x0d000000), blurRadius: 20, offset: Offset(0, -4))],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: List.generate(_navItems.length, (i) {
          final item = _navItems[i];
          final isActive = i == _currentIndex;
          return GestureDetector(
            onTap: () => setState(() => _currentIndex = i),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: isActive ? const Color(0x1F1FA5A5) : Colors.transparent,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(item.icon, size: 24, color: isActive ? const Color(0xFF1FA5A5) : const Color(0xFF0B3C49).withOpacity(0.3)),
                  const SizedBox(height: 3),
                  Text(
                    item.label,
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: isActive ? const Color(0xFF1FA5A5) : const Color(0xFF0B3C49).withOpacity(0.4)),
                  ),
                  if (isActive)
                    Container(
                      margin: const EdgeInsets.only(top: 2),
                      width: 24,
                      height: 3,
                      decoration: const BoxDecoration(
                        color: Color(0xFF1FA5A5),
                        borderRadius: BorderRadius.all(Radius.circular(3)),
                      ),
                    ),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }
}

class PlaceholderScreen extends StatelessWidget {
  final String label;
  const PlaceholderScreen({super.key, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      child: Center(
        child: Text(label, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Color(0xFF0B3C49))),
      ),
    );
  }
}

class _NavItem {
  final IconData icon;
  final String label;
  const _NavItem({required this.icon, required this.label});
}
