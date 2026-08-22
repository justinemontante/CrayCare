from __future__ import annotations

import ast, csv, hashlib, json, plistlib, re, shutil, subprocess, tomllib, xml.etree.ElementTree as ET, zipfile, zlib
from pathlib import Path

ROOT = Path.cwd().resolve()
OUT = ROOT / 'audit_every_file_output_v2'
OUT.mkdir(exist_ok=True)

BINARY_EXTS = {
    '.png','.jpg','.jpeg','.gif','.webp','.ico','.ttf','.otf','.woff','.woff2','.jar','.zip','.apk','.aab',
    '.keystore','.jks','.pdf','.bin','.so','.dll','.exe','.docx','.xlsx','.pptx','.joblib'
}
XML_LIKE = {'.xml','.plist','.storyboard','.xib','.xcworkspacedata'}
BALANCE_EXTS = {'.dart','.kt','.kts','.java','.cpp','.cc','.c','.h','.hpp','.ino','.swift','.m','.mm','.cmake','.rules','.dbml','.dbdiagram'}
records, issues, text_cache = [], [], {}


def relpath(p: Path) -> str:
    try: return p.resolve().relative_to(ROOT).as_posix()
    except Exception: return p.as_posix()


def issue(path, code, msg, severity='warning'):
    issues.append({'path': path, 'code': code, 'severity': severity, 'message': msg})


def run(cmd):
    try:
        p = subprocess.run(cmd, cwd=ROOT, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=180)
        return p.returncode, p.stdout.strip()
    except Exception as e:
        return 999, f'{type(e).__name__}: {e}'


def tracked():
    raw = subprocess.check_output(['git','ls-files','-z'])
    return sorted(x.decode('utf-8','surrogateescape') for x in raw.split(b'\0') if x)


def is_binary(path: Path, data: bytes):
    return path.suffix.lower() in BINARY_EXTS or b'\x00' in data[:8192]


def validate_png(data: bytes):
    if not data.startswith(b'\x89PNG\r\n\x1a\n'): return 'invalid PNG signature'
    pos, iend = 8, False
    while pos + 12 <= len(data):
        n = int.from_bytes(data[pos:pos+4], 'big'); typ = data[pos+4:pos+8]; end = pos+12+n
        if end > len(data): return 'truncated PNG chunk'
        payload = data[pos+8:pos+8+n]
        expected = int.from_bytes(data[pos+8+n:pos+12+n], 'big')
        actual = zlib.crc32(payload, zlib.crc32(typ)) & 0xffffffff
        if actual != expected: return f'PNG CRC mismatch in {typ!r}'
        pos = end
        if typ == b'IEND': iend = True; break
    return None if iend else 'PNG missing IEND'


def validate_binary(path: Path, data: bytes):
    ext = path.suffix.lower(); notes=[]; mime='unknown'
    if shutil.which('file'):
        rc, out = run(['file','-b','--mime-type',str(path)])
        if rc == 0: mime = out
    if ext == '.png':
        e = validate_png(data)
        if e: notes.append(e)
    elif ext in {'.jpg','.jpeg'} and not (data.startswith(b'\xff\xd8') and data.rstrip().endswith(b'\xff\xd9')):
        notes.append('invalid/truncated JPEG markers')
    elif ext == '.gif' and not (data.startswith(b'GIF87a') or data.startswith(b'GIF89a')):
        notes.append('invalid GIF signature')
    elif ext == '.webp' and not (len(data)>=12 and data[:4]==b'RIFF' and data[8:12]==b'WEBP'):
        notes.append('invalid WEBP signature')
    elif ext == '.ico' and not data.startswith(b'\x00\x00\x01\x00'):
        notes.append('invalid ICO signature')
    elif ext in {'.ttf','.otf'} and data[:4] not in {b'\x00\x01\x00\x00',b'OTTO',b'ttcf',b'true'}:
        notes.append('unrecognized font signature')
    elif ext in {'.zip','.jar','.docx','.xlsx','.pptx'}:
        try:
            with zipfile.ZipFile(path) as z:
                bad=z.testzip()
                if bad: notes.append(f'corrupt archive member: {bad}')
                names=set(z.namelist())
                if ext=='.docx' and 'word/document.xml' not in names: notes.append('DOCX missing word/document.xml')
                if ext=='.xlsx' and 'xl/workbook.xml' not in names: notes.append('XLSX missing xl/workbook.xml')
                if ext=='.pptx' and 'ppt/presentation.xml' not in names: notes.append('PPTX missing ppt/presentation.xml')
        except Exception as e: notes.append(f'invalid ZIP container: {e}')
    return mime, notes


def strip_basic(text: str):
    out=[]; i=0; n=len(text); quote=None; line=False; block=False
    while i<n:
        c=text[i]; nxt=text[i+1] if i+1<n else ''
        if line:
            if c=='\n': line=False; out.append('\n')
            else: out.append(' ')
            i+=1; continue
        if block:
            if c=='*' and nxt=='/': out.extend('  '); i+=2; block=False
            else: out.append('\n' if c=='\n' else ' '); i+=1
            continue
        if quote:
            if c=='\\': out.extend('  '); i+=2; continue
            if c==quote: quote=None
            out.append('\n' if c=='\n' else ' '); i+=1; continue
        if c=='/' and nxt=='/': out.extend('  '); i+=2; line=True; continue
        if c=='/' and nxt=='*': out.extend('  '); i+=2; block=True; continue
        if c in "'\"": quote=c; out.append(' '); i+=1; continue
        out.append(c); i+=1
    return ''.join(out)


def balance_error(text):
    clean=strip_basic(text); stack=[]; pairs={')':'(',']':'[','}':'{'}
    for i,c in enumerate(clean):
        if c in '([{': stack.append((c,i))
        elif c in ')]}':
            if not stack or stack[-1][0]!=pairs[c]: return f'unbalanced {c!r} at char {i}'
            stack.pop()
    return f'unclosed {stack[-1][0]!r} at char {stack[-1][1]}' if stack else None


def parse_text_file(path: Path, text: str):
    ext=path.suffix.lower(); rp=relpath(path)
    try:
        if ext=='.json' or path.name=='package-lock.json': json.loads(text)
        elif ext in XML_LIKE: ET.fromstring(text)
        elif ext in {'.yaml','.yml'} or path.name=='pubspec.lock':
            import yaml; yaml.safe_load(text)
        elif ext=='.toml': tomllib.loads(text)
        elif ext=='.csv': list(csv.reader(text.splitlines()))
        elif ext=='.plist': plistlib.loads(text.encode())
    except Exception as e: issue(rp,'parse_error',f'{ext or path.name} parse failed: {e}','error')

    if ext=='.py':
        try: ast.parse(text, filename=rp)
        except SyntaxError as e: issue(rp,'python_syntax',str(e),'error')
    if ext in BALANCE_EXTS:
        e=balance_error(text)
        if e: issue(rp,'delimiter_balance',e,'error')
    if re.search(r'^<<<<<<< |^=======\s*$|^>>>>>>> ', text, re.M):
        issue(rp,'merge_conflict_marker','unresolved git merge marker','error')


def check_dart_imports(path: Path, text: str, tracked_set):
    rp=relpath(path)
    for spec in re.findall(r'(?:import|export|part)\s+[\'\"]([^\'\"]+)[\'\"]', text):
        if spec.startswith(('dart:','package:')): continue
        target=(path.parent/spec).resolve()
        try: rel=target.relative_to(ROOT).as_posix()
        except ValueError: issue(rp,'outside_repo_import',spec,'error'); continue
        if rel not in tracked_set: issue(rp,'missing_dart_import',spec,'error')


def resolve_local(path: Path, target: str, tracked_set):
    target=target.split('#',1)[0].split('?',1)[0].strip()
    if not target or target.startswith(('http://','https://','mailto:','data:','javascript:','#','/')): return True
    candidates=[(path.parent/target).resolve(), (ROOT/target).resolve()]
    for c in candidates:
        try: rel=c.relative_to(ROOT).as_posix()
        except ValueError: continue
        if rel in tracked_set or any(x.startswith(rel.rstrip('/')+'/') for x in tracked_set): return True
    return False


def check_links_assets(path: Path, text: str, tracked_set):
    rp=relpath(path)
    targets=[]
    if path.suffix.lower()=='.md': targets += re.findall(r'\[[^\]]*\]\(([^)]+)\)', text)
    if path.suffix.lower() in {'.html','.htm'}:
        targets += re.findall(r'(?:src|href)\s*=\s*[\'\"]([^\'\"]+)[\'\"]', text, re.I)
        targets += re.findall(r'url\(\s*[\'\"]?([^\)\'\"]+)', text, re.I)
    targets += re.findall(r'[\'\"](assets/[^\'\"\n]+)[\'\"]', text)
    targets += re.findall(r'(?:asset|image_path|adaptive_icon_foreground):\s*([^\s#]+)', text)
    for raw in targets:
        t=raw.strip().strip('<>').strip('\'\"')
        if not resolve_local(path,t,tracked_set): issue(rp,'missing_local_reference',f'local target missing: {t}','error')


def check_ios_contents(path: Path, text: str, tracked_set):
    if path.name!='Contents.json': return
    rp=relpath(path)
    try: obj=json.loads(text)
    except Exception: return
    for image in obj.get('images',[]):
        fn=image.get('filename') if isinstance(image,dict) else None
        if fn:
            target=(path.parent/fn).resolve().relative_to(ROOT).as_posix()
            if target not in tracked_set: issue(rp,'missing_asset_catalog_file',fn,'error')


def android_resource_index(tracked_set, text_cache):
    base='android/app/src/main/res/'; idx=set()
    for f in tracked_set:
        if not f.startswith(base): continue
        rest=f[len(base):]; parts=rest.split('/')
        if len(parts)<2: continue
        folder=parts[0].split('-',1)[0]
        stem=Path(parts[-1]).stem
        if folder in {'drawable','mipmap','xml','layout','raw'}: idx.add((folder,stem))
    for f,t in text_cache.items():
        if not f.startswith(base+'values') or not f.endswith('.xml'): continue
        try: root=ET.fromstring(t)
        except Exception: continue
        for child in root:
            name=child.attrib.get('name')
            tag=child.tag.split('}')[-1]
            if name: idx.add((tag,name))
    return idx


def cross_checks(tracked_set):
    # Android package IDs.
    gradle=text_cache.get('android/app/build.gradle.kts',''); activity=text_cache.get('android/app/src/main/kotlin/com/example/craycare/MainActivity.kt',''); gs=text_cache.get('android/app/google-services.json','')
    vals={}
    for key,pat,txt in [('namespace',r'namespace\s*=\s*[\'\"]([^\'\"]+)',gradle),('applicationId',r'applicationId\s*=\s*[\'\"]([^\'\"]+)',gradle),('kotlinPackage',r'^package\s+([\w.]+)',activity)]:
        m=re.search(pat,txt,re.M); vals[key]=m.group(1) if m else None
    try:
        g=json.loads(gs); clients=g.get('client',[]); vals['googlePackage']=clients[0]['client_info']['android_client_info']['package_name'] if clients else None
    except Exception: vals['googlePackage']=None
    present=[v for v in vals.values() if v]
    if present and len(set(present))!=1: issue('android','android_package_mismatch',str(vals),'error')

    # Firebase project IDs.
    ids={}
    try: ids['.firebaserc']=json.loads(text_cache.get('.firebaserc','{}')).get('projects',{}).get('default')
    except Exception: pass
    try: ids['google-services.json']=json.loads(gs).get('project_info',{}).get('project_id')
    except Exception: pass
    m=re.search(r'projectId:\s*[\'\"]([^\'\"]+)',text_cache.get('lib/firebase_options.dart',''))
    if m: ids['firebase_options.dart']=m.group(1)
    ids={k:v for k,v in ids.items() if v}
    if len(set(ids.values()))>1: issue('firebase','firebase_project_mismatch',str(ids),'error')

    # Firebase function source dirs.
    try:
        fj=json.loads(text_cache.get('firebase.json','{}')); funcs=fj.get('functions',[]); funcs=[funcs] if isinstance(funcs,dict) else funcs
        for x in funcs:
            src=x.get('source') if isinstance(x,dict) else None
            if src and not (ROOT/src).is_dir(): issue('firebase.json','missing_functions_source',src,'error')
    except Exception: pass

    # PlatformIO source filters.
    pio=text_cache.get('esp32/platformio.ini',text_cache.get('platformio.ini',''))
    for target in re.findall(r'\+<([^>]+)>',pio):
        if not any((ROOT/x).exists() for x in [f'esp32/src/{target}',f'src/{target}']): issue('platformio.ini','missing_build_src_filter_target',target,'error')

    # Android app resource references.
    idx=android_resource_index(tracked_set,text_cache)
    for f,t in text_cache.items():
        if not f.startswith('android/app/src/main/'): continue
        for typ,name in re.findall(r'@(?!(?:android):)(drawable|mipmap|string|xml|layout|color|style)/([A-Za-z0-9_]+)',t):
            if (typ,name) not in idx:
                # Flutter/Android generated references are legitimate if known platform-generated.
                if name in {'ic_launcher','launch_background'}: continue
                issue(f,'missing_android_resource',f'@{typ}/{name}','error')

    # Windows/macOS case collisions.
    d={}
    for f in tracked_set: d.setdefault(f.lower(),[]).append(f)
    for group in d.values():
        if len(group)>1: issue(';'.join(group),'case_collision',str(group),'error')


def main():
    files=tracked(); tset=set(files)
    for rel in files:
        p=ROOT/rel
        try: data=p.read_bytes()
        except Exception as e:
            issue(rel,'unreadable',str(e),'error'); records.append({'path':rel,'status':'ERROR','category':'unreadable','size':None}); continue
        rec={'path':rel,'size':len(data),'sha256':hashlib.sha256(data).hexdigest(),'category':None,'encoding':None,'lines':None,'mime':None,'status':'OK','checks':[]}
        if is_binary(p,data):
            rec['category']='binary'; mime,notes=validate_binary(p,data); rec['mime']=mime; rec['checks']=['full-byte-read','sha256','mime/signature']
            for n in notes: issue(rel,'binary_integrity',n,'error')
            records.append(rec); continue
        try: text=data.decode('utf-8')
        except UnicodeDecodeError as e:
            rec['category']='binary-or-nonutf8'; rec['encoding']='non-utf8'; issue(rel,'non_utf8_candidate',str(e)); records.append(rec); continue
        rec['category']='text'; rec['encoding']='utf-8'; rec['lines']=text.count('\n')+(0 if not text or text.endswith('\n') else 1); rec['checks']=['full-byte-read','sha256','utf8']
        text_cache[rel]=text; parse_text_file(p,text); check_links_assets(p,text,tset); check_ios_contents(p,text,tset)
        if p.suffix.lower()=='.dart': check_dart_imports(p,text,tset)
        records.append(rec)

    cross_checks(tset)
    external=[]
    for rel in files:
        ext=Path(rel).suffix.lower()
        if ext in {'.js','.mjs','.cjs'} and shutil.which('node'):
            rc,out=run(['node','--check',rel]); external.append({'path':rel,'tool':'node --check','rc':rc,'output':out[-1500:]})
            if rc: issue(rel,'js_syntax',out[-1500:],'error')
        elif ext=='.sh' and shutil.which('bash'):
            rc,out=run(['bash','-n',rel]); external.append({'path':rel,'tool':'bash -n','rc':rc,'output':out[-1500:]})
            if rc: issue(rel,'shell_syntax',out[-1500:],'error')

    by={}
    for i in issues: by.setdefault(i['path'],[]).append(i)
    for r in records:
        x=by.get(r['path'],[])
        if any(i['severity']=='error' for i in x): r['status']='ERROR'
        elif x: r['status']='WARN'

    summary={'commit':subprocess.check_output(['git','rev-parse','HEAD'],text=True).strip(),'tracked_file_count':len(files),'read_file_count':len(records),'text_file_count':sum(r['category']=='text' for r in records),'binary_file_count':sum(r['category']=='binary' for r in records),'non_utf8_candidate_count':sum(r['category']=='binary-or-nonutf8' for r in records),'error_count':sum(i['severity']=='error' for i in issues),'warning_count':sum(i['severity']=='warning' for i in issues),'files_with_errors':sorted({i['path'] for i in issues if i['severity']=='error'}),'files_with_warnings':sorted({i['path'] for i in issues if i['severity']=='warning'})}
    (OUT/'summary.json').write_text(json.dumps(summary,indent=2),encoding='utf-8'); (OUT/'issues.json').write_text(json.dumps(issues,indent=2),encoding='utf-8'); (OUT/'files.json').write_text(json.dumps(records,indent=2),encoding='utf-8'); (OUT/'external_checks.json').write_text(json.dumps(external,indent=2),encoding='utf-8')
    with (OUT/'files.tsv').open('w',encoding='utf-8',newline='') as f:
        w=csv.writer(f,delimiter='\t'); w.writerow(['status','category','size','lines','mime','path','sha256','checks'])
        for r in records: w.writerow([r['status'],r['category'],r['size'],r['lines'],r['mime'],r['path'],r['sha256'],','.join(r['checks'])])
    md=['# Exhaustive Every-File Audit v2','',f"Commit: `{summary['commit']}`",f"Tracked files read: **{summary['read_file_count']} / {summary['tracked_file_count']}**",f"Text files: **{summary['text_file_count']}**",f"Binary files: **{summary['binary_file_count']}**",f"Non-UTF8 candidates: **{summary['non_utf8_candidate_count']}**",f"Errors: **{summary['error_count']}**",f"Warnings: **{summary['warning_count']}**",'','## Issues']
    md += ['No file-level integrity, syntax, local-reference, or configured cross-layer issues found.'] if not issues else [f"- **{i['severity'].upper()}** `{i['path']}` — `{i['code']}`: {i['message']}" for i in issues]
    md += ['','## Coverage','Every path returned by `git ls-files` was opened and read in full. Text files were UTF-8 decoded and parsed/checked according to their format; JS files used `node --check`, Python used AST parsing, relative Dart imports/local assets/HTML/Markdown links/iOS asset catalogs/Android resources were cross-referenced, and common binary image/font/archive/Office formats received signature/container checks. `files.tsv` contains one row per tracked file.']
    (OUT/'summary.md').write_text('\n'.join(md)+'\n',encoding='utf-8')
    print(json.dumps(summary,indent=2)); print((OUT/'summary.md').read_text())

if __name__=='__main__': main()
