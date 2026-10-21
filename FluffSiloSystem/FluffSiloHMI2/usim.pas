unit uSim;

{ FluffSilo HMI2 - simulation engine
  - 9 devices : Blower01, Screw01, Paddle01..07
  - PaddleCount (1..7) paddles installed; the others are hidden and never run
  - 9 properties per device (+ Running feedback) with priority levels
  - Auto sequencer, External Request, Paddle Patterns (up to MAX_STEPS steps)
  - Signal history + event log for charts and the Events window
  - Source = dsPLC: the logic runs in the PLC; uPlcLink writes the PLC data into
    this object and StepExternal only derives timers / history from it }

{$mode objfpc}{$H+}
{$COPERATORS ON}

interface

uses
  Classes, SysUtils, Math;

const
  MAX_PADDLES = 7;
  MAX_STEPS   = 20;
  DEV_COUNT   = 2 + MAX_PADDLES;
  DEV_BLOWER  = 0;
  DEV_SCREW   = 1;
  DEV_PADDLE1 = 2;
  DevNames: array[0..DEV_COUNT - 1] of string =
    ('Blower01', 'Screw01', 'Paddle01', 'Paddle02', 'Paddle03', 'Paddle04',
     'Paddle05', 'Paddle06', 'Paddle07');

  PROP_COUNT  = 10;
  P_AUTOSTART = 0;
  P_AUTOSTOP  = 1;
  P_INTERLOCK = 2;
  P_MANSTART  = 3;
  P_MANSTOP   = 4;
  P_ENABLE    = 5;
  P_DISABLE   = 6;
  P_FAULT     = 7;
  P_ESTOP     = 8;
  P_RUNNING   = 9;   { feedback, not a command property }
  PropNames: array[0..PROP_COUNT - 1] of string =
    ('Auto Start', 'Auto Stop', 'Interlock', 'Manual Start', 'Manual Stop',
     'Enable', 'Disable', 'Fault', 'E-Stop', 'Running');
  PropLevels: array[0..PROP_COUNT - 1] of Integer = (1, 2, 2, 3, 4, 5, 5, 6, 6, 0);

  SYS_EXTREQ   = 0;
  SYS_AUTOMODE = 1;
  SYS_PATTERN  = 2;
  SYS_ESTOP    = 3;
  SYS_COUNT    = 4;
  SysNames: array[0..SYS_COUNT - 1] of string =
    ('External Request', 'Auto Mode', 'Paddle Patterns', 'E-Stop (Main)');

  SYS_BASE     = DEV_COUNT * PROP_COUNT;
  SIGNAL_COUNT = SYS_BASE + SYS_COUNT;

  MIN_STEP_TIME = 0.5;
  MAX_STEP_TIME = 600;

type
  TSysMode = (smAutoStop, smAutoStart);
  TDataSource = (dsSimulation, dsPLC);
  TDevVisual = (dvIdle, dvAutoRun, dvManualRun, dvManualStop, dvDisabled, dvFault);

  { TDevice }

  TDevice = class
  public
    Index: Integer;
    Name: string;
    Props: array[0..PROP_COUNT - 1] of Boolean;
    RunTime: Double;        { current run duration }
    TotalRunTime: Double;
    StartCount: Integer;
    CtrlLevel: Integer;     { level that decided the output }
    Reason: string;
    Phase: Double;          { animation angle }
    LastRun: Boolean;       { running state of the previous step }
    Installed: Boolean;     { paddles above PaddleCount are not installed }
    function Running: Boolean;
    function Available: Boolean;
    function Visual: TDevVisual;
  end;

  TPatternStep = record
    P: array[0..MAX_PADDLES - 1] of Boolean;
    Duration: Double;
  end;
  TPattern = array of TPatternStep;

  TSimEvent = record
    T: Double;
    Stamp: TDateTime;  { wall clock }
    Sig: Integer;      { -1 = sequencer / command message }
    Value: Boolean;
    Text: string;
  end;

  TSigPoint = record
    T: Double;
    V: Boolean;
  end;

  TSigHistory = record
    Count: Integer;
    Pts: array of TSigPoint;
  end;

  TSimEventProc = procedure(const E: TSimEvent) of object;

  { TFluffSim }

  TFluffSim = class
  private
    FLastSig: array[0..SIGNAL_COUNT - 1] of Boolean;
    FPrevScrewRun: Boolean;
    FOnEvent: TSimEventProc;
    FLastPatStep: Integer;
    procedure ResolveControl(D: TDevice; out Run: Boolean; out Lvl: Integer; out Why: string);
    procedure UpdateRunStats(D: TDevice; Run: Boolean; dt: Double);
    procedure EvaluateDevice(D: TDevice; dt: Double);
    procedure ClearDevice(D: TDevice);
    procedure RunPattern(dt: Double);
    procedure RecordSignals;
    procedure AddPoint(Id: Integer; V: Boolean);
    function StepHasPaddle(S: Integer): Boolean;
    function StepBlocked(S: Integer): Boolean;
    function FindNextStep(SkipPauses: Boolean): Integer;
    procedure GoStep(S: Integer; const Why: string);
  public
    Time: Double;
    Source: TDataSource;
    CommOK: Boolean;           { PLC mode: data is fresh }
    ExtPatElapsed: Boolean;    { PLC mode: PatElapsed comes from the PLC }
    ExtSiloLevel: Boolean;     { PLC mode: SiloLevel comes from the PLC }
    Dev: array[0..DEV_COUNT - 1] of TDevice;
    PaddleCount: Integer;      { 1..MAX_PADDLES installed paddles }
    Mode: TSysMode;
    ExtRequest: Boolean;
    ReqOnTime, ReqOffTime: Double;
    EStopMain: Boolean;
    BlowerCmd, ScrewCmd, PatternCmd, PatternActive: Boolean;
    BlowerStopTimer: Double;   { >0 while counting down to blower stop }
    Pattern: TPattern;         { the ACTIVE pattern (simulator or PLC) }
    PatStep: Integer;
    PatElapsed: Double;
    PatternSeq: Integer;       { +1 whenever the active pattern changes }
    { configurable delays (s) }
    TBlowerToScrew: Double;    { blower run -> screw start            (7) }
    TReqHold: Double;          { request must be held                 (3) }
    TScrewToPaddle: Double;    { screw run -> paddle patterns         (3) }
    TReqOffScrewStop: Double;  { request lost -> screw stop           (3) }
    TScrewTripBlower: Double;  { screw stopped -> blower stop         (5) }
    TAutoStopBlower: Double;   { Auto Stop -> blower stop             (5) }
    { cosmetic material model }
    SiloLevel: Double;
    Filling: Boolean;
    History: array[0..SIGNAL_COUNT - 1] of TSigHistory;
    Events: array of TSimEvent;
    EventCount: Integer;
    constructor Create;
    destructor Destroy; override;
    procedure Step(dt: Double);
    procedure StepExternal(dt: Double);
    procedure ResetRuntime;
    procedure Log(ASig: Integer; AValue: Boolean; const AText: string);
    procedure SetPaddleCount(N: Integer);
    { main panel }
    procedure CmdAutoStart;
    procedure CmdAutoStop;
    procedure CmdEStop;
    procedure CmdResetEStop;
    procedure SetExtRequest(V: Boolean);
    { device panel }
    procedure CmdManualStart(I: Integer);
    procedure CmdManualStop(I: Integer);
    procedure CmdManualRelease(I: Integer);
    procedure CmdEnable(I: Integer);
    procedure CmdDisable(I: Integer);
    procedure CmdFault(I: Integer);
    procedure CmdResetFault(I: Integer);
    { pattern }
    procedure LoadDefaultPattern;
    procedure SetPattern(const P: TPattern);
    procedure PatternChanged;
    function StepText(S: Integer): string;
    function CycleTime: Double;
    { queries }
    function GetSignal(Id: Integer): Boolean;
    function ValueAt(Id: Integer; T: Double): Boolean;
    function FindHistIdx(Id: Integer; T: Double): Integer;
    procedure GetTimingInfo(L: TStrings);
    function DevDelayText(I: Integer): string;
    property OnEvent: TSimEventProc read FOnEvent write FOnEvent;
  end;

function SignalName(Id: Integer): string;
function SignalLevel(Id: Integer): Integer;
function SigId(ADev, AProp: Integer): Integer;
function SignalInstalled(Id: Integer): Boolean;
function FmtTime(T: Double): string;
function OnOff(V: Boolean): string;
function IsPaddle(I: Integer): Boolean;

{ pattern helpers (also used by the pattern editor and the PLC link) }
function DefaultPattern(APaddles: Integer): TPattern;
function StepMask(const S: TPatternStep): Integer;
procedure SetStepMask(var S: TPatternStep; AMask: Integer);
function StepLabel(const S: TPatternStep; APaddles: Integer): string;
function PatternsEqual(const A, B: TPattern; APaddles: Integer): Boolean;
function PatternTotal(const P: TPattern): Double;
function NormStepTime(V: Double): Double;
procedure SavePatternCsv(const AFile: string; const P: TPattern);
function LoadPatternCsv(const AFile: string; out P: TPattern; out Err: string): Boolean;

var
  Sim: TFluffSim;
  GDragSignal: Integer = -1;   { signal being dragged toward a chart }

implementation

function SignalName(Id: Integer): string;
begin
  if (Id >= 0) and (Id < SYS_BASE) then
    Result := DevNames[Id div PROP_COUNT] + '.' + PropNames[Id mod PROP_COUNT]
  else if (Id >= SYS_BASE) and (Id < SIGNAL_COUNT) then
    Result := 'System.' + SysNames[Id - SYS_BASE]
  else
    Result := '?';
end;

function SignalLevel(Id: Integer): Integer;
begin
  if (Id >= 0) and (Id < SYS_BASE) then
    Result := PropLevels[Id mod PROP_COUNT]
  else if Id = SYS_BASE + SYS_EXTREQ then
    Result := 1
  else
    Result := 0;
end;

function SigId(ADev, AProp: Integer): Integer;
begin
  Result := ADev * PROP_COUNT + AProp;
end;

function SignalInstalled(Id: Integer): Boolean;
begin
  if (Id >= 0) and (Id < SYS_BASE) and (Sim <> nil) then
    Result := Sim.Dev[Id div PROP_COUNT].Installed
  else
    Result := (Id >= 0) and (Id < SIGNAL_COUNT);
end;

function IsPaddle(I: Integer): Boolean;
begin
  Result := (I >= DEV_PADDLE1) and (I < DEV_COUNT);
end;

function FmtTime(T: Double): string;
var
  h, m: Integer;
  s: Double;
begin
  if T < 0 then T := 0;
  h := Trunc(T) div 3600;
  m := (Trunc(T) div 60) mod 60;
  s := T - h * 3600 - m * 60;
  { FormatFloat pads with zeros ("%04.1f" pads with spaces) }
  Result := Format('%.2d:%.2d:', [h, m]) + FormatFloat('00.0', Min(s, 59.94));
end;

function OnOff(V: Boolean): string;
begin
  if V then Result := 'ON' else Result := 'OFF';
end;

{ ---------------- pattern helpers ---------------- }

function NormStepTime(V: Double): Double;
begin
  Result := EnsureRange(Round(V * 10) / 10, MIN_STEP_TIME, MAX_STEP_TIME);
end;

function DefaultPattern(APaddles: Integer): TPattern;
var
  k, n: Integer;
begin
  { Concept: every paddle 8 s, then 2 s pause, one after the other }
  Result := nil;
  APaddles := EnsureRange(APaddles, 1, MAX_PADDLES);
  SetLength(Result, APaddles * 2);
  FillChar(Result[0], Length(Result) * SizeOf(TPatternStep), 0);
  n := 0;
  for k := 0 to APaddles - 1 do
  begin
    Result[n].P[k] := True;
    Result[n].Duration := 8;
    Result[n + 1].Duration := 2;
    Inc(n, 2);
  end;
end;

function StepMask(const S: TPatternStep): Integer;
var
  k: Integer;
begin
  Result := 0;
  for k := 0 to MAX_PADDLES - 1 do
    if S.P[k] then
      Result := Result or (1 shl k);
end;

procedure SetStepMask(var S: TPatternStep; AMask: Integer);
var
  k: Integer;
begin
  for k := 0 to MAX_PADDLES - 1 do
    S.P[k] := (AMask and (1 shl k)) <> 0;
end;

function StepLabel(const S: TPatternStep; APaddles: Integer): string;
var
  k: Integer;
begin
  Result := '';
  for k := 0 to Min(APaddles, MAX_PADDLES) - 1 do
    if S.P[k] then
    begin
      if Result <> '' then Result += '+';
      Result += 'P' + IntToStr(k + 1);
    end;
  if Result = '' then
    Result := 'Pause';
end;

function PatternsEqual(const A, B: TPattern; APaddles: Integer): Boolean;
var
  i, m: Integer;
begin
  Result := Length(A) = Length(B);
  if not Result then Exit;
  m := (1 shl APaddles) - 1;
  for i := 0 to High(A) do
    if ((StepMask(A[i]) and m) <> (StepMask(B[i]) and m)) or (Abs(A[i].Duration - B[i].Duration) > 0.05) then
      Exit(False);
end;

function PatternTotal(const P: TPattern): Double;
var
  i: Integer;
begin
  Result := 0;
  for i := 0 to High(P) do
    Result += P[i].Duration;
end;

function DotFloat(V: Double): string;
var
  fs: TFormatSettings;
begin
  fs := DefaultFormatSettings;
  fs.DecimalSeparator := '.';
  Result := FormatFloat('0.0', V, fs);
end;

procedure SavePatternCsv(const AFile: string; const P: TPattern);
var
  sl: TStringList;
  i, k: Integer;
  s: string;
begin
  { one step per line, readable in Excel: Step;Paddle01..07 (1/0);Time_s }
  sl := TStringList.Create;
  try
    sl.Add('# FluffSilo HMI2 Paddle Pattern - ' + FormatDateTime('yyyy-mm-dd hh:nn:ss', Now));
    s := 'Step';
    for k := 0 to MAX_PADDLES - 1 do
      s += ';' + DevNames[DEV_PADDLE1 + k];
    sl.Add(s + ';Time_s');
    for i := 0 to High(P) do
    begin
      s := IntToStr(i + 1);
      for k := 0 to MAX_PADDLES - 1 do
        s += ';' + IntToStr(Ord(P[i].P[k]));
      sl.Add(s + ';' + DotFloat(P[i].Duration));
    end;
    sl.SaveToFile(AFile);
  finally
    sl.Free;
  end;
end;

function LoadPatternCsv(const AFile: string; out P: TPattern; out Err: string): Boolean;
var
  sl, f: TStringList;
  i, k, n: Integer;
  line: string;
  v: Double;
  fs: TFormatSettings;
begin
  P := nil;
  Err := '';
  fs := DefaultFormatSettings;
  fs.DecimalSeparator := '.';
  sl := TStringList.Create;
  f := TStringList.Create;
  try
    try
      sl.LoadFromFile(AFile);
    except
      on E: Exception do
      begin
        Err := E.Message;
        Exit(False);
      end;
    end;
    f.StrictDelimiter := True;
    f.Delimiter := ';';
    for i := 0 to sl.Count - 1 do
    begin
      line := Trim(sl[i]);
      if (line = '') or (line[1] = '#') then Continue;
      { accept ',' as separator too (Excel with another locale) }
      if (Pos(';', line) = 0) and (Pos(',', line) > 0) then
        line := StringReplace(line, ',', ';', [rfReplaceAll]);
      f.DelimitedText := line;
      if SameText(Trim(f[0]), 'Step') then Continue;   { header }
      if f.Count < MAX_PADDLES + 2 then
      begin
        Err := Format('line %d: expected %d columns', [i + 1, MAX_PADDLES + 2]);
        Exit(False);
      end;
      n := Length(P);
      if n >= MAX_STEPS then
      begin
        Err := Format('more than %d steps', [MAX_STEPS]);
        Exit(False);
      end;
      SetLength(P, n + 1);
      for k := 0 to MAX_PADDLES - 1 do
        P[n].P[k] := Trim(f[k + 1]) = '1';
      if not TryStrToFloat(StringReplace(Trim(f[MAX_PADDLES + 1]), ',', '.', []), v, fs) then
      begin
        Err := Format('line %d: bad time "%s"', [i + 1, f[MAX_PADDLES + 1]]);
        Exit(False);
      end;
      P[n].Duration := NormStepTime(v);
    end;
    Result := True;
  finally
    f.Free;
    sl.Free;
  end;
end;

{ TDevice }

function TDevice.Running: Boolean;
begin
  Result := Props[P_RUNNING];
end;

function TDevice.Available: Boolean;
begin
  Result := Installed and not (Props[P_FAULT] or Props[P_ESTOP] or Props[P_DISABLE] or Props[P_MANSTOP]);
end;

function TDevice.Visual: TDevVisual;
begin
  if not Installed then Result := dvDisabled
  else if Props[P_FAULT] then Result := dvFault
  else if Props[P_DISABLE] then Result := dvDisabled
  else if Props[P_ESTOP] then Result := dvIdle
  else if Props[P_MANSTOP] then Result := dvManualStop
  else if Props[P_MANSTART] then Result := dvManualRun
  else if Running then Result := dvAutoRun
  else Result := dvIdle;
end;

{ TFluffSim }

constructor TFluffSim.Create;
var
  i: Integer;
begin
  inherited Create;
  for i := 0 to DEV_COUNT - 1 do
  begin
    Dev[i] := TDevice.Create;
    Dev[i].Index := i;
    Dev[i].Name := DevNames[i];
    Dev[i].Props[P_ENABLE] := True;
    Dev[i].Reason := 'Idle';
    Dev[i].Installed := True;
  end;
  PaddleCount := MAX_PADDLES;
  Mode := smAutoStop;
  TBlowerToScrew := 7;
  TReqHold := 3;
  TScrewToPaddle := 3;
  TReqOffScrewStop := 3;
  TScrewTripBlower := 5;
  TAutoStopBlower := 5;
  SiloLevel := 75;
  LoadDefaultPattern;
  RecordSignals;
end;

destructor TFluffSim.Destroy;
var
  i: Integer;
begin
  for i := 0 to DEV_COUNT - 1 do
    Dev[i].Free;
  inherited Destroy;
end;

procedure TFluffSim.Log(ASig: Integer; AValue: Boolean; const AText: string);
var
  E: TSimEvent;
begin
  E.T := Time;
  E.Stamp := Now;
  E.Sig := ASig;
  E.Value := AValue;
  E.Text := AText;
  if EventCount >= Length(Events) then
    SetLength(Events, Max(256, Length(Events) * 2));
  Events[EventCount] := E;
  Inc(EventCount);
  if Assigned(FOnEvent) then
    FOnEvent(E);
end;

procedure TFluffSim.ClearDevice(D: TDevice);
var
  k: Integer;
begin
  for k := 0 to PROP_COUNT - 1 do
    D.Props[k] := False;
  D.Props[P_ENABLE] := True;
  D.RunTime := 0;
  D.LastRun := False;
  D.CtrlLevel := 0;
  D.Reason := 'Idle';
end;

procedure TFluffSim.SetPaddleCount(N: Integer);
var
  k: Integer;
  inst: Boolean;
begin
  N := EnsureRange(N, 1, MAX_PADDLES);
  if N = PaddleCount then Exit;
  Log(-1, True, Format('Paddles installed: %d -> %d', [PaddleCount, N]));
  PaddleCount := N;
  for k := 0 to MAX_PADDLES - 1 do
  begin
    inst := k < N;
    if Dev[DEV_PADDLE1 + k].Installed <> inst then
    begin
      Dev[DEV_PADDLE1 + k].Installed := inst;
      ClearDevice(Dev[DEV_PADDLE1 + k]);
      if not inst then
        Dev[DEV_PADDLE1 + k].Reason := 'Not installed';
    end;
  end;
end;

procedure TFluffSim.AddPoint(Id: Integer; V: Boolean);
begin
  with History[Id] do
  begin
    if Count >= Length(Pts) then
      SetLength(Pts, Max(64, Length(Pts) * 2));
    Pts[Count].T := Time;
    Pts[Count].V := V;
    Inc(Count);
  end;
end;

function TFluffSim.GetSignal(Id: Integer): Boolean;
begin
  if (Id >= 0) and (Id < SYS_BASE) then
    Result := Dev[Id div PROP_COUNT].Props[Id mod PROP_COUNT]
  else
    case Id - SYS_BASE of
      SYS_EXTREQ:   Result := ExtRequest;
      SYS_AUTOMODE: Result := Mode = smAutoStart;
      SYS_PATTERN:  Result := PatternActive;
      SYS_ESTOP:    Result := EStopMain;
    else
      Result := False;
    end;
end;

function TFluffSim.FindHistIdx(Id: Integer; T: Double): Integer;
var
  lo, hi, mid: Integer;
begin
  { last index with Pts[i].T <= T, -1 if none }
  Result := -1;
  lo := 0;
  hi := History[Id].Count - 1;
  while lo <= hi do
  begin
    mid := (lo + hi) div 2;
    if History[Id].Pts[mid].T <= T then
    begin
      Result := mid;
      lo := mid + 1;
    end
    else
      hi := mid - 1;
  end;
end;

function TFluffSim.ValueAt(Id: Integer; T: Double): Boolean;
var
  k: Integer;
begin
  k := FindHistIdx(Id, T);
  if k < 0 then
    Result := False
  else
    Result := History[Id].Pts[k].V;
end;

procedure TFluffSim.RecordSignals;
var
  id: Integer;
  v: Boolean;
begin
  for id := 0 to SIGNAL_COUNT - 1 do
  begin
    v := GetSignal(id);
    if (History[id].Count = 0) or (v <> FLastSig[id]) then
    begin
      AddPoint(id, v);
      FLastSig[id] := v;
      if History[id].Count > 1 then
        Log(id, v, SignalName(id) + ' = ' + OnOff(v));
    end;
  end;
end;

procedure TFluffSim.ResolveControl(D: TDevice; out Run: Boolean; out Lvl: Integer; out Why: string);
begin
  { highest level wins }
  if not D.Installed then begin Run := False; Lvl := 0; Why := 'Not installed'; end
  else if D.Props[P_FAULT] then begin Run := False; Lvl := 6; Why := 'Fault'; end
  else if D.Props[P_ESTOP] then begin Run := False; Lvl := 6; Why := 'E-Stop'; end
  else if D.Props[P_DISABLE] then begin Run := False; Lvl := 5; Why := 'Disabled'; end
  else if D.Props[P_MANSTOP] then begin Run := False; Lvl := 4; Why := 'Manual Stop'; end
  else if D.Props[P_MANSTART] then begin Run := True; Lvl := 3; Why := 'Manual Start'; end
  else if D.Props[P_AUTOSTOP] then begin Run := False; Lvl := 2; Why := 'Auto Stop'; end
  else if D.Props[P_INTERLOCK] then begin Run := False; Lvl := 2; Why := 'Interlock'; end
  else if D.Props[P_AUTOSTART] then begin Run := True; Lvl := 1; Why := 'Auto Start'; end
  else begin Run := False; Lvl := 0; Why := 'Idle'; end;
end;

procedure TFluffSim.EvaluateDevice(D: TDevice; dt: Double);
var
  run: Boolean;
  lvl: Integer;
  why: string;
begin
  ResolveControl(D, run, lvl, why);
  D.Props[P_RUNNING] := run;
  D.CtrlLevel := lvl;
  D.Reason := why;
  UpdateRunStats(D, run, dt);
end;

procedure TFluffSim.UpdateRunStats(D: TDevice; Run: Boolean; dt: Double);
var
  speed: Double;
begin
  case D.Index of
    DEV_BLOWER: speed := 14;
    DEV_SCREW: speed := 6;
  else
    speed := 3.5;
  end;
  if Run then
  begin
    if not D.LastRun then
      Inc(D.StartCount);
    D.RunTime += dt;
    D.TotalRunTime += dt;
    D.Phase += dt * speed;
    if D.Phase > 2 * Pi * 1000 then
      D.Phase -= 2 * Pi * 1000;
  end
  else
    D.RunTime := 0;
  D.LastRun := Run;
end;

function TFluffSim.StepHasPaddle(S: Integer): Boolean;
var
  k: Integer;
begin
  Result := False;
  for k := 0 to PaddleCount - 1 do
    if Pattern[S].P[k] then
      Exit(True);
end;

function TFluffSim.StepBlocked(S: Integer): Boolean;
var
  k: Integer;
begin
  { a step is blocked when it needs paddles and none of them can run }
  if not StepHasPaddle(S) then
    Exit(False);
  Result := True;
  for k := 0 to PaddleCount - 1 do
    if Pattern[S].P[k] and Dev[DEV_PADDLE1 + k].Available then
      Exit(False);
end;

function TFluffSim.FindNextStep(SkipPauses: Boolean): Integer;
var
  n, k, s: Integer;
begin
  Result := -1;
  n := Length(Pattern);
  for k := 1 to n do
  begin
    s := (PatStep + k) mod n;
    if (not StepBlocked(s)) and ((not SkipPauses) or StepHasPaddle(s)) then
      Exit(s);
  end;
  if SkipPauses then
    Result := FindNextStep(False);
end;

procedure TFluffSim.GoStep(S: Integer; const Why: string);
begin
  PatStep := S;
  PatElapsed := 0;
  Log(-1, True, Format('Paddle Patterns -> step %d [%s] %.1fs%s',
    [S + 1, StepText(S), Pattern[S].Duration, Why]));
end;

function TFluffSim.StepText(S: Integer): string;
begin
  if (S < 0) or (S >= Length(Pattern)) then
    Exit('-');
  Result := StepLabel(Pattern[S], PaddleCount);
end;

function TFluffSim.CycleTime: Double;
begin
  Result := PatternTotal(Pattern);
end;

procedure TFluffSim.RunPattern(dt: Double);
var
  s: Integer;
begin
  if (not PatternCmd) or (Length(Pattern) = 0) then
  begin
    PatternActive := False;
    Exit;
  end;
  if not PatternActive then
  begin
    PatternActive := True;
    PatStep := Length(Pattern) - 1;      { so that "next" is step 0 }
    s := FindNextStep(False);
    if s < 0 then s := 0;
    GoStep(s, ' (start)');
    Exit;
  end;
  PatElapsed += dt;
  if PatElapsed >= Pattern[PatStep].Duration then
  begin
    s := FindNextStep(False);
    if s >= 0 then
      GoStep(s, '');
  end
  else if StepBlocked(PatStep) then
  begin
    { paddle in this step stopped -> next paddle continues }
    s := FindNextStep(True);
    if (s >= 0) and (s <> PatStep) then
      GoStep(s, ' (paddle stopped -> next)');
  end;
end;

procedure TFluffSim.Step(dt: Double);
var
  i, k: Integer;
  blowerRun, screwRun: Boolean;
begin
  Time += dt;

  if ExtRequest then
  begin
    ReqOnTime += dt;
    ReqOffTime := 0;
  end
  else
  begin
    ReqOffTime += dt;
    ReqOnTime := 0;
  end;

  blowerRun := Dev[DEV_BLOWER].Running;
  screwRun := Dev[DEV_SCREW].Running;

  { ---------------- auto sequencer ---------------- }
  case Mode of
    smAutoStart:
      begin
        BlowerCmd := True;
        BlowerStopTimer := 0;
        if not blowerRun then
        begin
          if ScrewCmd then
            Log(-1, False, 'Blower01 not running -> Screw01 & Paddle Patterns stop');
          ScrewCmd := False;
        end
        else
        begin
          if (not ScrewCmd) and ExtRequest and
             (Dev[DEV_BLOWER].RunTime >= TBlowerToScrew) and (ReqOnTime >= TReqHold) then
          begin
            ScrewCmd := True;
            Log(-1, True, 'Auto: Screw01 start (Blower ready + External Request)');
          end;
          if ScrewCmd and (not ExtRequest) and (ReqOffTime >= TReqOffScrewStop) then
          begin
            ScrewCmd := False;
            Log(-1, False, 'Auto: Screw01 stop (no External Request)');
          end;
        end;
        PatternCmd := (Mode = smAutoStart) and ScrewCmd and screwRun and blowerRun and
          ExtRequest and (Dev[DEV_SCREW].RunTime >= TScrewToPaddle);
      end;
    smAutoStop:
      begin
        ScrewCmd := False;
        PatternCmd := False;
        if BlowerStopTimer > 0 then
        begin
          BlowerStopTimer -= dt;
          if BlowerStopTimer <= 0 then
          begin
            BlowerStopTimer := 0;
            BlowerCmd := False;
            Log(-1, False, 'Auto: Blower01 stop (delay elapsed)');
          end;
        end
        else
          BlowerCmd := False;
      end;
  end;

  RunPattern(dt);

  { ---------------- auto commands -> properties ---------------- }
  with Dev[DEV_BLOWER] do
  begin
    Props[P_AUTOSTART] := BlowerCmd;
    Props[P_AUTOSTOP] := (Mode = smAutoStop) and not BlowerCmd;
    Props[P_INTERLOCK] := False;
  end;
  with Dev[DEV_SCREW] do
  begin
    Props[P_AUTOSTART] := ScrewCmd;
    Props[P_AUTOSTOP] := Mode = smAutoStop;
    Props[P_INTERLOCK] := not blowerRun;
  end;
  for k := 0 to PaddleCount - 1 do
    with Dev[DEV_PADDLE1 + k] do
    begin
      Props[P_AUTOSTART] := PatternActive and Pattern[PatStep].P[k];
      Props[P_AUTOSTOP] := Mode = smAutoStop;
      Props[P_INTERLOCK] := not screwRun;
    end;
  FPrevScrewRun := Dev[DEV_SCREW].Running;
  for i := 0 to DEV_COUNT - 1 do
  begin
    if not Dev[i].Installed then
    begin
      ClearDevice(Dev[i]);
      Dev[i].Reason := 'Not installed';
      Continue;
    end;
    Dev[i].Props[P_ESTOP] := EStopMain;
    Dev[i].Props[P_ENABLE] := not Dev[i].Props[P_DISABLE];
    EvaluateDevice(Dev[i], dt);
  end;

  { Screw01 stopped while auto wanted it running (fault, disable, manual stop...):
    Paddle Patterns stop now, Blower01 stops after the delay }
  if (Mode = smAutoStart) and ScrewCmd and FPrevScrewRun and not Dev[DEV_SCREW].Running then
  begin
    ScrewCmd := False;
    PatternCmd := False;
    PatternActive := False;
    for k := 0 to PaddleCount - 1 do
      Dev[DEV_PADDLE1 + k].Props[P_AUTOSTART] := False;
    Mode := smAutoStop;
    BlowerStopTimer := Max(0.001, TScrewTripBlower);
    Log(-1, False, Format('Screw01 stopped -> Paddle Patterns stop, Blower01 stops in %.1fs',
      [TScrewTripBlower]));
    for k := 0 to PaddleCount - 1 do
      EvaluateDevice(Dev[DEV_PADDLE1 + k], 0);
  end;

  { ---------------- material (visual only) ---------------- }
  if Dev[DEV_SCREW].Running then
    SiloLevel -= 0.8 * dt;
  if SiloLevel < 25 then
    Filling := True;
  if Filling then
  begin
    SiloLevel += 2.5 * dt;
    if SiloLevel >= 90 then
      Filling := False;
  end;
  SiloLevel := EnsureRange(SiloLevel, 0, 100);

  RecordSignals;
end;

procedure TFluffSim.StepExternal(dt: Double);
var
  i: Integer;
  run: Boolean;
  lvl: Integer;
  why: string;
begin
  { PLC mode: properties, mode, request and pattern were set by uPlcLink.
    Only derive what the PLC does not send (timers, counters, history). }
  Time += dt;
  if ExtRequest then
  begin
    ReqOnTime += dt;
    ReqOffTime := 0;
  end
  else
  begin
    ReqOffTime += dt;
    ReqOnTime := 0;
  end;

  for i := 0 to DEV_COUNT - 1 do
  begin
    ResolveControl(Dev[i], run, lvl, why);
    Dev[i].CtrlLevel := lvl;
    Dev[i].Reason := why;
    { the real output is the PLC Running feedback }
    if Dev[i].Installed and (Dev[i].Running <> run) then
      Dev[i].Reason := why + ' (fb ' + OnOff(Dev[i].Running) + ')';
    UpdateRunStats(Dev[i], Dev[i].Running, dt);
  end;
  BlowerCmd := Dev[DEV_BLOWER].Props[P_AUTOSTART];
  ScrewCmd := Dev[DEV_SCREW].Props[P_AUTOSTART];
  PatternCmd := PatternActive;
  BlowerStopTimer := 0;

  if (Length(Pattern) = 0) or (PatStep < 0) or (PatStep > High(Pattern)) then
    PatStep := 0;
  if Length(Pattern) = 0 then
    PatternActive := False;
  if not ExtPatElapsed then
  begin
    if (PatStep <> FLastPatStep) or not PatternActive then
      PatElapsed := 0
    else
      PatElapsed += dt;
  end;
  FLastPatStep := PatStep;

  Filling := False;
  if not ExtSiloLevel then
    SiloLevel := 0;
  SiloLevel := EnsureRange(SiloLevel, 0, 100);

  RecordSignals;
end;

procedure TFluffSim.ResetRuntime;
var
  i: Integer;
begin
  { back to a clean state after a PLC session / source change }
  for i := 0 to DEV_COUNT - 1 do
  begin
    ClearDevice(Dev[i]);
    if not Dev[i].Installed then
      Dev[i].Reason := 'Not installed';
  end;
  Mode := smAutoStop;
  ExtRequest := False;
  EStopMain := False;
  BlowerCmd := False;
  ScrewCmd := False;
  PatternCmd := False;
  PatternActive := False;
  BlowerStopTimer := 0;
  PatStep := 0;
  PatElapsed := 0;
  SiloLevel := 75;
  Filling := False;
  CommOK := False;
  RecordSignals;
end;

{ ---------------- commands ---------------- }

procedure TFluffSim.CmdAutoStart;
begin
  if EStopMain then
  begin
    Log(-1, False, 'CMD Auto Start rejected: E-Stop active');
    Exit;
  end;
  Log(-1, True, 'CMD Auto Start');
  Mode := smAutoStart;
  BlowerStopTimer := 0;
end;

procedure TFluffSim.CmdAutoStop;
begin
  Log(-1, False, 'CMD Auto Stop');
  if Mode = smAutoStart then
  begin
    Mode := smAutoStop;
    ScrewCmd := False;
    PatternCmd := False;
    if BlowerCmd then
      BlowerStopTimer := Max(0.001, TAutoStopBlower);
  end;
end;

procedure TFluffSim.CmdEStop;
begin
  Log(-1, False, 'CMD E-STOP pressed');
  EStopMain := True;
  Mode := smAutoStop;
  BlowerStopTimer := 0;
  BlowerCmd := False;
  ScrewCmd := False;
  PatternCmd := False;
end;

procedure TFluffSim.CmdResetEStop;
begin
  if EStopMain then
    Log(-1, True, 'CMD E-Stop reset');
  EStopMain := False;
end;

procedure TFluffSim.SetExtRequest(V: Boolean);
begin
  if V = ExtRequest then Exit;
  ExtRequest := V;
  if Mode = smAutoStop then
    Log(-1, V, 'External Request ' + OnOff(V) + ' (Auto Stop mode: ignored)');
end;

procedure TFluffSim.CmdManualStart(I: Integer);
begin
  Log(-1, True, 'CMD ' + DevNames[I] + ' Manual Start');
  Dev[I].Props[P_MANSTART] := True;
  Dev[I].Props[P_MANSTOP] := False;
end;

procedure TFluffSim.CmdManualStop(I: Integer);
begin
  Log(-1, False, 'CMD ' + DevNames[I] + ' Manual Stop');
  Dev[I].Props[P_MANSTOP] := True;
  Dev[I].Props[P_MANSTART] := False;
end;

procedure TFluffSim.CmdManualRelease(I: Integer);
begin
  Log(-1, True, 'CMD ' + DevNames[I] + ' return to Auto');
  Dev[I].Props[P_MANSTOP] := False;
  Dev[I].Props[P_MANSTART] := False;
end;

procedure TFluffSim.CmdEnable(I: Integer);
begin
  Log(-1, True, 'CMD ' + DevNames[I] + ' Enable');
  Dev[I].Props[P_DISABLE] := False;
  Dev[I].Props[P_ENABLE] := True;
end;

procedure TFluffSim.CmdDisable(I: Integer);
begin
  Log(-1, False, 'CMD ' + DevNames[I] + ' Disable');
  Dev[I].Props[P_DISABLE] := True;
  Dev[I].Props[P_ENABLE] := False;
end;

procedure TFluffSim.CmdFault(I: Integer);
begin
  Log(-1, False, 'SIM ' + DevNames[I] + ' Fault injected');
  Dev[I].Props[P_FAULT] := True;
end;

procedure TFluffSim.CmdResetFault(I: Integer);
begin
  if Dev[I].Props[P_FAULT] then
    Log(-1, True, 'CMD ' + DevNames[I] + ' Fault reset');
  Dev[I].Props[P_FAULT] := False;
end;

procedure TFluffSim.LoadDefaultPattern;
begin
  SetPattern(DefaultPattern(PaddleCount));
end;

procedure TFluffSim.SetPattern(const P: TPattern);
var
  i: Integer;
begin
  Pattern := Copy(P, 0, Min(Length(P), MAX_STEPS));
  for i := 0 to High(Pattern) do
    Pattern[i].Duration := NormStepTime(Pattern[i].Duration);
  PatternChanged;
end;

procedure TFluffSim.PatternChanged;
begin
  Inc(PatternSeq);
  if Length(Pattern) = 0 then
  begin
    PatStep := 0;
    PatternActive := False;
  end
  else if PatStep > High(Pattern) then
  begin
    PatStep := 0;
    PatElapsed := 0;
  end;
end;

procedure TFluffSim.GetTimingInfo(L: TStrings);
var
  s: string;
begin
  L.Clear;
  if Mode = smAutoStart then s := 'AUTO START' else s := 'AUTO STOP';
  if EStopMain then s += '   [E-STOP ACTIVE]';
  L.Add('Mode: ' + s);
  if ExtRequest then
    L.Add(Format('External Request: ON  (held %.1f s)', [ReqOnTime]))
  else
    L.Add(Format('External Request: OFF (off %.1f s)', [ReqOffTime]));

  if Mode = smAutoStart then
  begin
    if not Dev[DEV_BLOWER].Running then
      L.Add('Blower01: waiting (blocked: ' + Dev[DEV_BLOWER].Reason + ')')
    else if not ScrewCmd then
    begin
      if Dev[DEV_BLOWER].RunTime < TBlowerToScrew then
        L.Add(Format('Blower->Screw delay: %.1f / %.1f s', [Dev[DEV_BLOWER].RunTime, TBlowerToScrew]))
      else if not ExtRequest then
        L.Add('Screw01: waiting External Request')
      else
        L.Add(Format('Request hold: %.1f / %.1f s', [ReqOnTime, TReqHold]));
    end
    else if not ExtRequest then
      L.Add(Format('Screw01 stop in %.1f s', [Max(0, TReqOffScrewStop - ReqOffTime)]))
    else if not PatternActive then
    begin
      if Dev[DEV_SCREW].Running then
        L.Add(Format('Screw->Paddle delay: %.1f / %.1f s', [Dev[DEV_SCREW].RunTime, TScrewToPaddle]))
      else
        L.Add('Screw01: cannot run (' + Dev[DEV_SCREW].Reason + ')');
    end;
  end
  else if BlowerStopTimer > 0 then
    L.Add(Format('Blower01 stop in %.1f s', [BlowerStopTimer]));

  if PatternActive then
    L.Add(Format('Pattern step %d/%d [%s]  %.1f / %.1f s',
      [PatStep + 1, Length(Pattern), StepText(PatStep), PatElapsed, Pattern[PatStep].Duration]))
  else
    L.Add(Format('Paddle Patterns: stopped  (%d steps, cycle %.1f s)', [Length(Pattern), CycleTime]));
end;

function TFluffSim.DevDelayText(I: Integer): string;
var
  k, nx: Integer;
begin
  Result := '';
  if not Dev[I].Installed then Exit;
  case I of
    DEV_BLOWER:
      if BlowerStopTimer > 0 then
        Result := Format('stop in %.1fs', [BlowerStopTimer]);
    DEV_SCREW:
      if Mode = smAutoStart then
      begin
        if (not ScrewCmd) and Dev[DEV_BLOWER].Running and (Dev[DEV_BLOWER].RunTime < TBlowerToScrew) then
          Result := Format('start in %.1fs', [TBlowerToScrew - Dev[DEV_BLOWER].RunTime])
        else if (not ScrewCmd) and Dev[DEV_BLOWER].Running and ExtRequest then
          Result := Format('start in %.1fs', [Max(0, TReqHold - ReqOnTime)])
        else if ScrewCmd and not ExtRequest then
          Result := Format('stop in %.1fs', [Max(0, TReqOffScrewStop - ReqOffTime)]);
      end;
  else
    if PatternActive and (Length(Pattern) > 0) then
    begin
      k := I - DEV_PADDLE1;
      if Pattern[PatStep].P[k] then
        Result := Format('step %d: %.1fs left', [PatStep + 1, Max(0, Pattern[PatStep].Duration - PatElapsed)])
      else
      begin
        nx := (PatStep + 1) mod Length(Pattern);
        if Pattern[nx].P[k] then
          Result := Format('next in %.1fs', [Max(0, Pattern[PatStep].Duration - PatElapsed)]);
      end;
    end
    else if (Mode = smAutoStart) and ScrewCmd and Dev[DEV_SCREW].Running and ExtRequest then
      Result := Format('pattern in %.1fs', [Max(0, TScrewToPaddle - Dev[DEV_SCREW].RunTime)]);
  end;
end;

end.
