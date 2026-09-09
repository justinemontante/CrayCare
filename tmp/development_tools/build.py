from pathlib import Path
from zipfile import ZipFile, ZIP_DEFLATED
from copy import deepcopy
from lxml import etree as E
import hashlib

root = Path(__file__).resolve().parents[2]
source = next((root / 'docs').glob('Chapters*.docx'))
ns = {'w': 'http://schemas.openxmlformats.org/wordprocessingml/2006/main'}
w = '{' + ns['w'] + '}'
with ZipFile(source) as z:
    xml = E.fromstring(z.read('word/document.xml'))
    body = xml.find('w:body', ns)
    children = list(body)
    start = next(i for i,x in enumerate(children) if E.QName(x).localname == 'p' and ''.join(x.xpath('.//w:t/text()',namespaces=ns)).strip().startswith('3.3.2') and 'Development Tools' in ''.join(x.xpath('.//w:t/text()',namespaces=ns)))
    end = next(i for i in range(start+1,len(children)) if ''.join(children[i].xpath('.//w:t/text()',namespaces=ns)).startswith('3.4'))
    section = next((deepcopy(s) for x in children[start:] for s in x.xpath('./w:pPr/w:sectPr|self::w:sectPr',namespaces=ns)),deepcopy(children[-1]))
    selected = [deepcopy(x) for x in children[start:end]]
    tables = [x for x in selected if x.tag == w+'tbl']
    table = tables[0]
    for row in tables[1].findall('w:tr',ns)[1:]: table.append(deepcopy(row))
    for t in table.xpath('.//w:t',namespaces=ns):
        if t.text == 'Firebase Realtime Database': t.text = 'Cloud Firestore'
    additions = [
      ('Machine Learning Library','scikit-learn','Provides the Isolation Forest algorithm used to detect unusual combinations of water-quality readings and recent trends.'),
      ('Data Processing Libraries','pandas and NumPy','Used for organizing sensor records, validating data, and computing numerical and time-window features.'),
      ('Model Storage Library','joblib','Used to save the trained model and load it for anomaly detection.'),
      ('Backend Platform','Firebase Cloud Functions','Runs scheduled water-quality anomaly analysis and backend functions for sensor routing, notifications, and feeding schedule validation.'),
      ('Notification Service','Firebase Cloud Messaging','Delivers push notifications to the mobile application.'),
      ('Backend Runtime','Node.js','Runs the JavaScript backend functions for notifications and system integration.'),
      ('Deployment Tool','Firebase CLI','Used to deploy Cloud Functions, Firestore rules, and database indexes.'),
    ]
    prototype = table.findall('w:tr',ns)[-1]

    def make_row(values):
        row = deepcopy(prototype)
        for cell,value in zip(row.findall('w:tc',ns),values):
            paragraphs = cell.findall('w:p',ns)
            p=paragraphs[0]
            for extra in paragraphs[1:]: cell.remove(extra)
            for item in list(p):
                if item.tag != w+'pPr': p.remove(item)
            run=E.SubElement(p,w+'r'); text=E.SubElement(run,w+'t'); text.text=value
        return row

    # Python belongs to the same Programming Language group as C++ and Dart.
    dart_row = table.findall('w:tr', ns)[2]
    table.insert(list(table).index(dart_row) + 1, make_row(('', 'Python',
        'Used for processing sensor history, training the Isolation Forest model, and running Water Quality Anomaly Detection.')))
    for values in additions:
        row = make_row(values)
        table.append(row)
    # Preserve source table styling, repeat headers and let rows paginate intact.
    for i,row in enumerate(table.findall('w:tr',ns)):
        pr=row.find('w:trPr',ns)
        if pr is None: pr=E.SubElement(row,w+'trPr')
        if i==0: E.SubElement(pr,w+'tblHeader')
        E.SubElement(pr,w+'cantSplit')
        for cell in row.findall('w:tc',ns):
            for merge in cell.xpath('./w:tcPr/w:vMerge',namespaces=ns): merge.getparent().remove(merge)
        for p in row.xpath('.//w:p',namespaces=ns):
            for prop in p.xpath('./w:pPr/w:pageBreakBefore|./w:pPr/w:keepNext',namespaces=ns): prop.getparent().remove(prop)
    for child in list(body): body.remove(child)
    for x in selected:
        text=''.join(x.xpath('.//w:t/text()',namespaces=ns))
        if x.tag==w+'tbl' and x is not table: continue
        if text.startswith('Continuation of Table'): continue
        for br in x.xpath('.//w:br[@w:type="page"]|.//w:lastRenderedPageBreak|.//w:pPr/w:sectPr',namespaces=ns): br.getparent().remove(br)
        body.append(x)
    body.append(section)

    # Keep every visible item consistent at 11 pt, including headings and
    # table contents, while preserving the source document's font family.
    for run in body.xpath('.//w:r', namespaces=ns):
        rpr = run.find('w:rPr', ns)
        if rpr is None:
            rpr = E.Element(w+'rPr')
            run.insert(0, rpr)
        for name in ('sz', 'szCs'):
            size = rpr.find(f'w:{name}', ns)
            if size is None:
                size = E.SubElement(rpr, w+name)
            size.set(w+'val', '22')
    output=root/'docs'/'Development Tools.docx'
    with ZipFile(output,'w',ZIP_DEFLATED) as out:
        for item in z.infolist():
            out.writestr(item,E.tostring(xml,xml_declaration=True,encoding='UTF-8',standalone=True) if item.filename=='word/document.xml' else z.read(item.filename))
    print(output)
    print('Rows:',len(table.findall('w:tr',ns)))
    print('Reference SHA256:',hashlib.sha256(source.read_bytes()).hexdigest())
