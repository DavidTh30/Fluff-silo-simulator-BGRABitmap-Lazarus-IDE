unit uLog;

{ FluffSilo HMI2 - event log file
  Every event of Sim (commands, sequencer messages, signal changes) is appended to
  logs\HMI2_yyyymmdd.log next to the .exe (one file per day, tab separated):
    yyyy-mm-dd hh:nn:ss.zzz <TAB> sim time <TAB> signal id (-1 = message) <TAB> 1/0 <TAB> text }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, uSim;

function LogDir: string;
function LogFileName(ADay: TDateTime): string;
procedure LogWrite(const E: TSimEvent);
procedure LogClose;
procedure ExportEventsCsv(const AFile: string; const Idx: array of Integer);

implementation

var
  FStream: TFileStream = nil;
  FDay: Integer = -1;
  FFailed: Boolean = False;

function LogDir: string;
begin
  Result := ExtractFilePath(ParamStr(0)) + 'logs' + PathDelim;
end;

function LogFileName(ADay: TDateTime): string;
begin
  Result := LogDir + 'HMI2_' + FormatDateTime('yyyymmdd', ADay) + '.log';
end;

procedure LogClose;
begin
  FreeAndNil(FStream);
  FDay := -1;
end;

procedure OpenFor(ADay: TDateTime);
var
  fn: string;
begin
  LogClose;
  fn := LogFileName(ADay);
  ForceDirectories(LogDir);
  if FileExists(fn) then
  begin
    FStream := TFileStream.Create(fn, fmOpenWrite or fmShareDenyWrite);
    FStream.Seek(0, soEnd);
  end
  else
    FStream := TFileStream.Create(fn, fmCreate or fmShareDenyWrite);
  FDay := Trunc(ADay);
end;

procedure LogWrite(const E: TSimEvent);
var
  s: string;
begin
  if FFailed then Exit;
  try
    if (FStream = nil) or (Trunc(E.Stamp) <> FDay) then
      OpenFor(E.Stamp);
    s := FormatDateTime('yyyy-mm-dd hh:nn:ss.zzz', E.Stamp) + #9 + FmtTime(E.T) + #9 +
      IntToStr(E.Sig) + #9 + IntToStr(Ord(E.Value)) + #9 + E.Text + LineEnding;
    FStream.WriteBuffer(s[1], Length(s));
  except
    { disk full / read-only folder: stop logging, keep the HMI running }
    FFailed := True;
    LogClose;
  end;
end;

procedure ExportEventsCsv(const AFile: string; const Idx: array of Integer);
var
  sl: TStringList;
  i: Integer;
  e: TSimEvent;
  sig: string;
begin
  sl := TStringList.Create;
  try
    sl.Add('Clock;SimTime;Signal;Value;Text');
    for i := 0 to High(Idx) do
    begin
      e := Sim.Events[Idx[i]];
      if e.Sig < 0 then sig := 'Message' else sig := SignalName(e.Sig);
      sl.Add(Format('%s;%s;%s;%d;%s', [FormatDateTime('yyyy-mm-dd hh:nn:ss.zzz', e.Stamp), FmtTime(e.T),
        sig, Ord(e.Value), StringReplace(e.Text, ';', ',', [rfReplaceAll])]));
    end;
    sl.SaveToFile(AFile);
  finally
    sl.Free;
  end;
end;

finalization
  LogClose;

end.
