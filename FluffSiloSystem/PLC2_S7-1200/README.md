# Fluff Silo System 2 — โปรแกรม PLC Siemens S7-1200 (SCL)

> โปรแกรมคู่กับ **FluffSilo HMI2** — Blower01, Screw01, **Paddle01..07** และ **Paddle Patterns 20 step**
> สร้างต่อจาก `PLC_S7-1200` (logic เดิมทุกอย่าง: Priority L1..L6, Auto sequence, Interlock, Delay, Pattern)
> `DB_HMI` (DB10) มี layout ตรงกับ **Default S7 Map** ของ HMI2 ทุก byte

---

## 1. ไฟล์ทั้งหมด

| ไฟล์ | ชนิด | หน้าที่ |
|---|---|---|
| `01_PLC_Tags.csv` | PLC tag table | I/O ทั้งหมด 37 tag (copy/paste ลงตาราง tag ของ TIA Portal) |
| `02_UDT_typeDevStatus.scl` | UDT | 10 property ของอุปกรณ์ 1 ตัว (2 byte) — เหมือนเดิม |
| `03_DB_HMI.scl` | Global DB (**DB10**, non-optimized, retain) | แลกข้อมูลกับ HMI2: สถานะ 9 อุปกรณ์, คำสั่ง, Delay, จำนวน Paddle, Pattern 20 step (138 byte) |
| `04_FC_TenthsToTime.scl` | FC | 0.1 s (Int) → TIME — เหมือนเดิม |
| `05_FC_ScaleAnalog.scl` | FC | analog 0..27648 → % — เหมือนเดิม |
| `06_FC_ValidateParams.scl` | FC | จำกัดช่วงค่า: Delay, PaddleCount 1..7, StepCount 0..20, Mask 0..127 (ตัด bit ของ Paddle ที่ไม่ได้ติดตั้ง), StepTime 0.5..600 s |
| `07_FC_LoadDefaults.scl` | FC | ค่าเริ่มต้น: Delay 7/3/3/3/5/5 s, 7 Paddle, Pattern 14 step (P1..P7 ตัวละ 8 s + พัก 2 s) |
| `08_FC_StepBlocked.scl` | FC | step ถูก block เมื่อ Paddle ใน step ทำงานไม่ได้เลย (7 Paddle) |
| `09_FB_Motor.scl` | FB | อุปกรณ์ 1 ตัว + input **Installed** (FALSE = ไม่ทำงาน, ไม่ตรวจ fault, HMI เห็นเป็น Disable) |
| `10_FB_Sequencer.scl` | FB | ลำดับ Auto Start / Auto Stop / Trip / E-Stop — เหมือนเดิม |
| `11_FB_PaddlePattern.scl` | FB | Paddle Patterns สูงสุด **20 step × 7 Paddle** |
| `12_FB_FluffSilo.scl` | FB | โปรแกรมหลัก: I/O + ทุก FB + 9 × FB_Motor + DB_HMI |
| `13_DB_iDB_FluffSilo.scl` | Instance DB | instance ของ FB_FluffSilo (non-retain) |
| `14_OB1_Main.scl` | OB1 | `"FC_SimInputs"()` แล้ว `"iDB_FluffSilo"()` |
| `15_OB100_Startup.scl` | OB100 | ล้างคำสั่งค้าง, โหลดค่าเริ่มต้นเมื่อ retain หาย |
| `16_DB_Sim.scl` | Global DB (**DB11**, non-optimized, non-retain) | input จำลอง 23 bit + `SimMode` (ดูหัวข้อ 7) |
| `17_FC_SimInputs.scl` | FC | เมื่อ `SimMode` = 1 คัดลอก `DB_Sim` ทับ `%I` ต้น scan |
| `tools/check_plc2.py` | Python | ตรวจความสอดคล้องกับ HMI2 (หัวข้อ 9) |
| `tools/gen_fb_fluffsilo.py` | Python | สร้าง `12_FB_FluffSilo.scl` ใหม่ (ถ้าเปลี่ยนจำนวน Paddle) |

---

## 2. Hardware

| รายการ | รุ่น (แนะนำ) | หมายเหตุ |
|---|---|---|
| CPU | **CPU 1214C DC/DC/RLY** (6ES7214-1HG40-0XB0), FW ≥ V4.2 | DI 14 (I0.0..I1.5), DQ relay 10 (Q0.0..Q1.1), AI 2 |
| Signal module | **SM 1223 DI16 × 24 VDC / DQ16 relay** (6ES7223-1PL32-0XB0) | ใส่ slot 2 → **I8.0..I9.7** และ **Q8.0..Q9.7** |
| Safety relay | เช่น 3SK1 | ตัดไฟ contactor ทั้งหมดโดย hardware และส่งสถานะเข้า I0.0 |
| Level sensor | 0-10 V = 0-100 % | AI0 ของ CPU (IW64) |

ใช้ I/O รวม: DI 23 (เหลือ I9.1..I9.7), DQ 13 (เหลือ Q8.3..Q9.7)
ถ้าใช้ module อื่น ให้แก้แค่ address ใน tag table ไม่ต้องแก้โปรแกรม

---

## 3. I/O List

### Digital Inputs

| Address | Tag | ความหมาย | สถานะปกติ |
|---|---|---|---|
| %I0.0 | `EStop_OK` | Safety relay: วงจร E-Stop ปกติ | 1 (NC) |
| %I0.1 | `PB_AutoStart` | ปุ่ม Auto Start | NO |
| %I0.2 | `PB_AutoStop` | ปุ่ม Auto Stop | **NC** |
| %I0.3 | `PB_Reset` | ปุ่ม Reset E-Stop / Fault | NO |
| %I0.4 | `ExtRequest_In` | External Request จากเครื่องปลายทาง | 1 = ต้องการ |
| %I0.5 / %I0.6 | `Blower01_FB` / `Blower01_OL` | feedback / overload OK | NO / NC |
| %I0.7 / %I1.0 | `Screw01_FB` / `Screw01_OL` | | |
| %I1.1 / %I1.2 | `Paddle01_FB` / `Paddle01_OL` | | |
| %I1.3 / %I1.4 | `Paddle02_FB` / `Paddle02_OL` | | |
| %I1.5 / %I8.0 | `Paddle03_FB` / `Paddle03_OL` | (I8.0 บน SM 1223) | |
| %I8.1 / %I8.2 | `Paddle04_FB` / `Paddle04_OL` | | |
| %I8.3 / %I8.4 | `Paddle05_FB` / `Paddle05_OL` | | |
| %I8.5 / %I8.6 | `Paddle06_FB` / `Paddle06_OL` | | |
| %I8.7 / %I9.0 | `Paddle07_FB` / `Paddle07_OL` | | |

address ของ I0.0..I8.0 เหมือน `PLC_S7-1200` (3 Paddle) ทุกตัว

### Digital Outputs

| Address | Tag | ความหมาย |
|---|---|---|
| %Q0.0 | `Blower01_Run` | Contactor K1 |
| %Q0.1 | `Screw01_Run` | Contactor K2 |
| %Q0.2 .. %Q0.4 | `Paddle01_Run` .. `Paddle03_Run` | K3 .. K5 |
| %Q0.5 | `Lamp_AutoRun` | ไฟเขียว Auto |
| %Q0.6 | `Lamp_Fault` | ไฟแดง Fault (อุปกรณ์ใดก็ได้ หรือ level sensor) |
| %Q0.7 | `Lamp_EStop` | ไฟเหลือง E-Stop |
| %Q1.0 | `Fill_Request` | ขอเติมวัตถุดิบ (level < 25 % → ON, ≥ 90 % → OFF) |
| %Q1.1 | `Paddle04_Run` | K6 |
| %Q8.0 .. %Q8.2 | `Paddle05_Run` .. `Paddle07_Run` | K7 .. K9 (SM 1223) |

### Analog Input

| Address | Tag | ความหมาย |
|---|---|---|
| %IW64 | `Silo_Level_AI` | ระดับไซโล 0-10 V = 0-100 % |

---

## 4. โครงสร้างโปรแกรม

```
OB100 "Startup" ──► ล้างคำสั่ง HMI, FC_LoadDefaults (ถ้า retain หาย หรือ PaddleCount = 0), FC_ValidateParams

OB1 "Main" ──► "FC_SimInputs"   (ถ้า DB_Sim.SimMode = 1 : DB_Sim → %I)
           └─► "iDB_FluffSilo"  (FB_FluffSilo)
                 ├─ E-Stop latch, External Request = ExtRequest_In OR DB_HMI.Cmd.ExtRequest
                 ├─ FC_ValidateParams → nPad = DB_HMI.Cfg.PaddleCount (1..7)
                 ├─ Seq      : FB_Sequencer      (เหมือนเดิม)
                 ├─ Pattern  : FB_PaddlePattern   → PaddleCmd[0..6]  (20 step, ใช้ FC_StepBlocked)
                 ├─ Blower01, Screw01, Paddle01..07 : FB_Motor  (Paddle k: Installed := nPad > k)
                 ├─ outputs, ไฟ, FC_ScaleAnalog → Fill_Request
                 ├─ สถานะ → DB_HMI.Dev[0..8], Sys, Proc
                 └─ ล้าง bit คำสั่ง pulse (Cmd, DevCmd[0..71])
```

### Paddle ที่ไม่ได้ติดตั้ง (`Cfg.PaddleCount`)

- ตั้งจาก HMI2 (หน้าต่าง Paddle Patterns → *Paddles installed*) หรือแก้ใน `DB_HMI.Cfg.PaddleCount` (retain)
- Paddle ลำดับ > PaddleCount: `FB_Motor.Installed = FALSE` → Run = 0, ไม่ตรวจ overload / feedback (สายไม่ต้องต่อ), latch ทั้งหมดถูกล้าง, Status = Disable
- `FC_ValidateParams` ตัด bit ของ Paddle เหล่านั้นออกจาก Mask ของทุก step และ `FC_StepBlocked` ถือว่าใช้งานไม่ได้
- เมื่อเพิ่ม PaddleCount กลับ Paddle จะเริ่มแบบ Enable ไม่มี fault ค้าง

### Priority ใน FB_Motor (เหมือนเดิม)

```
Fault (L6) > E-Stop (L6) > Disable (L5) > Manual Stop (L4) > Manual Start (L3) > Auto Stop / Interlock (L2) > Auto Start (L1)
```

FaultCode: 1 = overload, 2 = ไม่มี feedback ภายใน `FbTimeout`, 3 = มี feedback ทั้งที่ไม่ได้สั่ง

---

## 5. ตัวเลือก (Options)

เหมือน `PLC_S7-1200`: `FbTimeout` (T#3S), `SafeInterlock` (FALSE), `RestartAfterBlowerTrip` (TRUE), `FillOnLevel` / `FillOffLevel` (25 / 90 %) — แก้ start value ใน `iDB_FluffSilo`

---

## 6. DB_HMI (DB10) — ใช้ร่วมกับ FluffSilo HMI2

| Offset | เนื้อหา | ทิศทาง |
|---|---|---|
| DBX0.0 – DBX17.7 | `Dev[0..8]` สถานะ 10 property ต่ออุปกรณ์ (อุปกรณ์ละ 2 byte) | PLC → HMI |
| DBX18.0 – 18.3 | `Sys`: AutoMode, ExtRequest, PatternActive, EStop | PLC → HMI |
| DBX20.0 – 20.4 | `Cmd`: AutoStart, AutoStop, EStop, ResetEStop (pulse), ExtRequest (คงค่า) | HMI → PLC |
| DBX22.0 – DBX30.7 | `DevCmd[อุปกรณ์×8 + คำสั่ง]` (72 bit) | HMI → PLC |
| DBW32 – DBW42 | `Delay[0..5]` (0.1 s) | HMI ↔ PLC |
| DBW44 / 46 / 48 | `Proc`: CurrentStep, StepElapsed (0.1 s), SiloLevel (0.1 %) | PLC → HMI |
| DBW52 | `Cfg.PaddleCount` (1..7) | HMI ↔ PLC |
| DBW56 | `Pattern.StepCount` (0..20) | HMI ↔ PLC |
| DBW58 – DBW96 | `Pattern.Mask[0..19]` (bit0 = Paddle01 .. bit6 = Paddle07) | HMI ↔ PLC |
| DBW98 – DBW136 | `Pattern.StepTime[0..19]` (0.1 s) | HMI ↔ PLC |

รายละเอียดทุก address: `FluffSiloHMI2/docs/HMI2_RegisterMap.md` และ `FluffSiloHMI2/docs/RegisterMap_Default.csv`

---

## 7. โหมดจำลอง input (DB_Sim, DB11)

ใช้หลักการเดียวกับ `PLC_S7-1200` หัวข้อ 7 (ตั้ง `"DB_Sim".SimMode` = TRUE จาก Watch table, DB เป็น non-retain)
bit DBX0.0 .. DBX1.6 **เหมือน DB_Sim ของ PLC_S7-1200 ทุกตัว** จึงใช้ FluffSilo Client Panel (5 มอเตอร์) ได้ทันที

| Offset | ตัวแปร | ไปที่ | Offset | ตัวแปร | ไปที่ |
|---|---|---|---|---|---|
| DBX0.0 | `EStop` | %I0.0 | DBX1.3 | `Paddle02_FB` | %I1.3 |
| DBX0.1 | `SelLeft` | %I0.1 `PB_AutoStart` | DBX1.4 | `Paddle02_OL` | %I1.4 |
| DBX0.2 | `SelRight` | %I0.2 `PB_AutoStop` (**กลับค่า**) | DBX1.5 | `Paddle03_FB` | %I1.5 |
| DBX0.3 | `Reset` | %I0.3 | DBX1.6 | `Paddle03_OL` | %I8.0 |
| DBX0.4 | `ExtRequest` | %I0.4 | DBX1.7 | `Paddle04_FB` | %I8.1 |
| DBX0.5 | `Blower01_FB` | %I0.5 | DBX2.0 | `Paddle04_OL` | %I8.2 |
| DBX0.6 | `Blower01_OL` | %I0.6 | DBX2.1 | `Paddle05_FB` | %I8.3 |
| DBX0.7 | `Screw01_FB` | %I0.7 | DBX2.2 | `Paddle05_OL` | %I8.4 |
| DBX1.0 | `Screw01_OL` | %I1.0 | DBX2.3 | `Paddle06_FB` | %I8.5 |
| DBX1.1 | `Paddle01_FB` | %I1.1 | DBX2.4 | `Paddle06_OL` | %I8.6 |
| DBX1.2 | `Paddle01_OL` | %I1.2 | DBX2.5 | `Paddle07_FB` | %I8.7 |
| | | | DBX2.6 | `Paddle07_OL` | %I9.0 |
| | | | DBX2.7 | สำรอง | |
| | | | **DBX3.0** | **`SimMode`** | |

> **คำเตือน** ในโหมดจำลอง PLC ไม่สนใจ input จริงรวมถึง E-Stop — ใช้กับ CPU ทดสอบหรือ PLCSIM Advanced เท่านั้น
> FluffSilo Client Panel จำลองได้ครบ 9 มอเตอร์: ใน Network Config ตั้ง **Paddles used** ให้เท่ากับ `Cfg.PaddleCount`
> และใส่ address `DB11.DBX…` ตามตารางนี้ (ดู `FluffSiloPanel/README.md` หัวข้อ 3)

---

## 8. การนำเข้า TIA Portal (V16 ขึ้นไป)

1. Add device → **CPU 1214C DC/DC/RLY** และใส่ **SM 1223 DI16/DQ16** ที่ slot 2 (ตรวจว่า address เป็น I8.0 / Q8.0)
2. CPU Properties → **Permit access with PUT/GET** = ON, ตั้ง IP
3. PLC tags → เปิด `01_PLC_Tags.csv` ใน Excel แล้ว copy คอลัมน์ Name / Data Type / Logical Address / Comment ไปวาง
4. External source files → เพิ่มไฟล์ `.scl` ทั้งหมด (02 – 17)
5. *Generate blocks from source* ตามลำดับ: **02 → 13, แล้ว 16, 17, แล้วจึง 14, 15**
6. `DB_HMI`: **Number = 10**, Optimized block access **ปิด** — ตรวจ Offset ให้ตรงหัวข้อ 6 (ขนาด 138 byte)
   `DB_Sim`: **Number = 11**, Optimized **ปิด**
7. Compile → Download → RUN
8. FluffSilo HMI2 → HW Config → Siemens S7, IP ของ PLC, Rack 0 / Slot 1 → Apply & Close → Data source PLC → CONNECT

> ถ้าเคยใช้ `PLC_S7-1200` ใน CPU เดิม: `DB_HMI` เปลี่ยน layout ทั้งหมด ต้อง download DB ใหม่ (ค่า retain จะถูกโหลดค่าเริ่มต้นจาก OB100)

---

## 9. สิ่งที่ตรวจสอบแล้ว และสิ่งที่ยังไม่ได้ตรวจ

**ตรวจแล้ว** (`python -I tools/check_plc2.py <โฟลเดอร์ FluffSiloSystem>` → ALL OK)
- ทุก symbol ที่อ้างใน SCL มีอยู่จริง และทุก tag ใน tag table (37) ถูกใช้, ไม่มี address ซ้ำ
- keyword เปิด/ปิด (`IF/END_IF`, `FOR`, `REGION`, `STRUCT`, `VAR` ฯลฯ) และวงเล็บครบทุกไฟล์
- **Layout ของ DB_HMI** คำนวณตามกฎ standard access (Bool เรียงเป็น bit, Int/Struct/Array/UDT เริ่มที่ byte คู่) → ขนาด 138 byte และตรงกับ **204 address** ใน `RegisterMap_Default.csv` ของ HMI2 ทุกตัว (ทั้ง offset และชนิด Bool/Word)
- `FB_FluffSilo`: ทั้ง 9 อุปกรณ์ใช้ DevCmd index ถูกต้อง (อุปกรณ์×8 + 0..5), I/O tag ถูกตัว, Paddle k ใช้ `PaddleCmd[k]` และ `Installed := (nPad > k)`, Status → `Dev[k]`, Run → output ถูกตัว
- `DB_Sim`: offset ตรงกับ comment ทุกตัว, 15 bit แรกเหมือน DB_Sim ของ `PLC_S7-1200`, `FC_SimInputs` คัดลอกครบ 23 input
- Logic เทียบกับ PLC emulator (`FluffSiloHMI2/tools/plc_emulator2.py`) ผ่าน HMI2 link test ทั้ง Modbus/S7 (emulator เป็นสำเนาแบบย่อของ logic นี้ ไม่ใช่ตัว SCL)

**ยังไม่ได้ตรวจ**
- **ยังไม่ได้ compile ใน TIA Portal** (เครื่องนี้ไม่มี TIA) ถ้าเจอ error ให้ส่งข้อความ error มาแก้
- จุดที่ควรดูตอน compile: `SHL(IN := #bit, N := 1)`, การส่ง Array ทั้งก้อนเข้า FB (`Mask := "DB_HMI".Pattern.Mask`), parameter ที่เป็น expression `(#nPad > k)`
- ยังไม่ได้ทดสอบกับ CPU จริงหรือ PLCSIM

---

## 10. ข้อควรระวังด้านความปลอดภัย

- E-Stop ต้องเป็นวงจร **hardware** (safety relay ตัดไฟ contactor) PLC มาตรฐานไม่ใช่ safety PLC
- `iDB_FluffSilo` เป็น NON_RETAIN โดยตั้งใจ: ไฟดับแล้วกลับมาเครื่องไม่สตาร์ทเอง
- การลด `PaddleCount` ขณะเครื่องทำงานจะหยุด Paddle ที่ถูกตัดออกทันที
- ก่อนใช้งานจริง ควรตั้ง `SafeInterlock = TRUE` และ `RestartAfterBlowerTrip = FALSE`
- `DB_Sim.SimMode` = 1 ทำให้ไม่สนใจ input จริง — ลบหรือปิดการเรียก `FC_SimInputs` ก่อนส่งมอบเครื่อง
