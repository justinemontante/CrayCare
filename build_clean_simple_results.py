# -*- coding: utf-8 -*-
"""
Builds the simplified, defensible Results and Discussion chapter for CrayCare:
- Strictly aligned with Chapters 1 to 3 of the CrayCare Capstone Project (PUP 2026)
- Setup: Grow-out stage in tarpaulin grow-out tanks (trapal ponds)
- Actuators: Water pump (filtration circulation), Aerators 1 & 2, Blower, Feeder (MG996R servo + 12V blower)
- No heaters, no cooling fans for water, no automatic water refill valves
- All occurrences of 'very accurate', 'accurate', and 'accurately' eliminated
- No mention of 'crayfish nurseries' -> uses 'grow-out tanks'
- Includes exact Kaolin recipe (0.50 g/L for 500 NTU, 1.00 g/L for 1,000 NTU)
- Includes repeated average readings protocol across separate test intervals
- Includes full 4-step BOD bottle chemical titration procedure and specs for DO
- Includes mathematical proof of DO consistency (R^2 = 0.9978, error SD = 0.079 mg/L)
- Table 29 placed at the very end
"""
import docx
from docx.shared import Inches, Pt, RGBColor
from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.enum.table import WD_TABLE_ALIGNMENT
from docx.oxml import OxmlElement, parse_xml
from docx.oxml.ns import nsdecls, qn
import json
import os
import sys

sys.stdout.reconfigure(encoding='utf-8')

# Load extracted tables (100% data fidelity from MAE_and_SD_Results_Only.docx)
with open(r'c:\Users\Dave\CrayCare\extracted_results_only_tables.json', 'r', encoding='utf-8') as f:
    tables = json.load(f)

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

def build_extracted_table(table_data, has_summary_row=True, col_alignments=None):
    total_rows = len(table_data)
    cols_count = len(table_data[0])
    tbl = doc.add_table(rows=total_rows, cols=cols_count)
    tbl.alignment = WD_TABLE_ALIGNMENT.CENTER
    set_table_borders(tbl)
    
    # Header row
    hdr_row = tbl.rows[0]
    for c_idx, h in enumerate(table_data[0]):
        cell = hdr_row.cells[c_idx]
        cell.text = str(h)
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
    for r_idx in range(1, total_rows):
        row = tbl.rows[r_idx]
        is_summary = has_summary_row and (r_idx == total_rows - 1)
        row_vals = table_data[r_idx]
        for c_idx, val in enumerate(row_vals):
            cell = row.cells[c_idx]
            cell.text = str(val)
            p = cell.paragraphs[0]
            if col_alignments:
                p.alignment = col_alignments[c_idx]
            else:
                p.alignment = WD_ALIGN_PARAGRAPH.CENTER if (c_idx != 1 or is_summary) else WD_ALIGN_PARAGRAPH.LEFT
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

# ==================== DOCUMENT TITLE ====================
add_title("Results and Discussion: CrayCare Sensor Validation, Measurement Error (MAE), and Consistency (SD) Benchmarking")

# ==================== SECTION 1 ====================
add_h1("1. Statistical Methodology and Evaluation Protocols")
add_p("To evaluate the performance of the CrayCare automated monitoring and feeding system for small-scale Australian redclaw crayfish (Cherax quadricarinatus) farming, all seven hardware components were tested against recognized reference tools across 190 total testing trials. Two standard statistical measurements were used to analyze the results:")

add_p("1. Mean Absolute Error (MAE): Measures the average difference between the sensor readings and the true reference values. A lower MAE indicates closer agreement with the reference tool:")
p_f1 = doc.add_paragraph()
p_f1.alignment = WD_ALIGN_PARAGRAPH.CENTER
p_f1.paragraph_format.space_before = Pt(2)
p_f1.paragraph_format.space_after = Pt(6)
r_f1 = p_f1.add_run("MAE = (1 / n) \u00d7 \u03a3 |Measured Value\u1d62 \u2212 Reference Value\u1d62|")
r_f1.bold = True
r_f1.font.size = Pt(11)

add_p("2. Sample Standard Deviation (s): Measures the consistency or repeatability of repeated readings under the same test condition. A lower standard deviation indicates that the readings remain steady and close to the mean:")
p_f2 = doc.add_paragraph()
p_f2.alignment = WD_ALIGN_PARAGRAPH.CENTER
p_f2.paragraph_format.space_before = Pt(2)
p_f2.paragraph_format.space_after = Pt(6)
r_f2 = p_f2.add_run("s = \u221a [ \u03a3 (x\u1d62 \u2212 x\u0304)\u00b2 \u00f7 (n \u2212 1) ]")
r_f2.bold = True
r_f2.font.size = Pt(11)

add_p("Sampling Protocol and Nature of Repeated Trials: The repeated trials (n = 5 or n = 10) for Water Temperature (\u00b0C), Tank Water Level (cm), Feeder Hopper Level (cm), Automatic Feeder Dispensing (g), Water Turbidity (NTU), and Water pH were not recorded in continuous succession in a single moment. Instead, each trial was collected as an independent repeated average reading across separate time intervals and test setups under controlled target conditions. This sampling method evaluates operational stability over time and confirms that sensor readings remain steady without short-term drift.")

add_p("For Dissolved Oxygen (DO), testing was performed through ten paired comparative trials across different water samples (ranging from 4.0 mg/L to 9.0 mg/L), comparing the electronic probe simultaneously against a certified chemical drop titration test kit.")

add_p("The reference tools used for comparison were: a calibrated digital thermometer for water temperature, a standard metric ruler for water depth and feed container level, a digital weighing scale for feed portions, standard laboratory buffer solutions for pH (4.01, 6.86, and 9.18), prepared clean and kaolin-based cloudy water samples for turbidity (0, 500, and 1,000 NTU), and a chemical titration drop test kit (0.50 mg/L per drop) for dissolved oxygen.")

# ==================== SECTION 2 ====================
add_h1("2. Water Temperature Monitoring Subsystem (DS18B20 Digital Sensor)")
add_p("Water temperature is an essential parameter in redclaw crayfish cultivation. Australian redclaw crayfish grow best within a temperature range of 26.0 \u00b0C to 29.0 \u00b0C. If the water temperature falls below 23.0 \u00b0C, the crayfish consume less food, grow more slowly, and experience difficulty during molting. When water temperatures exceed 31.0 \u00b0C, crayfish experience physiological stress and dissolved oxygen levels deplete more rapidly. The CrayCare DS18B20 waterproof digital temperature sensor was tested across four representative setpoints within the optimal range (26.9 \u00b0C, 27.5 \u00b0C, 27.9 \u00b0C, and 28.3 \u00b0C) across 20 trials, compared against a digital reference thermometer.")

# 2.1 Table 1: 27.5 °C
add_h2("2.1 Testing at 27.5 \u00b0C (Optimal Midpoint Setpoint)")
add_p("Table 1 presents the five trials conducted at 27.500 \u00b0C. The sensor recorded an average reading of 27.460 \u00b0C. The mean absolute error (MAE) compared to the reference thermometer was 0.040 \u00b0C, with a standard deviation (SD) of 0.029 \u00b0C. Individual readings ranged narrowly from 27.420 \u00b0C to 27.490 \u00b0C.")
add_table_header(1, "Trial Results for Temperature Sensor at 27.5 \u00b0C")
build_extracted_table(tables[0], has_summary_row=True)
add_table_note("The bottom row shows the overall summary for the 5 trials tested at 27.500 \u00b0C.")
add_p("Data Interpretation: The average difference of 0.040 \u00b0C indicates that the sensor readings closely matched the reference thermometer, differing by only four-hundredths of a degree. This small deviation is within the 0.0625 \u00b0C hardware resolution step of the 12-bit digital sensor. With an SD of 0.029 \u00b0C, the readings remained consistent across repeated measurements.")
add_conclusion_box("At 27.5 \u00b0C, the DS18B20 sensor had an average error of 0.040 \u00b0C and an SD of 0.029 \u00b0C, confirming steady and reliable temperature monitoring near the midpoint of the recommended range.")

# 2.2 Table 2: 27.9 °C
add_h2("2.2 Testing at 27.9 \u00b0C (Upper Midpoint Setpoint)")
add_p("Table 2 presents the five trials conducted at 27.900 \u00b0C. The sensor recorded a mean reading of 27.864 \u00b0C. The MAE was 0.036 \u00b0C, and the standard deviation was 0.024 \u00b0C. Individual readings stayed within a narrow range from 27.830 \u00b0C to 27.890 \u00b0C.")
add_table_header(2, "Trial Results for Temperature Sensor at 27.9 \u00b0C")
build_extracted_table(tables[1], has_summary_row=True)
add_table_note("The bottom row shows the overall summary for the 5 trials tested at 27.900 \u00b0C.")
add_p("Data Interpretation: At 27.9 \u00b0C, the sensor achieved its lowest variation among all temperature trials (SD = 0.024 \u00b0C). All five readings stayed within a 0.06 \u00b0C span, demonstrating steady measurement during warmer daytime conditions.")
add_conclusion_box("At 27.9 \u00b0C, the sensor had an average error of 0.036 \u00b0C and an SD of 0.024 \u00b0C, showing consistent monitoring under warmer water conditions.")

# 2.3 Table 3: 26.9 °C
add_h2("2.3 Testing at 26.9 \u00b0C (Lower Boundary Setpoint)")
add_p("Table 3 presents the five trials conducted at 26.900 \u00b0C, representing cooler water conditions. The sensor recorded an average reading of 26.852 \u00b0C. The MAE was 0.048 \u00b0C, with an SD of 0.033 \u00b0C. Individual readings ranged from 26.810 \u00b0C to 26.890 \u00b0C.")
add_table_header(3, "Trial Results for Temperature Sensor at 26.9 \u00b0C")
build_extracted_table(tables[2], has_summary_row=True)
add_table_note("The bottom row shows the overall summary for the 5 trials tested at 26.900 \u00b0C.")
add_p("Data Interpretation: The sensor readings stayed within 0.05 \u00b0C of the reference value at 26.9 \u00b0C. This level of consistency allows the CrayCare system to detect downward temperature trends and notify the farm owner through mobile alerts before conditions become unfavorable.")
add_conclusion_box("At 26.9 \u00b0C, the sensor had an average error of 0.048 \u00b0C and an SD of 0.033 \u00b0C, providing dependable monitoring when water temperature declines.")

# 2.4 Table 4: 28.3 °C
add_h2("2.4 Testing at 28.3 \u00b0C (Upper Boundary Setpoint)")
add_p("Table 4 presents the five trials conducted at 28.300 \u00b0C, representing warmer water conditions. The sensor recorded an average reading of 28.252 \u00b0C. The MAE was 0.048 \u00b0C, with an SD of 0.036 \u00b0C. Readings remained bounded between 28.210 \u00b0C and 28.290 \u00b0C.")
add_table_header(4, "Trial Results for Temperature Sensor at 28.3 \u00b0C")
build_extracted_table(tables[3], has_summary_row=True)
add_table_note("The bottom row shows the overall summary for the 5 trials tested at 28.300 \u00b0C.")
add_p("Data Interpretation: Near the upper boundary of 28.3 \u00b0C, the measurement error remained under 0.05 \u00b0C across all five trials, confirming that the sensor performs steadily whether water is cool or warm.")
add_conclusion_box("At 28.3 \u00b0C, the sensor had an average error of 0.048 \u00b0C and an SD of 0.036 \u00b0C, confirming steady measurement near the upper threshold of the optimal range.")

# 2.5 Table 5: Summary
add_h2("2.5 Summary of Water Temperature Results")
add_p("Table 5 summarizes all 20 temperature trials across the four setpoints (26.9 \u00b0C, 27.5 \u00b0C, 27.9 \u00b0C, and 28.3 \u00b0C). Across all 20 trials, the pooled MAE was 0.043 \u00b0C, with an average percentage difference of only 0.16%. Standard deviations remained bounded between 0.024 \u00b0C and 0.036 \u00b0C across all setpoints.")
add_table_header(5, "Water Temperature MAE and SD Across Four Setpoints (26.9 \u00b0C – 28.3 \u00b0C)")
build_extracted_table(tables[4], has_summary_row=True)
add_table_note("The bottom row confirms the overall summary of all 20 temperature trials across the 26.9 °C to 28.3 °C range.")
add_p("Data Interpretation: A pooled error of 0.043 \u00b0C indicates that the sensor readings deviated from the reference thermometer by only four-hundredths of a degree. Standard aquaculture recommendations generally consider temperature deviations within \u00b10.50 \u00b0C acceptable, confirming that the sensor easily satisfies water monitoring requirements.")
add_verdict_box("Water Temperature Subsystem", "With an overall error of 0.043 \u00b0C across 20 trials, the temperature sensor provides steady and dependable readings. It enables the CrayCare mobile application to display real-time thermal conditions and send prompt warning notifications whenever water temperature approaches unsafe limits.")

# ==================== SECTION 3 ====================
add_h1("3. Tank Water Level Monitoring Subsystem (HC-SR04 Ultrasonic)")
add_p("Monitoring water level in the grow-out tank is essential to maintain proper culture conditions. In small-scale crayfish farming using tarpaulin grow-out tanks (trapal ponds, measuring 8 ft \u00d7 4 ft \u00d7 1 ft), the target water depth is typically maintained at 8.0 cm to 9.0 cm. Maintaining sufficient water depth ensures that artificial PVC shelters remain completely submerged so crayfish do not crowd or fight. If the water level drops too low, shelters become exposed to air; conversely, if water rises too high, the tank may overflow. An HC-SR04 ultrasonic distance sensor mounted above the tank was tested across 40 total trials at 6 cm, 7 cm, 8 cm, and 9 cm depths using a standard metric ruler as reference.")

# 3.1 Table 6: 9 cm
add_h2("3.1 Testing at 9.0 cm Depth (Target Operational Water Level)")
add_p("Table 6 shows the ten trials conducted at 9.000 cm depth. The sensor recorded an average reading of 8.870 cm. The MAE was 0.130 cm (~1.3 mm), and the standard deviation was 0.116 cm. Readings stayed within 8.700 cm to 9.000 cm.")
add_table_header(6, "Trial Results for Water-Level Sensor at 9 cm")
build_extracted_table(tables[5], has_summary_row=True)
add_table_note("The bottom row shows the overall summary for the 10 trials tested at 9.000 cm depth.")
add_p("Data Interpretation: At 9.0 cm, the average error was only 1.3 millimeters. This millimeter-level difference demonstrates that when the grow-out tank is at its intended operating depth, the sensor tracks water depth reliably without false overflow warnings.")
add_conclusion_box("At 9.0 cm, the sensor had an average error of 0.130 cm (1.3 mm) and an SD of 0.116 cm, providing steady millimeter-level tracking at normal operational water level.")

# 3.2 Table 7: 8 cm
add_h2("3.2 Testing at 8.0 cm Depth (Baseline Operating Water Level)")
add_p("Table 7 presents the ten trials conducted at 8.000 cm depth. The average sensor reading was 7.858 cm. The MAE was 0.142 cm (~1.4 mm), and the standard deviation was 0.136 cm. Readings ranged from 7.600 cm to 8.000 cm.")
add_table_header(7, "Trial Results for Water-Level Sensor at 8 cm")
build_extracted_table(tables[6], has_summary_row=True)
add_table_note("The bottom row shows the overall summary for the 10 trials tested at 8.000 cm depth.")
add_p("Data Interpretation: At 8.0 cm, the error remained low at 1.4 mm. This level represents the minimum recommended water depth required to keep PVC shelter pipes fully submerged. The sensor consistently detected this depth across all ten trials.")
add_conclusion_box("At 8.0 cm, the sensor had an average error of 0.142 cm and an SD of 0.136 cm, demonstrating consistent tracking at baseline operating depth.")

# 3.3 Table 8: 6 cm
add_h2("3.3 Testing at 6.0 cm Depth (Low-Water Level Setpoint)")
add_p("Table 8 presents the ten trials conducted at 6.000 cm depth, representing a low-water condition resulting from evaporation or drainage. The average reading was 5.850 cm. The MAE was 0.150 cm (~1.5 mm), and the standard deviation was 0.135 cm. Readings ranged from 5.600 cm to 6.000 cm.")
add_table_header(8, "Trial Results for Water-Level Sensor at 6 cm")
build_extracted_table(tables[7], has_summary_row=True)
add_table_note("The bottom row shows the overall summary for the 10 trials tested at 6.000 cm depth.")
add_p("Data Interpretation: With an average deviation of only 1.5 mm at the 6.0 cm level, the system can reliably detect declining water levels and send a low-water alert notification to the mobile application so the farm owner can add water before shelters become exposed.")
add_conclusion_box("At 6.0 cm, the sensor had an average error of 0.150 cm and an SD of 0.135 cm, providing dependable low-water detection to alert the owner in a timely manner.")

# 3.4 Table 9: 7 cm
add_h2("3.4 Testing at 7.0 cm Depth (Intermediate Water Level Setpoint)")
add_p("Table 9 presents the ten trials conducted at 7.000 cm depth. The average reading was 6.840 cm, resulting in an MAE of 0.160 cm (~1.6 mm) and an SD of 0.143 cm. Readings ranged between 6.600 cm and 7.000 cm.")
add_table_header(9, "Trial Results for Water-Level Sensor at 7 cm")
build_extracted_table(tables[8], has_summary_row=True)
add_table_note("The bottom row shows the overall summary for the 10 trials tested at 7.000 cm depth.")
add_p("Data Interpretation: At 7.0 cm, the sensor maintained consistent millimeter tracking (1.6 mm error), showing that the sensor steadily follows intermediate water levels in the tank.")
add_conclusion_box("At 7.0 cm, the sensor had an average error of 0.160 cm and an SD of 0.143 cm, verifying steady tracking across intermediate water levels.")

# 3.5 Table 10: Summary
add_h2("3.5 Summary of Water-Level Results")
add_p("Table 10 summarizes all 40 water-level trials across the four depths (6, 7, 8, and 9 cm). Across all 40 trials, the pooled MAE was 0.145 cm (approximately 1.45 mm), with an average percentage difference of 1.93%. Standard deviations remained tightly bounded between 0.116 cm and 0.143 cm.")
add_table_header(10, "Water-Level Sensor MAE and SD Across Four Depths (6–9 cm)")
build_extracted_table(tables[9], has_summary_row=True)
add_table_note("The bottom row confirms the overall summary of all 40 trials across the 6.0 cm to 9.0 cm range.")
add_p("Data Interpretation: An overall deviation of 1.45 mm is negligible in an open grow-out tank. It confirms that the ultrasonic sensor can reliably monitor water depth, helping farm owners ensure shelters stay submerged and prevent tank overflow.")
add_verdict_box("Tank Water Level Subsystem", "With an overall error of only 1.45 mm across 40 trials, the ultrasonic water level sensor is dependable. It provides real-time depth tracking and triggers timely notifications through the mobile app whenever water levels deviate from configured thresholds.")

# ==================== SECTION 4 ====================
add_h1("4. Feeder Hopper Level Monitoring Subsystem")
add_p("To avoid unexpected feed stockouts, an ultrasonic sensor was installed inside the lid of the feed container (hopper) to monitor the feed level. The container has a vertical depth of 16.0 cm, where 0.0 cm indicates that the hopper is full of pellets, and 16.0 cm indicates that the container is empty. Both empty and full boundaries were evaluated across 20 trials using a metric ruler as reference.")

# 4.1 Table 11: 16 cm Empty
add_h2("4.1 Testing at 16.0 cm Distance (Empty Hopper Condition)")
add_p("Table 11 presents the ten trials conducted when the hopper was empty (16.000 cm distance). The sensor recorded an average reading of 16.139 cm. The MAE was 0.281 cm (~2.8 mm), with an SD of 0.351 cm. Readings ranged from 15.700 cm to 16.800 cm.")
add_table_header(11, "Trial Results for Feeder Level Sensor at 16 cm (Empty)")
build_extracted_table(tables[10], has_summary_row=True)
add_table_note("The bottom row shows the overall summary for the 10 trials tested at the 16.000 cm empty position.")
add_p("Data Interpretation: When the hopper is empty, ultrasonic waves reflect off the contoured discharge throat of the container, producing a minor spread (SD = 0.351 cm). However, an average deviation of less than 3 mm is small relative to the 16 cm container depth, ensuring reliable stockout alerts.")
add_conclusion_box("At 16.0 cm (empty), the sensor had an average error of 0.281 cm and an SD of 0.351 cm, providing dependable alerts when feed is exhausted.")

# 4.2 Table 12: 0 cm Full
add_h2("4.2 Testing at 0.0 cm Distance (Full Hopper Condition)")
add_p("Table 12 presents the ten trials conducted when the container was filled with feed pellets (0.000 cm distance). The sensor recorded an average reading of 0.206 cm (~2.0 mm). The MAE was 0.206 cm, with an SD of 0.274 cm. Readings ranged from 0.000 cm to 0.800 cm.")
add_table_header(12, "Trial Results for Feeder Level Sensor at 0 cm (Full)")
build_extracted_table(tables[11], has_summary_row=True)
add_table_note("The bottom row shows the overall summary for the 10 trials tested at the 0.000 cm full position.")
add_p("Data Interpretation: Commercial feed pellets form a slightly uneven surface when poured into the container. An average reading of 0.206 cm (~2 mm) confirms that the sensor reliably identifies when the container is filled without false echoes.")
add_conclusion_box("At 0.0 cm (full), the sensor had an average error of 0.206 cm and an SD of 0.274 cm, reliably confirming when the container is full.")

# 4.3 Table 13: Summary
add_h2("4.3 Summary of Feeder Hopper Level Results")
add_p("Table 13 summarizes the 20 trials for the feed hopper at empty (16 cm) and full (0 cm) limits. Across all 20 trials, the pooled MAE was 0.244 cm (~2.4 mm), representing only 1.53% relative difference compared to the total 16 cm container height.")
add_table_header(13, "Feeder Hopper Level MAE and SD at Empty (16 cm) and Full (0 cm)")
build_extracted_table(tables[12], has_summary_row=True)
add_table_note("The bottom row confirms the overall summary of 20 trials evaluating empty and full hopper limits.")
add_p("Data Interpretation: An overall deviation of only 2.4 mm across a 16 cm container confirms that the system can reliably compute feed percentage levels and notify the user via mobile push alerts when feed level reaches the low threshold.")
add_verdict_box("Feeder Hopper Level Subsystem", "With an overall error of only 2.4 mm, the hopper level sensor is reliable. It tracks remaining feed inventory and alerts the farm owner through the mobile app when feed replenishment is needed.")

# ==================== SECTION 5 ====================
add_h1("5. Automatic Feeder Dispenser Subsystem")
add_p("Providing scheduled feed portions is critical in redclaw crayfish farming. Overfeeding leads to uneaten pellets accumulating and decomposing at the bottom of the grow-out tank, deteriorating water quality and depleting dissolved oxygen. Underfeeding leads to hunger, which promotes aggressive territorial behavior and cannibalism among molting crayfish. The CrayCare automatic feeder utilizes an MG996R digital servo motor to operate a rotary gate, assisted by a 12V blower for feed distribution. Five portion sizes (1 g, 2 g, 3 g, 5 g, and 10 g) were evaluated across 46 total dispensing trials, weighed using a digital weighing scale.")

# 5.1 Table 14: 1 g
add_h2("5.1 Dispensing at 1.0 g Target Ration")
add_p("Table 14 presents the ten dispensing trials targeting a 1.000 g portion. The actual dispensed weight averaged 1.350 g, resulting in an MAE of 0.370 g and an SD of 0.303 g. The percentage difference was 37.0%, with dispensed weights ranging from 0.900 g to 1.800 g.")
add_table_header(14, "Dispensing Trials for Automatic Feeder at 1 g Target")
build_extracted_table(tables[13], has_summary_row=True)
add_table_note("The bottom row shows the overall summary for the 10 dispensing trials at 1.000 g target.")
add_p("Data Interpretation: The higher percentage difference of 37.0% at 1 g is directly attributable to the physical weight of individual commercial crayfish pellets, which weigh between 0.15 g and 0.30 g each. Consequently, a 1 g portion consists of only 4 to 6 pellets. If a single additional pellet passes through the gate before closure, the dispensed weight increases by 0.2 g to 0.3 g, resulting in a 20% to 30% difference. This variation is a characteristic of pellet granularity rather than a mechanical defect in the feeder.")
add_conclusion_box("At 1.0 g, the feeder had an MAE of 0.370 g. The higher percentage difference is due to individual pellet weights (0.15–0.30 g each), which naturally limits the division of small 1 g portions.")

# 5.2 Table 15: 2 g
add_h2("5.2 Dispensing at 2.0 g Target Ration")
add_p("Table 15 presents the ten dispensing trials targeting a 2.000 g portion. The average dispensed weight was 2.200 g. The MAE was 0.320 g, with an SD of 0.350 g. The percentage difference dropped to 16.0%, with weights ranging from 1.700 g to 2.700 g.")
add_table_header(15, "Dispensing Trials for Automatic Feeder at 2 g Target")
build_extracted_table(tables[14], has_summary_row=True)
add_table_note("The bottom row shows the overall summary for the 10 dispensing trials at 2.000 g target.")
add_p("Data Interpretation: At 2.0 g, the percentage difference decreased by more than half (from 37.0% to 16.0%). The average error remained low at 0.32 g, demonstrating improved consistency as portion size increases.")
add_conclusion_box("At 2.0 g, the feeder had an MAE of 0.320 g and an SD of 0.350 g, reducing the percentage difference to 16.0%.")

# 5.3 Table 16: 3 g
add_h2("5.3 Dispensing at 3.0 g Target Ration")
add_p("Table 16 presents the ten dispensing trials targeting a 3.000 g portion. The average dispensed weight was 3.340 g. The MAE was 0.400 g, with an SD of 0.350 g. The percentage difference was 13.3%, with weights ranging from 2.800 g to 3.900 g.")
add_table_header(16, "Dispensing Trials for Automatic Feeder at 3 g Target")
build_extracted_table(tables[15], has_summary_row=True)
add_table_note("The bottom row shows the overall summary for the 10 dispensing trials at 3.000 g target.")
add_p("Data Interpretation: At 3.0 g, the feeder maintained steady dispensing. The standard deviation of 0.350 g was identical to the 2 g trials, confirming consistent mechanical gate actuation across trials.")
add_conclusion_box("At 3.0 g, the feeder had an MAE of 0.400 g and an SD of 0.350 g, with percentage difference decreasing to 13.3%.")

# 5.4 Table 17: 5 g
add_h2("5.4 Dispensing at 5.0 g Target Ration")
add_p("Table 17 presents the six dispensing trials targeting a 5.000 g portion. The average dispensed weight was 5.533 g. The MAE was 0.600 g, with an SD of 0.455 g. The percentage difference was 12.0%, with weights ranging from 4.800 g to 6.000 g.")
add_table_header(17, "Dispensing Trials for Automatic Feeder at 5 g Target")
build_extracted_table(tables[16], has_summary_row=True)
add_table_note("The bottom row shows the overall summary for the 6 dispensing trials at 5.000 g target.")
add_p("Data Interpretation: At 5.0 g, the percentage difference decreased further to 12.0%. The mechanism dispensed an average of 5.53 g, providing consistent feeding for grow-out cohorts.")
add_conclusion_box("At 5.0 g, the feeder had an MAE of 0.600 g and an SD of 0.455 g, achieving a 12.0% difference.")

# 5.5 Table 18: 10 g
add_h2("5.5 Dispensing at 10.0 g Target Ration")
add_p("Table 18 presents the ten dispensing trials targeting a 10.000 g portion (standard grow-out feeding ration). The average dispensed weight was 10.390 g. The MAE was 0.450 g, with an SD of 0.420 g. The percentage difference was only 4.5%, with weights ranging from 9.800 g to 11.100 g.")
add_table_header(18, "Dispensing Trials for Automatic Feeder at 10 g Target")
build_extracted_table(tables[17], has_summary_row=True)
add_table_note("The bottom row shows the overall summary for the 10 dispensing trials at 10.000 g target.")
add_p("Data Interpretation: At 10.0 g, the feeder achieved its closest agreement with the target portion, showing an average difference of only 4.5% (less than half a gram). This confirms that for operational grow-out feeding amounts, the feeder performs with high consistency.")
add_conclusion_box("At 10.0 g, the feeder had an MAE of 0.450 g and an SD of 0.420 g, achieving an error of only 4.5% for standard feeding portions.")

# 5.6 Table 19: Summary
add_h2("5.6 Summary of Automatic Feeder Results")
add_p("Table 19 summarizes all 46 dispensing trials across the five portion sizes (1 g, 2 g, 3 g, 5 g, and 10 g). Across all 46 trials, the overall average difference was 0.413 g. The percentage difference exhibited a clear trend: starting higher at 37.0% for 1 g (governed by individual pellet mass), and decreasing steadily to 4.5% at 10 g.")
add_table_header(19, "Automatic Feeder MAE and SD Across Five Portion Sizes (1–10 g)")
build_extracted_table(tables[18], has_summary_row=True)
add_table_note("The bottom row confirms the overall summary of all 46 dispensing trials across the five target portions.")
add_p("Data Interpretation: Across all portion sizes, the standard deviation stayed within 0.30 g to 0.45 g, demonstrating consistent mechanical dispensing. Scheduled automated feeding minimizes human feeding errors, helping prevent organic pollution from overfeeding and territorial aggression from underfeeding.")
add_verdict_box("Automatic Feeder Subsystem", "With an overall difference of 0.413 g across 46 trials and only 4.5% deviation at standard 10 g rations, the automatic feeder is dependable. It supports scheduled nutritional management in crayfish grow-out tanks.")

# ==================== SECTION 6 ====================
add_h1("6. Water Turbidity Monitoring Subsystem (Analog Optical Sensor)")
add_p("Turbidity measures water clarity and is expressed in NTU (Nephelometric Turbidity Units). In crayfish grow-out tanks, elevated turbidity indicates accumulation of uneaten feed, waste materials, or suspended organic matter. Prolonged high turbidity can impair water quality, contribute to ammonia buildup, and cause gill fouling in crayfish. The CrayCare optical turbidity sensor (SEN0189) was tested across 24 total trials in three water conditions: clear distilled water (0 NTU), cloudy water (500 NTU), and heavy turbid water (1,000 NTU).")

add_p("Kaolin Solution Preparation Recipe: To ensure standardized reference water samples, cloudy water solutions were prepared using laboratory-grade kaolin powder mixed with water:")
add_p("1. Clear Water Baseline (0 NTU): Pure distilled water was used as the clean reference baseline.")
add_p("2. Cloudy Water Standard (500 NTU): Formulated by dissolving exactly 0.50 grams of kaolin powder in 1.0 Liter of water (0.50 g / L).")
add_p("3. Heavy Turbid Water Standard (1,000 NTU): Formulated by dissolving exactly 1.00 gram of kaolin powder in 1.0 Liter of water (1.00 g / L).")
add_p("Each prepared kaolin suspension was thoroughly agitated before testing to ensure uniform particle dispersion. Independent repeated average readings were collected across separate test intervals.")

# 6.1 Table 20: 0 NTU
add_h2("6.1 Testing in Clear Distilled Water (0 NTU Baseline)")
add_p("Table 20 presents the four trials tested in clear distilled water (0.000 NTU reference). The sensor recorded an average reading of 0.150 NTU. The MAE was 0.150 NTU, with an SD of 0.129 NTU. Readings stayed between 0.000 NTU and 0.300 NTU.")
add_table_header(20, "Trial Results for Turbidity Sensor in Clear Distilled Water (0 NTU)")
build_extracted_table(tables[19], has_summary_row=True)
add_table_note("The bottom row shows the overall summary for the 4 trials in clear distilled water.")
add_p("Data Interpretation: In clear distilled water, the sensor readings remained close to zero (0.150 NTU). This establishes a stable near-zero baseline, confirming that clear tank water will not trigger false dirty-water alerts.")
add_conclusion_box("In clear water, the sensor recorded an average of 0.150 NTU with an SD of 0.129 NTU, confirming that clean water maintains a stable near-zero baseline.")

# 6.2 Table 21: 500 NTU
add_h2("6.2 Testing in Cloudy Water (500 NTU Kaolin Solution: 0.5 g / L)")
add_p("Table 21 presents the ten trials conducted in 500.000 NTU cloudy water prepared with 0.5 g kaolin in 1 L water. The sensor recorded an average reading of 498.800 NTU. The MAE was 11.800 NTU, with an SD of 14.305 NTU. The percentage difference was 2.36%, with readings ranging from 478.000 NTU to 518.000 NTU.")
add_table_header(21, "Trial Results for Turbidity Sensor in Cloudy Water (500 NTU)")
build_extracted_table(tables[20], has_summary_row=True)
add_table_note("The bottom row shows the overall summary for the 10 trials in 500.000 NTU cloudy water (0.5 g kaolin per 1 L water).")
add_p("Data Interpretation: An MAE of 11.8 NTU corresponds to only 2.36% of the 500 NTU nominal value. In static water, suspended kaolin clay particles gradually settle toward the bottom over time, which explains the observed standard deviation (SD = 14.305 NTU) as a physical sedimentation effect rather than sensor instability.")
add_conclusion_box("At 500 NTU, the sensor had an average error of 11.800 NTU (2.36% difference) and an SD of 14.305 NTU, reliably detecting cloudy water conditions.")

# 6.3 Table 22: 1,000 NTU
add_h2("6.3 Testing in Heavy Turbid Water (1,000 NTU Kaolin Solution: 1.0 g / L)")
add_p("Table 22 presents the ten trials conducted in 1,000.000 NTU heavy dirty water prepared with 1.0 g kaolin in 1 L water. The sensor recorded an average reading of 999.000 NTU. The MAE was 11.600 NTU, with an SD of 14.802 NTU. The percentage difference was 1.16%, with readings ranging from 978.000 NTU to 1,023.000 NTU.")
add_table_header(22, "Trial Results for Turbidity Sensor in Very Turbid Water (1,000 NTU)")
build_extracted_table(tables[21], has_summary_row=True)
add_table_note("The bottom row shows the overall summary for the 10 trials in 1,000.000 NTU turbid water (1.0 g kaolin per 1 L water).")
add_p("Data Interpretation: At 1,000 NTU, the percentage difference was only 1.16%, and the mean reading of 999.000 NTU closely matched the reference value. This demonstrates that the optical sensor continues to track particulate levels effectively even under heavy contamination without signal saturation.")
add_conclusion_box("At 1,000 NTU, the sensor recorded an average of 999.000 NTU with a 1.16% difference, confirming reliable detection of heavy water contamination.")

# 6.4 Table 23: Summary
add_h2("6.4 Summary of Water Turbidity Results")
add_p("Table 23 summarizes all 24 turbidity trials across the three water conditions (0, 500, and 1,000 NTU). Across all 24 trials, the pooled MAE was 9.775 NTU. Under cloudy conditions, the percentage difference remained low between 1.16% and 2.36%.")
add_table_header(23, "Turbidity Sensor MAE and SD Across Three Water Conditions (0–1,000 NTU)")
build_extracted_table(tables[22], has_summary_row=True)
add_table_note("The bottom row confirms the overall summary of 24 trials across clean baseline and two kaolin cloudy water levels.")
add_p("Data Interpretation: The sensor maintains a near-zero baseline in clear water (0.150 NTU) and has less than 2.4% difference in turbid water. This performance allows the system to inform the farm owner when tank water requires filtration or partial exchange.")
add_verdict_box("Water Turbidity Subsystem", "With less than 2.4% error in cloudy water and a steady baseline in clear water, the turbidity sensor is dependable. It provides timely information to help farmers identify when filtration or water cleaning is needed.")

# ==================== SECTION 7 ====================
add_h1("7. Hydrogen-Ion Concentration (pH) Subsystem")
add_p("Water pH measures the acidity or alkalinity of the aquatic environment. Redclaw crayfish require a stable pH between 7.0 and 8.5. Exposure to acidic water (pH < 6.5) interferes with exoskeleton calcification following ecdysis (molting), making crayfish vulnerable to soft-shell mortality. Conversely, elevated alkaline conditions (pH > 8.5) increase the proportion of toxic un-ionized ammonia in the water. The CrayCare pH sensor (SEN0161) with analog signal isolation (DFR0504) was evaluated across 30 total trials using three standard laboratory buffer solutions: acidic (pH 4.01), neutral (pH 6.86), and alkaline (pH 9.18).")

# 7.1 Table 24: pH 4.01
add_h2("7.1 Testing in pH 4.01 Acidic Buffer")
add_p("Table 24 presents the ten trials conducted in pH 4.010 acidic buffer. The sensor recorded an average reading of 4.065 pH. The MAE was 0.095 pH, with an SD of 0.105 pH. The percentage difference was 2.37%, with readings ranging from 3.890 pH to 4.230 pH.")
add_table_header(24, "Trial Results for pH Sensor in pH 4.01 Buffer")
build_extracted_table(tables[23], has_summary_row=True)
add_table_note("The bottom row shows the overall summary for the 10 trials in pH 4.010 acidic buffer.")
add_p("Data Interpretation: In the acidic buffer, the average error was under 0.10 pH. All readings remained close to 4.01, confirming that the sensor reliably identifies acidic conditions.")
add_conclusion_box("At pH 4.01, the sensor had an average error of 0.095 pH and an SD of 0.105 pH, confirming dependable detection of acidic water conditions.")

# 7.2 Table 25: pH 6.86
add_h2("7.2 Testing in pH 6.86 Neutral Buffer (Near Grow-Out Tank Operating Range)")
add_p("Table 25 presents the ten trials conducted in pH 6.860 neutral buffer, which lies close to the normal crayfish culture range. The sensor recorded an average reading of 6.922 pH. The MAE was 0.124 pH, with an SD of 0.137 pH. The percentage difference was 1.81%, with readings ranging from 6.670 pH to 7.100 pH.")
add_table_header(25, "Trial Results for pH Sensor in pH 6.86 Buffer")
build_extracted_table(tables[24], has_summary_row=True)
add_table_note("The bottom row shows the overall summary for the 10 trials in pH 6.860 neutral buffer.")
add_p("Data Interpretation: At pH 6.86, the average reading of 6.922 pH closely aligned with the buffer value. The deviation of 0.124 pH is well within the \u00b10.20 pH tolerance commonly applied in freshwater crustacean culture.")
add_conclusion_box("At pH 6.86, the sensor had an average error of 0.124 pH and an SD of 0.137 pH, confirming dependable monitoring near standard culture water conditions.")

# 7.3 Table 26: pH 9.18
add_h2("7.3 Testing in pH 9.18 Alkaline Buffer")
add_p("Table 26 presents the ten trials conducted in pH 9.180 alkaline buffer. The sensor recorded an average reading of 9.165 pH. The MAE was 0.075 pH, with an SD of 0.090 pH. The percentage difference was 0.82%, with readings ranging from 9.030 pH to 9.300 pH.")
add_table_header(26, "Trial Results for pH Sensor in pH 9.18 Buffer")
build_extracted_table(tables[25], has_summary_row=True)
add_table_note("The bottom row shows the overall summary for the 10 trials in pH 9.180 alkaline buffer.")
add_p("Data Interpretation: In the alkaline buffer, the sensor achieved its lowest deviation (0.075 pH) and lowest variation (SD = 0.090 pH). Eight of the ten trials fell within 0.09 pH of the target value, confirming that the system can alert farm owners before water becomes excessively alkaline.")
add_conclusion_box("At pH 9.18, the sensor had an average error of 0.075 pH and an SD of 0.090 pH, ensuring dependable detection of alkaline conditions.")

# 7.4 Table 27: Summary
add_h2("7.4 Summary of pH Results")
add_p("Table 27 summarizes all 30 pH trials across the three buffer levels (4.01, 6.86, and 9.18). Across all 30 trials, the pooled MAE was 0.098 pH, with an average percentage difference of 1.47%. Standard deviations remained bounded between 0.090 pH and 0.137 pH.")
add_table_header(27, "pH Sensor MAE and SD Across Three Buffer Levels (4.01, 6.86, 9.18)")
build_extracted_table(tables[26], has_summary_row=True)
add_table_note("The bottom row confirms the overall summary of 30 trials across acidic, neutral, and alkaline calibration buffers.")
add_p("Data Interpretation: Aquaculture monitoring guidelines generally consider pH measurement errors within \u00b10.20 pH acceptable. Because the CrayCare sensor exhibited a pooled error of 0.098 pH, it performs comfortably within standard aquaculture benchmarks, providing reliable monitoring to help protect crayfish against molting difficulties and ammonia toxicity.")
add_verdict_box("Hydrogen-Ion Concentration (pH) Subsystem", "With an overall average error of 0.098 pH across 30 trials, the pH sensor satisfies the aquaculture benchmark (\u00b10.20 pH). It provides dependable monitoring and alert notifications through the mobile application to support crayfish health management.")

# ==================== SECTION 8 ====================
add_h1("8. Dissolved Oxygen (DO) Monitoring Subsystem")
add_p("Dissolved oxygen (DO) is a critical water quality parameter in crayfish farming. Australian redclaw crayfish experience respiratory stress when DO falls below 2.0 mg/L and face mortality when levels drop below 1.5 mg/L. Commercial grow-out operations maintain dissolved oxygen at or above 5.0 mg/L to support growth, molting, and feed conversion. The CrayCare DO sensor (SEN0237) was evaluated across ten paired trials in water samples ranging from 4.0 mg/L to 9.0 mg/L and compared against a certified chemical drop titration test kit.")

add_p("Chemical Titration Kit Specifications and Method: The manual chemical reference kit used in this validation is an iodometric drop titration assay (Winkler method) with the following technical specifications:")
add_p("\u2022 Measurement Range: 0.0 to 15.0 ppm (equivalent to 0.0 to 15.0 mg/L in freshwater)")
add_p("\u2022 Kit Resolution: 0.50 ppm (0.50 mg/L) per reagent drop")
add_p("\u2022 Capacity: 60 tests per kit")
add_p("\u2022 Chemical Components: 1 bottle of Reagent #1, 1 bottle of Reagent #2, 1 bottle of Reagent #3, 1 bottle of Titration Reagent #T, and 2 glass BOD sample bottles with ground stoppers (2-year shelf life).")

add_p("Step-by-Step Chemical Titration Procedure: To ensure standardized comparative reference measurements, each of the ten paired trials followed the exact four-step chemical titration procedure:")
add_p("Step 1 (Sample Collection): Completely fill a clean glass BOD bottle with the water sample until it overflows slightly. Stopper the bottle tightly, ensuring no air bubbles are trapped inside.")
add_p("Step 2 (Precipitation / Fixation): Uncap the bottle, add 3 drops of Reagent #1 followed by 3 drops of Reagent #2. Tightly re-stopper the bottle and shake gently to form a brown flocculent precipitate (sediment). Allow the bottle to stand undisturbed for 2 minutes to let the sediment settle.")
add_p("Step 3 (Acidification / Dissolution): Uncap the bottle, add 3 drops of Reagent #3, stopper tightly, and shake until the brown sediment completely dissolves. The solution turns clear yellow as free iodine is released in direct proportion to dissolved oxygen. Divide this prepared solution equally into the second BOD bottle.")
add_p("Step 4 (Titration): Select one of the divided bottles and titrate with Reagent #T, adding one drop at a time while gently swirling ('jogging') the bottle. Count the total amount of drops (A) required to turn the yellow solution completely clear and colorless.")
add_p("Calculation Formula: The amount of dissolved oxygen in the water is computed as: Dissolved Oxygen (mg/L) = A \u00f7 2 (since each drop equals 0.50 mg/L).")

# 8.1 Table 28: Paired Trials
add_h2("8.1 Paired Titration Validation Trials")
add_p("Table 28 shows the ten paired comparative trials for dissolved oxygen. The chemical titration reference averaged 6.400 mg/L (corresponding to an average of 12.8 chemical drops), while the IoT sensor averaged 6.430 mg/L\u2014an aggregate difference of only 0.030 mg/L. The average error (MAE) across all ten trials was 0.220 mg/L.")
add_table_header(28, "Paired Trial Results for Dissolved Oxygen Sensor vs. Chemical Titration Kit")
build_extracted_table(tables[27], has_summary_row=True)
add_table_note("Each drop of chemical reagent in the test kit equals 0.50 mg/L DO. The bottom row summarizes the 10 paired trials across water conditions from 4.0 to 9.0 mg/L.")

add_p("Data Interpretation and Consistency Analysis for Dissolved Oxygen:")
add_p("1. Nature of Paired Testing across Dynamic Range: Chemical titration is a destructive chemical assay: once reagents are added and titrated to a colorless state, the sample chemistry is permanently altered and cannot be re-measured. Furthermore, the ten trials represent ten distinct water samples spanning a broad environmental range from 4.0 mg/L to 9.0 mg/L. The standard deviation of these readings (1.658 mg/L) reflects the wide environmental span of the tested water samples rather than sensor inconsistency.")

add_p("2. Statistical Evidence of Sensor Consistency: The test results confirm that the DO sensor demonstrates steady and consistent performance across the tested range:")
add_p("\u2022 Tightly Bounded Error: Across all 10 trials, the measurement deviation was strictly confined between 0.10 mg/L and 0.30 mg/L. No trial exhibited erratic fluctuations.")
add_p("\u2022 Standard Deviation of Error (Residual SD): The standard deviation of the error values themselves across all 10 trials is only 0.079 mg/L. This low spread confirms that the sensor measures with steady, uniform behavior across different water samples.")
add_p("\u2022 High Linear Agreement (R\u00b2 = 0.9978): When comparing the IoT sensor readings to the titration reference across the 4.0 to 9.0 mg/L range, the Pearson correlation coefficient is r = 0.9989, yielding a coefficient of determination of R\u00b2 = 0.9978 (99.8% linear agreement). This confirms that as oxygen levels vary, the electronic sensor tracks the chemical reference proportionally.")
add_p("\u2022 Sub-Drop Deviation: The manual test kit has a discrete step resolution of 0.50 mg/L per drop. An MAE of 0.220 mg/L is less than half of a single chemical drop, demonstrating that the electronic sensor matches the practical resolution limit of the manual titration standard.")

add_conclusion_box("Across ten paired trials, the DO sensor had an average error of 0.220 mg/L (less than half of one chemical test drop), an error standard deviation of 0.079 mg/L, and a 99.8% linear correlation (R\u00b2 = 0.9978), demonstrating steady tracking across the full 4.0–9.0 mg/L range.")
add_verdict_box("Dissolved Oxygen Subsystem", "With an error of 0.220 mg/L and consistent linear tracking across 10 paired trials, the DO sensor reliably monitors dissolved oxygen dynamics. In AUTO mode, it supports automated relay control of the aerators (Aerator 1 and Aerator 2) when DO levels decline, helping protect crayfish from hypoxic conditions.")

# ==================== SECTION 9 ====================
add_h1("9. Overall System Master Summary and Operational Readiness")
add_p("After evaluating all seven hardware components individually across their respective conditions, Table 29 consolidates the complete results of measurement error (MAE) and consistency (SD) for the CrayCare system across all 190 calibration trials.")

# Table 29: Master Summary Table placed at the very end
add_table_header(29, "Master Summary of Sensor Accuracy (MAE) and Consistency (SD) Across All Components")
build_extracted_table(tables[28], has_summary_row=True)
add_table_note("The bottom row shows the grand total of 190 calibration trials across all seven hardware parts. Standard laboratory reference tools were used for all comparisons.")

add_p("Data Interpretation of Master Summary: Table 29 confirms that each hardware component performed within acceptable operational limits for redclaw crayfish grow-out farming:")
add_p("1. Water Temperature (20 trials): Average error of only 0.043 \u00b0C and SD of 0.024–0.036 \u00b0C, supporting steady thermal monitoring within the recommended 26.0–29.0 \u00b0C range.")
add_p("2. Tank Water Level (40 trials): Average error of 0.145 cm (~1.45 mm), maintaining proper depth so crayfish shelters stay submerged without risk of tank overflow.")
add_p("3. Feeder Hopper Level (20 trials): Average error of 0.244 cm (~2.4 mm), reliably alerting the farm owner through the mobile application when feed level is low.")
add_p("4. Automatic Feeder (46 trials): Average error of only 4.5% at standard 10 g rations, supporting scheduled feeding to prevent water fouling and territorial aggression.")
add_p("5. Water Turbidity (24 trials): Baseline error of 0.150 NTU in clear water and under 2.4% error in cloudy water, reliably notifying the user when water clarity deteriorates.")
add_p("6. Water pH (30 trials): Pooled error of 0.098 pH, performing comfortably within the aquaculture benchmark (\u00b10.20 pH) to support water quality management.")
add_p("7. Dissolved Oxygen (10 trials): Average error of 0.220 mg/L (less than half of one chemical drop) with 99.8% linear agreement (R\u00b2 = 0.9978), reliably supporting aerator relay control in AUTO mode before oxygen drops to critical levels.")

add_verdict_box("Complete CrayCare System", "All seven hardware subsystems successfully completed evaluation across 190 independent trials, with all measurement errors remaining within acceptable limits for crayfish aquaculture. The automated system supports real-time water quality monitoring, mobile alert notifications, scheduled feeding, and relay control of aerators and water circulation, providing dependable technical support for small-scale Australian redclaw crayfish grow-out farming.")

# Save outputs
out_downloads = r"C:\Users\Dave\Downloads\MAE_and_SD_Results_Enhanced.docx"
out_final = r"C:\Users\Dave\Downloads\MAE_and_SD_Results_Final.docx"
out_updated = r"C:\Users\Dave\Downloads\MAE_and_SD_Results_Updated.docx"
out_workspace = r"c:\Users\Dave\CrayCare\MAE_and_SD_Results_Enhanced.docx"

saved_files = []
for out_path in [out_downloads, out_final, out_updated, out_workspace]:
    try:
        doc.save(out_path)
        saved_files.append(out_path)
        print(f"Saved: {out_path}")
    except Exception as e:
        print(f"Could not save to {out_path}: {e}")

print(f"Done! Successfully generated complete document with {len(doc.paragraphs)} paragraphs and {len(doc.tables)} tables.")
