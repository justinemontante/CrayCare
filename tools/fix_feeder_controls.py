from pathlib import Path

EXPECTED_MAIN = "4f6ebb37edbe0d1fb335a26062d1eb335010e456"
PATH = Path("lib/widgets/controls/feeder_tab.dart")

text = PATH.read_text(encoding="utf-8")
original = text

replacements = [
    (
        "    final morning = schedules.where((s) => s.ampm == 'AM').toList();\n"
        "    final afternoon = schedules.where((s) => s.ampm == 'PM').toList();\n\n"
        "    return Container(",
        "    final morning = schedules.where((s) => s.ampm == 'AM').toList();\n"
        "    final afternoon = schedules.where((s) => s.ampm == 'PM').toList();\n"
        "    final hasEnabledSchedules = schedules.any((s) => s.enabled);\n\n"
        "    return Container(",
        1,
    ),
    (
        "                              color: schedules.isNotEmpty\n"
        "                                  ? AppColors.success\n"
        "                                  : AppColors.darkWith(0.3),",
        "                              color: hasEnabledSchedules\n"
        "                                  ? AppColors.success\n"
        "                                  : AppColors.darkWith(0.3),",
        1,
    ),
    (
        "                            schedules.isNotEmpty\n"
        "                                ? 'Schedules Active'\n"
        "                                : 'No Schedules',",
        "                            schedules.isEmpty\n"
        "                                ? 'No Schedules'\n"
        "                                : hasEnabledSchedules\n"
        "                                ? 'Schedules Active'\n"
        "                                : 'Schedules Paused',",
        1,
    ),
    (
        "                              color: schedules.isNotEmpty\n"
        "                                  ? AppColors.success\n"
        "                                  : AppColors.darkWith(0.4),",
        "                              color: hasEnabledSchedules\n"
        "                                  ? AppColors.success\n"
        "                                  : AppColors.darkWith(0.4),",
        1,
    ),
    (
        "                  const SizedBox(height: 20),\n"
        "                  SizedBox(\n"
        "                    width: double.infinity,\n"
        "                    child: ElevatedButton(\n"
        "                      onPressed: gramsError != null\n"
        "                          ? null\n"
        "                          : () {",
        "                  if (selectedDays.isEmpty) ...[\n"
        "                    const SizedBox(height: 8),\n"
        "                    const Text(\n"
        "                      'Select at least one day',\n"
        "                      style: TextStyle(\n"
        "                        fontSize: 10,\n"
        "                        fontWeight: FontWeight.w600,\n"
        "                        color: AppColors.critical,\n"
        "                      ),\n"
        "                    ),\n"
        "                  ],\n"
        "                  const SizedBox(height: 20),\n"
        "                  SizedBox(\n"
        "                    width: double.infinity,\n"
        "                    child: ElevatedButton(\n"
        "                      onPressed: gramsError != null || selectedDays.isEmpty\n"
        "                          ? null\n"
        "                          : () {",
        1,
    ),
]

for old, new, expected_count in replacements:
    count = text.count(old)
    if count != expected_count:
        raise SystemExit(f"Guard failed: expected {expected_count} occurrence(s), found {count}: {old[:100]!r}")
    text = text.replace(old, new, expected_count)

if text == original:
    raise SystemExit("No changes produced")

PATH.write_text(text, encoding="utf-8")
print("Patched feeder_tab.dart successfully")
