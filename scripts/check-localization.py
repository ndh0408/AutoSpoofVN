"""Kiem tra ban dia hoa cua LocationX.

Chay: python3 scripts/check-localization.py

Bao loi (exit 1) khi:
  - mot khoa L("...") duoc goi trong ma nguon nhung thieu o vi.lproj hoac en.lproj
    (luc chay app se hien ra chinh chuoi khoa, vi du "route.detail.title")
  - hai ngon ngu lech dinh dang %d/%@ cho cung mot khoa
    (day la loi CRASH that: String(format:) se doc tham so khong ton tai tren stack)
  - mot khoa duoc dinh nghia hai lan voi hai gia tri khac nhau
"""
import re, glob, os, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# Gia tri co the XUONG DONG nhieu dong (huong dan nhieu buoc), nen phai quet ca file
# voi DOTALL chu khong doc tung dong. Ban truoc doc tung dong nen bao thieu nham 3 khoa
# von van ton tai.
ENTRY = re.compile(r'"((?:[^"\\]|\\.)*)"\s*=\s*"((?:[^"\\]|\\.)*)"\s*;', re.DOTALL)

def parse_strings(path):
    d = {}
    dupes = []
    if not os.path.exists(path):
        return d, dupes
    src = open(path, encoding="utf-8").read()
    for m in ENTRY.finditer(src):
        k, v = m.group(1), m.group(2)
        if k in d and d[k] != v:
            dupes.append(k)
        d[k] = v
    return d, dupes

vi, vi_dupes = parse_strings(os.path.join(ROOT, "LocationX/Resources/vi.lproj/Localizable.strings"))
en, en_dupes = parse_strings(os.path.join(ROOT, "LocationX/Resources/en.lproj/Localizable.strings"))

used = {}
for f in glob.glob(os.path.join(ROOT, "LocationX/**/*.swift"), recursive=True):
    src = open(f, encoding="utf-8").read()
    for m in re.finditer(r'\bL\(\s*"([^"]+)"', src):
        used.setdefault(m.group(1), []).append(os.path.relpath(f, ROOT))

print(f"khoa duoc goi trong ma nguon : {len(used)}")
print(f"khoa trong vi.lproj          : {len(vi)}")
print(f"khoa trong en.lproj          : {len(en)}")

missing_vi = sorted(set(used) - set(vi))
missing_en = sorted(set(used) - set(en))
print(f"\nTHIEU o vi.lproj: {len(missing_vi)}")
for k in missing_vi[:40]:
    print(f"   {k}   <- {used[k][0]}")
print(f"\nTHIEU o en.lproj: {len(missing_en)}")
for k in missing_en[:40]:
    print(f"   {k}   <- {used[k][0]}")

only_vi = sorted(set(vi) - set(en))
only_en = sorted(set(en) - set(vi))
print(f"\nLECH giua hai ngon ngu: chi-vi={len(only_vi)} chi-en={len(only_en)}")
for k in (only_vi + only_en)[:20]:
    print("   ", k)

def specs(t):
    cleaned = t.replace("%%", "")
    return sorted(re.findall(r"%[0-9.$]*[@dfsxu]", cleaned))

mismatch = [(k, specs(vi[k]), specs(en[k])) for k in vi if k in en and specs(vi[k]) != specs(en[k])]
print(f"\nLECH dinh dang %: {len(mismatch)}")
for k, a, b in mismatch[:20]:
    print(f"   {k}: vi={a} en={b}")

if vi_dupes or en_dupes:
    print(f"\nKHOA TRUNG khac gia tri: vi={sorted(set(vi_dupes))[:10]} en={sorted(set(en_dupes))[:10]}")

bad = len(missing_vi) + len(missing_en) + len(mismatch)
print("\n" + ("KET LUAN: SACH" if bad == 0 else f"KET LUAN: {bad} van de can sua"))
sys.exit(1 if bad else 0)
