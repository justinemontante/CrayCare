const existingFunctions = require("./index");
const dailySummaryFunctions = require("./daily_summary");
const assignmentGuardFunctions = require("./assignment_guard");
const feederScheduleFunctions = require("./feeding/feeder_schedules");
const waterQualityClassifierFunctions = require("./water_quality_classification/classifier");

Object.assign(
  exports,
  existingFunctions,
  dailySummaryFunctions,
  assignmentGuardFunctions,
  feederScheduleFunctions,
  waterQualityClassifierFunctions,
);
