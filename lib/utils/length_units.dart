const double centimetersPerInch = 2.54;

double centimetersToInches(num centimeters) =>
    centimeters.toDouble() / centimetersPerInch;

String legacyCentimeterLengthTextToInches(dynamic value) {
  final text = value?.toString() ?? '';
  final centimeters = double.tryParse(text);
  return centimeters == null
      ? text
      : centimetersToInches(centimeters).toStringAsFixed(2);
}
