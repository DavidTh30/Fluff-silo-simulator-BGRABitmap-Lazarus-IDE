program FluffSiloHMI2;

{ FluffSilo HMI2 - 9 devices (Blower01, Screw01, Paddle01..07), 20-step Paddle Patterns.
  Command line:
    --export-map <file.csv>   write the default register map and exit
    --open-all                open the Pattern, Events and a Chart window at start
    --demo                    simulation x5 with Auto Start + External Request }

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  Interfaces, // this includes the LCL widgetset
  Forms, SysUtils, uMain, uSim, uDraw, uWidgets, uChartForm, uDeviceForm,
  uModbus, uS7, uPlcLink, uHwConfigForm, uPatternForm, uEventsForm, uLog;

{$R *.res}

begin
  if SameText(ParamStr(1), '--export-map') and (ParamStr(2) <> '') then
  begin
    ExportTagsCsv(ParamStr(2), DefaultTags);
    Halt(0);
  end;
  RequireDerivedFormResource := True;
  Application.Title := 'FluffSilo HMI2';
  Application.Scaled := True;
  Application.Initialize;
  Application.CreateForm(TMainForm, MainForm);
  Application.Run;
end.
