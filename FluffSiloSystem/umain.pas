unit uMain;

{ Fluff Silo System - main window
  Overview (BGRABitmap), main control panel, External Request,
  Paddle Patterns editor, delay settings, event log & signal list }

{$mode objfpc}{$H+}
{$COPERATORS ON}

interface

uses
  Classes, SysUtils, Math, Forms, Controls, Graphics, Dialogs, ExtCtrls, StdCtrls,
  Grids, Spin, LCLType, BGRABitmap, BGRABitmapTypes,
  uSim, uDraw, uWidgets, uChartForm, uDeviceForm;

type

  { TMainForm }

  TMainForm = class(TForm)
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
  private
    FOverview: TPaintBox;
    FRight: TScrollBox;
    FBottom: TPanel;
    BtnAutoStart, BtnAutoStop, BtnEStop, BtnReset, BtnReq: TSimButton;
    LblSim: TLabel;
    GridPat: TStringGrid;
    SpinDelay: array[0..5] of TFloatSpinEdit;
    SegSpeed: TSimSegment;
    FNextTop: Integer;
    FLastGridKey: string;
    LstEvents, LstSignals: TListBox;
    ChkAutoScroll: TCheckBox;
    Timer: TTimer;
    FLastTick: QWord;
    FSpeed: Double;
    FFlow, FInflow: Double;
    FHover: Integer;
    FEventsAdded: Boolean;
    FTiming: TStringList;
    FHit: array[0..DEV_COUNT - 1] of TRect;
    procedure BuildUI;
    function MakeGroup(AParent: TWinControl; const ACaption: string; AHeight: Integer): TGroupBox;
    procedure TimerTick(Sender: TObject);
    procedure HandleEvent(const E: TSimEvent);
    { overview }
    procedure OverviewPaint(Sender: TObject);
    procedure OverviewMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
    procedure OverviewMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    function HitDevice(X, Y: Integer): Integer;
    procedure DrawScene(bmp: TBGRABitmap);
    procedure DrawPipe(bmp: TBGRABitmap; const P: array of TPointF; W: Single);
    procedure DrawFlowDots(bmp: TBGRABitmap; const P: array of TPointF; Offset, Spacing, R: Single; C: TBGRAPixel);
    procedure DrawDeviceLabel(bmp: TBGRABitmap; I: Integer; X, Y: Single; AAlign: TAlignment);
    { buttons }
    procedure AutoStartClick(Sender: TObject);
    procedure AutoStopClick(Sender: TObject);
    procedure EStopClick(Sender: TObject);
    procedure ResetClick(Sender: TObject);
    procedure ReqClick(Sender: TObject);
    procedure NewChartClick(Sender: TObject);
    procedure ClearLogClick(Sender: TObject);
    procedure SpeedChange(Sender: TObject);
    procedure DelayChange(Sender: TObject);
    { pattern grid }
    procedure FillGrid;
    procedure GridSelectEditor(Sender: TObject; aCol, aRow: Integer; var Editor: TWinControl);
    procedure GridSetEditText(Sender: TObject; ACol, ARow: Integer; const Value: string);
    procedure GridMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure GridPrepareCanvas(Sender: TObject; aCol, aRow: Integer; aState: TGridDrawState);
    procedure AddStepClick(Sender: TObject);
    procedure DelStepClick(Sender: TObject);
    procedure DefaultPatClick(Sender: TObject);
    { lists }
    procedure ListMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure ListDblClick(Sender: TObject);
    procedure EventsDrawItem(Control: TWinControl; Index: Integer; ARect: TRect; State: TOwnerDrawState);
  end;

var
  MainForm: TMainForm;

implementation

{$R *.lfm}

const
  DW = 1000;   { design canvas }
  DH = 740;
  PADDLE_Y: array[0..2] of Single = (562, 497, 432);   { Paddle01, 02, 03 }
  BL_X = 870;
  BL_Y = 622;
  BL_R = 50;

function EncodeEv(Sig: Integer; V: Boolean): TObject;
begin
  Result := TObject(PtrInt((Sig + 1) * 2 + Ord(V)));
end;

procedure DecodeEv(O: TObject; out Sig: Integer; out V: Boolean);
var
  c: PtrInt;
begin
  c := PtrInt(O);
  Sig := c div 2 - 1;
  V := Odd(c);
end;

{ TMainForm }

procedure TMainForm.FormCreate(Sender: TObject);
begin
  FSpeed := 1;
  FHover := -1;
  FTiming := TStringList.Create;
  Sim := TFluffSim.Create;
  Sim.OnEvent := @HandleEvent;
  BuildUI;
  FillGrid;
  FLastTick := GetTickCount64;
  Timer := TTimer.Create(Self);
  Timer.Interval := 40;
  Timer.OnTimer := @TimerTick;
  Timer.Enabled := True;
  Sim.Log(-1, True, 'Simulator started - press Auto Start');
end;

procedure TMainForm.FormDestroy(Sender: TObject);
begin
  Timer.Enabled := False;
  while (ChartForms <> nil) and (ChartForms.Count > 0) do
    TChartForm(ChartForms[0]).Free;
  FreeDeviceForms;
  Sim.OnEvent := nil;
  FreeAndNil(Sim);
  FTiming.Free;
end;

function TMainForm.MakeGroup(AParent: TWinControl; const ACaption: string; AHeight: Integer): TGroupBox;
begin
  Result := TGroupBox.Create(Self);
  { append at the bottom: alTop controls are ordered by Top, so it must grow }
  Inc(FNextTop, 10000);
  Result.Top := FNextTop;
  Result.Parent := AParent;
  Result.Align := alTop;
  Result.Height := AHeight;
  Result.Caption := ' ' + ACaption + ' ';
  Result.Font.Style := [fsBold];
  Result.BorderSpacing.Around := 4;
  Result.DoubleBuffered := True;
end;

procedure TMainForm.BuildUI;
const
  DELAY_NAMES: array[0..5] of string =
    ('Blower -> Screw start', 'External Request hold', 'Screw -> Paddle Patterns',
     'Request lost -> Screw stop', 'Screw stopped -> Blower stop', 'Auto Stop -> Blower stop');
var
  g: TGroupBox;
  pnl, pBar: TPanel;
  b: TButton;
  l: TLabel;
  i: Integer;
  gEv, gSig: TGroupBox;
begin
  Caption := 'Fluff Silo System Simulator (BGRABitmap)';
  Width := Min(1500, Screen.WorkAreaWidth);
  Height := Min(940, Screen.WorkAreaHeight - 30);
  Position := poScreenCenter;
  KeyPreview := True;

  { ---------- right side panels ---------- }
  FRight := TScrollBox.Create(Self);
  FRight.Parent := Self;
  FRight.Align := alRight;
  FRight.Width := 470;
  FRight.HorzScrollBar.Visible := False;
  FRight.VertScrollBar.Tracking := True;
  { the BGRABitmap widgets repaint often: paint the panel off-screen first (no flicker) }
  DoubleBuffered := True;
  FRight.DoubleBuffered := True;

  { main control panel }
  g := MakeGroup(FRight, 'Main Control Panel', 160);
  BtnAutoStart := TSimButton.Create(Self);
  BtnAutoStart.Parent := g;
  BtnAutoStart.SetBounds(10, 6, 205, 50);
  BtnAutoStart.Caption := 'AUTO START';
  BtnAutoStart.SubText := 'Level 1';
  BtnAutoStart.BaseColor := $0040B040;
  BtnAutoStart.LampColor := clLime;
  BtnAutoStart.OnClick := @AutoStartClick;

  BtnAutoStop := TSimButton.Create(Self);
  BtnAutoStop.Parent := g;
  BtnAutoStop.SetBounds(225, 6, 205, 50);
  BtnAutoStop.Caption := 'AUTO STOP';
  BtnAutoStop.SubText := 'Level 2';
  BtnAutoStop.BaseColor := $00309030;
  BtnAutoStop.LampColor := clYellow;
  BtnAutoStop.OnClick := @AutoStopClick;

  BtnEStop := TSimButton.Create(Self);
  BtnEStop.Parent := g;
  BtnEStop.SetBounds(10, 62, 205, 50);
  BtnEStop.Caption := 'E-STOP';
  BtnEStop.SubText := 'Level 6 - all devices';
  BtnEStop.BaseColor := $002020D0;
  BtnEStop.LampColor := clYellow;
  BtnEStop.OnClick := @EStopClick;

  BtnReset := TSimButton.Create(Self);
  BtnReset.Parent := g;
  BtnReset.SetBounds(225, 62, 205, 50);
  BtnReset.Caption := 'RESET E-STOP';
  BtnReset.BaseColor := $00D8D8D8;
  BtnReset.LampColor := clAqua;
  BtnReset.OnClick := @ResetClick;

  LblSim := TLabel.Create(Self);
  LblSim.Parent := g;
  LblSim.SetBounds(12, 116, 420, 20);
  LblSim.Font.Style := [];

  { external request }
  g := MakeGroup(FRight, 'External Request (Level 1)', 84);
  BtnReq := TSimButton.Create(Self);
  BtnReq.Parent := g;
  BtnReq.SetBounds(10, 4, 420, 52);
  BtnReq.Caption := 'EXTERNAL REQUEST : OFF';
  BtnReq.BaseColor := $00E0B050;
  BtnReq.LampColor := clLime;
  BtnReq.OnClick := @ReqClick;

  { paddle patterns }
  g := MakeGroup(FRight, 'Paddle Patterns  (click P1/P2/P3 to toggle, edit Time)', 270);
  pBar := TPanel.Create(Self);
  pBar.Parent := g;
  pBar.Align := alBottom;
  pBar.Height := 34;
  pBar.BevelOuter := bvNone;
  b := TButton.Create(Self);
  b.Parent := pBar;
  b.SetBounds(6, 4, 100, 26);
  b.Caption := 'Add step';
  b.Font.Style := [];
  b.OnClick := @AddStepClick;
  b := TButton.Create(Self);
  b.Parent := pBar;
  b.SetBounds(112, 4, 110, 26);
  b.Caption := 'Delete step';
  b.Font.Style := [];
  b.OnClick := @DelStepClick;
  b := TButton.Create(Self);
  b.Parent := pBar;
  b.SetBounds(228, 4, 110, 26);
  b.Caption := 'Default';
  b.Font.Style := [];
  b.OnClick := @DefaultPatClick;

  GridPat := TStringGrid.Create(Self);
  GridPat.Parent := g;
  GridPat.Align := alClient;
  GridPat.Font.Style := [];
  GridPat.ColCount := 5;
  GridPat.FixedCols := 0;
  GridPat.RowCount := 2;
  GridPat.FixedRows := 1;
  GridPat.DefaultRowHeight := 24;
  GridPat.Options := GridPat.Options + [goEditing] - [goRangeSelect];
  GridPat.ColWidths[0] := 60;
  GridPat.ColWidths[1] := 70;
  GridPat.ColWidths[2] := 70;
  GridPat.ColWidths[3] := 70;
  GridPat.ColWidths[4] := 110;
  GridPat.Cells[0, 0] := 'Step';
  GridPat.Cells[1, 0] := 'Paddle01';
  GridPat.Cells[2, 0] := 'Paddle02';
  GridPat.Cells[3, 0] := 'Paddle03';
  GridPat.Cells[4, 0] := 'Time (s)';
  GridPat.OnSelectEditor := @GridSelectEditor;
  GridPat.OnSetEditText := @GridSetEditText;
  GridPat.OnMouseUp := @GridMouseUp;
  GridPat.OnPrepareCanvas := @GridPrepareCanvas;

  { delays }
  g := MakeGroup(FRight, 'Delay Settings (seconds)', 6 * 30 + 30);
  for i := 0 to 5 do
  begin
    l := TLabel.Create(Self);
    l.Parent := g;
    l.SetBounds(12, 8 + i * 30, 260, 20);
    l.Caption := DELAY_NAMES[i];
    l.Font.Style := [];
    SpinDelay[i] := TFloatSpinEdit.Create(Self);
    SpinDelay[i].Parent := g;
    SpinDelay[i].SetBounds(300, 4 + i * 30, 120, 26);
    SpinDelay[i].Font.Style := [];
    SpinDelay[i].MinValue := 0;
    SpinDelay[i].MaxValue := 600;
    SpinDelay[i].Increment := 0.5;
    SpinDelay[i].DecimalPlaces := 1;
    SpinDelay[i].Tag := i;
  end;
  SpinDelay[0].Value := Sim.TBlowerToScrew;
  SpinDelay[1].Value := Sim.TReqHold;
  SpinDelay[2].Value := Sim.TScrewToPaddle;
  SpinDelay[3].Value := Sim.TReqOffScrewStop;
  SpinDelay[4].Value := Sim.TScrewTripBlower;
  SpinDelay[5].Value := Sim.TAutoStopBlower;
  for i := 0 to 5 do
    SpinDelay[i].OnChange := @DelayChange;

  { simulation }
  g := MakeGroup(FRight, 'Simulation', 64);
  l := TLabel.Create(Self);
  l.Parent := g;
  l.SetBounds(12, 10, 100, 20);
  l.Caption := 'Speed';
  l.Font.Style := [];
  SegSpeed := TSimSegment.Create(Self);
  SegSpeed.Parent := g;
  SegSpeed.SetBounds(60, 5, 170, 26);
  SegSpeed.AccentColor := $00309030;
  SegSpeed.Items.CommaText := 'x1,x2,x5,x10';
  SegSpeed.ItemIndex := 0;
  SegSpeed.OnChange := @SpeedChange;
  l := TLabel.Create(Self);
  l.Parent := g;
  l.SetBounds(242, 10, 200, 20);
  l.Caption := 'Click a device to open its panel';
  l.Font.Style := [];
  l.Font.Color := clGrayText;

  { ---------- bottom: events & signals ---------- }
  FBottom := TPanel.Create(Self);
  FBottom.Parent := Self;
  FBottom.Align := alBottom;
  FBottom.Height := 230;
  FBottom.BevelOuter := bvNone;

  gSig := TGroupBox.Create(Self);
  gSig.Parent := FBottom;
  gSig.Align := alRight;
  gSig.Width := 330;
  gSig.Caption := ' Signals (drag to chart / double-click) ';
  gSig.BorderSpacing.Around := 4;
  pnl := TPanel.Create(Self);
  pnl.Parent := gSig;
  pnl.Align := alTop;
  pnl.Height := 32;
  pnl.BevelOuter := bvNone;
  b := TButton.Create(Self);
  b.Parent := pnl;
  b.SetBounds(4, 3, 150, 26);
  b.Caption := 'New empty chart';
  b.OnClick := @NewChartClick;
  LstSignals := TListBox.Create(Self);
  LstSignals.Parent := gSig;
  LstSignals.Align := alClient;
  for i := 0 to SIGNAL_COUNT - 1 do
    LstSignals.Items.AddObject(SignalName(i), EncodeEv(i, False));
  LstSignals.OnMouseDown := @ListMouseDown;
  LstSignals.OnDblClick := @ListDblClick;

  gEv := TGroupBox.Create(Self);
  gEv.Parent := FBottom;
  gEv.Align := alClient;
  gEv.Caption := ' Event Log (every event - drag onto a chart / double-click) ';
  gEv.BorderSpacing.Around := 4;
  pnl := TPanel.Create(Self);
  pnl.Parent := gEv;
  pnl.Align := alTop;
  pnl.Height := 32;
  pnl.BevelOuter := bvNone;
  ChkAutoScroll := TCheckBox.Create(Self);
  ChkAutoScroll.Parent := pnl;
  ChkAutoScroll.SetBounds(6, 6, 110, 20);
  ChkAutoScroll.Caption := 'Auto scroll';
  ChkAutoScroll.Checked := True;
  b := TButton.Create(Self);
  b.Parent := pnl;
  b.SetBounds(120, 3, 90, 26);
  b.Caption := 'Clear log';
  b.OnClick := @ClearLogClick;
  LstEvents := TListBox.Create(Self);
  LstEvents.Parent := gEv;
  LstEvents.Align := alClient;
  LstEvents.Style := lbOwnerDrawFixed;
  LstEvents.ItemHeight := 18;
  LstEvents.OnDrawItem := @EventsDrawItem;
  LstEvents.OnMouseDown := @ListMouseDown;
  LstEvents.OnDblClick := @ListDblClick;

  { ---------- overview ---------- }
  FOverview := TPaintBox.Create(Self);
  FOverview.Parent := Self;
  FOverview.Align := alClient;
  FOverview.OnPaint := @OverviewPaint;
  FOverview.OnMouseMove := @OverviewMouseMove;
  FOverview.OnMouseUp := @OverviewMouseUp;
end;

{ ================= timer / events ================= }

procedure TMainForm.TimerTick(Sender: TObject);
var
  now: QWord;
  dt, d: Double;
  key: string;
  i: Integer;
begin
  now := GetTickCount64;
  dt := (now - FLastTick) / 1000;
  FLastTick := now;
  if dt > 0.25 then dt := 0.25;
  dt := dt * FSpeed;
  while dt > 1e-6 do
  begin
    d := Min(dt, 0.05);
    Sim.Step(d);
    dt -= d;
    if Sim.Dev[DEV_BLOWER].Running then
      FFlow += d * 170;
    if Sim.Filling then
      FInflow += d * 110;
  end;

  BtnAutoStart.Lamp := Sim.Mode = smAutoStart;
  BtnAutoStop.Lamp := Sim.Mode = smAutoStop;
  BtnEStop.Lamp := Sim.EStopMain and (Frac(Sim.Time) < 0.5);
  BtnReset.Lamp := Sim.EStopMain;
  BtnReq.Lamp := Sim.ExtRequest;
  if Sim.ExtRequest then
  begin
    BtnReq.Caption := 'EXTERNAL REQUEST : ON';
    BtnReq.SubText := Format('held %.1f s  (click to release)', [Sim.ReqOnTime]);
  end
  else
  begin
    BtnReq.Caption := 'EXTERNAL REQUEST : OFF';
    BtnReq.SubText := 'click to request material';
  end;
  LblSim.Caption := Format('Sim time %s   speed x%g   events %d',
    [FmtTime(Sim.Time), FSpeed, Sim.EventCount]);

  if FEventsAdded then
  begin
    FEventsAdded := False;
    while LstEvents.Items.Count > 3000 do
      LstEvents.Items.Delete(0);
    if ChkAutoScroll.Checked and (LstEvents.Items.Count > 0) then
      LstEvents.TopIndex := LstEvents.Items.Count - 1;
  end;

  { repaint the pattern grid only when something in it changed (no flicker) }
  key := Format('%d|%d|', [Ord(Sim.PatternActive), Sim.PatStep]);
  for i := 0 to High(Sim.Pattern) do
    key := key + Format('%d%d%d:%.1f;', [Ord(Sim.Pattern[i].P[0]), Ord(Sim.Pattern[i].P[1]),
      Ord(Sim.Pattern[i].P[2]), Sim.Pattern[i].Duration]);
  if (key <> FLastGridKey) and not GridPat.EditorMode then
  begin
    FLastGridKey := key;
    FillGrid;
    GridPat.Invalidate;
  end;
  FOverview.Invalidate;
  RefreshDeviceForms;
  RefreshCharts;
end;

procedure TMainForm.HandleEvent(const E: TSimEvent);
begin
  if LstEvents = nil then Exit;
  LstEvents.Items.AddObject(FmtTime(E.T) + '   ' + E.Text, EncodeEv(E.Sig, E.Value));
  FEventsAdded := True;
end;

procedure TMainForm.EventsDrawItem(Control: TWinControl; Index: Integer;
  ARect: TRect; State: TOwnerDrawState);
var
  lb: TListBox;
  sig: Integer;
  v: Boolean;
  p: Integer;
begin
  lb := TListBox(Control);
  DecodeEv(lb.Items.Objects[Index], sig, v);
  if odSelected in State then
  begin
    lb.Canvas.Brush.Color := clHighlight;
    lb.Canvas.Font.Color := clHighlightText;
  end
  else
  begin
    lb.Canvas.Brush.Color := clWindow;
    if sig < 0 then
      lb.Canvas.Font.Color := $00A05000          { sequencer / command : blue }
    else
    begin
      p := sig mod PROP_COUNT;
      if (sig < SYS_BASE) and (p in [P_FAULT, P_ESTOP]) and v then
        lb.Canvas.Font.Color := clRed
      else if (sig < SYS_BASE) and (p in [P_MANSTART, P_MANSTOP]) and v then
        lb.Canvas.Font.Color := $000080E0      { orange }
      else if v then
        lb.Canvas.Font.Color := $00008000      { green }
      else
        lb.Canvas.Font.Color := clGray;
    end;
  end;
  lb.Canvas.FillRect(ARect);
  lb.Canvas.TextOut(ARect.Left + 4, ARect.Top + 1, lb.Items[Index]);
end;

procedure TMainForm.ListMouseDown(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
var
  lb: TListBox;
  idx, sig: Integer;
  v: Boolean;
begin
  if Button <> mbLeft then Exit;
  lb := TListBox(Sender);
  idx := lb.ItemAtPos(Point(X, Y), True);
  if idx < 0 then Exit;
  DecodeEv(lb.Items.Objects[idx], sig, v);
  if sig < 0 then Exit;     { sequencer message: nothing to chart }
  GDragSignal := sig;
  lb.BeginDrag(False, 5);
end;

procedure TMainForm.ListDblClick(Sender: TObject);
var
  lb: TListBox;
  sig: Integer;
  v: Boolean;
begin
  lb := TListBox(Sender);
  if lb.ItemIndex < 0 then Exit;
  DecodeEv(lb.Items.Objects[lb.ItemIndex], sig, v);
  if sig >= 0 then
    OpenChart([sig]);
end;

procedure TMainForm.NewChartClick(Sender: TObject);
begin
  OpenChart([]);
end;

procedure TMainForm.ClearLogClick(Sender: TObject);
begin
  LstEvents.Items.Clear;
end;

{ ================= buttons ================= }

procedure TMainForm.AutoStartClick(Sender: TObject);
begin
  Sim.CmdAutoStart;
end;

procedure TMainForm.AutoStopClick(Sender: TObject);
begin
  Sim.CmdAutoStop;
end;

procedure TMainForm.EStopClick(Sender: TObject);
begin
  Sim.CmdEStop;
end;

procedure TMainForm.ResetClick(Sender: TObject);
begin
  Sim.CmdResetEStop;
end;

procedure TMainForm.ReqClick(Sender: TObject);
begin
  Sim.SetExtRequest(not Sim.ExtRequest);
end;

procedure TMainForm.SpeedChange(Sender: TObject);
const
  SP: array[0..3] of Double = (1, 2, 5, 10);
begin
  if SegSpeed.ItemIndex >= 0 then
    FSpeed := SP[SegSpeed.ItemIndex];
end;

procedure TMainForm.DelayChange(Sender: TObject);
var
  v: Double;
begin
  v := TFloatSpinEdit(Sender).Value;
  case TFloatSpinEdit(Sender).Tag of
    0: Sim.TBlowerToScrew := v;
    1: Sim.TReqHold := v;
    2: Sim.TScrewToPaddle := v;
    3: Sim.TReqOffScrewStop := v;
    4: Sim.TScrewTripBlower := v;
    5: Sim.TAutoStopBlower := v;
  end;
end;

{ ================= pattern grid ================= }

procedure TMainForm.FillGrid;
var
  i, k: Integer;
begin
  GridPat.RowCount := Length(Sim.Pattern) + 1;
  for i := 0 to High(Sim.Pattern) do
  begin
    GridPat.Cells[0, i + 1] := IntToStr(i + 1);
    for k := 0 to PADDLE_COUNT - 1 do
      if Sim.Pattern[i].P[k] then
        GridPat.Cells[k + 1, i + 1] := 'RUN'
      else
        GridPat.Cells[k + 1, i + 1] := '-';
    GridPat.Cells[4, i + 1] := FormatFloat('0.0', Sim.Pattern[i].Duration);
  end;
end;

procedure TMainForm.GridSelectEditor(Sender: TObject; aCol, aRow: Integer;
  var Editor: TWinControl);
begin
  if aCol <> 4 then
    Editor := nil;
end;

procedure TMainForm.GridSetEditText(Sender: TObject; ACol, ARow: Integer;
  const Value: string);
var
  v: Double;
begin
  if (ACol <> 4) or (ARow < 1) or (ARow > Length(Sim.Pattern)) then Exit;
  if TryStrToFloat(Value, v) then
  begin
    Sim.Pattern[ARow - 1].Duration := Max(0.5, v);
    Sim.PatternChanged;
  end;
end;

procedure TMainForm.GridMouseUp(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
var
  c, r: Integer;
begin
  GridPat.MouseToCell(X, Y, c, r);
  if (r >= 1) and (r <= Length(Sim.Pattern)) and (c >= 1) and (c <= 3) then
  begin
    Sim.Pattern[r - 1].P[c - 1] := not Sim.Pattern[r - 1].P[c - 1];
    Sim.Log(-1, True, Format('Pattern step %d: Paddle0%d = %s',
      [r, c, OnOff(Sim.Pattern[r - 1].P[c - 1])]));
    FillGrid;
  end;
end;

procedure TMainForm.GridPrepareCanvas(Sender: TObject; aCol, aRow: Integer;
  aState: TGridDrawState);
begin
  if aRow < 1 then Exit;
  if (aCol in [1..3]) and (aRow <= Length(Sim.Pattern)) and Sim.Pattern[aRow - 1].P[aCol - 1] then
  begin
    GridPat.Canvas.Brush.Color := $00B0E8B0;
    GridPat.Canvas.Font.Style := [fsBold];
  end;
  if Sim.PatternActive and (aRow - 1 = Sim.PatStep) then
  begin
    if aCol = 0 then
      GridPat.Canvas.Brush.Color := $0030C030
    else if not ((aCol in [1..3]) and Sim.Pattern[aRow - 1].P[aCol - 1]) then
      GridPat.Canvas.Brush.Color := $00D8F8D8
    else
      GridPat.Canvas.Brush.Color := $0060D060;
  end;
end;

procedure TMainForm.AddStepClick(Sender: TObject);
var
  n: Integer;
begin
  n := Length(Sim.Pattern);
  SetLength(Sim.Pattern, n + 1);
  Sim.Pattern[n].P[0] := False;
  Sim.Pattern[n].P[1] := False;
  Sim.Pattern[n].P[2] := False;
  Sim.Pattern[n].Duration := 5;
  Sim.PatternChanged;
  FillGrid;
end;

procedure TMainForm.DelStepClick(Sender: TObject);
var
  r, i: Integer;
begin
  r := GridPat.Row - 1;
  if (r < 0) or (r > High(Sim.Pattern)) then
    r := High(Sim.Pattern);
  if r < 0 then Exit;
  for i := r to High(Sim.Pattern) - 1 do
    Sim.Pattern[i] := Sim.Pattern[i + 1];
  SetLength(Sim.Pattern, Length(Sim.Pattern) - 1);
  Sim.PatternChanged;
  FillGrid;
end;

procedure TMainForm.DefaultPatClick(Sender: TObject);
begin
  Sim.LoadDefaultPattern;
  FillGrid;
end;

{ ================= overview ================= }

function TMainForm.HitDevice(X, Y: Integer): Integer;
var
  i: Integer;
  dx, dy: Single;
begin
  Result := -1;
  if VS <= 0 then Exit;
  dx := (X - VOX) / VS;
  dy := (Y - VOY) / VS;
  for i := 0 to DEV_COUNT - 1 do
    if (dx >= FHit[i].Left) and (dx <= FHit[i].Right) and
       (dy >= FHit[i].Top) and (dy <= FHit[i].Bottom) then
      Exit(i);
end;

procedure TMainForm.OverviewMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
begin
  FHover := HitDevice(X, Y);
  if FHover >= 0 then
    FOverview.Cursor := crHandPoint
  else
    FOverview.Cursor := crDefault;
end;

procedure TMainForm.OverviewMouseUp(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
var
  d: Integer;
begin
  d := HitDevice(X, Y);
  if (Button = mbLeft) and (d >= 0) then
    ShowDeviceForm(d);
end;

procedure TMainForm.OverviewPaint(Sender: TObject);
var
  bmp: TBGRABitmap;
  w, h: Integer;
  s: Single;
begin
  w := FOverview.Width;
  h := FOverview.Height;
  if (w < 20) or (h < 20) then Exit;
  bmp := TBGRABitmap.Create(w, h, BGRA(222, 224, 227));
  try
    s := Min(w / DW, h / DH);
    SetView(s, (w - DW * s) / 2, (h - DH * s) / 2);
    DrawScene(bmp);
    bmp.Draw(FOverview.Canvas, 0, 0, True);
  finally
    bmp.Free;
  end;
end;

procedure TMainForm.DrawPipe(bmp: TBGRABitmap; const P: array of TPointF; W: Single);
begin
  VPolyLine(bmp, P, BGRA(95, 98, 104), W);
  VPolyLine(bmp, P, BGRA(165, 168, 174), W - 3);
  VPolyLine(bmp, P, BGRA(205, 208, 214), W * 0.35);
end;

procedure TMainForm.DrawFlowDots(bmp: TBGRABitmap; const P: array of TPointF;
  Offset, Spacing, R: Single; C: TBGRAPixel);
var
  i: Integer;
  segLen, d, pos, t: Single;
begin
  { dots travel along the polyline from P[0] to P[High] }
  pos := Offset - Floor(Offset / Spacing) * Spacing;
  d := 0;
  for i := 0 to High(P) - 1 do
  begin
    segLen := Hypot(P[i + 1].x - P[i].x, P[i + 1].y - P[i].y);
    while (segLen > 0) and (pos <= d + segLen) do
    begin
      t := (pos - d) / segLen;
      VCircle(bmp, P[i].x + (P[i + 1].x - P[i].x) * t, P[i].y + (P[i + 1].y - P[i].y) * t, R, C);
      pos += Spacing;
    end;
    d += segLen;
  end;
end;

procedure TMainForm.DrawDeviceLabel(bmp: TBGRABitmap; I: Integer; X, Y: Single; AAlign: TAlignment);
var
  D: TDevice;
  vis: TDevVisual;
  s, dly: string;
  c: TBGRAPixel;
begin
  D := Sim.Dev[I];
  vis := D.Visual;
  VText(bmp, X, Y, D.Name, 17, BGRA(20, 25, 35), True, AAlign);
  s := StateText(vis);
  if D.Running then
    s += '  ' + FmtTime(D.RunTime);
  s += Format('  L%d %s', [D.CtrlLevel, D.Reason]);
  case vis of
    dvFault: c := BGRA(200, 20, 20);
    dvAutoRun, dvManualRun: c := BGRA(0, 120, 40);
    dvDisabled: c := BGRA(70, 70, 70);
  else
    c := BGRA(90, 95, 105);
  end;
  VText(bmp, X, Y + 20, s, 12, c, True, AAlign);
  dly := Sim.DevDelayText(I);
  if dly <> '' then
    VText(bmp, X, Y + 35, 'delay: ' + dly, 12, BGRA(210, 100, 0), True, AAlign);
end;

procedure TMainForm.DrawScene(bmp: TBGRABitmap);
var
  i, k, j: Integer;
  lvlY, x, y, py, L1, L2, off, a: Single;
  inlet, outlet, feed: array of TPointF;
  blue, panel, frame, mat, matD, bladeC: TBGRAPixel;
  vis: TDevVisual;
  D: TDevice;
  matFlow: Boolean;
  r: TRect;

  procedure SetPts(var A: array of TPointF; const V: array of Single);
  var
    n: Integer;
  begin
    for n := 0 to High(A) do
      A[n] := PointF(V[n * 2], V[n * 2 + 1]);
  end;

begin
  blue := BGRA(50, 115, 185);
  panel := BGRA(178, 220, 246);
  frame := BGRA(40, 95, 165);
  mat := BGRA(246, 236, 212, 215);
  matD := BGRA(200, 185, 150, 200);

  { ---------- hit areas (design coords) ---------- }
  FHit[DEV_BLOWER] := Rect(810, 555, 960, 735);
  FHit[DEV_SCREW] := Rect(20, 578, 342, 650);
  for k := 0 to 2 do
    FHit[DEV_PADDLE1 + k] := Rect(60, Round(PADDLE_Y[k]) - 30, 342, Round(PADDLE_Y[k]) + 30);

  { ---------- inlet pipe (feed to cyclone) ---------- }
  SetLength(inlet, 2);
  SetPts(inlet, [1000, 66, 552, 66]);
  DrawPipe(bmp, inlet, 16);
  if Sim.Filling then
    DrawFlowDots(bmp, inlet, FInflow, 18, 3, BGRA(250, 240, 210));
  VText(bmp, 990, 38, 'Fluff feed', 13, BGRA(60, 60, 70), True, taRightJustify);
  if Sim.Filling then
    VText(bmp, 990, 78, 'filling...', 12, BGRA(0, 120, 200), True, taRightJustify);

  { ---------- outlet pipe (blower -> consumer) ---------- }
  SetLength(outlet, 13);
  outlet[0] := PointF(BL_X + BL_R * 0.75, BL_Y - BL_R * 1.2);
  outlet[1] := PointF(BL_X + BL_R * 0.75, 120);
  for j := 0 to 9 do
  begin
    a := Pi + j / 9 * Pi / 2;
    outlet[2 + j] := PointF(BL_X + BL_R * 0.75 + 30 + 30 * Cos(a), 120 + 30 * Sin(a));
  end;
  outlet[12] := PointF(1000, 90);
  DrawPipe(bmp, outlet, 26);
  matFlow := Sim.Dev[DEV_SCREW].Running and Sim.Dev[DEV_BLOWER].Running;
  if Sim.Dev[DEV_BLOWER].Running then
  begin
    if matFlow then
      DrawFlowDots(bmp, outlet, FFlow, 16, 4.5, BGRA(250, 238, 200))
    else
      DrawFlowDots(bmp, outlet, FFlow, 30, 2, BGRA(255, 255, 255, 150));
  end;
  { consumer / external request indicator }
  VText(bmp, 995, 108, 'to consumer', 12, BGRA(60, 60, 70), True, taRightJustify);
  DrawLed(bmp, VX(920), VY(140), VL(7), BGRA(40, 220, 80), Sim.ExtRequest);
  VText(bmp, 932, 132, 'Ext. Request ' + OnOff(Sim.ExtRequest), 12, BGRA(30, 30, 40), True);

  { ---------- cyclone ---------- }
  VRect(bmp, 528, 38, 542, 56, BGRA(150, 190, 225));
  VFrame(bmp, 528, 38, 542, 56, frame, 1);
  VRect(bmp, 512, 54, 558, 100, BGRA(120, 180, 230));
  VFrame(bmp, 512, 54, 558, 100, frame, 1.5);
  VPoly(bmp, [PointF(512, 100), PointF(558, 100), PointF(544, 132), PointF(526, 132)], BGRA(70, 140, 210));
  VRect(bmp, 527, 132, 543, 150, BGRA(150, 190, 225));
  VFrame(bmp, 527, 132, 543, 150, frame, 1);

  { ---------- silo body ---------- }
  VRect(bmp, 330, 150, 670, 385, panel);
  VRect(bmp, 340, 385, 660, 640, panel);
  { material }
  lvlY := 640 - (640 - 156) * Sim.SiloLevel / 100;
  if lvlY < 385 then
  begin
    VRect(bmp, 330, lvlY, 670, 385, mat);
    VRect(bmp, 340, 385, 660, 640, mat);
  end
  else
    VRect(bmp, 340, lvlY, 660, 640, mat);
  for i := 0 to 160 do
  begin
    x := 342 + (i * 73) mod 316;
    y := 638 - (i * 137) mod 480;
    if y > lvlY + 3 then
      VCircle(bmp, x, y, 1.6 + (i mod 3) * 0.6, matD);
  end;
  if Sim.Filling then
    for i := 0 to 5 do
    begin
      y := 152 + Frac(FInflow / 60 + i / 6) * Max(1, lvlY - 152);
      VCircle(bmp, 535 + ((i * 7) mod 9) - 4, y, 3, BGRA(250, 240, 210));
    end;

  { ---------- paddles (inside the silo) ---------- }
  for k := 0 to 2 do
  begin
    D := Sim.Dev[DEV_PADDLE1 + k];
    py := PADDLE_Y[k];
    VLine(bmp, 338, py, 652, py, BGRA(110, 115, 125), 5);
    if D.Running then
      bladeC := Darker(StateColor(D.Visual), 0.85)
    else if D.Visual in [dvFault, dvDisabled] then
      bladeC := StateColor(D.Visual)
    else
      bladeC := BGRA(135, 145, 158);
    for j := 0 to 3 do
    begin
      x := 385 + j * 72;
      a := D.Phase + j * 0.7;
      L1 := 24 * Cos(a);
      L2 := 24 * Sin(a);
      VLine(bmp, x - 6, py - L1, x - 6, py + L1, bladeC, 7);
      VLine(bmp, x + 6, py - L2, x + 6, py + L2, Darker(bladeC, 0.85), 7);
      VCircle(bmp, x, py, 4, BGRA(80, 85, 95));
    end;
  end;

  { ---------- silo frame grid ---------- }
  for i := 0 to 4 do
    VLine(bmp, 330 + i * 85, 150, 330 + i * 85, 385, frame, 4);
  VLine(bmp, 330, 150, 670, 150, frame, 4);
  VLine(bmp, 330, 230, 670, 230, frame, 3);
  VLine(bmp, 330, 310, 670, 310, frame, 3);
  VRect(bmp, 324, 381, 676, 391, blue);
  VLine(bmp, 340, 385, 340, 640, frame, 5);
  VLine(bmp, 660, 385, 660, 640, frame, 5);
  VLine(bmp, 500, 385, 500, 640, frame, 4);
  for k := 0 to 2 do
    VLine(bmp, 340, PADDLE_Y[k] + 14, 660, PADDLE_Y[k] + 14, frame, 2.5);
  VLine(bmp, 340, 596, 660, 596, frame, 2.5);
  { sight glasses }
  for i := 0 to 1 do
  begin
    y := 248 + i * 80;
    VRect(bmp, 536, y, 556, y + 46, BGRA(245, 245, 245));
    if lvlY < y + 46 then
      VRect(bmp, 536, Max(y, lvlY), 556, y + 46, BGRA(220, 205, 170));
    for j := 0 to 5 do
      VCircle(bmp, 541 + (j mod 2) * 9, y + 6 + j * 7, 2, BGRA(150, 150, 150));
    VFrame(bmp, 536, y, 556, y + 46, BGRA(40, 40, 40), 1.5);
  end;
  VText(bmp, 345, 158, Format('Level %.0f%%', [Sim.SiloLevel]), 13, BGRA(20, 50, 90), True);

  { ---------- screw conveyor ---------- }
  D := Sim.Dev[DEV_SCREW];
  VRect(bmp, 338, 600, 800, 632, BGRA(205, 212, 222, 235));
  off := Frac(D.Phase / (2 * Pi)) * 26;
  x := 344 + off;
  while x < 790 do
  begin
    VLine(bmp, x, 630, x + 13, 602, BGRA(85, 90, 100), 3);
    x += 26;
  end;
  VLine(bmp, 338, 616, 800, 616, BGRA(70, 75, 85), 4);
  VFrame(bmp, 338, 600, 800, 632, BGRA(60, 65, 75), 1.5);
  VRect(bmp, 798, 596, 808, 636, BGRA(140, 145, 155));
  VRect(bmp, 760, 632, 788, 648, BGRA(160, 165, 175));
  if D.Running then
    for i := 0 to 2 do
      VCircle(bmp, 774, 634 + Frac(FFlow / 40 + i / 3) * 14, 2.5, BGRA(250, 238, 200));

  { ---------- base frame & legs ---------- }
  VRect(bmp, 326, 640, 674, 652, blue);
  for i := 0 to 2 do
  begin
    x := 340 + i * 154;
    VRect(bmp, x, 652, x + 14, 712, blue);
    VRect(bmp, x - 8, 710, x + 22, 716, frame);
  end;
  VLine(bmp, 354, 690, 390, 652, blue, 4);
  VLine(bmp, 494, 690, 458, 652, blue, 4);
  VLine(bmp, 508, 690, 544, 652, blue, 4);
  VLine(bmp, 648, 690, 612, 652, blue, 4);

  { ---------- hopper + feed pipe to blower ---------- }
  VPoly(bmp, [PointF(732, 648), PointF(812, 648), PointF(780, 690), PointF(764, 690)], BGRA(110, 170, 225));
  VPolyLine(bmp, [PointF(732, 648), PointF(812, 648), PointF(780, 690), PointF(764, 690), PointF(732, 648)],
    frame, 1.5);
  SetLength(feed, 4);
  SetPts(feed, [772, 690, 772, 704, 834, 704, 836, 664]);
  DrawPipe(bmp, feed, 10);
  if matFlow then
    DrawFlowDots(bmp, feed, FFlow * 0.5, 14, 2.5, BGRA(250, 238, 200));

  { ---------- devices ---------- }
  D := Sim.Dev[DEV_BLOWER];
  DrawBlower(bmp, BL_X, BL_Y, BL_R, D.Visual, D.Phase);
  DrawDeviceLabel(bmp, DEV_BLOWER, 905, 680, taCenter);

  D := Sim.Dev[DEV_SCREW];
  DrawGearMotor(bmp, 180, 592, 158, 46, D.Visual);
  DrawDeviceLabel(bmp, DEV_SCREW, 172, 584, taRightJustify);

  for k := 0 to 2 do
  begin
    D := Sim.Dev[DEV_PADDLE1 + k];
    py := PADDLE_Y[k];
    vis := D.Visual;
    DrawMotor(bmp, 246, py - 20, 94, 40, vis);
    DrawDeviceLabel(bmp, DEV_PADDLE1 + k, 238, py - 26, taRightJustify);
  end;

  { hover frame }
  if FHover >= 0 then
  begin
    r := FHit[FHover];
    VRoundFrame(bmp, r.Left, r.Top, r.Right, r.Bottom, 8, BGRA(0, 120, 255, 200), 2);
  end;

  { ---------- timing box ---------- }
  Sim.GetTimingInfo(FTiming);
  VRound(bmp, 8, 8, 470, 30 + FTiming.Count * 19, 8, BGRA(255, 255, 255, 225));
  VRoundFrame(bmp, 8, 8, 470, 30 + FTiming.Count * 19, 8, BGRA(120, 130, 150), 1);
  VText(bmp, 18, 12, 'Sequence / Delays', 14, BGRA(30, 60, 120), True);
  for i := 0 to FTiming.Count - 1 do
    VText(bmp, 18, 30 + i * 19, FTiming[i], 13, BGRA(30, 30, 40), i = 0);

  { ---------- legend ---------- }
  y := 168;
  VRound(bmp, 8, y - 6, 250, y + 6 * 24 + 22, 8, BGRA(255, 255, 255, 200));
  VText(bmp, 18, y - 2, 'Legend', 14, BGRA(30, 60, 120), True);
  y += 20;
  for i := 0 to 5 do
  begin
    case i of
      0: vis := dvAutoRun;
      1: vis := dvIdle;
      2: vis := dvManualRun;
      3: vis := dvManualStop;
      4: vis := dvDisabled;
    else
      vis := dvFault;
    end;
    VRound(bmp, 18, y + i * 24, 52, y + i * 24 + 16, 3, StateColor(vis));
    if IsManualVis(vis) then
      VRect(bmp, 18, y + i * 24 + 5, 52, y + i * 24 + 11, CL_ORANGE);
    VRoundFrame(bmp, 18, y + i * 24, 52, y + i * 24 + 16, 3, BGRA(60, 60, 60), 1);
    case i of
      0: VText(bmp, 60, y + i * 24, 'Auto Start (run)', 12, BGRA(30, 30, 40));
      1: VText(bmp, 60, y + i * 24, 'Auto Stop / Interlock / E-Stop', 12, BGRA(30, 30, 40));
      2: VText(bmp, 60, y + i * 24, 'Manual Start', 12, BGRA(30, 30, 40));
      3: VText(bmp, 60, y + i * 24, 'Manual Stop', 12, BGRA(30, 30, 40));
      4: VText(bmp, 60, y + i * 24, 'Disable', 12, BGRA(30, 30, 40));
      5: VText(bmp, 60, y + i * 24, 'Fault', 12, BGRA(30, 30, 40));
    end;
  end;

  if Sim.EStopMain then
  begin
    VRound(bmp, 690, 170, 990, 215, 8, BGRA(220, 30, 30, 230));
    VText(bmp, 840, 178, 'E-STOP ACTIVE', 22, BGRA(255, 255, 255), True, taCenter);
  end;
end;

end.
