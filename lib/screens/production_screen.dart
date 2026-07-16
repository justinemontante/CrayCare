import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_colors.dart';
import '../services/tank_service.dart';
import '../widgets/production/crayfish/crayfish_overview_tab.dart';
import '../widgets/production/crayfish/crayfish_sampling_tab.dart';
import '../widgets/production/crayfish/crayfish_trends_tab.dart';
import '../widgets/production/crayfish/crayfish_batch_list.dart';
import '../utils/snackbar_helper.dart';

class ProductionScreen extends StatefulWidget {
  const ProductionScreen({super.key});

  @override
  State<ProductionScreen> createState() => ProductionScreenState();
}

class ProductionScreenState extends State<ProductionScreen> {

  String _formatTimestamp(int ts) {
    final dt = DateTime.fromMillisecondsSinceEpoch(ts);
    final months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    final dateStr = '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
    final h = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
    final ampm = dt.hour >= 12 ? 'PM' : 'AM';
    final timeStr = '$h:${dt.minute.toString().padLeft(2, '0')} $ampm';
    return '$dateStr · $timeStr';
  }
  int _crayfishTab = 0; // 0 = Overview, 1 = Sampling, 2 = Growth

  DateTime _lastEdited = DateTime.now();

  void switchToTab(int index) {
    if (index > 2) return;
    setState(() => _crayfishTab = index);
  }

  @override
  void initState() {
    super.initState();
    TankService.instance.addListener(_refreshUI);
  }

  @override
  void dispose() {
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
          Expanded(
            child: _buildCrayfishContent(),
          ),
        ],
      ),
    );
  }

  Widget _buildCrayfishContent() {
    final selectedBatchId = TankService.instance.selectedBatchId;
    
    if (selectedBatchId == null) {
      return Column(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: CrayfishBatchList(
                onNewBatch: () => _showSetupForm(isEdit: false),
              ),
            ),
          ),
        ],
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            children: [
              GestureDetector(
                onTap: () => TankService.instance.selectBatch(null),
                child: Row(
                  children: [
                    Icon(Icons.arrow_back_ios_new_rounded, size: 14, color: AppColors.primary),
                    const SizedBox(width: 4),
                    Text('Batches', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.primary)),
                  ],
                ),
              ),
              const Spacer(),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: _buildCrayfishSubTabBar(),
        ),
        Expanded(
          child: _buildActiveCrayfishTab(),
        ),
      ],
    );
  }

  Widget _buildActiveCrayfishTab() {
    final batchKey = '${TankService.instance.selectedBatchId}_$_lastEdited';
    switch (_crayfishTab) {
      case 0:return OverviewTab(
          key: ValueKey('overview_$batchKey'),
          onShowInitModal: _showInitModal,
          onShowMortalityModal: _showMortalityModal,
          onShowEditModal: _showEditModal,
          onShowLogsModal: _showLogsModal,
          onShowCompleteBatchModal: _startNewBatch,
          hasSetup: TankService.instance.isInitialized,
          lastEdited: _lastEdited,
        );
      case 1:
        return SamplingTab(
          key: ValueKey('sampling_$batchKey'),
          lastEdited: _lastEdited,
        );
      case 2:
        return TrendsTab(
          key: ValueKey('trends_$batchKey'),
          lastEdited: _lastEdited,
          onInfoTap: _showGrowthStageReferenceModal,
        );
      default:
        return const SizedBox.shrink();
    }
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
                      'Tank Management',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: AppColors.dark,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Container(
                          width: 8, height: 8,
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Tank',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: AppColors.dark.withValues(alpha: 0.55),
                          ),
                        ),
                      ],
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

  Widget _buildCrayfishSubTabBar() {
    final subTabs = [
      (Icons.dashboard_rounded, 'Overview'),
      (Icons.speed_outlined, 'Sampling'),
      (Icons.trending_up_rounded, 'Growth'),
    ];
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.dark.withValues(alpha: 0.02),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          ...List.generate(subTabs.length, (i) {
            final isActive = _crayfishTab == i;
            return Expanded(
              child: GestureDetector(
                onTap: () => setState(() => _crayfishTab = i),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: isActive ? Colors.white : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: isActive
                        ? [
                            BoxShadow(
                              color: AppColors.dark.withValues(alpha: 0.04),
                              blurRadius: 6,
                              offset: const Offset(0, 1),
                            ),
                          ]
                        : null,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        subTabs[i].$1,
                        size: 13,
                        color: isActive
                            ? AppColors.primary
                            : AppColors.dark.withValues(alpha: 0.45),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        subTabs[i].$2,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: isActive
                              ? AppColors.primary
                              : AppColors.dark.withValues(alpha: 0.45),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
        ],
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
                          minWidth: 510,
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
                                  SizedBox(width: 12),
                                  SizedBox(
                                    width: 120,
                                    child: Text('Growth Stage', style: _tableHeaderStyle),
                                  ),
                                  SizedBox(width: 12),
                                  SizedBox(
                                    width: 65,
                                    child: Text('ABW', style: _tableHeaderStyle),
                                  ),
                                  SizedBox(width: 12),
                                  SizedBox(
                                    width: 65,
                                    child: Text('ABL', style: _tableHeaderStyle),
                                  ),
                                  SizedBox(width: 12),
                                  SizedBox(
                                    width: 200,
                                    child: Text('System Classification', style: _tableHeaderStyle),
                                  ),
                                  SizedBox(width: 12),
                                ],
                              ),
                            ),
                            for (var i = 0; i < _stageLabels.length; i++)
                              _buildTableRow(
                                _stageLabels[i],
                                _stageAbwRanges[i],
                                _stageAblRanges[i],
                                _stageDescriptions[i],
                                isStriped: i.isOdd,
                                isLast: i == _stageLabels.length - 1,
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
                      backgroundColor: AppColors.primary,
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

  static const _stageLabels = [
    'Early Juvenile',
    'Advanced Juvenile',
    'Pre-Adult',
    'Market Size',
  ];
  static const _stageDescriptions = [
    'Newly stocked young crayfish',
    'Active early growth',
    'Preparing for full maturity',
    'Ready for harvest',
  ];
  static const _stageAbwRanges = ['1\u20135g', '5\u201315g', '15\u201350g', '50\u2013120g+'];
  static const _stageAblRanges = ['2\u20134cm', '4\u20136cm', '6\u201310cm', '10cm+'];

  static const _tableHeaderStyle = TextStyle(
    fontSize: 9,
    fontWeight: FontWeight.w800,
    color: AppColors.primary,
    letterSpacing: 0.8,
  );

  Widget _buildTableRow(
    String stage,
    String abw,
    String abl,
    String classification, {
    required bool isStriped,
    bool isLast = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
          const SizedBox(width: 12),
          SizedBox(
            width: 120,
            child: Text(stage, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.dark)),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 65,
            child: Text(abw, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.primary)),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 65,
            child: Text(abl, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.primary)),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 200,
            child: Text(classification, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: AppColors.dark.withValues(alpha: 0.55))),
          ),
          const SizedBox(width: 12),
        ],
      ),
    );
  }

  void _showInitModal() => _showSetupForm(isEdit: false);

  void _startNewBatch() {
    _showSetupForm(isEdit: false);
  }

  void _showEditModal() {
    if (TankService.instance.samplingHistory.isNotEmpty) {
      showBeautifulSnackbar(
        context,
        'Initial setup data can no longer be modified because sampling records already exist.',
        false,
      );
      return;
    }
    _showSetupForm(isEdit: true);
  }

  void _showSetupForm({required bool isEdit}) {
    final batchNameCtrl = TextEditingController(
      text: isEdit ? (TankService.instance.selectedBatch?.batchId ?? '') : '',
    );
    final countCtrl = TextEditingController(
      text: isEdit ? '${TankService.instance.initialCount}' : '',
    );
    final sampleCountCtrl = TextEditingController(
      text: isEdit ? '${TankService.instance.sampleCount}' : '',
    );
    final totalWeightCtrl = TextEditingController(
      text: isEdit
          ? TankService.instance.initialTotalWeight.toStringAsFixed(1)
          : '',
    );
    final totalLengthCtrl = TextEditingController(
      text: isEdit
          ? TankService.instance.initialTotalLength.toStringAsFixed(1)
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
            bool isSaving = false;

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
                    _buildBatchNameField(batchNameCtrl),
                    const SizedBox(height: 4),
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
                      'Sample Size',
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
                      'Initial Total\nSample Weight (g)',
                      'Total weight of sampled group',
                      totalWeightCtrl,
                    ),
                    _buildInfoCard(
                      Image.asset(
                        'assets/images/TotalLength.png',
                        width: 24,
                        height: 24,
                      ),
                      'Initial Total\nSample Length (cm)',
                      'Total length of sampled group',
                      totalLengthCtrl,
                    ),

                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: (sampleError != null || isSaving)
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
                                  setLocalState(() => isSaving = true);
                                  try {
                                    if (TankService.instance.isInitialized && !TankService.instance.isArchiveView) {
                                      await TankService.instance.completeBatch(
                                        harvestCount: 0,
                                        harvestWeightGrams: null,
                                      );
                                    }
                                    await TankService.instance.initializeGrowOut(
                                      count,
                                      sampleCount,
                                      totalWeight,
                                      totalLength,
                                      DateTime.now(),
                                      batchName: batchNameCtrl.text.trim(),
                                    );
                                  } catch (e) {
                                    setLocalState(() => isSaving = false);
                                    if (ctx.mounted) {
                                      showBeautifulSnackbar(
                                        ctx,
                                        e.toString().replaceFirst('Exception: ', ''),
                                        false,
                                      );
                                    }
                                    return;
                                  }
                                  if (ctx.mounted) Navigator.pop(ctx);
                                  if (mounted) {
                                    showBeautifulSnackbar(
                                      context,
                                      isEdit
                                          ? 'Setup beautifully updated!'
                                          : 'Grow-out successfully initialized!',
                                      true,
                                    );
                                  }
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
                        child: isSaving
                            ? const SizedBox(
                                height: 18,
                                width: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : Text(
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

  Widget _buildBatchNameField(TextEditingController controller) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Text(
              'Batch Name',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 11,
                color: AppColors.dark.withValues(alpha: 0.7),
              ),
            ),
          ),
          TextField(
            controller: controller,
            textCapitalization: TextCapitalization.words,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppColors.dark,
            ),
            decoration: InputDecoration(
              hintText: 'e.g. Spring Batch 2026',
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
    final liveCount = TankService.instance.inTankCount;

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
                  const SizedBox(height: 12),
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
                        final isHarvest = act.type == 'harvest';

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
                          case 'harvest':
                            icon = Icons.archive_rounded;
                            color = AppColors.success;
                            break;
                          default:
                            icon = Icons.circle_rounded;
                            color = AppColors.darkWith(0.3);
                        }

                        return Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: isHarvest
                                ? AppColors.success.withValues(alpha: 0.06)
                                : isMortality
                                    ? AppColors.criticalWith(0.04)
                                    : AppColors.primaryWith(0.04),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isHarvest
                                  ? AppColors.success.withValues(alpha: 0.2)
                                  : isMortality
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
                                    if (act.abw != null && act.avgLength != null)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 3),
                                        child: Text(
                                          'ABW: ${act.abw!.toStringAsFixed(2)}g  |  ABL: ${act.avgLength!.toStringAsFixed(2)}cm',
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w700,
                                            color: AppColors.success,
                                          ),
                                        ),
                                      ),
                                    Text(
                                      act.date.isNotEmpty ? '${act.date} Â· ${act.time}' : _formatTimestamp(act.timestamp),
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
    bool isText = false,
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
            keyboardType: isText ? TextInputType.text : const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: isText ? null : [
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


