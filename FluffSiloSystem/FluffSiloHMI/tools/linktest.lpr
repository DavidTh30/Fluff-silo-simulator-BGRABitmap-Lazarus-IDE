program linktest;

{ Headless integration test of uPlcLink + uModbus / uS7 against tools/plc_emulator.py
  (default register map).  Usage: linktest [modbus|s7] [host] [port] }

{$mode objfpc}{$H+}

uses
  Classes, SysUtils, Math, uSim, uModbus, uS7, uPlcLink;

var
  Fails: Integer = 0;

procedure Run(Seconds: Double);
var
  t0, last, now: QWord;
begin
  t0 := GetTickCount64;
  last := t0;
  repeat
    Sleep(40);
    now := GetTickCount64;
    Link.Update;
    Sim.StepExternal((now - last) / 1000);
    last := now;
  until now - t0 >= Seconds * 1000;
end;

procedure Check(const What: string; Ok: Boolean);
begin
  if Ok then
    WriteLn('  PASS  ', What)
  else
  begin
    WriteLn('  FAIL  ', What);
    Inc(Fails);
  end;
end;

function Mask(S: Integer): Integer;
var
  k: Integer;
begin
  Result := 0;
  for k := 0 to 2 do
    if Sim.Pattern[S].P[k] then
      Result := Result or (1 shl k);
end;

var
  cl: TModbusTcpClient;
  s7: TS7Client;
  r: TWordArray;
  b: TBytes;
  s7addr: TS7Address;
begin
  Sim := TFluffSim.Create;
  LoadConfig;
  PlcCfg.Host := '127.0.0.1';
  PlcCfg.Port := 5020;
  if SameText(ParamStr(1), 's7') then
  begin
    PlcCfg.Protocol := ppS7;
    PlcCfg.Port := 102;
  end;
  if ParamCount >= 2 then PlcCfg.Host := ParamStr(2);
  if ParamCount >= 3 then PlcCfg.Port := StrToInt(ParamStr(3));
  PlcCfg.PollMs := 100;
  WriteLn('Protocol: ', ProtocolName(PlcCfg.Protocol), '  ', PlcCfg.Host, ':', PlcCfg.Port);
  SetDataSource(dsPLC);
  Link.Start;

  WriteLn('1. connect + read');
  Run(1.5);
  Check('link online: ' + Link.StatusText, Link.Online);
  Check('comm ok', Sim.CommOK);
  Check(Format('delay BlowerToScrew = 7.0 (got %.2f)', [Sim.TBlowerToScrew]), SameValue(Sim.TBlowerToScrew, 7, 1e-6));
  Check(Format('pattern 6 steps (got %d)', [Length(Sim.Pattern)]), Length(Sim.Pattern) = 6);
  Check(Format('step 3 = P2, 8.0 s (mask %d, %.1f)', [Mask(2), Sim.Pattern[2].Duration]),
    (Mask(2) = 2) and SameValue(Sim.Pattern[2].Duration, 8, 1e-6));
  Check(Format('silo level from PLC (%.1f%%)', [Sim.SiloLevel]), Sim.ExtSiloLevel and (Sim.SiloLevel > 20));
  Check('Blower Enable ON', Sim.Dev[DEV_BLOWER].Props[P_ENABLE]);

  WriteLn('2. parameter write (delays + pattern)');
  HmiSetDelay(0, 2.5);
  HmiSetDelay(2, 1.0);
  HmiSetDelay(1, 1.0);
  HmiPatternToggle(1, 1);
  HmiPatternTime(1, 3.5);
  Run(1.0);
  Check(Format('BlowerToScrew read back 2.5 (got %.2f)', [Sim.TBlowerToScrew]), SameValue(Sim.TBlowerToScrew, 2.5, 1e-6));
  Check(Format('step 2 mask read back 2 (got %d)', [Mask(1)]), Mask(1) = 2);
  Check(Format('step 2 time read back 3.5 (got %.2f)', [Sim.Pattern[1].Duration]), SameValue(Sim.Pattern[1].Duration, 3.5, 1e-6));
  HmiPatternAdd;
  Run(0.6);
  Check(Format('add step -> 7 steps (got %d)', [Length(Sim.Pattern)]), Length(Sim.Pattern) = 7);
  HmiPatternDelete(6);
  Run(0.6);
  Check(Format('delete step -> 6 steps (got %d)', [Length(Sim.Pattern)]), Length(Sim.Pattern) = 6);

  WriteLn('3. Auto Start + External Request (pulse command)');
  HmiCommand(hcAutoStart);
  HmiSetExtRequest(True);
  Run(1.2);
  Check('Auto mode ON', Sim.Mode = smAutoStart);
  Check('Blower running', Sim.Dev[DEV_BLOWER].Running);
  Check('External Request ON', Sim.ExtRequest);
  Run(4.0);
  Check('Screw running after delays', Sim.Dev[DEV_SCREW].Running);
  Run(2.0);
  Check('Paddle Patterns active', Sim.PatternActive);
  Check(Format('Paddle01 running (step %d)', [Sim.PatStep + 1]), Sim.Dev[DEV_PADDLE1].Running);

  if PlcCfg.Protocol = ppS7 then
  begin
    s7 := TS7Client.Create(PlcCfg.Host, PlcCfg.Port, 0, 1, S7_CONN_PG, 1000);
    try
      s7.Connect;
      b := s7.ReadArea(S7_AREA_DB, 10, 0, 22);
      Check('Cmd.AutoStart (DB10.DBX12.0) pulse released to 0', (b[12] and 1) = 0);
      Check(Format('DB10.DBW20 raw = 25 (got %d)', [(b[20] shl 8) or b[21]]), ((b[20] shl 8) or b[21]) = 25);
      Check('Blower01.Running (DB10.DBX1.1) = 1', (b[1] and 2) <> 0);
    finally
      s7.Free;
    end;
  end
  else
  begin
    cl := TModbusTcpClient.Create(PlcCfg.Host, PlcCfg.Port, 1, 1000);
    try
      cl.Connect;
      Check('Cmd.AutoStart pulse released to 0', not cl.ReadBits(1, 160, 1)[0]);
      r := cl.ReadRegs(3, 0, 1);
      Check(Format('HR0 raw = 25 (got %d)', [r[0]]), r[0] = 25);
    finally
      cl.Free;
    end;
  end;

  WriteLn('4. device command: Screw01 Manual Stop');
  HmiCommand(hcManStop, DEV_SCREW);
  Run(1.0);
  Check('Screw Manual Stop prop ON', Sim.Dev[DEV_SCREW].Props[P_MANSTOP]);
  Check('Screw stopped', not Sim.Dev[DEV_SCREW].Running);
  Check('Screw visual = manual stop', Sim.Dev[DEV_SCREW].Visual = dvManualStop);
  HmiCommand(hcManRelease, DEV_SCREW);
  Run(0.8);
  Check('Screw Manual Stop released', not Sim.Dev[DEV_SCREW].Props[P_MANSTOP]);

  WriteLn('5. E-Stop / reset');
  HmiCommand(hcEStop);
  Run(1.0);
  Check('E-Stop main ON', Sim.EStopMain);
  Check('Blower stopped by E-Stop', not Sim.Dev[DEV_BLOWER].Running);
  HmiCommand(hcResetEStop);
  Run(1.0);
  Check('E-Stop reset', not Sim.EStopMain);
  Check(Format('history recorded (%d events)', [Sim.EventCount]), Sim.EventCount > 10);

  WriteLn('6. restore defaults + comm loss');
  HmiSetDelay(0, 7);
  HmiSetDelay(1, 3);
  HmiSetDelay(2, 3);
  HmiPatternDefault;
  HmiSetExtRequest(False);
  HmiCommand(hcAutoStop);
  Run(0.8);
  Link.Stop;
  Run(0.3);
  Check('comm flag cleared after stop', not Sim.CommOK);

  PlcCfg.Port := 5999;   { nothing listens here }
  WriteLn('7. S7 address parser');
  Check('parse DB10.DBX12.3', ParseS7Address('DB10.DBX12.3', s7addr) and (s7addr.Area = S7_AREA_DB) and
    (s7addr.DB = 10) and (s7addr.Start = 12) and (s7addr.Bit = 3) and (s7addr.Size = 0));
  Check('parse %MW20', ParseS7Address('%MW20', s7addr) and (s7addr.Area = S7_AREA_MK) and (s7addr.Size = 2));
  Check('parse Q0.7 / A0.7', ParseS7Address('A0.7', s7addr) and (s7addr.Area = S7_AREA_PA) and (s7addr.Bit = 7));
  Check('parse DB1.DBD40', ParseS7Address('db1.dbd40', s7addr) and (s7addr.Size = 4) and (s7addr.Start = 40));
  Check('reject DB10.DBX0.8', not ParseS7Address('DB10.DBX0.8', s7addr));
  Check('reject M10', not ParseS7Address('M10', s7addr));
  PlcCfg.TimeoutMs := 500;
  Link.Start;
  Run(1.5);
  Check('bad port -> error state: ' + Link.StatusText, Link.State = lsError);
  Link.Stop;

  WriteLn;
  if Fails = 0 then
    WriteLn('ALL TESTS PASSED')
  else
    WriteLn(Fails, ' TEST(S) FAILED');
  Sim.Free;
  Sim := nil;
  ExitCode := Ord(Fails > 0);
end.
