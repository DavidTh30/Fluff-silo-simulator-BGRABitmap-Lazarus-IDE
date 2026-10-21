# FluffSilo HMI2 — คู่มือสำหรับพัฒนาต่อ

เอกสารนี้รวบรวมทุกอย่างที่ต้องรู้เพื่อแก้ไข / ขยาย FluffSilo HMI2 และโปรแกรม PLC คู่กัน (`PLC2_S7-1200`)

---

## 1. ภาพรวมสถาปัตยกรรม

```
                 ┌─────────────── UI (main thread, ทุกอย่างวาดด้วย BGRABitmap) ───────────────┐
                 │ umain        upatternform    ueventsform    uchartform    udeviceform      │
                 │   │              │                │              │             │           │
                 │   └──── Hmi*() (uplclink) ◄──────┴──────────────┴─────────────┘           │
                 └───────────┬───────────────────────────────────────────────────────────────┘
                             │
          Simulation ◄───────┴───────► PLC mode
          Sim.Cmd*() / Sim.SetPattern       Link.WriteTag() → queue → TPlcThread (Modbus / S7)
          Sim.Step(dt)                      TPlcThread: poll → snapshot (critical section)
                                            Link.Update → ApplyToSim → Sim.StepExternal(dt)
                             │
                             ▼
             Sim (TFluffSim): Dev[0..8].Props, Mode, Pattern, Delays, History, Events
                             │
                             ├── OnEvent → uLog (logs\HMI2_yyyymmdd.log)
                             └── ทุก 40 ms: Overview, แถบสถานะ, Device/Chart/Pattern/Events refresh
```

- **`Sim` คือแหล่งข้อมูลเดียวของหน้าจอ** ทั้งโหมด Simulation และ PLC
  ในโหมด PLC ค่าที่อ่านได้จะถูกเขียนลง `Sim` (ApplyToSim) แล้วหน้าจออ่านจาก `Sim` เหมือนเดิม
- **ทุกคำสั่งของผู้ใช้ผ่าน `Hmi*` ใน `uplclink.pas`** ซึ่งเลือกเองว่าจะส่งไป Simulator หรือ PLC
- การสื่อสารอยู่ใน thread แยก (`TPlcThread`) หน้าจอไม่เคยรอ network

## 2. หน่วย (unit) และหน้าที่

| Unit | หน้าที่ | จุดที่มักแก้ |
|---|---|---|
| `usim.pas` | ค่าคงที่ระบบ (`MAX_PADDLES`, `MAX_STEPS`, `DevNames`, property), engine จำลอง, history/event, ฟังก์ชัน Pattern (`DefaultPattern`, `StepMask`, `SavePatternCsv`, `LoadPatternCsv`) | ลำดับการทำงาน Auto, Pattern |
| `uplclink.pas` | `TPlcSettings`, `THmiOptions`, `DefaultTags` (register map), INI, `TPlcThread`, `TPlcLink.ApplyToSim`, `Hmi*` | เพิ่ม tag / เปลี่ยน map |
| `umain.pas` | หน้าต่างหลัก, Overview (`DrawScene`), แถบสถานะ (`StripPaint`), การ์ด live pattern | ภาพเครื่องจักร |
| `upatternform.pas` | `TPatternGrid` (ตาราง), Timeline, ปุ่ม File/PLC, Delay, Paddles installed | ตัวแก้ไข Pattern |
| `ueventsform.pas` | `TEventView` (รายการแบบ virtual), ตัวกรอง, Save CSV | การแสดงเหตุการณ์ |
| `uchartform.pas` | History chart, เมนู Add signal, Save PNG | กราฟ |
| `udeviceform.pas` | หน้าต่างอุปกรณ์ | ปุ่มคำสั่ง |
| `uhwconfigform.pas` | Hardware Config (เหมือน HMI1) | — |
| `uwidgets.pas` | `TSimButton`, `TSimSegment`, `TSimPanel`, `TSimLabel`, `TSimSpin`, `TSimToggle` + `NewButton/NewLabel/NewSpin/NewPanel` | widget ใหม่ |
| `udraw.pas` | theme (`clTheme*`), `DrawCard`, `DrawIcon`, `DrawHatch`, `DrawScrollBar`, รูปมอเตอร์/blower, V* (พิกัด design ของ Overview) | สี / ไอคอน |
| `ulog.pas` | ไฟล์ log รายวัน, `ExportEventsCsv` | รูปแบบ log |
| `umodbus.pas`, `us7.pas` | client Modbus TCP / S7 (ไม่ได้แก้จาก HMI1) | — |

## 3. รูปแบบไฟล์

### 3.1 `FluffSiloHMI2.ini` (ข้างไฟล์ .exe)

```ini
[PLC]
Protocol=S7
Host=192.168.1.10
Port=102
UnitId=1
S7Rack=0
S7Slot=1
S7ConnType=1
TimeoutMs=1000
PollMs=200
PulseMs=500
AddrBase=0
WordSwap=0
MaxGap=0
AutoConnect=0
StartInPlc=0
[HMI]
SimPaddleCount=7
LogToFile=1
PatternDir=
[Tags]
Blower01.AutoStart=COIL,100,-1,BOOL,1,1,DB10.DBX0.0
```

| ค่า | ความหมาย |
|---|---|
| `Protocol` | `Modbus` หรือ `S7` |
| `S7ConnType` | 1 = PG, 2 = OP, 3 = S7 Basic |
| `SimPaddleCount` | จำนวน Paddle ในโหมด Simulation (1..7) |
| `LogToFile` | 1 = เขียน event log ลงไฟล์ |
| `PatternDir` | โฟลเดอร์ล่าสุดที่ใช้กับไฟล์ Pattern |
| `[Tags]` | `Key=Area,Address,Bit,Type,Scale,Enabled,S7Address` (TIniFile ไม่รองรับ comment ท้ายบรรทัด) |

### 3.2 ไฟล์ Pattern (`*.csv`)

```
# FluffSilo HMI2 Paddle Pattern - <ข้อความ>
Step;Paddle01;Paddle02;Paddle03;Paddle04;Paddle05;Paddle06;Paddle07;Time_s
1;1;0;0;0;0;0;0;8.0
2;0;0;0;0;0;0;0;2.0
```

- บรรทัดที่ขึ้นต้นด้วย `#` และบรรทัดหัวตาราง `Step;...` ถูกข้าม
- 1 = RUN, 0 = ไม่ทำงาน; ทุก Paddle เป็น 0 = พัก (Pause)
- Time หน่วยวินาที ทศนิยม 1 ตำแหน่ง ช่วง 0.5..600.0 (นอกช่วงจะถูกปรับ)
- ใช้ `,` แทน `;` ได้ถ้าไม่มี `;` ในบรรทัด (Excel บาง locale), ใช้ `,` เป็นจุดทศนิยมได้
- สูงสุด 20 step (เกินจะแจ้ง error)

### 3.3 Event log `logs\HMI2_yyyymmdd.log`

แยกด้วย TAB: `yyyy-mm-dd hh:nn:ss.zzz  sim-time  signal-id  value(1/0)  text`
- signal-id = -1 คือข้อความ (คำสั่ง, sequencer, PLC link), ≥ 0 คือ `dev×10 + prop` หรือ `90 + system`

### 3.4 Events CSV (Save CSV) และ Register map CSV

- Events: `Clock;SimTime;Signal;Value;Text`
- Register map (Export/Import ใน HW Config, `docs/RegisterMap_Default.csv`):
  `Key;Group;Access;Area;Address;Bit;Type;Scale;Enabled;S7Address;Description`

## 4. ขยายระบบ

### 4.1 เพิ่มจำนวน Paddle / Step สูงสุด

HMI:
1. `usim.pas`: `MAX_PADDLES`, `MAX_STEPS`, `DevNames` (DEV_COUNT คำนวณจาก MAX_PADDLES)
2. `uplclink.pas` → `DefaultTags`: ช่วง address จะชนกันเมื่อเกิน 10 อุปกรณ์ (coil 100+dev×10 ถึง 199) หรือเกิน 20 step (HR 21..40 / 41..60) — ต้องย้ายช่วง address และ offset S7 ให้ตรงกับ DB ใหม่
3. `upatternform.pas`: `PADDLE_COLORS` ต้องมีครบทุก Paddle, ความกว้างคอลัมน์ `PAD_W`
4. `umain.pas`: `PADDLE_TOP/PADDLE_BOTTOM` (ระยะห่างขั้นต่ำ ~55 px ใน design เพื่อไม่ให้ข้อความทับกัน)
5. Mask เป็น Int (15 bit ใช้ได้) ถ้าเกิน 15 Paddle ต้องเปลี่ยนเป็น DInt / 2 word

PLC (`PLC2_S7-1200`): `DB_HMI` (array size), `FB_PaddlePattern`, `FC_StepBlocked`, `FC_ValidateParams`, `FC_LoadDefaults`, `FB_FluffSilo` (สร้างใหม่ด้วย `PLC2_S7-1200/tools/gen_fb_fluffsilo.py`), tag table, `DB_Sim`

แล้ว **export map ใหม่** (`--export-map docs/RegisterMap_Default.csv`) และรันการตรวจในหัวข้อ 6

### 4.2 เพิ่ม tag ใหม่

1. เพิ่มใน `DefaultTags` (Key, Group, Modbus address, S7 address)
2. เพิ่มตัวแปร index (`TagXxx`) และหาใน `IndexTags`
3. อ่านค่าใน `TPlcLink.ApplyToSim` / เขียนผ่าน `PlcWrite` ในฟังก์ชัน `Hmi*` ใหม่
4. เพิ่มตัวแปรใน `DB_HMI` ของ PLC ที่ offset ตรงกัน
5. INI เก่ายังใช้ได้ (tag ใหม่จะใช้ค่าเริ่มต้นจนกว่าจะบันทึก)

### 4.3 เพิ่มหน้าต่างใหม่

- สร้าง `TForm.CreateNew` + `Color := clThemeBg` แล้วใช้ `NewPanel`/`NewButton`/`NewSpin`/`NewLabel`
- ข้อมูลภายใน `TSimPanel` วาดเพิ่มได้ผ่าน `OnPaintBody` (ใช้ `Panel.Bmp`)
- เรียก refresh จาก `TMainForm.TimerTick` (ดู `RefreshPatternForm`, `RefreshEventsForm`)

### 4.4 Widget

- control ที่มีพื้นหลังโปร่ง (`TSimButton`, `TSimSegment`, `TSimLabel`, `TSimToggle`) เป็น `TGraphicControl` วาดลง bitmap โปร่งใสแล้ว alpha-blend
- control ที่รับคีย์บอร์ด (`TSimSpin`, `TPatternGrid`, `TEventView`) เป็น `TCustomControl` + `DoubleBuffered` และไม่ลบพื้นหลัง (`EraseBackground` ว่าง) เพื่อไม่ให้กระพริบ
- การตั้งค่า `Value` / `ItemIndex` / `Checked` จากโค้ด **ไม่** เรียก `OnChange` (ป้องกัน loop เวลาอ่านค่าจาก PLC)

## 5. ข้อตกลงที่ต้องรักษาไว้

- Overview ใช้พิกัด design 1000×740 (`DW`, `DH`) ฟังก์ชัน `V*` แปลงตาม scale ของหน้าต่าง
- คำสั่ง pulse: HMI เขียน 1 แล้ว thread เขียน 0 เองหลัง `PulseMs`; ตอนหยุด link จะไม่ทิ้ง bit ค้าง
- ApplyToSim ข้ามการอ่าน parameter จาก snapshot ที่เก่ากว่าคำสั่งเขียนล่าสุด (`paramsFresh`) เพื่อไม่ให้ค่าบนจอเด้งกลับ
- `TPattern` เก็บ bit ครบ 7 Paddle เสมอ ส่วนการแสดงผล/ตัดสินใช้เฉพาะ Paddle ที่ติดตั้ง (`Sim.PaddleCount`)

## 6. เครื่องมือตรวจสอบ

| เครื่องมือ | ตรวจอะไร |
|---|---|
| `tools/linktest2.lpr` | PLC link ทั้ง Modbus และ S7 กับ emulator (อ่าน, เขียน Pattern 20 step, PaddleCount, คำสั่ง, E-Stop, CSV) |
| `tools/plc_emulator2.py` | PLC จำลอง อ่าน map จาก `docs/RegisterMap_Default.csv` |
| `--export-map` | สร้าง CSV ของ map ค่าเริ่มต้นจากโค้ด (ใช้เทียบกับ DB_HMI ของ PLC) |
| `PLC2_S7-1200/tools/check_plc2.py` | ตรวจโปรแกรม PLC กับ HMI2: `python -I PLC2_S7-1200/tools/check_plc2.py <โฟลเดอร์ FluffSiloSystem>` |
| `PLC2_S7-1200/tools/gen_fb_fluffsilo.py` | สร้าง `12_FB_FluffSilo.scl` (การเรียก FB_Motor 9 ตัว) |

`check_plc2.py` ตรวจ:
- ทุก symbol ใน SCL มีอยู่จริง, keyword เปิด/ปิดครบ, ทุก tag ถูกใช้
- คำนวณ offset ของ `DB_HMI` ตามกฎ standard access ของ S7 แล้วเทียบกับ 204 address ใน `RegisterMap_Default.csv`
- การต่อสาย 9 อุปกรณ์ใน `FB_FluffSilo` (DevCmd index, I/O tag, PaddleCmd, Installed, Status, Run)
- `DB_Sim` / `FC_SimInputs`

## 7. งานที่เหลือ / แนวทางต่อ

- ทดสอบกับ CPU จริงหรือ PLCSIM Advanced (ยังไม่ได้ compile ใน TIA Portal)
- `FluffSiloPanel` (virtual local panel) รองรับ 9 มอเตอร์แล้ว (*Paddles used* 1..7) — ทดสอบกับ emulator เท่านั้น
- Hardware Config ยังเป็น LCL control มาตรฐาน (หน้าต่างตั้งค่าทางวิศวกรรม) — แปลงเป็น BGRABitmap ได้ถ้าต้องการ
- Recipe: บันทึก Delay พร้อม Pattern ในไฟล์เดียว
- การแจ้งเตือน (alarm list ที่ต้อง acknowledge) แยกจาก Event log
