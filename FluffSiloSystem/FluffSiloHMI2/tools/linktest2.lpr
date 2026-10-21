program linktest2;

{ Headless integration test of FluffSilo HMI2 uPlcLink + uModbus / uS7 against
  tools/plc_emulator2.py (default register map).
  Build:  fpc -Mobjfpc -Sh -Fu.. linktest2.lpr      (from the tools folder)
  Usage:  linktest2 [modbus|s7] [host] [port] }

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

function TestPattern(N: Integer): TPattern;
var
  s: Integer;
begin
  Result := nil;
  SetLength(Result, N);
  for s := 0 to N - 1 do
  begin
    SetStepMask(Result[s], (s * 37 + 5) and 127);
    Result[s].Duration := 0.5 + s * 1.5;
  end;
end;

var
  p: TPattern;
  i: Integer;
  b: TBytes;
  cl: TModbusTcpClient;
  s7: TS7Client;
  r: TWordArray;
  same: Boolean;
  err: string;
begin
  Sim := TFluffSim.Create;
  LoadConfig;
  DefaultSettings(PlcCfg);
  Tags := DefaultTags;
  IndexTags;
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
  WriteLn('Protocol: ', ProtocolName(PlcCfg.Protocol), '  ', PlcCfg.Host, ':', PlcCfg.Port,
    '  tags: ', Length(Tags));
  SetDataSource(dsPLC);
  Link.Start;

  WriteLn('1. connect + read');
  Run(1.5);
  Check('link online: ' + Link.StatusText, Link.Online);
  Check('comm ok', Sim.CommOK);
  Check(Format('delay BlowerToScrew = 7.0 (got %.2f)', [Sim.TBlowerToScrew]), SameValue(Sim.TBlowerToScrew, 7, 1e-6));
  Check(Format('paddles installed = 7 (got %d)', [Sim.PaddleCount]), Sim.PaddleCount = 7);
  Check(Format('pattern 14 steps (got %d)', [Length(Sim.Pattern)]), Length(Sim.Pattern) = 14);
  if Length(Sim.Pattern) >= 13 then
    Check(Format('step 13 = P7, 8.0 s (mask %d, %.1f)', [StepMask(Sim.Pattern[12]), Sim.Pattern[12].Duration]),
      (StepMask(Sim.Pattern[12]) = 64) and SameValue(Sim.Pattern[12].Duration, 8, 1e-6));
  Check(Format('silo level from PLC (%.1f%%)', [Sim.SiloLevel]), Sim.ExtSiloLevel and (Sim.SiloLevel > 20));
  Check('Paddle07 Enable ON', Sim.Dev[DEV_PADDLE1 + 6].Props[P_ENABLE]);

  WriteLn('2. Pattern -> PLC: 20 steps, then 5 steps');
  p := TestPattern(MAX_STEPS);
  i := HmiPatternWrite(p);
  Run(2.0);
  Check(Format('%d values sent', [i]), i > 20);
  Check(Format('read back 20 steps (got %d)', [Length(Sim.Pattern)]), Length(Sim.Pattern) = 20);
  Check('20-step table equal after read back', PatternsEqual(p, Sim.Pattern, MAX_PADDLES));
  p := TestPattern(5);
  p[4].Duration := 12.5;
  HmiPatternWrite(p);
  Run(1.2);
  same := PatternsEqual(p, Sim.Pattern, MAX_PADDLES);
  Check(Format('shrink to 5 steps (got %d), step 5 = 12.5 s', [Length(Sim.Pattern)]), same);
  i := HmiPatternWrite(p);
  Check(Format('writing the same table again sends 1 value (count) (got %d)', [i]), i = 1);

  WriteLn('3. paddles installed = 4');
  HmiSetPaddleCount(4);
  Run(1.2);
  Check(Format('PaddleCount read back 4 (got %d)', [Sim.PaddleCount]), Sim.PaddleCount = 4);
  Check('Paddle05..07 not installed', not Sim.Dev[DEV_PADDLE1 + 4].Installed and not Sim.Dev[DEV_PADDLE1 + 6].Installed);
  Check('Paddle04 installed', Sim.Dev[DEV_PADDLE1 + 3].Installed);
  same := True;
  for i := 0 to High(Sim.Pattern) do
    if StepMask(Sim.Pattern[i]) > 15 then same := False;
  Check('PLC cleared mask bits of paddles 5..7', same);
  HmiSetPaddleCount(7);
  Run(1.0);
  Check('PaddleCount back to 7', Sim.PaddleCount = 7);

  WriteLn('4. Auto Start + External Request (pulse command)');
  HmiPatternWrite(DefaultPattern(7));
  HmiSetDelay(0, 1.0);
  HmiSetDelay(1, 0.5);
  HmiSetDelay(2, 0.5);
  HmiCommand(hcAutoStart);
  HmiSetExtRequest(True);
  Run(1.0);
  Check('Auto mode ON', Sim.Mode = smAutoStart);
  Check('Blower running', Sim.Dev[DEV_BLOWER].Running);
  Check('External Request ON', Sim.ExtRequest);
  Run(2.5);
  Check('Screw running after delays', Sim.Dev[DEV_SCREW].Running);
  Check('Paddle Patterns active', Sim.PatternActive);
  Check(Format('Paddle01 running (step %d)', [Sim.PatStep + 1]), Sim.Dev[DEV_PADDLE1].Running);

  if PlcCfg.Protocol = ppS7 then
  begin
    s7 := TS7Client.Create(PlcCfg.Host, PlcCfg.Port, 0, 1, S7_CONN_PG, 1000);
    try
      s7.Connect;
      b := s7.ReadArea(S7_AREA_DB, 10, 0, 138);
      Check('Cmd.AutoStart (DB10.DBX20.0) pulse released to 0', (b[20] and 1) = 0);
      Check(Format('DB10.DBW32 raw = 10 (got %d)', [(b[32] shl 8) or b[33]]), ((b[32] shl 8) or b[33]) = 10);
      Check(Format('DB10.DBW56 step count = 14 (got %d)', [(b[56] shl 8) or b[57]]), ((b[56] shl 8) or b[57]) = 14);
      Check(Format('DB10.DBW82 step 13 mask = 64 (got %d)', [(b[82] shl 8) or b[83]]), ((b[82] shl 8) or b[83]) = 64);
      Check('Blower01.Running (DB10.DBX1.1) = 1', (b[1] and 2) <> 0);
      Check('Paddle01.Running (DB10.DBX5.1) = 1', (b[5] and 2) <> 0);
    finally
      s7.Free;
    end;
  end
  else
  begin
    cl := TModbusTcpClient.Create(PlcCfg.Host, PlcCfg.Port, 1, 1000);
    try
      cl.Connect;
      Check('Cmd.AutoStart (coil 210) pulse released to 0', not cl.ReadBits(1, 210, 1)[0]);
      r := cl.ReadRegs(3, 0, 61);
      Check(Format('HR0 raw = 10 (got %d)', [r[0]]), r[0] = 10);
      Check(Format('HR20 step count = 14 (got %d)', [r[20]]), r[20] = 14);
      Check(Format('HR33 step 13 mask = 64 (got %d)', [r[33]]), r[33] = 64);
      Check(Format('HR15 paddles = 7 (got %d)', [r[15]]), r[15] = 7);
    finally
      cl.Free;
    end;
  end;

  WriteLn('5. device command: Paddle07 Manual Start / Screw01 Manual Stop');
  HmiCommand(hcManStart, DEV_PADDLE1 + 6);
  Run(1.0);
  Check('Paddle07 Manual Start + running', Sim.Dev[DEV_PADDLE1 + 6].Props[P_MANSTART] and Sim.Dev[DEV_PADDLE1 + 6].Running);
  Check('Paddle07 visual = manual run', Sim.Dev[DEV_PADDLE1 + 6].Visual = dvManualRun);
  HmiCommand(hcManRelease, DEV_PADDLE1 + 6);
  HmiCommand(hcManStop, DEV_SCREW);
  Run(1.0);
  Check('Screw stopped (manual stop)', not Sim.Dev[DEV_SCREW].Running and Sim.Dev[DEV_SCREW].Props[P_MANSTOP]);
  HmiCommand(hcManRelease, DEV_SCREW);
  Run(0.8);

  WriteLn('6. E-Stop / reset');
  HmiCommand(hcEStop);
  Run(1.0);
  Check('E-Stop main ON', Sim.EStopMain);
  Check('Blower stopped by E-Stop', not Sim.Dev[DEV_BLOWER].Running);
  HmiCommand(hcResetEStop);
  Run(1.0);
  Check('E-Stop reset', not Sim.EStopMain);
  Check(Format('history recorded (%d events)', [Sim.EventCount]), Sim.EventCount > 20);

  WriteLn('7. restore defaults');
  HmiSetDelay(0, 7);
  HmiSetDelay(1, 3);
  HmiSetDelay(2, 3);
  HmiSetExtRequest(False);
  HmiCommand(hcAutoStop);
  Run(1.0);
  Link.Stop;
  Run(0.3);
  Check('comm flag cleared after stop', not Sim.CommOK);

  WriteLn('8. pattern CSV file round trip');
  p := TestPattern(MAX_STEPS);
  SavePatternCsv(GetTempDir + 'hmi2_pattern_test.csv', p);
  Check('load CSV', LoadPatternCsv(GetTempDir + 'hmi2_pattern_test.csv', Sim.Pattern, err));
  Check('CSV round trip equal (20 steps)', PatternsEqual(p, Sim.Pattern, MAX_PADDLES));
  DeleteFile(GetTempDir + 'hmi2_pattern_test.csv');

  WriteLn;
  if Fails = 0 then
    WriteLn('ALL TESTS PASSED')
  else
    WriteLn(Fails, ' TEST(S) FAILED');
  Sim.Free;
  Sim := nil;
  ExitCode := Ord(Fails > 0);
end.
