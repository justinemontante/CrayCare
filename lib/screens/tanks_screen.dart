import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_colors.dart';
import '../models/crayfish_stage.dart';
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
            width: 36,
            height: 36,
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  isSuccess ? 'Success' : 'Error',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                    color: Colors.white,
                  ),
                ),
                Text(
                  message,
                  style: TextStyle(
                    fontWeight: FontWeight.w500,
                    fontSize: 11,
                    color: Colors.white.withValues(alpha: 0.9),
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.close_rounded,
              color: Colors.white,
              size: 16,
            ),
          ),
        ],
      ),
      backgroundColor: isSuccess
          ? const Color(0xFF059669)
          : const Color(0xFFDC2626),
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 12,
      duration: const Duration(seconds: 3),
    ),
  );
}

class TanksScreen extends StatefulWidget {
  const TanksScreen({super.key});

  @override
  State<TanksScreen> createState() => TanksScreenState();
}

class TanksScreenState extends State<TanksScreen> {
  int _activeTab = 0;
  DateTime _lastEdited = DateTime.now();

  void switchToTab(int index) {
    if (index < 0 || index > 2) return;
    setState(() => _activeTab = index);
  }
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
                  lastEdited: _lastEdited,
                  sampleCountController: _sampleCountController,
                  sampleWeightController: _sampleWeightController,
                  sampleLengthController: _sampleLengthController,
                ),
                TrendsTab(
                  lastEdited: _lastEdited,
                  onInfoTap: _showGrowthStageReferenceModal,
                ),
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
    final scrollCtrl = ScrollController();
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
                SizedBox(
                  width: double.infinity,
                  child: Scrollbar(
                    controller: scrollCtrl,
                    thumbVisibility: true,
                    child: SingleChildScrollView(
                      controller: scrollCtrl,
                      scrollDirection: Axis.horizontal,
                      child: Container(
                        constraints: BoxConstraints(
                          minWidth: MediaQuery.of(context).size.width - 40,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: AppColors.dark.withValues(alpha: 0.08),
                          ),
                          color: Colors.white,
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.primary.withValues(
                                  alpha: 0.06,
                                ),
                                borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(15),
                                ),
                              ),
                              child: const Row(
                                children: [
                                  SizedBox(width: 16),
                                  SizedBox(
                                    width: 130,
                                    child: Text(
                                      'Growth Stage',
                                      style: _tableHeaderStyle,
                                    ),
                                  ),
                                  SizedBox(width: 24),
                                  SizedBox(
                                    width: 160,
                                    child: Text(
                                      'Average Length (cm)',
                                      style: _tableHeaderStyle,
                                    ),
                                  ),
                                  SizedBox(width: 24),
                                  SizedBox(
                                    width: 160,
                                    child: Text(
                                      'Average Weight (g)',
                                      style: _tableHeaderStyle,
                                    ),
                                  ),
                                  SizedBox(width: 24),
                                  SizedBox(
                                    width: 220,
                                    child: Text(
                                      'System Classification',
                                      style: _tableHeaderStyle,
                                    ),
                                  ),
                                  SizedBox(width: 16),
                                ],
                              ),
                            ),
                            for (var i = 0; i < CrayfishStage.all.length; i++)
                              _buildTableRow(
                                CrayfishStage.all[i].label,
                                CrayfishStage.all[i].lengthRange,
                                CrayfishStage.all[i].weightRange,
                                CrayfishStage.all[i].description,
                                isStriped: i.isOdd,
                                isLast: i == CrayfishStage.all.length - 1,
                              ),
                          ],
                        ),
                      ),
                    ),
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
    ).whenComplete(() => scrollCtrl.dispose());
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
    String weight,
    String classification, {
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
          const SizedBox(width: 16),
          SizedBox(
            width: 130,
            child: Text(
              stage,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppColors.dark,
              ),
            ),
          ),
          const SizedBox(width: 24),
          SizedBox(
            width: 160,
            child: Text(
              length,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.dark,
              ),
            ),
          ),
          const SizedBox(width: 24),
          SizedBox(
            width: 160,
            child: Text(
              weight,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.dark,
              ),
            ),
          ),
          const SizedBox(width: 24),
          SizedBox(
            width: 220,
            child: Text(
              classification,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: AppColors.dark.withValues(alpha: 0.55),
              ),
            ),
          ),
          const SizedBox(width: 16),
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
          ? (TankService.instance.initialWeight *
                    TankService.instance.sampleCount)
                .toStringAsFixed(1)
          : '',
    );
    final totalLengthCtrl = TextEditingController(
      text: isEdit
          ? (TankService.instance.initialLength *
                    TankService.instance.sampleCount)
                .toStringAsFixed(1)
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
        return StatefulBuilder(
          builder: (ctx, setLocalState) {
            String? validateSample() {
              final pop = int.tryParse(countCtrl.text) ?? 0;
              final sample = int.tryParse(sampleCountCtrl.text) ?? 0;
              if (sample > 0 && pop > 0 && sample > pop) {
                return 'Sample count ($sample) exceeds population ($pop).';
              }
              return null;
            }

            final sampleError = validateSample();

            void revalidate() {
              setLocalState(() {});
            }

            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(ctx).viewInsets.bottom,
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                child: Column(
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
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            Icons.tune_rounded,
                            size: 22,
                            color: AppColors.primary,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              isEdit
                                  ? 'Edit Initialization'
                                  : 'Grow-Out Initialization',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                                color: AppColors.dark,
                              ),
                            ),
                            Text(
                              isEdit
                                  ? 'Update your tank setup data'
                                  : 'Set up your tank for the first time',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                                color: AppColors.dark.withValues(alpha: 0.5),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    _buildInfoCard(
                      Image.asset(
                        'assets/images/InitialPopulation.png',
                        width: 24,
                        height: 24,
                      ),
                      'Initial Population',
                      'Total stock count upon start',
                      countCtrl,
                      onChanged: revalidate,
                    ),
                    _buildInfoCard(
                      Image.asset(
                        'assets/images/SampleCount.png',
                        width: 24,
                        height: 24,
                      ),
                      'Sample Count',
                      'Number of crayfish sampled',
                      sampleCountCtrl,
                      errorText: sampleError,
                      onChanged: revalidate,
                    ),
                    _buildInfoCard(
                      Image.asset(
                        'assets/images/TotalWeight.png',
                        width: 24,
                        height: 24,
                      ),
                      'Total Weight (g)',
                      'Sum weight of sampled group',
                      totalWeightCtrl,
                    ),
                    _buildInfoCard(
                      Image.asset(
                        'assets/images/TotalLength.png',
                        width: 24,
                        height: 24,
                      ),
                      'Total Length (cm)',
                      'Sum length of sampled group',
                      totalLengthCtrl,
                    ),

                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: sampleError != null
                            ? null
                            : () async {
                                final count = int.tryParse(countCtrl.text) ?? 0;
                                final sampleCount =
                                    int.tryParse(sampleCountCtrl.text) ?? 0;
                                final totalWeight =
                                    double.tryParse(totalWeightCtrl.text) ??
                                    0.0;
                                final totalLength =
                                    double.tryParse(totalLengthCtrl.text) ??
                                    0.0;

                                if (count > 0 && sampleCount > 0) {
                                  await TankService.instance.initializeGrowOut(
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
                          backgroundColor: sampleError != null
                              ? AppColors.dark.withValues(alpha: 0.2)
                              : AppColors.primary,
                          foregroundColor: sampleError != null
                              ? Colors.white.withValues(alpha: 0.4)
                              : Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          elevation: 0,
                        ),
                        child: Text(
                          isEdit
                              ? 'Update Initialization'
                              : 'Initialize Grow-Out',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildInfoCard(
    Widget iconWidget,
    String title,
    String subtitle,
    TextEditingController controller, {
    String? errorText,
    VoidCallback? onChanged,
  }) {
    final hasError = errorText != null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: hasError
                          ? AppColors.critical.withValues(alpha: 0.12)
                          : AppColors.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: iconWidget,
                  ),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                          color: hasError ? AppColors.critical : AppColors.dark,
                        ),
                      ),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 9,
                          color: hasError
                              ? AppColors.critical.withValues(alpha: 0.6)
                              : AppColors.dark.withValues(alpha: 0.5),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const Spacer(),
              SizedBox(
                width: 100,
                child: TextField(
                  controller: controller,
                  onChanged: (_) => onChanged?.call(),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*$')),
                  ],
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                    color: hasError ? AppColors.critical : AppColors.primary,
                  ),
                  decoration: InputDecoration(
                    hintText: '0',
                    hintStyle: TextStyle(
                      color: hasError
                          ? AppColors.critical.withValues(alpha: 0.3)
                          : AppColors.dark.withValues(alpha: 0.2),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(
                        color: hasError
                            ? AppColors.critical.withValues(alpha: 0.6)
                            : AppColors.dark.withValues(alpha: 0.3),
                        width: 1.5,
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(
                        color: hasError
                            ? AppColors.critical.withValues(alpha: 0.6)
                            : AppColors.dark.withValues(alpha: 0.3),
                        width: 1.5,
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(
                        color: hasError
                            ? AppColors.critical
                            : AppColors.primary,
                        width: 1.5,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (hasError)
            Padding(
              padding: const EdgeInsets.only(top: 6, left: 4),
              child: Row(
                children: [
                  Icon(
                    Icons.error_outline_rounded,
                    size: 12,
                    color: AppColors.critical.withValues(alpha: 0.8),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      errorText,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: AppColors.critical.withValues(alpha: 0.8),
                        height: 1.3,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  void _showMortalityModal() {
    final countCtrl = TextEditingController();
    final liveCount = TankService.instance.liveCount;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocalState) {
            final mortalityVal = int.tryParse(countCtrl.text) ?? 0;
            final String? errorText = mortalityVal > liveCount
                ? 'Cannot exceed current live count ($liveCount).'
                : null;

            void revalidate() => setLocalState(() {});

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
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.favorite_rounded,
                          size: 14,
                          color: AppColors.primary,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Live count: $liveCount',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppColors.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildModalInput(
                    'Number of Dead Crayfish',
                    'e.g. 5',
                    countCtrl,
                    hasError: errorText != null,
                    onChanged: revalidate,
                  ),
                  if (errorText != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12, left: 4),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: AppColors.critical.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Icon(
                              Icons.error_outline_rounded,
                              size: 14,
                              color: AppColors.critical,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            errorText,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: AppColors.critical.withValues(alpha: 0.85),
                            ),
                          ),
                        ],
                      ),
                    ),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: errorText == null && mortalityVal > 0
                          ? () {
                              TankService.instance.addMortality(mortalityVal);
                              Navigator.pop(ctx);
                              showBeautifulSnackbar(
                                context,
                                'Mortality of $mortalityVal successfully logged.',
                                true,
                              );
                            }
                          : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: errorText != null
                            ? AppColors.dark.withValues(alpha: 0.2)
                            : AppColors.critical,
                        foregroundColor: errorText != null
                            ? Colors.white.withValues(alpha: 0.4)
                            : Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        elevation: 0,
                      ),
                      child: const Text(
                        'Confirm Logging',
                        style: TextStyle(
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
      },
    );
  }

  void _showLogsModal() {
    final activities = TankService.instance.activities.toList();

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) {
        final halfHeight = MediaQuery.of(context).size.height * 0.5;
        return SizedBox(
          height: halfHeight,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: Column(
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
                const SizedBox(height: 20),
                Row(
                  children: [
                    const Text(
                      'Activity Logs',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: AppColors.dark,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${activities.length} entries',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppColors.dark.withValues(alpha: 0.4),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (activities.isEmpty)
                  const Expanded(
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.receipt_long_rounded, size: 40),
                          SizedBox(height: 12),
                          Text(
                            'No logs yet',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  Expanded(
                    child: ListView.separated(
                      itemCount: activities.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 6),
                      itemBuilder: (_, i) {
                        final act = activities[i];
                        final isMortality = act.type == 'mortality';

                        IconData icon;
                        Color color;
                        switch (act.type) {
                          case 'init':
                            icon = Icons.inventory_2_rounded;
                            color = AppColors.primary;
                            break;
                          case 'mortality':
                            icon = Icons.warning_rounded;
                            color = AppColors.critical;
                            break;
                          case 'edit':
                            icon = Icons.edit_rounded;
                            color = AppColors.warning;
                            break;
                          case 'sampling':
                            icon = Icons.biotech_rounded;
                            color = AppColors.success;
                            break;
                          default:
                            icon = Icons.circle_rounded;
                            color = AppColors.darkWith(0.3);
                        }

                        return Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: isMortality
                                ? AppColors.criticalWith(0.04)
                                : AppColors.primaryWith(0.04),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isMortality
                                  ? AppColors.criticalWith(0.15)
                                  : AppColors.darkWith(0.06),
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  color: color.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Icon(icon, size: 18, color: color),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      act.action,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: AppColors.dark,
                                      ),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '${act.date} · ${act.time}',
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w500,
                                        color: AppColors.dark.withValues(
                                          alpha: 0.4,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: color.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  act.type == 'init'
                                      ? 'Initialization'
                                      : act.type[0].toUpperCase() +
                                            act.type.substring(1),
                                  style: TextStyle(
                                    fontSize: 8,
                                    fontWeight: FontWeight.w700,
                                    color: color,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(ctx),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 0,
                    ),
                    child: const Text(
                      'Close',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
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

  Widget _buildModalInput(
    String label,
    String hint,
    TextEditingController controller, {
    bool hasError = false,
    VoidCallback? onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: hasError ? AppColors.critical : AppColors.dark,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: controller,
            onChanged: (_) => onChanged?.call(),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*$')),
            ],
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: hasError ? AppColors.critical : AppColors.dark,
            ),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: TextStyle(
                color: hasError
                    ? AppColors.critical.withValues(alpha: 0.3)
                    : AppColors.dark.withValues(alpha: 0.3),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 14,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: hasError
                      ? AppColors.critical.withValues(alpha: 0.6)
                      : AppColors.dark.withValues(alpha: 0.5),
                  width: 1.5,
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: hasError
                      ? AppColors.critical.withValues(alpha: 0.6)
                      : AppColors.dark.withValues(alpha: 0.5),
                  width: 1.5,
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: hasError ? AppColors.critical : AppColors.primary,
                  width: 2,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
