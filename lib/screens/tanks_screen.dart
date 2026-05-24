import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_colors.dart';
import '../services/tank_service.dart';
import '../widgets/tanks/inventory_tab.dart';
import '../widgets/tanks/sampling_tab.dart';
import '../widgets/tanks/trends_tab.dart';

// Helper for beautiful snackbars
void showBeautifulSnackbar(
  BuildContext context,
  String message,
  bool isSuccess,
) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isSuccess
                  ? Icons.check_circle_rounded
                  : Icons.warning_amber_rounded,
              color: Colors.white,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 13,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
      backgroundColor: isSuccess ? AppColors.success : AppColors.critical,
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 10,
      duration: const Duration(seconds: 3),
    ),
  );
}

class TanksScreen extends StatefulWidget {
  const TanksScreen({super.key});

  @override
  State<TanksScreen> createState() => _TanksScreenState();
}

class _TanksScreenState extends State<TanksScreen> {
  int _activeTab = 0;
  DateTime _lastEdited = DateTime.now();
  final _sampleCountController = TextEditingController();
  final _sampleWeightController = TextEditingController();
  final _sampleLengthController = TextEditingController();

  @override
  void initState() {
    super.initState();
    TankService.instance.addListener(_refreshUI);
  }

  @override
  void dispose() {
    _sampleCountController.dispose();
    _sampleWeightController.dispose();
    _sampleLengthController.dispose();
    TankService.instance.removeListener(_refreshUI);
    super.dispose();
  }

  void _refreshUI() {
    if (mounted) setState(() => _lastEdited = DateTime.now());
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      child: Column(
        children: [
          _buildHeader(),
          _buildTabBar(),
          Expanded(
            child: IndexedStack(
              index: _activeTab,
              children: [
                InventoryTab(
                  onShowInitModal: _showInitModal,
                  onShowMortalityModal: _showMortalityModal,
                  onShowEditModal: _showEditModal,
                  onShowLogsModal: _showLogsModal,
                  hasSetup: TankService.instance.isInitialized,
                  lastEdited: _lastEdited,
                ),
                SamplingTab(
                  sampleCountController: _sampleCountController,
                  sampleWeightController: _sampleWeightController,
                  sampleLengthController: _sampleLengthController,
                  onShowGrowthStageReferenceModal:
                      _showGrowthStageReferenceModal,
                ),
                const TrendsTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFFF8FFFF), // #f8ffff
            Color(0xFFF2FDFD), // #f2fdfd
            Color(0xFFE8FAFA), // #e8fafa
            Color(0xFFDAF4F5), // #daf4f5
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.1),
            blurRadius: 15,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned(
            right: 0,
            bottom: 0,
            width: 170,
            height: 100,
            child: Image.asset(
              'assets/images/crayfish_seaweed_tank.png',
              fit: BoxFit.contain,
              alignment: Alignment.bottomRight,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
            child: Row(
              children: [
                Container(
                  width: 4,
                  height: 42,
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(width: 14),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Tank — Grow-out',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: AppColors.dark,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Crayfish Growth Tracker',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppColors.dark.withValues(alpha: 0.5),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    final tabs = [
      (
        _activeTab == 0 ? Icons.inventory_2 : Icons.inventory_2_outlined,
        'Inventory',
      ),
      (_activeTab == 1 ? Icons.speed : Icons.speed_outlined, 'Sampling'),
      (
        _activeTab == 2 ? Icons.trending_up : Icons.trending_up_outlined,
        'Trends',
      ),
    ];
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 14),
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: AppColors.dark.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: List.generate(tabs.length, (i) {
          final isActive = _activeTab == i;
          return Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _activeTab = i),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: isActive ? Colors.white : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: isActive
                      ? [
                          BoxShadow(
                            color: AppColors.dark.withValues(alpha: 0.05),
                            blurRadius: 10,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : null,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      tabs[i].$1,
                      size: 14,
                      color: isActive
                          ? AppColors.primary
                          : AppColors.dark.withValues(alpha: 0.4),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      tabs[i].$2,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: isActive
                            ? AppColors.primary
                            : AppColors.dark.withValues(alpha: 0.4),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  void _showGrowthStageReferenceModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 5,
                    decoration: BoxDecoration(
                      color: AppColors.dark.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  'Growth Classification',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: AppColors.dark,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Based on SRAC Publication No. 244 & Queensland Guidelines.',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: AppColors.dark.withValues(alpha: 0.5),
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 24),
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: AppColors.dark.withValues(alpha: 0.08),
                    ),
                    color: Colors.white,
                  ),
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.06),
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(15),
                          ),
                        ),
                        child: const Row(
                          children: [
                            Expanded(
                              flex: 2,
                              child: Text('STAGE', style: _tableHeaderStyle),
                            ),
                            Expanded(
                              child: Text('LENGTH', style: _tableHeaderStyle),
                            ),
                            Expanded(
                              child: Text('WEIGHT', style: _tableHeaderStyle),
                            ),
                          ],
                        ),
                      ),
                      _buildTableRow(
                        'Early Juvenile',
                        '2–4 cm',
                        '1–5 g',
                        isStriped: false,
                      ),
                      _buildTableRow(
                        'Advanced Juvenile',
                        '4–6 cm',
                        '5–15 g',
                        isStriped: true,
                      ),
                      _buildTableRow(
                        'Grow-out Phase',
                        '6–10 cm',
                        '15–50 g',
                        isStriped: false,
                      ),
                      _buildTableRow(
                        'Market Size',
                        '> 10 cm',
                        '50 g +',
                        isStriped: true,
                        isLast: true,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(ctx),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.dark,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: const Text(
                      'Got it, thanks!',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  static const _tableHeaderStyle = TextStyle(
    fontSize: 9,
    fontWeight: FontWeight.w800,
    color: AppColors.primary,
    letterSpacing: 0.8,
  );

  Widget _buildTableRow(
    String stage,
    String length,
    String weight, {
    required bool isStriped,
    bool isLast = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: isStriped
            ? AppColors.dark.withValues(alpha: 0.02)
            : Colors.white,
        borderRadius: isLast
            ? const BorderRadius.vertical(bottom: Radius.circular(15))
            : null,
      ),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(
              stage,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppColors.dark,
              ),
            ),
          ),
          Expanded(
            child: Text(
              length,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppColors.dark.withValues(alpha: 0.6),
              ),
            ),
          ),
          Expanded(
            child: Text(
              weight,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: AppColors.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showInitModal() => _showSetupForm(isEdit: false);
  void _showEditModal() => _showSetupForm(isEdit: true);

  void _showSetupForm({required bool isEdit}) {
    final countCtrl = TextEditingController(
      text: isEdit ? '${TankService.instance.initialCount}' : '',
    );
    final sampleCountCtrl = TextEditingController(
      text: isEdit ? '${TankService.instance.sampleCount}' : '',
    );
    final totalWeightCtrl = TextEditingController(
      text: isEdit
          ? (TankService.instance.initialWeight * TankService.instance.sampleCount).toStringAsFixed(1)
          : '',
    );
    final totalLengthCtrl = TextEditingController(
      text: isEdit
          ? (TankService.instance.initialLength * TankService.instance.sampleCount).toStringAsFixed(1)
          : '',
    );

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 5,
                    decoration: BoxDecoration(
                      color: AppColors.dark.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  isEdit ? 'Edit Initialization' : 'Grow-Out Initialization',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: AppColors.dark,
                  ),
                ),
                const SizedBox(height: 24),
                _buildInfoCard(
                  Icons.people_alt_rounded,
                  'Initial Population',
                  'Total stock count upon start',
                  countCtrl,
                ),
                _buildInfoCard(
                  Icons.analytics_rounded,
                  'Sample Count',
                  'Number of crayfish sampled',
                  sampleCountCtrl,
                ),
                _buildInfoCard(
                  Icons.scale_rounded,
                  'Total Weight (g)',
                  'Sum weight of sampled group',
                  totalWeightCtrl,
                ),
                _buildInfoCard(
                  Icons.straighten_rounded,
                  'Total Length (cm)',
                  'Sum length of sampled group',
                  totalLengthCtrl,
                ),

                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      final count = int.tryParse(countCtrl.text) ?? 0;
                      final sampleCount =
                          int.tryParse(sampleCountCtrl.text) ?? 0;
                      final totalWeight =
                          double.tryParse(totalWeightCtrl.text) ?? 0.0;
                      final totalLength =
                          double.tryParse(totalLengthCtrl.text) ?? 0.0;

                      if (count > 0 && sampleCount > 0) {
                        TankService.instance.initializeGrowOut(
                          count,
                          sampleCount,
                          totalWeight,
                          totalLength,
                          DateTime.now(),
                        );
                        Navigator.pop(ctx);
                        showBeautifulSnackbar(
                          context,
                          isEdit
                              ? 'Setup beautifully updated!'
                              : 'Grow-out successfully initialized!',
                          true,
                        );
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      elevation: 0,
                    ),
                    child: Text(
                      isEdit ? 'Update Initialization' : 'Initialize Grow-Out',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildInfoCard(
    IconData icon,
    String title,
    String subtitle,
    TextEditingController controller,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: Colors.white, size: 16),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                        color: AppColors.dark,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 9,
                        color: AppColors.dark.withValues(alpha: 0.5),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: controller,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*$')),
            ],
            style: const TextStyle(
              fontWeight: FontWeight.w900,
              color: AppColors.primary,
            ),
            decoration: InputDecoration(
              hintText: '0',
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 14,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: AppColors.dark.withValues(alpha: 0.5),
                  width: 1.5,
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: AppColors.dark.withValues(alpha: 0.5),
                  width: 1.5,
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(
                  color: AppColors.primary,
                  width: 2,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showMortalityModal() {
    final countCtrl = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom,
            left: 24,
            right: 24,
            top: 16,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 5,
                  decoration: BoxDecoration(
                    color: AppColors.dark.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Log Mortality',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: AppColors.critical,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Record the number of dead crayfish found in the tank.',
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.dark.withValues(alpha: 0.5),
                ),
              ),
              const SizedBox(height: 24),
              _buildModalInput('Number of Dead Crayfish', 'e.g. 5', countCtrl),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    final mortalityVal = int.tryParse(countCtrl.text);
                    if (mortalityVal != null && mortalityVal > 0) {
                      TankService.instance.addMortality(mortalityVal);
                      Navigator.pop(ctx);
                      showBeautifulSnackbar(
                        context,
                        'Mortality of $mortalityVal successfully logged.',
                        false,
                      );
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.critical,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 0,
                  ),
                  child: const Text(
                    'Confirm Logging',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        );
      },
    );
  }

  void _showLogsModal() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 5,
                  decoration: BoxDecoration(
                    color: AppColors.dark.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Activity Logs',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: AppColors.dark,
                ),
              ),
              const SizedBox(height: 20),
              Expanded(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    _buildLogItem(
                      Icons.water_drop,
                      'Water changed',
                      'Today, 8:00 AM',
                      AppColors.primary,
                    ),
                    _buildLogItem(
                      Icons.restaurant,
                      'Fed 500g pellets',
                      'Yesterday, 6:00 PM',
                      AppColors.success,
                    ),
                    _buildLogItem(
                      Icons.warning_amber_rounded,
                      'Mortality: 2 recorded',
                      'Yesterday, 8:00 AM',
                      AppColors.critical,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Close',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: AppColors.dark,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildModalInput(
    String label,
    String hint,
    TextEditingController controller,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AppColors.dark,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: controller,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*$')),
            ],
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: TextStyle(
                color: AppColors.dark.withValues(alpha: 0.3),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 14,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: AppColors.dark.withValues(alpha: 0.5),
                  width: 1.5,
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: AppColors.dark.withValues(alpha: 0.5),
                  width: 1.5,
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(
                  color: AppColors.primary,
                  width: 2,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogItem(
    IconData icon,
    String title,
    String subtitle,
    Color color,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.dark.withValues(alpha: 0.06)),
        boxShadow: [
          BoxShadow(
            color: AppColors.dark.withValues(alpha: 0.02),
            blurRadius: 5,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 20, color: color),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: AppColors.dark,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                    color: AppColors.dark.withValues(alpha: 0.5),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
