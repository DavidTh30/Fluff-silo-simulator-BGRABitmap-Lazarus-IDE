unit uS7;

{ Minimal blocking Siemens S7 client (S7comm over ISO-on-TCP, RFC1006, port 102).
  Read / write of DB, M (merker), I (inputs), Q (outputs) as bytes or single bits.
  Works with S7-300/400 and S7-1200/1500 (PUT/GET access enabled, DB not
  "optimized block access"). Used only from the PLC worker thread. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, ssockets, uModbus;

const
  S7_AREA_PE = $81;   { I  inputs   }
  S7_AREA_PA = $82;   { Q  outputs  }
  S7_AREA_MK = $83;   { M  merkers  }
  S7_AREA_DB = $84;   { DB          }

  S7_CONN_PG = 1;
  S7_CONN_OP = 2;
  S7_CONN_BASIC = 3;

type
  ES7 = class(Exception);
  ES7Device = class(EPlcDevice);

  TS7Address = record
    Area: Byte;
    DB: Integer;
    Start: Integer;     { byte offset }
    Bit: Integer;       { 0..7 for bit addresses, -1 otherwise }
    Size: Integer;      { 0 = bit, 1 = byte, 2 = word, 4 = dword }
  end;

  { TS7Client }

  TS7Client = class
  private
    FSock: TInetSocket;
    FHost: string;
    FPort: Word;
    FRack, FSlot, FConnType: Integer;
    FTimeout: Integer;
    FPduRef: Word;
    FPduSize: Integer;
    procedure ReadExact(var Buf; Count: Integer);
    procedure SendTpkt(const Payload: TBytes);
    function RecvTpkt: TBytes;
    function Exchange(const S7: TBytes): TBytes;
  public
    constructor Create(const AHost: string; APort: Word; ARack, ASlot, AConnType, ATimeoutMs: Integer);
    destructor Destroy; override;
    procedure Connect;
    procedure Disconnect;
    function Connected: Boolean;
    function MaxReadBytes: Integer;
    function ReadArea(Area: Byte; DB, Start, Count: Integer): TBytes;
    procedure WriteArea(Area: Byte; DB, Start: Integer; const Data: TBytes);
    procedure WriteBit(Area: Byte; DB, ByteAddr, Bit: Integer; V: Boolean);
    property PduSize: Integer read FPduSize;
  end;

function ParseS7Address(const S: string; out A: TS7Address): Boolean;
function S7AreaName(Area: Byte): string;
function S7ConnTypeName(T: Integer): string;

implementation

function S7AreaName(Area: Byte): string;
begin
  case Area of
    S7_AREA_PE: Result := 'I';
    S7_AREA_PA: Result := 'Q';
    S7_AREA_MK: Result := 'M';
  else
    Result := 'DB';
  end;
end;

function S7ConnTypeName(T: Integer): string;
begin
  case T of
    S7_CONN_OP: Result := 'OP';
    S7_CONN_BASIC: Result := 'S7 Basic';
  else
    Result := 'PG';
  end;
end;

function ItemErrorText(Code: Byte): string;
begin
  case Code of
    $01: Result := 'Hardware fault';
    $03: Result := 'Access denied (enable PUT/GET, DB must not be optimized)';
    $05: Result := 'Address out of range';
    $06: Result := 'Data type not supported';
    $07: Result := 'Data type inconsistent';
    $0A: Result := 'Object does not exist (DB?)';
  else
    Result := Format('Item error $%.2x', [Code]);
  end;
end;

{ Accepts (with or without %):  DB10.DBX0.0  DB10.DBB4  DB10.DBW20  DB10.DBD40
  M10.3  MB5  MW20  MD24   I0.0 / E0.0  IB0  IW0   Q0.1 / A0.1  QB0  QW0 }
function ParseS7Address(const S: string; out A: TS7Address): Boolean;
var
  u, rest: string;
  p: Integer;

  function TakeNum(var T: string; out N: Integer): Boolean;
  var
    k: Integer;
  begin
    k := 1;
    while (k <= Length(T)) and (T[k] in ['0'..'9']) do Inc(k);
    Result := (k > 1) and TryStrToInt(Copy(T, 1, k - 1), N);
    Delete(T, 1, k - 1);
  end;

  function SizeCode(C: Char; out Sz: Integer): Boolean;
  begin
    Result := True;
    case C of
      'X': Sz := 0;
      'B': Sz := 1;
      'W': Sz := 2;
      'D': Sz := 4;
    else
      Result := False;
    end;
  end;

  function OffsetAndBit(var T: string): Boolean;
  begin
    Result := TakeNum(T, A.Start);
    if not Result then Exit;
    if A.Size = 0 then
    begin
      Result := (Length(T) >= 2) and (T[1] = '.');
      if not Result then Exit;
      Delete(T, 1, 1);
      Result := TakeNum(T, A.Bit) and (A.Bit >= 0) and (A.Bit <= 7);
    end;
    Result := Result and (T = '');
  end;

begin
  Result := False;
  A.Area := S7_AREA_DB;
  A.DB := 0;
  A.Start := 0;
  A.Bit := -1;
  A.Size := 1;
  u := UpperCase(StringReplace(StringReplace(Trim(S), '%', '', [rfReplaceAll]), ' ', '', [rfReplaceAll]));
  if u = '' then Exit;
  if Copy(u, 1, 2) = 'DB' then
  begin
    rest := Copy(u, 3, MaxInt);
    if not TakeNum(rest, A.DB) or (A.DB < 1) or (A.DB > 65535) then Exit;
    if Copy(rest, 1, 3) <> '.DB' then Exit;
    Delete(rest, 1, 3);
    if (rest = '') or not SizeCode(rest[1], A.Size) then Exit;
    Delete(rest, 1, 1);
    Result := OffsetAndBit(rest);
    Exit;
  end;
  case u[1] of
    'I', 'E': A.Area := S7_AREA_PE;
    'Q', 'A': A.Area := S7_AREA_PA;
    'M': A.Area := S7_AREA_MK;
  else
    Exit;
  end;
  rest := Copy(u, 2, MaxInt);
  if rest = '' then Exit;
  if rest[1] in ['0'..'9'] then
    A.Size := 0
  else
  begin
    if not SizeCode(rest[1], A.Size) then Exit;
    Delete(rest, 1, 1);
  end;
  p := Length(rest);
  Result := (p > 0) and OffsetAndBit(rest);
end;

{ TS7Client }

constructor TS7Client.Create(const AHost: string; APort: Word; ARack, ASlot, AConnType,
  ATimeoutMs: Integer);
begin
  inherited Create;
  FHost := AHost;
  FPort := APort;
  FRack := ARack;
  FSlot := ASlot;
  FConnType := AConnType;
  FTimeout := ATimeoutMs;
  FPduSize := 240;
end;

destructor TS7Client.Destroy;
begin
  Disconnect;
  inherited Destroy;
end;

procedure TS7Client.Disconnect;
begin
  FreeAndNil(FSock);
end;

function TS7Client.Connected: Boolean;
begin
  Result := FSock <> nil;
end;

function TS7Client.MaxReadBytes: Integer;
begin
  { response = 12 header + 2 params + 4 item header }
  Result := FPduSize - 18;
end;

procedure TS7Client.ReadExact(var Buf; Count: Integer);
var
  p: PByte;
  n: Integer;
begin
  p := @Buf;
  while Count > 0 do
  begin
    n := FSock.Read(p^, Count);
    if n <= 0 then
      raise ES7.Create('Connection closed or response timeout');
    Inc(p, n);
    Dec(Count, n);
  end;
end;

procedure TS7Client.SendTpkt(const Payload: TBytes);
var
  frame: TBytes;
  n: Integer;
begin
  if FSock = nil then
    raise ES7.Create('Not connected');
  n := Length(Payload) + 4;
  SetLength(frame, n);
  frame[0] := 3;
  frame[1] := 0;
  frame[2] := Hi(Word(n));
  frame[3] := Lo(Word(n));
  Move(Payload[0], frame[4], Length(Payload));
  if FSock.Write(frame[0], n) <> n then
    raise ES7.Create('Socket write failed');
end;

function TS7Client.RecvTpkt: TBytes;
var
  hdr: array[0..3] of Byte;
  n: Integer;
begin
  ReadExact(hdr, 4);
  if hdr[0] <> 3 then
    raise ES7.Create('Invalid TPKT header');
  n := (hdr[2] shl 8) or hdr[3];
  if (n < 7) or (n > 8192) then
    raise ES7.Create('Invalid TPKT length');
  SetLength(Result, n - 4);
  ReadExact(Result[0], n - 4);
end;

function TS7Client.Exchange(const S7: TBytes): TBytes;
var
  payload, r: TBytes;
  li, hl: Integer;
begin
  Inc(FPduRef);
  SetLength(payload, 3 + Length(S7));
  payload[0] := 2;      { COTP DT, EOT }
  payload[1] := $F0;
  payload[2] := $80;
  Move(S7[0], payload[3], Length(S7));
  payload[3 + 4] := Hi(FPduRef);
  payload[3 + 5] := Lo(FPduRef);
  SendTpkt(payload);
  repeat
    r := RecvTpkt;
    li := r[0];
    if (Length(r) < li + 1 + 10) or (r[1] <> $F0) then
      raise ES7.Create('Unexpected COTP frame');
    Result := Copy(r, li + 1, MaxInt);
  until (Result[4] = Hi(FPduRef)) and (Result[5] = Lo(FPduRef));
  if Result[0] <> $32 then
    raise ES7.Create('Not an S7 telegram');
  if Result[1] in [2, 3] then
  begin
    hl := 12;
    if Length(Result) < hl then
      raise ES7.Create('Short S7 header');
    if (Result[10] <> 0) or (Result[11] <> 0) then
    begin
      if (Result[10] = $81) and (Result[11] = $04) then
        raise ES7Device.Create('PLC refused the function (enable PUT/GET in the CPU properties)')
      else
        raise ES7Device.CreateFmt('S7 error class $%.2x code $%.2x', [Result[10], Result[11]]);
    end;
  end;
end;

procedure TS7Client.Connect;
var
  cr, r, s7: TBytes;
begin
  Disconnect;
  FSock := TInetSocket.Create(FHost, FPort, FTimeout);
  FSock.IOTimeout := FTimeout;
  try
    { COTP connection request: local TSAP 01.00, remote TSAP = conn type . rack*32+slot }
    cr := TBytes.Create($11, $E0, 0, 0, 0, 1, 0, $C0, 1, $0A, $C1, 2, 1, 0, $C2, 2,
      Byte(FConnType), Byte(FRack * $20 + FSlot));
    SendTpkt(cr);
    r := RecvTpkt;
    if (Length(r) < 2) or (r[1] <> $D0) then
      raise ES7.CreateFmt('ISO connection refused (check rack %d / slot %d)', [FRack, FSlot]);
    { S7 setup communication, ask for PDU 960 }
    s7 := TBytes.Create($32, 1, 0, 0, 0, 0, 0, 8, 0, 0, $F0, 0, 0, 1, 0, 1, $03, $C0);
    r := Exchange(s7);
    if Length(r) < 20 then
      raise ES7.Create('Invalid setup communication response');
    FPduSize := (r[18] shl 8) or r[19];
    if FPduSize < 64 then
      FPduSize := 240;
  except
    Disconnect;
    raise;
  end;
end;

function MakeItem(TS: Byte; Count: Word; Area: Byte; DB: Integer; BitAddr: LongWord): TBytes;
begin
  if Area <> S7_AREA_DB then DB := 0;
  Result := TBytes.Create($12, $0A, $10, TS, Hi(Count), Lo(Count), Hi(Word(DB)), Lo(Word(DB)), Area,
    Byte(BitAddr shr 16), Byte(BitAddr shr 8), Byte(BitAddr));
end;

function TS7Client.ReadArea(Area: Byte; DB, Start, Count: Integer): TBytes;
var
  s7, r, item: TBytes;
  done, n, ts, len: Integer;
begin
  SetLength(Result, Count);
  done := 0;
  while done < Count do
  begin
    n := Count - done;
    if n > MaxReadBytes then n := MaxReadBytes;
    item := MakeItem($02, n, Area, DB, LongWord(Start + done) * 8);
    s7 := TBytes.Create($32, 1, 0, 0, 0, 0, 0, 14, 0, 0, $04, 1);
    s7 := Concat(s7, item);
    r := Exchange(s7);
    if Length(r) < 18 then
      raise ES7.Create('Short read response');
    if r[14] <> $FF then
      raise ES7Device.Create(ItemErrorText(r[14]));
    ts := r[15];
    len := (r[16] shl 8) or r[17];
    if ts in [3, 4, 5] then len := len div 8;
    if (len < n) or (Length(r) < 18 + n) then
      raise ES7.Create('Short read data');
    Move(r[18], Result[done], n);
    Inc(done, n);
  end;
end;

procedure TS7Client.WriteArea(Area: Byte; DB, Start: Integer; const Data: TBytes);
var
  s7, r, item, d: TBytes;
  n: Integer;
begin
  n := Length(Data);
  if n = 0 then Exit;
  if n > FPduSize - 35 then
    raise ES7.Create('Write block too large');
  item := MakeItem($02, n, Area, DB, LongWord(Start) * 8);
  d := TBytes.Create(0, $04, Hi(Word(n * 8)), Lo(Word(n * 8)));
  s7 := TBytes.Create($32, 1, 0, 0, 0, 0, 0, 14, Hi(Word(4 + n)), Lo(Word(4 + n)), $05, 1);
  s7 := Concat(s7, item, d, Data);
  r := Exchange(s7);
  if Length(r) < 15 then
    raise ES7.Create('Short write response');
  if r[14] <> $FF then
    raise ES7Device.Create(ItemErrorText(r[14]));
end;

procedure TS7Client.WriteBit(Area: Byte; DB, ByteAddr, Bit: Integer; V: Boolean);
var
  s7, r, item: TBytes;
begin
  item := MakeItem($01, 1, Area, DB, LongWord(ByteAddr) * 8 + LongWord(Bit));
  s7 := TBytes.Create($32, 1, 0, 0, 0, 0, 0, 14, 0, 5, $05, 1);
  s7 := Concat(s7, item, TBytes.Create(0, $03, 0, 1, Ord(V)));
  r := Exchange(s7);
  if Length(r) < 15 then
    raise ES7.Create('Short write response');
  if r[14] <> $FF then
    raise ES7Device.Create(ItemErrorText(r[14]));
end;

end.
