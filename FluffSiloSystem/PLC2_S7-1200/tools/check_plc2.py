"""Consistency checks for PLC2_S7-1200 against FluffSiloHMI2 (stdlib only)."""
import re, sys, os, glob

root = sys.argv[1]
plc = os.path.join(root, 'PLC2_S7-1200')
ok = True
def fail(m):
    global ok; ok = False; print('FAIL', m)

tags = {}
for line in open(os.path.join(plc, '01_PLC_Tags.csv'), encoding='utf-8').read().splitlines()[1:]:
    if line.strip():
        p = line.split(';'); tags[p[0]] = (p[2], p[3])
addrs = [a for _, a in tags.values()]
if len(set(addrs)) != len(addrs): fail('duplicate address in tag table')

src = {os.path.basename(f): open(f, encoding='utf-8').read() for f in sorted(glob.glob(os.path.join(plc, '*.scl')))}
def strip(s):
    s = re.sub(r'\(\*.*?\*\)', '', s, flags=re.S)
    s = re.sub(r"'[^']*'", "''", s)
    return re.sub(r'//[^\n]*', '', s)

blocks = {}
for fn, s in src.items():
    for kind, name in re.findall(r'^(TYPE|DATA_BLOCK|FUNCTION_BLOCK|FUNCTION|ORGANIZATION_BLOCK)\s+"([^"]+)"', s, re.M):
        blocks[name] = (kind, fn)
print('blocks:', len(blocks), sorted(blocks))

# ---------- 1. symbols ----------
used = set()
for fn, s in src.items():
    for sym in re.findall(r'"([^"]+)"', strip(s)):
        used.add(sym)
        if sym not in tags and sym not in blocks:
            fail(f'{fn}: unknown symbol "{sym}"')
unused = [t for t in tags if t not in used]
if unused: fail(f'unused tags {unused}')
print('symbols ok, tags used:', len(tags) - len(unused), '/', len(tags))

# ---------- 2. keyword balance ----------
pairs = [('TYPE', 'END_TYPE'), ('DATA_BLOCK', 'END_DATA_BLOCK'), ('FUNCTION_BLOCK', 'END_FUNCTION_BLOCK'),
         ('FUNCTION', 'END_FUNCTION'), ('ORGANIZATION_BLOCK', 'END_ORGANIZATION_BLOCK'),
         ('IF', 'END_IF'), ('CASE', 'END_CASE'), ('FOR', 'END_FOR'), ('WHILE', 'END_WHILE'),
         ('REPEAT', 'END_REPEAT'), ('STRUCT', 'END_STRUCT'), ('REGION', 'END_REGION')]
for fn, s in src.items():
    t = strip(s)
    for a, b in pairs:
        fl = re.I if a == 'STRUCT' else 0
        na = len(re.findall(r'(?<![\w])' + a + r'(?![\w])', t, fl))
        nb = len(re.findall(r'(?<![\w])' + b + r'(?![\w])', t, fl))
        if na != nb: fail(f'{fn}: {a}={na} {b}={nb}')
    nv = len(re.findall(r'(?<![\w])VAR(_INPUT|_OUTPUT|_IN_OUT|_TEMP|_STAT)?(?![\w])', t))
    ne = len(re.findall(r'(?<![\w])END_VAR(?![\w])', t))
    if nv != ne: fail(f'{fn}: VAR={nv} END_VAR={ne}')
    if t.count('(') != t.count(')'): fail(f'{fn}: parentheses ( {t.count("(")} ) {t.count(")")}')
print('keywords balanced')

# ---------- 3. standard-access layout ----------
SIZES = {'Bool': None, 'Byte': 1, 'Char': 1, 'Int': 2, 'Word': 2, 'UInt': 2, 'DInt': 4, 'DWord': 4,
         'Real': 4, 'Time': 4}

def parse_members(body):
    """returns list of (name, typ) where typ is str, ('struct', members) or ('array', lo, hi, typ)"""
    toks = re.findall(r'\w+|"[^"]+"|\.\.|[:;\[\],]', body)
    pos = 0
    def parse_type():
        nonlocal pos
        t = toks[pos]; pos += 1
        if t.lower() == 'struct':
            mem = parse_list('END_STRUCT'); pos += 1
            return ('struct', mem)
        if t.lower() == 'array':
            assert toks[pos] == '['; lo = int(toks[pos + 1]); assert toks[pos + 2] == '..'
            hi = int(toks[pos + 3]); assert toks[pos + 4] == ']'; assert toks[pos + 5].lower() == 'of'
            pos += 6
            return ('array', lo, hi, parse_type())
        return t.strip('"')
    def parse_list(end):
        nonlocal pos
        mem = []
        while pos < len(toks) and toks[pos].upper() != end:
            name = toks[pos]; assert toks[pos + 1] == ':', (name, toks[pos + 1]); pos += 2
            typ = parse_type()
            if pos < len(toks) and toks[pos] == ';': pos += 1
            mem.append((name, typ))
        return mem
    return parse_list('#END#')

udts = {}
for fn, s in src.items():
    for name, body in re.findall(r'TYPE\s+"([^"]+)".*?STRUCT(.*?)END_STRUCT;\s*END_TYPE', strip(s), re.S):
        udts[name] = parse_members(body)

class Lay:
    def __init__(self): self.byte = 0; self.bit = 0; self.out = {}
    def align_even(self):
        if self.bit: self.byte += 1; self.bit = 0
        if self.byte % 2: self.byte += 1
    def place(self, path, typ):
        if isinstance(typ, tuple) and typ[0] == 'struct':
            self.align_even(); self.members(path + '.', typ[1]); self.align_even(); return
        if isinstance(typ, tuple) and typ[0] == 'array':
            _, lo, hi, et = typ
            self.align_even()
            for i in range(lo, hi + 1):
                self.place(f'{path}[{i}]', et)
            self.align_even(); return
        if typ in udts:
            self.align_even(); self.members(path + '.', udts[typ]); self.align_even(); return
        if typ == 'Bool':
            self.out[path] = ('X', self.byte, self.bit)
            self.bit += 1
            if self.bit == 8: self.byte += 1; self.bit = 0
            return
        n = SIZES[typ]
        if self.bit: self.byte += 1; self.bit = 0
        if n > 1 and self.byte % 2: self.byte += 1
        self.out[path] = ({1: 'B', 2: 'W', 4: 'D'}[n], self.byte, 0)
        self.byte += n
    def members(self, prefix, mem):
        for name, typ in mem:
            self.place(prefix + name, typ)

def db_layout(fname, dbname):
    s = strip(src[fname])
    m = re.search(r'DATA_BLOCK\s+"' + dbname + r'".*?STRUCT(.*)END_STRUCT;\s*BEGIN', s, re.S)
    lay = Lay(); lay.members('', parse_members(m.group(1))); lay.align_even()
    return lay.out, lay.byte

hmi, size = db_layout('03_DB_HMI.scl', 'DB_HMI')
print('DB_HMI size', size)
if size != 138: fail(f'DB_HMI size {size} != 138')

def fmt(a):
    k, b, bit = a
    return f'DBX{b}.{bit}' if k == 'X' else f'DB{k}{b}'

# header comment ranges
hdr = src['03_DB_HMI.scl']
for m in re.finditer(r'//\s+DB([XWBD])(\d+)(?:\.(\d))?\s', hdr[:hdr.index('DATA_BLOCK')]):
    pass

# ---------- 4. HMI2 default map vs DB_HMI ----------
DEV = ['Blower01', 'Screw01'] + [f'Paddle{k:02d}' for k in range(1, 8)]
PROP = {'AutoStart': 'AutoStart', 'AutoStop': 'AutoStop', 'Interlock': 'Interlock', 'ManualStart': 'ManualStart',
        'ManualStop': 'ManualStop', 'Enable': 'Enable', 'Disable': 'Disable', 'Fault': 'Fault', 'E-Stop': 'EStop',
        'Running': 'Running'}
CMD = ['ManualStart', 'ManualStop', 'ReturnAuto', 'Enable', 'Disable', 'ResetFault']
DELAY = ['BlowerToScrew', 'ReqHold', 'ScrewToPaddle', 'ReqOffScrewStop', 'ScrewTripBlower', 'AutoStopBlower']

def member_for(key):
    p = key.split('.')
    if p[0] in DEV and len(p) == 2: return f'Dev[{DEV.index(p[0])}].{PROP[p[1]]}'
    if p[0] in DEV and p[1] == 'Cmd': return f'DevCmd[{DEV.index(p[0]) * 8 + CMD.index(p[2])}]'
    if p[0] == 'System': return 'Sys.' + p[1]
    if p[0] == 'Cmd': return 'Cmd.' + p[1]
    if p[0] == 'Delay': return f'Delay[{DELAY.index(p[1])}]'
    if key == 'Pattern.CurrentStep': return 'Proc.CurrentStep'
    if key == 'Pattern.StepElapsed': return 'Proc.StepElapsed'
    if key == 'Silo.Level': return 'Proc.SiloLevel'
    if key == 'Config.PaddleCount': return 'Cfg.PaddleCount'
    if key == 'Pattern.StepCount': return 'Pattern.StepCount'
    m = re.match(r'Pattern\.Step(\d\d)\.(Mask|Time)$', key)
    if m:
        return f'Pattern.{"Mask" if m.group(2) == "Mask" else "StepTime"}[{int(m.group(1)) - 1}]'
    return None

csvf = os.path.join(root, 'FluffSiloHMI2', 'docs', 'RegisterMap_Default.csv')
rows = open(csvf, encoding='utf-8').read().splitlines()
hdrc = rows[0].split(';')
ci = {n: i for i, n in enumerate(hdrc)}
n = 0
seen = set()
for r in rows[1:]:
    f = r.split(';')
    key, s7, typ = f[ci['Key']], f[ci['S7Address']], f[ci['Type']]
    mem = member_for(key)
    if mem is None or mem not in hmi:
        fail(f'{key}: no DB_HMI member ({mem})'); continue
    want = 'DB10.' + fmt(hmi[mem])
    if s7 != want: fail(f'{key}: HMI {s7} but DB_HMI.{mem} is {want}')
    if (typ == 'BOOL') != (hmi[mem][0] == 'X'): fail(f'{key}: type {typ} vs {hmi[mem][0]}')
    seen.add(mem)
    n += 1
print(f'HMI2 default map: {n} tags compared with DB_HMI offsets')
spare = [m for m in hmi if m not in seen and 'Spare' not in m and not re.match(r'DevCmd\[\d+\]', m)]
if spare: fail(f'DB_HMI members without HMI tag: {spare}')
devcmd_unused = [m for m in hmi if m.startswith('DevCmd') and m not in seen]
print('DevCmd bits reserved (cmd 6,7 per device):', len(devcmd_unused))

# ---------- 5. FB_FluffSilo wiring ----------
fb = strip(src['12_FB_FluffSilo.scl'])
for d, name in enumerate(DEV):
    m = re.search(r'#' + name + r'\((.*?)\);', fb, re.S)
    if not m: fail(f'no call of {name}'); continue
    call = m.group(1)
    idx = [int(x) for x in re.findall(r'DevCmd\[(\d+)\]', call)]
    if idx != list(range(d * 8, d * 8 + 6)): fail(f'{name}: DevCmd {idx}')
    if f'"{name}_FB"' not in call or f'"{name}_OL"' not in call: fail(f'{name}: I/O tags')
    if d >= 2:
        k = d - 2
        if f'PaddleCmd[{k}]' not in call or f'(#nPad > {k})' not in call: fail(f'{name}: pattern / installed')
    if not re.search(r'"DB_HMI"\.Dev\[' + str(d) + r'\]\s*:=\s*#' + name + r'\.Status', fb): fail(f'{name}: status')
    if not re.search(r'"' + name + r'_Run"\s*:=\s*#' + name + r'\.Run', fb): fail(f'{name}: output')
print('FB_FluffSilo wiring: 9 devices checked')

# ---------- 6. DB_Sim ----------
sim, ssize = db_layout('16_DB_Sim.scl', 'DB_Sim')
print('DB_Sim size', ssize)
hs = src['16_DB_Sim.scl']
head = hs[:hs.index('DATA_BLOCK')]
nh = 0
for m in re.finditer(r'DBX(\d+)\.(\d)\s+(\w+)(?=\s+(?:->|1 =|$))', head, re.M):
    b, bi, name = int(m.group(1)), int(m.group(2)), m.group(3)
    if name == 'Spare': name = 'Spare_2_7'
    nh += 1
    if sim.get(name, (None,))[1:] != (b, bi): fail(f'DB_Sim header {name} DBX{b}.{bi} vs {sim.get(name)}')
for name, a in sim.items():
    m = re.search(r'\b' + name + r'\s*:\s*Bool;\s*//\s*DBX(\d+)\.(\d)', hs)
    if not m or (int(m.group(1)), int(m.group(2))) != a[1:]: fail(f'DB_Sim inline {name}')
print('DB_Sim header entries', nh, 'members', len(sim))
# same prefix as PLC1 DB_Sim
p1 = os.path.join(root, 'PLC_S7-1200', '16_DB_Sim.scl')
if os.path.exists(p1):
    t1 = strip(open(p1, encoding='utf-8').read())
    m1 = re.search(r'STRUCT(.*)END_STRUCT', t1, re.S)
    l1 = Lay(); l1.members('', parse_members(m1.group(1)))
    for name, a in l1.out.items():
        if name.startswith('Spare') or name == 'SimMode': continue
        if sim.get(name) != a: fail(f'DB_Sim {name} differs from PLC1 ({a} vs {sim.get(name)})')
    print('DB_Sim compatible with PLC_S7-1200 DB_Sim for the first', len(l1.out) - 2, 'bits')

fc = strip(src['17_FC_SimInputs.scl'])
assigns = dict(re.findall(r'"(\w+)"\s*:=\s*((?:NOT\s+)?"DB_Sim"\.\w+)', fc))
expect = {'EStop_OK': '"DB_Sim".EStop', 'PB_AutoStart': '"DB_Sim".SelLeft', 'PB_AutoStop': 'NOT "DB_Sim".SelRight',
          'PB_Reset': '"DB_Sim".Reset', 'ExtRequest_In': '"DB_Sim".ExtRequest'}
for name in DEV:
    for x in ('FB', 'OL'): expect[f'{name}_{x}'] = f'"DB_Sim".{name}_{x}'
inputs = [t for t, (ty, a) in tags.items() if a.startswith('%I') and ty == 'Bool']
if sorted(inputs) != sorted(expect): fail(f'input tags {sorted(set(inputs) ^ set(expect))}')
for t, e in expect.items():
    if assigns.get(t) != e: fail(f'FC_SimInputs {t}: {assigns.get(t)}')
print('FC_SimInputs:', len(assigns), 'inputs mapped')

ob1 = strip(src['14_OB1_Main.scl'])
if not (0 <= ob1.find('"FC_SimInputs"()') < ob1.find('"iDB_FluffSilo"()')): fail('OB1 call order')
print('ALL OK' if ok else 'ERRORS')
sys.exit(0 if ok else 1)
