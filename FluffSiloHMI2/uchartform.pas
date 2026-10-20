unit uChartForm;

{ FluffSilo HMI2 - popup history chart (BGRABitmap)
  Traces are added with the "Add signal" menu, by dragging an event from the
  Events window or a property from a device panel, or with "Chart all" there. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, Forms, Controls, Graphics, ExtCtrls, Menus, Dialogs,
  BGRABitmap, BGRABitmapTypes, uSim, uDraw, uWidgets;

type

  { TChartForm }

  TChartForm = class(TForm)
  private
    FTop: TSimPanel;
    FBox: TPaintBox;
    FWindow: TSimSegment;
    FPause: TSimToggle;
    FAddBtn: TSimButton;
    FMenu: TPopupMenu;
    FSigs: array of Integer;
    FEndTime: Double;
    FMouseX, FMouseY: Integer;
    procedure BoxPaint(Sender: TObject);
    procedure Render(bmp: TBGRABitmap; w, h: Integer; ShowCursor: Boolean);
    procedure AnyDragOver(Sender, Source: TObject; X, Y: Integer; State: TDragState; var Accept: Boolean);
    procedure AnyDragDrop(Sender, Source: TObject; X, Y: Integer);
    procedure BoxMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
    procedure BoxMouseLeave(Sender: TObject);
    procedure BoxDblClick(Sender: TObject);
    procedure BoxMouseWheel(Sender: TObject; Shift: TShiftState; WheelDelta: Integer;
      MousePos: TPoint; var Handled: Boolean);
    procedure AddClick(Sender: TObject);
    procedure MenuPick(Sender: TObject);
    procedure ClearClick(Sender: TObject);
    procedure SavePngClick(Sender: TObject);
    procedure PauseChange(Sender: TObject);
    procedure WindowChange(Sender: TObject);
    procedure FormCloseEv(Sender: TObject; var CloseAction: TCloseAction);
    procedure BuildMenu;
    function WindowSec: Double;
    procedure GetRange(out t0, t1: Double);
  public
    constructor CreateChart(AOwner: TComponent);
    destructor Destroy; override;
    procedure AddSignal(Id: Integer);
    procedure Tick;
  end;

procedure OpenChart(const Sigs: array of Integer);
procedure RefreshCharts;

var
  ChartForms: TList = nil;

implementation

const
  LBL_W = 210;
  LANE_H = 36;
  AXIS_H = 24;
  RIGHT_M = 12;

  TRACE_COLORS: array[0..7] of TColor =
    ($0050E070, $00FFB040, $004080FF, $00FF70D0, $0040E0FF, $00A0A0FF, $0070FFB0, $00FFFF60);

var
  ChartSeq: Integer = 0;

procedure OpenChart(const Sigs: array of Integer);
var
  F: TChartForm;
  i: Integer;
begin
  F := TChartForm.CreateChart(Application);
  for i := 0 to High(Sigs) do
    F.AddSignal(Sigs[i]);
  F.Show;
end;

procedure RefreshCharts;
var
  i: Integer;
begin
  if ChartForms = nil then Exit;
  for i := 0 to ChartForms.Count - 1 do
    TChartForm(ChartForms[i]).Tick;
end;

{ TChartForm }

constructor TChartForm.CreateChart(AOwner: TComponent);
var
  b: TSimButton;
begin
  inherited CreateNew(AOwner);
  Inc(ChartSeq);
  Caption := 'History Chart #' + IntToStr(ChartSeq);
  Width := 980;
  Height := 300;
  Position := poDesigned;
  Left := 80 + (ChartSeq mod 8) * 30;
  Top := 80 + (ChartSeq mod 8) * 30;
  FormStyle := fsStayOnTop;
  Color := clThemeBg;
  OnClose := @FormCloseEv;
  OnDragOver := @AnyDragOver;
  OnDragDrop := @AnyDragDrop;

  FTop := NewPanel(Self, Self, '', clThemeAccent);
  FTop.Align := alTop;
  FTop.Height := 46;
  FTop.OnDragOver := @AnyDragOver;
  FTop.OnDragDrop := @AnyDragDrop;

  FAddBtn := NewButton(Self, FTop, 8, 7, 130, 30, 'Add signal', $00C08040, ikAdd, @AddClick);
  FWindow := TSimSegment.Create(Self);
  FWindow.Parent := FTop;
  FWindow.SetBounds(146, 9, 300, 26);
  FWindow.Items.CommaText := '30s,60s,120s,300s,600s,All';
  FWindow.ItemIndex := 1;
  FWindow.OnChange := @WindowChange;
  FPause := TSimToggle.Create(Self);
  FPause.Parent := FTop;
  FPause.SetBounds(456, 10, 90, 24);
  FPause.Caption := 'Pause';
  FPause.OnChange := @PauseChange;
  b := NewButton(Self, FTop, 552, 7, 120, 30, 'Clear', $00D8D8D8, ikClear, @ClearClick);
  b.Hint := 'Remove all traces';
  b.ShowHint := True;
  b := NewButton(Self, FTop, 678, 7, 130, 30, 'Save PNG', $00D8D8D8, ikSave, @SavePngClick);
  b.Hint := 'Save the chart as a picture';
  b.ShowHint := True;
  NewLabel(Self, FTop, 818, 12, 160, 'wheel = scroll back', 11, False, clThemeMuted);

  FMenu := TPopupMenu.Create(Self);

  FBox := TPaintBox.Create(Self);
  FBox.Parent := Self;
  FBox.Align := alClient;
  FBox.OnPaint := @BoxPaint;
  FBox.OnDragOver := @AnyDragOver;
  FBox.OnDragDrop := @AnyDragDrop;
  FBox.OnMouseMove := @BoxMouseMove;
  FBox.OnMouseLeave := @BoxMouseLeave;
  FBox.OnDblClick := @BoxDblClick;
  FBox.OnMouseWheel := @BoxMouseWheel;
  FBox.ShowHint := True;
  FBox.Hint := 'Double-click a lane to remove it';
  FMouseX := -1;

  if ChartForms = nil then
    ChartForms := TList.Create;
  ChartForms.Add(Self);
end;

destructor TChartForm.Destroy;
begin
  if ChartForms <> nil then
    ChartForms.Remove(Self);
  inherited Destroy;
end;

procedure TChartForm.FormCloseEv(Sender: TObject; var CloseAction: TCloseAction);
begin
  CloseAction := caFree;
end;

procedure TChartForm.BuildMenu;
var
  d, p, s: Integer;
  sub, it: TMenuItem;
begin
  FMenu.Items.Clear;
  sub := TMenuItem.Create(FMenu);
  sub.Caption := 'System';
  FMenu.Items.Add(sub);
  for s := 0 to SYS_COUNT - 1 do
  begin
    it := TMenuItem.Create(FMenu);
    it.Caption := SysNames[s];
    it.Tag := SYS_BASE + s;
    it.OnClick := @MenuPick;
    sub.Add(it);
  end;
  for d := 0 to DEV_COUNT - 1 do
  begin
    if not Sim.Dev[d].Installed then Continue;
    sub := TMenuItem.Create(FMenu);
    sub.Caption := DevNames[d];
    FMenu.Items.Add(sub);
    it := TMenuItem.Create(FMenu);
    it.Caption := 'All properties';
    it.Tag := -(d + 1);
    it.OnClick := @MenuPick;
    sub.Add(it);
    it := TMenuItem.Create(FMenu);
    it.Caption := '-';
    sub.Add(it);
    for p := 0 to PROP_COUNT - 1 do
    begin
      it := TMenuItem.Create(FMenu);
      it.Caption := PropNames[p];
      it.Tag := SigId(d, p);
      it.OnClick := @MenuPick;
      sub.Add(it);
    end;
  end;
end;

procedure TChartForm.AddClick(Sender: TObject);
var
  pt: TPoint;
begin
  BuildMenu;
  pt := FAddBtn.ClientToScreen(Point(0, FAddBtn.Height));
  FMenu.PopUp(pt.X, pt.Y);
end;

procedure TChartForm.MenuPick(Sender: TObject);
var
  t, p: Integer;
begin
  t := TMenuItem(Sender).Tag;
  if t < 0 then
    for p := 0 to PROP_COUNT - 1 do
      AddSignal(SigId(-t - 1, p))
  else
    AddSignal(t);
end;

procedure TChartForm.AddSignal(Id: Integer);
var
  i, h: Integer;
begin
  if (Id < 0) or (Id >= SIGNAL_COUNT) then Exit;
  for i := 0 to High(FSigs) do
    if FSigs[i] = Id then Exit;
  SetLength(FSigs, Length(FSigs) + 1);
  FSigs[High(FSigs)] := Id;
  h := FTop.Height + AXIS_H + Length(FSigs) * LANE_H + 30;
  if ClientHeight < h then
    ClientHeight := Min(h, Screen.Height - 120);
  FBox.Invalidate;
end;

procedure TChartForm.Tick;
begin
  if not FPause.Checked then
    FBox.Invalidate;
end;

function TChartForm.WindowSec: Double;
begin
  case FWindow.ItemIndex of
    0: Result := 30;
    1: Result := 60;
    2: Result := 120;
    3: Result := 300;
    4: Result := 600;
  else
    Result := 0;   { all }
  end;
end;

procedure TChartForm.GetRange(out t0, t1: Double);
var
  span: Double;
begin
  span := WindowSec;
  if span <= 0 then
  begin
    t0 := 0;
    t1 := Max(10, Sim.Time);
    Exit;
  end;
  if FPause.Checked then t1 := FEndTime else t1 := Sim.Time;
  t1 := Max(t1, span);
  t0 := t1 - span;
end;

procedure TChartForm.PauseChange(Sender: TObject);
begin
  FEndTime := Sim.Time;
  FBox.Invalidate;
end;

procedure TChartForm.WindowChange(Sender: TObject);
begin
  FBox.Invalidate;
end;

procedure TChartForm.ClearClick(Sender: TObject);
begin
  SetLength(FSigs, 0);
  FBox.Invalidate;
end;

procedure TChartForm.SavePngClick(Sender: TObject);
var
  dlg: TSaveDialog;
  bmp: TBGRABitmap;
begin
  dlg := TSaveDialog.Create(Self);
  try
    dlg.Filter := 'PNG picture (*.png)|*.png';
    dlg.DefaultExt := 'png';
    dlg.FileName := 'Chart_' + FormatDateTime('yyyymmdd_hhnnss', Now) + '.png';
    if not dlg.Execute then Exit;
    bmp := TBGRABitmap.Create(Max(200, FBox.Width), Max(100, FBox.Height), BGRA(22, 26, 32));
    try
      Render(bmp, bmp.Width, bmp.Height, False);
      bmp.SaveToFile(dlg.FileName);
    finally
      bmp.Free;
    end;
    Sim.Log(-1, True, 'Chart saved: ' + dlg.FileName);
  finally
    dlg.Free;
  end;
end;

procedure TChartForm.AnyDragOver(Sender, Source: TObject; X, Y: Integer;
  State: TDragState; var Accept: Boolean);
begin
  Accept := (GDragSignal >= 0) and (GDragSignal < SIGNAL_COUNT);
end;

procedure TChartForm.AnyDragDrop(Sender, Source: TObject; X, Y: Integer);
begin
  AddSignal(GDragSignal);
  GDragSignal := -1;
end;

procedure TChartForm.BoxMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
begin
  FMouseX := X;
  FMouseY := Y;
  FBox.Invalidate;
end;

procedure TChartForm.BoxMouseLeave(Sender: TObject);
begin
  FMouseX := -1;
  FBox.Invalidate;
end;

procedure TChartForm.BoxDblClick(Sender: TObject);
var
  lane, i: Integer;
begin
  lane := (FMouseY - AXIS_H) div LANE_H;
  if (FMouseY < AXIS_H) or (lane < 0) or (lane > High(FSigs)) then Exit;
  for i := lane to High(FSigs) - 1 do
    FSigs[i] := FSigs[i + 1];
  SetLength(FSigs, Length(FSigs) - 1);
  FBox.Invalidate;
end;

procedure TChartForm.BoxMouseWheel(Sender: TObject; Shift: TShiftState;
  WheelDelta: Integer; MousePos: TPoint; var Handled: Boolean);
var
  span: Double;
begin
  Handled := True;
  span := WindowSec;
  if span <= 0 then Exit;
  if not FPause.Checked then
  begin
    FEndTime := Sim.Time;
    FPause.Checked := True;
  end;
  FEndTime := EnsureRange(FEndTime - WheelDelta / 120 * span * 0.1, span, Max(span, Sim.Time));
  FBox.Invalidate;
end;

procedure TChartForm.BoxPaint(Sender: TObject);
var
  bmp: TBGRABitmap;
begin
  if (FBox.Width < 50) or (FBox.Height < 30) then Exit;
  bmp := TBGRABitmap.Create(FBox.Width, FBox.Height, BGRA(22, 26, 32));
  try
    Render(bmp, FBox.Width, FBox.Height, True);
    bmp.Draw(FBox.Canvas, 0, 0, True);
  finally
    bmp.Free;
  end;
end;

procedure TChartForm.Render(bmp: TBGRABitmap; w, h: Integer; ShowCursor: Boolean);
const
  STEPS: array[0..10] of Double = (1, 2, 5, 10, 15, 30, 60, 120, 300, 600, 1800);
var
  i, j, k, x, y, yHi, yLo, id, cnt, mx: Integer;
  t0, t1, tEnd, span, stp, tg, segT, tp, tm: Double;
  cur, v: Boolean;
  col: TBGRAPixel;
  plotL, plotR: Integer;
  s: string;

  function TX(t: Double): Single;
  begin
    Result := plotL + (t - t0) / (t1 - t0) * (plotR - plotL);
  end;

  procedure Seg(ta, tb: Double; val: Boolean);
  var
    xa, xb: Single;
  begin
    if tb <= ta then Exit;
    xa := TX(ta);
    xb := TX(tb);
    if val then
    begin
      bmp.FillRectAntialias(xa, yHi, xb, yLo, WithAlpha(col, 55));
      bmp.DrawLineAntialias(xa, yHi, xb, yHi, col, 2);
    end
    else
      bmp.DrawLineAntialias(xa, yLo, xb, yLo, WithAlpha(col, 200), 2);
  end;

begin
  bmp.GradientFill(0, 0, w, h, BGRA(26, 31, 39), BGRA(16, 19, 24), gtLinear, PointF(0, 0), PointF(0, h), dmSet);
  GetRange(t0, t1);
  span := t1 - t0;
  plotL := LBL_W;
  plotR := w - RIGHT_M;

  { time grid }
  stp := STEPS[High(STEPS)];
  for i := 0 to High(STEPS) do
    if span / STEPS[i] <= 10 then
    begin
      stp := STEPS[i];
      Break;
    end;
  tg := Ceil(t0 / stp) * stp;
  while tg <= t1 do
  begin
    x := Round(TX(tg));
    bmp.DrawLineAntialias(x, AXIS_H - 4, x, h, BGRA(60, 66, 76), 1);
    PText(bmp, x, 3, FmtTime(tg), 11, BGRA(170, 175, 185), False, taCenter);
    tg := tg + stp;
  end;
  bmp.DrawLineAntialias(plotL, AXIS_H - 2, plotR, AXIS_H - 2, BGRA(90, 96, 106), 1);

  if Length(FSigs) = 0 then
  begin
    PText(bmp, w div 2, h div 2 - 22, 'No trace yet', 20, BGRA(140, 150, 160), True, taCenter);
    PText(bmp, w div 2, h div 2 + 6, 'Add signal  |  drag an event from the Events window  |  drag a device property',
      13, BGRA(120, 130, 140), False, taCenter);
  end;

  tEnd := Min(t1, Sim.Time);
  for i := 0 to High(FSigs) do
  begin
    id := FSigs[i];
    y := AXIS_H + i * LANE_H;
    yHi := y + 7;
    yLo := y + LANE_H - 7;
    col := TB(TRACE_COLORS[i mod Length(TRACE_COLORS)]);
    if Odd(i) then
      bmp.FillRectAntialias(0, y, w, y + LANE_H, BGRA(255, 255, 255, 10));
    bmp.DrawLineAntialias(0, y + LANE_H, w, y + LANE_H, BGRA(50, 55, 64), 1);

    { label }
    bmp.FillRectAntialias(6, y + 10, 14, y + LANE_H - 10, col);
    PText(bmp, 20, y + 2, SignalName(id), 13, BGRA(230, 232, 236), True);
    v := Sim.GetSignal(id);
    s := OnOff(v);
    if SignalLevel(id) > 0 then
      s := s + '   L' + IntToStr(SignalLevel(id));
    s := s + '   ' + IntToStr(Max(0, Sim.History[id].Count - 1)) + ' chg';
    PText(bmp, 20, y + 18, s, 11, BGRA(150, 156, 166));

    { waveform }
    cnt := Sim.History[id].Count;
    k := Sim.FindHistIdx(id, t0);
    if k < 0 then
    begin
      cur := False;
      segT := Max(t0, 0);
      j := 0;
    end
    else
    begin
      cur := Sim.History[id].Pts[k].V;
      segT := t0;
      j := k + 1;
    end;
    while j < cnt do
    begin
      tp := Sim.History[id].Pts[j].T;
      if tp > tEnd then Break;
      Seg(segT, tp, cur);
      bmp.DrawLineAntialias(TX(tp), yHi, TX(tp), yLo, col, 1.5);
      cur := Sim.History[id].Pts[j].V;
      segT := tp;
      Inc(j);
    end;
    Seg(segT, tEnd, cur);
  end;

  { label column separator }
  bmp.DrawLineAntialias(plotL - 4, 0, plotL - 4, h, BGRA(80, 86, 96), 1);

  { cursor }
  if ShowCursor and (FMouseX >= plotL) and (FMouseX <= plotR) then
  begin
    mx := FMouseX;
    tm := t0 + (mx - plotL) / (plotR - plotL) * span;
    bmp.DrawLineAntialias(mx, AXIS_H, mx, h, BGRA(255, 255, 255, 140), 1);
    bmp.FillRectAntialias(mx + 4, AXIS_H + 1, mx + 96, AXIS_H + 17, BGRA(0, 0, 0, 190));
    PText(bmp, mx + 8, AXIS_H + 2, FmtTime(tm), 12, BGRA(255, 255, 255));
    for i := 0 to High(FSigs) do
      if tm <= Sim.Time then
      begin
        y := AXIS_H + i * LANE_H;
        v := Sim.ValueAt(FSigs[i], tm);
        PText(bmp, mx - 6, y + 11, OnOff(v), 11, BGRA(255, 255, 255), True, taRightJustify);
      end;
  end;

  if FPause.Checked then
    PText(bmp, plotR - 4, AXIS_H + 2, 'PAUSED', 12, BGRA(255, 180, 60), True, taRightJustify);
end;

finalization
  FreeAndNil(ChartForms);

end.
