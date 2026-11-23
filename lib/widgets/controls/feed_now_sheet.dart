import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/control_types.dart';
import '../../theme/app_colors.dart';
import '../../utils/feeding_progress.dart';

/// Identifies the schedule this Feed Now should complete when it reaches the
/// full recommended dose. Partial feedings deliberately leave this null.
class FeedNowCover {
  final String scheduleKey;
  final String scheduleTime;
  final int occurrenceAtMs;

  const FeedNowCover({
    required this.scheduleKey,
    required this.scheduleTime,
    required this.occurrenceAtMs,
  });
}

class FeedNowResult {
  final double grams;
  final FeedNowCover? cover;

  const FeedNowResult({required this.grams, this.cover});
}

/// Returns the requested grams and optional schedule cover to the caller; this
/// sheet never starts feeding. Owning the controller here keeps it alive
/// through the exit animation.
class FeedNowSheet extends StatefulWidget {
  final FeedingProgress? progress;
  final FeedNowCover? cover;

  const FeedNowSheet({super.key, this.progress, this.cover});

  @override
  State<FeedNowSheet> createState() => _FeedNowSheetState();
}

class _FeedNowSheetState extends State<FeedNowSheet> {
  final TextEditingController _gramsController = TextEditingController();

  @override
  void initState() {
    super.initState();
    final progress = widget.progress;
    if (progress != null && progress.canApply) {
      _gramsController.text = progress.dispensableGrams.round().toString();
    }
  }

  @override
  void dispose() {
    _gramsController.dispose();
    super.dispose();
  }

  double? get _grams => double.tryParse(_gramsController.text.trim());

  bool get _willCompleteSlot {
    final progress = widget.progress;
    final grams = _grams;
    if (progress == null || progress.isDone || grams == null) return false;
    return progress.dispensedGrams + grams >= progress.recommendedGrams - 1;
  }

  String? _validationError(double? grams) {
    final text = _gramsController.text.trim();
    if (text.isEmpty) return null;
    if (grams == null) return 'Enter a valid number';

    final rangeError = validateFeederGrams(grams);
    if (rangeError != null) return rangeError;

    final progress = widget.progress;
    if (progress != null && grams > progress.dispensableGrams) {
      return 'Only ${progress.dispensableGrams.round()} g remaining';
    }
    return null;
  }

  String _note(FeedingProgress? progress) {
    if (progress == null) {
      return 'No recommendation available. This is a manual feeding.';
    }
    var note = progress.progressNote;
    if (_willCompleteSlot && widget.cover != null) {
      note +=
          '\n\nThis Feed Now will cover the '
          '${widget.cover!.scheduleTime} schedule.';
    }
    return note;
  }

  @override
  Widget build(BuildContext context) {
    final progress = widget.progress;
    final grams = _grams;
    final error = _validationError(grams);
    final canSubmit =
        grams != null && error == null && !(progress?.isDone ?? false);

    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        16,
        20,
        28 + MediaQuery.viewInsetsOf(context).bottom,
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
            const SizedBox(height: 20),
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppColors.lightBg,
                    borderRadius: BorderRadius.circular(11),
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    Icons.set_meal_rounded,
                    size: 22,
                    color: AppColors.darkWith(0.7),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Feed Now',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: AppColors.dark,
                        ),
                      ),
                      Text(
                        widget.progress == null
                            ? 'Manual feeding'
                            : '5% biomass recommendation',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.subtitleText,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            if (progress != null) ...[
              _buildPlanPanel(progress),
              const SizedBox(height: 18),
            ],
            TextField(
              controller: _gramsController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: false,
                signed: false,
              ),
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              enabled: !(progress?.isDone ?? false),
              onChanged: (_) => setState(() {}),
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.darkText,
              ),
              decoration: InputDecoration(
                labelText: 'Feed amount (g)',
                labelStyle: const TextStyle(fontSize: 12),
                hintStyle: const TextStyle(fontSize: 12),
                hintText: progress != null && progress.canApply
                    ? 'Remaining ${progress.dispensableGrams.round()}'
                    : 'Enter 1–200',
                suffixText: 'g',
                suffixStyle: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
                errorStyle: const TextStyle(fontSize: 11),
                errorText: error,
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 16,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(
                    color: AppColors.primary,
                    width: 1.6,
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(
                    color: AppColors.primary,
                    width: 2.2,
                  ),
                ),
                errorBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(
                    color: AppColors.critical,
                    width: 1.6,
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
            const SizedBox(height: 14),
            Text(
              _note(progress),
              style: TextStyle(
                fontSize: 11,
                color: AppColors.subtitleText,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 22),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: canSubmit
                    ? () => Navigator.of(context).pop(
                        FeedNowResult(
                          grams: grams,
                          cover: _willCompleteSlot ? widget.cover : null,
                        ),
                      )
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: Colors.grey.shade300,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  progress?.isDone == true
                      ? '${progress?.slotLabel ?? 'Slot'} feeding complete'
                      : grams != null && error == null
                      ? 'Dispense ${grams.round()} g'
                      : 'Dispense Feed',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlanPanel(FeedingProgress progress) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.faintBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Recommendation plan',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.darkText,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.darkWith(0.04),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(
                  '5% biomass',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: AppColors.darkWith(0.55),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _buildPlanSlot(
                label: 'AM',
                dispensed: progress.morningDispensedGrams,
                recommended: progress.recommendedGrams,
                active: progress.slot == FeedingSlot.morning,
              ),
              const SizedBox(width: 14),
              _buildPlanSlot(
                label: 'PM',
                dispensed: progress.eveningDispensedGrams,
                recommended: progress.recommendedGrams,
                active: progress.slot == FeedingSlot.evening,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPlanSlot({
    required String label,
    required double dispensed,
    required double recommended,
    required bool active,
  }) {
    final remaining = (recommended - dispensed).clamp(0.0, recommended);
    final complete = remaining < 1;
    final value = recommended <= 0
        ? 0.0
        : (dispensed / recommended).clamp(0.0, 1.0).toDouble();

    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.3,
                  color: active ? AppColors.primary : AppColors.subtitleText,
                ),
              ),
              const SizedBox(width: 5),
              Text(
                '${dispensed.round()}/${recommended.round()} g',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.darkText,
                ),
              ),
              const Spacer(),
              Text(
                complete ? 'Done' : '${remaining.round()} left',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: complete
                      ? AppColors.success
                      : AppColors.darkWith(0.45),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: value,
              minHeight: 4,
              backgroundColor: AppColors.darkWith(0.08),
              valueColor: AlwaysStoppedAnimation<Color>(
                complete ? AppColors.success : AppColors.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
