unit uModbus;

{ Minimal blocking Modbus TCP client (FC01/02/03/04/05/06/16).
  Used only from the PLC worker thread. Addresses are protocol offsets (0-based). }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, ssockets;

type
  { the PLC answered with an error for one request: the link itself is still fine
    (shared by every protocol client) }
  EPlcDevice = class(Exception);
  EModbus = class(Exception);
  EModbusDevice = class(EPlcDevice);

  TWordArray = array of Word;
  TBoolArray = array of Boolean;

  { TModbusTcpClient }

  TModbusTcpClient = class
  private
    FSock: TInetSocket;
    FHost: string;
    FPort: Word;
    FUnitId: Byte;
    FTimeout: Integer;
    FTransId: Word;
    procedure SendRecv(const Req: TBytes; out Resp: TBytes);
    procedure ReadExact(var Buf; Count: Integer);
    function MakePdu(Fn: Byte; const Data: array of Byte): TBytes;
  public
    constructor Create(const AHost: string; APort: Word; AUnitId: Byte; ATimeoutMs: Integer);
    destructor Destroy; override;
    procedure Connect;
    procedure Disconnect;
    function Connected: Boolean;
    function ReadBits(Fn: Byte; Addr, Count: Word): TBoolArray;      { FC01 / FC02 }
    function ReadRegs(Fn: Byte; Addr, Count: Word): TWordArray;      { FC03 / FC04 }
    procedure WriteCoil(Addr: Word; V: Boolean);                     { FC05 }
    procedure WriteReg(Addr: Word; V: Word);                         { FC06 }
    procedure WriteRegs(Addr: Word; const V: array of Word);         { FC16 }
  end;

function ModbusExceptionText(Code: Byte): string;

implementation

function ModbusExceptionText(Code: Byte): string;
begin
  case Code of
    1: Result := 'Illegal function';
    2: Result := 'Illegal data address';
    3: Result := 'Illegal data value';
    4: Result := 'Server device failure';
    6: Result := 'Server busy';
    10: Result := 'Gateway path unavailable';
    11: Result := 'Gateway target failed to respond';
  else
    Result := 'Exception ' + IntToStr(Code);
  end;
end;

{ TModbusTcpClient }

constructor TModbusTcpClient.Create(const AHost: string; APort: Word; AUnitId: Byte;
  ATimeoutMs: Integer);
begin
  inherited Create;
  FHost := AHost;
  FPort := APort;
  FUnitId := AUnitId;
  FTimeout := ATimeoutMs;
end;

destructor TModbusTcpClient.Destroy;
begin
  Disconnect;
  inherited Destroy;
end;

procedure TModbusTcpClient.Connect;
begin
  Disconnect;
  FSock := TInetSocket.Create(FHost, FPort, FTimeout);
  FSock.IOTimeout := FTimeout;
end;

procedure TModbusTcpClient.Disconnect;
begin
  FreeAndNil(FSock);
end;

function TModbusTcpClient.Connected: Boolean;
begin
  Result := FSock <> nil;
end;

procedure TModbusTcpClient.ReadExact(var Buf; Count: Integer);
var
  p: PByte;
  n: Integer;
begin
  p := @Buf;
  while Count > 0 do
  begin
    n := FSock.Read(p^, Count);
    if n <= 0 then
      raise EModbus.Create('Connection closed or response timeout');
    Inc(p, n);
    Dec(Count, n);
  end;
end;

function TModbusTcpClient.MakePdu(Fn: Byte; const Data: array of Byte): TBytes;
var
  i: Integer;
begin
  SetLength(Result, 1 + Length(Data));
  Result[0] := Fn;
  for i := 0 to High(Data) do
    Result[1 + i] := Data[i];
end;

procedure TModbusTcpClient.SendRecv(const Req: TBytes; out Resp: TBytes);
var
  frame: TBytes;
  hdr: array[0..6] of Byte;
  len, tid: Integer;
begin
  if FSock = nil then
    raise EModbus.Create('Not connected');
  Inc(FTransId);
  SetLength(frame, 7 + Length(Req));
  frame[0] := Hi(FTransId);
  frame[1] := Lo(FTransId);
  frame[2] := 0;
  frame[3] := 0;
  frame[4] := Hi(Word(Length(Req) + 1));
  frame[5] := Lo(Word(Length(Req) + 1));
  frame[6] := FUnitId;
  Move(Req[0], frame[7], Length(Req));
  if FSock.Write(frame[0], Length(frame)) <> Length(frame) then
    raise EModbus.Create('Socket write failed');

  { skip stale responses (e.g. late answer to a timed-out request) }
  repeat
    ReadExact(hdr, 7);
    len := (hdr[4] shl 8) or hdr[5];
    if (len < 2) or (len > 260) then
      raise EModbus.Create('Invalid MBAP length');
    SetLength(Resp, len - 1);
    ReadExact(Resp[0], len - 1);
    tid := (hdr[0] shl 8) or hdr[1];
  until tid = FTransId;

  if (Resp[0] and $80) <> 0 then
  begin
    if Length(Resp) > 1 then
      raise EModbusDevice.Create(ModbusExceptionText(Resp[1]))
    else
      raise EModbusDevice.Create('Modbus exception');
  end;
  if Resp[0] <> Req[0] then
    raise EModbus.Create('Function code mismatch');
end;

function TModbusTcpClient.ReadBits(Fn: Byte; Addr, Count: Word): TBoolArray;
var
  resp: TBytes;
  i: Integer;
begin
  SendRecv(MakePdu(Fn, [Hi(Addr), Lo(Addr), Hi(Count), Lo(Count)]), resp);
  if (Length(resp) < 2) or (resp[1] < (Count + 7) div 8) or (Length(resp) < 2 + resp[1]) then
    raise EModbus.Create('Short bit response');
  SetLength(Result, Count);
  for i := 0 to Count - 1 do
    Result[i] := (resp[2 + i div 8] and (1 shl (i mod 8))) <> 0;
end;

function TModbusTcpClient.ReadRegs(Fn: Byte; Addr, Count: Word): TWordArray;
var
  resp: TBytes;
  i: Integer;
begin
  SendRecv(MakePdu(Fn, [Hi(Addr), Lo(Addr), Hi(Count), Lo(Count)]), resp);
  if (Length(resp) < 2) or (resp[1] < Count * 2) or (Length(resp) < 2 + Count * 2) then
    raise EModbus.Create('Short register response');
  SetLength(Result, Count);
  for i := 0 to Count - 1 do
    Result[i] := (resp[2 + i * 2] shl 8) or resp[3 + i * 2];
end;

procedure TModbusTcpClient.WriteCoil(Addr: Word; V: Boolean);
var
  resp: TBytes;
  hv: Byte;
begin
  if V then hv := $FF else hv := 0;
  SendRecv(MakePdu(5, [Hi(Addr), Lo(Addr), hv, 0]), resp);
end;

procedure TModbusTcpClient.WriteReg(Addr: Word; V: Word);
var
  resp: TBytes;
begin
  SendRecv(MakePdu(6, [Hi(Addr), Lo(Addr), Hi(V), Lo(V)]), resp);
end;

procedure TModbusTcpClient.WriteRegs(Addr: Word; const V: array of Word);
var
  req, resp: TBytes;
  i, n: Integer;
begin
  n := Length(V);
  SetLength(req, 6 + n * 2);
  req[0] := 16;
  req[1] := Hi(Addr);
  req[2] := Lo(Addr);
  req[3] := Hi(Word(n));
  req[4] := Lo(Word(n));
  req[5] := n * 2;
  for i := 0 to n - 1 do
  begin
    req[6 + i * 2] := Hi(V[i]);
    req[7 + i * 2] := Lo(V[i]);
  end;
  SendRecv(req, resp);
end;

end.
