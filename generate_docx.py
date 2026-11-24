import docx
from docx.shared import Inches, Pt, RGBColor
from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.enum.table import WD_TABLE_ALIGNMENT
from docx.oxml import OxmlElement, parse_xml
from docx.oxml.ns import nsdecls, qn
import os

def set_cell_margins(cell, top=90, bottom=90, left=110, right=110):
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

doc = docx.Document()

# Page Setup (1 inch margins)
for section in doc.sections:
    section.top_margin = Inches(1.0)
    section.bottom_margin = Inches(1.0)
    section.left_margin = Inches(1.0)
    section.right_margin = Inches(1.0)

# Set base style to Times New Roman, 12pt
normal_style = doc.styles['Normal']
normal_style.font.name = 'Times New Roman'
normal_style.font.size = Pt(12)
normal_style.font.color.rgb = RGBColor(0, 0, 0)
normal_style.paragraph_format.line_spacing = 1.5
normal_style.paragraph_format.space_after = Pt(6)

# Title
title = doc.add_paragraph()
title.paragraph_format.space_before = Pt(0)
title.paragraph_format.space_after = Pt(14)
title.alignment = WD_ALIGN_PARAGRAPH.CENTER
t_run = title.add_run("Results and Discussion: Crayfish Mortality and Population Dynamics")
t_run.bold = True
t_run.font.size = Pt(16)
t_run.font.name = 'Times New Roman'

# Subheading 1
sub1 = doc.add_paragraph()
sub1.paragraph_format.space_before = Pt(12)
sub1.paragraph_format.space_after = Pt(4)
s1_run = sub1.add_run("1. Experimental Setup and Initial Conditions")
s1_run.bold = True
s1_run.font.size = Pt(13)

p1 = doc.add_paragraph()
p1.paragraph_format.first_line_indent = Inches(0.5)
p1.add_run("At the beginning of the study, Tank A and Tank B were established under identical rearing conditions to ensure a controlled comparison and eliminate environmental bias. Both tanks shared the same dimensions, utilized water from the same source, and were equipped with an equal number of artificial shelters or hides. On October 9, 2026, each tank was stocked with an initial baseline population of 100 juvenile redclaw crayfish (")
p1_sci = p1.add_run("Cherax quadricarinatus")
p1_sci.italic = True
p1.add_run("). The primary planned variable between the two setups was the management approach: Tank A was managed with the assistance of the automated CrayCare system, whereas Tank B relied exclusively on traditional manual operations.")

# Subheading 2
sub2 = doc.add_paragraph()
sub2.paragraph_format.space_before = Pt(12)
sub2.paragraph_format.space_after = Pt(4)
s2_run = sub2.add_run("2. Cumulative Population Count and Overall Mortality")
s2_run.bold = True
s2_run.font.size = Pt(13)

p2 = doc.add_paragraph()
p2.paragraph_format.first_line_indent = Inches(0.5)
p2.add_run("The final population count was recorded on November 13, 2026, concluding the 35-day (5-week) trial period. Tank A yielded 93 surviving crayfish, whereas Tank B yielded 71 surviving individuals. The cumulative mortality rate was calculated using the standard formula:")

# Formula Box
p_formula = doc.add_paragraph()
p_formula.alignment = WD_ALIGN_PARAGRAPH.CENTER
p_formula.paragraph_format.space_before = Pt(4)
p_formula.paragraph_format.space_after = Pt(8)
f_run = p_formula.add_run("Cumulative Mortality Rate (%) = [(Initial Population − Final Survivors) ÷ Initial Population] × 100")
f_run.bold = True
f_run.italic = True
f_run.font.size = Pt(11)

p_table1_intro = doc.add_paragraph()
p_table1_intro.paragraph_format.first_line_indent = Inches(0.5)
p_table1_intro.add_run("Table 1 summarizes the overall initial population, surviving counts, and cumulative mortality rates observed across both tanks.")

# Table 1 Title
p_tbl1_title = doc.add_paragraph()
p_tbl1_title.paragraph_format.space_before = Pt(8)
p_tbl1_title.paragraph_format.space_after = Pt(2)
t1_bold = p_tbl1_title.add_run("Table 1\n")
t1_bold.bold = True
t1_italic = p_tbl1_title.add_run("Overall Population Counts and Cumulative Mortality Rates (Oct. 9 – Nov. 13, 2026)")
t1_italic.italic = True

table1 = doc.add_table(rows=3, cols=6)
table1.alignment = WD_TABLE_ALIGNMENT.CENTER
set_table_borders(table1)

headers1 = [
    "Tank",
    "Management Method",
    "Initial Population\n(Oct. 9, 2026)",
    "Final Survivors\n(Nov. 13, 2026)",
    "Presumed Mortalities /\nMissing*",
    "Cumulative\nMortality Rate"
]

data1 = [
    ["Tank A", "CrayCare-assisted management", "100", "93", "7", "7%"],
    ["Tank B", "Manual management", "100", "71", "29", "29%"]
]

hdr_row1 = table1.rows[0]
for idx, text in enumerate(headers1):
    cell = hdr_row1.cells[idx]
    cell.text = text
    p = cell.paragraphs[0]
    p.alignment = WD_ALIGN_PARAGRAPH.CENTER
    p.paragraph_format.line_spacing = 1.0
    p.paragraph_format.space_after = Pt(2)
    p.paragraph_format.space_before = Pt(2)
    for run in p.runs:
        run.bold = True
        run.font.name = 'Times New Roman'
        run.font.size = Pt(10)
    set_cell_margins(cell, top=80, bottom=80, left=100, right=100)
    set_cell_background(cell, "F2F2F2")

add_header_bottom_border(hdr_row1)

for r_idx, row_data in enumerate(data1):
    row = table1.rows[r_idx + 1]
    for c_idx, val in enumerate(row_data):
        cell = row.cells[c_idx]
        cell.text = val
        p = cell.paragraphs[0]
        p.alignment = WD_ALIGN_PARAGRAPH.CENTER if c_idx != 1 else WD_ALIGN_PARAGRAPH.LEFT
        p.paragraph_format.line_spacing = 1.0
        p.paragraph_format.space_after = Pt(2)
        p.paragraph_format.space_before = Pt(2)
        for run in p.runs:
            run.font.name = 'Times New Roman'
            run.font.size = Pt(10)
        set_cell_margins(cell, top=80, bottom=80, left=100, right=100)

p_note1 = doc.add_paragraph()
p_note1.paragraph_format.space_before = Pt(4)
p_note1.paragraph_format.space_after = Pt(12)
n1_lead = p_note1.add_run("*Note. ")
n1_lead.italic = True
n1_lead.font.size = Pt(10)
n1_text = p_note1.add_run("In communal decapod culture, population decreases account for both confirmed dead individuals (carcasses) and unrecovered individuals presumed lost to post-molt cannibalism. No individuals escaped or were intentionally removed during the observation period.")
n1_text.font.size = Pt(10)

# Subheading 3: Weekly Mortality Progression
sub3 = doc.add_paragraph()
sub3.paragraph_format.space_before = Pt(14)
sub3.paragraph_format.space_after = Pt(4)
s3_run = sub3.add_run("3. Weekly Population and Mortality Progression")
s3_run.bold = True
s3_run.font.size = Pt(13)

p_w1 = doc.add_paragraph()
p_w1.paragraph_format.first_line_indent = Inches(0.5)
p_w1.add_run("To evaluate the temporal progression of mortality throughout the 35-day rearing trial, weekly population censuses were conducted at the conclusion of each 7-day interval following stocking. Table 2 details the surviving population, weekly mortality increments, and cumulative mortality rates recorded for both tanks from baseline (Week 0) through Week 5.")

# Table 2 Title
p_tbl2_title = doc.add_paragraph()
p_tbl2_title.paragraph_format.space_before = Pt(8)
p_tbl2_title.paragraph_format.space_after = Pt(2)
t2_bold = p_tbl2_title.add_run("Table 2\n")
t2_bold.bold = True
t2_italic = p_tbl2_title.add_run("Weekly Census, Mortality Increments, and Cumulative Mortality Across 5 Weeks")
t2_italic.italic = True

table2 = doc.add_table(rows=7, cols=7)
table2.alignment = WD_TABLE_ALIGNMENT.CENTER
set_table_borders(table2)

headers2 = [
    "Observation\nPeriod",
    "Tank A\nSurvivors",
    "Tank A\nWeekly Deaths",
    "Tank A\nCum. Mort. (%)",
    "Tank B\nSurvivors",
    "Tank B\nWeekly Deaths",
    "Tank B\nCum. Mort. (%)"
]

data2 = [
    ["Week 0 (Oct. 09)", "100", "0", "0%", "100", "0", "0%"],
    ["Week 1 (Oct. 16)", "98", "2", "2%", "96", "4", "4%"],
    ["Week 2 (Oct. 23)", "96", "2", "4%", "89", "7", "11%"],
    ["Week 3 (Oct. 30)", "95", "1", "5%", "83", "6", "17%"],
    ["Week 4 (Nov. 06)", "95", "0", "5%", "78", "5", "22%"],
    ["Week 5 (Nov. 13)", "93", "2", "7%", "71", "7", "29%"]
]

hdr_row2 = table2.rows[0]
for idx, text in enumerate(headers2):
    cell = hdr_row2.cells[idx]
    cell.text = text
    p = cell.paragraphs[0]
    p.alignment = WD_ALIGN_PARAGRAPH.CENTER
    p.paragraph_format.line_spacing = 1.0
    p.paragraph_format.space_after = Pt(2)
    p.paragraph_format.space_before = Pt(2)
    for run in p.runs:
        run.bold = True
        run.font.name = 'Times New Roman'
        run.font.size = Pt(9.5)
    set_cell_margins(cell, top=70, bottom=70, left=80, right=80)
    set_cell_background(cell, "F2F2F2")

add_header_bottom_border(hdr_row2)

for r_idx, row_data in enumerate(data2):
    row = table2.rows[r_idx + 1]
    for c_idx, val in enumerate(row_data):
        cell = row.cells[c_idx]
        cell.text = val
        p = cell.paragraphs[0]
        p.alignment = WD_ALIGN_PARAGRAPH.CENTER
        p.paragraph_format.line_spacing = 1.0
        p.paragraph_format.space_after = Pt(2)
        p.paragraph_format.space_before = Pt(2)
        for run in p.runs:
            run.font.name = 'Times New Roman'
            run.font.size = Pt(9.5)
        set_cell_margins(cell, top=70, bottom=70, left=80, right=80)

# Figure 1: Weekly Chart
p_fig1_title = doc.add_paragraph()
p_fig1_title.paragraph_format.space_before = Pt(12)
p_fig1_title.paragraph_format.space_after = Pt(2)
f1_bold = p_fig1_title.add_run("Figure 1\n")
f1_bold.bold = True
f1_italic = p_fig1_title.add_run("Weekly Surviving Population and Cumulative Mortality Trajectories Between Tank A and Tank B")
f1_italic.italic = True

chart_img_path = r"c:\Users\Dave\CrayCare\weekly_mortality_chart.png"
if os.path.exists(chart_img_path):
    p_chart = doc.add_paragraph()
    p_chart.alignment = WD_ALIGN_PARAGRAPH.CENTER
    p_chart.paragraph_format.space_before = Pt(4)
    p_chart.paragraph_format.space_after = Pt(4)
    r_c = p_chart.add_run()
    r_c.add_picture(chart_img_path, width=Inches(6.2))

p_fig1_note = doc.add_paragraph()
p_fig1_note.paragraph_format.space_before = Pt(2)
p_fig1_note.paragraph_format.space_after = Pt(10)
f1n_lead = p_fig1_note.add_run("Note. ")
f1n_lead.italic = True
f1n_lead.font.size = Pt(10)
f1n_text = p_fig1_note.add_run("(A) Weekly census counts of surviving crayfish. (B) Cumulative mortality trajectory across the 35-day trial period. Tank A was assisted by the CrayCare automated system, while Tank B was managed manually.")
f1n_text.font.size = Pt(10)

p_w2 = doc.add_paragraph()
p_w2.paragraph_format.first_line_indent = Inches(0.5)
p_w2.add_run("As illustrated in Figure 1 and Table 2, the population trajectories of the two tanks diverged immediately after the first week and widened progressively over time. Tank A exhibited remarkable stability throughout the entire 35-day period: weekly mortality was consistently negligible, registering only 0 to 2 mortalities per week (Week 1: 2; Week 2: 2; Week 3: 1; Week 4: 0; Week 5: 2). Notably, during Week 4, Tank A achieved a 100% weekly survival rate with zero recorded deaths, culminating in 93 survivors (7% cumulative mortality).")

p_w3 = doc.add_paragraph()
p_w3.paragraph_format.first_line_indent = Inches(0.5)
p_w3.add_run("In stark contrast, Tank B displayed continuous, severe mortality each week. Following an initial 4 deaths in Week 1, Tank B experienced substantial, sustained population reductions across all subsequent weeks, recording 7 deaths in Week 2, 6 deaths in Week 3, 5 deaths in Week 4, and 7 deaths in Week 5. This consistent loss of 5 to 7 crayfish weekly demonstrates that adverse conditions in Tank B were persistent rather than episodic.")

p_w4 = doc.add_paragraph()
p_w4.paragraph_format.first_line_indent = Inches(0.5)
p_w4.add_run("This chronic mortality pattern in Tank B illustrates the compounding nature of manual management shortcomings. Irregular feeding intervals, unmeasured rations, and unmonitored feed accumulation led to progressive deterioration of water quality. Concurrently, juvenile redclaw crayfish molt frequently during early life stages. When subjected to persistent nutritional and environmental stress, soft-shelled post-molt individuals are repeatedly preyed upon by conspecifics, leading to continuous cannibalistic losses throughout the rearing period as evidenced by frequent gastrolith collections.")

# Subheading 4: Operational Consistency
sub4 = doc.add_paragraph()
sub4.paragraph_format.space_before = Pt(14)
sub4.paragraph_format.space_after = Pt(4)
s4_run = sub4.add_run("4. Operational Consistency and Water Quality Dynamics")
s4_run.bold = True
s4_run.font.size = Pt(13)

p3 = doc.add_paragraph()
p3.paragraph_format.first_line_indent = Inches(0.5)
p3.add_run("The contrasting weekly trends underscore the operational advantages of automated system assistance over manual maintenance. In Tank A, the CrayCare system ensured scheduled, regulated feed delivery and continuous, real-time tracking of water parameters. This consistency prevented food deprivation while avoiding the bio-overload associated with overfeeding.")

p4 = doc.add_paragraph()
p4.paragraph_format.first_line_indent = Inches(0.5)
p4.add_run("Conversely, Tank B was subject to the inherent limitations and vulnerabilities of manual labor. Because manual management depends strictly on human intervention and availability, it was prone to operational lapses, irregular monitoring, and subjective portioning. Researchers observed repeated occasions where feeding in Tank B was delayed, administered outside regular schedules, or provided in unmeasured, excessive amounts. Furthermore, because manual water checking was intermittent, critical parameter shifts could not be detected or remediated immediately. These operational lapses directly align with findings by Viau et al. (2012) and Barki et al. (1997), which establish that juvenile redclaw survival is strongly governed by water quality stability, and that irregular feed rationing and uneven distribution intensify competition, behavioral stress, and mortality.")

# Subheading 5: Gastrolith Observations
sub5 = doc.add_paragraph()
sub5.paragraph_format.space_before = Pt(14)
sub5.paragraph_format.space_after = Pt(4)
s5_run = sub5.add_run("5. Gastrolith Observations and Potential Cannibalism")
s5_run.bold = True
s5_run.font.size = Pt(13)

p5 = doc.add_paragraph()
p5.paragraph_format.first_line_indent = Inches(0.5)
p5.add_run("Throughout the study, researchers retrieved gastroliths considerably more frequently from Tank B than from Tank A (see Figure 2). Gastroliths are disc-like calcium deposits formed within the stomach wall during the pre-molt stage and are directly linked to the molt cycle of ")
p5_sci1 = p5.add_run("Cherax quadricarinatus")
p5_sci1.italic = True
p5.add_run(" (Shechter et al., 2008). In studies of Australian ")
p5_sci2 = p5.add_run("Cherax")
p5_sci2.italic = True
p5.add_run(" species, gastroliths recovered from the substrate without accompanying carcasses serve as supporting physical evidence of cannibalism, as the soft post-molt body is consumed while the hard, calcified gastroliths remain undigested (Wangpen, 2007).")

# Figure 2: Gastrolith Photo
p_fig2_title = doc.add_paragraph()
p_fig2_title.paragraph_format.space_before = Pt(10)
p_fig2_title.paragraph_format.space_after = Pt(2)
fig2_num = p_fig2_title.add_run("Figure 2\n")
fig2_num.bold = True
fig2_name = p_fig2_title.add_run("Gastroliths Retrieved from Experimental Rearing Tanks")
fig2_name.italic = True

gastro_img_path = r"c:\Users\Dave\CrayCare\gastroliths_sample.png"
if os.path.exists(gastro_img_path):
    p_gimg = doc.add_paragraph()
    p_gimg.alignment = WD_ALIGN_PARAGRAPH.CENTER
    p_gimg.paragraph_format.space_before = Pt(4)
    p_gimg.paragraph_format.space_after = Pt(4)
    rg = p_gimg.add_run()
    rg.add_picture(gastro_img_path, width=Inches(2.0))

p_fig2_note = doc.add_paragraph()
p_fig2_note.paragraph_format.space_before = Pt(2)
p_fig2_note.paragraph_format.space_after = Pt(10)
f2n_lead = p_fig2_note.add_run("Note. ")
f2n_lead.italic = True
f2n_lead.font.size = Pt(10)
f2n_text = p_fig2_note.add_run("Paired, calcified gastroliths collected from experimental tanks during sampling. The presence of intact gastroliths on the substrate in the absence of carcasses provides supporting physical evidence of post-molt cannibalism.")
f2n_text.font.size = Pt(10)

p6 = doc.add_paragraph()
p6.paragraph_format.first_line_indent = Inches(0.5)
p6.add_run("In the present study, the elevated frequency of gastroliths in Tank B—observed across successive weeks—is consistent with the likelihood that cannibalism was a major contributor to the unrecovered mortalities. However, gastroliths alone cannot definitively determine whether an individual died from direct cannibalistic attack or succumbed to natural molting complications prior to scavenging. Because the number of hides was strictly identical in both tanks, hide availability was controlled, pointing to operational and feeding consistency as the key differentiating factors.")

# Subheading 6: Comparative Context with Related Smart Aquaculture Studies (NEW SECTION)
sub6 = doc.add_paragraph()
sub6.paragraph_format.space_before = Pt(14)
sub6.paragraph_format.space_after = Pt(4)
s6_run = sub6.add_run("6. Comparative Context with Related Smart Aquaculture Studies")
s6_run.bold = True
s6_run.font.size = Pt(13)

p_comp1 = doc.add_paragraph()
p_comp1.paragraph_format.first_line_indent = Inches(0.5)
p_comp1.add_run("The mortality results observed in the present study are directionally consistent with recent comparative aquaculture studies investigating IoT-enabled and automated management systems across decapod crustacean species. Table 3 presents a comparative summary of reported survival and mortality figures between automated/smart systems and conventional/manual farming methods in related literature.")

# Table 3: Comparative Studies Table
p_tbl3_title = doc.add_paragraph()
p_tbl3_title.paragraph_format.space_before = Pt(8)
p_tbl3_title.paragraph_format.space_after = Pt(2)
t3_bold = p_tbl3_title.add_run("Table 3\n")
t3_bold.bold = True
t3_italic = p_tbl3_title.add_run("Comparison of Survival and Mortality Metrics in Smart vs. Conventional Crustacean Aquaculture Studies")
t3_italic.italic = True

table3 = doc.add_table(rows=5, cols=5)
table3.alignment = WD_TABLE_ALIGNMENT.CENTER
set_table_borders(table3)

headers3 = [
    "Study",
    "Species",
    "Experimental Comparison",
    "Smart / IoT System Results",
    "Conventional / Manual Results"
]

data3 = [
    [
        "Ramirez et al. (2026)",
        "Australian redclaw crayfish\n(Cherax quadricarinatus)",
        "CrayTure smart monitoring system vs. conventional farming",
        "Survival: 93.33%\n(Implied Mort.: 6.67%)",
        "Survival: 73.33%\n(Implied Mort.: 26.67%)"
    ],
    [
        "Khunsoongnoen et al. (2025)",
        "Giant freshwater prawn\n(Macrobrachium rosenbergii)",
        "IoT-enabled pond vs. traditional pond (N = 300 per pond)",
        "Deaths: 36\nMortality: 12.00%\n(Survival: 88.00%)",
        "Deaths: 85\nMortality: 28.33%\n(Survival: 71.67%)"
    ],
    [
        "Blancaflor & Baccay (2022)",
        "Whiteleg shrimp\n(Litopenaeus vannamei)",
        "IoT-managed biofloc system vs. conventional RAS",
        "Survival: 93.00%\n(Implied Mort.: 7.00%)",
        "Survival: 85.00%\n(Implied Mort.: 15.00%)"
    ],
    [
        "Present Study (2026)",
        "Australian redclaw crayfish\n(Cherax quadricarinatus)",
        "CrayCare automated management vs. manual management (N = 100)",
        "Deaths: 7\nMortality: 7.00%\nSurvival: 93.00%",
        "Deaths: 29\nMortality: 29.00%\nSurvival: 71.00%"
    ]
]

hdr_row3 = table3.rows[0]
for idx, text in enumerate(headers3):
    cell = hdr_row3.cells[idx]
    cell.text = text
    p = cell.paragraphs[0]
    p.alignment = WD_ALIGN_PARAGRAPH.CENTER
    p.paragraph_format.line_spacing = 1.0
    p.paragraph_format.space_after = Pt(2)
    p.paragraph_format.space_before = Pt(2)
    for run in p.runs:
        run.bold = True
        run.font.name = 'Times New Roman'
        run.font.size = Pt(9.5)
    set_cell_margins(cell, top=70, bottom=70, left=80, right=80)
    set_cell_background(cell, "F2F2F2")

add_header_bottom_border(hdr_row3)

for r_idx, row_data in enumerate(data3):
    row = table3.rows[r_idx + 1]
    for c_idx, val in enumerate(row_data):
        cell = row.cells[c_idx]
        cell.text = val
        p = cell.paragraphs[0]
        p.alignment = WD_ALIGN_PARAGRAPH.CENTER if c_idx >= 3 else WD_ALIGN_PARAGRAPH.LEFT
        p.paragraph_format.line_spacing = 1.0
        p.paragraph_format.space_after = Pt(2)
        p.paragraph_format.space_before = Pt(2)
        for run in p.runs:
            if r_idx == 3:  # Present study highlight
                run.bold = True
            run.font.name = 'Times New Roman'
            run.font.size = Pt(9.0)
        set_cell_margins(cell, top=70, bottom=70, left=80, right=80)

p_note3 = doc.add_paragraph()
p_note3.paragraph_format.space_before = Pt(4)
p_note3.paragraph_format.space_after = Pt(10)
n3_lead = p_note3.add_run("*Note. ")
n3_lead.italic = True
n3_lead.font.size = Pt(10)
n3_text = p_note3.add_run("Implied mortality percentages are calculated as 100% minus reported survival percentage. Differences in production systems, stocking densities, and species biology mean these studies provide contextual comparison rather than direct empirical equivalence.")
n3_text.font.size = Pt(10)

p_comp2 = doc.add_paragraph()
p_comp2.paragraph_format.first_line_indent = Inches(0.5)
p_comp2.add_run("The mortality outcomes of the present study correspond closely with the findings of Ramirez et al. (2026), who reported a survival rate of 93.33% (6.67% implied mortality) in their smart-system group compared to 73.33% (26.67% implied mortality) in conventional redclaw crayfish rearing. This directional similarity is further corroborated in broader decapod aquaculture: Khunsoongnoen et al. (2025) recorded a mortality rate of 12% in an IoT-enabled pond versus 28.33% in a traditional pond for giant freshwater prawn (")
p_comp2_sci = p_comp2.add_run("Macrobrachium rosenbergii")
p_comp2_sci.italic = True
p_comp2.add_run("). In another crustacean context, Blancaflor and Baccay (2022) documented enhanced survival under an IoT-biofloc water quality management system (93%) relative to conventional recirculating aquaculture systems (85%) for whiteleg shrimp (")
p_comp2_sci2 = p_comp2.add_run("Litopenaeus vannamei")
p_comp2_sci2.italic = True
p_comp2.add_run(").")

p_comp3 = doc.add_paragraph()
p_comp3.paragraph_format.first_line_indent = Inches(0.5)
p_comp3.add_run("These comparative studies demonstrate that the elevated survival in Tank A (93%) and the increased mortality in Tank B (29%) fall well within recognized empirical ranges for automated versus traditional crustacean management. Nonetheless, critical distinctions in species biology, physical scale, sensor architectures, and water treatment methods mean that external studies provide supportive benchmark context rather than proving the specific causal mechanisms of the mortality difference in this investigation.")

# Subheading 7: Role of CrayCare System and Study Scope
sub7 = doc.add_paragraph()
sub7.paragraph_format.space_before = Pt(14)
sub7.paragraph_format.space_after = Pt(4)
s7_run = sub7.add_run("7. Role of the CrayCare System and Study Scope")
s7_run.bold = True
s7_run.font.size = Pt(13)

p7 = doc.add_paragraph()
p7.paragraph_format.first_line_indent = Inches(0.5)
p7.add_run("Overall, Tank A achieved a substantially higher survival rate (93%) compared to Tank B (71%). Importantly, this difference in mortality is not claimed to be solely or exclusively solved by the CrayCare system, as crayfish survival is multifactorial and naturally subject to biological vulnerabilities such as molting complications. Rather, the CrayCare system functioned as an effective assistive tool that significantly improved overall ")
p7_b = p7.add_run("crayfish care and tank maintenance")
p7_b.bold = True
p7.add_run(". By automating scheduled feedings and providing continuous environmental oversight, the system mitigated the risks of human error and operational delays, thereby sustaining a more stable and supportive rearing environment.")

# References Section
doc.add_page_break()
p_ref_h = doc.add_paragraph()
p_ref_h.alignment = WD_ALIGN_PARAGRAPH.CENTER
p_ref_h.paragraph_format.space_before = Pt(12)
p_ref_h.paragraph_format.space_after = Pt(12)
rh_run = p_ref_h.add_run("References")
rh_run.bold = True
rh_run.font.size = Pt(14)

references = [
    (
        "Barki, A., Levi, T., Shrem, A., & Karplus, I. (1997). Ration and spatial distribution of feed affect survival, growth, and competition in juvenile red-claw crayfish, ",
        "Cherax quadricarinatus",
        ", reared in the laboratory. ",
        "Aquaculture",
        ", 148(2–3), 169–177. https://doi.org/10.1016/S0044-8486(96)01418-4"
    ),
    (
        "Blancaflor, E. B., & Baccay, M. (2022). Assessment of an automated IoT-biofloc water quality management system in the Litopenaeus vannamei’s mortality and growth rate. ",
        "",
        "",
        "Automatika",
        ", 63(2), 259–274. https://doi.org/10.1080/00051144.2022.2031540"
    ),
    (
        "Khunsoongnoen, C., Thianphan, S., & Bua-ngam, P. (2025). Development of an IoT-based water quality monitoring application to enhance productivity in giant freshwater prawn farming. ",
        "",
        "",
        "Maejo Information Technology and Innovation Journal",
        ", 11(3), 392–405. https://doi.org/10.14456/mitij.2025.56"
    ),
    (
        "Ramirez, N. A. T., Salatan, C. K. W., Datuan, A. J. S., Tanoy, Z. C., Tatu, S. G., & Castillo, J. P. (2026). CrayTure: Smart aquaculture system and water quality monitoring for Australian red-claw crayfish farming using YOLOv11. In ",
        "2026 International Conference on Automatics, Robotics and Artificial Intelligence (ICARAI)",
        ". IEEE. https://doi.org/10.1109/ICARAI70085.2026.11635267",
        "",
        ""
    ),
    (
        "Shechter, A., Berman, A., Singer, A., Freiman, A., Grinstein, M., Erez, J., Aflalo, E. D., & Sagi, A. (2008). Reciprocal changes in calcification of the gastrolith and cuticle during the molt cycle of the red claw crayfish ",
        "Cherax quadricarinatus",
        ". ",
        "The Biological Bulletin",
        ", 214(2), 122–134. https://doi.org/10.2307/25066669"
    ),
    (
        "Viau, V. E., Ostera, J. M., Tolivia, A., Ballester, E. L. C., Abreu, P. C., & Rodríguez, E. M. (2012). Contribution of biofilm to water quality, survival and growth of juveniles of the freshwater crayfish ",
        "Cherax quadricarinatus",
        " (Decapoda, Parastacidae). ",
        "Aquaculture",
        ", 324–325, 70–78. https://www.sciencedirect.com/science/article/abs/pii/S004484861100799X?via%3Dihub"
    ),
    (
        "Wangpen, P. (2007). ",
        "The role of shelter in Australian freshwater crayfish (Cherax spp.) polysystems",
        " [Doctoral dissertation, Curtin University of Technology]. Curtin University Research Repository. https://espace.curtin.edu.au/bitstream/handle/20.500.11937/2312/15622_wangpen%20Phd.pdf?sequence=2",
        "",
        ""
    )
]

for ref in references:
    p = doc.add_paragraph()
    p.paragraph_format.left_indent = Inches(0.5)
    p.paragraph_format.first_line_indent = Inches(-0.5)
    p.paragraph_format.space_after = Pt(8)
    p.paragraph_format.line_spacing = 1.15
    
    p.add_run(ref[0])
    if ref[1]:
        r1 = p.add_run(ref[1])
        r1.italic = True
    if ref[2]:
        p.add_run(ref[2])
    if ref[3]:
        r2 = p.add_run(ref[3])
        r2.italic = True
    if ref[4]:
        p.add_run(ref[4])

output_primary = r"c:\Users\Dave\CrayCare\Crayfish_Mortality_Results_and_Discussion.docx"
output_secondary = r"c:\Users\Dave\CrayCare\Crayfish_Mortality_Results_and_Discussion_with_Weekly_Data.docx"

saved = []
try:
    doc.save(output_primary)
    saved.append(output_primary)
except PermissionError:
    print(f"Notice: {output_primary} is currently open in Word.")

try:
    doc.save(output_secondary)
    saved.append(output_secondary)
except PermissionError:
    print(f"Notice: {output_secondary} is currently open in Word.")

print(f"Successfully generated docx at: {', '.join(saved)}")
