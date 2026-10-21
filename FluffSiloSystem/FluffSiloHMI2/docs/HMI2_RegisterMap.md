# FluffSilo HMI2 — Default Register Map

รายการเต็มทุก tag (204 tag) อยู่ใน [`RegisterMap_Default.csv`](RegisterMap_Default.csv)
ไฟล์นี้สร้างจากโปรแกรมด้วย `FluffSiloHMI2.exe --export-map RegisterMap_Default.csv`
และใช้ **Import CSV** ใน Hardware Config ได้ทันที

- อุปกรณ์ (dev): 0 = Blower01, 1 = Screw01, 2..8 = Paddle01..07
- Property (prop): 0 AutoStart, 1 AutoStop, 2 Interlock, 3 ManualStart, 4 ManualStop, 5 Enable, 6 Disable, 7 Fault, 8 E-Stop, 9 Running
- คำสั่งอุปกรณ์ (cmd): 0 ManualStart, 1 ManualStop, 2 ReturnAuto, 3 Enable, 4 Disable, 5 ResetFault
- คำสั่งแบบ **pulse**: HMI เขียน 1 แล้วเขียน 0 หลัง *Command pulse* (ค่าเริ่มต้น 500 ms) — PLC ต้องตรวจขอบขาขึ้น

## 1. สรุป

| กลุ่ม | Modbus (offset, Address base 0) | Siemens S7 (DB10, non-optimized) | R/W |
|---|---|---|---|
| สถานะอุปกรณ์ | Coil **100 + dev×10 + prop** (100..189) | **DBX(dev×2 + prop÷8).(prop mod 8)** (DBB0..17) | R |
| สถานะระบบ AutoMode, ExtRequest, PatternActive, EStop | Coil 200..203 | DBX18.0..18.3 | R |
| คำสั่งหลัก AutoStart, AutoStop, EStop, ResetEStop, ExtRequest | Coil 210..214 | DBX20.0..20.4 | W (ExtRequest = คงค่า 1/0) |
| คำสั่งอุปกรณ์ | Coil **300 + dev×10 + cmd** (300..385) | **DBX(22 + dev).cmd** (DBB22..30) | W pulse |
| Delay[0..5] (×0.1 s) | HR 0..5 | DBW32..42 | RW |
| Pattern.CurrentStep (1..20, 0 = ไม่ทำงาน) | HR 10 | DBW44 | R |
| Pattern.StepElapsed (×0.1 s) | HR 11 | DBW46 | R |
| Silo.Level (×0.1 %) | HR 12 | DBW48 | R |
| **Config.PaddleCount** (1..7) | HR 15 | DBW52 | RW |
| Pattern.StepCount (0..20) | HR 20 | DBW56 | RW |
| Pattern.Step01..20.Mask | HR 21..40 | DBW58..96 | RW |
| Pattern.Step01..20.Time (×0.1 s) | HR 41..60 | DBW98..136 | RW |

**Mask**: bit0 = Paddle01, bit1 = Paddle02 … bit6 = Paddle07, 0 = พัก (Pause) — ค่า 0..127
ขนาด DB10 = **138 byte**

## 2. สถานะอุปกรณ์

### Modbus coil

| prop | Blower01 | Screw01 | P01 | P02 | P03 | P04 | P05 | P06 | P07 |
|---|---|---|---|---|---|---|---|---|---|
| 0 Auto Start (L1) | 100 | 110 | 120 | 130 | 140 | 150 | 160 | 170 | 180 |
| 1 Auto Stop (L2) | 101 | 111 | 121 | 131 | 141 | 151 | 161 | 171 | 181 |
| 2 Interlock (L2) | 102 | 112 | 122 | 132 | 142 | 152 | 162 | 172 | 182 |
| 3 Manual Start (L3) | 103 | 113 | 123 | 133 | 143 | 153 | 163 | 173 | 183 |
| 4 Manual Stop (L4) | 104 | 114 | 124 | 134 | 144 | 154 | 164 | 174 | 184 |
| 5 Enable (L5) | 105 | 115 | 125 | 135 | 145 | 155 | 165 | 175 | 185 |
| 6 Disable (L5) | 106 | 116 | 126 | 136 | 146 | 156 | 166 | 176 | 186 |
| 7 Fault (L6) | 107 | 117 | 127 | 137 | 147 | 157 | 167 | 177 | 187 |
| 8 E-Stop (L6) | 108 | 118 | 128 | 138 | 148 | 158 | 168 | 178 | 188 |
| 9 Running | 109 | 119 | 129 | 139 | 149 | 159 | 169 | 179 | 189 |

### S7 (DB10)

| prop | Blower01 | Screw01 | P01 | P02 | P03 | P04 | P05 | P06 | P07 |
|---|---|---|---|---|---|---|---|---|---|
| 0 Auto Start | DBX0.0 | DBX2.0 | DBX4.0 | DBX6.0 | DBX8.0 | DBX10.0 | DBX12.0 | DBX14.0 | DBX16.0 |
| 3 Manual Start | DBX0.3 | DBX2.3 | DBX4.3 | DBX6.3 | DBX8.3 | DBX10.3 | DBX12.3 | DBX14.3 | DBX16.3 |
| 6 Disable | DBX0.6 | DBX2.6 | DBX4.6 | DBX6.6 | DBX8.6 | DBX10.6 | DBX12.6 | DBX14.6 | DBX16.6 |
| 7 Fault | DBX0.7 | DBX2.7 | DBX4.7 | DBX6.7 | DBX8.7 | DBX10.7 | DBX12.7 | DBX14.7 | DBX16.7 |
| 8 E-Stop | DBX1.0 | DBX3.0 | DBX5.0 | DBX7.0 | DBX9.0 | DBX11.0 | DBX13.0 | DBX15.0 | DBX17.0 |
| 9 Running | DBX1.1 | DBX3.1 | DBX5.1 | DBX7.1 | DBX9.1 | DBX11.1 | DBX13.1 | DBX15.1 | DBX17.1 |

(property 1, 2, 4, 5 อยู่ที่ bit .1, .2, .4, .5 ของ byte แรกของอุปกรณ์)

## 3. คำสั่งอุปกรณ์

| cmd | Blower01 | Screw01 | P01 | P02 | P03 | P04 | P05 | P06 | P07 |
|---|---|---|---|---|---|---|---|---|---|
| Modbus coil +0..+5 | 300 | 310 | 320 | 330 | 340 | 350 | 360 | 370 | 380 |
| S7 byte (bit = cmd) | DBX22.x | DBX23.x | DBX24.x | DBX25.x | DBX26.x | DBX27.x | DBX28.x | DBX29.x | DBX30.x |

ใน PLC (`DB_HMI.DevCmd`) index = dev×8 + cmd → bit 6, 7 ของแต่ละ byte สำรองไว้

## 4. Paddle ที่ไม่ได้ติดตั้ง

- `Config.PaddleCount` = จำนวน Paddle ที่ติดตั้ง (1..7) HMI เขียนได้จากหน้าต่าง Paddle Patterns → *Paddles installed*
- PLC รายงานสถานะของ Paddle ที่ไม่ได้ติดตั้งเป็น **Disable = 1** และค่าอื่นเป็น 0
- PLC ตัด bit ของ Paddle ที่ไม่ได้ติดตั้งออกจาก Mask (FC_ValidateParams)
- HMI ซ่อน Paddle เหล่านั้นจาก Overview, แถบสถานะ, เมนู Chart และแสดงเป็นช่องลายขีดในตาราง Pattern

## 5. การเขียน Pattern (Pattern > PLC)

1. ถ้าจำนวน step ใหม่ **น้อยกว่า** ของเดิม: เขียน `StepCount` ก่อน
2. เขียน `Mask` และ `Time` เฉพาะ step ที่ต่างจากค่าที่อ่านจาก PLC
3. ถ้าจำนวน step ใหม่ **มากกว่าหรือเท่าเดิม**: เขียน `StepCount` เป็นค่าสุดท้าย

ค่าที่ HMI แสดงจะอ่านกลับจาก PLC ทุกรอบ poll (ไม่ใช้ค่าที่อ่านมาก่อนที่คำสั่งเขียนของตัวเองจะถึง PLC)
