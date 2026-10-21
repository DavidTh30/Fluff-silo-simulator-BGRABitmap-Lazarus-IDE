unit uPlcLink;

{ FluffSilo HMI2 - PLC link (Modbus TCP or Siemens S7)
  9 devices (Blower01, Screw01, Paddle01..07), pattern up to MAX_PLC_STEPS steps.
  The default map is documented in docs/HMI2_RegisterMap.md and exported to
  docs/RegisterMap_Default.csv (FluffSiloHMI2.exe --export-map <file>).
  - Hardware config : protocol, PLC IP / port / unit id or rack/slot
                      + register map (tag table, Modbus and S7 address per tag), saved to INI
  - TPlcThread      : background polling + write queue (never blocks the UI)
  - TPlcLink        : main-thread facade, copies PLC data into Sim (uSim)
  - Hmi* routines   : every operator action goes through here and is routed
                      either to the simulator or to the PLC }

{$mode objfpc}{$H+}
{$COPERATORS ON}

interface

uses
  Classes, SysUtils, Math, IniFiles, SyncObjs, uModbus, uS7, uSim;

const
  MAX_PLC_STEPS = MAX_STEPS;   { pattern steps reserved in the PLC (20) }
  S7_DEFAULT_DB = 10;
  DEV_CMD_COUNT = 6;
  DevCmdNames: array[0..DEV_CMD_COUNT - 1] of string =
    ('ManualStart', 'ManualStop', 'ReturnAuto', 'Enable', 'Disable', 'ResetFault');
  SYS_CMD_COUNT = 5;
  SysCmdNames: array[0..SYS_CMD_COUNT - 1] of string =
    ('AutoStart', 'AutoStop', 'EStop', 'ResetEStop', 'ExtRequest');
  DELAY_COUNT = 6;
  DelayKeys: array[0..DELAY_COUNT - 1] of string =
    ('BlowerToScrew', 'ReqHold', 'ScrewToPaddle', 'ReqOffScrewStop', 'ScrewTripBlower', 'AutoStopBlower');
  DelayDescs: array[0..DELAY_COUNT - 1] of string =
    ('Blower -> Screw start delay (s)', 'External Request hold time (s)',
     'Screw -> Paddle Patterns delay (s)', 'Request lost -> Screw stop (s)',
     'Screw stopped -> Blower stop (s)', 'Auto Stop -> Blower stop (s)');

type
  TPlcProtocol = (ppModbusTcp, ppS7);
  TMbArea = (maCoil, maDiscrete, maInputReg, maHoldingReg);
  TTagType = (ttBool, ttInt16, ttUInt16, ttInt32, ttFloat32);
  TTagAccess = (acRead, acWrite, acReadWrite);
  TLinkState = (lsStopped, lsConnecting, lsOnline, lsError);

  TTagDef = record
    Key: string;
    Group: string;
    Desc: string;
    Access: TTagAccess;
    Pulse: Boolean;        { command: write 1, then 0 after PulseMs }
    { Modbus }
    Area: TMbArea;
    Address: Integer;      { as typed by the user (see AddrBase) }
    Bit: Integer;          { -1 = whole value; 0..15 = bit inside a register }
    { Siemens S7, e.g. DB10.DBX0.0 / DB10.DBW20 / M10.3 / MW20 / Q0.1 }
    S7Addr: string;
    { common }
    DType: TTagType;
    Scale: Double;         { engineering = raw * Scale }
    Enabled: Boolean;
  end;
  TTagDefs = array of TTagDef;

  TPlcSettings = record
    Protocol: TPlcProtocol;
    Host: string;
    Port: Integer;
    UnitId: Integer;       { Modbus }
    S7Rack: Integer;       { S7: S7-300 = 0/2, S7-1200/1500 = 0/1 }
    S7Slot: Integer;
    S7ConnType: Integer;   { S7_CONN_PG / OP / BASIC }
    TimeoutMs: Integer;
    PollMs: Integer;
    PulseMs: Integer;
    AddrBase: Integer;     { 0 = protocol offset, 1 = 1-based (e.g. coil 1 = offset 0) }
    WordSwap: Boolean;     { 32-bit values: low word first }
    MaxGap: Integer;       { merge reads across gaps up to this many addresses }
    AutoConnect: Boolean;
    StartInPlc: Boolean;
  end;

  TDoubleArray = array of Double;

  TWriteReq = record
    Tag: Integer;
    Value: Double;
    Pulse: Boolean;
    Seq: Integer;
  end;

  TReadBlock = record
    Area: TMbArea;         { Modbus }
    S7Area: Byte;          { S7 }
    S7DB: Integer;
    Start: Integer;        { Modbus: protocol offset, S7: byte offset }
    Count: Integer;        { registers / bits (Modbus), bytes (S7) }
    Tags: array of Integer;
  end;

  { TPlcThread }

  TPlcThread = class(TThread)
  private
    FCfg: TPlcSettings;
    FTags: TTagDefs;
    FBlocks: array of TReadBlock;
    FClient: TModbusTcpClient;
    FS7: TS7Client;
    FS7Addr: array of TS7Address;
    FLock: TCriticalSection;
    FWake: TEvent;
    FQueue: array of TWriteReq;
    FResets: array of record Tag: Integer; Due: QWord; end;
    FDoneSeq: Integer;
    { shared, guarded by FLock }
    FValues: TDoubleArray;
    FValid: array of Boolean;
    FSnapSeq: Integer;
    FSnapWriteSeq: Integer;
    FState: TLinkState;
    FLastError: string;
    FWarn: string;
    FPollCount: Integer;
    FPollMs: Integer;
    procedure BuildBlocks;
    procedure BuildS7Blocks;
    function IsS7: Boolean;
    function LinkUp: Boolean;
    procedure LinkConnect;
    procedure LinkDisconnect;
    procedure DoReadsS7(var Vals: TDoubleArray; var Ok: array of Boolean; var Warn: string);
    procedure WriteTagS7(Idx: Integer; V: Double);
    procedure SetState(S: TLinkState; const Err: string);
    procedure Pause(Ms: Integer);
    procedure DoWrites;
    procedure DoReads;
    procedure WriteTag(Idx: Integer; V: Double);
    function TagOffset(Idx: Integer): Integer;
  protected
    procedure Execute; override;
  public
    constructor Create(const ACfg: TPlcSettings; const ATags: TTagDefs);
    destructor Destroy; override;
    procedure Queue(ATag: Integer; AValue: Double; APulse: Boolean; ASeq: Integer);
    procedure Shutdown;
  end;

  { TPlcLink }

  TPlcLink = class
  private
    FThread: TPlcThread;
    FWriteSeq: Integer;
    FLastSnap: Integer;
    FLastData: QWord;
    procedure ApplyToSim(WriteSeq: Integer);
  public
    Values: TDoubleArray;
    Valid: array of Boolean;
    State: TLinkState;
    LastError, Warn: string;
    PollCount, PollMs: Integer;
    destructor Destroy; override;
    procedure Start;
    procedure Stop;
    function Running: Boolean;
    function Online: Boolean;
    procedure Update;                  { main thread, every UI tick }
    function WriteTag(Idx: Integer; V: Double; APulse: Boolean = False): Boolean;
    function StatusText: string;
  end;

  THmiCmd = (hcAutoStart, hcAutoStop, hcEStop, hcResetEStop, hcExtRequest,
             hcManStart, hcManStop, hcManRelease, hcEnable, hcDisable, hcResetFault, hcFault);

  { HMI options (INI section [HMI]) }
  THmiOptions = record
    SimPaddleCount: Integer;   { paddles installed in simulation mode }
    LogToFile: Boolean;        { write every event to logs\HMI2_yyyymmdd.log }
    PatternDir: string;        { last folder used by Pattern to File / File to Pattern }
  end;

var
  PlcCfg: TPlcSettings;
  HmiOpt: THmiOptions;
  Tags: TTagDefs;
  Link: TPlcLink;
  { tag indices (-1 = not defined) }
  TagDevProp: array[0..DEV_COUNT - 1, 0..PROP_COUNT - 1] of Integer;
  TagSys: array[0..SYS_COUNT - 1] of Integer;
  TagSysCmd: array[0..SYS_CMD_COUNT - 1] of Integer;
  TagDevCmd: array[0..DEV_COUNT - 1, 0..DEV_CMD_COUNT - 1] of Integer;
  TagDelay: array[0..DELAY_COUNT - 1] of Integer;
  TagPatCount, TagPatStep, TagPatElapsed, TagSiloLevel, TagPaddleCount: Integer;
  TagPatMask, TagPatTime: array[0..MAX_PLC_STEPS - 1] of Integer;

{ config }
procedure DefaultSettings(out S: TPlcSettings);
function DefaultTags: TTagDefs;
procedure IndexTags;
function ConfigFileName: string;
procedure LoadConfig;
procedure SaveConfig;
function FindTag(const AKey: string): Integer;
function AreaName(A: TMbArea): string;
function AreaShort(A: TMbArea): string;
function TypeName(T: TTagType): string;
function AccessName(A: TTagAccess): string;
function TagUsable(Idx: Integer): Boolean;
function TagReadable(const T: TTagDef): Boolean;
function ValidateTags(const S: TPlcSettings; const ATags: TTagDefs; Errors: TStrings): Boolean;
procedure ExportTagsCsv(const AFile: string; const ATags: TTagDefs);
function ImportTagsCsv(const AFile: string; var ATags: TTagDefs; Log: TStrings): Integer;
function FormatTagValue(const T: TTagDef; V: Double): string;
function ProtocolName(P: TPlcProtocol): string;
function LinkTargetText: string;
function TagAddrText(const T: TTagDef; P: TPlcProtocol): string;
function ChangeS7DbNumber(var ATags: TTagDefs; OldDb, NewDb: Integer): Integer;

{ HMI routing: simulator or PLC }
function PlcMode: Boolean;
procedure SetDataSource(ASource: TDataSource);
procedure HmiCommand(C: THmiCmd; ADev: Integer = -1);
procedure HmiSetExtRequest(V: Boolean);
procedure HmiSetDelay(Idx: Integer; V: Double);
procedure HmiSetPaddleCount(N: Integer);
{ "Pattern to PLC": the whole table, only changed steps are written }
function HmiPatternWrite(const P: TPattern): Integer;
function SimDelay(Idx: Integer): Double;
function TargetName: string;   { 'PLC' or 'Simulator' }

implementation

{ ======================= config ======================= }

function AreaName(A: TMbArea): string;
begin
  case A of
    maCoil: Result := '0x Coil';
    maDiscrete: Result := '1x Discrete Input';
    maInputReg: Result := '3x Input Register';
  else
    Result := '4x Holding Register';
  end;
end;

function AreaShort(A: TMbArea): string;
begin
  case A of
    maCoil: Result := 'COIL';
    maDiscrete: Result := 'DI';
    maInputReg: Result := 'IR';
  else
    Result := 'HR';
  end;
end;

function TypeName(T: TTagType): string;
begin
  case T of
    ttBool: Result := 'BOOL';
    ttInt16: Result := 'INT16';
    ttUInt16: Result := 'UINT16';
    ttInt32: Result := 'INT32';
  else
    Result := 'FLOAT32';
  end;
end;

function AccessName(A: TTagAccess): string;
begin
  case A of
    acRead: Result := 'R';
    acWrite: Result := 'W';
  else
    Result := 'RW';
  end;
end;

function ParseArea(const S: string; out A: TMbArea): Boolean;
var
  u: string;
begin
  u := UpperCase(Trim(S));
  Result := True;
  if (u = 'COIL') or (Copy(u, 1, 2) = '0X') then A := maCoil
  else if (u = 'DI') or (Copy(u, 1, 2) = '1X') then A := maDiscrete
  else if (u = 'IR') or (Copy(u, 1, 2) = '3X') then A := maInputReg
  else if (u = 'HR') or (Copy(u, 1, 2) = '4X') then A := maHoldingReg
  else Result := False;
end;

function ParseType(const S: string; out T: TTagType): Boolean;
var
  u: string;
begin
  u := UpperCase(Trim(S));
  Result := True;
  if u = 'BOOL' then T := ttBool
  else if u = 'INT16' then T := ttInt16
  else if u = 'UINT16' then T := ttUInt16
  else if u = 'INT32' then T := ttInt32
  else if (u = 'FLOAT32') or (u = 'REAL') then T := ttFloat32
  else Result := False;
end;

function FloatStr(V: Double): string;
var
  fs: TFormatSettings;
begin
  fs := DefaultFormatSettings;
  fs.DecimalSeparator := '.';
  Result := FloatToStr(V, fs);
end;

function StrFloat(const S: string; Def: Double): Double;
var
  fs: TFormatSettings;
begin
  fs := DefaultFormatSettings;
  fs.DecimalSeparator := '.';
  if not TryStrToFloat(Trim(S), Result, fs) then
    Result := Def;
end;

procedure DefaultSettings(out S: TPlcSettings);
begin
  S.Protocol := ppModbusTcp;
  S.Host := '192.168.1.10';
  S.Port := 502;
  S.UnitId := 1;
  S.S7Rack := 0;
  S.S7Slot := 1;
  S.S7ConnType := S7_CONN_PG;
  S.TimeoutMs := 1000;
  S.PollMs := 200;
  S.PulseMs := 500;
  S.AddrBase := 0;
  S.WordSwap := False;
  S.MaxGap := 0;
  S.AutoConnect := False;
  S.StartInPlc := False;
end;

procedure DefaultHmiOptions(out O: THmiOptions);
begin
  O.SimPaddleCount := MAX_PADDLES;
  O.LogToFile := True;
  O.PatternDir := '';
end;

function DefaultTags: TTagDefs;
var
  n: Integer;

  procedure Add(const AKey, AGroup, ADesc: string; AAcc: TTagAccess; APulse: Boolean;
    AArea: TMbArea; AAddr: Integer; AType: TTagType; AScale: Double; const AS7: string);
  begin
    SetLength(Result, n + 1);
    with Result[n] do
    begin
      Key := AKey;
      Group := AGroup;
      Desc := ADesc;
      Access := AAcc;
      Pulse := APulse;
      Area := AArea;
      Address := AAddr;
      Bit := -1;
      DType := AType;
      Scale := AScale;
      Enabled := True;
      S7Addr := Format('DB%d.', [S7_DEFAULT_DB]) + AS7;
    end;
    Inc(n);
  end;

var
  d, p, c, s: Integer;
begin
  { default register map - see docs/HMI2_RegisterMap.md
    Modbus (protocol offsets)                 S7 DB10 (non-optimized "DB_HMI")
      coil 100 + dev*10 + prop  dev status      DBX(dev*2 + prop div 8).(prop mod 8)   DBB0..17
      coil 200..203  system status              DBX18.0..3
      coil 210..214  main commands              DBX20.0..4
      coil 300 + dev*10 + cmd  device commands  DBX(22 + dev).cmd                      DBB22..30
      HR 0..5    delays (0.1 s)                 DBW32..42
      HR 10..12  step, elapsed, silo level      DBW44 / 46 / 48
      HR 15      paddles installed              DBW52
      HR 20      step count                     DBW56
      HR 21..40  step masks (bit k = Paddle k+1) DBW58..96
      HR 41..60  step times (0.1 s)             DBW98..136 }
  n := 0;
  Result := nil;
  for d := 0 to DEV_COUNT - 1 do
    for p := 0 to PROP_COUNT - 1 do
      Add(DevNames[d] + '.' + StringReplace(PropNames[p], ' ', '', [rfReplaceAll]),
        'Device Status', DevNames[d] + ' ' + PropNames[p] + ' (L' + IntToStr(PropLevels[p]) + ')',
        acRead, False, maCoil, 100 + d * 10 + p, ttBool, 1, Format('DBX%d.%d', [d * 2 + p div 8, p mod 8]));
  Add('System.AutoMode', 'System Status', 'Auto Start mode active', acRead, False, maCoil, 200, ttBool, 1, 'DBX18.0');
  Add('System.ExtRequest', 'System Status', 'External Request', acRead, False, maCoil, 201, ttBool, 1, 'DBX18.1');
  Add('System.PatternActive', 'System Status', 'Paddle Patterns running', acRead, False, maCoil, 202, ttBool, 1,
    'DBX18.2');
  Add('System.EStop', 'System Status', 'E-Stop (Main) active', acRead, False, maCoil, 203, ttBool, 1, 'DBX18.3');
  Add('Cmd.AutoStart', 'Command', 'Auto Start push button (pulse)', acWrite, True, maCoil, 210, ttBool, 1, 'DBX20.0');
  Add('Cmd.AutoStop', 'Command', 'Auto Stop push button (pulse)', acWrite, True, maCoil, 211, ttBool, 1, 'DBX20.1');
  Add('Cmd.EStop', 'Command', 'HMI E-Stop push button (pulse)', acWrite, True, maCoil, 212, ttBool, 1, 'DBX20.2');
  Add('Cmd.ResetEStop', 'Command', 'Reset E-Stop (pulse)', acWrite, True, maCoil, 213, ttBool, 1, 'DBX20.3');
  Add('Cmd.ExtRequest', 'Command', 'HMI External Request (maintained 1/0)', acWrite, False, maCoil, 214, ttBool, 1,
    'DBX20.4');
  for d := 0 to DEV_COUNT - 1 do
    for c := 0 to DEV_CMD_COUNT - 1 do
      Add(DevNames[d] + '.Cmd.' + DevCmdNames[c], 'Device Command',
        DevNames[d] + ' ' + DevCmdNames[c] + ' (pulse)', acWrite, True, maCoil, 300 + d * 10 + c, ttBool, 1,
        Format('DBX%d.%d', [22 + d, c]));
  for s := 0 to DELAY_COUNT - 1 do
    Add('Delay.' + DelayKeys[s], 'Parameter', DelayDescs[s], acReadWrite, False,
      maHoldingReg, s, ttUInt16, 0.1, Format('DBW%d', [32 + s * 2]));
  Add('Pattern.CurrentStep', 'Process', 'Active pattern step (1-based, 0 = none)', acRead, False,
    maHoldingReg, 10, ttUInt16, 1, 'DBW44');
  Add('Pattern.StepElapsed', 'Process', 'Elapsed time of active step (s)', acRead, False,
    maHoldingReg, 11, ttUInt16, 0.1, 'DBW46');
  Add('Silo.Level', 'Process', 'Silo level (%)', acRead, False, maHoldingReg, 12, ttUInt16, 0.1, 'DBW48');
  Add('Config.PaddleCount', 'Config', Format('Paddles installed (1..%d)', [MAX_PADDLES]), acReadWrite, False,
    maHoldingReg, 15, ttUInt16, 1, 'DBW52');
  Add('Pattern.StepCount', 'Pattern', 'Number of pattern steps (0..' + IntToStr(MAX_PLC_STEPS) + ')',
    acReadWrite, False, maHoldingReg, 20, ttUInt16, 1, 'DBW56');
  for s := 0 to MAX_PLC_STEPS - 1 do
    Add(Format('Pattern.Step%.2d.Mask', [s + 1]), 'Pattern',
      Format('Step %d paddles: bit0=P1 .. bit6=P7 (0 = pause)', [s + 1]), acReadWrite, False,
      maHoldingReg, 21 + s, ttUInt16, 1, Format('DBW%d', [58 + s * 2]));
  for s := 0 to MAX_PLC_STEPS - 1 do
    Add(Format('Pattern.Step%.2d.Time', [s + 1]), 'Pattern', Format('Step %d duration (s)', [s + 1]),
      acReadWrite, False, maHoldingReg, 41 + s, ttUInt16, 0.1, Format('DBW%d', [98 + s * 2]));
end;

function LinkTargetText: string;
begin
  if PlcCfg.Protocol = ppS7 then
    Result := Format('S7 %s  rack %d slot %d', [PlcCfg.Host, PlcCfg.S7Rack, PlcCfg.S7Slot])
  else
    Result := Format('Modbus %s:%d  unit %d', [PlcCfg.Host, PlcCfg.Port, PlcCfg.UnitId]);
end;

function ProtocolName(P: TPlcProtocol): string;
begin
  if P = ppS7 then
    Result := 'Siemens S7'
  else
    Result := 'Modbus TCP';
end;

function TagAddrText(const T: TTagDef; P: TPlcProtocol): string;
begin
  if P = ppS7 then
    Result := T.S7Addr
  else
  begin
    Result := AreaShort(T.Area) + ' ' + IntToStr(T.Address);
    if T.Bit >= 0 then
      Result := Result + '.' + IntToStr(T.Bit);
  end;
end;

function ChangeS7DbNumber(var ATags: TTagDefs; OldDb, NewDb: Integer): Integer;
var
  i: Integer;
  a: TS7Address;
  prefix: string;
begin
  { DB10.DBX0.0 -> DB<NewDb>.DBX0.0 for every tag in DB<OldDb> }
  Result := 0;
  prefix := 'DB' + IntToStr(NewDb) + '.';
  for i := 0 to High(ATags) do
    if ParseS7Address(ATags[i].S7Addr, a) and (a.Area = S7_AREA_DB) and (a.DB = OldDb) then
    begin
      ATags[i].S7Addr := prefix + Copy(ATags[i].S7Addr, Pos('.', ATags[i].S7Addr) + 1, MaxInt);
      Inc(Result);
    end;
end;

function FindTag(const AKey: string): Integer;
var
  i: Integer;
begin
  for i := 0 to High(Tags) do
    if SameText(Tags[i].Key, AKey) then
      Exit(i);
  Result := -1;
end;

procedure IndexTags;
var
  d, p, s: Integer;
begin
  for d := 0 to DEV_COUNT - 1 do
  begin
    for p := 0 to PROP_COUNT - 1 do
      TagDevProp[d, p] := FindTag(DevNames[d] + '.' + StringReplace(PropNames[p], ' ', '', [rfReplaceAll]));
    for p := 0 to DEV_CMD_COUNT - 1 do
      TagDevCmd[d, p] := FindTag(DevNames[d] + '.Cmd.' + DevCmdNames[p]);
  end;
  TagSys[SYS_EXTREQ] := FindTag('System.ExtRequest');
  TagSys[SYS_AUTOMODE] := FindTag('System.AutoMode');
  TagSys[SYS_PATTERN] := FindTag('System.PatternActive');
  TagSys[SYS_ESTOP] := FindTag('System.EStop');
  for s := 0 to SYS_CMD_COUNT - 1 do
    TagSysCmd[s] := FindTag('Cmd.' + SysCmdNames[s]);
  for s := 0 to DELAY_COUNT - 1 do
    TagDelay[s] := FindTag('Delay.' + DelayKeys[s]);
  TagPatCount := FindTag('Pattern.StepCount');
  TagPatStep := FindTag('Pattern.CurrentStep');
  TagPatElapsed := FindTag('Pattern.StepElapsed');
  TagSiloLevel := FindTag('Silo.Level');
  TagPaddleCount := FindTag('Config.PaddleCount');
  for s := 0 to MAX_PLC_STEPS - 1 do
  begin
    TagPatMask[s] := FindTag(Format('Pattern.Step%.2d.Mask', [s + 1]));
    TagPatTime[s] := FindTag(Format('Pattern.Step%.2d.Time', [s + 1]));
  end;
end;

function TagUsable(Idx: Integer): Boolean;
begin
  Result := (Idx >= 0) and (Idx <= High(Tags)) and Tags[Idx].Enabled;
end;

function TagReadable(const T: TTagDef): Boolean;
begin
  Result := T.Enabled and (T.Access in [acRead, acReadWrite]);
end;

function ConfigFileName: string;
begin
  Result := ChangeFileExt(ParamStr(0), '.ini');
end;

function TagToStr(const T: TTagDef): string;
begin
  Result := Format('%s,%d,%d,%s,%s,%d,%s',
    [AreaShort(T.Area), T.Address, T.Bit, TypeName(T.DType), FloatStr(T.Scale), Ord(T.Enabled), T.S7Addr]);
end;

procedure StrToTag(const S: string; var T: TTagDef);
var
  sl: TStringList;
  a: TMbArea;
  ty: TTagType;
begin
  sl := TStringList.Create;
  try
    sl.StrictDelimiter := True;
    sl.Delimiter := ',';
    sl.DelimitedText := S;
    if sl.Count < 6 then Exit;
    if ParseArea(sl[0], a) then T.Area := a;
    T.Address := StrToIntDef(sl[1], T.Address);
    T.Bit := StrToIntDef(sl[2], T.Bit);
    if ParseType(sl[3], ty) then T.DType := ty;
    T.Scale := StrFloat(sl[4], T.Scale);
    T.Enabled := sl[5] <> '0';
    if (sl.Count >= 7) and (Trim(sl[6]) <> '') then
      T.S7Addr := Trim(sl[6]);
  finally
    sl.Free;
  end;
end;

procedure LoadConfig;
var
  ini: TIniFile;
  i: Integer;
  s: string;
begin
  DefaultSettings(PlcCfg);
  DefaultHmiOptions(HmiOpt);
  Tags := DefaultTags;
  if FileExists(ConfigFileName) then
  begin
    ini := TIniFile.Create(ConfigFileName);
    try
      if SameText(ini.ReadString('PLC', 'Protocol', 'Modbus'), 'S7') then
        PlcCfg.Protocol := ppS7;
      PlcCfg.Host := ini.ReadString('PLC', 'Host', PlcCfg.Host);
      PlcCfg.Port := ini.ReadInteger('PLC', 'Port', PlcCfg.Port);
      PlcCfg.UnitId := ini.ReadInteger('PLC', 'UnitId', PlcCfg.UnitId);
      PlcCfg.S7Rack := ini.ReadInteger('PLC', 'S7Rack', PlcCfg.S7Rack);
      PlcCfg.S7Slot := ini.ReadInteger('PLC', 'S7Slot', PlcCfg.S7Slot);
      PlcCfg.S7ConnType := ini.ReadInteger('PLC', 'S7ConnType', PlcCfg.S7ConnType);
      PlcCfg.TimeoutMs := ini.ReadInteger('PLC', 'TimeoutMs', PlcCfg.TimeoutMs);
      PlcCfg.PollMs := ini.ReadInteger('PLC', 'PollMs', PlcCfg.PollMs);
      PlcCfg.PulseMs := ini.ReadInteger('PLC', 'PulseMs', PlcCfg.PulseMs);
      PlcCfg.AddrBase := ini.ReadInteger('PLC', 'AddrBase', PlcCfg.AddrBase);
      PlcCfg.WordSwap := ini.ReadBool('PLC', 'WordSwap', PlcCfg.WordSwap);
      PlcCfg.MaxGap := ini.ReadInteger('PLC', 'MaxGap', PlcCfg.MaxGap);
      PlcCfg.AutoConnect := ini.ReadBool('PLC', 'AutoConnect', PlcCfg.AutoConnect);
      PlcCfg.StartInPlc := ini.ReadBool('PLC', 'StartInPlc', PlcCfg.StartInPlc);
      HmiOpt.SimPaddleCount := EnsureRange(ini.ReadInteger('HMI', 'SimPaddleCount', HmiOpt.SimPaddleCount),
        1, MAX_PADDLES);
      HmiOpt.LogToFile := ini.ReadBool('HMI', 'LogToFile', HmiOpt.LogToFile);
      HmiOpt.PatternDir := ini.ReadString('HMI', 'PatternDir', HmiOpt.PatternDir);
      for i := 0 to High(Tags) do
      begin
        s := ini.ReadString('Tags', Tags[i].Key, '');
        if s <> '' then
          StrToTag(s, Tags[i]);
      end;
    finally
      ini.Free;
    end;
  end;
  IndexTags;
end;

procedure SaveConfig;
var
  ini: TIniFile;
  i: Integer;
begin
  ini := TIniFile.Create(ConfigFileName);
  try
    if PlcCfg.Protocol = ppS7 then
      ini.WriteString('PLC', 'Protocol', 'S7')
    else
      ini.WriteString('PLC', 'Protocol', 'Modbus');
    ini.WriteString('PLC', 'Host', PlcCfg.Host);
    ini.WriteInteger('PLC', 'Port', PlcCfg.Port);
    ini.WriteInteger('PLC', 'UnitId', PlcCfg.UnitId);
    ini.WriteInteger('PLC', 'S7Rack', PlcCfg.S7Rack);
    ini.WriteInteger('PLC', 'S7Slot', PlcCfg.S7Slot);
    ini.WriteInteger('PLC', 'S7ConnType', PlcCfg.S7ConnType);
    ini.WriteInteger('PLC', 'TimeoutMs', PlcCfg.TimeoutMs);
    ini.WriteInteger('PLC', 'PollMs', PlcCfg.PollMs);
    ini.WriteInteger('PLC', 'PulseMs', PlcCfg.PulseMs);
    ini.WriteInteger('PLC', 'AddrBase', PlcCfg.AddrBase);
    ini.WriteBool('PLC', 'WordSwap', PlcCfg.WordSwap);
    ini.WriteInteger('PLC', 'MaxGap', PlcCfg.MaxGap);
    ini.WriteBool('PLC', 'AutoConnect', PlcCfg.AutoConnect);
    ini.WriteBool('PLC', 'StartInPlc', PlcCfg.StartInPlc);
    ini.WriteInteger('HMI', 'SimPaddleCount', HmiOpt.SimPaddleCount);
    ini.WriteBool('HMI', 'LogToFile', HmiOpt.LogToFile);
    ini.WriteString('HMI', 'PatternDir', HmiOpt.PatternDir);
    ini.EraseSection('Tags');
    for i := 0 to High(Tags) do
      ini.WriteString('Tags', Tags[i].Key, TagToStr(Tags[i]));
    ini.UpdateFile;
  finally
    ini.Free;
  end;
end;

function ValidateTags(const S: TPlcSettings; const ATags: TTagDefs; Errors: TStrings): Boolean;
var
  i, off: Integer;
  t: TTagDef;
  a: TS7Address;
begin
  Errors.Clear;
  if Trim(S.Host) = '' then Errors.Add('PLC IP address is empty');
  if (S.Port < 1) or (S.Port > 65535) then Errors.Add('Port must be 1..65535');
  if S.Protocol = ppS7 then
  begin
    if (S.S7Rack < 0) or (S.S7Rack > 7) then Errors.Add('Rack must be 0..7');
    if (S.S7Slot < 0) or (S.S7Slot > 31) then Errors.Add('Slot must be 0..31');
    for i := 0 to High(ATags) do
    begin
      t := ATags[i];
      if not t.Enabled then Continue;
      if not ParseS7Address(t.S7Addr, a) then
      begin
        Errors.Add(Format('%s: invalid S7 address "%s"', [t.Key, t.S7Addr]));
        Continue;
      end;
      case t.DType of
        ttBool:
          if a.Size <> 0 then
            Errors.Add(Format('%s: BOOL needs a bit address (e.g. DB10.DBX0.0, M10.3)', [t.Key]));
        ttInt16, ttUInt16:
          if not (a.Size in [1, 2]) or ((a.Size = 1) and (t.DType = ttInt16)) then
            Errors.Add(Format('%s: INT16 needs a word (DBW / MW), UINT16 a word or byte', [t.Key]));
        ttInt32, ttFloat32:
          if a.Size <> 4 then
            Errors.Add(Format('%s: INT32 / FLOAT32 (DINT / REAL) needs a double word (DBD / MD)', [t.Key]));
      end;
      if (t.Access in [acWrite, acReadWrite]) and (a.Area = S7_AREA_PE) then
        Errors.Add(Format('%s: inputs (I) are overwritten by the PLC, use DB / M / Q for writable tags', [t.Key]));
      if (t.DType <> ttBool) and (t.Scale = 0) then
        Errors.Add(Format('%s: scale must not be 0', [t.Key]));
    end;
    Exit(Errors.Count = 0);
  end;
  if (S.UnitId < 0) or (S.UnitId > 255) then Errors.Add('Unit ID must be 0..255');
  for i := 0 to High(ATags) do
  begin
    t := ATags[i];
    if not t.Enabled then Continue;
    off := t.Address - S.AddrBase;
    if (off < 0) or (off > 65535) then
      Errors.Add(Format('%s: address %d out of range', [t.Key, t.Address]))
    else if (t.DType in [ttInt32, ttFloat32]) and (off > 65534) then
      Errors.Add(Format('%s: 32-bit value needs 2 registers', [t.Key]));
    if (t.Access in [acWrite, acReadWrite]) and (t.Area in [maDiscrete, maInputReg]) then
      Errors.Add(Format('%s: %s is read-only, writable tag needs Coil or Holding Register',
        [t.Key, AreaName(t.Area)]));
    if (t.Area in [maCoil, maDiscrete]) and (t.DType <> ttBool) then
      Errors.Add(Format('%s: coils / discrete inputs can only hold BOOL', [t.Key]));
    if (t.Bit < -1) or (t.Bit > 15) then
      Errors.Add(Format('%s: bit must be -1 (none) or 0..15', [t.Key]));
    if (t.Bit >= 0) and ((t.DType <> ttBool) or (t.Area in [maCoil, maDiscrete])) then
      Errors.Add(Format('%s: bit index is only for BOOL inside a register', [t.Key]));
    if (t.DType <> ttBool) and (t.Scale = 0) then
      Errors.Add(Format('%s: scale must not be 0', [t.Key]));
  end;
  Result := Errors.Count = 0;
end;

procedure ExportTagsCsv(const AFile: string; const ATags: TTagDefs);
var
  sl: TStringList;
  i: Integer;
  t: TTagDef;
begin
  sl := TStringList.Create;
  try
    sl.Add('Key;Group;Access;Area;Address;Bit;Type;Scale;Enabled;S7Address;Description');
    for i := 0 to High(ATags) do
    begin
      t := ATags[i];
      sl.Add(Format('%s;%s;%s;%s;%d;%d;%s;%s;%d;%s;%s',
        [t.Key, t.Group, AccessName(t.Access), AreaShort(t.Area), t.Address, t.Bit,
         TypeName(t.DType), FloatStr(t.Scale), Ord(t.Enabled), t.S7Addr, t.Desc]));
    end;
    sl.SaveToFile(AFile);
  finally
    sl.Free;
  end;
end;

function ImportTagsCsv(const AFile: string; var ATags: TTagDefs; Log: TStrings): Integer;
var
  sl, f: TStringList;
  i, k, j, cS7: Integer;
  a: TMbArea;
  ty: TTagType;
begin
  Result := 0;
  sl := TStringList.Create;
  f := TStringList.Create;
  try
    sl.LoadFromFile(AFile);
    f.StrictDelimiter := True;
    f.Delimiter := ';';
    { the S7 column was added later: locate it by the header }
    cS7 := -1;
    if sl.Count > 0 then
    begin
      f.DelimitedText := sl[0];
      for j := 0 to f.Count - 1 do
        if SameText(Trim(f[j]), 'S7Address') then
          cS7 := j;
    end;
    for i := 1 to sl.Count - 1 do
    begin
      if Trim(sl[i]) = '' then Continue;
      f.DelimitedText := sl[i];
      if f.Count < 9 then
      begin
        Log.Add(Format('line %d: not enough columns', [i + 1]));
        Continue;
      end;
      k := -1;
      for j := 0 to High(ATags) do
        if SameText(ATags[j].Key, Trim(f[0])) then
        begin
          k := j;
          Break;
        end;
      if k < 0 then
      begin
        Log.Add(Format('line %d: unknown tag "%s"', [i + 1, f[0]]));
        Continue;
      end;
      if ParseArea(f[3], a) then ATags[k].Area := a
      else Log.Add(Format('line %d: bad area "%s"', [i + 1, f[3]]));
      ATags[k].Address := StrToIntDef(Trim(f[4]), ATags[k].Address);
      ATags[k].Bit := StrToIntDef(Trim(f[5]), ATags[k].Bit);
      if ParseType(f[6], ty) then ATags[k].DType := ty
      else Log.Add(Format('line %d: bad type "%s"', [i + 1, f[6]]));
      ATags[k].Scale := StrFloat(f[7], ATags[k].Scale);
      ATags[k].Enabled := Trim(f[8]) <> '0';
      if (cS7 >= 0) and (cS7 < f.Count) then
        ATags[k].S7Addr := Trim(f[cS7]);
      Inc(Result);
    end;
  finally
    f.Free;
    sl.Free;
  end;
end;

function FormatTagValue(const T: TTagDef; V: Double): string;
begin
  if T.DType = ttBool then
    Result := OnOff(V > 0.5)
  else if (Frac(T.Scale) = 0) and (T.DType <> ttFloat32) then
    Result := FormatFloat('0', V)
  else
    Result := FormatFloat('0.###', V);
end;

{ ======================= TPlcThread ======================= }

function EncodeRaw(const T: TTagDef; V: Double; Swap: Boolean; out W: array of Word): Integer; forward;
function DecodeRaw(const T: TTagDef; const W: array of Word; Swap: Boolean): Double; forward;

constructor TPlcThread.Create(const ACfg: TPlcSettings; const ATags: TTagDefs);
var
  i: Integer;
begin
  FCfg := ACfg;
  FTags := Copy(ATags);
  FLock := TCriticalSection.Create;
  FWake := TEvent.Create(nil, False, False, '');
  SetLength(FValues, Length(FTags));
  SetLength(FValid, Length(FTags));
  FState := lsConnecting;
  if IsS7 then
  begin
    { S7 blocks depend on the negotiated PDU size: built after connect }
    SetLength(FS7Addr, Length(FTags));
    for i := 0 to High(FTags) do
      if not ParseS7Address(FTags[i].S7Addr, FS7Addr[i]) then
        FTags[i].Enabled := False;
  end
  else
    BuildBlocks;
  inherited Create(False);
end;

function TPlcThread.IsS7: Boolean;
begin
  Result := FCfg.Protocol = ppS7;
end;

function TPlcThread.LinkUp: Boolean;
begin
  if IsS7 then
    Result := (FS7 <> nil) and FS7.Connected
  else
    Result := (FClient <> nil) and FClient.Connected;
end;

procedure TPlcThread.LinkConnect;
begin
  if IsS7 then
  begin
    if FS7 = nil then
      FS7 := TS7Client.Create(FCfg.Host, FCfg.Port, FCfg.S7Rack, FCfg.S7Slot, FCfg.S7ConnType, FCfg.TimeoutMs);
    FS7.Connect;
    BuildS7Blocks;
  end
  else
  begin
    if FClient = nil then
      FClient := TModbusTcpClient.Create(FCfg.Host, FCfg.Port, FCfg.UnitId, FCfg.TimeoutMs);
    FClient.Connect;
  end;
end;

procedure TPlcThread.LinkDisconnect;
begin
  if FS7 <> nil then FS7.Disconnect;
  if FClient <> nil then FClient.Disconnect;
end;

procedure TPlcThread.BuildS7Blocks;
var
  idx: array of Integer;
  i, j, n, t, b, len, lim, s0, e0: Integer;
  a, ta: TS7Address;

  function Less(x, y: Integer): Boolean;
  begin
    with FS7Addr[x] do
      if Area <> FS7Addr[y].Area then Exit(Area < FS7Addr[y].Area)
      else if DB <> FS7Addr[y].DB then Exit(DB < FS7Addr[y].DB)
      else Exit(Start < FS7Addr[y].Start);
  end;

begin
  SetLength(FBlocks, 0);
  lim := Max(16, FS7.MaxReadBytes);
  SetLength(idx, 0);
  for i := 0 to High(FTags) do
    if TagReadable(FTags[i]) then
    begin
      n := Length(idx);
      SetLength(idx, n + 1);
      j := n;
      while (j > 0) and Less(i, idx[j - 1]) do
      begin
        idx[j] := idx[j - 1];
        Dec(j);
      end;
      idx[j] := i;
    end;
  b := -1;
  for i := 0 to High(idx) do
  begin
    t := idx[i];
    ta := FS7Addr[t];
    len := Max(1, ta.Size);
    if b >= 0 then
    begin
      a.Area := FBlocks[b].S7Area;
      a.DB := FBlocks[b].S7DB;
      s0 := FBlocks[b].Start;
      e0 := s0 + FBlocks[b].Count;
    end;
    if (b >= 0) and (ta.Area = a.Area) and (ta.DB = a.DB) and (ta.Start <= e0 + FCfg.MaxGap) and
       (Max(e0, ta.Start + len) - s0 <= lim) then
      FBlocks[b].Count := Max(e0, ta.Start + len) - s0
    else
    begin
      b := Length(FBlocks);
      SetLength(FBlocks, b + 1);
      FBlocks[b].S7Area := ta.Area;
      FBlocks[b].S7DB := ta.DB;
      FBlocks[b].Start := ta.Start;
      FBlocks[b].Count := len;
      SetLength(FBlocks[b].Tags, 0);
    end;
    n := Length(FBlocks[b].Tags);
    SetLength(FBlocks[b].Tags, n + 1);
    FBlocks[b].Tags[n] := t;
  end;
end;

procedure TPlcThread.DoReadsS7(var Vals: TDoubleArray; var Ok: array of Boolean; var Warn: string);
var
  i, k, t, rel: Integer;
  buf: TBytes;
  w: array[0..1] of Word;
  ad: TS7Address;
  def: TTagDef;
begin
  for i := 0 to High(FBlocks) do
    with FBlocks[i] do
      try
        buf := FS7.ReadArea(S7Area, S7DB, Start, Count);
        for k := 0 to High(Tags) do
        begin
          t := Tags[k];
          ad := FS7Addr[t];
          rel := ad.Start - Start;
          case ad.Size of
            0: Vals[t] := (buf[rel] shr ad.Bit) and 1;
            1: Vals[t] := buf[rel] * FTags[t].Scale;
          else
            begin
              { S7 is big-endian: decode as two words, high word first }
              w[0] := (buf[rel] shl 8) or buf[rel + 1];
              w[1] := 0;
              if ad.Size = 4 then
                w[1] := (buf[rel + 2] shl 8) or buf[rel + 3];
              def := FTags[t];
              def.Bit := -1;
              Vals[t] := DecodeRaw(def, w, False);
            end;
          end;
          Ok[t] := True;
        end;
      except
        on E: EPlcDevice do
          if S7Area = S7_AREA_DB then
            Warn := Format('Read DB%d.DBB%d..%d: %s', [S7DB, Start, Start + Count - 1, E.Message])
          else
            Warn := Format('Read %sB%d..%d: %s', [S7AreaName(S7Area), Start, Start + Count - 1, E.Message]);
      end;
end;

procedure TPlcThread.WriteTagS7(Idx: Integer; V: Double);
var
  ad: TS7Address;
  w: array[0..1] of Word;
  data: TBytes;
  def: TTagDef;
begin
  ad := FS7Addr[Idx];
  if ad.Size = 0 then
  begin
    FS7.WriteBit(ad.Area, ad.DB, ad.Start, ad.Bit, V > 0.5);
    Exit;
  end;
  def := FTags[Idx];
  def.Bit := -1;
  if ad.Size = 1 then
  begin
    if def.Scale <> 0 then V := V / def.Scale;
    data := TBytes.Create(Byte(EnsureRange(Round(V), 0, 255)));
  end
  else
  begin
    EncodeRaw(def, V, False, w);
    if ad.Size = 2 then
      data := TBytes.Create(Hi(w[0]), Lo(w[0]))
    else
      data := TBytes.Create(Hi(w[0]), Lo(w[0]), Hi(w[1]), Lo(w[1]));
  end;
  FS7.WriteArea(ad.Area, ad.DB, ad.Start, data);
end;

destructor TPlcThread.Destroy;
begin
  FWake.Free;
  FLock.Free;
  inherited Destroy;
end;

procedure TPlcThread.Shutdown;
begin
  Terminate;
  FWake.SetEvent;
end;

function TPlcThread.TagOffset(Idx: Integer): Integer;
begin
  Result := FTags[Idx].Address - FCfg.AddrBase;
end;

procedure TPlcThread.BuildBlocks;
const
  MAX_REGS = 120;
  MAX_BITS = 1900;
var
  a: TMbArea;
  idx: array of Integer;
  i, j, n, t, off, len, lim, b: Integer;
begin
  SetLength(FBlocks, 0);
  for a := Low(TMbArea) to High(TMbArea) do
  begin
    { collect readable tags of this area, sorted by offset }
    SetLength(idx, 0);
    for i := 0 to High(FTags) do
      if TagReadable(FTags[i]) and (FTags[i].Area = a) and (TagOffset(i) >= 0) and (TagOffset(i) <= 65535) then
      begin
        n := Length(idx);
        SetLength(idx, n + 1);
        j := n;
        while (j > 0) and (TagOffset(idx[j - 1]) > TagOffset(i)) do
        begin
          idx[j] := idx[j - 1];
          Dec(j);
        end;
        idx[j] := i;
      end;
    if a in [maCoil, maDiscrete] then lim := MAX_BITS else lim := MAX_REGS;
    b := -1;
    for i := 0 to High(idx) do
    begin
      t := idx[i];
      off := TagOffset(t);
      if FTags[t].DType in [ttInt32, ttFloat32] then len := 2 else len := 1;
      if (b >= 0) and (off <= FBlocks[b].Start + FBlocks[b].Count + FCfg.MaxGap) and
         (Max(FBlocks[b].Count, off + len - FBlocks[b].Start) <= lim) then
        FBlocks[b].Count := Max(FBlocks[b].Count, off + len - FBlocks[b].Start)
      else
      begin
        b := Length(FBlocks);
        SetLength(FBlocks, b + 1);
        FBlocks[b].Area := a;
        FBlocks[b].Start := off;
        FBlocks[b].Count := len;
        SetLength(FBlocks[b].Tags, 0);
      end;
      n := Length(FBlocks[b].Tags);
      SetLength(FBlocks[b].Tags, n + 1);
      FBlocks[b].Tags[n] := t;
    end;
  end;
end;

procedure TPlcThread.SetState(S: TLinkState; const Err: string);
begin
  FLock.Enter;
  try
    FState := S;
    FLastError := Err;
  finally
    FLock.Leave;
  end;
end;

procedure TPlcThread.Pause(Ms: Integer);
begin
  if Ms > 0 then
    FWake.WaitFor(Ms);
end;

procedure TPlcThread.Queue(ATag: Integer; AValue: Double; APulse: Boolean; ASeq: Integer);
var
  n: Integer;
begin
  FLock.Enter;
  try
    n := Length(FQueue);
    SetLength(FQueue, n + 1);
    FQueue[n].Tag := ATag;
    FQueue[n].Value := AValue;
    FQueue[n].Pulse := APulse;
    FQueue[n].Seq := ASeq;
  finally
    FLock.Leave;
  end;
  FWake.SetEvent;
end;

function EncodeRaw(const T: TTagDef; V: Double; Swap: Boolean; out W: array of Word): Integer;
var
  i32: LongInt;
  sg: Single;
  lw: LongWord;
begin
  if T.DType = ttBool then
  begin
    W[0] := Ord(V > 0.5);
    Exit(1);
  end;
  if T.Scale <> 0 then V := V / T.Scale;
  case T.DType of
    ttInt16:
      begin
        W[0] := Word(SmallInt(EnsureRange(Round(V), -32768, 32767)));
        Result := 1;
      end;
    ttUInt16:
      begin
        W[0] := Word(EnsureRange(Round(V), 0, 65535));
        Result := 1;
      end;
    ttInt32:
      begin
        i32 := LongInt(EnsureRange(Round(V), Int64(-2147483648), Int64(2147483647)));
        lw := LongWord(i32);
        Result := 2;
      end;
  else
    begin
      sg := V;
      Move(sg, lw, 4);
      Result := 2;
    end;
  end;
  if Result = 2 then
  begin
    if Swap then
    begin
      W[0] := Lo(lw);
      W[1] := Hi(lw);
    end
    else
    begin
      W[0] := Hi(lw);
      W[1] := Lo(lw);
    end;
  end;
end;

function DecodeRaw(const T: TTagDef; const W: array of Word; Swap: Boolean): Double;
var
  lw: LongWord;
  sg: Single;
begin
  case T.DType of
    ttBool:
      if T.Bit >= 0 then
        Result := (W[0] shr T.Bit) and 1
      else
        Result := Ord(W[0] <> 0);
    ttInt16: Result := SmallInt(W[0]);
    ttUInt16: Result := W[0];
  else
    begin
      if Swap then
        lw := (LongWord(W[1]) shl 16) or W[0]
      else
        lw := (LongWord(W[0]) shl 16) or W[1];
      if T.DType = ttInt32 then
        Result := LongInt(lw)
      else
      begin
        Move(lw, sg, 4);
        Result := sg;
      end;
    end;
  end;
  if (T.DType <> ttBool) and (T.Scale <> 0) then
    Result := Result * T.Scale;
end;

procedure TPlcThread.WriteTag(Idx: Integer; V: Double);
var
  t: TTagDef;
  off, n: Integer;
  w: array[0..1] of Word;
  cur: TWordArray;
begin
  if IsS7 then
  begin
    WriteTagS7(Idx, V);
    Exit;
  end;
  t := FTags[Idx];
  off := TagOffset(Idx);
  case t.Area of
    maCoil:
      FClient.WriteCoil(off, V > 0.5);
    maHoldingReg:
      if (t.DType = ttBool) and (t.Bit >= 0) then
      begin
        { bit inside a register: read - modify - write }
        cur := FClient.ReadRegs(3, off, 1);
        if V > 0.5 then
          cur[0] := cur[0] or (1 shl t.Bit)
        else
          cur[0] := cur[0] and not Word(1 shl t.Bit);
        FClient.WriteReg(off, cur[0]);
      end
      else
      begin
        n := EncodeRaw(t, V, FCfg.WordSwap, w);
        if n = 1 then
          FClient.WriteReg(off, w[0])
        else
          FClient.WriteRegs(off, [w[0], w[1]]);
      end;
  else
    raise EModbusDevice.Create(t.Key + ' is in a read-only area');
  end;
end;

procedure TPlcThread.DoWrites;
var
  q: array of TWriteReq;
  i, n, maxSeq: Integer;
  now: QWord;
begin
  FLock.Enter;
  try
    q := FQueue;
    FQueue := nil;
  finally
    FLock.Leave;
  end;
  maxSeq := FDoneSeq;
  for i := 0 to High(q) do
  begin
    try
      WriteTag(q[i].Tag, q[i].Value);
      if q[i].Pulse and (q[i].Value > 0.5) then
      begin
        n := Length(FResets);
        SetLength(FResets, n + 1);
        FResets[n].Tag := q[i].Tag;
        FResets[n].Due := GetTickCount64 + QWord(Max(50, FCfg.PulseMs));
      end;
    except
      on E: EPlcDevice do
      begin
        FLock.Enter;
        FWarn := 'Write ' + FTags[q[i].Tag].Key + ': ' + E.Message;
        FLock.Leave;
      end;
    end;
    maxSeq := Max(maxSeq, q[i].Seq);
  end;
  FDoneSeq := maxSeq;

  { finish pulses that are due }
  now := GetTickCount64;
  i := 0;
  while i <= High(FResets) do
    if FResets[i].Due <= now then
    begin
      try
        WriteTag(FResets[i].Tag, 0);
      except
        on E: EPlcDevice do ;
      end;
      FResets[i] := FResets[High(FResets)];
      SetLength(FResets, Length(FResets) - 1);
    end
    else
      Inc(i);
end;

procedure TPlcThread.DoReads;
var
  vals: TDoubleArray;
  ok: array of Boolean;
  i, k, t, rel: Integer;
  bits: TBoolArray;
  regs: TWordArray;
  warn: string;
  w: array[0..1] of Word;
  t0: QWord;
  seq: Integer;
begin
  t0 := GetTickCount64;
  seq := FDoneSeq;   { every write queued up to here is already in the PLC }
  SetLength(vals, Length(FTags));
  SetLength(ok, Length(FTags));
  warn := '';
  if IsS7 then
    DoReadsS7(vals, ok, warn)
  else
  for i := 0 to High(FBlocks) do
    with FBlocks[i] do
      try
        if Area in [maCoil, maDiscrete] then
        begin
          if Area = maCoil then
            bits := FClient.ReadBits(1, Start, Count)
          else
            bits := FClient.ReadBits(2, Start, Count);
          for k := 0 to High(Tags) do
          begin
            t := Tags[k];
            vals[t] := Ord(bits[TagOffset(t) - Start]);
            ok[t] := True;
          end;
        end
        else
        begin
          if Area = maHoldingReg then
            regs := FClient.ReadRegs(3, Start, Count)
          else
            regs := FClient.ReadRegs(4, Start, Count);
          for k := 0 to High(Tags) do
          begin
            t := Tags[k];
            rel := TagOffset(t) - Start;
            w[0] := regs[rel];
            if rel + 1 < Count then w[1] := regs[rel + 1] else w[1] := 0;
            vals[t] := DecodeRaw(FTags[t], w, FCfg.WordSwap);
            ok[t] := True;
          end;
        end;
      except
        on E: EPlcDevice do
          warn := Format('Read %s %d..%d: %s', [AreaShort(Area), Start + FCfg.AddrBase,
            Start + FCfg.AddrBase + Count - 1, E.Message]);
      end;

  FLock.Enter;
  try
    FValues := vals;
    FValid := ok;
    Inc(FSnapSeq);
    FSnapWriteSeq := seq;
    Inc(FPollCount);
    FPollMs := GetTickCount64 - t0;
    if warn <> '' then
      FWarn := warn
    else if Copy(FWarn, 1, 5) = 'Read ' then
      FWarn := '';
    FState := lsOnline;
    FLastError := '';
  finally
    FLock.Leave;
  end;
end;

procedure TPlcThread.Execute;
begin
  try
    while not Terminated do
    begin
      if not LinkUp then
      begin
        SetState(lsConnecting, '');
        try
          LinkConnect;
        except
          on E: Exception do
          begin
            LinkDisconnect;
            SetState(lsError, 'Connect ' + FCfg.Host + ':' + IntToStr(FCfg.Port) + ' - ' + E.Message);
            Pause(2000);
            Continue;
          end;
        end;
      end;
      try
        DoWrites;
        if Terminated then Break;
        DoReads;
      except
        on E: Exception do
        begin
          LinkDisconnect;
          SetState(lsError, E.Message);
          Pause(1000);
          Continue;
        end;
      end;
      if Length(FResets) > 0 then
        Pause(Min(FCfg.PollMs, 50))
      else
        Pause(FCfg.PollMs);
    end;
    { leave no pulse stuck at 1 }
    if LinkUp then
      try
        while Length(FResets) > 0 do
        begin
          WriteTag(FResets[High(FResets)].Tag, 0);
          SetLength(FResets, Length(FResets) - 1);
        end;
      except
      end;
  finally
    FreeAndNil(FClient);
    FreeAndNil(FS7);
  end;
end;

{ ======================= TPlcLink ======================= }

destructor TPlcLink.Destroy;
begin
  Stop;
  inherited Destroy;
end;

procedure TPlcLink.Start;
begin
  Stop;
  SetLength(Values, Length(Tags));
  SetLength(Valid, Length(Tags));
  FillChar(Valid[0], Length(Valid) * SizeOf(Boolean), 0);
  FLastSnap := 0;
  FWriteSeq := 0;
  FLastData := 0;
  State := lsConnecting;
  LastError := '';
  Warn := '';
  PollCount := 0;
  FThread := TPlcThread.Create(PlcCfg, Tags);
  if PlcCfg.Protocol = ppS7 then
    Sim.Log(-1, True, Format('PLC link start  S7  %s:%d  rack %d slot %d (%s)', [PlcCfg.Host, PlcCfg.Port,
      PlcCfg.S7Rack, PlcCfg.S7Slot, S7ConnTypeName(PlcCfg.S7ConnType)]))
  else
    Sim.Log(-1, True, Format('PLC link start  Modbus TCP  %s:%d  unit %d', [PlcCfg.Host, PlcCfg.Port,
      PlcCfg.UnitId]));
end;

procedure TPlcLink.Stop;
begin
  if FThread = nil then Exit;
  FThread.Shutdown;
  FThread.WaitFor;
  FreeAndNil(FThread);
  State := lsStopped;
  if Sim <> nil then
  begin
    Sim.CommOK := False;
    Sim.Log(-1, False, 'PLC link stopped');
  end;
end;

function TPlcLink.Running: Boolean;
begin
  Result := FThread <> nil;
end;

function TPlcLink.Online: Boolean;
begin
  Result := Running and (State = lsOnline);
end;

procedure TPlcLink.Update;
var
  snap, wseq: Integer;
  oldState: TLinkState;
begin
  if FThread = nil then Exit;
  oldState := State;
  FThread.FLock.Enter;
  try
    State := FThread.FState;
    LastError := FThread.FLastError;
    Warn := FThread.FWarn;
    PollCount := FThread.FPollCount;
    PollMs := FThread.FPollMs;
    snap := FThread.FSnapSeq;
    wseq := FThread.FSnapWriteSeq;
    if snap <> FLastSnap then
    begin
      Values := Copy(FThread.FValues);
      Valid := Copy(FThread.FValid);
    end;
  finally
    FThread.FLock.Leave;
  end;
  if State <> oldState then
  begin
    if State = lsOnline then
      Sim.Log(-1, True, 'PLC online ' + PlcCfg.Host)
    else if State = lsError then
      Sim.Log(-1, False, 'PLC communication error: ' + LastError);
  end;
  if snap <> FLastSnap then
  begin
    FLastSnap := snap;
    FLastData := GetTickCount64;
    if Sim.Source = dsPLC then
      ApplyToSim(wseq);
  end;
  { data older than 3 poll periods (min 2 s) is stale }
  Sim.CommOK := (State = lsOnline) and
    (GetTickCount64 - FLastData < QWord(Max(2000, PlcCfg.PollMs * 3)));
end;

function TPlcLink.WriteTag(Idx: Integer; V: Double; APulse: Boolean): Boolean;
begin
  Result := False;
  if (FThread = nil) or not TagUsable(Idx) then Exit;
  if not (Tags[Idx].Access in [acWrite, acReadWrite]) then Exit;
  Inc(FWriteSeq);
  FThread.Queue(Idx, V, APulse, FWriteSeq);
  Result := True;
end;

procedure TPlcLink.ApplyToSim(WriteSeq: Integer);

  function Get(Idx: Integer; out V: Double): Boolean;
  begin
    Result := TagUsable(Idx) and (Idx <= High(Valid)) and Valid[Idx];
    if Result then V := Values[Idx];
  end;

  function GetB(Idx: Integer; Def: Boolean): Boolean;
  var
    v: Double;
  begin
    if Get(Idx, v) then Result := v > 0.5 else Result := Def;
  end;

var
  d, p, n, s: Integer;
  v: Double;
  paramsFresh: Boolean;
  np: TPattern;
begin
  if Get(TagPaddleCount, v) and (WriteSeq >= FWriteSeq) then
    Sim.SetPaddleCount(Round(v));
  for d := 0 to DEV_COUNT - 1 do
  begin
    for p := 0 to PROP_COUNT - 1 do
      Sim.Dev[d].Props[p] := GetB(TagDevProp[d, p], False);
    if not TagUsable(TagDevProp[d, P_ENABLE]) then
      Sim.Dev[d].Props[P_ENABLE] := not Sim.Dev[d].Props[P_DISABLE];
  end;
  if GetB(TagSys[SYS_AUTOMODE], False) then Sim.Mode := smAutoStart else Sim.Mode := smAutoStop;
  Sim.ExtRequest := GetB(TagSys[SYS_EXTREQ], False);
  Sim.EStopMain := GetB(TagSys[SYS_ESTOP], False);
  Sim.ExtSiloLevel := Get(TagSiloLevel, v);
  if Sim.ExtSiloLevel then Sim.SiloLevel := v;
  Sim.ExtPatElapsed := Get(TagPatElapsed, v);
  if Sim.ExtPatElapsed then Sim.PatElapsed := v;

  { parameters: skip snapshots taken before our own pending writes reached the PLC }
  paramsFresh := WriteSeq >= FWriteSeq;
  if paramsFresh then
  begin
    for s := 0 to DELAY_COUNT - 1 do
      if Get(TagDelay[s], v) then
        case s of
          0: Sim.TBlowerToScrew := v;
          1: Sim.TReqHold := v;
          2: Sim.TScrewToPaddle := v;
          3: Sim.TReqOffScrewStop := v;
          4: Sim.TScrewTripBlower := v;
          5: Sim.TAutoStopBlower := v;
        end;
    if Get(TagPatCount, v) then
    begin
      n := EnsureRange(Round(v), 0, MAX_PLC_STEPS);
      SetLength(np, n);
      for s := 0 to n - 1 do
      begin
        if Get(TagPatMask[s], v) then
          SetStepMask(np[s], Round(v))
        else
          SetStepMask(np[s], 0);
        if Get(TagPatTime[s], v) then
          np[s].Duration := v
        else
          np[s].Duration := 0;
      end;
      { compare all mask bits: the PLC table is shown as it is }
      if not PatternsEqual(np, Sim.Pattern, MAX_PADDLES) then
      begin
        Sim.Pattern := np;
        Sim.PatternChanged;
      end;
    end;
  end;

  Sim.PatternActive := GetB(TagSys[SYS_PATTERN], False) and (Length(Sim.Pattern) > 0);
  if Get(TagPatStep, v) then
    Sim.PatStep := EnsureRange(Round(v) - 1, 0, Max(0, High(Sim.Pattern)));
end;

function TPlcLink.StatusText: string;
begin
  case State of
    lsStopped: Result := 'Disconnected';
    lsConnecting: Result := 'Connecting ' + PlcCfg.Host + ' ...';
    lsOnline: Result := Format('ONLINE %s %s  polls %d  (%d ms)',
      [ProtocolName(PlcCfg.Protocol), PlcCfg.Host, PollCount, PollMs]);
  else
    Result := 'ERROR: ' + LastError;
  end;
  if (State = lsOnline) and (Warn <> '') then
    Result := Result + '  ! ' + Warn;
end;

{ ======================= HMI routing ======================= }

function PlcMode: Boolean;
begin
  Result := (Sim <> nil) and (Sim.Source = dsPLC);
end;

procedure SetDataSource(ASource: TDataSource);
begin
  if Sim.Source = ASource then Exit;
  if ASource = dsPLC then
  begin
    Sim.ResetRuntime;
    Sim.Source := dsPLC;
    Sim.Log(-1, True, 'Data source: PLC (' + ProtocolName(PlcCfg.Protocol) + ')');
  end
  else
  begin
    Link.Stop;
    Sim.Source := dsSimulation;
    Sim.SetPaddleCount(HmiOpt.SimPaddleCount);
    Sim.ResetRuntime;
    Sim.ExtPatElapsed := False;
    Sim.ExtSiloLevel := False;
    Sim.LoadDefaultPattern;
    Sim.Log(-1, True, 'Data source: Simulation');
  end;
end;

function CmdText(C: THmiCmd): string;
begin
  case C of
    hcAutoStart: Result := 'Auto Start';
    hcAutoStop: Result := 'Auto Stop';
    hcEStop: Result := 'E-STOP';
    hcResetEStop: Result := 'Reset E-Stop';
    hcExtRequest: Result := 'External Request';
    hcManStart: Result := 'Manual Start';
    hcManStop: Result := 'Manual Stop';
    hcManRelease: Result := 'Return to Auto';
    hcEnable: Result := 'Enable';
    hcDisable: Result := 'Disable';
    hcResetFault: Result := 'Reset Fault';
  else
    Result := 'Fault';
  end;
end;

procedure PlcWrite(Idx: Integer; V: Double; APulse: Boolean; const What: string);
begin
  if not TagUsable(Idx) then
    Sim.Log(-1, False, 'HMI ' + What + ': no PLC tag configured (Hardware Config)')
  else if not Link.Running then
    Sim.Log(-1, False, 'HMI ' + What + ': PLC not connected')
  else if Link.WriteTag(Idx, V, APulse) then
    Sim.Log(-1, V > 0.5, Format('HMI %s -> %s [%s]', [What, Tags[Idx].Key,
      TagAddrText(Tags[Idx], PlcCfg.Protocol)]))
  else
    Sim.Log(-1, False, 'HMI ' + What + ': tag ' + Tags[Idx].Key + ' is not writable');
end;

procedure HmiCommand(C: THmiCmd; ADev: Integer);
const
  DEVCMD: array[hcManStart..hcResetFault] of Integer = (0, 1, 2, 3, 4, 5);
var
  tag: Integer;
begin
  if not PlcMode then
  begin
    case C of
      hcAutoStart: Sim.CmdAutoStart;
      hcAutoStop: Sim.CmdAutoStop;
      hcEStop: Sim.CmdEStop;
      hcResetEStop: Sim.CmdResetEStop;
      hcExtRequest: Sim.SetExtRequest(not Sim.ExtRequest);
      hcManStart: Sim.CmdManualStart(ADev);
      hcManStop: Sim.CmdManualStop(ADev);
      hcManRelease: Sim.CmdManualRelease(ADev);
      hcEnable: Sim.CmdEnable(ADev);
      hcDisable: Sim.CmdDisable(ADev);
      hcResetFault: Sim.CmdResetFault(ADev);
      hcFault: Sim.CmdFault(ADev);
    end;
    Exit;
  end;
  case C of
    hcAutoStart..hcResetEStop:
      PlcWrite(TagSysCmd[Ord(C)], 1, True, CmdText(C));
    hcExtRequest:
      HmiSetExtRequest(not Sim.ExtRequest);
    hcManStart..hcResetFault:
      begin
        tag := TagDevCmd[ADev, DEVCMD[C]];
        PlcWrite(tag, 1, True, DevNames[ADev] + ' ' + CmdText(C));
      end;
    hcFault:
      Sim.Log(-1, False, 'Simulate Fault is not available in PLC mode');
  end;
end;

procedure HmiSetExtRequest(V: Boolean);
begin
  if PlcMode then
    PlcWrite(TagSysCmd[4], Ord(V), False, 'External Request ' + OnOff(V))
  else
    Sim.SetExtRequest(V);
end;

function SimDelay(Idx: Integer): Double;
begin
  case Idx of
    0: Result := Sim.TBlowerToScrew;
    1: Result := Sim.TReqHold;
    2: Result := Sim.TScrewToPaddle;
    3: Result := Sim.TReqOffScrewStop;
    4: Result := Sim.TScrewTripBlower;
  else
    Result := Sim.TAutoStopBlower;
  end;
end;

procedure HmiSetDelay(Idx: Integer; V: Double);
begin
  if Abs(SimDelay(Idx) - V) < 1e-6 then Exit;
  case Idx of
    0: Sim.TBlowerToScrew := V;
    1: Sim.TReqHold := V;
    2: Sim.TScrewToPaddle := V;
    3: Sim.TReqOffScrewStop := V;
    4: Sim.TScrewTripBlower := V;
    5: Sim.TAutoStopBlower := V;
  end;
  if PlcMode then
    PlcWrite(TagDelay[Idx], V, False, Format('set %s = %.1f s', [DelayKeys[Idx], V]));
end;

function TargetName: string;
begin
  if PlcMode then Result := 'PLC' else Result := 'Simulator';
end;

procedure HmiSetPaddleCount(N: Integer);
begin
  N := EnsureRange(N, 1, MAX_PADDLES);
  if PlcMode then
    PlcWrite(TagPaddleCount, N, False, Format('paddles installed = %d', [N]))
  else
    Sim.SetPaddleCount(N);
end;

function HmiPatternWrite(const P: TPattern): Integer;
var
  n, old, s: Integer;
  cur: TPattern;
begin
  { returns the number of values sent (simulator: number of steps) }
  n := Min(Length(P), MAX_PLC_STEPS);
  if not PlcMode then
  begin
    Sim.SetPattern(P);
    Sim.Log(-1, True, Format('Pattern -> Simulator: %d steps, cycle %.1f s', [n, Sim.CycleTime]));
    Exit(n);
  end;
  Result := 0;
  if not Link.Running then
  begin
    Sim.Log(-1, False, 'Pattern -> PLC: PLC not connected');
    Exit;
  end;
  cur := Sim.Pattern;
  old := Length(cur);
  Sim.Log(-1, True, Format('Pattern -> PLC: %d steps (was %d)', [n, old]));
  { shrinking: lower the count first so the PLC never runs a half-written table }
  if n < old then
  begin
    PlcWrite(TagPatCount, n, False, 'pattern step count');
    Inc(Result);
  end;
  for s := 0 to n - 1 do
  begin
    if (s >= old) or (StepMask(cur[s]) <> StepMask(P[s])) then
    begin
      PlcWrite(TagPatMask[s], StepMask(P[s]), False, Format('pattern step %d mask', [s + 1]));
      Inc(Result);
    end;
    if (s >= old) or (Abs(cur[s].Duration - P[s].Duration) > 0.05) then
    begin
      PlcWrite(TagPatTime[s], NormStepTime(P[s].Duration), False, Format('pattern step %d time', [s + 1]));
      Inc(Result);
    end;
  end;
  if n >= old then
  begin
    PlcWrite(TagPatCount, n, False, 'pattern step count');
    Inc(Result);
  end;
end;

initialization
  DefaultSettings(PlcCfg);
  DefaultHmiOptions(HmiOpt);
  Tags := DefaultTags;
  IndexTags;
  Link := TPlcLink.Create;

finalization
  FreeAndNil(Link);

end.
