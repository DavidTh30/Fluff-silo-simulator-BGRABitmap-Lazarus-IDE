unit uChartForm;

{ Popup history chart. Signals/events can be dragged onto it. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, Forms, Controls, Graphics, ExtCtrls, StdCtrls,
  BGRABitmap, BGRABitmapTypes, uSim, uDraw;

type

  { TChartForm }

  TChartForm = class(TForm)
  private
    FTop: TPanel;
    FBox: TPaintBox;
    FWindow: TComboBox;
    FPause: TCheckBox;
    FClear: TButton;
    FHint: TLabel;
    FSigs: array of Integer;
    FEndTime: Double;
    FMouseX, FMouseY: Integer;
    procedure BoxPaint(Sender: TObject);
    procedure AnyDragOver(Sender, Source: TObject; X, Y: Integer; State: TDragState; var Accept: Boolean);
    procedure AnyDragDrop(Sender, Source: TObject; X, Y: Integer);
    procedure BoxMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
    procedure BoxMouseLeave(Sender: TObject);
    procedure BoxDblClick(Sender: TObject);
    procedure BoxMouseWheel(Sender: TObject; Shift: TShiftState; WheelDelta: Integer;
      MousePos: TPoint; var Handled: Boolean);
    procedure ClearClick(Sender: TObject);
    procedure PauseClick(Sender: TObject);
    procedure WindowChange(Sender: TObject);
    procedure FormCloseEv(Sender: TObject; var CloseAction: TCloseAction);
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
begin
  inherited CreateNew(AOwner);
  Inc(ChartSeq);
  Caption := 'History Chart #' + IntToStr(ChartSeq) + '  (drag signals / events here)';
  Width := 900;
  Height := 260;
  Position := poDesigned;
  Left := 80 + (ChartSeq mod 8) * 30;
  Top := 80 + (ChartSeq mod 8) * 30;
  FormStyle := fsStayOnTop;
  OnClose := @FormCloseEv;
  OnDragOver := @AnyDragOver;
  OnDragDrop := @AnyDragDrop;

  FTop := TPanel.Create(Self);
  FTop.Parent := Self;
  FTop.Align := alTop;
  FTop.Height := 34;
  FTop.BevelOuter := bvNone;
  FTop.OnDragOver := @AnyDragOver;
  FTop.OnDragDrop := @AnyDragDrop;

  FWindow := TComboBox.Create(Self);
  FWindow.Parent := FTop;
  FWindow.Style := csDropDownList;
  FWindow.SetBounds(8, 5, 90, 24);
  FWindow.Items.CommaText := '"30 s","60 s","120 s","300 s","600 s","All"';
  FWindow.ItemIndex := 1;
  FWindow.OnChange := @WindowChange;

  FPause := TCheckBox.Create(Self);
  FPause.Parent := FTop;
  FPause.SetBounds(108, 8, 70, 20);
  FPause.Caption := 'Pause';
  FPause.OnClick := @PauseClick;

  FClear := TButton.Create(Self);
  FClear.Parent := FTop;
  FClear.SetBounds(180, 4, 90, 26);
  FClear.Caption := 'Clear traces';
  FClear.OnClick := @ClearClick;

  FHint := TLabel.Create(Self);
  FHint.Parent := FTop;
  FHint.SetBounds(282, 9, 600, 20);
  FHint.Caption := 'Drop = add trace | Double-click lane = remove | Wheel = scroll back (pauses)';
  FHint.Font.Color := clGrayText;

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

procedure TChartForm.PauseClick(Sender: TObject);
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
const
  STEPS: array[0..10] of Double = (1, 2, 5, 10, 15, 30, 60, 120, 300, 600, 1800);
var
  bmp: TBGRABitmap;
  w, h, i, j, k, x, y, yHi, yLo, id, cnt, mx: Integer;
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
  w := FBox.Width;
  h := FBox.Height;
  if (w < 50) or (h < 30) then Exit;
  bmp := TBGRABitmap.Create(w, h, BGRA(22, 26, 32));
  try
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
      PText(bmp, w div 2, h div 2 - 10, 'Drag a signal or an event here', 18,
        BGRA(120, 130, 140), True, taCenter);

    tEnd := Min(t1, Sim.Time);
    for i := 0 to High(FSigs) do
    begin
      id := FSigs[i];
      y := AXIS_H + i * LANE_H;
      yHi := y + 7;
      yLo := y + LANE_H - 7;
      col := ColorToBGRA(TRACE_COLORS[i mod Length(TRACE_COLORS)]);
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
    if (FMouseX >= plotL) and (FMouseX <= plotR) then
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

    bmp.Draw(FBox.Canvas, 0, 0, True);
  finally
    bmp.Free;
  end;
end;

finalization
  FreeAndNil(ChartForms);

end.
