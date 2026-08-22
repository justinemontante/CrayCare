from __future__ import annotations

import ast
import csv
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import tomllib
import xml.etree.ElementTree as ET
import zipfile
import zlib
from pathlib import Path, PurePosixPath

ROOT = Path.cwd()
REPORT_DIR = ROOT / "audit_every_file_output"
REPORT_DIR.mkdir(exist_ok=True)

BINARY_EXTS = {
    ".png", ".jpg", ".jpeg", ".gif", ".webp", ".ico", ".ttf", ".otf", ".woff", ".woff2",
    ".jar", ".zip", ".apk", ".aab", ".keystore", ".jks", ".pdf", ".bin", ".so", ".dll", ".exe",
}
TEXT_CODE_EXTS = {
    ".dart", ".py", ".js", ".mjs", ".cjs", ".ts", ".tsx", ".jsx", ".kt", ".kts", ".java",
    ".cpp", ".cc", ".c", ".h", ".hpp", ".ino", ".sh", ".ps1", ".gradle",
}
STRUCTURED_EXTS = {".json", ".xml", ".yaml", ".yml", ".toml", ".csv"}

records: list[dict] = []
issues: list[dict] = []
text_cache: dict[str, str] = {}


def add_issue(path: str, code: str, message: str, severity: str = "warning") -> None:
    issues.append({"path": path, "code": code, "severity": severity, "message": message})


def run(cmd: list[str], cwd: Path | None = None) -> tuple[int, str]:
    try:
        p = subprocess.run(cmd, cwd=cwd or ROOT, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=180)
        return p.returncode, p.stdout.strip()
    except Exception as e:
        return 999, f"{type(e).__name__}: {e}"


def tracked_files() -> list[str]:
    raw = subprocess.check_output(["git", "ls-files", "-z"])
    return sorted(x.decode("utf-8", "surrogateescape") for x in raw.split(b"\0") if x)


def has_nul(data: bytes) -> bool:
    return b"\x00" in data[:8192]


def is_probably_binary(path: Path, data: bytes) -> bool:
    return path.suffix.lower() in BINARY_EXTS or has_nul(data)


def validate_png(data: bytes) -> str | None:
    sig = b"\x89PNG\r\n\x1a\n"
    if not data.startswith(sig):
        return "invalid PNG signature"
    pos = 8
    seen_iend = False
    while pos + 12 <= len(data):
        length = int.from_bytes(data[pos:pos+4], "big")
        ctype = data[pos+4:pos+8]
        end = pos + 12 + length
        if end > len(data):
            return "truncated PNG chunk"
        payload = data[pos+8:pos+8+length]
        expected = int.from_bytes(data[pos+8+length:pos+12+length], "big")
        actual = zlib.crc32(ctype)
        actual = zlib.crc32(payload, actual) & 0xFFFFFFFF
        if actual != expected:
            return f"PNG CRC mismatch in {ctype.decode('ascii', 'replace')}"
        pos = end
        if ctype == b"IEND":
            seen_iend = True
            break
    if not seen_iend:
        return "PNG missing IEND"
    return None


def validate_binary(path: Path, data: bytes) -> tuple[str, list[str]]:
    ext = path.suffix.lower()
    notes: list[str] = []
    mime = "unknown"
    if shutil.which("file"):
        rc, out = run(["file", "-b", "--mime-type", str(path)])
        if rc == 0:
            mime = out
    if ext == ".png":
        err = validate_png(data)
        if err:
            notes.append(err)
    elif ext in {".jpg", ".jpeg"}:
        if not (data.startswith(b"\xff\xd8") and data.rstrip().endswith(b"\xff\xd9")):
            notes.append("invalid or truncated JPEG markers")
    elif ext == ".gif":
        if not (data.startswith(b"GIF87a") or data.startswith(b"GIF89a")):
            notes.append("invalid GIF signature")
    elif ext == ".webp":
        if not (len(data) >= 12 and data[:4] == b"RIFF" and data[8:12] == b"WEBP"):
            notes.append("invalid WEBP signature")
    elif ext == ".ico":
        if not data.startswith(b"\x00\x00\x01\x00"):
            notes.append("invalid ICO signature")
    elif ext in {".ttf", ".otf"}:
        if data[:4] not in {b"\x00\x01\x00\x00", b"OTTO", b"ttcf", b"true"}:
            notes.append("unrecognized font signature")
    elif ext in {".zip", ".jar"}:
        try:
            with zipfile.ZipFile(path) as zf:
                bad = zf.testzip()
                if bad:
                    notes.append(f"corrupt ZIP member: {bad}")
        except Exception as e:
            notes.append(f"invalid ZIP/JAR: {e}")
    return mime, notes


def strip_strings_comments(text: str, language: str) -> str:
    # Conservative lexer used only for delimiter sanity; not a compiler.
    out = []
    i = 0
    n = len(text)
    in_line = False
    in_block = False
    quote: str | None = None
    triple = False
    while i < n:
        c = text[i]
        nxt = text[i+1] if i + 1 < n else ""
        if in_line:
            if c == "\n":
                in_line = False
                out.append("\n")
            else:
                out.append(" ")
            i += 1
            continue
        if in_block:
            if c == "*" and nxt == "/":
                out.extend("  ")
                i += 2
                in_block = False
            else:
                out.append("\n" if c == "\n" else " ")
                i += 1
            continue
        if quote is not None:
            if triple and text[i:i+3] == quote * 3:
                out.extend("   ")
                i += 3
                quote = None
                triple = False
            elif not triple and c == "\\":
                out.extend("  ")
                i += 2
            elif not triple and c == quote:
                out.append(" ")
                i += 1
                quote = None
            else:
                out.append("\n" if c == "\n" else " ")
                i += 1
            continue
        if c == "/" and nxt == "/":
            out.extend("  ")
            i += 2
            in_line = True
            continue
        if c == "/" and nxt == "*":
            out.extend("  ")
            i += 2
            in_block = True
            continue
        if language == "py" and c == "#":
            out.append(" ")
            i += 1
            in_line = True
            continue
        if c in {"'", '"'}:
            if text[i:i+3] == c * 3:
                out.extend("   ")
                i += 3
                quote = c
                triple = True
            else:
                out.append(" ")
                i += 1
                quote = c
            continue
        out.append(c)
        i += 1
    return "".join(out)


def delimiter_error(text: str, ext: str) -> str | None:
    lang = "py" if ext == ".py" else "other"
    clean = strip_strings_comments(text, lang)
    pairs = {")": "(", "]": "[", "}": "{"}
    stack: list[tuple[str, int]] = []
    for idx, c in enumerate(clean):
        if c in "([{":
            stack.append((c, idx))
        elif c in ")]}":
            if not stack or stack[-1][0] != pairs[c]:
                return f"unbalanced delimiter {c!r} at character {idx}"
            stack.pop()
    if stack:
        return f"unclosed delimiter {stack[-1][0]!r} at character {stack[-1][1]}"
    return None


def parse_structured(path: Path, text: str) -> None:
    ext = path.suffix.lower()
    try:
        if ext == ".json":
            json.loads(text)
        elif ext == ".xml":
            ET.fromstring(text)
        elif ext == ".toml":
            tomllib.loads(text)
        elif ext == ".csv":
            list(csv.reader(text.splitlines()))
        elif ext in {".yaml", ".yml"}:
            try:
                import yaml  # type: ignore
                yaml.safe_load(text)
            except ImportError:
                # YAML parser is optional; workflow installs PyYAML when available.
                pass
    except Exception as e:
        add_issue(path.as_posix(), "parse_error", f"{ext} parse failed: {e}", "error")


def check_markdown_links(path: Path, text: str, tracked_set: set[str]) -> None:
    for target in re.findall(r"\[[^\]]*\]\(([^)]+)\)", text):
        target = target.strip().split()[0].strip("<>")
        if not target or target.startswith(("http://", "https://", "mailto:", "#")):
            continue
        target = target.split("#", 1)[0]
        if not target:
            continue
        resolved = (path.parent / target).resolve()
        try:
            rel = resolved.relative_to(ROOT.resolve()).as_posix()
        except ValueError:
            continue
        if rel not in tracked_set and not (ROOT / rel).exists():
            add_issue(path.as_posix(), "broken_relative_link", f"Markdown target does not exist: {target}")


def check_relative_dart_imports(path: Path, text: str, tracked_set: set[str]) -> None:
    for spec in re.findall(r"(?:import|export|part)\s+['\"]([^'\"]+)['\"]", text):
        if spec.startswith(("dart:", "package:")):
            continue
        resolved = (path.parent / spec).resolve()
        try:
            rel = resolved.relative_to(ROOT.resolve()).as_posix()
        except ValueError:
            add_issue(path.as_posix(), "outside_repo_import", f"Relative Dart import escapes repository: {spec}", "error")
            continue
        if rel not in tracked_set:
            add_issue(path.as_posix(), "missing_dart_import", f"Missing relative Dart import/export/part: {spec}", "error")


def check_asset_references(path: Path, text: str, tracked_set: set[str]) -> None:
    patterns = [
        r"['\"](assets/[^'\"\n]+)['\"]",
        r"asset:\s*([^\s#]+)",
        r"image_path:\s*([^\s#]+)",
        r"adaptive_icon_foreground:\s*([^\s#]+)",
    ]
    seen: set[str] = set()
    for pat in patterns:
        for raw in re.findall(pat, text):
            asset = raw.strip().strip("'\"")
            if not asset.startswith("assets/") or asset in seen:
                continue
            seen.add(asset)
            if asset.endswith("/"):
                if not any(x.startswith(asset) for x in tracked_set):
                    add_issue(path.as_posix(), "missing_asset_directory", f"Referenced asset directory missing: {asset}", "error")
            elif asset not in tracked_set:
                add_issue(path.as_posix(), "missing_asset", f"Referenced asset missing (case-sensitive): {asset}", "error")


def check_generic_text(path: Path, text: str) -> None:
    if re.search(r"^<<<<<<< |^=======\s*$|^>>>>>>> ", text, flags=re.M):
        add_issue(path.as_posix(), "merge_conflict_marker", "Unresolved git merge-conflict marker", "error")
    if "\x00" in text:
        add_issue(path.as_posix(), "nul_in_text", "NUL byte decoded in text file", "error")
    if path.suffix.lower() in TEXT_CODE_EXTS:
        err = delimiter_error(text, path.suffix.lower())
        if err:
            add_issue(path.as_posix(), "delimiter_balance", err, "error")


def semantic_cross_checks(tracked_set: set[str]) -> None:
    # Android namespace/applicationId/Kotlin package/Firebase Android registration.
    gradle = text_cache.get("android/app/build.gradle.kts", "")
    main_activity = text_cache.get("android/app/src/main/kotlin/com/example/craycare/MainActivity.kt", "")
    google = text_cache.get("android/app/google-services.json", "")
    ns = re.search(r"namespace\s*=\s*['\"]([^'\"]+)", gradle)
    appid = re.search(r"applicationId\s*=\s*['\"]([^'\"]+)", gradle)
    pkg = re.search(r"^package\s+([\w.]+)", main_activity, re.M)
    try:
        gobj = json.loads(google) if google else {}
        clients = gobj.get("client", [])
        gpkg = clients[0].get("client_info", {}).get("android_client_info", {}).get("package_name") if clients else None
    except Exception:
        gpkg = None
    values = {"namespace": ns.group(1) if ns else None, "applicationId": appid.group(1) if appid else None, "kotlinPackage": pkg.group(1) if pkg else None, "googlePackage": gpkg}
    nonempty = [v for v in values.values() if v]
    if nonempty and len(set(nonempty)) != 1:
        add_issue("android", "android_package_mismatch", f"Android package identifiers disagree: {values}", "error")

    # Firebase project IDs across common configs.
    firebaserc = text_cache.get(".firebaserc", "")
    firebase_options = text_cache.get("lib/firebase_options.dart", "")
    ids: dict[str, str] = {}
    try:
        f = json.loads(firebaserc) if firebaserc else {}
        if f.get("projects", {}).get("default"):
            ids[".firebaserc"] = f["projects"]["default"]
    except Exception:
        pass
    try:
        g = json.loads(google) if google else {}
        pid = g.get("project_info", {}).get("project_id")
        if pid:
            ids["google-services.json"] = pid
    except Exception:
        pass
    m = re.search(r"projectId:\s*['\"]([^'\"]+)", firebase_options)
    if m:
        ids["firebase_options.dart"] = m.group(1)
    if len(set(ids.values())) > 1:
        add_issue("firebase", "firebase_project_mismatch", f"Firebase project IDs disagree: {ids}", "error")

    # firebase.json function source folders.
    fjson = text_cache.get("firebase.json", "")
    try:
        obj = json.loads(fjson) if fjson else {}
        funcs = obj.get("functions", [])
        if isinstance(funcs, dict):
            funcs = [funcs]
        for item in funcs:
            src = item.get("source") if isinstance(item, dict) else None
            if src and not (ROOT / src).is_dir():
                add_issue("firebase.json", "missing_functions_source", f"Function source directory missing: {src}", "error")
    except Exception:
        pass

    # PlatformIO production source filter targets must exist.
    pio = text_cache.get("esp32/platformio.ini", text_cache.get("platformio.ini", ""))
    for target in re.findall(r"\+<([^>]+)>", pio):
        candidates = [ROOT / "esp32" / "src" / target, ROOT / "src" / target]
        if not any(c.exists() for c in candidates):
            add_issue("platformio.ini", "missing_build_src_filter_target", f"build_src_filter target not found: {target}", "error")

    # Case-insensitive path collisions are dangerous on Windows/macOS.
    lower: dict[str, list[str]] = {}
    for p in tracked_set:
        lower.setdefault(p.lower(), []).append(p)
    for group in lower.values():
        if len(group) > 1:
            add_issue(";".join(group), "case_collision", f"Paths collide case-insensitively: {group}", "error")


def main() -> int:
    files = tracked_files()
    tracked_set = set(files)

    # Every tracked path is explicitly read here. No glob-based skipping.
    for rel in files:
        p = ROOT / rel
        try:
            data = p.read_bytes()
        except Exception as e:
            add_issue(rel, "unreadable_file", f"Could not read tracked file: {e}", "error")
            records.append({"path": rel, "status": "ERROR", "category": "unreadable", "size": None})
            continue

        rec = {
            "path": rel,
            "size": len(data),
            "sha256": hashlib.sha256(data).hexdigest(),
            "category": None,
            "encoding": None,
            "lines": None,
            "mime": None,
            "status": "OK",
            "checks": [],
        }

        if is_probably_binary(p, data):
            rec["category"] = "binary"
            mime, notes = validate_binary(p, data)
            rec["mime"] = mime
            rec["checks"].append("binary-readable")
            if p.suffix.lower() in {".png", ".jpg", ".jpeg", ".gif", ".webp", ".ico", ".ttf", ".otf", ".zip", ".jar"}:
                rec["checks"].append("signature/container")
            for note in notes:
                add_issue(rel, "binary_integrity", note, "error")
            records.append(rec)
            continue

        try:
            text = data.decode("utf-8")
            rec["encoding"] = "utf-8"
        except UnicodeDecodeError as e:
            rec["category"] = "binary-or-nonutf8"
            rec["encoding"] = "non-utf8"
            mime = "unknown"
            if shutil.which("file"):
                rc, out = run(["file", "-b", "--mime-type", str(p)])
                if rc == 0:
                    mime = out
            rec["mime"] = mime
            add_issue(rel, "non_utf8_text_candidate", f"Non-binary-extension file is not UTF-8: {e}")
            records.append(rec)
            continue

        text_cache[rel] = text
        rec["category"] = "text"
        rec["lines"] = 0 if not text else text.count("\n") + (0 if text.endswith("\n") else 1)
        rec["checks"].append("utf8-readable")
        check_generic_text(p, text)

        ext = p.suffix.lower()
        if ext in STRUCTURED_EXTS:
            parse_structured(p, text)
            rec["checks"].append(f"{ext[1:]}-parse")
        if ext == ".py":
            try:
                ast.parse(text, filename=rel)
                rec["checks"].append("python-ast")
            except SyntaxError as e:
                add_issue(rel, "python_syntax", f"Python syntax error: {e}", "error")
        if ext == ".dart":
            check_relative_dart_imports(p, text, tracked_set)
            rec["checks"].append("dart-relative-imports")
        if ext == ".md":
            check_markdown_links(p, text, tracked_set)
            rec["checks"].append("markdown-relative-links")
        check_asset_references(p, text, tracked_set)
        rec["checks"].append("asset-references")
        records.append(rec)

    semantic_cross_checks(tracked_set)

    # External syntax validators run over all matching tracked files.
    external_checks: list[dict] = []
    for rel in files:
        ext = Path(rel).suffix.lower()
        if ext in {".js", ".mjs", ".cjs"} and shutil.which("node"):
            rc, out = run(["node", "--check", rel])
            external_checks.append({"path": rel, "tool": "node --check", "rc": rc, "output": out[-2000:]})
            if rc != 0:
                add_issue(rel, "js_syntax", out[-2000:], "error")
        elif ext == ".sh" and shutil.which("bash"):
            rc, out = run(["bash", "-n", rel])
            external_checks.append({"path": rel, "tool": "bash -n", "rc": rc, "output": out[-2000:]})
            if rc != 0:
                add_issue(rel, "shell_syntax", out[-2000:], "error")

    # Whole-repository checks.
    rc, out = run(["git", "diff", "--check", "HEAD"])
    external_checks.append({"path": "<repo>", "tool": "git diff --check", "rc": rc, "output": out})
    rc2, out2 = run(["git", "status", "--porcelain"])
    external_checks.append({"path": "<repo>", "tool": "git status --porcelain", "rc": rc2, "output": out2})

    # Attach issue counts back to per-file records.
    by_path: dict[str, list[dict]] = {}
    for issue in issues:
        by_path.setdefault(issue["path"], []).append(issue)
    for rec in records:
        related = by_path.get(rec["path"], [])
        if any(i["severity"] == "error" for i in related):
            rec["status"] = "ERROR"
        elif related:
            rec["status"] = "WARN"

    summary = {
        "commit": subprocess.check_output(["git", "rev-parse", "HEAD"], text=True).strip(),
        "tracked_file_count": len(files),
        "text_file_count": sum(r["category"] == "text" for r in records),
        "binary_file_count": sum(r["category"] == "binary" for r in records),
        "non_utf8_candidate_count": sum(r["category"] == "binary-or-nonutf8" for r in records),
        "error_count": sum(i["severity"] == "error" for i in issues),
        "warning_count": sum(i["severity"] == "warning" for i in issues),
        "files_with_errors": sorted({i["path"] for i in issues if i["severity"] == "error"}),
        "files_with_warnings": sorted({i["path"] for i in issues if i["severity"] == "warning"}),
    }

    (REPORT_DIR / "summary.json").write_text(json.dumps(summary, indent=2, ensure_ascii=False), encoding="utf-8")
    (REPORT_DIR / "issues.json").write_text(json.dumps(issues, indent=2, ensure_ascii=False), encoding="utf-8")
    (REPORT_DIR / "files.json").write_text(json.dumps(records, indent=2, ensure_ascii=False), encoding="utf-8")
    (REPORT_DIR / "external_checks.json").write_text(json.dumps(external_checks, indent=2, ensure_ascii=False), encoding="utf-8")

    with (REPORT_DIR / "files.tsv").open("w", encoding="utf-8", newline="") as f:
        w = csv.writer(f, delimiter="\t")
        w.writerow(["status", "category", "size", "lines", "mime", "path", "sha256", "checks"])
        for r in records:
            w.writerow([r["status"], r["category"], r["size"], r["lines"], r["mime"], r["path"], r["sha256"], ",".join(r["checks"])])

    md = [
        "# Exhaustive Every-File Audit",
        "",
        f"Commit: `{summary['commit']}`",
        f"Tracked files read: **{summary['tracked_file_count']} / {summary['tracked_file_count']}**",
        f"Text files: **{summary['text_file_count']}**",
        f"Binary files: **{summary['binary_file_count']}**",
        f"Non-UTF8 candidates: **{summary['non_utf8_candidate_count']}**",
        f"Errors: **{summary['error_count']}**",
        f"Warnings: **{summary['warning_count']}**",
        "",
        "## Issues",
    ]
    if not issues:
        md.append("No automated file-level integrity or cross-reference issues found.")
    else:
        for i in issues:
            md.append(f"- **{i['severity'].upper()}** `{i['path']}` — `{i['code']}`: {i['message']}")
    md += ["", "## Coverage", "", "Every path returned by `git ls-files` was opened and read as bytes. Text files were UTF-8 decoded and subjected to extension-specific parsing/syntax/reference checks. Binary files were read in full, hashed, MIME-classified, and common image/font/archive signatures or containers were validated. See `files.tsv` for one row per tracked file."]
    (REPORT_DIR / "summary.md").write_text("\n".join(md) + "\n", encoding="utf-8")

    print(json.dumps(summary, indent=2))
    print(f"AUDIT_REPORT_DIR={REPORT_DIR}")
    # Do not fail on audit findings; artifact must still upload for review.
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
