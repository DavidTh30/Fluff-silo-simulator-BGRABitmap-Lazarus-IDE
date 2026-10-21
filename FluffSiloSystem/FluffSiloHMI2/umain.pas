unit uMain;

{ FluffSilo HMI2 - main window (everything painted with BGRABitmap)
    left   : Overview of the plant (1..7 paddles) + device status strip
    right  : PLC connection, main control panel, External Request,
             windows (Paddle Patterns & Delays, Events, Chart), live pattern
  Other windows: uPatternForm, uEventsForm, uChartForm, uDeviceForm, uHwConfigForm.
  Every operator action goes through uPlcLink.Hmi* (simulator or PLC). }

{$mode objfpc}{$H+}
{$COPERATORS ON}

interface

uses
  Classes, SysUtils, Math, Forms, Controls, Graphics, Dialogs, ExtCtrls, LCLType,
  BGRABitmap, BGRABitmapTypes,
  uSim, uDraw, uWidgets, uChartForm, uDeviceForm, uPlcLink, uHwConfigForm,
  uPatternForm, uEventsForm, uLog;

type

  { TMainForm }

  TMainForm = class(TForm)
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
  private
    FOverview: TPaintBox;
    FStrip: TPaintBox;
    FRight: TScrollBox;
    FNextTop: Integer;
    CardPlc, CardMain, CardReq, CardWin, CardPat: TSimPanel;
    BtnAutoStart, BtnAutoStop, BtnEStop, BtnReset, BtnReq: TSimButton;
    BtnConnect, BtnPattern, BtnEvents: TSimButton;
    SegSource, SegSpeed: TSimSegment;
    LblPlc, LblSim: TSimLabel;
    FUpdatingUI: Boolean;
    Timer: TTimer;
    FLastTick: QWord;
    FSpeed: Double;
    FFlow, FInflow: Double;
    FHover: Integer;
    FTiming: TStringList;
    FHit: array[0..DEV_COUNT - 1] of TRect;
    FTileHit: array of record R: TRect; Dev: Integer; end;
    FEventHit: TRect;
    procedure BuildUI;
    function Card(const ATitle: string; AHeight: Integer; AAccent: TColor): TSimPanel;
    procedure TimerTick(Sender: TObject);
    procedure HandleEvent(const E: TSimEvent);
    procedure FormKey(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure StartupOptions;
    { overview }
    function PaddleY(K: Integer): Single;
    procedure OverviewPaint(Sender: TObject);
    procedure OverviewMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
    procedure OverviewMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    function HitDevice(X, Y: Integer): Integer;
    procedure DrawScene(bmp: TBGRABitmap);
    procedure DrawPipe(bmp: TBGRABitmap; const P: array of TPointF; W: Single);
    procedure DrawFlowDots(bmp: TBGRABitmap; const P: array of TPointF; Offset, Spacing, R: Single; C: TBGRAPixel);
    procedure DrawDeviceLabel(bmp: TBGRABitmap; I: Integer; X, Y: Single; AAlign: TAlignment);
    { status strip }
    procedure StripPaint(Sender: TObject);
    procedure StripMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    { live pattern card }
    procedure PatCardPaint(Sender: TObject);
    procedure PatCardClick(Sender: TObject);
    { buttons }
    procedure AutoStartClick(Sender: TObject);
    procedure AutoStopClick(Sender: TObject);
    procedure EStopClick(Sender: TObject);
    procedure ResetClick(Sender: TObject);
    procedure ReqClick(Sender: TObject);
    procedure PatternClick(Sender: TObject);
    procedure EventsClick(Sender: TObject);
    procedure NewChartClick(Sender: TObject);
    procedure SpeedChange(Sender: TObject);
    procedure SourceChange(Sender: TObject);
    procedure ConnectClick(Sender: TObject);
    procedure HwConfigClick(Sender: TObject);
    procedure SyncDataSourceUI;
  end;

var
  MainForm: TMainForm;

implementation

{$R *.lfm}

const
  DW = 1000;   { design canvas }
  DH = 740;
  BL_X = 870;
  BL_Y = 622;
  BL_R = 50;
  PADDLE_BOTTOM = 568;
  PADDLE_TOP = 232;   { 7 paddles: 56 apart, none on the silo band at y 386 }
  RIGHT_W = 420;
  CW = RIGHT_W - 32;  { usable card width (room for the scroll bar) }

{ TMainForm }

procedure TMainForm.FormCreate(Sender: TObject);
begin
  FSpeed := 1;
  FHover := -1;
  FTiming := TStringList.Create;
  Sim := TFluffSim.Create;
  Sim.OnEvent := @HandleEvent;
  LoadConfig;
  Sim.SetPaddleCount(HmiOpt.SimPaddleCount);
  Sim.LoadDefaultPattern;
  BuildUI;
  FLastTick := GetTickCount64;
  Timer := TTimer.Create(Self);
  Timer.Interval := 40;
  Timer.OnTimer := @TimerTick;
  Timer.Enabled := True;
  Sim.Log(-1, True, 'FluffSilo HMI2 started - config ' + ConfigFileName);
  if PlcCfg.StartInPlc then
  begin
    SetDataSource(dsPLC);
    if PlcCfg.AutoConnect then
      Link.Start;
  end;
  SyncDataSourceUI;
  StartupOptions;
end;

procedure TMainForm.FormDestroy(Sender: TObject);
begin
  Timer.Enabled := False;
  Link.Stop;
  try
    SaveConfig;
  except
  end;
  while (ChartForms <> nil) and (ChartForms.Count > 0) do
    TChartForm(ChartForms[0]).Free;
  FreeDeviceForms;
  FreeAndNil(PatternForm);
  FreeAndNil(EventsForm);
  Sim.OnEvent := nil;
  FreeAndNil(Sim);
  LogClose;
  FTiming.Free;
end;

procedure TMainForm.StartupOptions;
var
  i: Integer;
begin
  { --open-all : open the Pattern and Events windows and a chart
    --demo     : simulation x5, Auto Start + External Request (presentation / test) }
  for i := 1 to ParamCount do
    if SameText(ParamStr(i), '--open-all') then
    begin
      ShowPatternForm;
      ShowEventsForm;
      OpenChart([SigId(DEV_BLOWER, P_RUNNING), SigId(DEV_SCREW, P_RUNNING), SigId(DEV_PADDLE1, P_RUNNING),
        SigId(DEV_PADDLE1 + 1, P_RUNNING), SYS_BASE + SYS_PATTERN]);
    end
    else if SameText(ParamStr(i), '--demo') and not PlcMode then
    begin
      SegSpeed.ItemIndex := 2;
      SpeedChange(nil);
      HmiCommand(hcAutoStart);
      HmiSetExtRequest(True);
    end;
end;

function TMainForm.Card(const ATitle: string; AHeight: Integer; AAccent: TColor): TSimPanel;
begin
  Result := NewPanel(Self, FRight, ATitle, AAccent);
  { append at the bottom: alTop controls are ordered by Top, so it must grow }
  Inc(FNextTop, 10000);
  Result.Top := FNextTop;
  Result.Align := alTop;
  Result.Height := AHeight;
  Result.BorderSpacing.Left := 6;
  Result.BorderSpacing.Right := 6;
  Result.BorderSpacing.Top := 6;
end;

procedure TMainForm.BuildUI;
var
  g: TSimPanel;
  y: Integer;
  b: TSimButton;
begin
  Caption := 'FluffSilo HMI2  -  Blower / Screw / Paddle01..07';
  Width := Min(1560, Screen.WorkAreaWidth);
  Height := Min(960, Screen.WorkAreaHeight - 30);
  Position := poScreenCenter;
  Color := clThemeBg;
  KeyPreview := True;
  OnKeyDown := @FormKey;
  DoubleBuffered := True;
  ShowHint := True;

  { ---------- right side ---------- }
  FRight := TScrollBox.Create(Self);
  FRight.Parent := Self;
  FRight.Align := alRight;
  FRight.Width := RIGHT_W;
  FRight.BorderStyle := bsNone;
  FRight.Color := clThemeBg;
  FRight.HorzScrollBar.Visible := False;
  FRight.VertScrollBar.Tracking := True;
  FRight.DoubleBuffered := True;

  { PLC connection / data source }
  CardPlc := Card('PLC Connection', 150, $00C08040);
  g := CardPlc;
  y := g.BodyTop;
  NewLabel(Self, g, 14, y + 3, 90, 'Data source', 13);
  SegSource := TSimSegment.Create(Self);
  SegSource.Parent := g;
  SegSource.SetBounds(100, y, CW - 220, 28);
  SegSource.Items.Add('SIMULATION');
  SegSource.Items.Add('PLC');
  SegSource.ItemIndex := 0;
  SegSource.OnChange := @SourceChange;
  b := NewButton(Self, g, CW - 112, y - 1, 104, 30, 'HW Config', $00D8D8D8, ikGear, @HwConfigClick);
  b.Hint := 'Hardware Config: protocol, IP, register map';
  BtnConnect := TSimButton.Create(Self);
  BtnConnect.Parent := g;
  BtnConnect.SetBounds(10, y + 36, CW - 20, 44);
  BtnConnect.Caption := 'CONNECT';
  BtnConnect.BaseColor := $00C08040;
  BtnConnect.LampColor := clLime;
  BtnConnect.OnClick := @ConnectClick;
  LblPlc := NewLabel(Self, g, 12, y + 84, CW - 24, '', 12);
  LblPlc.ShowHint := True;

  { main control panel }
  CardMain := Card('Main Control Panel', 168, $0040B040);
  g := CardMain;
  y := g.BodyTop;
  BtnAutoStart := TSimButton.Create(Self);
  BtnAutoStart.Parent := g;
  BtnAutoStart.SetBounds(10, y, (CW - 26) div 2, 50);
  BtnAutoStart.Caption := 'AUTO START';
  BtnAutoStart.SubText := 'Level 1';
  BtnAutoStart.BaseColor := $0040B040;
  BtnAutoStart.LampColor := clLime;
  BtnAutoStart.OnClick := @AutoStartClick;

  BtnAutoStop := TSimButton.Create(Self);
  BtnAutoStop.Parent := g;
  BtnAutoStop.SetBounds(16 + (CW - 26) div 2, y, (CW - 26) div 2, 50);
  BtnAutoStop.Caption := 'AUTO STOP';
  BtnAutoStop.SubText := 'Level 2';
  BtnAutoStop.BaseColor := $00309030;
  BtnAutoStop.LampColor := clYellow;
  BtnAutoStop.OnClick := @AutoStopClick;

  BtnEStop := TSimButton.Create(Self);
  BtnEStop.Parent := g;
  BtnEStop.SetBounds(10, y + 56, (CW - 26) div 2, 50);
  BtnEStop.Caption := 'E-STOP';
  BtnEStop.SubText := 'Level 6 - all devices';
  BtnEStop.BaseColor := $002020D0;
  BtnEStop.LampColor := clYellow;
  BtnEStop.OnClick := @EStopClick;

  BtnReset := TSimButton.Create(Self);
  BtnReset.Parent := g;
  BtnReset.SetBounds(16 + (CW - 26) div 2, y + 56, (CW - 26) div 2, 50);
  BtnReset.Caption := 'RESET E-STOP';
  BtnReset.BaseColor := $00D8D8D8;
  BtnReset.LampColor := clAqua;
  BtnReset.OnClick := @ResetClick;
  LblSim := NewLabel(Self, g, 12, y + 110, CW - 24, '', 12, False, clThemeMuted);

  { external request }
  CardReq := Card('External Request (Level 1)', 92, $00E0B050);
  g := CardReq;
  BtnReq := TSimButton.Create(Self);
  BtnReq.Parent := g;
  BtnReq.SetBounds(10, g.BodyTop, CW - 20, 52);
  BtnReq.Caption := 'EXTERNAL REQUEST : OFF';
  BtnReq.BaseColor := $00E0B050;
  BtnReq.LampColor := clLime;
  BtnReq.OnClick := @ReqClick;

  { windows }
  CardWin := Card('Windows', 196, $00B08060);
  g := CardWin;
  y := g.BodyTop;
  BtnPattern := NewButton(Self, g, 10, y, CW - 20, 46, 'Paddle Patterns & Delays', $00E8E0D8, ikPattern,
    @PatternClick);
  BtnPattern.CaptionSize := 14;
  BtnPattern.SubText := 'editor, file, PLC transfer, delay settings';
  BtnEvents := NewButton(Self, g, 10, y + 52, (CW - 26) div 2, 40, 'Events', $00E8E0D8, ikList, @EventsClick);
  BtnEvents.Hint := 'Event log window (F3)';
  b := NewButton(Self, g, 16 + (CW - 26) div 2, y + 52, (CW - 26) div 2, 40, 'New Chart', $00E8E0D8, ikChart, @NewChartClick);
  b.Hint := 'History chart window (F4)';
  NewLabel(Self, g, 14, y + 104, 90, 'Sim speed', 13);
  SegSpeed := TSimSegment.Create(Self);
  SegSpeed.Parent := g;
  SegSpeed.SetBounds(104, y + 100, 200, 28);
  SegSpeed.AccentColor := $00309030;
  SegSpeed.Items.CommaText := 'x1,x2,x5,x10';
  SegSpeed.ItemIndex := 0;
  SegSpeed.OnChange := @SpeedChange;
  NewLabel(Self, g, 14, y + 132, CW - 24, 'Click a device (overview or strip) to open its panel', 11,
    False, clThemeMuted);

  { live pattern }
  CardPat := Card('Paddle Patterns (live)', 172, $0040A040);
  CardPat.OnPaintBody := @PatCardPaint;
  CardPat.OnClick := @PatCardClick;
  CardPat.Cursor := crHandPoint;
  CardPat.Hint := 'Click to open the Paddle Patterns window';
  CardPat.ShowHint := True;

  { ---------- bottom: device status strip ---------- }
  FStrip := TPaintBox.Create(Self);
  FStrip.Parent := Self;
  FStrip.Align := alBottom;
  FStrip.Height := 104;
  FStrip.OnPaint := @StripPaint;
  FStrip.OnMouseUp := @StripMouseUp;
  FStrip.Cursor := crHandPoint;

  { ---------- overview ---------- }
  FOverview := TPaintBox.Create(Self);
  FOverview.Parent := Self;
  FOverview.Align := alClient;
  FOverview.OnPaint := @OverviewPaint;
  FOverview.OnMouseMove := @OverviewMouseMove;
  FOverview.OnMouseUp := @OverviewMouseUp;
end;

procedure TMainForm.FormKey(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  case Key of
    VK_F2: ShowPatternForm;
    VK_F3: ShowEventsForm;
    VK_F4: OpenChart([]);
  else
    Exit;
  end;
  Key := 0;
end;

{ ================= timer / events ================= }

procedure TMainForm.TimerTick(Sender: TObject);
var
  now: QWord;
  dt, d: Double;
begin
  now := GetTickCount64;
  dt := (now - FLastTick) / 1000;
  FLastTick := now;
  if dt > 0.25 then dt := 0.25;
  if PlcMode then
  begin
    { real time, data from the PLC }
    Link.Update;
    Sim.StepExternal(dt);
    if Sim.Dev[DEV_BLOWER].Running then
      FFlow += dt * 170;
  end
  else
  begin
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
  end;
  SyncDataSourceUI;

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
  BtnEvents.SubText := Format('%d events', [Sim.EventCount]);
  if PlcMode then
    LblSim.Caption := Format('HMI time %s   PLC mode   events %d', [FmtTime(Sim.Time), Sim.EventCount])
  else
    LblSim.Caption := Format('Sim time %s   speed x%g   events %d', [FmtTime(Sim.Time), FSpeed, Sim.EventCount]);

  FOverview.Invalidate;
  FStrip.Invalidate;
  CardPat.Invalidate;
  RefreshDeviceForms;
  RefreshCharts;
  RefreshPatternForm;
  RefreshEventsForm;
end;

procedure TMainForm.HandleEvent(const E: TSimEvent);
begin
  if HmiOpt.LogToFile then
    LogWrite(E);
end;

{ ================= buttons ================= }

procedure TMainForm.AutoStartClick(Sender: TObject);
begin
  HmiCommand(hcAutoStart);
end;

procedure TMainForm.AutoStopClick(Sender: TObject);
begin
  HmiCommand(hcAutoStop);
end;

procedure TMainForm.EStopClick(Sender: TObject);
begin
  HmiCommand(hcEStop);
end;

procedure TMainForm.ResetClick(Sender: TObject);
begin
  HmiCommand(hcResetEStop);
end;

procedure TMainForm.ReqClick(Sender: TObject);
begin
  HmiCommand(hcExtRequest);
end;

procedure TMainForm.PatternClick(Sender: TObject);
begin
  ShowPatternForm;
end;

procedure TMainForm.PatCardClick(Sender: TObject);
begin
  ShowPatternForm;
end;

procedure TMainForm.EventsClick(Sender: TObject);
begin
  ShowEventsForm;
end;

procedure TMainForm.NewChartClick(Sender: TObject);
begin
  OpenChart([]);
end;

{ ================= PLC / data source ================= }

procedure TMainForm.SyncDataSourceUI;
begin
  FUpdatingUI := True;
  try
    SegSource.ItemIndex := Ord(PlcMode);
    SegSpeed.Enabled := not PlcMode;
    BtnConnect.Enabled := PlcMode;
    BtnConnect.Lamp := Link.Online and Sim.CommOK;
    if Link.Running then
    begin
      BtnConnect.Caption := 'DISCONNECT';
      BtnConnect.SubText := LinkTargetText;
    end
    else
    begin
      BtnConnect.Caption := 'CONNECT';
      if PlcMode then
        BtnConnect.SubText := 'to ' + LinkTargetText
      else
        BtnConnect.SubText := 'select data source "PLC" first';
    end;
    if not PlcMode then
    begin
      LblPlc.Caption := 'Offline simulation (no PLC)';
      LblPlc.TextColor := clThemeMuted;
    end
    else
    begin
      LblPlc.Caption := Link.StatusText;
      LblPlc.Hint := LblPlc.Caption;
      if Link.Online and Sim.CommOK then
      begin
        if Link.Warn <> '' then LblPlc.TextColor := $000080E0 else LblPlc.TextColor := $00008000;
      end
      else if Link.State = lsError then
        LblPlc.TextColor := clRed
      else
        LblPlc.TextColor := clThemeMuted;
    end;
  finally
    FUpdatingUI := False;
  end;
end;

procedure TMainForm.SourceChange(Sender: TObject);
begin
  if FUpdatingUI then Exit;
  if SegSource.ItemIndex = 1 then
    SetDataSource(dsPLC)
  else
    SetDataSource(dsSimulation);
  if PatternForm <> nil then
    PatternForm.LoadFromActive;
  SyncDataSourceUI;
end;

procedure TMainForm.ConnectClick(Sender: TObject);
begin
  if not PlcMode then Exit;
  if Link.Running then
    Link.Stop
  else
    Link.Start;
  SyncDataSourceUI;
end;

procedure TMainForm.HwConfigClick(Sender: TObject);
begin
  ShowHardwareConfig;
  SyncDataSourceUI;
end;

procedure TMainForm.SpeedChange(Sender: TObject);
const
  SP: array[0..3] of Double = (1, 2, 5, 10);
begin
  if SegSpeed.ItemIndex >= 0 then
    FSpeed := SP[SegSpeed.ItemIndex];
end;

{ ================= live pattern card ================= }

procedure TMainForm.PatCardPaint(Sender: TObject);
var
  b: TBGRABitmap;
  x0, x1, y0, laneH, n, s, k: Integer;
  t, span, xa, xb, cx: Single;
  st: string;
begin
  b := CardPat.Bmp;
  n := Sim.PaddleCount;
  x0 := 40;
  x1 := CardPat.Width - 16;
  y0 := CardPat.BodyTop + 2;
  laneH := Max(6, Min(12, 84 div Max(1, n)));
  span := Max(1, Sim.CycleTime);
  for k := 0 to n - 1 do
  begin
    PText(b, x0 - 6, y0 + k * laneH - 2, 'P' + IntToStr(k + 1), 9, BGRA(100, 110, 130), False, taRightJustify);
    b.DrawLineAntialias(x0, y0 + k * laneH + laneH / 2, x1, y0 + k * laneH + laneH / 2, BGRA(228, 232, 240), 1);
  end;
  t := 0;
  for s := 0 to High(Sim.Pattern) do
  begin
    xa := x0 + t / span * (x1 - x0);
    xb := x0 + (t + Sim.Pattern[s].Duration) / span * (x1 - x0);
    for k := 0 to n - 1 do
      if Sim.Pattern[s].P[k] then
        b.FillRoundRectAntialias(xa + 0.5, y0 + k * laneH + 1, xb - 0.5, y0 + (k + 1) * laneH - 1, 2, 2,
          BGRA(50, 160, 70));
    b.DrawLineAntialias(xa, y0 - 2, xa, y0 + n * laneH + 2, BGRA(200, 206, 216), 1);
    if Sim.PatternActive and (s = Sim.PatStep) then
    begin
      cx := xa + Min(Sim.Pattern[s].Duration, Sim.PatElapsed) / span * (x1 - x0);
      b.FillRectAntialias(xa, y0 - 2, cx, y0 + n * laneH + 2, BGRA(40, 170, 60, 45));
      b.DrawLineAntialias(cx, y0 - 4, cx, y0 + n * laneH + 4, BGRA(220, 30, 30), 2);
    end;
    t := t + Sim.Pattern[s].Duration;
  end;
  if Sim.PatternActive then
    st := Format('Step %d/%d  [%s]  %.1f / %.1f s', [Sim.PatStep + 1, Length(Sim.Pattern),
      Sim.StepText(Sim.PatStep), Sim.PatElapsed, Sim.Pattern[Sim.PatStep].Duration])
  else
    st := Format('Stopped  -  %d steps, cycle %.1f s, %d paddles', [Length(Sim.Pattern), Sim.CycleTime, n]);
  PText(b, 14, CardPat.Height - 30, st, 12, TB(clThemeText), Sim.PatternActive);
end;

{ ================= device status strip ================= }

procedure TMainForm.StripPaint(Sender: TObject);
var
  bmp: TBGRABitmap;
  w, h, i, n, tw, x, y, k, evW: Integer;
  D: TDevice;
  vis: TDevVisual;
  c, tc: TBGRAPixel;
  s: string;
  e: TSimEvent;
begin
  w := FStrip.Width;
  h := FStrip.Height;
  if (w < 50) or (h < 20) then Exit;
  bmp := TBGRABitmap.Create(w, h, TB(clThemeBg));
  try
    n := 2 + Sim.PaddleCount;
    evW := Min(380, w div 4);
    tw := Min(168, (w - evW - 16 - (n - 1) * 6) div n);
    SetLength(FTileHit, n);
    x := 8;
    for i := 0 to n - 1 do
    begin
      D := Sim.Dev[i];
      vis := D.Visual;
      c := StateColor(vis);
      FTileHit[i].R := Rect(x, 6, x + tw, h - 8);
      FTileHit[i].Dev := i;
      bmp.FillRoundRectAntialias(x + 1, 8, x + tw + 1, h - 6, 8, 8, BGRA(0, 0, 0, 30));
      bmp.FillRoundRectAntialias(x, 6, x + tw, h - 8, 8, 8, TB(clThemeCard));
      { state band }
      bmp.FillRoundRectAntialias(x, 6, x + tw, 32, 8, 8, c);
      bmp.FillRectAntialias(x, 22, x + tw, 32, c);
      if IsManualVis(vis) then
        bmp.FillRectAntialias(x, 16, x + tw, 22, CL_ORANGE);
      if vis in [dvDisabled, dvFault, dvAutoRun, dvManualRun] then tc := BGRA(255, 255, 255) else tc := BGRA(25, 30, 40);
      PText(bmp, x + 8, 9, D.Name, 13, tc, True);
      DrawLed(bmp, x + tw - 14, 19, 5, BGRA(60, 255, 90), D.Running);
      PText(bmp, x + 8, 35, StateText(vis), 12, TB(clThemeText), True);
      if D.Running then
        PText(bmp, x + 8, 51, 'run ' + FmtTime(D.RunTime), 11, BGRA(0, 120, 40))
      else
        PText(bmp, x + 8, 51, Format('starts %d', [D.StartCount]), 11, TB(clThemeMuted));
      s := Sim.DevDelayText(i);
      if s <> '' then
        PText(bmp, x + 8, 67, s, 11, BGRA(210, 100, 0), True)
      else
        PText(bmp, x + 8, 67, Format('L%d %s', [D.CtrlLevel, D.Reason]), 11, TB(clThemeMuted));
      if FHover = i then
        bmp.RoundRectAntialias(x, 6, x + tw, h - 8, 8, 8, BGRA(0, 120, 255, 200), 2)
      else
        bmp.RoundRectAntialias(x, 6, x + tw, h - 8, 8, 8, TB(clThemeBorder), 1);
      Inc(x, tw + 6);
    end;
    { last events }
    x := w - evW - 8;
    FEventHit := Rect(x, 6, w - 8, h - 8);
    bmp.FillRoundRectAntialias(x, 6, w - 8, h - 8, 8, 8, BGRA(30, 36, 46));
    PText(bmp, x + 10, 9, 'Last events  (F3 = Events window)', 11, BGRA(150, 170, 200), True);
    y := 26;
    k := Sim.EventCount - 1;
    while (k >= 0) and (y < h - 22) do
    begin
      e := Sim.Events[k];
      case EventClass(e) of
        2: tc := BGRA(255, 110, 110);
        0: tc := BGRA(140, 190, 255);
      else
        if e.Value then tc := BGRA(120, 230, 130) else tc := BGRA(170, 175, 185);
      end;
      PText(bmp, x + 10, y, FormatDateTime('hh:nn:ss', e.Stamp) + '  ' + e.Text, 11, tc);
      Inc(y, 16);
      Dec(k);
    end;
    bmp.Draw(FStrip.Canvas, 0, 0, True);
  finally
    bmp.Free;
  end;
end;

procedure TMainForm.StripMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  i: Integer;
begin
  if Button <> mbLeft then Exit;
  for i := 0 to High(FTileHit) do
    if FTileHit[i].R.Contains(Point(X, Y)) then
    begin
      ShowDeviceForm(FTileHit[i].Dev);
      Exit;
    end;
  if FEventHit.Contains(Point(X, Y)) then
    ShowEventsForm;
end;

{ ================= overview ================= }

function TMainForm.PaddleY(K: Integer): Single;
var
  sp: Single;
begin
  { Paddle01 at the bottom; spacing 65 like HMI1 for 3 paddles, tighter for more }
  if Sim.PaddleCount <= 1 then
    sp := 0
  else
    sp := Min(65, (PADDLE_BOTTOM - PADDLE_TOP) / (Sim.PaddleCount - 1));
  Result := PADDLE_BOTTOM - K * sp;
end;

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
    if Sim.Dev[i].Installed and (dx >= FHit[i].Left) and (dx <= FHit[i].Right) and
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
    bmp.GradientFill(0, 0, w, h, BGRA(232, 236, 241), BGRA(208, 213, 220), gtLinear, PointF(0, 0), PointF(0, h),
      dmSet);
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
  big: Single;
begin
  D := Sim.Dev[I];
  vis := D.Visual;
  { smaller text when many paddles share the height }
  if IsPaddle(I) and (Sim.PaddleCount > 4) then big := 15 else big := 17;
  VText(bmp, X, Y, D.Name, big, BGRA(20, 25, 35), True, AAlign);
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
  VText(bmp, X, Y + big + 2, s, 12, c, True, AAlign);
  dly := Sim.DevDelayText(I);
  if dly <> '' then
    VText(bmp, X, Y + big + 16, 'delay: ' + dly, 12, BGRA(210, 100, 0), True, AAlign);
end;

procedure TMainForm.DrawScene(bmp: TBGRABitmap);
var
  i, k, j, n: Integer;
  lvlY, x, y, py, L1, L2, off, a: Single;
  inlet, outlet, feed: array of TPointF;
  blue, panel, frame, mat, matD, bladeC: TBGRAPixel;
  vis: TDevVisual;
  D: TDevice;
  matFlow: Boolean;
  r: TRect;

  procedure SetPts(var A: array of TPointF; const V: array of Single);
  var
    m: Integer;
  begin
    for m := 0 to High(A) do
      A[m] := PointF(V[m * 2], V[m * 2 + 1]);
  end;

begin
  blue := BGRA(50, 115, 185);
  panel := BGRA(178, 220, 246);
  frame := BGRA(40, 95, 165);
  mat := BGRA(246, 236, 212, 215);
  matD := BGRA(200, 185, 150, 200);
  n := Sim.PaddleCount;

  { ---------- hit areas (design coords) ---------- }
  for k := 0 to DEV_COUNT - 1 do
    FHit[k] := Rect(0, 0, 0, 0);
  FHit[DEV_BLOWER] := Rect(810, 555, 960, 735);
  FHit[DEV_SCREW] := Rect(20, 578, 342, 650);
  for k := 0 to n - 1 do
    FHit[DEV_PADDLE1 + k] := Rect(40, Round(PaddleY(k)) - 28, 342, Round(PaddleY(k)) + 26);

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
  for k := 0 to n - 1 do
  begin
    D := Sim.Dev[DEV_PADDLE1 + k];
    py := PaddleY(k);
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
      L1 := 22 * Cos(a);
      L2 := 22 * Sin(a);
      VLine(bmp, x - 6, py - L1, x - 6, py + L1, bladeC, 7);
      VLine(bmp, x + 6, py - L2, x + 6, py + L2, Darker(bladeC, 0.85), 7);
      VCircle(bmp, x, py, 4, BGRA(80, 85, 95));
    end;
    { paddle number on the shaft end }
    VCircle(bmp, 640, py, 9, BGRA(255, 255, 255, 220));
    VText(bmp, 640, py - 8, IntToStr(k + 1), 12, BGRA(30, 50, 90), True, taCenter);
  end;

  { ---------- silo frame ---------- }
  for i := 0 to 4 do
    VLine(bmp, 330 + i * 85, 150, 330 + i * 85, 385, WithAlpha(frame, 150), 3);
  VLine(bmp, 330, 150, 670, 150, frame, 4);
  VRect(bmp, 324, 381, 676, 391, blue);
  VLine(bmp, 340, 385, 340, 640, frame, 5);
  VLine(bmp, 660, 385, 660, 640, frame, 5);
  VLine(bmp, 330, 150, 330, 385, frame, 4);
  VLine(bmp, 670, 150, 670, 385, frame, 4);
  for k := 0 to n - 1 do
    VLine(bmp, 340, PaddleY(k) + 14, 660, PaddleY(k) + 14, WithAlpha(frame, 170), 2);
  VLine(bmp, 340, 596, 660, 596, frame, 2.5);
  { sight glasses (only where the paddles leave room for them) }
  if n <= 3 then
  for i := 0 to 1 do
  begin
    y := 248 + i * 80;
    VRect(bmp, 536, y, 556, y + 46, BGRA(245, 245, 245, 200));
    if lvlY < y + 46 then
      VRect(bmp, 536, Max(y, lvlY), 556, y + 46, BGRA(220, 205, 170, 200));
    VFrame(bmp, 536, y, 556, y + 46, BGRA(40, 40, 40), 1.5);
  end;
  if PlcMode and not Sim.ExtSiloLevel then
    VText(bmp, 345, 158, 'Level n/a', 13, BGRA(20, 50, 90), True)
  else
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
  DrawDeviceLabel(bmp, DEV_SCREW, 172, 646, taRightJustify);

  for k := 0 to n - 1 do
  begin
    D := Sim.Dev[DEV_PADDLE1 + k];
    py := PaddleY(k);
    vis := D.Visual;
    DrawMotor(bmp, 246, py - 18, 94, 36, vis);
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
  if PlcMode then
    FTiming.Insert(0, 'Source: PLC ' + ProtocolName(PlcCfg.Protocol) + ' ' + PlcCfg.Host +
      '  (delays = HMI estimate)')
  else
    FTiming.Insert(0, Format('Source: Simulation  (%d paddles)', [n]));
  VRound(bmp, 8, 8, 470, 30 + FTiming.Count * 19, 8, BGRA(255, 255, 255, 225));
  VRoundFrame(bmp, 8, 8, 470, 30 + FTiming.Count * 19, 8, BGRA(120, 130, 150), 1);
  VText(bmp, 18, 12, 'Sequence / Delays', 14, BGRA(30, 60, 120), True);
  for i := 0 to FTiming.Count - 1 do
    VText(bmp, 18, 30 + i * 19, FTiming[i], 13, BGRA(30, 30, 40), i = 1);

  { ---------- legend (right side, clear of the outlet pipe) ---------- }
  y := 312;
  VRound(bmp, 690, y - 8, 884, y + 6 * 22 + 22, 8, BGRA(255, 255, 255, 200));
  VRoundFrame(bmp, 690, y - 8, 884, y + 6 * 22 + 22, 8, BGRA(150, 160, 175), 1);
  VText(bmp, 700, y - 4, 'Legend', 14, BGRA(30, 60, 120), True);
  y += 18;
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
    VRound(bmp, 700, y + i * 22, 730, y + i * 22 + 15, 3, StateColor(vis));
    if IsManualVis(vis) then
      VRect(bmp, 700, y + i * 22 + 5, 730, y + i * 22 + 10, CL_ORANGE);
    VRoundFrame(bmp, 700, y + i * 22, 730, y + i * 22 + 15, 3, BGRA(60, 60, 60), 1);
    case i of
      0: VText(bmp, 738, y + i * 22, 'Auto run', 12, BGRA(30, 30, 40));
      1: VText(bmp, 738, y + i * 22, 'Stop / Interlock / E-Stop', 12, BGRA(30, 30, 40));
      2: VText(bmp, 738, y + i * 22, 'Manual Start', 12, BGRA(30, 30, 40));
      3: VText(bmp, 738, y + i * 22, 'Manual Stop', 12, BGRA(30, 30, 40));
      4: VText(bmp, 738, y + i * 22, 'Disabled', 12, BGRA(30, 30, 40));
      5: VText(bmp, 738, y + i * 22, 'Fault', 12, BGRA(30, 30, 40));
    end;
  end;

  if Sim.EStopMain then
  begin
    VRound(bmp, 690, 170, 990, 215, 8, BGRA(220, 30, 30, 230));
    VText(bmp, 840, 178, 'E-STOP ACTIVE', 22, BGRA(255, 255, 255), True, taCenter);
  end;
  if PlcMode and not Sim.CommOK then
  begin
    VRound(bmp, 690, 225, 990, 290, 8, BGRA(230, 120, 0, 235));
    if Link.Running then
      VText(bmp, 840, 230, 'PLC COMMUNICATION LOST', 20, BGRA(255, 255, 255), True, taCenter)
    else
      VText(bmp, 840, 230, 'PLC NOT CONNECTED', 20, BGRA(255, 255, 255), True, taCenter);
    VText(bmp, 840, 260, 'values shown are not live', 13, BGRA(255, 255, 255), False, taCenter);
  end;
end;

end.
