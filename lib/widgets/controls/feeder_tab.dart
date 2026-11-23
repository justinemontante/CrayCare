import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../theme/app_colors.dart';
import '../../models/control_types.dart';
import '../../utils/snackbar_helper.dart';
import '../../services/tank_service.dart';
import '../../utils/feeding_progress.dart';

class FeederRecommendation {
  final int inTankCount;
  final double abw;
  final double totalBiomassGrams;
  final double dailyRationGrams;
  final double perFeedingGrams;
  final bool hasData;

  const FeederRecommendation({
    required this.inTankCount,
    required this.abw,
    required this.totalBiomassGrams,
    required this.dailyRationGrams,
    required this.perFeedingGrams,
    required this.hasData,
  });

  static FeederRecommendation compute() {
    final tank = TankService.instance;
    final history = tank.samplingHistory;
    final weekly = history.where((e) => !e.isBaseline).toList();
    final latest = weekly.isNotEmpty ? weekly.last : null;
    final abw = latest != null ? latest.abw : tank.initialWeight;
    final inTank = tank.inTankCount;

    if (inTank <= 0 || abw <= 0) {
      return const FeederRecommendation(
        inTankCount: 0,
        abw: 0.0,
        totalBiomassGrams: 0.0,
        dailyRationGrams: 0.0,
        perFeedingGrams: 0.0,
        hasData: false,
      );
    }

    final totalBiomass = inTank * abw;
    // 5% biomass rule (Cheng et al., 2025). The ESP32 delivers whole grams,
    // 1–200 g per feeding, so clamp the dose first and derive the daily ration
    // from it — otherwise the card and breakdown show mismatched totals.
    final perFeed =
        (totalBiomass * 0.05 / 2).roundToDouble().clamp(1.0, 200.0);
    final dailyRation = perFeed * 2;

    return FeederRecommendation(
      inTankCount: inTank,
      abw: abw,
      totalBiomassGrams: totalBiomass,
      dailyRationGrams: dailyRation,
      perFeedingGrams: perFeed,
      hasData: true,
    );
  }
}

class FeederTab extends StatelessWidget {
  // Feeder schedules are anchored to Asia/Manila wall-clock time to match the
  // ESP32's NTP-synced clock and the Cloud Function's MANILA_OFFSET_MS. Using
  // DateTime.now() here compares against the device timezone, which can cause
  // false "missed"/"completed" states when the phone is abroad.
  static DateTime _manilaNow() => manilaWallClock();

  final List<ScheduleItem> schedules;
  final TextEditingController timeCtl;
  final VoidCallback onFeedNow;
  final Future<bool> Function(double grams, String days) onAddSchedule;
  final void Function(int index) onDeleteSchedule;
  final Future<bool> Function(int index, ScheduleItem item) onEditSchedule;
  final void Function(int index, bool enabled) onToggleSchedule;
  final List<LogEntry> feederLogs;
  final Set<String> fedToday;

  final bool isOnline;
  final bool isRunning;
  final bool canFeed;
  final String feedBlockedReason;
  final double? feedLevelPercent;
  final String? feedLevelZone;
  final double estimatedConsumptionToday;
  final List<String> waterQualityWarnings;

  const FeederTab({
    super.key,
    required this.schedules,
    required this.timeCtl,
    required this.onFeedNow,
    required this.onAddSchedule,
    required this.onDeleteSchedule,
    required this.onEditSchedule,
    required this.onToggleSchedule,
    required this.feederLogs,
    this.fedToday = const {},
    this.isOnline = true,
    this.isRunning = false,
    this.canFeed = true,
    this.feedBlockedReason = '',
    this.feedLevelPercent,
    this.feedLevelZone,
    this.estimatedConsumptionToday = 0,
    this.waterQualityWarnings = const [],
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: TankService.instance,
      builder: (context, _) {
        final rec = FeederRecommendation.compute();
        final batch = TankService.instance.selectedBatch;
        DateTime? batchStart;
        DateTime? batchEndExclusive;
        if (batch != null) {
          batchStart = feedingManilaDate(batch.stockingDate);
          final endRaw = batch.harvestDate ?? batch.endedAt;
          if (endRaw != null) {
            batchEndExclusive = feedingManilaDate(endRaw).add(
              const Duration(days: 1),
            );
          }
        }
        final progress = rec.hasData
            ? computeFeedingProgress(
                recommendedGrams: rec.perFeedingGrams,
                logs: feederLogs,
                now: _manilaNow(),
                batchStart: batchStart,
                batchEndExclusive: batchEndExclusive,
              )
            : null;
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
          child: _buildFeederCardBody(context, rec, progress),
        );
      },
    );
  }

  Widget _buildFeederCardBody(
    BuildContext ctx,
    FeederRecommendation rec,
    FeedingProgress? progress,
  ) {
    final daytime = schedules.where((s) {
      final minutes = feederScheduleMinutes(s);
      return minutes >= 6 * 60 && minutes < 18 * 60;
    }).toList();
    final nighttime = schedules.where((s) {
      final minutes = feederScheduleMinutes(s);
      return minutes < 6 * 60 || minutes >= 18 * 60;
    }).toList();
    final hasEnabledSchedules = schedules.any((s) => s.enabled);

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFFCFCFC),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.darkWith(0.15), width: 1.5),
        boxShadow: AppShadows.card,
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: Image.asset(
                      'assets/images/FeedingImage.png',
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'Automatic Feeder',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: AppColors.dark,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          GestureDetector(
                            onTap: () => _showFeederLog(ctx),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.primary.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.history,
                                    size: 11,
                                    color: AppColors.primary,
                                  ),
                                  SizedBox(width: 3),
                                  Text(
                                    'Log',
                                    style: TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.primary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Container(
                            width: 7,
                            height: 7,
                            decoration: BoxDecoration(
                              color: hasEnabledSchedules
                                  ? AppColors.success
                                  : AppColors.darkWith(0.3),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 5),
                          Text(
                            schedules.isEmpty
                                ? 'Auto Mode • No Schedules'
                                : hasEnabledSchedules
                                ? 'Auto Mode • Ready'
                                : 'Auto Mode • Paused',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w600,
                              color: hasEnabledSchedules
                                  ? AppColors.success
                                  : AppColors.darkWith(0.4),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _buildFeedInventorySummary(),
            const SizedBox(height: 10),
            _buildFeedingRecommendationCard(ctx, rec, progress),
            if (schedules.isNotEmpty) ...[
              const SizedBox(height: 10),
              _buildCountdown(),
            ],
            const SizedBox(height: 12),
            _buildFeedNowButton(ctx),
            if (waterQualityWarnings.isNotEmpty) ...[
              const SizedBox(height: 10),
              _buildWaterQualityWarning(),
            ],
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Schedules:',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppColors.dark,
                  ),
                ),
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => _showScheduleModal(ctx),
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 9,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.add, size: 10, color: AppColors.primary),
                          SizedBox(width: 4),
                          Text(
                            'Add Schedule',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              color: AppColors.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            if (schedules.isNotEmpty) ...[
              const SizedBox(height: 10),
              _buildSchedulePeriod(
                ctx,
                'Daytime',
                Icons.wb_sunny_outlined,
                daytime,
              ),
              const SizedBox(height: 12),
              _buildSchedulePeriod(
                ctx,
                'Night',
                Icons.nightlight_outlined,
                nighttime,
              ),
            ] else
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.darkWith(0.03),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      Icon(
                        Icons.schedule_send_outlined,
                        size: 28,
                        color: AppColors.darkWith(0.2),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'No schedules yet',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.darkWith(0.4),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Tap above to add a feeding schedule',
                        style: TextStyle(
                          fontSize: 10,
                          color: AppColors.darkWith(0.3),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildFeedingRecommendationCard(
    BuildContext ctx,
    FeederRecommendation rec,
    FeedingProgress? progress,
  ) {
    if (!rec.hasData) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.faintBorder),
        ),
        child: Row(
          children: [
            Icon(
              Icons.scale_rounded,
              size: 16,
              color: AppColors.darkWith(0.35),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Record crayfish sampling and stocking data to activate live 5% biomass feeding recommendations.',
                style: TextStyle(
                  fontSize: 9,
                  color: AppColors.subtitleText,
                  height: 1.3,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.faintBorder),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: AppColors.lightBg,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.scale_rounded,
                    size: 15,
                    color: AppColors.darkWith(0.7),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Feeding Recommendation',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: AppColors.dark,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        '5% of body weight',
                        style: TextStyle(
                          fontSize: 9,
                          color: AppColors.subtitleText,
                        ),
                      ),
                    ],
                  ),
                ),
                InkWell(
                  onTap: () => _showFeedingBreakdownModal(ctx, rec),
                  borderRadius: BorderRadius.circular(20),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(
                      Icons.help_outline_rounded,
                      size: 16,
                      color: AppColors.darkWith(0.3),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(height: 1, color: AppColors.faintBorder),
            const SizedBox(height: 12),
            // Two clear stats: the dose and how often. The farmer sets times.
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${rec.perFeedingGrams.toInt()} g',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: AppColors.primary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'per feeding',
                        style: TextStyle(
                          fontSize: 8,
                          color: AppColors.subtitleText,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(width: 1, height: 28, color: AppColors.faintBorder),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '2 times daily',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: AppColors.dark,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${rec.dailyRationGrams.round()} g total / day',
                        style: TextStyle(
                          fontSize: 8,
                          color: AppColors.subtitleText,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (progress != null) ...[
              const SizedBox(height: 10),
              Container(height: 1, color: AppColors.faintBorder),
              const SizedBox(height: 10),
              Text(
                'AM ${progress.morningDispensedGrams.toInt()}/'
                '${rec.perFeedingGrams.toInt()} g · PM '
                '${progress.eveningDispensedGrams.toInt()}/'
                '${rec.perFeedingGrams.toInt()} g',
                style: TextStyle(
                  fontSize: 8,
                  color: AppColors.subtitleText,
                  height: 1.3,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _showFeedingBreakdownModal(
    BuildContext ctx,
    FeederRecommendation rec,
  ) {
    showModalBottomSheet(
      context: ctx,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      sheetAnimationStyle: const AnimationStyle(
        duration: Duration(milliseconds: 260),
        reverseDuration: Duration(milliseconds: 220),
      ),
      builder: (sheetCtx) {
        final rawDaily = rec.totalBiomassGrams * 0.05;
        final isCapped = (rawDaily - rec.dailyRationGrams).abs() > 0.01;
        return Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            10,
            20,
            24 + MediaQuery.of(sheetCtx).viewInsets.bottom,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                // Header
                Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: AppColors.lightBg,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      alignment: Alignment.center,
                      child: Icon(
                        Icons.calculate_outlined,
                        size: 20,
                        color: AppColors.darkWith(0.7),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Feeding Calculation',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: AppColors.dark,
                            ),
                          ),
                          Text(
                            '5% of body weight',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: AppColors.subtitleText,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, size: 20),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      color: AppColors.darkWith(0.4),
                      onPressed: () => Navigator.pop(sheetCtx),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                // Live Parameters Strip
                Text(
                  'CURRENT TANK PARAMETERS',
                  style: TextStyle(
                    fontSize: 8.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.3,
                    color: AppColors.darkWith(0.5),
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.darkWith(0.03),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: AppColors.darkWith(0.08),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'LIVE STOCK',
                              style: TextStyle(
                                fontSize: 7.5,
                                fontWeight: FontWeight.w700,
                                color: AppColors.darkWith(0.4),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${rec.inTankCount} pcs',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: AppColors.dark,
                              ),
                            ),
                            Text(
                              'Initial − Mortality',
                              style: TextStyle(
                                fontSize: 7.5,
                                color: AppColors.darkWith(0.35),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        height: 28,
                        width: 1,
                        color: AppColors.darkWith(0.08),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'LATEST ABW',
                              style: TextStyle(
                                fontSize: 7.5,
                                fontWeight: FontWeight.w700,
                                color: AppColors.darkWith(0.4),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${rec.abw.toStringAsFixed(1)} g',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: AppColors.dark,
                              ),
                            ),
                            Text(
                              'Avg Body Weight',
                              style: TextStyle(
                                fontSize: 7.5,
                                color: AppColors.darkWith(0.35),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        height: 28,
                        width: 1,
                        color: AppColors.darkWith(0.08),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'EST. BIOMASS',
                              style: TextStyle(
                                fontSize: 7.5,
                                fontWeight: FontWeight.w700,
                                color: AppColors.darkWith(0.4),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${(rec.totalBiomassGrams / 1000).toStringAsFixed(2)} kg',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: AppColors.primary,
                              ),
                            ),
                            Text(
                              '${rec.totalBiomassGrams.toStringAsFixed(1)} g total',
                              style: TextStyle(
                                fontSize: 7.5,
                                color: AppColors.darkWith(0.35),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                // Step-by-Step Calculation
                Text(
                  'STEP-BY-STEP CALCULATION',
                  style: TextStyle(
                    fontSize: 8.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.3,
                    color: AppColors.darkWith(0.5),
                  ),
                ),
                const SizedBox(height: 8),
                _buildComputationStepRow(
                  stepNum: '1',
                  title: 'Total Biomass',
                  formula: 'Population × ABW',
                  computation:
                      '${rec.inTankCount} pcs × ${rec.abw.toStringAsFixed(1)}g = ${rec.totalBiomassGrams.toStringAsFixed(1)} g',
                ),
                const SizedBox(height: 8),
                _buildComputationStepRow(
                  stepNum: '2',
                  title: 'Daily Feed (5%)',
                  formula: 'Biomass × 0.05',
                  computation:
                      isCapped
                          ? '${rawDaily.toStringAsFixed(1)}g × 0.05 → ${rec.dailyRationGrams.toStringAsFixed(1)} g / day (capped)'
                          : '${rawDaily.toStringAsFixed(1)}g × 0.05 = ${rec.dailyRationGrams.toStringAsFixed(1)} g / day',
                ),
                const SizedBox(height: 8),
                _buildComputationStepRow(
                  stepNum: '3',
                  title: 'Dose per Feed',
                  formula: '2 times daily',
                  computation:
                      '${rec.dailyRationGrams.toStringAsFixed(1)}g ÷ 2 = ${(rec.dailyRationGrams / 2).toStringAsFixed(1)}g → ${rec.perFeedingGrams.toInt()} g',
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(sheetCtx),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: const Text(
                      'Got It',
                      style: TextStyle(
                        fontSize: 12.5,
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

  Widget _buildComputationStepRow({
    required String stepNum,
    required String title,
    required String formula,
    required String computation,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: AppColors.darkWith(0.08),
          width: 1.0,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.darkWith(0.1),
            ),
            alignment: Alignment.center,
            child: Text(
              stepNum,
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w800,
                color: AppColors.darkWith(0.6),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.dark,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      formula,
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w500,
                        color: AppColors.darkWith(0.45),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    computation,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: AppColors.darkWith(0.7),
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

  Widget _buildWaterQualityWarning() {
    const staleSuffix = ' reading is stale or unavailable';
    final staleSensors = <String>[];
    final otherWarnings = <String>[];
    for (final warning in waterQualityWarnings) {
      if (warning.endsWith(staleSuffix)) {
        staleSensors.add(
          warning.substring(0, warning.length - staleSuffix.length),
        );
      } else {
        otherWarnings.add(warning);
      }
    }

    final sensorNames = staleSensors.map((sensor) {
      switch (sensor) {
        case 'Temperature':
          return 'temperature';
        case 'Dissolved oxygen':
          return 'dissolved oxygen';
        case 'pH':
          return 'pH';
        case 'Turbidity':
          return 'turbidity';
        default:
          return sensor;
      }
    }).toList();
    String joinNames(List<String> names) {
      if (names.length < 2) return names.first;
      if (names.length == 2) return '${names[0]} and ${names[1]}';
      return '${names.sublist(0, names.length - 1).join(', ')}, and ${names.last}';
    }

    final displayWarnings = [
      if (sensorNames.isNotEmpty)
        'No recent readings are available for ${joinNames(sensorNames)}.',
      ...otherWarnings,
    ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.warning_amber_rounded,
                size: 16,
                color: AppColors.warning,
              ),
              const SizedBox(width: 6),
              const Text(
                'Water-quality warning',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: AppColors.dark,
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          ...displayWarnings.map(
            (warning) => Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                '• $warning',
                style: TextStyle(
                  fontSize: 9,
                  height: 1.25,
                  color: AppColors.darkWith(0.7),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeedInventorySummary() {
    final level = feedLevelPercent;
    final zone = feedLevelZone;

    Color levelColor = AppColors.darkWith(0.35);
    String levelLabel = 'Waiting for sensor';
    if (level != null) {
      switch (zone) {
        case 'EMPTY':
          levelColor = AppColors.critical;
          levelLabel = 'EMPTY';
        case 'CRITICAL':
          levelColor = AppColors.critical;
          levelLabel = 'CRITICAL';
        case 'WARNING':
          levelColor = AppColors.warning;
          levelLabel = 'LOW';
        case 'OPTIMAL':
          levelColor = AppColors.success;
          levelLabel = 'NORMAL';
        default:
          levelLabel = 'UNKNOWN';
      }
    }

    final isCritical = zone == 'CRITICAL' || zone == 'EMPTY';
    final isLow = isCritical || zone == 'WARNING';
    final hasKnownStatus = const {
      'EMPTY',
      'CRITICAL',
      'WARNING',
      'OPTIMAL',
    }.contains(zone);
    final availabilityText = level == null
        ? 'Waiting for a feed-level sensor reading'
        : !hasKnownStatus
        ? 'Feed-level status is unavailable.'
        : isCritical
        ? 'Critical feed level. Feeding is blocked until the hopper is refilled.'
        : isLow
        ? 'Feed level is low. Refill the hopper soon.'
        : 'Feed level is within the configured operating range.';
    final availabilityColor = level == null || !hasKnownStatus
        ? AppColors.darkWith(0.45)
        : isCritical
        ? AppColors.critical
        : isLow
        ? AppColors.warning
        : AppColors.success;
    final availabilityIcon = level == null || !hasKnownStatus
        ? Icons.sensors_off_outlined
        : isCritical
        ? Icons.error_outline_rounded
        : isLow
        ? Icons.inventory_outlined
        : Icons.check_circle_outline;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.faintBorder),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _inventoryMetric(
                  Icons.inventory_2_outlined,
                  'Feed Level',
                  level == null ? '--' : '${level.toStringAsFixed(0)}%',
                  levelLabel,
                  levelColor,
                ),
              ),
              Container(width: 1, height: 46, color: AppColors.darkWith(0.08)),
              Expanded(
                child: _inventoryMetric(
                  Icons.scale_outlined,
                  'Est. consumption today',
                  '~${estimatedConsumptionToday.toStringAsFixed(1)} g',
                  '',
                  AppColors.primary,
                ),
              ),
            ],
          ),
          if (level == null || isLow) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: availabilityColor.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Icon(availabilityIcon, size: 14, color: availabilityColor),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      availabilityText,
                      style: TextStyle(
                        fontSize: 9,
                        height: 1.3,
                        fontWeight: FontWeight.w700,
                        color: availabilityColor,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _inventoryMetric(
    IconData icon,
    String label,
    String value,
    String detail,
    Color color,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 7),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, size: 16, color: color),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 8,
                    color: AppColors.darkWith(0.45),
                  ),
                ),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    color: AppColors.dark,
                  ),
                ),
                if (detail.isNotEmpty)
                  Text(
                    detail,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 8,
                      fontWeight: FontWeight.w600,
                      color: color,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeedNowButton(BuildContext context) {
    final enabled = isOnline && !isRunning && canFeed;
    return SizedBox(
      width: double.infinity,
      child: Tooltip(
        message: !canFeed && isOnline ? feedBlockedReason : '',
        decoration: BoxDecoration(
          color: AppColors.critical,
          borderRadius: BorderRadius.circular(8),
        ),
        textStyle: const TextStyle(fontSize: 12, color: Colors.white),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        waitDuration: const Duration(milliseconds: 100),
        child: ElevatedButton(
          onPressed: enabled
              ? onFeedNow
              : () {
                  if (!isOnline) {
                    showBeautifulSnackbar(
                      context,
                      'Feeder is offline. Cannot dispense feed.',
                      false,
                      title: 'Feeder Offline',
                    );
                  } else if (!canFeed) {
                    showBeautifulSnackbar(
                      context,
                      feedBlockedReason,
                      false,
                      title: 'Feed Blocked',
                    );
                  }
                },
          style: ElevatedButton.styleFrom(
            backgroundColor: isOnline
                ? AppColors.primary
                : Colors.grey.shade300,
            foregroundColor: isOnline ? Colors.white : Colors.grey.shade500,
            padding: const EdgeInsets.symmetric(vertical: 11),
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                isRunning
                    ? Icons.hourglass_top
                    : !isOnline
                    ? Icons.wifi_off
                    : !canFeed
                    ? Icons.block
                    : Icons.play_arrow,
                size: 14,
                color: isOnline ? Colors.white : Colors.grey.shade500,
              ),
              const SizedBox(width: 6),
              Text(
                isRunning
                    ? 'Feeding...'
                    : !isOnline
                    ? 'Feeder Offline'
                    : !canFeed
                    ? 'Feed Blocked'
                    : 'Feed Now',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: isOnline ? Colors.white : Colors.grey.shade500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCountdown() {
    return StreamBuilder<int>(
      stream: Stream.periodic(const Duration(seconds: 1), (i) => i),
      builder: (context, _) {
        final now = _manilaNow();

        final statuses = <ScheduleItem, String>{
          for (final schedule in schedules) schedule: _scheduleStatus(schedule),
        };
        final nextOccurrence = nextEnabledFeeding(
          schedules,
          now,
          skipToday: (schedule) => const [
            'completed',
            'skipped',
            'failed',
          ].contains(statuses[schedule]),
        );
        final next = nextOccurrence?.schedule;
        final nextAt = nextOccurrence?.at;

        final bool noUpcoming = next == null || nextAt == null;

        String? display;
        String? scheduleLabel;
        if (!noUpcoming) {
          display = _formatDuration(nextAt.difference(now));
          scheduleLabel =
              '${next.time} ${next.ampm} • ${_scheduleDayLabel(nextAt, now)}';
        }

        return Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.darkWith(0.03),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(
                  noUpcoming ? Icons.info_outline : Icons.timer_outlined,
                  size: 14,
                  color: noUpcoming
                      ? AppColors.darkWith(0.4)
                      : AppColors.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    noUpcoming
                        ? 'No enabled feeding schedule'
                        : 'Next: $scheduleLabel',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                      color: AppColors.darkWith(0.6),
                    ),
                  ),
                ),
                if (display != null)
                  Text(
                    display,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: AppColors.dark,
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _formatDuration(Duration d) {
    final days = d.inDays;
    final h = d.inHours.remainder(24);
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    final parts = <String>[];
    if (days > 0) parts.add('${days}d');
    if (h > 0) parts.add('${h}h');
    parts.add('${m}m');
    parts.add('${s}s');
    return parts.join(' ');
  }

  String _scheduleDayLabel(DateTime target, DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    final targetDay = DateTime(target.year, target.month, target.day);
    final dayOffset = targetDay.difference(today).inDays;
    if (dayOffset == 0) return 'Today';
    if (dayOffset == 1) return 'Tomorrow';
    const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return weekdays[target.weekday - 1];
  }

  String _logDateString() {
    final now = _manilaNow();
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[now.month - 1]} ${now.day}, ${now.year}';
  }

  /// Converts a day mask ("1111111") into a readable label like
  /// "Every day", "Weekdays", or "Mon, Wed, Fri".
  String _formatDays(String days) {
    if (days.length < 7) return 'Every day';
    if (days == '1111111') return 'Every day';
    if (days == '0111110') return 'Weekdays';
    if (days == '1000001') return 'Weekends';
    final labels = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
    final parts = <String>[];
    for (var i = 0; i < 7; i++) {
      if (days[i] == '1') parts.add(labels[i]);
    }
    if (parts.isEmpty) return 'No days';
    return parts.join(', ');
  }

  String _scheduleStatus(ScheduleItem s) {
    if (!s.enabled) return 'disabled';
    // Not active today → show as "off today" (not due).
    final now = _manilaNow();
    if (!feederScheduleRunsOnDate(s, now)) return 'off_today';
    final outcome = feederRecordedOutcome(s, now, feederLogs);
    if (outcome != null) return outcome;
    final scheduleTimeStr = '${s.time} ${s.ampm}';
    final todayStr = _logDateString();
    for (final log in feederLogs) {
      if ((log.type == 'missed' || log.type == 'pending_confirmation') &&
          s.id != null &&
          log.scheduleKey == s.id &&
          log.scheduleTime == scheduleTimeStr &&
          log.date == todayStr) {
        return 'missed';
      }
    }
    final minutes = feederScheduleMinutes(s);
    final h = minutes ~/ 60;
    final m = minutes % 60;
    final scheduleDt = DateTime(now.year, now.month, now.day, h, m);
    if (!feederScheduleWasEffectiveAt(s, scheduleDt)) return 'upcoming';
    if (now.isBefore(scheduleDt)) return 'upcoming';
    return 'pending';
  }

  String _feedStatusLabel(String? status) {
    switch (status?.toLowerCase()) {
      case 'completed':
        return 'Completed';
      case 'forced':
        return 'Completed (schedule confirmed)';
      case 'blocked':
        return 'Blocked';
      case 'failed':
        return 'Failed';
      case 'skipped_insufficient':
        return 'Skipped (low feed level)';
      case 'pending_confirmation':
        return 'Needs confirmation';
      default:
        return status?.replaceAll('_', ' ') ?? '';
    }
  }

  Widget _buildSchedulePeriod(
    BuildContext ctx,
    String label,
    IconData icon,
    List<ScheduleItem> items,
  ) {
    const previewLimit = 2;
    final previewItems = items.take(previewLimit).toList();

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.darkWith(0.04),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(icon, size: 14, color: AppColors.primary),
                  const SizedBox(width: 6),
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppColors.dark,
                    ),
                  ),
                ],
              ),
              Text(
                '${items.length} schedule${items.length != 1 ? 's' : ''}',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: AppColors.darkWith(0.4),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (items.isEmpty)
            Container(
              padding: const EdgeInsets.all(8),
              child: Text(
                'No schedules set',
                style: TextStyle(fontSize: 10, color: AppColors.darkWith(0.3)),
              ),
            )
          else
            ...previewItems.map(
              (s) => _buildScheduleItem(ctx, schedules.indexOf(s), s),
            ),
          if (items.length > previewLimit) ...[
            const SizedBox(height: 4),
            SizedBox(
              width: double.infinity,
              child: TextButton.icon(
                onPressed: () => _showAllSchedules(ctx, label, icon, items),
                icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 16),
                label: Text('View all ${items.length} schedules'),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  backgroundColor: AppColors.primary.withValues(alpha: 0.07),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  textStyle: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(9),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _showAllSchedules(
    BuildContext ctx,
    String label,
    IconData icon,
    List<ScheduleItem> items,
  ) {
    showModalBottomSheet<void>(
      context: ctx,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      sheetAnimationStyle: const AnimationStyle(
        duration: Duration(milliseconds: 260),
        reverseDuration: Duration(milliseconds: 220),
      ),
      builder: (sheetCtx) => FractionallySizedBox(
        heightFactor: 0.76,
        child: Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              children: [
                const SizedBox(height: 10),
                Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.darkWith(0.15),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 16, 10, 12),
                  child: Row(
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(11),
                        ),
                        child: Icon(icon, size: 19, color: AppColors.primary),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '$label Schedules',
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                color: AppColors.dark,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${items.length} feeding schedule${items.length == 1 ? '' : 's'}',
                              style: TextStyle(
                                fontSize: 10,
                                color: AppColors.darkWith(0.45),
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(sheetCtx),
                        icon: const Icon(Icons.close_rounded),
                        color: AppColors.darkWith(0.55),
                      ),
                    ],
                  ),
                ),
                Divider(height: 1, color: AppColors.darkWith(0.08)),
                Expanded(
                  child: Scrollbar(
                    child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
                      itemCount: items.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 5),
                      itemBuilder: (_, itemIndex) {
                        final schedule = items[itemIndex];
                        return _buildScheduleItem(
                          sheetCtx,
                          schedules.indexOf(schedule),
                          schedule,
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildScheduleItem(BuildContext ctx, int index, ScheduleItem s) {
    final status = _scheduleStatus(s);
    Color bgColor;
    Color borderColor;
    Color dotColor;
    String statusLabel;
    IconData statusIcon;

    switch (status) {
      case 'completed':
        bgColor = AppColors.success.withValues(alpha: 0.08);
        borderColor = Colors.transparent;
        dotColor = AppColors.success;
        statusLabel = 'Completed';
        statusIcon = Icons.check_circle;
        break;
      case 'pending':
        bgColor = AppColors.warning.withValues(alpha: 0.1);
        borderColor = AppColors.warning.withValues(alpha: 0.25);
        dotColor = AppColors.warning;
        statusLabel = 'Pending';
        statusIcon = Icons.hourglass_bottom;
        break;
      case 'missed':
      case 'skipped':
      case 'failed':
        bgColor = AppColors.darkWith(0.06);
        borderColor = AppColors.darkWith(0.15);
        dotColor = AppColors.darkWith(0.4);
        statusLabel = status == 'skipped'
            ? 'Skipped'
            : status == 'failed'
            ? 'Failed'
            : 'Missed';
        statusIcon = Icons.error_outline;
        break;
      case 'off_today':
        bgColor = AppColors.darkWith(0.03);
        borderColor = AppColors.darkWith(0.1);
        dotColor = AppColors.darkWith(0.35);
        statusLabel = 'Off today';
        statusIcon = Icons.event_busy;
        break;
      case 'disabled':
        bgColor = AppColors.darkWith(0.05);
        borderColor = AppColors.darkWith(0.12);
        dotColor = AppColors.darkWith(0.4);
        statusLabel = 'Paused';
        statusIcon = Icons.pause_circle_outline;
        break;
      default:
        bgColor = Colors.white;
        borderColor = AppColors.darkWith(0.08);
        dotColor = AppColors.primaryWith(0.5);
        statusLabel = 'Upcoming';
        statusIcon = Icons.schedule;
        break;
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: bgColor,
          border: Border.all(color: borderColor),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Icon(statusIcon, size: 11, color: dotColor),
            const SizedBox(width: 5),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${s.time} ${s.ampm}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: status == 'disabled'
                          ? AppColors.darkWith(0.4)
                          : AppColors.dark,
                      decoration: status == 'completed'
                          ? TextDecoration.lineThrough
                          : null,
                      decorationColor: AppColors.darkWith(0.3),
                    ),
                  ),
                  if (s.grams != null) ...[
                    const SizedBox(height: 1),
                    Text(
                      '${s.grams!.toStringAsFixed(1)}g',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: AppColors.primary,
                      ),
                    ),
                  ],
                  const SizedBox(height: 1),
                  Text(
                    _formatDays(s.days),
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w500,
                      color: AppColors.darkWith(0.45),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: status == 'completed'
                        ? AppColors.success.withValues(alpha: 0.15)
                        : status == 'pending'
                        ? AppColors.warning.withValues(alpha: 0.15)
                        : status == 'missed'
                        ? AppColors.darkWith(0.1)
                        : AppColors.darkWith(0.08),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    statusLabel.toUpperCase(),
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      color: status == 'completed'
                          ? AppColors.success
                          : status == 'pending'
                          ? const Color(0xFFc97d08)
                          : AppColors.darkWith(0.5),
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 34,
                      height: 30,
                      child: FittedBox(
                        fit: BoxFit.contain,
                        child: Switch(
                          value: s.enabled,
                          activeTrackColor: AppColors.primary,
                          onChanged: (val) => onToggleSchedule(index, val),
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 34,
                      height: 34,
                      child: PopupMenuButton<String>(
                        tooltip: 'Schedule actions',
                        padding: EdgeInsets.zero,
                        icon: Icon(
                          Icons.more_vert_rounded,
                          size: 18,
                          color: AppColors.darkWith(0.55),
                        ),
                        onSelected: (action) {
                          if (action == 'edit') {
                            _showScheduleModal(ctx, index: index, existing: s);
                          } else if (action == 'delete') {
                            _confirmDelete(ctx, index);
                          }
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(
                            value: 'edit',
                            child: Row(
                              children: [
                                Icon(
                                  Icons.edit_outlined,
                                  size: 18,
                                  color: AppColors.primary,
                                ),
                                SizedBox(width: 10),
                                Text('Edit schedule'),
                              ],
                            ),
                          ),
                          PopupMenuItem(
                            value: 'delete',
                            child: Row(
                              children: [
                                Icon(
                                  Icons.delete_outline,
                                  size: 18,
                                  color: AppColors.critical,
                                ),
                                SizedBox(width: 10),
                                Text('Delete schedule'),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDelete(BuildContext ctx, int index) {
    showDialog(
      context: ctx,
      animationStyle: const AnimationStyle(
        duration: Duration(milliseconds: 220),
        reverseDuration: Duration(milliseconds: 180),
      ),
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.warning_rounded, size: 20, color: AppColors.critical),
            SizedBox(width: 8),
            Text(
              'Delete Schedule',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
            ),
          ],
        ),
        content: const Text(
          'Are you sure you want to delete this schedule?',
          style: TextStyle(fontSize: 12, color: AppColors.dark),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text(
              'Cancel',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(dialogCtx);
              onDeleteSchedule(index);
            },
            child: const Text(
              'Delete',
              style: TextStyle(
                color: AppColors.critical,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildGroupedFeederLogs() {
    final groups = <String, List<LogEntry>>{};
    for (final log in feederLogs) {
      final act = log.action.toLowerCase();
      // Only include actual dispensing events (ignore schedule toggle/config changes)
      if (!act.contains('dispens') && !act.contains('feed')) {
        continue;
      }
      final date = log.date.isEmpty ? 'Date unavailable' : log.date;
      groups.putIfAbsent(date, () => <LogEntry>[]).add(log);
    }

    final now = _manilaNow();
    final today = _formatFeederLogDate(now);
    final yesterday = _formatFeederLogDate(
      now.subtract(const Duration(days: 1)),
    );

    return [
      for (final group in groups.entries) ...[
        Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 7),
          child: Row(
            children: [
              Icon(
                Icons.calendar_today_rounded,
                size: 11,
                color: AppColors.primary.withValues(alpha: 0.8),
              ),
              const SizedBox(width: 6),
              Text(
                group.key == today
                    ? 'Today · ${group.key}'
                    : group.key == yesterday
                    ? 'Yesterday · ${group.key}'
                    : group.key,
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: AppColors.dark,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Container(height: 1, color: AppColors.darkWith(0.08)),
              ),
            ],
          ),
        ),
        for (final log in group.value) _buildFeederLogEntry(log),
      ],
    ];
  }

  String _formatFeederLogDate(DateTime date) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  Widget _buildFeederLogEntry(LogEntry log) {
    final isIssue =
        log.status == 'skipped_insufficient' ||
        log.status == 'blocked' ||
        log.status == 'failed' ||
        log.type == 'error';
    final dotColor = isIssue
        ? AppColors.critical
        : log.type == 'auto'
        ? AppColors.primary
        : AppColors.warning;
    final statusLabel = _feedStatusLabel(log.status);
    final displayGrams = log.requestedGrams ?? log.estimatedDispensedGrams;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.darkWith(0.03),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  log.action,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppColors.dark,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  log.time.isEmpty ? 'Time unavailable' : log.time,
                  style: TextStyle(fontSize: 9, color: AppColors.darkWith(0.4)),
                ),
                if (statusLabel.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    statusLabel,
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      color: log.status == 'completed' || log.status == 'forced'
                          ? AppColors.success
                          : AppColors.critical,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (displayGrams != null) ...[
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'EST. GRAMS',
                  style: TextStyle(
                    fontSize: 7,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.35,
                    color: AppColors.darkWith(0.45),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '~${displayGrams.toStringAsFixed(0)} g',
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: AppColors.dark,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  void _showFeederLog(BuildContext ctx) {
    showModalBottomSheet(
      context: ctx,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      sheetAnimationStyle: const AnimationStyle(
        duration: Duration(milliseconds: 260),
        reverseDuration: Duration(milliseconds: 220),
      ),
      builder: (sheetCtx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(sheetCtx).size.height * 0.75,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(6),
                          child: Image.asset(
                            'assets/images/FeedingImage.png',
                            fit: BoxFit.contain,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Feeder Log',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: AppColors.dark,
                            ),
                          ),
                          Text(
                            'Recent feeding activity',
                            style: TextStyle(
                              fontSize: 10,
                              color: AppColors.darkWith(0.45),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Flexible(
                    child: feederLogs.isEmpty
                        ? Center(
                            child: Text(
                              'No activity yet.',
                              style: TextStyle(
                                fontSize: 11,
                                color: AppColors.darkWith(0.35),
                              ),
                            ),
                          )
                        : SingleChildScrollView(
                            child: Column(children: _buildGroupedFeederLogs()),
                          ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: TextButton(
                      onPressed: () => Navigator.pop(sheetCtx),
                      style: TextButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 9),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: const Text(
                        'Close',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _showScheduleModal(
    BuildContext ctx, {
    int? index,
    ScheduleItem? existing,
  }) {
    final isEdit = existing != null;
    TimeOfDay selectedTime;
    if (isEdit) {
      int h = int.tryParse(existing.time.split(':')[0]) ?? 6;
      final m = int.tryParse(existing.time.split(':')[1]) ?? 0;
      if (existing.ampm == 'PM' && h != 12) h += 12;
      if (existing.ampm == 'AM' && h == 12) h = 0;
      selectedTime = TimeOfDay(hour: h, minute: m);
    } else {
      selectedTime = const TimeOfDay(hour: 6, minute: 0);
    }
    final rec = FeederRecommendation.compute();
    final existingGrams = existing?.grams;
    final initialGramsText = existingGrams == null
        ? (rec.hasData ? rec.perFeedingGrams.toInt().toString() : '')
        : (existingGrams.isFinite &&
                  existingGrams >= 1 &&
                  existingGrams <= 200 &&
                  existingGrams == existingGrams.roundToDouble()
              ? existingGrams.toInt().toString()
              : existingGrams.toString());
    final gramsCtl = TextEditingController(text: initialGramsText);
    // Day-of-week mask, Sunday first: index 0..6. Default = every day.
    final selectedDays = <int>{
      for (var i = 0; i < 7; i++)
        if (existing == null ||
            existing.days.length <= i ||
            existing.days[i] == '1')
          i,
    };
    var isSaving = false;
    String? saveError;

    showModalBottomSheet(
      context: ctx,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      sheetAnimationStyle: const AnimationStyle(
        duration: Duration(milliseconds: 260),
        reverseDuration: Duration(milliseconds: 220),
      ),
      builder: (sheetCtx) {
        return StatefulBuilder(
          builder: (sheetCtx, setSheetState) {
            String? gramsError;
            if (gramsCtl.text.trim().isNotEmpty) {
              final v = double.tryParse(gramsCtl.text.trim());
              if (v == null) {
                gramsError = 'Enter a valid number';
              } else {
                gramsError = validateFeederGrams(v);
              }
            }

            return Padding(
              padding: EdgeInsets.fromLTRB(
                20,
                10,
                20,
                20 + MediaQuery.of(sheetCtx).viewInsets.bottom,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 36,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      isEdit ? 'Edit Schedule' : 'Add Schedule',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: AppColors.dark,
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Time picker
                    GestureDetector(
                      onTap: () async {
                        final picked = await showTimePicker(
                          context: sheetCtx,
                          initialTime: selectedTime,
                        );
                        if (picked != null) {
                          setSheetState(() => selectedTime = picked);
                        }
                      },
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 16,
                        ),
                        decoration: BoxDecoration(
                          border: Border.all(color: AppColors.darkWith(0.15)),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              selectedTime.format(sheetCtx),
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: AppColors.dark,
                              ),
                            ),
                            Icon(
                              Icons.access_time,
                              size: 18,
                              color: AppColors.primary,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    // Quick Times
                    Row(
                      children: [
                        Text(
                          'Quick Times:',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: AppColors.darkWith(0.5),
                          ),
                        ),
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: () => setSheetState(
                            () => selectedTime =
                                const TimeOfDay(hour: 6, minute: 0),
                          ),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: selectedTime.hour == 6 &&
                                      selectedTime.minute == 0
                                  ? AppColors.primary.withValues(alpha: 0.12)
                                  : AppColors.darkWith(0.04),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: selectedTime.hour == 6 &&
                                        selectedTime.minute == 0
                                    ? AppColors.primary
                                    : AppColors.darkWith(0.12),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.wb_sunny_outlined,
                                  size: 12,
                                  color: Color(0xFFE5A100),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '6:00 AM',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: selectedTime.hour == 6 &&
                                            selectedTime.minute == 0
                                        ? AppColors.primary
                                        : AppColors.dark,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        GestureDetector(
                          onTap: () => setSheetState(
                            () => selectedTime =
                                const TimeOfDay(hour: 18, minute: 0),
                          ),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: selectedTime.hour == 18 &&
                                      selectedTime.minute == 0
                                  ? AppColors.primary.withValues(alpha: 0.12)
                                  : AppColors.darkWith(0.04),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: selectedTime.hour == 18 &&
                                        selectedTime.minute == 0
                                    ? AppColors.primary
                                    : AppColors.darkWith(0.12),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.nightlight_outlined,
                                  size: 12,
                                  color: Color(0xFF6C5CE7),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '6:00 PM',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: selectedTime.hour == 18 &&
                                            selectedTime.minute == 0
                                        ? AppColors.primary
                                        : AppColors.dark,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (rec.hasData) ...[
                      const SizedBox(height: 10),
                      GestureDetector(
                        onTap: () {
                          setSheetState(() {
                            gramsCtl.text = '${rec.perFeedingGrams.toInt()}';
                          });
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: AppColors.primary.withValues(alpha: 0.2),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.scale_rounded,
                                size: 12,
                                color: AppColors.primary,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'Use 5% Body Weight: ${rec.perFeedingGrams.toInt()}g',
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.primary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    // Grams field
                    TextField(
                      controller: gramsCtl,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: false,
                        signed: false,
                      ),
                      inputFormatters: [
                        TextInputFormatter.withFunction((oldValue, newValue) {
                          if (newValue.text.isEmpty ||
                              RegExp(r'^\d+$').hasMatch(newValue.text)) {
                            return newValue;
                          }
                          return oldValue;
                        }),
                      ],
                      onChanged: (_) => setSheetState(() {}),
                      decoration: InputDecoration(
                        labelText: 'Grams *',
                        hintText: 'Enter 1–200 whole grams',
                        helperText: 'Required · 1 swing per gram',
                        suffixText: 'g',
                        errorText: gramsError,
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: AppColors.darkWith(0.15),
                            width: 1.5,
                          ),
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                            color: AppColors.primary,
                            width: 2,
                          ),
                        ),
                        errorBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                            color: AppColors.critical,
                            width: 1.5,
                          ),
                        ),
                        focusedErrorBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                            color: AppColors.critical,
                            width: 2,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    // Days of the week selector (alarm-clock style)
                    Text(
                      'Repeat on',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppColors.darkWith(0.6),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: List.generate(7, (i) {
                        final on = selectedDays.contains(i);
                        return GestureDetector(
                          onTap: () => setSheetState(() {
                            if (on) {
                              selectedDays.remove(i);
                            } else {
                              selectedDays.add(i);
                            }
                          }),
                          child: Container(
                            width: 36,
                            height: 36,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: on
                                  ? AppColors.primary
                                  : Colors.transparent,
                              border: Border.all(
                                color: on
                                    ? AppColors.primary
                                    : AppColors.darkWith(0.2),
                                width: 1.5,
                              ),
                            ),
                            child: Text(
                              const ['S', 'M', 'T', 'W', 'T', 'F', 'S'][i],
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: on
                                    ? Colors.white
                                    : AppColors.darkWith(0.5),
                              ),
                            ),
                          ),
                        );
                      }),
                    ),
                    if (selectedDays.isEmpty) ...[
                      const SizedBox(height: 8),
                      const Text(
                        'Select at least one day',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: AppColors.critical,
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed:
                            gramsCtl.text.trim().isEmpty ||
                                gramsError != null ||
                                selectedDays.isEmpty ||
                                isSaving
                            ? null
                            : () async {
                                final h = selectedTime.hour;
                                final m = selectedTime.minute;
                                final ampm = h >= 12 ? 'PM' : 'AM';
                                final h12 = h % 12 == 0 ? 12 : h % 12;
                                final timeStr =
                                    '$h12:${m.toString().padLeft(2, '0')}';
                                final intVal = int.tryParse(
                                  gramsCtl.text.trim(),
                                );
                                if (intVal == null ||
                                    intVal < 1 ||
                                    intVal > 200) {
                                  return;
                                }
                                final grams = intVal.toDouble();
                                final daysMask = String.fromCharCodes(
                                  List.generate(
                                    7,
                                    (i) => selectedDays.contains(i) ? 49 : 48,
                                  ),
                                );
                                final requested = ScheduleItem(
                                  timeStr,
                                  ampm,
                                  enabled: existing?.enabled ?? true,
                                  grams: grams,
                                  days: daysMask,
                                );
                                ScheduleItem? conflict;
                                for (final e in schedules.asMap().entries) {
                                  if (isEdit && e.key == index) continue;
                                  final s = e.value;
                                  if (feederSchedulesConflict(requested, s)) {
                                    conflict = s;
                                    break;
                                  }
                                }
                                if (conflict != null) {
                                  setSheetState(
                                    () => saveError =
                                        feederScheduleConflictMessage(
                                          requested,
                                          conflict!,
                                        ),
                                  );
                                  return;
                                }
                                if (isEdit) {
                                  setSheetState(() {
                                    isSaving = true;
                                    saveError = null;
                                  });
                                  final saved = await onEditSchedule(
                                    index!,
                                    ScheduleItem(
                                      timeStr,
                                      ampm,
                                      enabled: existing.enabled,
                                      grams: grams,
                                      days: daysMask,
                                    ),
                                  );
                                  if (!sheetCtx.mounted) return;
                                  if (!saved) {
                                    setSheetState(() {
                                      isSaving = false;
                                      saveError =
                                          'Schedule was not saved. Check your connection and try again.';
                                    });
                                    return;
                                  }
                                  Navigator.pop(sheetCtx);
                                } else {
                                  timeCtl.text = '$timeStr:$ampm';
                                  setSheetState(() {
                                    isSaving = true;
                                    saveError = null;
                                  });
                                  final saved = await onAddSchedule(
                                    grams,
                                    daysMask,
                                  );
                                  if (!sheetCtx.mounted) return;
                                  if (!saved) {
                                    setSheetState(() {
                                      isSaving = false;
                                      saveError =
                                          'Schedule was not saved. Check your connection and try again.';
                                    });
                                    return;
                                  }
                                  Navigator.pop(sheetCtx);
                                }
                              },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          disabledBackgroundColor: Colors.grey.shade300,
                          foregroundColor: Colors.white,
                          disabledForegroundColor: Colors.grey.shade500,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: isSaving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : Text(
                                isEdit ? 'Save' : 'Add',
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                      ),
                    ),
                    if (saveError != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        saveError!,
                        style: const TextStyle(
                          color: AppColors.critical,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}
