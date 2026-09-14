import fs from "node:fs/promises";
import { Workbook, SpreadsheetFile } from "@oai/artifact-tool";

const outPath = "docs/deliverables/CrayCare_Implementation_Plan_2026.xlsx";
const wb = Workbook.create();
const plan = wb.worksheets.add("Implementation Plan");
const milestones = wb.worksheets.add("Milestones & Status");
const lists = wb.worksheets.add("Lists");

const C = {
  navy: "#073B4C", teal: "#0E9F9A", aqua: "#D9F2F0", pale: "#EEF8F7",
  green: "#73C69B", amber: "#F4B942", red: "#E76F51", gray: "#667085",
  lightGray: "#E7ECEF", white: "#FFFFFF", text: "#16343D", blue: "#3B82F6",
};
const font = "Arial";
const d = (s) => new Date(`${s}T00:00:00`);
const statusFor = (end, start) => {
  const asOf = d("2026-09-11");
  if (d(end) < asOf) return "Completed";
  if (d(start) <= asOf) return "In Progress";
  return "Pending";
};

const groups = [
  ["1.0", "Phase 1: Proposal and Requirements", [
    ["1.1", "Brainstorming and problem identification", "2026-04-06", "2026-04-12"],
    ["1.2", "Formulate proposed titles and concept notes", "2026-04-06", "2026-04-19"],
    ["1.3", "Initial literature search and feasibility check", "2026-04-06", "2026-04-19"],
    ["1.4", "Title defense and panel presentation", "2026-04-20", "2026-04-24"],
    ["1.5", "Revisions and official title approval", "2026-04-25", "2026-04-30"],
  ]],
  ["2.0", "Chapters 1-3 Development", [
    ["2.1", "Design system architecture", "2026-05-04", "2026-05-10"],
    ["2.2", "Draft project context, purpose, and objectives", "2026-05-04", "2026-05-17"],
    ["2.3", "Prepare technical background, DFDs, and infrastructure", "2026-05-04", "2026-05-17"],
    ["2.4", "Complete problem analysis and requirements matrix", "2026-05-11", "2026-05-17"],
    ["2.5", "Gather and evaluate foreign and local literature", "2026-05-04", "2026-05-24"],
    ["2.6", "Write thematic narrative, systems review, and synthesis", "2026-05-11", "2026-05-24"],
    ["2.7", "Define use cases, reports, and functional requirements", "2026-05-04", "2026-05-24"],
    ["2.8", "Prepare activity, class, database, and interface designs", "2026-05-11", "2026-05-24"],
    ["2.9", "Define methodology, test procedures, and evaluation plan", "2026-05-18", "2026-05-24"],
    ["2.10", "Compile, format, and submit Chapters 1-3", "2026-05-25", "2026-05-31"],
  ]],
  ["3.0", "Proposal Prototype and Defense", [
    ["3.1", "Adviser consultation and manuscript corrections", "2026-05-25", "2026-06-07"],
    ["3.2", "Prepare mock-defense presentation deck", "2026-05-25", "2026-06-07"],
    ["3.3", "Conduct Mock Defense 1", "2026-06-08", "2026-06-12"],
    ["3.4", "Apply panel corrections and recommendations", "2026-06-08", "2026-06-21"],
    ["3.5", "Research and canvass hardware components", "2026-05-25", "2026-06-21"],
    ["3.6", "Prepare hardware budget and cost estimate", "2026-05-25", "2026-06-14"],
    ["3.7", "Procure sensors and prototype materials", "2026-06-01", "2026-06-21"],
    ["3.8", "Assemble hardware prototype", "2026-06-15", "2026-07-05"],
    ["3.9", "Integrate sensors and complete wiring", "2026-06-15", "2026-07-05"],
    ["3.10", "Calibrate, test, troubleshoot, and refine prototype", "2026-06-22", "2026-07-12"],
    ["3.11", "Translate UI design to Flutter codebase", "2026-06-08", "2026-07-05"],
    ["3.12", "Develop core mobile application features", "2026-06-08", "2026-07-05"],
    ["3.13", "Integrate mobile app with hardware prototype", "2026-06-15", "2026-07-05"],
    ["3.14", "Test app-hardware communication", "2026-06-29", "2026-07-12"],
    ["3.15", "Prepare manuscript, app, hardware, and deck for proposal defense", "2026-06-29", "2026-07-12"],
    ["3.16", "Final proposal defense and submission", "2026-07-13", "2026-07-17"],
    ["3.17", "Apply proposal-defense corrections", "2026-07-18", "2026-08-02"],
  ]],
  ["4.0", "Phase 2: Hardware and Tank Implementation", [
    ["4.1", "Complete procurement of final hardware components", "2026-08-31", "2026-09-13"],
    ["4.2", "Build and complete the final hardware assembly", "2026-09-01", "2026-09-20"],
    ["4.3", "Complete final wiring and sensor connections", "2026-09-01", "2026-09-20"],
    ["4.4", "Complete device casing, mounting, and waterproofing", "2026-09-08", "2026-09-27"],
    ["4.5", "Calibrate all sensors and hardware components", "2026-09-08", "2026-09-27"],
    ["4.6", "Validate sensor accuracy and component reliability", "2026-09-15", "2026-09-30"],
    ["4.7", "Integrate finalized hardware into the actual tank setup", "2026-09-22", "2026-09-30"],
    ["4.8", "Conduct final hardware readiness inspection and sign-off", "2026-09-22", "2026-09-30"],
  ]],
  ["5.0", "Software, Cloud, and Mobile Application", [
    ["5.1", "Complete IoT sensor data programming", "2026-08-03", "2026-09-13"],
    ["5.2", "Finalize Firebase cloud database and security rules", "2026-08-03", "2026-09-20"],
    ["5.3", "Finalize dashboard and tank management features", "2026-08-03", "2026-09-20"],
    ["5.4", "Finalize feeder scheduling and actuator controls", "2026-08-10", "2026-09-20"],
    ["5.5", "Finalize alerts, sampling reminders, and push notifications", "2026-08-10", "2026-09-27"],
    ["5.6", "Complete UI/UX refinement and performance optimization", "2026-08-17", "2026-09-30"],
    ["5.7", "Verify authentication, ownership, and access-control rules", "2026-08-24", "2026-09-30"],
  ]],
  ["6.0", "Supporting Machine Learning Feature", [
    ["6.1", "Prepare water-quality reference dataset", "2026-08-03", "2026-08-16"],
    ["6.2", "Engineer temperature, pH, dissolved oxygen, and turbidity features", "2026-08-10", "2026-08-23"],
    ["6.3", "Train and validate the anomaly-detection model", "2026-08-17", "2026-09-20"],
    ["6.4", "Deploy the prediction pipeline to the cloud", "2026-09-14", "2026-09-27"],
    ["6.5", "Integrate Normal/Unusual results, trends, insights, and recommendations", "2026-09-14", "2026-09-30"],
    ["6.6", "Test model outputs and document limitations", "2026-09-21", "2026-10-07"],
  ]],
  ["7.0", "October Deployment, Live Implementation, and Field Testing", [
    ["7.1", "Complete deployment preparation and system-readiness verification", "2026-09-22", "2026-09-30"],
    ["7.2", "Deploy CrayCare to the actual crayfish tank", "2026-10-01", "2026-10-07"],
    ["7.3", "Begin full live operation of the deployed system", "2026-10-01", "2026-10-31"],
    ["7.4", "Monitor sensors, feeder, aerators, water pump, and notifications", "2026-10-01", "2026-10-31"],
    ["7.5", "Conduct functional, integration, and reliability testing", "2026-10-01", "2026-10-21"],
    ["7.6", "Conduct field testing in the actual crayfish environment", "2026-10-08", "2026-10-31"],
    ["7.7", "Fix deployment issues and refine system performance", "2026-10-08", "2026-11-07"],
    ["7.8", "Run usability and ISO/IEC 25010 evaluation", "2026-11-01", "2026-11-15"],
    ["7.9", "Finalize test evidence, logs, and technical documentation", "2026-11-08", "2026-11-22"],
  ]],
  ["8.0", "Chapter 4: Results and Discussion", [
    ["8.1", "Distribute evaluation instruments to evaluators", "2026-11-01", "2026-11-15"],
    ["8.2", "Collect and encode live-operation and evaluation data", "2026-10-01", "2026-11-15"],
    ["8.3", "Perform statistical analysis", "2026-11-16", "2026-11-30"],
    ["8.4", "Present and interpret the results", "2026-11-23", "2026-12-07"],
    ["8.5", "Draft, review, and revise Chapter 4", "2026-11-16", "2026-12-07"],
  ]],
  ["9.0", "Chapter 5 and Final Deliverables", [
    ["9.1", "Write the summary of findings", "2026-12-01", "2026-12-07"],
    ["9.2", "Write conclusions", "2026-12-01", "2026-12-13"],
    ["9.3", "Write recommendations", "2026-12-01", "2026-12-13"],
    ["9.4", "Draft, review, and revise Chapter 5", "2026-12-07", "2026-12-16"],
    ["9.5", "Compile and format the full Chapters 1-5 manuscript", "2026-11-30", "2026-12-13"],
    ["9.6", "Complete final proofreading and plagiarism check", "2026-12-07", "2026-12-20"],
    ["9.7", "Prepare and conduct the final oral defense", "2026-12-07", "2026-12-20"],
    ["9.8", "Apply final panel corrections", "2026-12-21", "2026-12-24"],
    ["9.9", "Secure adviser approval and signatures", "2026-12-21", "2026-12-24"],
    ["9.10", "Print, bind, and submit the final manuscript", "2026-12-25", "2026-12-28"],
    ["9.11", "Project closure and archive", "2026-12-28", "2026-12-31"],
  ]],
];

const weeks = [];
const weekEnds = [];
for (let month = 0; month < 12; month++) {
  for (const day of [1, 8, 15, 22]) {
    weeks.push(new Date(2026, month, day));
    weekEnds.push(new Date(2026, month, day === 22 ? new Date(2026, month + 1, 0).getDate() : day + 6));
  }
}
const lastCol = 6 + weeks.length;
const colName = (n) => { let s = ""; while (n > 0) { n--; s = String.fromCharCode(65 + n % 26) + s; n = Math.floor(n / 26); } return s; };
const last = colName(lastCol);

plan.showGridLines = false;
plan.mergeCells(`A1:${last}1`);
plan.getRange("A1").values = [["CRAYCARE CAPSTONE IMPLEMENTATION PLAN — 2026"]];
plan.getRange(`A1:${last}1`).format = { fill: C.navy, font: { name: font, size: 16, bold: true, color: C.white }, horizontalAlignment: "center", verticalAlignment: "center" };
plan.getRange("A1").format.rowHeight = 32;

const statuses = ["Completed", "In Progress", "Pending", "For Evaluation"];
plan.getRange("A3:F4").format = { fill: C.navy, font: { name: font, size: 10, bold: true, color: C.white }, horizontalAlignment: "center", verticalAlignment: "center", wrapText: true, borders: { preset: "all", style: "thin", color: C.white } };
for (const c of ["A","B","C","D","E","F"]) plan.mergeCells(`${c}3:${c}4`);
plan.getRange("A3:F3").values = [["WBS", "Activity", "Status", "Start Date", "End Date", "Duration (Days)"]];
plan.getRange("G4").write([weeks.map((_, i) => `W${(i % 4) + 1}`)]);
plan.getRange(`G4:${last}4`).format = { fill: C.teal, font: { name: font, size: 8, bold: true, color: C.white }, horizontalAlignment: "center", verticalAlignment: "center", borders: { preset: "all", style: "thin", color: C.white } };

let monthStart = 0;
while (monthStart < weeks.length) {
  const m = weeks[monthStart].getMonth(); let monthEnd = monthStart;
  while (monthEnd + 1 < weeks.length && weeks[monthEnd + 1].getMonth() === m) monthEnd++;
  const c1 = colName(7 + monthStart), c2 = colName(7 + monthEnd);
  if (c1 !== c2) plan.mergeCells(`${c1}3:${c2}3`);
  plan.getRange(`${c1}3`).values = [[weeks[monthStart].toLocaleString("en-US", { month: "long" })]];
  plan.getRange(`${c1}3:${c2}3`).format = { fill: C.teal, font: { name: font, size: 10, bold: true, color: C.white }, horizontalAlignment: "center", verticalAlignment: "center", borders: { preset: "outside", style: "thin", color: C.white } };
  monthStart = monthEnd + 1;
}

let row = 5; const taskRows = []; const phaseRows = [];
for (const [phaseWbs, phase, tasks] of groups) {
  phaseRows.push(row);
  plan.getRange(`A${row}`).values = [[phaseWbs]];
  plan.mergeCells(`B${row}:${last}${row}`);
  plan.getRange(`B${row}`).values = [[phase]];
  plan.getRange(`A${row}:${last}${row}`).format = { fill: C.aqua, font: { name: font, size: 10, bold: true, color: C.navy }, verticalAlignment: "center", borders: { preset: "outside", style: "thin", color: "#9BCDC9" } };
  row++;
  for (const [wbs, activity, start, end] of tasks) {
    taskRows.push(row);
    plan.getRange(`A${row}:E${row}`).values = [[wbs, activity, statusFor(end, start), d(start), d(end)]];
    plan.getRange(`F${row}`).formulas = [[`=IF(OR(D${row}="",E${row}=""),"",E${row}-D${row}+1)`]];
    const formulas = weeks.map((start, i) => {
      const end = weekEnds[i];
      return `=IF(AND($D${row}<=DATE(${end.getFullYear()},${end.getMonth()+1},${end.getDate()}),$E${row}>=DATE(${start.getFullYear()},${start.getMonth()+1},${start.getDate()})),1,"")`;
    });
    plan.getRange(`G${row}:${last}${row}`).formulas = [formulas];
    row++;
  }
}
const lastRow = row - 1;
plan.getRange(`A5:F${lastRow}`).format = { font: { name: font, size: 9, color: C.text }, verticalAlignment: "center", borders: { insideHorizontal: { style: "thin", color: "#D8E5E4" }, bottom: { style: "thin", color: "#B7D8D5" } } };
plan.getRange(`A5:A${lastRow}`).format.horizontalAlignment = "center";
plan.getRange(`C5:C${lastRow}`).format.horizontalAlignment = "center";
plan.getRange(`D5:E${lastRow}`).format.numberFormat = "mmm d, yyyy";
plan.getRange(`D5:F${lastRow}`).format.horizontalAlignment = "center";
plan.getRange(`G5:${last}${lastRow}`).format = { font: { name: font, size: 8, color: C.teal }, horizontalAlignment: "center", verticalAlignment: "center", numberFormat: ";;;", borders: { preset: "all", style: "thin", color: "#E4EFEE" } };
plan.getRange(`G5:${last}${lastRow}`).conditionalFormats.add("cellIs", { operator: "equal", formula: 1, format: { fill: C.green } });
plan.getRange(`C5:C${lastRow}`).dataValidation = { rule: { type: "list", values: statuses } };
plan.getRange(`C5:C${lastRow}`).conditionalFormats.add("containsText", { text: "Completed", format: { fill: "#DDF4E7", font: { color: "#16794A", bold: true } } });
plan.getRange(`C5:C${lastRow}`).conditionalFormats.add("containsText", { text: "In Progress", format: { fill: "#FFF0C2", font: { color: "#8A5B00", bold: true } } });
plan.getRange(`C5:C${lastRow}`).conditionalFormats.add("containsText", { text: "Pending", format: { fill: "#ECEFF2", font: { color: C.gray } } });
plan.getRange(`C5:C${lastRow}`).conditionalFormats.add("containsText", { text: "For Evaluation", format: { fill: "#DBEAFE", font: { color: "#1D4ED8", bold: true } } });
plan.getRange("A:A").format.columnWidth = 10;
plan.getRange("B:B").format.columnWidth = 43;
plan.getRange("C:C").format.columnWidth = 15;
plan.getRange("D:E").format.columnWidth = 14;
plan.getRange("F:F").format.columnWidth = 13;
plan.getRange(`G:${last}`).format.columnWidth = 4.5;
plan.getRange(`A5:${last}${lastRow}`).format.rowHeight = 22;
for (const r of phaseRows) plan.getRange(`A${r}:${last}${r}`).format.rowHeight = 24;
plan.freezePanes.unfreeze();
plan.getRange(`A3:${last}${lastRow}`).format.autofitRows();

milestones.showGridLines = false;
milestones.mergeCells("A1:F1");
milestones.getRange("A1").values = [["CRAYCARE MILESTONES & STATUS"]];
milestones.getRange("A1:F1").format = { fill: C.navy, font: { name: font, size: 16, bold: true, color: C.white }, horizontalAlignment: "center", verticalAlignment: "center" };
milestones.getRange("A3:F3").values = [["Milestone", "Target Date", "Status", "Related Phase", "Expected Output", "Remarks"]];
milestones.getRange("A3:F3").format = { fill: C.teal, font: { name: font, size: 10, bold: true, color: C.white }, horizontalAlignment: "center", verticalAlignment: "center", wrapText: true };
const ms = [
  ["Official title approval", "2026-04-30", "Completed", "Proposal", "Approved CrayCare title", "Foundation for Chapters 1-3"],
  ["Submission of Chapters 1-3", "2026-05-31", "Completed", "Documentation", "Complete proposal manuscript", "For adviser/panel review"],
  ["Working proposal prototype", "2026-07-12", "Completed", "Prototype", "Hardware and mobile demo", "Ready for proposal defense"],
  ["Final proposal defense", "2026-07-17", "Completed", "Defense", "Panel evaluation and corrections", "Corrections tracked in plan"],
  ["Final hardware calibration and tank integration", "2026-09-30", "In Progress", "Implementation", "Calibrated and fully integrated tank hardware", "Final build, wiring, casing, and validation continue in September"],
  ["Deployment-ready CrayCare system", "2026-09-30", "In Progress", "Software", "Production-ready app, cloud, feeder, actuators, and alerts", "Required before actual tank deployment"],
  ["ML supporting feature validation", "2026-10-07", "Pending", "Machine Learning", "Validated anomaly-detection results", "Advisory feature; not direct actuator control"],
  ["CrayCare deployed to actual tank", "2026-10-07", "Pending", "Deployment", "Operational system installed in the actual tank", "Live implementation begins in October"],
  ["Integrated field-tested system", "2026-11-15", "Pending", "Testing", "Live-operation, field-test, and usability evidence", "Includes October operational data"],
  ["Chapter 4 completion", "2026-12-07", "Pending", "Documentation", "Results and discussion", "Based on live system and evaluation data"],
  ["Chapter 5 and full manuscript", "2026-12-13", "Pending", "Documentation", "Complete Chapters 1-5", "Ready for final review"],
  ["Final oral defense", "2026-12-20", "Pending", "Defense", "Final presentation and panel feedback", "Prepare system demonstration"],
  ["Final submission and closure", "2026-12-31", "Pending", "Closure", "Approved bound manuscript and archive", "Close project records"],
];
const milestoneLastRow = 3 + ms.length;
milestones.getRange(`A4:F${milestoneLastRow}`).values = ms.map(x => [x[0], d(x[1]), x[2], x[3], x[4], x[5]]);
milestones.getRange(`B4:B${milestoneLastRow}`).format.numberFormat = "mmm d, yyyy";
milestones.getRange(`C4:C${milestoneLastRow}`).dataValidation = { rule: { type: "list", values: statuses } };
milestones.getRange(`A4:F${milestoneLastRow}`).format = { font: { name: font, size: 10, color: C.text }, verticalAlignment: "center", wrapText: true, borders: { insideHorizontal: { style: "thin", color: "#D8E5E4" }, bottom: { style: "thin", color: "#B7D8D5" } } };
milestones.getRange(`C4:C${milestoneLastRow}`).conditionalFormats.add("containsText", { text: "Completed", format: { fill: "#DDF4E7", font: { color: "#16794A", bold: true } } });
milestones.getRange(`C4:C${milestoneLastRow}`).conditionalFormats.add("containsText", { text: "In Progress", format: { fill: "#FFF0C2", font: { color: "#8A5B00", bold: true } } });
milestones.getRange(`C4:C${milestoneLastRow}`).conditionalFormats.add("containsText", { text: "Pending", format: { fill: "#ECEFF2", font: { color: C.gray } } });
milestones.getRange("A:A").format.columnWidth = 31; milestones.getRange("B:B").format.columnWidth = 15;
milestones.getRange("C:C").format.columnWidth = 15; milestones.getRange("D:D").format.columnWidth = 20;
milestones.getRange("E:E").format.columnWidth = 34; milestones.getRange("F:F").format.columnWidth = 38;
milestones.getRange(`A4:F${milestoneLastRow}`).format.rowHeight = 34;
milestones.freezePanes.unfreeze();

lists.showGridLines = false;
lists.getRange("A1:B1").values = [["Status", "Phase"]];
lists.getRange("A1:B1").format = { fill: C.navy, font: { name: font, size: 10, bold: true, color: C.white } };
lists.getRange("A2:A5").values = statuses.map(x => [x]);
lists.getRange("B2:B10").values = groups.map(x => [x[1]]);
lists.getRange("A1:B10").format.font = { name: font, size: 10, color: C.text };
lists.getRange("A:A").format.columnWidth = 20; lists.getRange("B:B").format.columnWidth = 45;

plan.tabColor = C.navy; milestones.tabColor = C.teal; lists.tabColor = C.gray;
wb.recalculate();
await fs.mkdir("docs/deliverables", { recursive: true });
const preview = await wb.render({ sheetName: "Implementation Plan", range: `A1:${last}${Math.min(lastRow, 35)}`, scale: 0.85, format: "png" });
await fs.writeFile(".codex-work/implementation-plan/preview.png", new Uint8Array(await preview.arrayBuffer()));
const previewBottom = await wb.render({ sheetName: "Implementation Plan", range: `A55:${last}${lastRow}`, scale: 0.85, format: "png" });
await fs.writeFile(".codex-work/implementation-plan/preview-bottom.png", new Uint8Array(await previewBottom.arrayBuffer()));
const previewMid = await wb.render({ sheetName: "Implementation Plan", range: `A38:${last}75`, scale: 0.85, format: "png" });
await fs.writeFile(".codex-work/implementation-plan/preview-mid.png", new Uint8Array(await previewMid.arrayBuffer()));
const previewMilestones = await wb.render({ sheetName: "Milestones & Status", range: `A1:F${milestoneLastRow}`, scale: 1, format: "png" });
await fs.writeFile(".codex-work/implementation-plan/preview-milestones.png", new Uint8Array(await previewMilestones.arrayBuffer()));
const xlsx = await SpreadsheetFile.exportXlsx(wb);
await xlsx.save(outPath);

const inspect = await wb.inspect({ kind: "sheet,formula", maxChars: 5000, options: { maxResults: 50 } });
console.log(inspect.ndjson);
console.log(JSON.stringify({ outPath, taskCount: taskRows.length, lastRow, lastCol: last }));
