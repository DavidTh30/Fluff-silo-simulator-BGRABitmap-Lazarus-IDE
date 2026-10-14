unit uDeviceForm;

{ Popup panel: local control + properties of one device }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, Forms, Controls, Graphics, ExtCtrls, StdCtrls,
  BGRABitmap, BGRABitmapTypes, uSim, uDraw, uChartForm;

type

  { TDeviceForm }

  TDeviceForm = class(TForm)
  private
    FDev: Integer;
    FIcon: TPaintBox;
    FProps: TPaintBox;
    FBtnPanel: TPanel;
    procedure IconPaint(Sender: TObject);
    procedure PropsPaint(Sender: TObject);
    procedure PropsMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure BtnClick(Sender: TObject);
  public
    constructor CreateDev(AOwner: TComponent; ADev: Integer);
    destructor Destroy; override;
    procedure Tick;
  end;

procedure ShowDeviceForm(ADev: Integer);
procedure RefreshDeviceForms;
procedure FreeDeviceForms;

implementation

const
  ROW_H = 26;
  ROW_TOP = 4;
  BTN_CAPTIONS: array[0..7] of string =
    ('Manual Start', 'Manual Stop', 'Return to Auto', 'Enable', 'Disable',
     'Simulate Fault', 'Reset Fault', 'Chart all');

var
  DeviceForms: array[0..DEV_COUNT - 1] of TDeviceForm;

procedure ShowDeviceForm(ADev: Integer);
begin
  if DeviceForms[ADev] = nil then
    DeviceForms[ADev] := TDeviceForm.CreateDev(Application, ADev);
  DeviceForms[ADev].Show;
  DeviceForms[ADev].BringToFront;
end;

procedure RefreshDeviceForms;
var
  i: Integer;
begin
  for i := 0 to DEV_COUNT - 1 do
    if (DeviceForms[i] <> nil) and DeviceForms[i].Visible then
      DeviceForms[i].Tick;
end;

procedure FreeDeviceForms;
var
  i: Integer;
begin
  for i := 0 to DEV_COUNT - 1 do
    FreeAndNil(DeviceForms[i]);
end;

{ TDeviceForm }

constructor TDeviceForm.CreateDev(AOwner: TComponent; ADev: Integer);
var
  i: Integer;
  b: TButton;
begin
  inherited CreateNew(AOwner);
  FDev := ADev;
  Caption := DevNames[ADev] + ' - Control & Properties';
  BorderStyle := bsSingle;
  BorderIcons := [biSystemMenu];
  FormStyle := fsStayOnTop;
  ClientWidth := 440;
  ClientHeight := 150 + PROP_COUNT * ROW_H + ROW_TOP * 2 + 4 * 34 + 16;
  Position := poDesigned;
  Left := 200 + ADev * 40;
  Top := 120 + ADev * 30;

  FIcon := TPaintBox.Create(Self);
  FIcon.Parent := Self;
  FIcon.Align := alTop;
  FIcon.Height := 150;
  FIcon.OnPaint := @IconPaint;

  FProps := TPaintBox.Create(Self);
  FProps.Parent := Self;
  FProps.Align := alTop;
  FProps.Top := 200;
  FProps.Height := PROP_COUNT * ROW_H + ROW_TOP * 2;
  FProps.OnPaint := @PropsPaint;
  FProps.OnMouseDown := @PropsMouseDown;
  FProps.Cursor := crHandPoint;
  FProps.ShowHint := True;
  FProps.Hint := 'Drag a property onto a chart, or click the chart icon';

  FBtnPanel := TPanel.Create(Self);
  FBtnPanel.Parent := Self;
  FBtnPanel.Align := alClient;
  FBtnPanel.BevelOuter := bvNone;

  for i := 0 to High(BTN_CAPTIONS) do
  begin
    b := TButton.Create(Self);
    b.Parent := FBtnPanel;
    b.Caption := BTN_CAPTIONS[i];
    b.Tag := i;
    b.SetBounds(10 + (i mod 2) * 215, 8 + (i div 2) * 34, 205, 28);
    b.OnClick := @BtnClick;
  end;
end;

destructor TDeviceForm.Destroy;
begin
  { the form may be freed by Application before FreeDeviceForms runs }
  if DeviceForms[FDev] = Self then
    DeviceForms[FDev] := nil;
  inherited Destroy;
end;

procedure TDeviceForm.Tick;
begin
  FIcon.Invalidate;
  FProps.Invalidate;
end;

procedure TDeviceForm.BtnClick(Sender: TObject);
var
  i: Integer;
  sigs: array of Integer;
begin
  case TButton(Sender).Tag of
    0: Sim.CmdManualStart(FDev);
    1: Sim.CmdManualStop(FDev);
    2: Sim.CmdManualRelease(FDev);
    3: Sim.CmdEnable(FDev);
    4: Sim.CmdDisable(FDev);
    5: Sim.CmdFault(FDev);
    6: Sim.CmdResetFault(FDev);
    7:
      begin
        SetLength(sigs, PROP_COUNT);
        for i := 0 to PROP_COUNT - 1 do
          sigs[i] := SigId(FDev, i);
        OpenChart(sigs);
      end;
  end;
  Tick;
end;

procedure TDeviceForm.IconPaint(Sender: TObject);
var
  bmp: TBGRABitmap;
  D: TDevice;
  vis: TDevVisual;
  tx: Integer;
  s: string;
begin
  bmp := TBGRABitmap.Create(FIcon.Width, FIcon.Height, BGRA(236, 240, 244));
  try
    D := Sim.Dev[FDev];
    vis := D.Visual;
    SetView(1, 0, 0);
    if FDev = DEV_BLOWER then
      DrawBlower(bmp, 80, 82, 48, vis, D.Phase)
    else if FDev = DEV_SCREW then
      DrawGearMotor(bmp, 10, 52, 150, 60, vis)
    else
      DrawMotor(bmp, 15, 50, 135, 62, vis);

    tx := 180;
    PText(bmp, tx, 8, D.Name, 22, BGRA(20, 30, 50), True);
    bmp.FillRoundRectAntialias(tx, 42, tx + 150, 66, 6, 6, StateColor(vis));
    if IsManualVis(vis) then
      bmp.FillRectAntialias(tx, 50, tx + 150, 58, CL_ORANGE);
    if vis in [dvDisabled, dvFault] then
      PText(bmp, tx + 75, 45, StateText(vis), 14, BGRA(255, 255, 255), True, taCenter)
    else
      PText(bmp, tx + 75, 45, StateText(vis), 14, BGRA(20, 20, 20), True, taCenter);
    PText(bmp, tx, 74, Format('Control: L%d  %s', [D.CtrlLevel, D.Reason]), 14, BGRA(40, 40, 60));
    PText(bmp, tx, 94, 'Run time : ' + FmtTime(D.RunTime), 14, BGRA(40, 40, 60));
    PText(bmp, tx, 112, 'Total    : ' + FmtTime(D.TotalRunTime) +
      Format('   Starts: %d', [D.StartCount]), 14, BGRA(40, 40, 60));
    s := Sim.DevDelayText(FDev);
    if s <> '' then
      PText(bmp, tx, 130, 'Delay    : ' + s, 14, BGRA(200, 90, 0), True);
    bmp.Draw(FIcon.Canvas, 0, 0, True);
  finally
    bmp.Free;
  end;
end;

procedure TDeviceForm.PropsPaint(Sender: TObject);
var
  bmp: TBGRABitmap;
  i, y, w, lvl: Integer;
  D: TDevice;
  isOn: Boolean;
  lc, tc: TBGRAPixel;
begin
  w := FProps.Width;
  bmp := TBGRABitmap.Create(w, FProps.Height, BGRA(250, 251, 252));
  try
    D := Sim.Dev[FDev];
    for i := 0 to PROP_COUNT - 1 do
    begin
      y := ROW_TOP + i * ROW_H;
      isOn := D.Props[i];
      if Odd(i) then
        bmp.FillRectAntialias(0, y, w, y + ROW_H, BGRA(238, 241, 245));
      { highlight the level that is in control }
      lvl := PropLevels[i];
      if isOn and (lvl > 0) and (lvl = D.CtrlLevel) then
        bmp.FillRectAntialias(0, y, 5, y + ROW_H, BGRA(30, 120, 220));
      case i of
        P_FAULT: lc := CL_RED;
        P_ESTOP: lc := CL_RED;
        P_MANSTART, P_MANSTOP: lc := CL_ORANGE;
        P_DISABLE: lc := BGRA(120, 120, 120);
        P_AUTOSTOP, P_INTERLOCK: lc := BGRA(240, 200, 40);
      else
        lc := BGRA(40, 220, 80);
      end;
      DrawLed(bmp, 20, y + ROW_H / 2, 7, lc, isOn);
      tc := BGRA(25, 30, 40);
      PText(bmp, 38, y + 4, PropNames[i], 15, tc, True);
      if lvl > 0 then
        PText(bmp, 190, y + 5, 'Level ' + IntToStr(lvl), 13, BGRA(90, 100, 120))
      else
        PText(bmp, 190, y + 5, 'Feedback', 13, BGRA(90, 100, 120));
      if isOn then
        PText(bmp, 270, y + 4, 'ON', 15, BGRA(0, 140, 40), True)
      else
        PText(bmp, 270, y + 4, 'OFF', 15, BGRA(140, 140, 140), True);
      PText(bmp, 315, y + 6, '(drag)', 11, BGRA(150, 160, 175));
      { chart icon }
      bmp.RoundRectAntialias(w - 44, y + 3, w - 10, y + ROW_H - 3, 4, 4, BGRA(90, 110, 140), 1);
      bmp.DrawLineAntialias(w - 40, y + ROW_H - 8, w - 33, y + 12, BGRA(30, 120, 220), 1.6);
      bmp.DrawLineAntialias(w - 33, y + 12, w - 25, y + 17, BGRA(30, 120, 220), 1.6);
      bmp.DrawLineAntialias(w - 25, y + 17, w - 14, y + 7, BGRA(30, 120, 220), 1.6);
    end;
    bmp.Draw(FProps.Canvas, 0, 0, True);
  finally
    bmp.Free;
  end;
end;

procedure TDeviceForm.PropsMouseDown(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
var
  row: Integer;
begin
  if Button <> mbLeft then Exit;
  row := (Y - ROW_TOP) div ROW_H;
  if (row < 0) or (row >= PROP_COUNT) then Exit;
  if X >= FProps.Width - 46 then
    OpenChart([SigId(FDev, row)])
  else
  begin
    GDragSignal := SigId(FDev, row);
    FProps.BeginDrag(False, 4);
  end;
end;

end.
