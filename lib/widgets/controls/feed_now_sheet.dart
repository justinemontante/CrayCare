import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/control_types.dart';
import '../../theme/app_colors.dart';

/// Returns the requested grams to the caller; this sheet never starts feeding.
/// Owning the controller here keeps it alive through the exit animation.
class FeedNowSheet extends StatefulWidget {
  const FeedNowSheet({super.key});

  @override
  State<FeedNowSheet> createState() => _FeedNowSheetState();
}

class _FeedNowSheetState extends State<FeedNowSheet> {
  final TextEditingController _gramsController = TextEditingController();

  @override
  void dispose() {
    _gramsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = _gramsController.text.trim();
    final grams = double.tryParse(text);
    final error = text.isEmpty
        ? null
        : grams == null
        ? 'Enter a valid number'
        : validateFeederGrams(grams);

    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        14,
        20,
        20 + MediaQuery.viewInsetsOf(context).bottom,
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
            const SizedBox(height: 18),
            const Text(
              'Feed Now',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: AppColors.dark,
              ),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _gramsController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: false,
                signed: false,
              ),
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: 'Feed amount (g)',
                hintText: 'Enter 1–200',
                suffixText: 'g',
                errorText: error,
                filled: true,
                fillColor: Colors.white,
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
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: grams == null || error != null
                    ? null
                    : () => Navigator.of(context).pop(grams),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: Colors.grey.shade300,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text('Dispense Feed'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
