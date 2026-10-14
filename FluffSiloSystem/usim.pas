unit uSim;

{ Fluff Silo simulation engine
  - 5 devices : Blower01, Screw01, Paddle01..03
  - 9 properties per device (+ Running feedback) with priority levels
  - Auto sequencer, External Request, Paddle Patterns
  - Signal history + event log for charts }

{$mode objfpc}{$H+}
{$COPERATORS ON}

interface

uses
  Classes, SysUtils, Math;

const
  DEV_COUNT   = 5;
  DEV_BLOWER  = 0;
  DEV_SCREW   = 1;
  DEV_PADDLE1 = 2;
  DEV_PADDLE2 = 3;
  DEV_PADDLE3 = 4;
  DevNames: array[0..DEV_COUNT - 1] of string =
    ('Blower01', 'Screw01', 'Paddle01', 'Paddle02', 'Paddle03');

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

  PADDLE_COUNT = 3;

type
  TSysMode = (smAutoStop, smAutoStart);
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
    function Running: Boolean;
    function Available: Boolean;
    function Visual: TDevVisual;
  end;

  TPatternStep = record
    P: array[0..PADDLE_COUNT - 1] of Boolean;
    Duration: Double;
  end;

  TSimEvent = record
    T: Double;
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
    procedure EvaluateDevice(D: TDevice; dt: Double);
    procedure RunPattern(dt: Double);
    procedure RecordSignals;
    procedure AddPoint(Id: Integer; V: Boolean);
    function StepHasPaddle(S: Integer): Boolean;
    function StepBlocked(S: Integer): Boolean;
    function FindNextStep(SkipPauses: Boolean): Integer;
    procedure GoStep(S: Integer; const Why: string);
  public
    Time: Double;
    Dev: array[0..DEV_COUNT - 1] of TDevice;
    Mode: TSysMode;
    ExtRequest: Boolean;
    ReqOnTime, ReqOffTime: Double;
    EStopMain: Boolean;
    BlowerCmd, ScrewCmd, PatternCmd, PatternActive: Boolean;
    BlowerStopTimer: Double;   { >0 while counting down to blower stop }
    Pattern: array of TPatternStep;
    PatStep: Integer;
    PatElapsed: Double;
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
    procedure Log(ASig: Integer; AValue: Boolean; const AText: string);
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
    procedure PatternChanged;
    function StepText(S: Integer): string;
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
function FmtTime(T: Double): string;
function OnOff(V: Boolean): string;

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

function FmtTime(T: Double): string;
var
  h, m: Integer;
  s: Double;
begin
  if T < 0 then T := 0;
  h := Trunc(T) div 3600;
  m := (Trunc(T) div 60) mod 60;
  s := T - h * 3600 - m * 60;
  Result := Format('%.2d:%.2d:%04.1f', [h, m, s]);
end;

function OnOff(V: Boolean): string;
begin
  if V then Result := 'ON' else Result := 'OFF';
end;

{ TDevice }

function TDevice.Running: Boolean;
begin
  Result := Props[P_RUNNING];
end;

function TDevice.Available: Boolean;
begin
  Result := not (Props[P_FAULT] or Props[P_ESTOP] or Props[P_DISABLE] or Props[P_MANSTOP]);
end;

function TDevice.Visual: TDevVisual;
begin
  if Props[P_FAULT] then Result := dvFault
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
  end;
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

procedure TFluffSim.EvaluateDevice(D: TDevice; dt: Double);
const
  SPEED: array[0..DEV_COUNT - 1] of Double = (14, 6, 3.5, 3.5, 3.5);
var
  run, wasRun: Boolean;
  lvl: Integer;
  why: string;
begin
  wasRun := D.Props[P_RUNNING];
  { highest level wins }
  if D.Props[P_FAULT] then begin run := False; lvl := 6; why := 'Fault'; end
  else if D.Props[P_ESTOP] then begin run := False; lvl := 6; why := 'E-Stop'; end
  else if D.Props[P_DISABLE] then begin run := False; lvl := 5; why := 'Disabled'; end
  else if D.Props[P_MANSTOP] then begin run := False; lvl := 4; why := 'Manual Stop'; end
  else if D.Props[P_MANSTART] then begin run := True; lvl := 3; why := 'Manual Start'; end
  else if D.Props[P_AUTOSTOP] then begin run := False; lvl := 2; why := 'Auto Stop'; end
  else if D.Props[P_INTERLOCK] then begin run := False; lvl := 2; why := 'Interlock'; end
  else if D.Props[P_AUTOSTART] then begin run := True; lvl := 1; why := 'Auto Start'; end
  else begin run := False; lvl := 0; why := 'Idle'; end;

  D.Props[P_RUNNING] := run;
  D.CtrlLevel := lvl;
  D.Reason := why;
  if run then
  begin
    if not wasRun then
      Inc(D.StartCount);
    D.RunTime += dt;
    D.TotalRunTime += dt;
    D.Phase += dt * SPEED[D.Index];
    if D.Phase > 2 * Pi * 1000 then
      D.Phase -= 2 * Pi * 1000;
  end
  else
    D.RunTime := 0;
end;

function TFluffSim.StepHasPaddle(S: Integer): Boolean;
var
  k: Integer;
begin
  Result := False;
  for k := 0 to PADDLE_COUNT - 1 do
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
  for k := 0 to PADDLE_COUNT - 1 do
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
var
  k: Integer;
begin
  Result := '';
  if (S < 0) or (S >= Length(Pattern)) then
    Exit('-');
  for k := 0 to PADDLE_COUNT - 1 do
    if Pattern[S].P[k] then
    begin
      if Result <> '' then Result += '+';
      Result += 'P' + IntToStr(k + 1);
    end;
  if Result = '' then
    Result := 'Pause';
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
  for k := 0 to PADDLE_COUNT - 1 do
    with Dev[DEV_PADDLE1 + k] do
    begin
      Props[P_AUTOSTART] := PatternActive and Pattern[PatStep].P[k];
      Props[P_AUTOSTOP] := Mode = smAutoStop;
      Props[P_INTERLOCK] := not screwRun;
    end;
  FPrevScrewRun := Dev[DEV_SCREW].Running;
  for i := 0 to DEV_COUNT - 1 do
  begin
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
    for k := 0 to PADDLE_COUNT - 1 do
      Dev[DEV_PADDLE1 + k].Props[P_AUTOSTART] := False;
    Mode := smAutoStop;
    BlowerStopTimer := Max(0.001, TScrewTripBlower);
    Log(-1, False, Format('Screw01 stopped -> Paddle Patterns stop, Blower01 stops in %.1fs',
      [TScrewTripBlower]));
    for k := 0 to PADDLE_COUNT - 1 do
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

  procedure Add(p1, p2, p3: Boolean; d: Double);
  var
    n: Integer;
  begin
    n := Length(Pattern);
    SetLength(Pattern, n + 1);
    Pattern[n].P[0] := p1;
    Pattern[n].P[1] := p2;
    Pattern[n].P[2] := p3;
    Pattern[n].Duration := d;
  end;

begin
  SetLength(Pattern, 0);
  Add(True, False, False, 8);
  Add(False, False, False, 2);
  Add(False, True, False, 8);
  Add(False, False, False, 2);
  Add(False, False, True, 8);
  Add(False, False, False, 2);
  PatternChanged;
end;

procedure TFluffSim.PatternChanged;
var
  i: Integer;
begin
  for i := 0 to High(Pattern) do
    if Pattern[i].Duration < 0.5 then
      Pattern[i].Duration := 0.5;
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
    L.Add('Paddle Patterns: stopped');
end;

function TFluffSim.DevDelayText(I: Integer): string;
var
  k, nx: Integer;
begin
  Result := '';
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
