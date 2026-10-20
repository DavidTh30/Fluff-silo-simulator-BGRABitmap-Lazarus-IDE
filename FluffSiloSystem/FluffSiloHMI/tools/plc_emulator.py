"""FluffSilo PLC emulator - Modbus TCP + Siemens S7 server (Python stdlib only).

For testing FluffSilo HMI without a real PLC. Implements the DEFAULT register map
of FluffSilo HMI (see HMI_RegisterMap.md) - Modbus and S7 (DB10) - and a simplified
version of the Fluff Silo sequence, so the HMI shows a moving plant.

    python plc_emulator.py [--host 127.0.0.1] [--port 5020] [--s7port 102] [--log]

Then in the HMI: Hardware Config -> protocol, IP 127.0.0.1, port 5020 (Modbus)
or 102 (S7, any rack/slot), Save; data source "PLC"; CONNECT.
"""
import argparse
import socketserver
import struct
import threading
import time

COILS = [0] * 1000
HR = [0] * 200
LOCK = threading.Lock()
LOG = False

DEV = ["Blower01", "Screw01", "Paddle01", "Paddle02", "Paddle03"]
P_AUTOSTART, P_AUTOSTOP, P_INTERLOCK, P_MANSTART, P_MANSTOP = 0, 1, 2, 3, 4
P_ENABLE, P_DISABLE, P_FAULT, P_ESTOP, P_RUNNING = 5, 6, 7, 8, 9
C_AUTOMODE, C_EXTREQ, C_PATTERN, C_ESTOP = 150, 151, 152, 153
CMD_AUTOSTART, CMD_AUTOSTOP, CMD_ESTOP, CMD_RESET, CMD_EXTREQ = 160, 161, 162, 163, 164


def dp(d, p):
    return 100 + d * 10 + p


def dc(d, c):
    return 200 + d * 10 + c


def init():
    for d in range(5):
        COILS[dp(d, P_ENABLE)] = 1
    for i, v in enumerate([70, 30, 30, 30, 50, 50]):   # delays x0.1 s
        HR[i] = v
    pat = [(1, 80), (0, 20), (2, 80), (0, 20), (4, 80), (0, 20)]
    HR[20] = len(pat)
    for i, (m, t) in enumerate(pat):
        HR[21 + i] = m
        HR[31 + i] = t
    HR[12] = 750                                          # level 75.0 %


class Plc:
    """Very small copy of the Fluff Silo sequence (enough to exercise the HMI)."""

    def __init__(self):
        self.auto = False
        self.blower_cmd = False
        self.screw_cmd = False
        self.req_on = self.req_off = 0.0
        self.run_t = [0.0] * 5
        self.step = 0
        self.step_t = 0.0
        self.stop_timer = 0.0
        self.level = HR[12] / 10
        self.prev = {}

    def edge(self, addr):
        v = COILS[addr]
        was = self.prev.get(addr, 0)
        self.prev[addr] = v
        return v and not was

    def scan(self, dt):
        c = COILS
        if self.edge(CMD_ESTOP):
            c[C_ESTOP] = 1
            self.auto = False
        if self.edge(CMD_RESET):
            c[C_ESTOP] = 0
        if self.edge(CMD_AUTOSTART) and not c[C_ESTOP]:
            self.auto = True
        if self.edge(CMD_AUTOSTOP) and self.auto:
            self.auto = False
            self.stop_timer = HR[5] / 10
        for d in range(5):
            if self.edge(dc(d, 0)):
                c[dp(d, P_MANSTART)], c[dp(d, P_MANSTOP)] = 1, 0
            if self.edge(dc(d, 1)):
                c[dp(d, P_MANSTOP)], c[dp(d, P_MANSTART)] = 1, 0
            if self.edge(dc(d, 2)):
                c[dp(d, P_MANSTART)] = c[dp(d, P_MANSTOP)] = 0
            if self.edge(dc(d, 3)):
                c[dp(d, P_DISABLE)] = 0
            if self.edge(dc(d, 4)):
                c[dp(d, P_DISABLE)] = 1
            if self.edge(dc(d, 5)):
                c[dp(d, P_FAULT)] = 0
            c[dp(d, P_ENABLE)] = 1 - c[dp(d, P_DISABLE)]
            c[dp(d, P_ESTOP)] = c[C_ESTOP]

        req = c[CMD_EXTREQ]
        c[C_EXTREQ] = req
        if req:
            self.req_on += dt
            self.req_off = 0
        else:
            self.req_off += dt
            self.req_on = 0

        run = [c[dp(d, P_RUNNING)] for d in range(5)]
        if self.auto:
            self.blower_cmd = True
            self.stop_timer = 0
            if not run[0]:
                self.screw_cmd = False
            else:
                if not self.screw_cmd and req and self.run_t[0] >= HR[0] / 10 and self.req_on >= HR[1] / 10:
                    self.screw_cmd = True
                if self.screw_cmd and not req and self.req_off >= HR[3] / 10:
                    self.screw_cmd = False
        else:
            self.screw_cmd = False
            if self.stop_timer > 0:
                self.stop_timer -= dt
            if self.stop_timer <= 0:
                self.blower_cmd = False
        pattern = (self.auto and self.screw_cmd and run[0] and run[1] and req
                   and self.run_t[1] >= HR[2] / 10 and HR[20] > 0)
        if pattern and not c[C_PATTERN]:
            self.step, self.step_t = 0, 0.0
        elif pattern:
            self.step_t += dt
            if self.step_t >= max(0.5, HR[31 + self.step] / 10):
                self.step = (self.step + 1) % HR[20]
                self.step_t = 0.0
        c[C_PATTERN] = int(pattern)
        c[C_AUTOMODE] = int(self.auto)
        HR[10] = self.step + 1 if pattern else 0
        HR[11] = int(self.step_t * 10) if pattern else 0

        mask = HR[21 + self.step] if pattern else 0
        auto_start = [self.blower_cmd, self.screw_cmd] + [bool(mask & (1 << k)) for k in range(3)]
        for d in range(5):
            c[dp(d, P_AUTOSTART)] = int(auto_start[d])
            c[dp(d, P_AUTOSTOP)] = int(not self.auto and not (d == 0 and self.blower_cmd))
            c[dp(d, P_INTERLOCK)] = int((d == 1 and not run[0]) or (d >= 2 and not run[1]))
            p = [c[dp(d, i)] for i in range(10)]
            if p[P_FAULT] or p[P_ESTOP] or p[P_DISABLE] or p[P_MANSTOP]:
                r = 0
            elif p[P_MANSTART]:
                r = 1
            elif p[P_AUTOSTOP] or p[P_INTERLOCK]:
                r = 0
            else:
                r = int(p[P_AUTOSTART])
            c[dp(d, P_RUNNING)] = r
            self.run_t[d] = self.run_t[d] + dt if r else 0.0
        if run[1]:
            self.level -= 0.8 * dt          # % per second while discharging
        if self.level < 25:
            self.level = 90.0               # refilled
        HR[12] = int(self.level * 10)


def plc_loop():
    plc = Plc()
    last = time.time()
    while True:
        time.sleep(0.05)
        now = time.time()
        with LOCK:
            plc.scan(now - last)
        last = now


class Handler(socketserver.BaseRequestHandler):
    def handle(self):
        sock = self.request
        while True:
            hdr = self.recv(sock, 7)
            if not hdr:
                return
            tid, pid, length, uid = struct.unpack(">HHHB", hdr)
            pdu = self.recv(sock, length - 1)
            if pdu is None:
                return
            resp = self.process(pdu)
            sock.sendall(struct.pack(">HHHB", tid, 0, len(resp) + 1, uid) + resp)

    @staticmethod
    def recv(sock, n):
        buf = b""
        while len(buf) < n:
            chunk = sock.recv(n - len(buf))
            if not chunk:
                return None
            buf += chunk
        return buf

    def process(self, pdu):
        fn = pdu[0]
        try:
            with LOCK:
                if fn in (1, 2):
                    addr, cnt = struct.unpack(">HH", pdu[1:5])
                    if addr + cnt > len(COILS):
                        raise IndexError
                    bits = COILS[addr:addr + cnt]
                    data = bytearray((cnt + 7) // 8)
                    for i, b in enumerate(bits):
                        if b:
                            data[i // 8] |= 1 << (i % 8)
                    out = bytes([fn, len(data)]) + bytes(data)
                elif fn in (3, 4):
                    addr, cnt = struct.unpack(">HH", pdu[1:5])
                    if addr + cnt > len(HR):
                        raise IndexError
                    out = bytes([fn, cnt * 2]) + b"".join(struct.pack(">H", v & 0xFFFF) for v in HR[addr:addr + cnt])
                elif fn == 5:
                    addr, val = struct.unpack(">HH", pdu[1:5])
                    COILS[addr] = 1 if val == 0xFF00 else 0
                    out = pdu[:5]
                elif fn == 6:
                    addr, val = struct.unpack(">HH", pdu[1:5])
                    HR[addr] = val
                    out = pdu[:5]
                elif fn == 16:
                    addr, cnt = struct.unpack(">HH", pdu[1:5])
                    for i in range(cnt):
                        HR[addr + i] = struct.unpack(">H", pdu[6 + i * 2:8 + i * 2])[0]
                    out = pdu[:5]
                else:
                    return bytes([fn | 0x80, 1])
            if LOG and fn in (5, 6, 16):
                print(f"WRITE fc{fn} addr={struct.unpack('>H', pdu[1:3])[0]} data={pdu[3:].hex()}", flush=True)
            elif LOG:
                print(f"READ  fc{fn} addr={struct.unpack('>H', pdu[1:3])[0]} n={struct.unpack('>H', pdu[3:5])[0]}",
                      flush=True)
            return out
        except (IndexError, struct.error):
            return bytes([fn | 0x80, 2])


class Server(socketserver.ThreadingTCPServer):
    allow_reuse_address = True
    daemon_threads = True


# ---------------------------------------------------------------- Siemens S7 ---
# DB10 is a view onto the same memory, using the default S7 map of FluffSilo HMI:
#   DBB0..9 device status (2 bytes/device), DBB10 system, DBB12 main commands,
#   DBB14..18 device commands, DBW20.. delays, DBW32/34/36 process,
#   DBW40 step count, DBW42.. masks, DBW62.. times
S7_DB = 10
S7_DB_SIZE = 100
MERKERS = bytearray(256)
INPUTS = bytearray(64)     # %I  (written by the FluffSilo Client Panel)
OUTPUTS = bytearray(64)    # %Q  (read by the Client Panel; write with --log to watch)
AREA_MEM = {0x81: INPUTS, 0x82: OUTPUTS, 0x83: MERKERS}


def _bit_coil(byte, bit):
    """DB10 bit -> coil index (None if unmapped)."""
    if byte < 10:
        d, p = byte // 2, (byte % 2) * 8 + bit
        return 100 + d * 10 + p if p < 10 else None
    if byte == 10 and bit < 4:
        return 150 + bit
    if byte == 12 and bit < 5:
        return 160 + bit
    if 14 <= byte <= 18 and bit < 6:
        return 200 + (byte - 14) * 10 + bit
    return None


def _word_hr(off):
    """DB10 word offset -> holding register index (None if unmapped)."""
    if 20 <= off <= 30 and off % 2 == 0:
        return (off - 20) // 2
    if off in (32, 34, 36):
        return 10 + (off - 32) // 2
    if off == 40:
        return 20
    if 42 <= off <= 60 and off % 2 == 0:
        return 21 + (off - 42) // 2
    if 62 <= off <= 80 and off % 2 == 0:
        return 31 + (off - 62) // 2
    return None


def db_image():
    b = bytearray(S7_DB_SIZE)
    for byte in range(19):
        for bit in range(8):
            c = _bit_coil(byte, bit)
            if c is not None and COILS[c]:
                b[byte] |= 1 << bit
    for off in range(20, 82, 2):
        h = _word_hr(off)
        if h is not None:
            b[off] = (HR[h] >> 8) & 0xFF
            b[off + 1] = HR[h] & 0xFF
    return b


def db_store(start, data):
    img = db_image()
    img[start:start + len(data)] = data
    for byte in range(start, start + len(data)):
        if byte < 19:
            for bit in range(8):
                c = _bit_coil(byte, bit)
                if c is not None:
                    COILS[c] = (img[byte] >> bit) & 1
        off = byte - (byte % 2)
        h = _word_hr(off)
        if h is not None:
            HR[h] = (img[off] << 8) | img[off + 1]


class S7Handler(socketserver.BaseRequestHandler):
    def handle(self):
        sock = self.request
        while True:
            hdr = Handler.recv(sock, 4)
            if not hdr or hdr[0] != 3:
                return
            n = (hdr[2] << 8) | hdr[3]
            body = Handler.recv(sock, n - 4)
            if body is None:
                return
            li, typ = body[0], body[1]
            if typ == 0xE0:                                   # COTP connection request
                params = body[7:li + 1]
                tsap = params[params.index(0xC2) + 2:params.index(0xC2) + 4] if 0xC2 in params else b""
                if LOG:
                    print(f"S7  COTP CR  remote TSAP={tsap.hex()}", flush=True)
                cc = bytes([0xD0]) + body[4:6] + b"\x00\x01\x00" + params
                self.send(sock, bytes([len(cc)]) + cc)
                continue
            if typ != 0xF0:
                return
            pdu = body[li + 1:]
            resp = self.process(pdu)
            self.send(sock, b"\x02\xF0\x80" + resp)

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
                            c = _bit_coil(start, bit)
                            if c is not None:
                                COILS[c] = val[0] & 1
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
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--host", default="127.0.0.1")
    ap.add_argument("--port", type=int, default=5020)
    ap.add_argument("--s7port", type=int, default=102, help="Siemens S7 (ISO-on-TCP) port, 0 = off")
    ap.add_argument("--log", action="store_true", help="print every request")
    a = ap.parse_args()
    LOG = a.log
    init()
    threading.Thread(target=plc_loop, daemon=True).start()
    if a.s7port:
        try:
            s7 = Server((a.host, a.s7port), S7Handler)
            threading.Thread(target=s7.serve_forever, daemon=True).start()
            print(f"Siemens S7 server (DB{S7_DB}) on {a.host}:{a.s7port}", flush=True)
        except OSError as e:
            print(f"S7 port {a.s7port} not available: {e}", flush=True)
    print(f"Modbus TCP server on {a.host}:{a.port}", flush=True)
    Server((a.host, a.port), Handler).serve_forever()


if __name__ == "__main__":
    main()
