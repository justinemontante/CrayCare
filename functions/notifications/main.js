const existingFunctions = require("./index");
const dailySummaryFunctions = require("./daily_summary");
const assignmentGuardFunctions = require("./assignment_guard");

Object.assign(
  exports,
  existingFunctions,
  dailySummaryFunctions,
  assignmentGuardFunctions,
);
