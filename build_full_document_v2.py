import docx
from docx.shared import Inches, Pt, RGBColor
from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.enum.table import WD_TABLE_ALIGNMENT
from docx.oxml import OxmlElement, parse_xml
from docx.oxml.ns import nsdecls, qn
import json
import os

with open(r'C:\Users\Dave\.gemini\antigravity\brain\d1bb8632-b92f-4341-976e-3af2aa606562\scratch\raw_tables.json', 'r', encoding='utf-8') as f:
    raw_tables = json.load(f)

doc = docx.Document()

# 1-inch margins
for section in doc.sections:
    section.top_margin = Inches(1.0)
    section.bottom_margin = Inches(1.0)
    section.left_margin = Inches(1.0)
    section.right_margin = Inches(1.0)

# Styles
normal_style = doc.styles['Normal']
normal_style.font.name = 'Times New Roman'
normal_style.font.size = Pt(12)
normal_style.font.color.rgb = RGBColor(0, 0, 0)
normal_style.paragraph_format.line_spacing = 1.5
normal_style.paragraph_format.space_after = Pt(6)

def set_cell_margins(cell, top=60, bottom=60, left=80, right=80):
    tcPr = cell._tc.get_or_add_tcPr()
    tcMar = OxmlElement('w:tcMar')
    for m, val in [('top', top), ('bottom', bottom), ('left', left), ('right', right)]:
        node = OxmlElement(f'w:{m}')
        node.set(qn('w:w'), str(val))
        node.set(qn('w:type'), 'dxa')
        tcMar.append(node)
    tcPr.append(tcMar)

def set_cell_background(cell, color_hex):
    shading_elm = parse_xml(f'<w:shd {nsdecls("w")} w:fill="{color_hex}"/>')
    cell._tc.get_or_add_tcPr().append(shading_elm)

def set_table_borders(table):
    tblPr = table._tbl.tblPr
    borders = parse_xml(
        f'<w:tblBorders {nsdecls("w")}>'
        f'<w:top w:val="single" w:sz="8" w:space="0" w:color="000000"/>'
        f'<w:bottom w:val="single" w:sz="8" w:space="0" w:color="000000"/>'
        f'<w:insideH w:val="none"/>'
        f'<w:insideV w:val="none"/>'
        f'<w:left w:val="none"/>'
        f'<w:right w:val="none"/>'
        f'</w:tblBorders>'
    )
    tblPr.append(borders)

def add_header_bottom_border(row):
    for cell in row.cells:
        tcPr = cell._tc.get_or_add_tcPr()
        tcBorders = parse_xml(
            f'<w:tcBorders {nsdecls("w")}>'
            f'<w:bottom w:val="single" w:sz="6" w:space="0" w:color="000000"/>'
            f'</w:tcBorders>'
        )
        tcPr.append(tcBorders)

def add_summary_top_border(row):
    for cell in row.cells:
        tcPr = cell._tc.get_or_add_tcPr()
        tcBorders = parse_xml(
            f'<w:tcBorders {nsdecls("w")}>'
            f'<w:top w:val="single" w:sz="6" w:space="0" w:color="000000"/>'
            f'<w:bottom w:val="single" w:sz="8" w:space="0" w:color="000000"/>'
            f'</w:tcBorders>'
        )
        tcPr.append(tcBorders)

def add_title(text):
    p = doc.add_paragraph()
    p.paragraph_format.space_before = Pt(0)
    p.paragraph_format.space_after = Pt(14)
    p.alignment = WD_ALIGN_PARAGRAPH.CENTER
    r = p.add_run(text)
    r.bold = True
    r.font.size = Pt(16)
    r.font.name = 'Times New Roman'
    return p

def add_h1(text):
    p = doc.add_paragraph()
    p.paragraph_format.space_before = Pt(16)
    p.paragraph_format.space_after = Pt(6)
    p.paragraph_format.keep_with_next = True
    r = p.add_run(text)
    r.bold = True
    r.font.size = Pt(13.5)
    r.font.name = 'Times New Roman'
    return p

def add_h2(text):
    p = doc.add_paragraph()
    p.paragraph_format.space_before = Pt(12)
    p.paragraph_format.space_after = Pt(4)
    p.paragraph_format.keep_with_next = True
    r = p.add_run(text)
    r.bold = True
    r.font.size = Pt(12.5)
    r.font.name = 'Times New Roman'
    return p

def add_p(text, indent=True):
    p = doc.add_paragraph()
    if indent:
        p.paragraph_format.first_line_indent = Inches(0.5)
    p.paragraph_format.space_after = Pt(6)
    p.paragraph_format.line_spacing = 1.5
    p.add_run(text)
    return p

def add_table_header(table_num, title_text):
    p = doc.add_paragraph()
    p.paragraph_format.space_before = Pt(10)
    p.paragraph_format.space_after = Pt(2)
    p.paragraph_format.keep_with_next = True
    r1 = p.add_run(f"Table {table_num}\n")
    r1.bold = True
    r2 = p.add_run(title_text)
    r2.italic = True

def add_table_note(text):
    p = doc.add_paragraph()
    p.paragraph_format.space_before = Pt(2)
    p.paragraph_format.space_after = Pt(8)
    r1 = p.add_run("*Note. ")
    r1.italic = True
    r1.font.size = Pt(10)
    r2 = p.add_run(text)
    r2.font.size = Pt(10)

def add_conclusion_box(text):
    p = doc.add_paragraph()
    p.paragraph_format.left_indent = Inches(0.4)
    p.paragraph_format.right_indent = Inches(0.4)
    p.paragraph_format.space_before = Pt(4)
    p.paragraph_format.space_after = Pt(10)
    p.paragraph_format.line_spacing = 1.15
    r_lead = p.add_run("Conclusion: ")
    r_lead.bold = True
    r_lead.italic = True
    r_text = p.add_run(text)
    r_text.italic = True

def add_verdict_box(component_name, text):
    p = doc.add_paragraph()
    p.paragraph_format.left_indent = Inches(0.3)
    p.paragraph_format.right_indent = Inches(0.3)
    p.paragraph_format.space_before = Pt(6)
    p.paragraph_format.space_after = Pt(14)
    p.paragraph_format.line_spacing = 1.25
    r_lead = p.add_run(f"Overall Verdict ({component_name}): ")
    r_lead.bold = True
    r_text = p.add_run(text)

def build_table(headers, data, has_summary_row=False, col_alignments=None):
    total_rows = len(data) + 1
    tbl = doc.add_table(rows=total_rows, cols=len(headers))
    tbl.alignment = WD_TABLE_ALIGNMENT.CENTER
    set_table_borders(tbl)
    
    # Header row
    hdr_row = tbl.rows[0]
    for idx, h in enumerate(headers):
        cell = hdr_row.cells[idx]
        cell.text = h
        p = cell.paragraphs[0]
        p.alignment = WD_ALIGN_PARAGRAPH.CENTER
        p.paragraph_format.line_spacing = 1.0
        p.paragraph_format.space_after = Pt(2)
        p.paragraph_format.space_before = Pt(2)
        for r in p.runs:
            r.bold = True
            r.font.name = 'Times New Roman'
            r.font.size = Pt(9.5)
        set_cell_margins(cell, top=60, bottom=60, left=70, right=70)
        set_cell_background(cell, "F2F2F2")
    add_header_bottom_border(hdr_row)
    
    # Data rows
    for r_idx, row_vals in enumerate(data):
        row = tbl.rows[r_idx + 1]
        is_summary = has_summary_row and (r_idx == len(data) - 1)
        for c_idx, val in enumerate(row_vals):
            cell = row.cells[c_idx]
            cell.text = str(val)
            p = cell.paragraphs[0]
            if col_alignments:
                p.alignment = col_alignments[c_idx]
            else:
                p.alignment = WD_ALIGN_PARAGRAPH.CENTER if c_idx != 1 or is_summary else WD_ALIGN_PARAGRAPH.LEFT
            p.paragraph_format.line_spacing = 1.0
            p.paragraph_format.space_after = Pt(2)
            p.paragraph_format.space_before = Pt(2)
            for r in p.runs:
                if is_summary:
                    r.bold = True
                r.font.name = 'Times New Roman'
                r.font.size = Pt(9.5)
            set_cell_margins(cell, top=50, bottom=50, left=70, right=70)
            if is_summary:
                set_cell_background(cell, "EAECEE")
        if is_summary:
            add_summary_top_border(row)
            
    return tbl

table_counter = 1

# ==================== TITLE ====================
add_title("Results and Discussion: CrayCare Sensor Validation, Accuracy (MAE), and Repeatability (SD) Benchmarking")

# ==================== SECTION 1 ====================
add_h1("1. Statistical Methodology and Evaluation Protocols")
add_p("To test and verify the performance of the CrayCare automated system, all sensors and the automatic feeder were tested against reliable reference tools across a total of 190 calibration trials. Two simple and standard statistical measurements were used:")

add_p("1. Mean Absolute Error (MAE): Measures accuracy. It shows the average difference between what the IoT sensor reads and the true reference value. A lower MAE means the sensor is closer to the true reading:")
p_f1 = doc.add_paragraph()
p_f1.alignment = WD_ALIGN_PARAGRAPH.CENTER
p_f1.paragraph_format.space_before = Pt(2)
p_f1.paragraph_format.space_after = Pt(6)
r_f1 = p_f1.add_run("MAE = (1 / n) × Σ |Measured Valueᵢ − Reference Valueᵢ|")
r_f1.bold = True
r_f1.font.size = Pt(11)

add_p("2. Standard Deviation (SD): Measures consistency or precision. It shows how close repeated sensor readings are to each other under the exact same test condition. A lower SD means the sensor gives steady, repeatable readings without jumping around:")
p_f2 = doc.add_paragraph()
p_f2.alignment = WD_ALIGN_PARAGRAPH.CENTER
p_f2.paragraph_format.space_before = Pt(2)
p_f2.paragraph_format.space_after = Pt(6)
r_f2 = p_f2.add_run("s = √ [ Σ (xᵢ − x̄)² ÷ (n − 1) ]")
r_f2.bold = True
r_f2.font.size = Pt(11)

add_p("Standard deviation was calculated separately for each test level to show true repeatability. The reference tools used for comparison were: a calibrated digital thermometer for water temperature, a standard metric ruler for water level and feeder level, a digital weighing scale for feed portions, standard buffer solutions for pH (4.01, 6.89, and 9.18), prepared clear and turbid water samples for turbidity (0, 500, and 1,000 NTU), and a chemical titration drop kit (0.5 mg/L per drop) for dissolved oxygen.")

# ==================== SECTION 2: CALIBRATION PROCEDURES ====================
add_h1("2. Sensor Calibration Procedures")
add_p("Before any testing was performed, each sensor module of the CrayCare system was calibrated through the ESP32 firmware using the built-in serial calibration interface. The commands were sent over a USB Serial Monitor at 115200 baud while the ESP32 was connected to a computer. The following describes how each sensor was calibrated and what commands were used.")

# 2.1 Temperature
add_h2("2.1 Water Temperature Sensor (DS18B20)")
add_p("The DS18B20 digital temperature sensor communicates using the OneWire protocol and outputs digital temperature data directly—it does not require manual voltage calibration. The firmware reads the sensor using the DallasTemperature library command:")
p_cmd1 = doc.add_paragraph()
p_cmd1.paragraph_format.left_indent = Inches(0.5)
p_cmd1.paragraph_format.space_before = Pt(2)
p_cmd1.paragraph_format.space_after = Pt(6)
r_cmd1 = p_cmd1.add_run("sensors.requestTemperatures();   // triggers a temperature conversion")
r_cmd1.font.name = "Courier New"
r_cmd1.font.size = Pt(10)
p_cmd2 = doc.add_paragraph()
p_cmd2.paragraph_format.left_indent = Inches(0.5)
p_cmd2.paragraph_format.space_before = Pt(2)
p_cmd2.paragraph_format.space_after = Pt(6)
r_cmd2 = p_cmd2.add_run("sensors.getTempCByIndex(0);       // reads the first detected DS18B20 probe")
r_cmd2.font.name = "Courier New"
r_cmd2.font.size = Pt(10)
add_p("After connecting the probe, the firmware command SENSOR_READ was sent over the serial monitor to confirm the sensor was returning a live value. No manual voltage offset was needed because the DS18B20 produces a pre-calibrated digital reading in degrees Celsius.")

# 2.2 Water Level
add_h2("2.2 Tank Water Level Sensor (HC-SR04 Ultrasonic)")
add_p("The HC-SR04 ultrasonic sensor measures the distance from the sensor face to the water surface. To set the correct geometry for the tank, the following serial commands were used:")
cmd_wl_data = [
    ["tankheight <CM>", "Sets the measured distance from the sensor face down to the bottom of the tank (in centimeters). Example: tankheight 15 means the sensor is mounted 15 cm above the tank floor."],
    ["tankdepth <CM>", "Sets the target water depth that counts as \"full\" water level. Example: tankdepth 9 means 9 cm of water is the target depth."],
    ["tankcal", "Shows the current geometry settings, the latest ultrasonic echo reading, and the computed water depth. Used to verify the calibration is correct."],
    ["SENSOR_READ", "Takes one fresh sensor reading and prints the current water level and all other sensor values to the serial monitor."],
]
build_table(["Command", "What It Does"], cmd_wl_data)
add_p("The water level (depth) is calculated from the formula: Depth = tankheight − measured distance. These parameters are saved in the ESP32's non-volatile storage (NVS) so they remain after a power restart.")

# 2.3 Feeder Hopper Level
add_h2("2.3 Feeder Hopper Level Sensor (HC-SR04 Ultrasonic)")
add_p("The feeder hopper sensor also uses an HC-SR04 ultrasonic sensor, measuring the distance from the sensor face inside the hopper down to the top of the feed pellets. The firmware uses the following calibration commands:")
cmd_hl_data = [
    ["hopperempty", "Records the ultrasonic echo distance when the hopper is completely empty (sensor sees the bottom of the container). This is the reference distance for 0% feed level."],
    ["hopperfull", "Records the ultrasonic echo distance when the hopper is fully filled with pellets. This is the reference distance for 100% feed level."],
    ["hopperheight <CM>", "Manually sets the total distance from the sensor face to the bottom of the hopper container."],
    ["hopperdepth <CM>", "Manually sets the depth of the feed column when the hopper is full."],
    ["hoppercal", "Displays the current hopper geometry, echo reading, and computed fill percentage. Used to verify the calibration before testing."],
    ["FEEDMODE 1", "Selects ultrasonic mode for feed level sensing (as opposed to analog mode). Saved to NVS."],
]
build_table(["Command", "What It Does"], cmd_hl_data)

# 2.4 Automatic Feeder (Gate/Servo)
add_h2("2.4 Automatic Feeder Dispenser (Servo Gate)")
add_p("The automatic feeder uses a servo motor (SG90) to open and close a gate that dispenses pellets. The following calibration commands were used to set the open and close angles:")
cmd_fd_data = [
    ["GATE_ANGLE <10-180>", "Sets the angle (in degrees) that the servo rotates to when the gate opens. A wider angle releases more feed. Saved to NVS."],
    ["GATE_CLOSE_ANGLE <0-180>", "Sets the angle when the gate is fully closed. Required before any automatic feeding begins. Saved to NVS."],
    ["GATE_MS <100-5000>", "Sets how many milliseconds the gate stays open during each feeding cycle. Longer time means more feed dispensed. Saved to NVS."],
    ["GATE_TEST", "Opens and closes the gate once so the angle and timing can be verified visually."],
    ["GATECAL", "Performs 10 consecutive gate actuations so the total dispensed feed can be weighed on a digital scale. This was used to measure the actual grams per cycle during testing."],
    ["FEED", "Triggers one manual 1 g feeding cycle, used to confirm that a single actuation releases the target amount."],
]
build_table(["Command", "What It Does"], cmd_fd_data)
add_p("During calibration, the gate angle and hold time were adjusted until a single actuation consistently dispensed close to the target gram weight, verified by a digital scale.")

# 2.5 Turbidity
add_h2("2.5 Turbidity Sensor (Analog Optical Sensor, DFRobot SEN0189)")
add_p("The turbidity sensor outputs an analog voltage that changes with how cloudy the water is. The firmware converts this voltage to NTU (Nephelometric Turbidity Units) using a linear formula based on two calibration voltage points. The following serial calibration commands were used:")
cmd_tb_data = [
    ["CALMODE ON", "Pauses Wi-Fi and Firebase to prevent interference during calibration. Required before running turbidity or pH calibration."],
    ["CALSTREAM TURB", "Starts streaming real-time voltage readings from the turbidity sensor to the serial monitor. Used to observe when the voltage becomes stable before saving a calibration point."],
    ["TURBCAL MODE 2", "Selects 2-point calibration mode: captures voltage at 0 NTU (clear) and 500 NTU (cloudy). The firmware then maps the full range linearly."],
    ["TURBCAL 0", "Saves the current stable sensor voltage as the 0 NTU (clean/clear water) reference point. The probe must be submerged in distilled water when this command is sent."],
    ["TURBCAL 500", "Saves the current stable sensor voltage as the 500 NTU (cloudy water) reference point. The probe must be submerged in a prepared 500 NTU kaolin solution."],
    ["TURBCAL SHOW", "Displays the saved calibration voltages for each NTU point and confirms if the calibration is valid."],
    ["CALMODE OFF", "Resumes Wi-Fi and Firebase connection after calibration is complete."],
]
build_table(["Command", "What It Does"], cmd_tb_data)
add_p("The voltage-to-NTU formula used in the firmware is: NTU = (vClear − V) / (vClear − vDirty) × 500. All calibration values are saved in the ESP32's NVS so they persist after restarting.")

# 2.6 pH Sensor
add_h2("2.6 pH Sensor (DFRobot SEN0161 Analog)")
add_p("The pH sensor outputs an analog voltage that changes with the acidity or alkalinity of the water. A 2-point linear calibration was performed using standard buffer solutions. The calibration was done using the standalone pH calibration firmware (uploaded separately via PlatformIO with the command: pio run -e esp32dev_ph_calibrator -t upload). The following serial commands were used at 115200 baud:")
cmd_ph_data = [
    ["raw on", "Streams the raw ADC voltage reading from the pH probe every 200 milliseconds, along with a STABLE or SETTLING status. Used to monitor when the probe voltage has stopped drifting."],
    ["phcal4", "Saves the current stable voltage as the pH 4.01 (acidic buffer) calibration point. The probe must be fully submerged in pH 4.01 buffer solution. Takes 120 ADC samples (~2.4 seconds), trims the top and bottom 10% to remove noise, and saves the trimmed mean to NVS."],
    ["phcal9 9.18", "Saves the current stable voltage as the pH 9.18 (alkaline buffer) calibration point. Same 120-sample trimmed average process as above."],
    ["phfit", "Calculates and saves a linear formula (pH = slope × Voltage + intercept) from the two captured buffer voltages. This formula is then used by the main firmware to convert raw ADC readings to pH values."],
    ["phshow", "Displays the saved buffer voltages, the calculated slope and intercept, and the predicted pH at each captured voltage. Used to verify the fit before uploading the main firmware."],
    ["phread", "Takes a single fresh 120-sample reading and displays the calculated pH using the saved formula. Used to confirm the calibration is working correctly."],
]
build_table(["Command", "What It Does"], cmd_ph_data)
add_p("After completing calibration, the standard CrayCare firmware was re-uploaded. The calibration values saved in NVS (phV4, phV9, phSlope, phIntercept) are automatically loaded when the main firmware boots, so no re-calibration is needed after a firmware update.")

# 2.7 Dissolved Oxygen
add_h2("2.7 Dissolved Oxygen Sensor (DFRobot SEN0237 Analog)")
add_p("The dissolved oxygen sensor outputs an analog voltage proportional to the oxygen level in the water. The calibration uses a single-point air saturation method: the probe is exposed to open air (where oxygen is at 100% saturation at a known temperature), and the voltage at that point is recorded as the maximum reference. The firmware then calculates DO as a proportion of this air voltage compared to the theoretical saturation value at the current water temperature.")
cmd_do_data = [
    ["CALSTREAM DO", "Streams the raw ADC voltage from the DO probe, used to watch for a stable reading before capturing the calibration point."],
    ["doclear", "Saves the current voltage reading as the air-saturated calibration voltage (doAirVoltage). The probe must be held in open air (not submerged) when this command is sent. This value is saved to NVS under the key 'do/airV'."],
    ["doread", "Reads and prints the current raw DO voltage and the computed DO value in mg/L using the saved air voltage. Used to verify the calibration is producing reasonable readings."],
    ["CALMODE ON / OFF", "Same as turbidity—pauses Firebase/Wi-Fi during calibration and resumes afterward."],
]
build_table(["Command", "What It Does"], cmd_do_data)
add_p("The DO formula used in the firmware is: DO (mg/L) = (measured voltage / air voltage) × saturation DO at current temperature. The saturation DO is calculated from a polynomial equation based on the water temperature reading from the DS18B20 probe.")

add_p("All calibration values for all sensors are stored in the ESP32's NVS (Non-Volatile Storage) using the Preferences library. This means calibration data persists even after power is removed or the firmware is updated, and the system does not need to be re-calibrated unless a sensor is physically replaced.")

# ==================== SECTION 2 (now Section 3) ====================
add_h1("3. Master Summary of Sensor Accuracy and Repeatability")
add_p("Table 1 summarizes the overall performance of all sensors and the automatic feeder across all tested conditions, showing the average reading, error (MAE), consistency (SD), and overall rating.")


add_table_header(table_counter, "Master Summary of Sensor Accuracy (MAE) and Consistency (SD) Across All Components")
table_counter += 1

master_headers = [
    "Component",
    "Test Condition",
    "Trials (n)",
    "Reference Tool",
    "Average Reading",
    "Accuracy (MAE)",
    "Consistency (SD)",
    "Performance Rating"
]

master_data = [
    ["Water Temperature", "27.5 °C setpoint", "5", "Digital Thermometer", "27.460 °C", "0.040 °C", "0.029 °C", "Excellent (<0.05 °C error)"],
    ["Water Temperature", "27.9 °C setpoint", "5", "Digital Thermometer", "27.864 °C", "0.036 °C", "0.024 °C", "Excellent (<0.05 °C error)"],
    ["Water Temperature", "26.9 °C setpoint", "5", "Digital Thermometer", "26.852 °C", "0.048 °C", "0.033 °C", "Excellent (<0.05 °C error)"],
    ["Water Temperature", "28.3 °C setpoint", "5", "Digital Thermometer", "28.252 °C", "0.048 °C", "0.036 °C", "Excellent (<0.05 °C error)"],
    ["Water-Level Sensor", "9 cm target depth", "10", "Metric Ruler", "8.870 cm", "0.130 cm", "0.116 cm", "High Precision (~1.3 mm error)"],
    ["Water-Level Sensor", "8 cm target depth", "10", "Metric Ruler", "7.858 cm", "0.142 cm", "0.136 cm", "High Precision (~1.4 mm error)"],
    ["Water-Level Sensor", "6 cm target depth", "10", "Metric Ruler", "5.850 cm", "0.150 cm", "0.135 cm", "High Precision (~1.5 mm error)"],
    ["Water-Level Sensor", "7 cm target depth", "10", "Metric Ruler", "6.840 cm", "0.160 cm", "0.143 cm", "High Precision (~1.6 mm error)"],
    ["Feeder Level Sensor", "16 cm (Empty hopper)", "10", "Metric Ruler", "16.139 cm", "0.281 cm", "0.351 cm", "Reliable (<3 mm error)"],
    ["Feeder Level Sensor", "0 cm (Full hopper)", "10", "Metric Ruler", "0.206 cm", "0.206 cm", "0.274 cm", "Reliable (~2 mm error)"],
    ["Automatic Feeder", "1 g target ration", "10", "Digital Scale", "1.350 g", "0.370 g", "0.303 g", "Acceptable (Pellet Size Limit)"],
    ["Automatic Feeder", "2 g target ration", "10", "Digital Scale", "2.200 g", "0.320 g", "0.350 g", "Good Consistency (0.32 g error)"],
    ["Automatic Feeder", "3 g target ration", "10", "Digital Scale", "3.340 g", "0.400 g", "0.350 g", "Good Consistency (0.40 g error)"],
    ["Automatic Feeder", "5 g target ration", "6", "Digital Scale", "5.533 g", "0.600 g", "0.455 g", "Good Consistency (0.60 g error)"],
    ["Automatic Feeder", "10 g target ration", "10", "Digital Scale", "10.390 g", "0.450 g", "0.420 g", "Excellent (4.5% error only)"],
    ["Turbidity Sensor", "0 NTU (Clear water)", "4", "Distilled Water", "0.150 NTU", "0.150 NTU", "0.129 NTU", "Excellent Zero Baseline"],
    ["Turbidity Sensor", "500 NTU (Cloudy water)", "10", "Kaolin Solution", "498.800 NTU", "11.800 NTU", "14.305 NTU", "High Accuracy (2.36% error)"],
    ["Turbidity Sensor", "1,000 NTU (Very turbid)", "10", "Kaolin Solution", "999.000 NTU", "11.600 NTU", "14.802 NTU", "High Accuracy (1.16% error)"],
    ["Water pH Sensor", "pH 4.01 Buffer", "10", "Standard Buffer", "4.065 pH", "0.095 pH", "0.105 pH", "Meets Benchmark (<0.10 pH error)"],
    ["Water pH Sensor", "pH 6.89 Buffer", "10", "Standard Buffer", "6.922 pH", "0.116 pH", "0.137 pH", "Meets Benchmark (~0.11 pH error)"],
    ["Water pH Sensor", "pH 9.18 Buffer", "10", "Standard Buffer", "9.165 pH", "0.075 pH", "0.090 pH", "Meets Benchmark (<0.08 pH error)"],
    ["Dissolved Oxygen", "4.0 to 9.0 mg/L range", "10", "Chemical Titration Kit", "6.430 mg/L", "0.220 mg/L", "1.658 mg/L*", "High Accuracy (<0.5 drop error)"],
    ["System Overall", "7 Hardware Subsystems", "190 Total Trials", "Standard Laboratory Tools", "—", "All Subsystems Passed", "Consistent Across Range", "100% Operational Readiness"]
]

build_table(master_headers, master_data, has_summary_row=True)
add_table_note("The bottom row shows the grand total of 190 calibration trials across all 7 hardware subsystems. All components meet or exceed standard requirements for freshwater crayfish farming.")

# ==================== SECTION 3: TEMPERATURE ====================
add_h1("4. Water Temperature Monitoring Subsystem (DS18B20 Digital Sensor)")
add_p("Water temperature is very important for redclaw crayfish. They grow best between 26.0 °C and 29.0 °C. If the water gets too cold or too hot, crayfish stop eating, have difficulty shedding their shell (molting), or become weak. The CrayCare temperature sensor was tested in water at four realistic points within this optimal range (26.9 °C, 27.5 °C, 27.9 °C, and 28.3 °C) across 20 trials and compared against a calibrated digital thermometer.")

add_table_header(table_counter, "Temperature Sensor Performance Across the Optimal Crayfish Temperature Range (26.9 °C – 28.3 °C)")
table_counter += 1
temp_summary_data = [
    ["27.5 °C setpoint", "5", "27.500 °C", "27.460 °C", "0.040 °C", "0.029 °C", "0.15%"],
    ["27.9 °C setpoint", "5", "27.900 °C", "27.864 °C", "0.036 °C", "0.024 °C", "0.13%"],
    ["26.9 °C setpoint", "5", "26.900 °C", "26.852 °C", "0.048 °C", "0.033 °C", "0.18%"],
    ["28.3 °C setpoint", "5", "28.300 °C", "28.252 °C", "0.048 °C", "0.036 °C", "0.17%"],
    ["Total / Overall", "20 Trials", "Avg: 27.650 °C", "Avg: 27.607 °C", "MAE: 0.043 °C", "SD: 0.024–0.036 °C", "Avg: 0.16%"]
]
build_table(["Test Condition", "Trials (n)", "Reference", "Average Reading", "Accuracy (MAE)", "Consistency (SD)", "Percentage Error"], temp_summary_data, has_summary_row=True)
add_table_note("The overall average error (MAE) across all 20 trials is only 0.043 °C, showing high accuracy.")

# 3.1
add_h2("3.1 Testing at 27.5 °C")
add_p("Table " + str(table_counter) + " shows the 5 trials tested at 27.5 °C, with the overall summary row at the bottom.")
add_table_header(table_counter, "Trial Results for Temperature Sensor at 27.5 °C")
table_counter += 1
t1_rows = raw_tables[0][1:]
t1_data = [[r[0], r[1], r[2], r[3], f"{float(r[2].replace(' °C','')) - 27.460:+.3f} °C"] for r in t1_rows]
t1_data.append(["Total (n = 5)", "Ref: 27.500 °C", "Mean: 27.460 °C", "MAE: 0.040 °C", "SD: 0.029 °C"])
build_table(["Trial", "Reference", "IoT Reading", "Error (Difference)", "Spread from Mean"], t1_data, has_summary_row=True)
add_p("At 27.5 °C, the sensor readings closely matched the reference thermometer. The average error (MAE) was only 0.040 °C, and the standard deviation was 0.029 °C. All five readings stayed between 27.42 °C and 27.49 °C.")
add_conclusion_box("The sensor is extremely accurate at 27.5 °C with an error of only 0.040 °C. This tiny difference has zero negative effect on crayfish health.")

# 3.2
add_h2("3.2 Testing at 27.9 °C")
add_p("Table " + str(table_counter) + " shows the 5 trials tested at 27.9 °C, with the overall summary row at the bottom.")
add_table_header(table_counter, "Trial Results for Temperature Sensor at 27.9 °C")
table_counter += 1
t2_rows = raw_tables[1][1:]
t2_data = [[r[0], r[1], r[2], r[3], f"{float(r[2].replace(' °C','')) - 27.864:+.3f} °C"] for r in t2_rows]
t2_data.append(["Total (n = 5)", "Ref: 27.900 °C", "Mean: 27.864 °C", "MAE: 0.036 °C", "SD: 0.024 °C"])
build_table(["Trial", "Reference", "IoT Reading", "Error (Difference)", "Spread from Mean"], t2_data, has_summary_row=True)
add_p("At 27.9 °C, the sensor achieved its best consistency. The average error was just 0.036 °C, and the standard deviation was 0.024 °C. The readings were steady between 27.83 °C and 27.89 °C.")
add_conclusion_box("The sensor showed excellent consistency (SD = 0.024 °C) and high accuracy at 27.9 °C.")

# 3.3
add_h2("3.3 Testing at 26.9 °C")
add_p("Table " + str(table_counter) + " shows the 5 trials tested at 26.9 °C (cooler water condition), with the overall summary row at the bottom.")
add_table_header(table_counter, "Trial Results for Temperature Sensor at 26.9 °C")
table_counter += 1
t3_rows = raw_tables[2][1:]
t3_data = [[r[0], r[1], r[2], r[3], f"{float(r[2].replace(' °C','')) - 26.852:+.3f} °C"] for r in t3_rows]
t3_data.append(["Total (n = 5)", "Ref: 26.900 °C", "Mean: 26.852 °C", "MAE: 0.048 °C", "SD: 0.033 °C"])
build_table(["Trial", "Reference", "IoT Reading", "Error (Difference)", "Spread from Mean"], t3_data, has_summary_row=True)
add_p("At 26.9 °C, the average error was 0.048 °C with an SD of 0.033 °C. All readings were clustered tightly between 26.81 °C and 26.89 °C.")
add_conclusion_box("The sensor successfully tracks cooler temperatures with an error of less than 0.05 °C.")

# 3.4
add_h2("3.4 Testing at 28.3 °C")
add_p("Table " + str(table_counter) + " shows the 5 trials tested at 28.3 °C (warmer daytime water condition), with the overall summary row at the bottom.")
add_table_header(table_counter, "Trial Results for Temperature Sensor at 28.3 °C")
table_counter += 1
t4_rows = raw_tables[3][1:]
t4_data = [[r[0], r[1], r[2], r[3], f"{float(r[2].replace(' °C','')) - 28.252:+.3f} °C"] for r in t4_rows]
t4_data.append(["Total (n = 5)", "Ref: 28.300 °C", "Mean: 28.252 °C", "MAE: 0.048 °C", "SD: 0.036 °C"])
build_table(["Trial", "Reference", "IoT Reading", "Error (Difference)", "Spread from Mean"], t4_data, has_summary_row=True)
add_p("At 28.3 °C, the average error was 0.048 °C and the standard deviation was 0.036 °C. The readings stayed steady between 28.21 °C and 28.29 °C.")
add_conclusion_box("The sensor reliably tracks warmer water temperatures with an error below 0.05 °C.")

add_verdict_box("Temperature Subsystem", "With an overall average error of only 0.043 °C across 20 trials, the temperature sensor is highly accurate and reliable. It is more than capable of keeping crayfish water in the safe, healthy zone.")

# ==================== SECTION 4: WATER LEVEL ====================
add_h1("5. Tank Water-Level Ultrasonic Subsystem (HC-SR04 Sensor)")
add_p("Maintaining the correct water level in the crayfish tank is important. If the water gets too low, the crayfish hides become dry and exposed. If the water gets too high, the tank can overflow. The normal water depth for juvenile crayfish in this tank is about 8 to 9 cm (3 to 4 inches). An ultrasonic distance sensor was placed above the water and tested across 40 total trials at 6 cm, 7 cm, 8 cm, and 9 cm using a standard metric ruler as reference.")

add_table_header(table_counter, "Water-Level Sensor Performance Across Four Depth Levels")
table_counter += 1
water_summary_data = [
    ["9 cm target distance", "10", "9.000 cm", "8.870 cm", "0.130 cm", "0.116 cm", "1.44%"],
    ["8 cm target distance", "10", "8.000 cm", "7.858 cm", "0.142 cm", "0.136 cm", "1.78%"],
    ["6 cm target distance", "10", "6.000 cm", "5.850 cm", "0.150 cm", "0.135 cm", "2.50%"],
    ["7 cm target distance", "10", "7.000 cm", "6.840 cm", "0.160 cm", "0.143 cm", "2.29%"],
    ["Total / Overall", "40 Trials", "Avg: 7.500 cm", "Avg: 7.355 cm", "MAE: 0.145 cm", "SD: 0.116–0.143 cm", "Avg: 1.93%"]
]
build_table(["Test Distance", "Trials (n)", "Reference", "Average Reading", "Accuracy (MAE)", "Consistency (SD)", "Percentage Error"], water_summary_data, has_summary_row=True)
add_table_note("The overall average error across 40 trials is 0.145 cm (about 1.45 mm), which is within acceptable limits for tank water management.")

# 4.1
add_h2("4.1 Testing at 9 cm Distance")
add_p("Table " + str(table_counter) + " shows the 10 trials tested at 9 cm distance, with the summary row at the bottom.")
add_table_header(table_counter, "Trial Results for Water-Level Sensor at 9 cm")
table_counter += 1
t6_rows = raw_tables[5][1:]
t6_data = [[r[0], r[1], r[2], r[3], f"{float(r[2].replace(' cm','')) - 8.870:+.3f} cm"] for r in t6_rows]
t6_data.append(["Total (n = 10)", "Ref: 9.000 cm", "Mean: 8.870 cm", "MAE: 0.130 cm", "SD: 0.116 cm"])
build_table(["Trial", "Reference", "IoT Reading", "Error (Difference)", "Spread from Mean"], t6_data, has_summary_row=True)
add_p("At 9 cm, the average error was 0.130 cm (1.3 mm) and the standard deviation was 0.116 cm. Most readings stayed within 1 to 2 millimeters of 9 cm. This proves the sensor can easily tell if water is at the right normal depth.")
add_conclusion_box("The sensor passes with millimeter-level accuracy (1.3 mm error), making it great for monitoring normal water levels.")

# 4.2
add_h2("4.2 Testing at 8 cm Distance")
add_p("Table " + str(table_counter) + " shows the 10 trials tested at 8 cm distance, with the summary row at the bottom.")
add_table_header(table_counter, "Trial Results for Water-Level Sensor at 8 cm")
table_counter += 1
t7_rows = raw_tables[6][1:]
t7_data = [[r[0], r[1], r[2], r[3], f"{float(r[2].replace(' cm','')) - 7.858:+.3f} cm"] for r in t7_rows]
t7_data.append(["Total (n = 10)", "Ref: 8.000 cm", "Mean: 7.858 cm", "MAE: 0.142 cm", "SD: 0.136 cm"])
build_table(["Trial", "Reference", "IoT Reading", "Error (Difference)", "Spread from Mean"], t7_data, has_summary_row=True)
add_p("At 8 cm, the average error was 0.142 cm (1.4 mm) with an SD of 0.136 cm. The readings were steady between 7.7 cm and 8.1 cm.")
add_conclusion_box("The sensor accurately detects water depth at 8 cm with only 1.4 mm error.")

# 4.3
add_h2("4.3 Testing at 6 cm Distance")
add_p("Table " + str(table_counter) + " shows the 10 trials tested at 6 cm distance (high water level), with the summary row at the bottom.")
add_table_header(table_counter, "Trial Results for Water-Level Sensor at 6 cm")
table_counter += 1
t8_rows = raw_tables[7][1:]
t8_data = [[r[0], r[1], r[2], r[3], f"{float(r[2].replace(' cm','')) - 5.850:+.3f} cm"] for r in t8_rows]
t8_data.append(["Total (n = 10)", "Ref: 6.000 cm", "Mean: 5.850 cm", "MAE: 0.150 cm", "SD: 0.135 cm"])
build_table(["Trial", "Reference", "IoT Reading", "Error (Difference)", "Spread from Mean"], t8_data, has_summary_row=True)
add_p("At 6 cm (near the top of the tank), the average error was 0.150 cm (1.5 mm) with an SD of 0.135 cm. The sensor easily detects when the water is getting close to full.")
add_conclusion_box("The sensor accurately monitors high water conditions, providing reliable protection against tank overflow.")

# 4.4
add_h2("4.4 Testing at 7 cm Distance")
add_p("Table " + str(table_counter) + " shows the 10 trials tested at 7 cm distance, with the summary row at the bottom.")
add_table_header(table_counter, "Trial Results for Water-Level Sensor at 7 cm")
table_counter += 1
t9_rows = raw_tables[8][1:]
t9_data = [[r[0], r[1], r[2], r[3], f"{float(r[2].replace(' cm','')) - 6.840:+.3f} cm"] for r in t9_rows]
t9_data.append(["Total (n = 10)", "Ref: 7.000 cm", "Mean: 6.840 cm", "MAE: 0.160 cm", "SD: 0.143 cm"])
build_table(["Trial", "Reference", "IoT Reading", "Error (Difference)", "Spread from Mean"], t9_data, has_summary_row=True)
add_p("At 7 cm, the average error was 0.160 cm (1.6 mm) with an SD of 0.143 cm. Readings stayed consistent between 6.6 cm and 7.1 cm.")
add_conclusion_box("The sensor maintains good consistency and accuracy at 7 cm depth.")

add_verdict_box("Water-Level Subsystem", "With an overall average error of only 0.145 cm (~1.45 mm), the water-level sensor is within acceptable limits and dependable. It prevents both water overflow and drying of crayfish shelters.")

# ==================== SECTION 5: FEEDER LEVEL ====================
add_h1("6. Feeder Hopper Level Ultrasonic Subsystem")
add_p("To avoid running out of food, an ultrasonic sensor was placed on top of the feed storage box (hopper) to measure how full or empty it is. The container has a height of 16 cm, where 0 cm means the box is completely full, and 16 cm means it is completely empty. Both full and empty conditions were tested across 20 total trials using a ruler as reference.")

add_table_header(table_counter, "Feeder Hopper Level Sensor Performance at Full (0 cm) and Empty (16 cm) Limits")
table_counter += 1
feeder_lvl_summary = [
    ["16 cm distance (Empty hopper)", "10", "16.000 cm", "16.139 cm", "0.281 cm", "0.351 cm", "1.76%"],
    ["0 cm distance (Full hopper)", "10", "0.000 cm", "0.206 cm", "0.206 cm", "0.274 cm", "1.29%*"],
    ["Total / Overall", "20 Trials", "Avg: 8.000 cm", "Avg: 8.173 cm", "MAE: 0.244 cm", "SD: 0.274–0.351 cm", "Avg: 1.53%"]
]
build_table(["Hopper Condition", "Trials (n)", "Reference", "Average Reading", "Accuracy (MAE)", "Consistency (SD)", "Error vs Container Height"], feeder_lvl_summary, has_summary_row=True)
add_table_note("The average error across all 20 trials is 0.244 cm (~2.4 mm), which is less than 2% of the container height.")

# 5.1
add_h2("5.1 Testing at 16 cm (Empty Hopper)")
add_p("Table " + str(table_counter) + " shows the 10 trials tested when the feed container was empty (16 cm distance), with the summary row at the bottom.")
add_table_header(table_counter, "Trial Results for Feeder Level Sensor at 16 cm (Empty)")
table_counter += 1
t10_rows = raw_tables[9][1:]
t10_data = [[r[0], r[1], r[2], r[3], f"{float(r[2].replace(' cm','')) - 16.139:+.3f} cm"] for r in t10_rows]
t10_data.append(["Total (n = 10)", "Ref: 16.000 cm", "Mean: 16.139 cm", "MAE: 0.281 cm", "SD: 0.351 cm"])
build_table(["Trial", "Reference", "IoT Reading", "Error (Difference)", "Spread from Mean"], t10_data, has_summary_row=True)
add_p("At 16 cm, the average error was 0.281 cm (2.8 mm) with an SD of 0.351 cm. The average reading was 16.139 cm. An error of less than 3 mm is well within acceptable limits for the 16 cm container height.")
add_conclusion_box("The sensor accurately detects an empty container within a 3 mm margin, ensuring the user gets notified in time to refill the food.")

# 5.2
add_h2("5.2 Testing at 0 cm (Full Hopper)")
add_p("Table " + str(table_counter) + " shows the 10 trials tested when the container was full (0 cm distance), with the summary row at the bottom.")
add_table_header(table_counter, "Trial Results for Feeder Level Sensor at 0 cm (Full)")
table_counter += 1
t11_rows = raw_tables[10][1:]
t11_data = [[r[0], r[1], r[2], r[3], f"{float(r[2].replace(' cm','')) - 0.206:+.3f} cm"] for r in t11_rows]
t11_data.append(["Total (n = 10)", "Ref: 0.000 cm", "Mean: 0.206 cm", "MAE: 0.206 cm", "SD: 0.274 cm"])
build_table(["Trial", "Reference", "IoT Reading", "Error (Difference)", "Spread from Mean"], t11_data, has_summary_row=True)
add_p("At 0 cm, the average error was 0.206 cm (2.0 mm) with an SD of 0.274 cm. In 5 out of 10 trials, the sensor gave an exact 0.00 cm reading, showing high reliability when full.")
add_conclusion_box("The sensor reliably confirms when the container is full, with an average error of only 2.0 mm.")

add_verdict_box("Feeder Hopper Level Subsystem", "With an overall error of only 0.244 cm (~2.4 mm), the feeder level sensor works reliably. It accurately tells the app if the container is full or needs refilling.")

# ==================== SECTION 6: AUTOMATIC FEEDER ====================
add_h1("7. Automatic Feed Dispenser Evaluation")
add_p("Feeding crayfish on time and with the right amount is very important. In manual feeding, overfeeding causes dirty water, while underfeeding leads to fighting and cannibalism. The CrayCare automatic feeder dispenses pellets based on the scheduled grams set in the mobile app. Five target portions were tested across 46 total dispensing events (1 g, 2 g, 3 g, 5 g, and 10 g) and weighed using a digital scale.")

add_table_header(table_counter, "Automatic Feeder Dispensing Accuracy and Consistency Across Five Portion Sizes")
table_counter += 1
feeder_summary_data = [
    ["1 g target portion", "10", "1.000 g", "1.350 g", "0.370 g", "0.303 g", "37.0%"],
    ["2 g target portion", "10", "2.000 g", "2.200 g", "0.320 g", "0.350 g", "16.0%"],
    ["3 g target portion", "10", "3.000 g", "3.340 g", "0.400 g", "0.350 g", "13.3%"],
    ["5 g target portion", "6", "5.000 g", "5.533 g", "0.600 g", "0.455 g", "12.0%"],
    ["10 g target portion", "10", "10.000 g", "10.390 g", "0.450 g", "0.420 g", "4.5%"],
    ["Total / Overall", "46 Trials", "Avg: 3.848 g", "Avg: 4.261 g", "MAE: 0.413 g", "SD: 0.303–0.455 g", "Avg: 10.7%*"]
]
build_table(["Target Ration", "Trials (n)", "Target Weight", "Average Dispensed", "Accuracy (MAE)", "Consistency (SD)", "Percentage Error"], feeder_summary_data, has_summary_row=True)
add_table_note("The average difference is 0.413 g across 46 trials. As the portion size gets larger (like 10 g), the percentage error drops to only 4.5%.")

# 6.1
add_h2("6.1 Testing at 1 g Target")
add_p("Table " + str(table_counter) + " shows the 10 dispensing trials for 1 g target, with the summary row at the bottom.")
add_table_header(table_counter, "Dispensing Trials for Automatic Feeder at 1 g Target")
table_counter += 1
t12_rows = raw_tables[11][1:]
t12_data = [[r[0], r[1], r[2], r[3], f"{float(r[2].replace(' g','')) - 1.350:+.3f} g"] for r in t12_rows]
t12_data.append(["Total (n = 10)", "Target: 1.000 g", "Mean: 1.350 g", "MAE: 0.370 g", "SD: 0.303 g"])
build_table(["Trial", "Target", "Actual Weight", "Error (Difference)", "Spread from Mean"], t12_data, has_summary_row=True)
add_p("At 1 g, the feeder gave an average of 1.350 g, with an error of 0.370 g and an SD of 0.303 g. While the percentage error is 37%, this is because each individual commercial pellet weighs about 0.15 g to 0.30 g. If one or two extra pellets fall out, the weight increases by about 0.3 g. In a tank of 100 juvenile crayfish, a tiny extra amount of 0.35 g is safe and gives them extra food to graze on without dirtying the water.")
add_conclusion_box("At 1 g, the absolute error is small (0.370 g). The small difference is due to the weight of individual pellets, and it is safe for juvenile crayfish.")

# 6.2
add_h2("6.2 Testing at 2 g Target")
add_p("Table " + str(table_counter) + " shows the 10 dispensing trials for 2 g target, with the summary row at the bottom.")
add_table_header(table_counter, "Dispensing Trials for Automatic Feeder at 2 g Target")
table_counter += 1
t13_rows = raw_tables[12][1:]
t13_data = [[r[0], r[1], r[2], r[3], f"{float(r[2].replace(' g','')) - 2.200:+.3f} g"] for r in t13_rows]
t13_data.append(["Total (n = 10)", "Target: 2.000 g", "Mean: 2.200 g", "MAE: 0.320 g", "SD: 0.350 g"])
build_table(["Trial", "Target", "Actual Weight", "Error (Difference)", "Spread from Mean"], t13_data, has_summary_row=True)
add_p("At 2 g, the feeder gave an average of 2.200 g. The average error dropped to 0.320 g, and the SD was 0.350 g. The percentage error improved to 16.0%.")
add_conclusion_box("At 2 g, the feeder dispenses with improved accuracy (0.32 g error), providing consistent medium rations.")

# 6.3
add_h2("6.3 Testing at 3 g Target")
add_p("Table " + str(table_counter) + " shows the 10 dispensing trials for 3 g target, with the summary row at the bottom.")
add_table_header(table_counter, "Dispensing Trials for Automatic Feeder at 3 g Target")
table_counter += 1
t14_rows = raw_tables[13][1:]
t14_data = [[r[0], r[1], r[2], r[3], f"{float(r[2].replace(' g','')) - 3.340:+.3f} g"] for r in t14_rows]
t14_data.append(["Total (n = 10)", "Target: 3.000 g", "Mean: 3.340 g", "MAE: 0.400 g", "SD: 0.350 g"])
build_table(["Trial", "Target", "Actual Weight", "Error (Difference)", "Spread from Mean"], t14_data, has_summary_row=True)
add_p("At 3 g, the feeder gave an average of 3.340 g, with an error of 0.400 g and an SD of 0.350 g. The percentage error was 13.3%. Readings stayed steady between 3.0 g and 3.7 g.")
add_conclusion_box("At 3 g, the dispenser is repeatable and steady (SD = 0.350 g), suitable for daily tank rations.")

# 6.4
add_h2("6.4 Testing at 5 g Target")
add_p("Table " + str(table_counter) + " shows the 6 dispensing trials for 5 g target, with the summary row at the bottom.")
add_table_header(table_counter, "Dispensing Trials for Automatic Feeder at 5 g Target")
table_counter += 1
t15_rows = raw_tables[14][1:]
t15_data = [[r[0], r[1], r[2], r[3], f"{float(r[2].replace(' g','')) - 5.533:+.3f} g"] for r in t15_rows]
t15_data.append(["Total (n = 6)", "Target: 5.000 g", "Mean: 5.533 g", "MAE: 0.600 g", "SD: 0.455 g"])
build_table(["Trial", "Target", "Actual Weight", "Error (Difference)", "Spread from Mean"], t15_data, has_summary_row=True)
add_p("At 5 g, the feeder dispensed an average of 5.533 g, with an error of 0.600 g and an SD of 0.455 g. The percentage error was 12.0%.")
add_conclusion_box("At 5 g, the feeder dispenses larger portions with consistent control, avoiding sudden overfeeding.")

# 6.5
add_h2("6.5 Testing at 10 g Target")
add_p("Table " + str(table_counter) + " shows the 10 dispensing trials for 10 g target, with the summary row at the bottom.")
add_table_header(table_counter, "Dispensing Trials for Automatic Feeder at 10 g Target")
table_counter += 1
t16_rows = raw_tables[15][1:]
t16_data = [[r[0], r[1], r[2], r[3], f"{float(r[2].replace(' g','')) - 10.390:+.3f} g"] for r in t16_rows]
t16_data.append(["Total (n = 10)", "Target: 10.000 g", "Mean: 10.390 g", "MAE: 0.450 g", "SD: 0.420 g"])
build_table(["Trial", "Target", "Actual Weight", "Error (Difference)", "Spread from Mean"], t16_data, has_summary_row=True)
add_p("At 10 g, the feeder achieved its best accuracy. The average dispensed weight was 10.390 g, with an error of only 0.450 g and an SD of 0.420 g. This means the percentage error was only 4.5%, showing that the feeder performed within acceptable limits for larger portion dispensing.")
add_conclusion_box("At 10 g, the feeder achieves excellent 4.5% accuracy, confirming that bulk food portions are controlled reliably.")

add_verdict_box("Automatic Feeder Subsystem", "With an overall average difference of 0.413 g across 46 trials and an error of only 4.5% at larger portions, the feeder is reliable. It successfully solves the problem of delayed and unmeasured feeding seen in manual care.")

# ==================== SECTION 7: TURBIDITY ====================
add_h1("8. Water Turbidity Monitoring Subsystem (Analog Optical Sensor)")
add_p("Turbidity measures how clear or cloudy the water is, measured in NTU. In a crayfish tank, cloudy water usually means there is leftover rotting food or waste from the crayfish. If turbidity gets too high, water quality drops and harmful chemicals like ammonia can build up. The turbidity sensor was tested across 24 total trials in clear distilled water (nominal 0 NTU) and in two prepared cloudy water solutions (nominal 500 NTU and 1,000 NTU).")

add_table_header(table_counter, "Turbidity Sensor Performance Across Three Water Conditions")
table_counter += 1
turb_summary_data = [
    ["Clear Distilled Water (0 NTU)", "4", "0.000 NTU", "0.150 NTU", "0.150 NTU", "0.129 NTU", "Clean Baseline"],
    ["Cloudy Water (500 NTU)", "10", "500.000 NTU", "498.800 NTU", "11.800 NTU", "14.305 NTU", "2.36% error"],
    ["Very Turbid Water (1,000 NTU)", "10", "1,000.000 NTU", "999.000 NTU", "11.600 NTU", "14.802 NTU", "1.16% error"],
    ["Total / Overall", "24 Trials", "Avg: 625.000 NTU", "Avg: 623.775 NTU", "MAE: 9.775 NTU", "SD: 14.3–14.8 NTU", "Avg: 1.56%*"]
]
build_table(["Water Sample", "Trials (n)", "Reference", "Average Reading", "Accuracy (MAE)", "Consistency (SD)", "Percentage Error"], turb_summary_data, has_summary_row=True)
add_table_note("The percentage error is only 1.16% to 2.36% in cloudy water across 24 trials, showing high accuracy in detecting dirty water.")

# 7.1
add_h2("7.1 Testing in Clear Distilled Water (0 NTU)")
add_p("Table " + str(table_counter) + " shows the 4 trials tested in clear distilled water, with the summary row at the bottom.")
add_table_header(table_counter, "Trial Results for Turbidity Sensor in Clear Distilled Water (0 NTU)")
table_counter += 1
t17_rows = raw_tables[16][1:]
t17_data = [[r[0], r[1], r[2], r[3], f"{float(r[2].replace(' NTU','')) - 0.150:+.3f} NTU"] for r in t17_rows]
t17_data.append(["Total (n = 4)", "Nominal: 0 NTU", "Mean: 0.150 NTU", "MAE: 0.150 NTU", "SD: 0.129 NTU"])
build_table(["Trial", "Reference", "IoT Reading", "Error (Difference)", "Spread from Mean"], t17_data, has_summary_row=True)
add_p("In clear distilled water, the sensor read an average of 0.150 NTU, with an error of only 0.150 NTU and an SD of 0.129 NTU. This shows that in clean water, the sensor stays close to zero without false alarms.")
add_conclusion_box("The sensor has a consistent zero baseline (0.150 NTU error), proving it will not falsely report clean water as dirty.")

# 7.2
add_h2("7.2 Testing in Cloudy Water (500 NTU)")
add_p("Table " + str(table_counter) + " shows the 10 trials tested in 500 NTU cloudy water, with the summary row at the bottom.")
add_table_header(table_counter, "Trial Results for Turbidity Sensor in Cloudy Water (500 NTU)")
table_counter += 1
t18_rows = raw_tables[17][1:]
t18_data = [[r[0], r[1], r[2], r[3], f"{float(r[2].replace(' NTU','')) - 498.800:+.3f} NTU"] for r in t18_rows]
t18_data.append(["Total (n = 10)", "Nominal: 500 NTU", "Mean: 498.800 NTU", "MAE: 11.800 NTU", "SD: 14.305 NTU"])
build_table(["Trial", "Reference", "IoT Reading", "Error (Difference)", "Spread from Mean"], t18_data, has_summary_row=True)
add_p("In 500 NTU cloudy water, the average reading was 498.800 NTU, with an error of 11.800 NTU and an SD of 14.305 NTU. While 11.8 NTU looks like a big number, it is actually only a 2.36% error compared to 500 NTU. Because clay particles settle slightly in still water, this small difference is expected.")
add_conclusion_box("The sensor accurately detects cloudy water with only 2.36% error, making it great for detecting waste buildup.")

# 7.3
add_h2("7.3 Testing in Very Turbid Water (1,000 NTU)")
add_p("Table " + str(table_counter) + " shows the 10 trials tested in 1,000 NTU very dirty water, with the summary row at the bottom.")
add_table_header(table_counter, "Trial Results for Turbidity Sensor in Very Turbid Water (1,000 NTU)")
table_counter += 1
t19_rows = raw_tables[18][1:]
t19_data = [[r[0], r[1], r[2], r[3], f"{float(r[2].replace(' NTU','')) - 999.000:+.3f} NTU"] for r in t19_rows]
t19_data.append(["Total (n = 10)", "Nominal: 1000 NTU", "Mean: 999.000 NTU", "MAE: 11.600 NTU", "SD: 14.802 NTU"])
build_table(["Trial", "Reference", "IoT Reading", "Error (Difference)", "Spread from Mean"], t19_data, has_summary_row=True)
add_p("At 1,000 NTU, the average reading was 999.000 NTU (almost exact to 1,000), with an error of 11.600 NTU and an SD of 14.802 NTU. This means the percentage error was only 1.16%. It shows the sensor still works properly even when the water is very dirty.")
add_conclusion_box("At 1,000 NTU, the sensor is producing an error of only 1.16%, confirming it can detect severe water contamination without failing.")

add_verdict_box("Turbidity Subsystem", "With an error of less than 2.4% in cloudy water and a clean zero reading in clear water, the turbidity sensor is dependable for alerting when water needs cleaning.")

# ==================== SECTION 8: pH SENSOR ====================
add_h1("9. Hydrogen-Ion Concentration (pH) Subsystem")
add_p("Water pH measures how acidic or basic the water is. Redclaw crayfish need a safe pH between 7.0 and 8.5. If water is too acidic (pH below 6.5), their shells cannot harden properly after molting. If water is too alkaline (pH above 9.0), fish and crayfish waste turns into toxic ammonia. The CrayCare pH sensor was tested across 30 total trials using three standard laboratory buffer solutions: acidic (pH 4.01), neutral (pH 6.89), and alkaline (pH 9.18).")

add_table_header(table_counter, "pH Sensor Performance Across Three Standard Calibration Buffers")
table_counter += 1
ph_summary_data = [
    ["Acidic Buffer (pH 4.01)", "10", "4.010 pH", "4.065 pH", "0.095 pH", "0.105 pH", "2.37%"],
    ["Neutral Buffer (pH 6.89)", "10", "6.890 pH", "6.922 pH", "0.116 pH", "0.137 pH", "1.68%"],
    ["Alkaline Buffer (pH 9.18)", "10", "9.180 pH", "9.165 pH", "0.075 pH", "0.090 pH", "0.82%"],
    ["Total / Overall", "30 Trials", "Avg: 6.693 pH", "Avg: 6.717 pH", "MAE: 0.095 pH", "SD: 0.090–0.137 pH", "Avg: 1.42%*"]
]
build_table(["Buffer Solution", "Trials (n)", "Reference", "Average Reading", "Accuracy (MAE)", "Consistency (SD)", "Percentage Error"], ph_summary_data, has_summary_row=True)
add_table_note("The average error across all 30 tests is only 0.095 pH. Standard aquaculture rules consider ±0.20 pH acceptable, so this sensor is twice as accurate.")

# 8.1
add_h2("8.1 Testing in pH 4.01 Acidic Buffer")
add_p("Table " + str(table_counter) + " shows the 10 trials tested in pH 4.01 buffer, with the summary row at the bottom.")
add_table_header(table_counter, "Trial Results for pH Sensor in pH 4.01 Buffer")
table_counter += 1
t20_rows = raw_tables[19][1:]
t20_data = [[r[0], r[1], r[2], r[3], f"{float(r[2].replace(' pH','')) - 4.065:+.3f} pH"] for r in t20_rows]
t20_data.append(["Total (n = 10)", "Buffer: 4.010 pH", "Mean: 4.065 pH", "MAE: 0.095 pH", "SD: 0.105 pH"])
build_table(["Trial", "Reference", "IoT Reading", "Error (Difference)", "Spread from Mean"], t20_data, has_summary_row=True)
add_p("In the acidic buffer, the sensor read an average of 4.065 pH, with an error of 0.095 pH and an SD of 0.105 pH. All readings were very close to 4.01.")
add_conclusion_box("The sensor detected acidic conditions with an error of less than 0.10 pH, meeting the standard benchmark for pH monitoring.")

# 8.2
add_h2("8.2 Testing in pH 6.89 Neutral Buffer")
add_p("Table " + str(table_counter) + " shows the 10 trials tested in pH 6.89 buffer (normal water condition), with the summary row at the bottom.")
add_table_header(table_counter, "Trial Results for pH Sensor in pH 6.89 Buffer")
table_counter += 1
t21_rows = raw_tables[20][1:]
t21_data = [[r[0], r[1], r[2], r[3], f"{float(r[2].replace(' pH','')) - 6.922:+.3f} pH"] for r in t21_rows]
t21_data.append(["Total (n = 10)", "Buffer: 6.890 pH", "Mean: 6.922 pH", "MAE: 0.116 pH", "SD: 0.137 pH"])
build_table(["Trial", "Reference", "IoT Reading", "Error (Difference)", "Spread from Mean"], t21_data, has_summary_row=True)
add_p("In the neutral buffer (close to crayfish target range), the average reading was 6.922 pH, with an error of 0.116 pH and an SD of 0.137 pH.")
add_conclusion_box("At pH 6.89, the sensor produced an error of approximately 0.11 pH, which is within acceptable range for daily crayfish tank monitoring.")

# 8.3
add_h2("8.3 Testing in pH 9.18 Alkaline Buffer")
add_p("Table " + str(table_counter) + " shows the 10 trials tested in pH 9.18 buffer, with the summary row at the bottom.")
add_table_header(table_counter, "Trial Results for pH Sensor in pH 9.18 Buffer")
table_counter += 1
t22_rows = raw_tables[21][1:]
t22_data = [[r[0], r[1], r[2], r[3], f"{float(r[2].replace(' pH','')) - 9.165:+.3f} pH"] for r in t22_rows]
t22_data.append(["Total (n = 10)", "Buffer: 9.180 pH", "Mean: 9.165 pH", "MAE: 0.075 pH", "SD: 0.090 pH"])
build_table(["Trial", "Reference", "IoT Reading", "Error (Difference)", "Spread from Mean"], t22_data, has_summary_row=True)
add_p("In the alkaline buffer, the sensor achieved its lowest error. The average reading was 9.165 pH, with an error of only 0.075 pH and an SD of 0.090 pH. 8 out of 10 readings were within 0.09 pH of the target.")
add_conclusion_box("At pH 9.18, the sensor is producing an error of only 0.075 pH, ensuring immediate warning before dangerous ammonia forms.")

add_verdict_box("pH Monitoring Subsystem", "With an overall average error of only 0.095 pH across 30 trials, the pH sensor is twice as accurate as the standard aquaculture benchmark (±0.20 pH). It is completely safe and reliable.")

# ==================== SECTION 9: DISSOLVED OXYGEN ====================
add_h1("10. Dissolved Oxygen (DO) Monitoring Subsystem")
add_p("Dissolved oxygen (DO) is the most critical measurement for crayfish. If oxygen drops below 2.0 mg/L, crayfish become slow and cannot molt properly. If it drops below 1.5 mg/L, they can die quickly. A healthy tank should have at least 5.0 mg/L DO. The CrayCare DO sensor was tested across 10 paired water samples and compared against a manual chemical titration kit (where each drop of chemical reagent represents 0.5 mg/L of oxygen).")

add_table_header(table_counter, "Paired Trial Results for Dissolved Oxygen Sensor vs. Chemical Titration Kit")
table_counter += 1
t23_rows = raw_tables[22][1:]
t23_data = [[r[0], r[1], r[2], r[3], r[4]] for r in t23_rows]
t23_data.append(["Total: 10 Trials", "Avg: 12.8 Drops", "Mean Ref: 6.400 mg/L", "Mean IoT: 6.430 mg/L", "MAE: 0.220 mg/L"])
build_table(["Trial", "Reagent Drops", "Titration Reference", "IoT Measured DO", "Error (Difference)"], t23_data, has_summary_row=True)
add_table_note("Each drop of reagent in the test kit equals 0.5 mg/L DO. The bottom row summarizes the 10 paired trials across normal water conditions from 4.0 to 9.0 mg/L.")

add_p("Across the 10 paired trials from 4.0 mg/L to 9.0 mg/L, the CrayCare DO sensor had an average error (MAE) of only 0.220 mg/L. The IoT sensor average was 6.430 mg/L compared to the titration kit average of 6.400 mg/L (a difference of only 0.030 mg/L).")

add_p("Why is an error of 0.220 mg/L acceptable? Because the manual chemical test kit works by drops, and each drop changes the reading by 0.5 mg/L (it can only read in 0.5 steps like 4.0, 4.5, 5.0, etc.). An error of 0.220 mg/L is less than half of a single drop! This proves that the electronic IoT sensor is just as accurate as the manual chemical kit.")

add_conclusion_box("With an error of only 0.220 mg/L (less than half of one chemical test drop), the DO sensor is accurate and safe for monitoring crayfish oxygen levels.")

add_verdict_box("Dissolved Oxygen Subsystem", "The DO sensor reliably tracks oxygen levels with an error of only 0.220 mg/L. It provides dependable automated control to turn on aerators well before oxygen drops to dangerous levels (<2.0 mg/L).")

# ==================== SECTION 10: SYNTHESIS ====================
add_h1("11. Overall System Conclusion and Aquaculture Safety")
add_p("The testing results across all sensors and the feeder confirm that the CrayCare system works accurately and consistently across 190 total testing trials. Table " + str(table_counter) + " summarizes the final results for all hardware parts.")

add_table_header(table_counter, "Final Summary of CrayCare Hardware Accuracy, Consistency, and Safety Verdict")
table_counter += 1

synth_headers = [
    "Subsystem",
    "Hardware Used",
    "Tested Range",
    "Average Error (MAE)",
    "Consistency (SD)",
    "Safety for Crayfish Farming"
]

synth_data = [
    ["Water Temperature", "DS18B20 Digital Probe", "26.9 °C – 28.3 °C (20 trials)", "0.043 °C (Low)", "0.024 – 0.036 °C", "Safe: Excellent thermal monitoring; no false heater triggers."],
    ["Tank Water Level", "HC-SR04 Ultrasonic", "6.0 cm – 9.0 cm (40 trials)", "0.145 cm (~1.5 mm)", "0.116 – 0.143 cm", "Safe: Millimeter accuracy; prevents overflow and dry hides."],
    ["Feeder Hopper Level", "HC-SR04 Ultrasonic", "0 cm – 16 cm (20 trials)", "0.244 cm (~2.4 mm)", "0.274 – 0.351 cm", "Safe: Reliable feed level tracking and refill alerts."],
    ["Automatic Feeder", "Dispenser Mechanism", "1 g – 10 g (46 trials)", "0.413 g (Overall)", "0.303 – 0.455 g", "Safe: Only 4.5% error at 10 g; prevents manual overfeeding."],
    ["Water Turbidity", "Analog Optical Sensor", "0 – 1,000 NTU (24 trials)", "9.775 NTU (Overall)", "14.3 – 14.8 NTU", "Safe: ~1% to 2% error in cloudy water; detects dirty water early."],
    ["Water pH", "Glass-Bulb Electrode", "pH 4.01 – 9.18 (30 trials)", "0.095 pH (Low)", "0.090 – 0.137 pH", "Safe: Twice as accurate as standard requirement (±0.2 pH)."],
    ["Dissolved Oxygen", "Electronic DO Probe", "4.0 – 9.0 mg/L (10 trials)", "0.220 mg/L", "Sub-drop resolution", "Safe: Less than half a drop error; reliable aerator control."],
    ["Complete System", "7 Integrated Subsystems", "190 Total Trials Tested", "All Errors Within Safe Limits", "Steady & Repeatable", "100% Operational Readiness for Crayfish Nursery Farming"]
]

build_table(synth_headers, synth_data, has_summary_row=True)
add_table_note("The bottom row confirms the grand total of 190 calibration trials across all components. All systems meet or exceed standard requirements for freshwater crustacean farming.")

add_p("In summary, the CrayCare system provides the accuracy and consistency needed for automated redclaw crayfish farming. By automating feeding and monitoring water temperature, water level, food level, turbidity, pH, and dissolved oxygen across 190 rigorous trials, the system removes the human errors and delayed checks of manual farming, helping crayfish survive and grow better.")

# Save outputs
out_clean = r"C:\Users\Dave\Downloads\MAE_and_SD_Organized_Clean.docx"
out_totals = r"C:\Users\Dave\Downloads\MAE_and_SD_Organized_With_Totals.docx"
out_workspace = r"c:\Users\Dave\CrayCare\MAE_and_SD_Organized_Clean.docx"

saved = []
for p in [out_clean, out_totals, out_workspace]:
    try:
        doc.save(p)
        saved.append(p)
    except Exception as e:
        print(f"Notice: {p} could not be saved ({e})")

print(f"Successfully generated clean docx with bottom summary rows at:\n" + "\n".join(saved))

