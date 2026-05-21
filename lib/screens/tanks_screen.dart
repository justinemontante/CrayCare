import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../services/tank_service.dart';
import '../widgets/tanks/inventory_tab.dart';
import '../widgets/tanks/sampling_tab.dart';
import '../widgets/tanks/trends_tab.dart';

class TanksScreen extends StatefulWidget {
  const TanksScreen({super.key});

  @override
  State<TanksScreen> createState() => _TanksScreenState();
}

class _TanksScreenState extends State<TanksScreen> {
  int _activeTab = 0;
  final bool _hasSetup = true;
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
                  hasSetup: _hasSetup,
                  lastEdited: _lastEdited,
                ),
                SamplingTab(
                  sampleCountController: _sampleCountController,
                  sampleWeightController: _sampleWeightController,
                  sampleLengthController: _sampleLengthController,
                  onShowGrowthStageReferenceModal: _showGrowthStageReferenceModal,
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
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: AppColors.darkWith(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
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
            padding: const EdgeInsets.fromLTRB(12, 20, 12, 20),
            child: Row(
              children: [
                Container(
                  width: 3,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 14),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Tank — Grow-out',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.dark,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Crayfish Growth Tracker',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                        color: AppColors.darkWith(0.5),
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
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 14),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.darkWith(0.04),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: List.generate(tabs.length, (i) {
          final isActive = _activeTab == i;
          return Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _activeTab = i),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  color: isActive ? Colors.white : Colors.transparent,
                  borderRadius: BorderRadius.circular(11),
                  boxShadow: isActive
                      ? [
                          BoxShadow(
                            color: AppColors.primaryWith(0.12),
                            blurRadius: 8,
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
                      size: 12,
                      color: isActive
                          ? AppColors.primary
                          : AppColors.darkWith(0.45),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      tabs[i].$2,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: isActive
                            ? AppColors.primary
                            : AppColors.darkWith(0.45),
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
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
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
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.dark.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  'Growth Classification Reference',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                    color: AppColors.dark,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Based on SRAC Publication No. 244 and Queensland Government Guidelines.',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: AppColors.dark.withValues(alpha: 0.5),
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 24),
                Table(
                  border: TableBorder.all(
                    color: AppColors.dark.withValues(alpha: 0.08),
                    width: 1,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  columnWidths: const {
                    0: FlexColumnWidth(2.2),
                    1: FlexColumnWidth(1.5),
                    2: FlexColumnWidth(1.5),
                  },
                  children: [
                    TableRow(
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.05),
                      ),
                      children: const [
                        Padding(
                          padding: EdgeInsets.all(12),
                          child: Text(
                            'STAGE',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 9,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                        Padding(
                          padding: EdgeInsets.all(12),
                          child: Text(
                            'LENGTH',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 9,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                        Padding(
                          padding: EdgeInsets.all(12),
                          child: Text(
                            'WEIGHT',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 9,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                    _buildTableRow('Early Juvenile', '2 – 4 cm', '1 – 5 g'),
                    _buildTableRow('Advanced Juvenile', '4 – 6 cm', '5 – 15 g'),
                    _buildTableRow('Grow-out Phase', '6 – 10 cm', '15 – 50 g'),
                    _buildTableRow('Market Size / Adult', '> 10 cm', '50 g +'),
                  ],
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(ctx),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: AppColors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: const Text(
                      'Close Reference',
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
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

  TableRow _buildTableRow(String stage, String length, String weight) {
    return TableRow(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          child: Text(
            stage,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.dark),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          child: Text(
            length,
            style: TextStyle(fontSize: 10, color: AppColors.dark.withValues(alpha: 0.7)),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          child: Text(
            weight,
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.primary),
          ),
        ),
      ],
    );
  }

  void _showInitModal() {
    _showSetupForm(isEdit: false);
  }

  void _showEditModal() {
    _showSetupForm(isEdit: true);
  }

  void _showSetupForm({required bool isEdit}) {
    final countCtrl = TextEditingController(
      text: isEdit ? '${TankService.instance.initialCount}' : '',
    );
    final weightCtrl = TextEditingController(
      text: isEdit ? '${TankService.instance.initialWeight}' : '',
    );
    final lengthCtrl = TextEditingController(
      text: isEdit ? '${TankService.instance.initialLength}' : '',
    );

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom,
            left: 20,
            right: 20,
            top: 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.darkWith(0.1),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                isEdit ? 'Edit Grow-Out Setup' : 'Initialize Grow-Out',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppColors.dark,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Enter the initial stocking details for this tank.',
                style: TextStyle(fontSize: 12, color: AppColors.darkWith(0.5)),
              ),
              const SizedBox(height: 20),
              _buildModalInput('Initial Stock Count', 'e.g. 1000', countCtrl),
              _buildModalInput('Average Weight (g)', 'e.g. 2.5', weightCtrl),
              _buildModalInput('Average Length (cm)', 'e.g. 3.0', lengthCtrl),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    // TankService.instance.updateSetup(
                    //   int.parse(countCtrl.text),
                    //   double.parse(weightCtrl.text),
                    //   double.parse(lengthCtrl.text)
                    // );

                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          isEdit ? 'Setup updated!' : 'Setup initialized!',
                        ),
                      ),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Save Setup',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        );
      },
    );
  }

  void _showMortalityModal() {
    final countCtrl = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom,
            left: 20,
            right: 20,
            top: 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.darkWith(0.1),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Log Mortality',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppColors.critical,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Record the number of dead crayfish found in the tank.',
                style: TextStyle(fontSize: 12, color: AppColors.darkWith(0.5)),
              ),
              const SizedBox(height: 20),
              _buildModalInput('Number of Dead Crayfish', 'e.g. 5', countCtrl),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    if (countCtrl.text.isNotEmpty) {
                      // TankService.instance.addMortality(int.parse(countCtrl.text));

                      Navigator.pop(ctx);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Mortality successfully logged.'),
                        ),
                      );
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.critical,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Confirm Logging',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
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
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.darkWith(0.1),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Activity Logs',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppColors.dark,
                ),
              ),
              const SizedBox(height: 16),
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
                      Icons.warning,
                      'Mortality: 2 recorded',
                      'Yesterday, 8:00 AM',
                      AppColors.critical,
                    ),
                  ],
                ),
              ),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Close'),
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
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: controller,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              hintText: hint,
              filled: true,
              fillColor: AppColors.darkWith(0.03),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 14,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: AppColors.darkWith(0.1)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: AppColors.darkWith(0.1)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.primary),
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
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.darkWith(0.02),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.darkWith(0.05)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 18, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.darkWith(0.5),
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
