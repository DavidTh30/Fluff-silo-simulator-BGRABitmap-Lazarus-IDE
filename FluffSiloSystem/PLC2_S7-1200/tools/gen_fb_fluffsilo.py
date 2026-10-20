"""Generate 12_FB_FluffSilo.scl (Blower01, Screw01, Paddle01..P).

Usage: python -I gen_fb_fluffsilo.py ..\12_FB_FluffSilo.scl   (P = 7, change P below for more paddles;
note: the Installed expressions are written as (#nPad > k))
"""
import sys
out = sys.argv[1]
P = 7
L = []
a = L.append
a("""// =============================================================================
// Fluff Silo System 2 - S7-1200
// FB "FB_FluffSilo" : top level, called once per scan from OB1 with "iDB_FluffSilo"
//
//   I/O (PLC tags)  ->  E-Stop latch, External Request, parameters
//                   ->  FB_Sequencer -> FB_PaddlePattern -> 9 x FB_Motor  ->  outputs
//                   ->  DB_HMI status for FluffSilo HMI2
//
// Devices: Blower01, Screw01, Paddle01..07. DB_HMI.Cfg.PaddleCount (1..7) paddles are
// installed; the others never run (FB_Motor.Installed = FALSE) and their inputs may be unwired.
//
// Configuration: static variables marked [CFG] - change their start values in
// "iDB_FluffSilo" (or online). See README section "Options".
// =============================================================================
FUNCTION_BLOCK "FB_FluffSilo"
TITLE = 'Fluff Silo System 2'
{ S7_Optimized_Access := 'TRUE' }
VERSION : 0.1
   VAR
      FbTimeout : Time := T#3S;              // [CFG] running feedback supervision
      SafeInterlock : Bool := FALSE;         // [CFG] TRUE: Interlock also blocks Manual Start
      RestartAfterBlowerTrip : Bool := TRUE; // [CFG] FALSE: a Blower01 trip ends Auto mode
      FillOnLevel : Real := 25.0;            // [CFG] % - Fill_Request ON below this level
      FillOffLevel : Real := 90.0;           // [CFG] % - Fill_Request OFF at this level
      EStopLatch : Bool;                     // E-Stop latched (until reset)
      FillReq : Bool;
      LevelPct : Real;                       // silo level 0..100 %
      LevelSensorFault : Bool;
      AnyFault : Bool;
      rtReset : R_TRIG;
      Seq : "FB_Sequencer";
      Pattern : "FB_PaddlePattern";
      Blower01 : "FB_Motor";
      Screw01 : "FB_Motor";""")
for k in range(1, P + 1):
    a(f'      Paddle{k:02d} : "FB_Motor";')
a("""   END_VAR

   VAR_TEMP
      resetPulse : Bool;
      extReq : Bool;
      cmdStart : Bool;
      cmdStop : Bool;
      avail : Array[0..6] of Bool;
      tBlowerToScrew : Time;
      tReqHold : Time;
      tScrewToPaddle : Time;
      tReqOffScrewStop : Time;
      tScrewTripBlower : Time;
      tAutoStopBlower : Time;
      nPad : Int;
      i : Int;
   END_VAR


BEGIN
	REGION E-Stop and reset
	    // Hardware E-Stop (safety relay, NC) or HMI E-Stop -> latched until Reset
	    // NOTE: the safety relay must switch off the contactors by hardware.
	    //       The PLC only follows it (category / PL according to the risk assessment).
	    #rtReset(CLK := "PB_Reset" OR "DB_HMI".Cmd.ResetEStop);
	    #resetPulse := #rtReset.Q;
	    IF NOT "EStop_OK" OR "DB_HMI".Cmd.EStop THEN
	        #EStopLatch := TRUE;
	    END_IF;
	    IF #resetPulse AND "EStop_OK" AND NOT "DB_HMI".Cmd.EStop THEN
	        #EStopLatch := FALSE;
	    END_IF;
	END_REGION

	REGION External Request and parameters
	    // External Request = hardware input from the consumer OR the HMI button
	    #extReq := "ExtRequest_In" OR "DB_HMI".Cmd.ExtRequest;

	    "FC_ValidateParams"();
	    #nPad := "DB_HMI".Cfg.PaddleCount;   // 1..7 after FC_ValidateParams
	    #tBlowerToScrew := "FC_TenthsToTime"(Tenths := "DB_HMI".Delay[0]);
	    #tReqHold := "FC_TenthsToTime"(Tenths := "DB_HMI".Delay[1]);
	    #tScrewToPaddle := "FC_TenthsToTime"(Tenths := "DB_HMI".Delay[2]);
	    #tReqOffScrewStop := "FC_TenthsToTime"(Tenths := "DB_HMI".Delay[3]);
	    #tScrewTripBlower := "FC_TenthsToTime"(Tenths := "DB_HMI".Delay[4]);
	    #tAutoStopBlower := "FC_TenthsToTime"(Tenths := "DB_HMI".Delay[5]);
	END_REGION

	REGION Auto sequence
	    // panel Auto Stop push button is NC: wire break = stop, start refused while pressed
	    #cmdStop := "DB_HMI".Cmd.AutoStop OR NOT "PB_AutoStop";
	    #cmdStart := ("DB_HMI".Cmd.AutoStart OR "PB_AutoStart") AND NOT #cmdStop;

	    #Seq(CmdAutoStart := #cmdStart,
	         CmdAutoStop := #cmdStop,
	         EStopActive := #EStopLatch,
	         ExtRequest := #extReq,
	         BlowerRunning := "Blower01_FB",
	         ScrewRunning := "Screw01_FB",
	         TBlowerToScrew := #tBlowerToScrew,
	         TReqHold := #tReqHold,
	         TScrewToPaddle := #tScrewToPaddle,
	         TReqOffScrewStop := #tReqOffScrewStop,
	         TScrewTripBlower := #tScrewTripBlower,
	         TAutoStopBlower := #tAutoStopBlower,
	         RestartAfterBlowerTrip := #RestartAfterBlowerTrip);
	END_REGION

	REGION Paddle Patterns
	    // availability of the paddles from the previous scan (not installed = not available)""")
for k in range(P):
    a(f'	    #avail[{k}] := #Paddle{k+1:02d}.Available;')
a("""
	    #Pattern(Enable := #Seq.PatternCmd,
	             Available := #avail,
	             StepCount := "DB_HMI".Pattern.StepCount,
	             Mask := "DB_HMI".Pattern.Mask,
	             StepTime := "DB_HMI".Pattern.StepTime);
	END_REGION

	REGION Devices
	    // DevCmd index = device * 8 + command
	    // command: 0 ManualStart, 1 ManualStop, 2 ReturnAuto, 3 Enable, 4 Disable, 5 ResetFault""")


def call(name, idx, auto_start, auto_stop, interlock, installed):
    b = idx * 8
    pad = ' ' * (len(name) + 2)
    a(f'	    #{name}(Installed := {installed},')
    rows = [
        ('AutoStart', auto_start), ('AutoStop', auto_stop), ('Interlock', interlock), ('EStop', '#EStopLatch'),
        ('CmdManStart', f'"DB_HMI".DevCmd[{b}]'), ('CmdManStop', f'"DB_HMI".DevCmd[{b + 1}]'),
        ('CmdReturnAuto', f'"DB_HMI".DevCmd[{b + 2}]'), ('CmdEnable', f'"DB_HMI".DevCmd[{b + 3}]'),
        ('CmdDisable', f'"DB_HMI".DevCmd[{b + 4}]'), ('CmdResetFault', f'"DB_HMI".DevCmd[{b + 5}] OR #resetPulse'),
        ('Feedback', f'"{name}_FB"'), ('OverloadOK', f'"{name}_OL"'), ('FbTimeout', '#FbTimeout'),
        ('SafeInterlock', '#SafeInterlock')]
    for i, (p, v) in enumerate(rows):
        end = ');' if i == len(rows) - 1 else ','
        a(f'	    {pad}{p} := {v}{end}')
    a('')


call('Blower01', 0, '#Seq.BlowerAutoStart', '#Seq.BlowerAutoStop', 'FALSE', 'TRUE')
call('Screw01', 1, '#Seq.ScrewAutoStart', '#Seq.ScrewAutoStop', '#Seq.ScrewInterlock', 'TRUE')
for k in range(P):
    call(f'Paddle{k+1:02d}', 2 + k, f'#Pattern.PaddleCmd[{k}]', '#Seq.PaddleAutoStop', '#Seq.PaddleInterlock',
         f'(#nPad > {k})')
L[-1:] = []
a("""	END_REGION

	REGION Outputs
	    "Blower01_Run" := #Blower01.Run;
	    "Screw01_Run" := #Screw01.Run;""")
for k in range(1, P + 1):
    a(f'	    "Paddle{k:02d}_Run" := #Paddle{k:02d}.Run;')
a("""
	    #AnyFault := #Blower01.Status.Fault OR #Screw01.Status.Fault""")
for k in range(1, P + 1):
    end = ';' if k == P else ''
    a(f'	                 OR #Paddle{k:02d}.Status.Fault{end}')
a("""	    "Lamp_AutoRun" := #Seq.AutoMode;
	    "Lamp_Fault" := #AnyFault OR #LevelSensorFault;
	    "Lamp_EStop" := #EStopLatch;
	END_REGION

	REGION Silo level and fill request
	    #LevelPct := "FC_ScaleAnalog"(Raw := "Silo_Level_AI", EngLow := 0.0, EngHigh := 100.0,
	                                  Fault => #LevelSensorFault);
	    // request raw material for the silo (hysteresis), never on a broken sensor
	    IF #LevelSensorFault THEN
	        #FillReq := FALSE;
	    ELSIF #LevelPct < #FillOnLevel THEN
	        #FillReq := TRUE;
	    ELSIF #LevelPct >= #FillOffLevel THEN
	        #FillReq := FALSE;
	    END_IF;
	    "Fill_Request" := #FillReq;
	END_REGION

	REGION Status to HMI
	    "DB_HMI".Dev[0] := #Blower01.Status;
	    "DB_HMI".Dev[1] := #Screw01.Status;""")
for k in range(1, P + 1):
    a(f'	    "DB_HMI".Dev[{k + 1}] := #Paddle{k:02d}.Status;')
a("""
	    "DB_HMI".Sys.AutoMode := #Seq.AutoMode;
	    "DB_HMI".Sys.ExtRequest := #extReq;
	    "DB_HMI".Sys.PatternActive := #Pattern.Active;
	    "DB_HMI".Sys.EStop := #EStopLatch;

	    "DB_HMI".Proc.CurrentStep := #Pattern.CurrentStep;
	    "DB_HMI".Proc.StepElapsed := #Pattern.ElapsedTenths;
	    "DB_HMI".Proc.SiloLevel := REAL_TO_INT(#LevelPct * 10.0);
	END_REGION

	REGION Acknowledge HMI pulse commands
	    // every command acts once; Cmd.ExtRequest is a maintained signal and stays
	    "DB_HMI".Cmd.AutoStart := FALSE;
	    "DB_HMI".Cmd.AutoStop := FALSE;
	    "DB_HMI".Cmd.EStop := FALSE;
	    "DB_HMI".Cmd.ResetEStop := FALSE;
	    FOR #i := 0 TO 71 DO
	        "DB_HMI".DevCmd[#i] := FALSE;
	    END_FOR;
	END_REGION

END_FUNCTION_BLOCK
""")
open(out, 'w', encoding='utf-8', newline='\n').write('\n'.join(L))
print('lines', len('\n'.join(L).splitlines()))
