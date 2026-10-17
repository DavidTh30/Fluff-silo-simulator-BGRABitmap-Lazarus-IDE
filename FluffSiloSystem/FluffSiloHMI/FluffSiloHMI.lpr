program FluffSiloHMI;

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  Interfaces, // this includes the LCL widgetset
  Forms, uMain, uSim, uDraw, uWidgets, uChartForm, uDeviceForm,
  uModbus, uS7, uPlcLink, uHwConfigForm;

{$R *.res}

begin
  RequireDerivedFormResource := True;
  Application.Title := 'FluffSilo HMI';
  Application.Scaled := True;
  Application.Initialize;
  Application.CreateForm(TMainForm, MainForm);
  Application.Run;
end.
