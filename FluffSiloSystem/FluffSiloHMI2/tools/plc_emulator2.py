"""FluffSilo HMI2 PLC emulator - Modbus TCP + Siemens S7 server (Python stdlib only).

Test FluffSilo HMI2 without a real PLC. The register map is read from
docs/RegisterMap_Default.csv (FluffSiloHMI2.exe --export-map), so Modbus and S7 (DB10)
always match the HMI. A simplified copy of the PLC2 program runs inside
(9 devices, 1..7 paddles installed, 20-step Paddle Patterns).

    python -I plc_emulator2.py [--host 127.0.0.1] [--port 5020] [--s7port 102] [--map FILE] [--log]

Then in the HMI2: HW Config -> protocol, IP 127.0.0.1, port 5020 (Modbus) or 102 (S7,
rack 0 / slot 1), Save; data source "PLC"; CONNECT.
"""
import argparse
import csv
import os
import socketserver
import struct
import threading
import time

LOCK = threading.Lock()
LOG = False
V = {}                 # tag key -> raw value (int)
COIL = {}              # modbus coil address -> key
HREG = {}              # modbus holding register -> key
S7BIT = {}             # (byte, bit) in DB10 -> key
S7WORD = {}            # byte offset in DB10 -> key
S7_DB = 10
S7_DB_SIZE = 138
INPUTS = bytearray(64)     # %I  (client panel / test tool)
OUTPUTS = bytearray(64)    # %Q
MERKERS = bytearray(256)
AREA_MEM = {0x81: INPUTS, 0x82: OUTPUTS, 0x83: MERKERS}

DEV = ["Blower01", "Screw01"] + [f"Paddle{k:02d}" for k in range(1, 8)]
PROPS = ["AutoStart", "AutoStop", "Interlock", "ManualStart", "ManualStop", "Enable", "Disable", "Fault",
         "E-Stop", "Running"]
CMDS = ["ManualStart", "ManualStop", "ReturnAuto", "Enable", "Disable", "ResetFault"]
DELAYS = ["BlowerToScrew", "ReqHold", "ScrewToPaddle", "ReqOffScrewStop", "ScrewTripBlower", "AutoStopBlower"]


def load_map(path):
    with open(path, encoding="utf-8") as f:
        for row in csv.DictReader(f, delimiter=";"):
            key = row["Key"]
            V[key] = 0
            addr = int(row["Address"])
            if row["Area"] == "COIL":
                COIL[addr] = key
            elif row["Area"] == "HR":
                HREG[addr] = key
            s7 = row["S7Address"].upper()
            if s7.startswith(f"DB{S7_DB}.DBX"):
                b, bit = s7.split("DBX")[1].split(".")
                S7BIT[(int(b), int(bit))] = key
            elif s7.startswith(f"DB{S7_DB}.DBW"):
                S7WORD[int(s7.split("DBW")[1])] = key
    print(f"map: {len(V)} tags, {len(COIL)} coils, {len(HREG)} registers, DB{S7_DB}: "
          f"{len(S7BIT)} bits + {len(S7WORD)} words", flush=True)


def p(d, prop):
    return f"{DEV[d]}.{PROPS[prop]}"


def init():
    for d in range(len(DEV)):
        V[p(d, 5)] = 1
    for i, v in enumerate([70, 30, 30, 30, 50, 50]):   # delays x0.1 s
        V["Delay." + DELAYS[i]] = v
    V["Config.PaddleCount"] = 7
    pat = []
    for k in range(7):
        pat += [(1 << k, 80), (0, 20)]
    V["Pattern.StepCount"] = len(pat)
    for i in range(20):
        m, t = pat[i] if i < len(pat) else (0, 50)
        V[f"Pattern.Step{i + 1:02d}.Mask"] = m
        V[f"Pattern.Step{i + 1:02d}.Time"] = t
    V["Silo.Level"] = 750


class Plc:
    """Small copy of the PLC2 program (enough to exercise the HMI)."""

    def __init__(self):
        self.auto = False
        self.blower_cmd = self.screw_cmd = False
        self.req_on = self.req_off = 0.0
        self.run_t = [0.0] * len(DEV)
        self.step, self.step_t = 0, 0.0
        self.stop_timer = 0.0
        self.level = 75.0
        self.prev = {}

    def edge(self, key):
        v = V[key]
        was = self.prev.get(key, 0)
        self.prev[key] = v
        return v and not was

    def scan(self, dt):
        n_pad = max(1, min(7, V["Config.PaddleCount"]))
        V["Config.PaddleCount"] = n_pad
        V["Pattern.StepCount"] = max(0, min(20, V["Pattern.StepCount"]))
        used = (1 << n_pad) - 1
        for i in range(20):
            V[f"Pattern.Step{i + 1:02d}.Mask"] = V[f"Pattern.Step{i + 1:02d}.Mask"] & used
            V[f"Pattern.Step{i + 1:02d}.Time"] = max(5, min(6000, V[f"Pattern.Step{i + 1:02d}.Time"]))
        if self.edge("Cmd.EStop"):
            V["System.EStop"] = 1
            self.auto = False
        if self.edge("Cmd.ResetEStop"):
            V["System.EStop"] = 0
            for d in range(len(DEV)):
                V[p(d, 7)] = 0
        if self.edge("Cmd.AutoStart") and not V["System.EStop"]:
            self.auto = True
        if self.edge("Cmd.AutoStop") and self.auto:
            self.auto = False
            self.stop_timer = V["Delay.AutoStopBlower"] / 10
        inst = [True, True] + [k < n_pad for k in range(7)]
        for d in range(len(DEV)):
            # like FB_Motor: a device that is installed again starts enabled, without latches
            if inst[d] and not self.prev.get(("inst", d), True):
                for i in range(10):
                    V[p(d, i)] = 0
            self.prev[("inst", d)] = inst[d]
            c = lambda i: f"{DEV[d]}.Cmd.{CMDS[i]}"
            if self.edge(c(0)):
                V[p(d, 3)], V[p(d, 4)] = 1, 0
            if self.edge(c(1)):
                V[p(d, 4)], V[p(d, 3)] = 1, 0
            if self.edge(c(2)):
                V[p(d, 3)] = V[p(d, 4)] = 0
            if self.edge(c(3)):
                V[p(d, 6)] = 0
            if self.edge(c(4)):
                V[p(d, 6)] = 1
            if self.edge(c(5)):
                V[p(d, 7)] = 0
            V[p(d, 5)] = 1 - V[p(d, 6)]
            V[p(d, 8)] = V["System.EStop"]
            if not inst[d]:
                for i in range(10):
                    V[p(d, i)] = 0
                V[p(d, 6)] = 1

        req = V["Cmd.ExtRequest"]
        V["System.ExtRequest"] = req
        if req:
            self.req_on += dt
            self.req_off = 0
        else:
            self.req_off += dt
            self.req_on = 0

        run = [V[p(d, 9)] for d in range(len(DEV))]
        if V["System.EStop"]:
            self.auto = False
            self.blower_cmd = self.screw_cmd = False
            self.stop_timer = 0
        if self.auto:
            self.blower_cmd = True
            self.stop_timer = 0
            if not run[0]:
                self.screw_cmd = False
            else:
                if (not self.screw_cmd and req and self.run_t[0] >= V["Delay.BlowerToScrew"] / 10
                        and self.req_on >= V["Delay.ReqHold"] / 10):
                    self.screw_cmd = True
                if self.screw_cmd and not req and self.req_off >= V["Delay.ReqOffScrewStop"] / 10:
                    self.screw_cmd = False
        else:
            self.screw_cmd = False
            if self.stop_timer > 0:
                self.stop_timer -= dt
            if self.stop_timer <= 0:
                self.blower_cmd = False
        n = V["Pattern.StepCount"]
        pattern = (self.auto and self.screw_cmd and run[0] and run[1] and req
                   and self.run_t[1] >= V["Delay.ScrewToPaddle"] / 10 and n > 0)
        if pattern and not V["System.PatternActive"]:
            self.step, self.step_t = 0, 0.0
        elif pattern:
            if self.step >= n:
                self.step, self.step_t = 0, 0.0
            self.step_t += dt
            if self.step_t >= max(0.5, V[f"Pattern.Step{self.step + 1:02d}.Time"] / 10):
                self.step = (self.step + 1) % n
                self.step_t = 0.0
        V["System.PatternActive"] = int(pattern)
        V["System.AutoMode"] = int(self.auto)
        V["Pattern.CurrentStep"] = self.step + 1 if pattern else 0
        V["Pattern.StepElapsed"] = int(self.step_t * 10) if pattern else 0

        mask = V[f"Pattern.Step{self.step + 1:02d}.Mask"] if pattern else 0
        auto_start = [self.blower_cmd, self.screw_cmd] + [bool(mask & (1 << k)) for k in range(7)]
        for d in range(len(DEV)):
            if not inst[d]:
                self.run_t[d] = 0.0
                continue
            V[p(d, 0)] = int(auto_start[d])
            V[p(d, 1)] = int(not self.auto and not (d == 0 and self.blower_cmd))
            V[p(d, 2)] = int((d == 1 and not run[0]) or (d >= 2 and not run[1]))
            q = [V[p(d, i)] for i in range(10)]
            if q[7] or q[8] or q[6] or q[4]:
                r = 0
            elif q[3]:
                r = 1
            elif q[1] or q[2]:
                r = 0
            else:
                r = int(q[0])
            V[p(d, 9)] = r
            self.run_t[d] = self.run_t[d] + dt if r else 0.0
            # contactor outputs Q0.0.. (Paddle04 = Q1.1, 05..07 = Q8.0..8.2) like the tag table
            qa = [(0, 0), (0, 1), (0, 2), (0, 3), (0, 4), (1, 1), (8, 0), (8, 1), (8, 2)][d]
            OUTPUTS[qa[0]] = (OUTPUTS[qa[0]] & ~(1 << qa[1])) | (r << qa[1])
        if run[1]:
            self.level -= 0.8 * dt
        if self.level < 25:
            self.level = 90.0
        V["Silo.Level"] = int(self.level * 10)


def plc_loop():
    plc = Plc()
    last = time.time()
    while True:
        time.sleep(0.05)
        now = time.time()
        with LOCK:
            plc.scan(now - last)
        last = now


def recv(sock, n):
    buf = b""
    while len(buf) < n:
        chunk = sock.recv(n - len(buf))
        if not chunk:
            return None
        buf += chunk
    return buf


class Handler(socketserver.BaseRequestHandler):
    def handle(self):
        sock = self.request
        while True:
            hdr = recv(sock, 7)
            if not hdr:
                return
            tid, pid, length, uid = struct.unpack(">HHHB", hdr)
            pdu = recv(sock, length - 1)
            if pdu is None:
                return
            resp = self.process(pdu)
            sock.sendall(struct.pack(">HHHB", tid, 0, len(resp) + 1, uid) + resp)

    @staticmethod
    def process(pdu):
        fn = pdu[0]
        try:
            with LOCK:
                if fn in (1, 2):
                    addr, cnt = struct.unpack(">HH", pdu[1:5])
                    if addr + cnt > 1000:
                        raise IndexError
                    data = bytearray((cnt + 7) // 8)
                    for i in range(cnt):
                        k = COIL.get(addr + i)
                        if k and V[k]:
                            data[i // 8] |= 1 << (i % 8)
                    out = bytes([fn, len(data)]) + bytes(data)
                elif fn in (3, 4):
                    addr, cnt = struct.unpack(">HH", pdu[1:5])
                    if addr + cnt > 200:
                        raise IndexError
                    out = bytes([fn, cnt * 2]) + b"".join(
                        struct.pack(">H", V[HREG[a]] & 0xFFFF if a in HREG else 0) for a in range(addr, addr + cnt))
                elif fn == 5:
                    addr, val = struct.unpack(">HH", pdu[1:5])
                    if addr in COIL:
                        V[COIL[addr]] = 1 if val == 0xFF00 else 0
                    out = pdu[:5]
                elif fn == 6:
                    addr, val = struct.unpack(">HH", pdu[1:5])
                    if addr in HREG:
                        V[HREG[addr]] = val
                    out = pdu[:5]
                elif fn == 16:
                    addr, cnt = struct.unpack(">HH", pdu[1:5])
                    for i in range(cnt):
                        if addr + i in HREG:
                            V[HREG[addr + i]] = struct.unpack(">H", pdu[6 + i * 2:8 + i * 2])[0]
                    out = pdu[:5]
                else:
                    return bytes([fn | 0x80, 1])
            if LOG:
                print(f"MB  fc{fn} addr={struct.unpack('>H', pdu[1:3])[0]} {pdu[3:].hex()}", flush=True)
            return out
        except (IndexError, struct.error):
            return bytes([fn | 0x80, 2])


class Server(socketserver.ThreadingTCPServer):
    allow_reuse_address = True
    daemon_threads = True


def db_image():
    b = bytearray(S7_DB_SIZE)
    for (byte, bit), k in S7BIT.items():
        if V[k]:
            b[byte] |= 1 << bit
    for off, k in S7WORD.items():
        b[off:off + 2] = struct.pack(">H", V[k] & 0xFFFF)
    return b


def db_store(start, data):
    img = db_image()
    img[start:start + len(data)] = data
    for byte in range(start, start + len(data)):
        for bit in range(8):
            k = S7BIT.get((byte, bit))
            if k:
                V[k] = (img[byte] >> bit) & 1
        off = byte - (byte % 2)
        k = S7WORD.get(off)
        if k:
            V[k] = struct.unpack(">h", bytes(img[off:off + 2]))[0]


class S7Handler(socketserver.BaseRequestHandler):
    def handle(self):
        sock = self.request
        while True:
            hdr = recv(sock, 4)
            if not hdr or hdr[0] != 3:
                return
            n = (hdr[2] << 8) | hdr[3]
            body = recv(sock, n - 4)
            if body is None:
                return
            li, typ = body[0], body[1]
            if typ == 0xE0:                                   # COTP connection request
                params = body[7:li + 1]
                cc = bytes([0xD0]) + body[4:6] + b"\x00\x01\x00" + params
                self.send(sock, bytes([len(cc)]) + cc)
                continue
            if typ != 0xF0:
                return
            self.send(sock, b"\x02\xF0\x80" + self.process(body[li + 1:]))

    @staticmethod
    def send(sock, payload):
        sock.sendall(struct.pack(">BBH", 3, 0, len(payload) + 4) + payload)

    @staticmethod
    def ack(ref, params, data=b""):
        return (bytes([0x32, 3, 0, 0]) + ref + struct.pack(">HH", len(params), len(data))
                + b"\x00\x00" + params + data)

    def process(self, pdu):
        ref = pdu[4:6]
        plen = struct.unpack(">H", pdu[6:8])[0]
        params = pdu[10:10 + plen]
        data = pdu[10 + plen:]
        fn = params[0]
        if fn == 0xF0:                                        # setup communication
            return self.ack(ref, b"\xF0\x00\x00\x01\x00\x01" + struct.pack(">H", 480))
        count = params[1]
        items = [params[2 + i * 12:14 + i * 12] for i in range(count)]
        with LOCK:
            if fn == 0x04:                                    # read var
                out = b""
                for k, it in enumerate(items):
                    ts, n, db, area = it[3], struct.unpack(">H", it[4:6])[0], struct.unpack(">H", it[6:8])[0], it[8]
                    addr = int.from_bytes(it[9:12], "big")
                    start, bit = addr >> 3, addr & 7
                    mem = db_image() if (area == 0x84 and db == S7_DB) else AREA_MEM.get(area)
                    if LOG:
                        print(f"S7  READ  area={area:02x} db={db} start={start} n={n}", flush=True)
                    if mem is None:
                        item = b"\x0A\x00\x00\x00"
                    elif start + n > len(mem):
                        item = b"\x05\x00\x00\x00"
                    elif ts == 1:
                        item = b"\xFF\x03\x00\x01" + bytes([(mem[start] >> bit) & 1])
                    else:
                        item = b"\xFF\x04" + struct.pack(">H", n * 8) + bytes(mem[start:start + n])
                    if len(item) % 2 and k < count - 1:
                        item += b"\x00"
                    out += item
                return self.ack(ref, bytes([4, count]), out)
            if fn == 0x05:                                    # write var
                res, pos = b"", 0
                for it in items:
                    ts, db, area = it[3], struct.unpack(">H", it[6:8])[0], it[8]
                    addr = int.from_bytes(it[9:12], "big")
                    start, bit = addr >> 3, addr & 7
                    dts, dlen = data[pos + 1], struct.unpack(">H", data[pos + 2:pos + 4])[0]
                    nbytes = 1 if dts == 3 else dlen // 8
                    val = data[pos + 4:pos + 4 + nbytes]
                    pos += 4 + nbytes + (nbytes % 2)
                    if LOG:
                        print(f"S7  WRITE area={area:02x} db={db} start={start}.{bit} data={val.hex()}", flush=True)
                    if area == 0x84 and db == S7_DB:
                        if ts == 1:
                            k = S7BIT.get((start, bit))
                            if k:
                                V[k] = val[0] & 1
                        else:
                            db_store(start, val)
                        res += b"\xFF"
                    elif area in AREA_MEM and start + len(val) <= len(AREA_MEM[area]):
                        mem = AREA_MEM[area]
                        if ts == 1:
                            mem[start] = (mem[start] & ~(1 << bit)) | ((val[0] & 1) << bit)
                        else:
                            mem[start:start + len(val)] = val
                        res += b"\xFF"
                    else:
                        res += b"\x0A"
                return self.ack(ref, bytes([5, count]), res)
        return bytes([0x32, 3, 0, 0]) + ref + b"\x00\x00\x00\x00\x81\x04"


def main():
    global LOG
    here = os.path.dirname(os.path.abspath(__file__))
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--host", default="127.0.0.1")
    ap.add_argument("--port", type=int, default=5020, help="Modbus TCP port, 0 = off")
    ap.add_argument("--s7port", type=int, default=102, help="Siemens S7 (ISO-on-TCP) port, 0 = off")
    ap.add_argument("--map", default=os.path.join(here, "..", "docs", "RegisterMap_Default.csv"))
    ap.add_argument("--log", action="store_true", help="print every request")
    a = ap.parse_args()
    LOG = a.log
    load_map(a.map)
    init()
    threading.Thread(target=plc_loop, daemon=True).start()
    if a.s7port:
        try:
            s7 = Server((a.host, a.s7port), S7Handler)
            threading.Thread(target=s7.serve_forever, daemon=True).start()
            print(f"Siemens S7 server (DB{S7_DB}) on {a.host}:{a.s7port}", flush=True)
        except OSError as e:
            print(f"S7 port {a.s7port} not available: {e}", flush=True)
    if a.port:
        print(f"Modbus TCP server on {a.host}:{a.port}", flush=True)
        Server((a.host, a.port), Handler).serve_forever()
    else:
        while True:
            time.sleep(1)


if __name__ == "__main__":
    main()
