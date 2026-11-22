import docx
from docx.shared import Pt, Inches
from docx.enum.text import WD_ALIGN_PARAGRAPH

doc_path = r'C:\Users\Justin\Desktop\CrayCare\deliverables\Deliverables\ML DOCU.docx'
out_path = r'C:\Users\Justin\Desktop\CrayCare\deliverables\Deliverables\ML DOCU_Updated.docx'
doc = docx.Document(doc_path)

def format_body(p, text):
    p.text = text
    p.alignment = WD_ALIGN_PARAGRAPH.JUSTIFY
    p.paragraph_format.line_spacing = 2.0
    p.paragraph_format.first_line_indent = Inches(0.5)
    p.paragraph_format.space_before = Pt(0)
    p.paragraph_format.space_after = Pt(0)
    for r in p.runs:
        r.font.name = "Arial"
        r.font.size = Pt(11)

def format_heading(p, text):
    p.text = text
    p.alignment = WD_ALIGN_PARAGRAPH.LEFT
    p.paragraph_format.line_spacing = 2.0
    p.paragraph_format.first_line_indent = Inches(0)
    p.paragraph_format.space_before = Pt(12)
    p.paragraph_format.space_after = Pt(0)
    for r in p.runs:
        r.font.name = "Arial"
        r.font.size = Pt(11)
        r.bold = True

# 1. Update Section 3.5 Intro (P2)
intro_text = (
    "This section presents the methodology used to prepare the water quality dataset "
    "and develop the machine learning classification model in CrayCare. The model automates "
    "water quality assessment to provide small-scale Australian redclaw crayfish farmers with "
    "clear insights and actionable recommendations. The workflow integrates empirical sensor data "
    "from an operational Recirculating Aquaculture System (RAS) trapond, biological threshold standards, "
    "domain-driven data augmentation, and supervised Random Forest classification."
)
format_body(doc.paragraphs[2], intro_text)

# 2. Update Section 3.5.1 Paragraph 1 (P4)
acq_text = (
    "The empirical dataset comprises 4,962 multi-parameter sensor observations collected at ten-minute "
    "sampling intervals from the CrayCare recirculating aquaculture system (RAS) trapond facility in Lopez, "
    "Quezon between October 9, 2026, and November 12, 2026. Because the readings originate from active sensing "
    "hardware deployed in an operational RAS culture environment, the observations capture authentic diurnal cycles, "
    "post-feeding turbidity variations, oxygen consumption, and aeration dynamics. Continuous filtration in the "
    "RAS setup and routine aquaculture management maintained viable environmental conditions, resulting in 3,786 "
    "optimal Good readings and 1,176 suboptimal Poor readings with zero natural Critical events in the observed sensor stream."
)
format_body(doc.paragraphs[4], acq_text)

# 3. Update Section 3.5.5 Heading (P11)
format_heading(doc.paragraphs[11], "3.5.5 Random Forest Model Development and Algorithmic Configuration")

# 4. Update P12 (Paragraph 1 of 3.5.5)
p12_text = (
    "The classification pipeline employed a supervised Random Forest algorithm trained to map multi-parameter "
    "water sensor streams into three discrete status categories comprising Good, Poor, and Critical conditions. "
    "In addition to the four primary physical telemetry inputs (water temperature, pH level, dissolved oxygen, and turbidity), "
    "the model utilized an engineered physiological ratio feature representing the dissolved oxygen to temperature ratio "
    "to capture the inverse biological relationship between water warming and oxygen saturation capacity."
)
format_body(doc.paragraphs[12], p12_text)

# 5. Update P13 (Paragraph 2 of 3.5.5)
p13_text = (
    "To ensure rigorous temporal isolation, the researchers applied Chronological Holdout Validation with a two-hour buffer "
    "gap between successive partitions, preventing temporal autocorrelation and data leakage across splits. The earliest "
    "70 percent of empirical observations (3,473 readings) was pooled with 4,540 domain-driven augmented critical scenarios "
    "to establish an augmented training fit set of 8,013 records. Minor Gaussian jitter reflecting hardware precision limits "
    "was injected into the training partition to regularize tree splitting against sensor noise. In contrast, the subsequent "
    "15 percent validation partition (732 readings) and the final 15 percent holdout test partition (733 readings) were "
    "preserved strictly as pure empirical sensor observations collected from active pond operations."
)
format_body(doc.paragraphs[13], p13_text)

# 6. Insert Paragraph 3 of 3.5.5 before P14
p13_b_text = (
    "The model was implemented via scikit-learn using a Random Forest Classifier initialized with 300 decision estimators, "
    "unconstrained maximum tree depth, a minimum split threshold of two samples, a minimum leaf size of one sample, and "
    "a fixed random seed of 42 for exact experimental reproducibility. Node split quality was guided by the Gini impurity criterion. "
    "To correct for residual class frequency disparities following augmentation, tree loss penalties applied balanced class "
    "weighting inversely proportional to class frequencies. Hyperparameters were verified through five-fold cross-validation on "
    "the training set and confirmed against the validation partition. Following training, the ensemble logic was serialized "
    "into an optimized JSON tree representation for zero-dependency execution within the system's live serverless Cloud Functions environment."
)
# Insert before paragraph 14
p_new = doc.paragraphs[14].insert_paragraph_before()
format_body(p_new, p13_b_text)

# 7. Update Section 4.4 Conclusion Paragraph to mention RAS
for p in doc.paragraphs:
    if "Beyond categorical classifications, the CrayCare system translates" in p.text:
        dec_text = (
            "Beyond categorical classifications, the CrayCare system translates machine learning predictions into "
            "structured decision-support advisories for recirculating aquaculture system (RAS) trapond management. "
            "When sensor streams indicate deteriorating water conditions, such as elevated turbidity levels accompanied "
            "by temperature fluctuations, the analytical module automatically couples the predicted state with targeted "
            "corrective recommendations. These automated advisories instruct the user to inspect filtration media, verify "
            "aeration equipment, and perform proper water level adjustments. This integration bridges predictive machine "
            "learning with practical pond management, offering reliable operational support for small-scale crayfish producers."
        )
        format_body(p, dec_text)
        break

doc.save(doc_path)
print("Successfully updated ML DOCU.docx with ultra-detailed, 100% compliant content and RAS integration!")
