# FluffSilo HMI — คู่มือการใช้งาน และ Register Map

> FluffSilo HMI คือโปรแกรมที่ clone มาจาก FluffSilo (Simulator) แล้วเพิ่มการเชื่อมต่อ PLC ได้ 2 แบบ ให้เลือกใน Hardware Config
> - **Modbus TCP** (port 502) ใช้ได้กับ PLC เกือบทุกยี่ห้อ
> - **Siemens S7** (S7comm / ISO-on-TCP, port 102) ต่อ S7-300/400/1200/1500 ได้โดยตรง ไม่ต้องเขียน Modbus server ใน PLC (ดูหัวข้อ 3A)
>
> เมื่อเชื่อมต่อ PLC แล้ว **Logic การควบคุมจะทำงานอยู่ใน PLC** ส่วนโปรแกรมนี้ทำหน้าที่เป็น HMI คือแสดงผล สั่งงาน และปรับ Parameter
> โหมด Simulation เดิมยังใช้งานได้ครบ (ใช้ตอนไม่มี PLC หรือใช้สาธิต)

---

## 1. ไฟล์ในโปรเจกต์

| ไฟล์ | หน้าที่ |
|---|---|
| `FluffSiloHMI.lpi / .lpr` | โปรเจกต์ Lazarus (ต้องใช้แพ็กเกจ LCL + BGRABitmapPack) |
| `umodbus.pas` | **ใหม่** — Modbus TCP client (FC01/02/03/04/05/06/16) ใช้ `ssockets` ของ FPC ไม่ต้องติดตั้งแพ็กเกจเพิ่ม |
| `us7.pas` | **ใหม่** — Siemens S7 client (COTP/ISO-on-TCP + S7comm: setup, read var, write var/bit) และตัวแปลง S7 address เช่น `DB10.DBX0.0` |
| `uplclink.pas` | **ใหม่** — Tag map (Modbus + S7 address ต่อ tag), โหลด/บันทึก INI, Thread อ่าน/เขียน PLC, ส่งต่อคำสั่ง HMI ไปที่ Simulator หรือ PLC (`Hmi*`) |
| `uhwconfigform.pas` | **ใหม่** — หน้าต่าง Hardware Config |
| `usim.pas` | เพิ่ม `Source` (Simulation/PLC), `StepExternal`, `ResetRuntime` |
| `umain.pas` | เพิ่มกลุ่ม **PLC Connection** และส่งทุกปุ่มผ่าน `Hmi*` |
| `udeviceform.pas` | ปุ่มของแต่ละอุปกรณ์ส่งผ่าน `Hmi*` (ใน PLC mode ปิดปุ่ม Simulate Fault) |
| `FluffSiloHMI.ini` | สร้างอัตโนมัติข้างไฟล์ .exe เมื่อกด **Save & Apply** ใน Hardware Config |
| `tools/plc_emulator.py` | PLC จำลอง (Modbus TCP server + S7 server ที่มี DB10, Python ล้วน) ใช้ทดสอบ HMI โดยไม่ต้องมี PLC จริง |
| `tools/linktest.lpr` | โปรแกรมทดสอบอัตโนมัติ (console) ของส่วน PLC link |

---

## 2. วิธีใช้งาน

1. เปิด `FluffSiloHMI.exe`
2. กด **Hardware Config**
   - เลือก **Protocol**: `Modbus TCP` หรือ `Siemens S7`
     (เมื่อเปลี่ยน protocol ช่อง port จะสลับ 502 ↔ 102 ให้อัตโนมัติ ถ้ายังเป็นค่ามาตรฐานอยู่)
   - ใส่ **PLC IP address** และ **TCP port**
   - **Modbus TCP**: ใส่ **Unit ID** แล้วเลือก **Address base**
     - `0 - protocol offset` ใช้ตัวเลขตำแหน่งแบบ protocol จริง คือ coil แรก = 0
     - `1 - 1-based` เหมาะกับคู่มือ PLC ที่นับตำแหน่งแรกเป็น 1 เช่น 40001 → ใส่ 1
   - **Siemens S7**: ใส่ **Rack / Slot** และเลือก **Connection type** (ดูหัวข้อ 3A)
   - แก้ตาราง **Register map** ให้ตรงกับ PLC
     - Modbus: แก้คอลัมน์ Area / Address / Bit
     - S7: แก้คอลัมน์ **S7 Address** (address ที่ผิดรูปแบบจะเป็นตัวแดง)
     - ทั้งสองแบบแก้ Type / Scale / Use ได้ และใช้ **Show group** กรองตารางได้
   - กด **Test connection** เพื่อตรวจการเชื่อมต่อและอ่าน tag แรก
   - กด **Save & Apply** เพื่อบันทึกลง `FluffSiloHMI.ini`
   - ทุก tag เก็บ address ไว้ทั้งแบบ Modbus และ S7 จึงสลับ protocol ไปมาได้โดยค่าที่ตั้งไว้ไม่หาย
3. ที่กลุ่ม **PLC Connection** เลือก Data source = **PLC (Modbus TCP / S7)** แล้วกด **CONNECT**
   - หลอดไฟเขียวพร้อมข้อความ `ONLINE ... polls n` = สื่อสารปกติ
   - ถ้าสื่อสารขาด จะมีแถบส้ม **PLC COMMUNICATION LOST** บน Overview และระบบจะพยายามเชื่อมต่อใหม่เองทุก 2 วินาที
4. ตอนตั้งค่าหน้างาน ให้เปิด Hardware Config ขณะ ONLINE แล้วดูคอลัมน์ **Live value** ว่าค่าตรงกับสถานะจริงของ PLC หรือไม่
5. ตัวเลือก **Connect automatically at start-up** และ **Start in PLC mode** ทำให้เปิดโปรแกรมแล้วเชื่อมต่อ PLC ทันที

### สิ่งที่ปรับจาก HMI ได้ (เขียนลง PLC)

| ส่วนบนหน้าจอ | สิ่งที่เขียนลง PLC |
|---|---|
| AUTO START / AUTO STOP / E-STOP / RESET E-STOP | Coil คำสั่งแบบ **pulse** |
| EXTERNAL REQUEST | Coil แบบ **คงค่า** 1/0 |
| Device Panel: Manual Start/Stop, Return to Auto, Enable, Disable, Reset Fault | Coil คำสั่งแบบ **pulse** ของแต่ละอุปกรณ์ |
| Delay Settings (6 ค่า) | Holding Register (หน่วย 0.1 s) |
| Paddle Patterns: คลิก P1/P2/P3, แก้ Time, Add/Delete/Default | Holding Register ของ Pattern (สูงสุด 10 step) |

**Pulse** หมายถึง HMI เขียนค่า 1 แล้วเขียน 0 กลับหลังเวลา **Command pulse (ms)** (ค่าเริ่มต้น 500 ms)
ฝั่ง PLC ควรตรวจจับคำสั่งด้วย **ขอบขาขึ้น (rising edge)**

Parameter ที่ HMI แสดงจะ **อ่านกลับจาก PLC** ทุกรอบ poll ดังนั้นค่าบนจอคือค่าจริงใน PLC
ถ้า PLC ไม่รับค่า (เช่น ค่าเกินช่วง) ตัวเลขบนจอจะเด้งกลับเป็นค่าเดิม

---

## 3. Default Register Map

ค่าเริ่มต้นเป็นแบบ **Address base = 0 (protocol offset)**
ทุก bit ใช้พื้นที่ Coil (0x) และทุกค่าตัวเลขใช้ Holding Register (4x) สามารถเปลี่ยน Area ได้ทุก tag

### 3.1 สถานะอุปกรณ์ (PLC → HMI, Coil, อ่านอย่างเดียว)

Address = **100 + อุปกรณ์×10 + property**

| Property (offset) | Blower01 | Screw01 | Paddle01 | Paddle02 | Paddle03 |
|---|---|---|---|---|---|
| +0 Auto Start (L1) | 100 | 110 | 120 | 130 | 140 |
| +1 Auto Stop (L2) | 101 | 111 | 121 | 131 | 141 |
| +2 Interlock (L2) | 102 | 112 | 122 | 132 | 142 |
| +3 Manual Start (L3) | 103 | 113 | 123 | 133 | 143 |
| +4 Manual Stop (L4) | 104 | 114 | 124 | 134 | 144 |
| +5 Enable (L5) | 105 | 115 | 125 | 135 | 145 |
| +6 Disable (L5) | 106 | 116 | 126 | 136 | 146 |
| +7 Fault (L6) | 107 | 117 | 127 | 137 | 147 |
| +8 E-Stop (L6) | 108 | 118 | 128 | 138 | 148 |
| +9 **Running (feedback)** | 109 | 119 | 129 | 139 | 149 |

สีของอุปกรณ์บนจอคำนวณจาก property เหล่านี้ตามกฎใน Concept
การหมุนของอุปกรณ์และเวลาทำงาน (Run time / Starts) ใช้ค่า **Running** จาก PLC

### 3.2 สถานะระบบ (PLC → HMI, Coil, อ่านอย่างเดียว)

| Address | Tag | ความหมาย |
|---|---|---|
| 150 | System.AutoMode | 1 = อยู่ในโหมด Auto Start |
| 151 | System.ExtRequest | สัญญาณ External Request ที่ PLC ใช้จริง |
| 152 | System.PatternActive | Paddle Patterns กำลังทำงาน |
| 153 | System.EStop | E-Stop หลัก active |

### 3.3 คำสั่งจากแผงควบคุมหลัก (HMI → PLC, Coil, เขียน)

| Address | Tag | ชนิด |
|---|---|---|
| 160 | Cmd.AutoStart | pulse |
| 161 | Cmd.AutoStop | pulse |
| 162 | Cmd.EStop | pulse (E-Stop ทาง HMI — **ห้ามใช้แทนวงจร E-Stop hardware**) |
| 163 | Cmd.ResetEStop | pulse |
| 164 | Cmd.ExtRequest | คงค่า 1/0 |

### 3.4 คำสั่งรายอุปกรณ์ (HMI → PLC, Coil, pulse)

Address = **200 + อุปกรณ์×10 + คำสั่ง**

| คำสั่ง (offset) | Blower01 | Screw01 | Paddle01 | Paddle02 | Paddle03 |
|---|---|---|---|---|---|
| +0 ManualStart | 200 | 210 | 220 | 230 | 240 |
| +1 ManualStop | 201 | 211 | 221 | 231 | 241 |
| +2 ReturnAuto (ยกเลิก Manual) | 202 | 212 | 222 | 232 | 242 |
| +3 Enable | 203 | 213 | 223 | 233 | 243 |
| +4 Disable | 204 | 214 | 224 | 234 | 244 |
| +5 ResetFault | 205 | 215 | 225 | 235 | 245 |

### 3.5 Parameter และค่า Process (Holding Register)

| Address | Tag | R/W | Type | Scale | หน่วย / ความหมาย |
|---|---|---|---|---|---|
| 0 | Delay.BlowerToScrew | RW | UINT16 | 0.1 | s (ค่าเริ่มต้น 70 = 7.0 s) |
| 1 | Delay.ReqHold | RW | UINT16 | 0.1 | s (30 = 3.0 s) |
| 2 | Delay.ScrewToPaddle | RW | UINT16 | 0.1 | s |
| 3 | Delay.ReqOffScrewStop | RW | UINT16 | 0.1 | s |
| 4 | Delay.ScrewTripBlower | RW | UINT16 | 0.1 | s |
| 5 | Delay.AutoStopBlower | RW | UINT16 | 0.1 | s |
| 10 | Pattern.CurrentStep | R | UINT16 | 1 | step ที่กำลังทำงาน (นับจาก 1, 0 = ไม่ทำงาน) |
| 11 | Pattern.StepElapsed | R | UINT16 | 0.1 | s ที่ผ่านไปของ step ปัจจุบัน (ถ้าปิดใช้งาน HMI จะประมาณเอง) |
| 12 | Silo.Level | R | UINT16 | 0.1 | % ระดับไซโล (ถ้าปิดใช้งาน จะแสดง "Level n/a") |
| 20 | Pattern.StepCount | RW | UINT16 | 1 | จำนวน step 0..10 |
| 21..30 | Pattern.Step01..10.Mask | RW | UINT16 | 1 | bit0 = Paddle01, bit1 = Paddle02, bit2 = Paddle03 (0 = Pause) |
| 31..40 | Pattern.Step01..10.Time | RW | UINT16 | 0.1 | s ระยะเวลาของ step |

Pattern เริ่มต้นใน PLC ที่แนะนำ: `StepCount=6`, `Mask = 1,0,2,0,4,0`, `Time = 80,20,80,20,80,20`

---

## 3A. Siemens S7

### การตั้งค่าใน TIA Portal / STEP 7 (ต้องทำก่อน)

| CPU | สิ่งที่ต้องตั้ง |
|---|---|
| S7-1200 / S7-1500 | CPU Properties → *Protection & Security* → *Connection mechanisms* → ติ๊ก **Permit access with PUT/GET communication from remote partner** |
| S7-1200 / S7-1500 | DB ที่ใช้ (ค่าเริ่มต้น DB10) → Properties → *Attributes* → **ไม่ติ๊ก "Optimized block access"** แล้ว compile/download ใหม่ |
| S7-1500 | ถ้าเปิด access protection ต้องตั้งระดับให้อนุญาต HMI access |
| S7-300 / S7-400 | ใช้ได้ทันที (ต่อผ่าน CP/PN port ของ CPU) |

ถ้าไม่ได้ตั้ง PUT/GET จะเห็น error `PLC refused the function (enable PUT/GET ...)`
ถ้า DB เป็น optimized จะเห็น `Access denied (enable PUT/GET, DB must not be optimized)`

### Rack / Slot / Connection type

| CPU | Rack | Slot |
|---|---|---|
| S7-1200, S7-1500 | 0 | 1 |
| S7-300 | 0 | 2 |
| S7-400 | 0 | ตามตำแหน่ง CPU ใน rack (ดูใน HW Config) |
| ET200SP CPU | 0 | 1 |

**Connection type** ค่าเริ่มต้นคือ `PG` ถ้า PLC มีการเชื่อมต่อแบบ PG เต็ม ให้เปลี่ยนเป็น `OP` หรือ `S7 Basic`
Port มาตรฐานคือ **102**

### รูปแบบ S7 Address ที่รองรับ

ใส่ `%` นำหน้าได้ ไม่สนตัวพิมพ์เล็ก/ใหญ่ และใช้ตัวย่อแบบเยอรมันได้ด้วย (`E` = I, `A` = Q)

| ชนิดข้อมูล | Type ใน HMI | ตัวอย่าง |
|---|---|---|
| Bool | `BOOL` | `DB10.DBX12.3`, `M10.3`, `Q0.1`, `I0.0` |
| Byte | `UINT16` | `DB10.DBB4`, `MB5` |
| Int / Word | `INT16` / `UINT16` | `DB10.DBW20`, `MW20` |
| DInt / Real | `INT32` / `FLOAT32` | `DB10.DBD40`, `MD24` |

- Tag ที่ HMI ต้องเขียนห้ามอยู่ใน `I` (input)
- การเขียน Bool ใช้คำสั่งเขียน bit เดี่ยวของ S7 จึงไม่ไปทับ bit อื่นใน byte เดียวกัน
- การอ่านจะรวม address ที่อยู่ติดกันใน DB/พื้นที่เดียวกันเป็น request เดียว ขนาดตาม PDU ที่ตกลงกับ PLC
- ปุ่ม **Change DB number...** ใช้เปลี่ยนเลข DB ของทุก tag ในครั้งเดียว เช่น DB10 → DB25

### Default S7 Map — ทุก tag อยู่ใน DB10 (non-optimized)

| Offset ใน DB10 | เนื้อหา |
|---|---|
| `DBX0.0 .. DBX9.7` | สถานะอุปกรณ์: อุปกรณ์ละ 2 byte, byte = อุปกรณ์×2 + property÷8, bit = property mod 8 |
| `DBX10.0 .. 10.3` | System: AutoMode, ExtRequest, PatternActive, EStop |
| `DBX12.0 .. 12.4` | Cmd: AutoStart, AutoStop, EStop, ResetEStop, ExtRequest |
| `DBX14.c .. DBX18.c` | คำสั่งรายอุปกรณ์ (byte 14+อุปกรณ์, bit c = ManualStart, ManualStop, ReturnAuto, Enable, Disable, ResetFault) |
| `DBW20 .. DBW30` | Delay 6 ค่า (INT, ×0.1 s) |
| `DBW32 / 34 / 36` | Pattern.CurrentStep / Pattern.StepElapsed (×0.1 s) / Silo.Level (×0.1 %) |
| `DBW40` | Pattern.StepCount |
| `DBW42 .. DBW60` | Pattern.Step01..10.Mask |
| `DBW62 .. DBW80` | Pattern.Step01..10.Time (×0.1 s) |

ตัวอย่าง address ของสถานะอุปกรณ์:

| Property | Blower01 | Screw01 | Paddle01 | Paddle02 | Paddle03 |
|---|---|---|---|---|---|
| Auto Start | DBX0.0 | DBX2.0 | DBX4.0 | DBX6.0 | DBX8.0 |
| Manual Start | DBX0.3 | DBX2.3 | DBX4.3 | DBX6.3 | DBX8.3 |
| Fault | DBX0.7 | DBX2.7 | DBX4.7 | DBX6.7 | DBX8.7 |
| E-Stop | DBX1.0 | DBX3.0 | DBX5.0 | DBX7.0 | DBX9.0 |
| Running | DBX1.1 | DBX3.1 | DBX5.1 | DBX7.1 | DBX9.1 |

โครงสร้าง DB10 ที่แนะนำใน TIA Portal (ให้ offset ตรงกับตารางด้านบน):
`Array[0..4] of Struct` (อุปกรณ์ละ 10 Bool = 2 byte) → `Struct` System 4 Bool → `Struct` Cmd 5 Bool → `Array[0..4] of Struct` คำสั่งอุปกรณ์ 6 Bool → `Array[0..5] of Int` Delay → `Int` ×3 → `Int` StepCount → `Array[0..9] of Int` Mask → `Array[0..9] of Int` Time

ต้องตรวจคอลัมน์ *Offset* ใน DB editor ให้ตรงกัน เพราะ TIA จัด Struct ให้เริ่มที่ byte คู่เสมอ
ถ้าไม่ตรง ให้แก้ address ใน Hardware Config ตาม offset จริง

---

## 4. ความยืดหยุ่นของ Register Map (Modbus)

| คอลัมน์ | ตัวเลือก |
|---|---|
| Area | `0x Coil`, `1x Discrete Input`, `3x Input Register`, `4x Holding Register` |
| Type | `BOOL`, `INT16`, `UINT16`, `INT32`, `FLOAT32` (32-bit ใช้ 2 register ลำดับ word เลือกได้ใน *32-bit word order*) |
| Bit | ว่าง = ใช้ทั้งค่า, `0..15` = BOOL ที่เป็น bit ใน register (เช่น status word) |
| Scale | ค่าที่แสดง = raw × Scale (เช่น 0.1 สำหรับเวลาหน่วย 100 ms) |
| Use | ไม่ติ๊ก = ไม่อ่าน/ไม่เขียน tag นี้ |

กติกาที่ตรวจตอน Save:
- Tag ที่ต้องเขียน (W/RW) ต้องอยู่ใน Coil หรือ Holding Register
- Coil/Discrete Input ใช้ได้แค่ BOOL
- Bit ใช้ได้เฉพาะ BOOL ที่อยู่ใน register

ข้อควรรู้:
- การเขียน BOOL ที่เป็น bit ใน Holding Register ใช้วิธี **อ่าน → แก้ bit → เขียนกลับ** (FC03 + FC06) หาก PLC เปลี่ยน bit อื่นใน word เดียวกันพร้อมกันอาจชนกัน แนะนำให้แยก word คำสั่งออกจาก word สถานะ
- **Merge read gap**: รวม address ที่ห่างกันไม่เกินค่านี้ให้อ่านใน request เดียว (เร็วขึ้น) หาก PLC ตอบ *Illegal data address* ให้ตั้งเป็น 0
- **Export / Import CSV** ใช้ส่งตาราง address ให้ผู้เขียนโปรแกรม PLC หรือรับกลับมา คั่นด้วย `;` และอ้างอิงด้วยคอลัมน์ Key

ตัวอย่างการตั้ง Address ตามยี่ห้อ PLC (ต้องตรวจสอบกับคู่มือ Modbus ของรุ่นที่ใช้จริง):

| PLC | แนวทาง |
|---|---|
| Siemens S7-1200/1500 (MB_SERVER) | Holding Register = DB ที่กำหนดใน MB_SERVER; Coil = %Q; แนะนำให้ map bit ทั้งหมดเป็น bit ใน Holding Register (ใช้คอลัมน์ Bit) |
| Schneider M221/M241 | %M = Coil, %MW = Holding Register |
| Mitsubishi FX5 / iQ-R | ตั้ง Modbus device assignment (เช่น M → Coil, D → Holding Register) |
| Delta DVP/AS | M bit และ D register มี address Modbus ตายตัวตามคู่มือ (เช่น D0 = 0x1000) |
| Omron NX/NJ | ต้องใช้ Modbus TCP server FB หรือ gateway |

---

## 5. สิ่งที่ PLC ต้องทำ (ข้อกำหนดสำหรับผู้เขียนโปรแกรม PLC)

1. ทำ Logic ทั้งหมดตาม `Concept.txt` ใน PLC: Auto sequence, Priority Level, Interlock, Paddle Patterns และ Delay
2. รับคำสั่ง pulse ด้วย rising edge (HMI ค้างค่า 1 ประมาณ 500 ms)
3. Running (+9) ต้องเป็น **feedback จริง** จาก contactor/drive ไม่ใช่สถานะของคำสั่ง
4. ตรวจช่วงค่าของ Parameter ที่ HMI เขียนมา (เช่น เวลา ≥ 0.5 s, StepCount ≤ 10)
5. **E-Stop ต้องเป็นวงจร hardware** ปุ่ม E-STOP บน HMI เป็นเพียงคำสั่งเสริม
6. แนะนำให้ PLC ตรวจการสื่อสารกับ HMI (watchdog) เอง หาก HMI ขาดการติดต่อไม่ควรทำให้เครื่องจักรอยู่ในสภาวะอันตราย

---

## 6. การทำงานภายใน (สำหรับนักพัฒนา)

```
UI (umain / udeviceform)
  │  Hmi*() ──────────► Simulation: Sim.Cmd*()
  │                     PLC mode : Link.WriteTag() → queue → TPlcThread
  ▼
TPlcLink.Update (ทุก 40 ms, main thread)
  │  copy snapshot ใต้ critical section
  ▼
ApplyToSim → Sim.Props / Mode / Pattern / Delays
  ▼
Sim.StepExternal → CtrlLevel/Reason, RunTime, Starts, History, Event log, Chart

TPlcThread (background)
  loop: connect (retry 2 s) → เขียนคำสั่งที่รอในคิว + ปล่อย pulse → อ่านทุก block → snapshot → รอ PollMs
```

- รวม tag เป็น block ต่อ Area (สูงสุด 120 register / 1900 bit ต่อ request)
- Modbus exception ของ block ใด block หนึ่งจะไม่ตัดการเชื่อมต่อ (แสดงเป็นคำเตือนสีส้ม)
  แต่ถ้า socket error จะ reconnect ใหม่
- **ป้องกันค่าเด้ง**: snapshot ที่อ่านก่อนคำสั่งเขียนของผู้ใช้ไปถึง PLC จะไม่ถูกนำมาทับค่า Parameter/Pattern
- ตัวนับเวลา Delay ที่แสดงบน Overview ในโหมด PLC เป็น **ค่าประมาณของ HMI** (PLC ไม่ได้ส่งค่า timer มา)
  หากต้องการค่าแม่นยำ ให้เพิ่ม tag ของ timer ใน PLC (ดูหัวข้อ 8)

---

## 7. การทดสอบ

### PLC จำลอง

```bash
python tools/plc_emulator.py --port 5020 --s7port 102 --log
```

จากนั้นใน Hardware Config ตั้ง IP `127.0.0.1` แล้วเลือก
- Modbus TCP: port `5020`
- Siemens S7: port `102` (rack/slot ใดก็ได้)

แล้วเลือก Data source เป็น PLC และกด CONNECT

PLC จำลองมี DB10 ตาม Default S7 Map และใช้หน่วยความจำชุดเดียวกับฝั่ง Modbus

### ทดสอบอัตโนมัติ (ขณะ plc_emulator ทำงาน)

```bash
C:\lazarus\fpc\3.2.2\bin\x86_64-win64\fpc.exe -MObjFPC -Fu. -FUlib\test -FElib\test tools\linktest.lpr
```

```bash
lib\test\linktest.exe modbus 127.0.0.1 5020
```

```bash
lib\test\linktest.exe s7 127.0.0.1 102
```

ผลการทดสอบล่าสุด: **PASS ทุกข้อทั้งสอง protocol** (Modbus TCP 36 ข้อ / Siemens S7 37 ข้อ รวมการตรวจตัวแปลง S7 address) ครอบคลุม
- การเชื่อมต่อและการอ่านค่า
- การเขียน Delay และ Pattern (รวม Add/Delete step) แล้วอ่านกลับ
- คำสั่ง Auto Start แบบ pulse และ External Request จนลำดับทำงานถึง Paddle Patterns
- การปล่อย pulse กลับเป็น 0
- Manual Stop / Return to Auto
- E-Stop / Reset
- การตัดการเชื่อมต่อ และกรณีต่อพอร์ตผิด

---

## 8. แนวทางพัฒนาต่อ

- เพิ่ม tag สำหรับ timer จริงจาก PLC (เวลาที่เหลือของแต่ละ delay) และตัวนับชั่วโมงทำงาน/จำนวนครั้ง start ที่เก็บใน PLC
- Heartbeat/Watchdog register ระหว่าง HMI ↔ PLC
- รองรับ Modbus RTU (RS-485) โดยเพิ่ม client ใหม่ข้าง `uModbus` / `uS7` โดยไม่ต้องแก้ UI
- S7: อ่านหลาย item ใน request เดียว เมื่อ tag กระจายอยู่หลาย DB เพื่อลดเวลา poll
- Login/สิทธิ์ผู้ใช้ก่อนแก้ Parameter และ Hardware Config
- บันทึก History/Event ลงฐานข้อมูล (SQLite) เพื่อดูย้อนหลังข้ามการรีสตาร์ท
