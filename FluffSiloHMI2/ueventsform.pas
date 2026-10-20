unit uEventsForm;

{ FluffSilo HMI2 - Events window (separate window, BGRABitmap list)
  - every event of Sim: commands, sequencer messages, signal changes
  - filter All / Commands / Signals / Alarms, auto scroll, clear (view only)
  - drag an event onto a chart, double-click = new chart with that signal
  - Save CSV (the rows shown), log file per day (uLog), open the log folder }

{$mode objfpc}{$H+}
{$COPERATORS ON}

interface

uses
  Classes, SysUtils, Math, Forms, Controls, Graphics, ExtCtrls, Dialogs, LCLType, LCLIntf,
  BGRABitmap, BGRABitmapTypes, uSim, uDraw, uWidgets, uChartForm, uLog, uPlcLink;

type

  { TEventView }

  TEventView = class(TCustomControl)
  private
    FIdx: array of Integer;
    FCount: Integer;
    FScanned: Integer;     { Sim events already looked at }
    FBase: Integer;        { first Sim event shown (Clear) }
    FTop: Integer;
    FSel: Integer;
    FFilter: Integer;
    FAutoScroll: Boolean;
    FDragSB: Boolean;
    FOnUserScroll: TNotifyEvent;
    function Accept(const E: TSimEvent): Boolean;
    function RowsVisible: Integer;
    function RowAt(Y: Integer): Integer;
    procedure SetFilter(V: Integer);
    procedure ScrollTo(ATop: Integer; AUser: Boolean);
    procedure SBMouse(Y: Integer);
  protected
    procedure Paint; override;
    procedure EraseBackground(DC: HDC); override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure DblClick; override;
    function DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean; override;
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
  public
    constructor Create(AOwner: TComponent); override;
    procedure Rebuild;
    procedure PullEvents;
    procedure ClearView;
    property Filter: Integer read FFilter write SetFilter;
    property AutoScroll: Boolean read FAutoScroll write FAutoScroll;
    property Count: Integer read FCount;
    property OnUserScroll: TNotifyEvent read FOnUserScroll write FOnUserScroll;
  end;

  { TEventsForm }

  TEventsForm = class(TForm)
  private
    FBar: TSimPanel;
    FFilterSeg: TSimSegment;
    FAuto, FLogFile: TSimToggle;
    FInfo: TSimLabel;
    FView: TEventView;
    procedure FilterChange(Sender: TObject);
    procedure AutoChange(Sender: TObject);
    procedure LogFileChange(Sender: TObject);
    procedure UserScroll(Sender: TObject);
    procedure ClearClick(Sender: TObject);
    procedure SaveClick(Sender: TObject);
    procedure FolderClick(Sender: TObject);
    procedure FormCloseEv(Sender: TObject; var CloseAction: TCloseAction);
  public
    constructor CreateEvents(AOwner: TComponent);
    procedure Tick;
  end;

function EventClass(const E: TSimEvent): Integer;   { 0 message, 1 signal, 2 alarm }
procedure ShowEventsForm;
procedure RefreshEventsForm;

var
  EventsForm: TEventsForm = nil;

implementation

const
  ROW_H = 20;
  HEAD_H = 24;
  SB_W = 12;

type
  TIntArray = array of Integer;

function EventClass(const E: TSimEvent): Integer;
var
  p: Integer;
  u: string;
begin
  if E.Sig >= 0 then
  begin
    p := E.Sig mod PROP_COUNT;
    if E.Value and (((E.Sig < SYS_BASE) and (p in [P_FAULT, P_ESTOP])) or (E.Sig = SYS_BASE + SYS_ESTOP)) then
      Exit(2);
    Exit(1);
  end;
  u := UpperCase(E.Text);
  if (Pos('REJECT', u) > 0) or (Pos('ERROR', u) > 0) or (Pos('LOST', u) > 0) or (Pos('E-STOP', u) > 0) or
     (Pos('NOT CONNECTED', u) > 0) or (Pos('FAULT', u) > 0) then
    Result := 2
  else
    Result := 0;
end;

procedure ShowEventsForm;
begin
  if EventsForm = nil then
    EventsForm := TEventsForm.CreateEvents(Application);
  EventsForm.Show;
  EventsForm.BringToFront;
end;

procedure RefreshEventsForm;
begin
  if EventsForm <> nil then
    EventsForm.Tick;
end;

{ TEventView }

constructor TEventView.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  ControlStyle := ControlStyle + [csOpaque];
  DoubleBuffered := True;
  TabStop := True;
  FAutoScroll := True;
  FSel := -1;
end;

function TEventView.Accept(const E: TSimEvent): Boolean;
var
  c: Integer;
begin
  c := EventClass(E);
  case FFilter of
    1: Result := E.Sig < 0;
    2: Result := E.Sig >= 0;
    3: Result := c = 2;
  else
    Result := True;
  end;
end;

procedure TEventView.SetFilter(V: Integer);
begin
  if V = FFilter then Exit;
  FFilter := V;
  Rebuild;
end;

procedure TEventView.Rebuild;
begin
  FCount := 0;
  FScanned := FBase;
  FSel := -1;
  PullEvents;
  if FAutoScroll then
    ScrollTo(FCount, False)
  else
    ScrollTo(FTop, False);
  Invalidate;
end;

procedure TEventView.ClearView;
begin
  FBase := Sim.EventCount;
  FTop := 0;
  Rebuild;
end;

procedure TEventView.PullEvents;
var
  added: Boolean;
begin
  if Sim = nil then Exit;
  added := False;
  while FScanned < Sim.EventCount do
  begin
    if Accept(Sim.Events[FScanned]) then
    begin
      if FCount >= Length(FIdx) then
        SetLength(FIdx, Max(1024, Length(FIdx) * 2));
      FIdx[FCount] := FScanned;
      Inc(FCount);
      added := True;
    end;
    Inc(FScanned);
  end;
  if added then
  begin
    if FAutoScroll then
      ScrollTo(FCount, False);
    Invalidate;
  end;
end;

function TEventView.RowsVisible: Integer;
begin
  Result := Max(1, (Height - HEAD_H) div ROW_H);
end;

function TEventView.RowAt(Y: Integer): Integer;
begin
  if Y < HEAD_H then Exit(-1);
  Result := FTop + (Y - HEAD_H) div ROW_H;
  if Result >= FCount then Result := -1;
end;

procedure TEventView.ScrollTo(ATop: Integer; AUser: Boolean);
begin
  ATop := EnsureRange(ATop, 0, Max(0, FCount - RowsVisible));
  if ATop <> FTop then
  begin
    FTop := ATop;
    Invalidate;
  end;
  if AUser then
  begin
    { scrolling up stops auto scroll, reaching the end starts it again }
    FAutoScroll := FTop >= FCount - RowsVisible;
    if Assigned(FOnUserScroll) then
      FOnUserScroll(Self);
  end;
end;

procedure TEventView.SBMouse(Y: Integer);
begin
  ScrollTo(Round((Y - HEAD_H) / Max(1, Height - HEAD_H) * FCount) - RowsVisible div 2, True);
end;

procedure TEventView.EraseBackground(DC: HDC);
begin
end;

procedure TEventView.Paint;
var
  bmp: TBGRABitmap;
  i, r, y, n, cls: Integer;
  e: TSimEvent;
  tc, bar: TBGRAPixel;
  p: Integer;
begin
  if (Width < 20) or (Height < 20) then Exit;
  bmp := TBGRABitmap.Create(Width, Height, BGRA(252, 253, 255));
  try
    { header }
    bmp.GradientFill(0, 0, Width, HEAD_H, BGRA(236, 241, 248), BGRA(220, 228, 239), gtLinear,
      PointF(0, 0), PointF(0, HEAD_H), dmSet);
    bmp.DrawLineAntialias(0, HEAD_H - 0.5, Width, HEAD_H - 0.5, BGRA(180, 190, 205), 1);
    PText(bmp, 14, 4, 'Sim time', 12, TB(clThemeTitle), True);
    PText(bmp, 104, 4, 'Clock', 12, TB(clThemeTitle), True);
    PText(bmp, 196, 4, 'Event', 12, TB(clThemeTitle), True);

    n := RowsVisible;
    for r := 0 to n do
    begin
      i := FTop + r;
      if i >= FCount then Break;
      y := HEAD_H + r * ROW_H;
      e := Sim.Events[FIdx[i]];
      cls := EventClass(e);
      if i = FSel then
        bmp.FillRectAntialias(0, y, Width - SB_W, y + ROW_H, BGRA(205, 225, 250))
      else if Odd(i) then
        bmp.FillRectAntialias(0, y, Width - SB_W, y + ROW_H, BGRA(243, 246, 250));
      { class bar + colour (same rules as HMI1) }
      if e.Sig < 0 then
      begin
        if cls = 2 then tc := BGRA(190, 30, 30) else tc := BGRA(0, 80, 160);
        bar := tc;
      end
      else
      begin
        p := e.Sig mod PROP_COUNT;
        if cls = 2 then tc := BGRA(210, 20, 20)
        else if (e.Sig < SYS_BASE) and (p in [P_MANSTART, P_MANSTOP]) and e.Value then tc := BGRA(224, 128, 0)
        else if e.Value then tc := BGRA(0, 128, 0)
        else tc := BGRA(128, 128, 128);
        bar := tc;
      end;
      bmp.FillRectAntialias(2, y + 3, 6, y + ROW_H - 3, bar);
      PText(bmp, 14, y + 2, FmtTime(e.T), 12, BGRA(70, 80, 95));
      PText(bmp, 104, y + 2, FormatDateTime('hh:nn:ss', e.Stamp), 12, BGRA(110, 120, 135));
      PText(bmp, 196, y + 2, e.Text, 13, tc, cls = 2);
      if e.Sig >= 0 then
        DrawIcon(bmp, ikChart, Width - SB_W - 22, y + 4, 12, BGRA(150, 165, 190));
    end;
    if FCount = 0 then
      PText(bmp, Width div 2, Height div 2 - 10, 'No events', 16, BGRA(150, 160, 175), True, taCenter);
    DrawScrollBar(bmp, Width - SB_W + 2, HEAD_H + 2, Height - HEAD_H - 4, FCount, n, FTop);
    if Focused then
      bmp.RectangleAntialias(0.5, 0.5, Width - 0.5, Height - 0.5, TB(clThemeAccent), 1);
    bmp.Draw(Canvas, 0, 0, True);
  finally
    bmp.Free;
  end;
end;

procedure TEventView.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  r: Integer;
begin
  inherited MouseDown(Button, Shift, X, Y);
  SetFocus;
  if Button <> mbLeft then Exit;
  if X >= Width - SB_W then
  begin
    FDragSB := True;
    SBMouse(Y);
    Exit;
  end;
  r := RowAt(Y);
  if r < 0 then Exit;
  FSel := r;
  Invalidate;
  if Sim.Events[FIdx[r]].Sig >= 0 then
  begin
    GDragSignal := Sim.Events[FIdx[r]].Sig;
    BeginDrag(False, 5);
  end;
end;

procedure TEventView.MouseMove(Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseMove(Shift, X, Y);
  if FDragSB then
    SBMouse(Y);
end;

procedure TEventView.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseUp(Button, Shift, X, Y);
  FDragSB := False;
end;

procedure TEventView.DblClick;
begin
  inherited DblClick;
  if (FSel >= 0) and (FSel < FCount) and (Sim.Events[FIdx[FSel]].Sig >= 0) then
    OpenChart([Sim.Events[FIdx[FSel]].Sig]);
end;

function TEventView.DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean;
begin
  Result := True;
  ScrollTo(FTop - Sign(WheelDelta) * 3, True);
end;

procedure TEventView.KeyDown(var Key: Word; Shift: TShiftState);
begin
  case Key of
    VK_UP: FSel := Max(0, FSel - 1);
    VK_DOWN: FSel := Min(FCount - 1, FSel + 1);
    VK_PRIOR: FSel := Max(0, FSel - RowsVisible);
    VK_NEXT: FSel := Min(FCount - 1, FSel + RowsVisible);
    VK_HOME: FSel := 0;
    VK_END: FSel := FCount - 1;
  else
    begin
      inherited KeyDown(Key, Shift);
      Exit;
    end;
  end;
  Key := 0;
  if FSel < FTop then ScrollTo(FSel, True)
  else if FSel >= FTop + RowsVisible then ScrollTo(FSel - RowsVisible + 1, True);
  Invalidate;
end;

{ TEventsForm }

constructor TEventsForm.CreateEvents(AOwner: TComponent);
begin
  inherited CreateNew(AOwner);
  Caption := 'FluffSilo HMI2 - Events';
  Width := 900;
  Height := 560;
  Position := poDesigned;
  Left := 140;
  Top := 160;
  Color := clThemeBg;
  OnClose := @FormCloseEv;

  FBar := NewPanel(Self, Self, '', clThemeAccent);
  FBar.Align := alTop;
  FBar.Height := 52;

  FFilterSeg := TSimSegment.Create(Self);
  FFilterSeg.Parent := FBar;
  FFilterSeg.SetBounds(10, 11, 320, 28);
  FFilterSeg.Items.CommaText := 'All,Commands,Signals,Alarms';
  FFilterSeg.ItemIndex := 0;
  FFilterSeg.OnChange := @FilterChange;

  FAuto := TSimToggle.Create(Self);
  FAuto.Parent := FBar;
  FAuto.SetBounds(342, 13, 120, 24);
  FAuto.Caption := 'Auto scroll';
  FAuto.Checked := True;
  FAuto.OnChange := @AutoChange;

  NewButton(Self, FBar, 466, 9, 96, 32, 'Clear', $00D8D8D8, ikClear, @ClearClick).Hint :=
    'Clear the list (the log file keeps everything)';
  NewButton(Self, FBar, 568, 9, 116, 32, 'Save CSV', $00D8D8D8, ikSave, @SaveClick).Hint :=
    'Save the rows shown to a CSV file';
  NewButton(Self, FBar, 690, 9, 96, 32, 'Logs', $00D8D8D8, ikFolder, @FolderClick).Hint :=
    'Open the folder of the daily log files';

  FLogFile := TSimToggle.Create(Self);
  FLogFile.Parent := FBar;
  FLogFile.SetBounds(796, 13, 100, 24);
  FLogFile.Caption := 'Log file';
  FLogFile.Checked := HmiOpt.LogToFile;
  FLogFile.OnChange := @LogFileChange;
  ShowHint := True;

  FInfo := NewLabel(Self, Self, 0, 0, 200, '', 12, False, clThemeMuted);
  FInfo.Align := alBottom;
  FInfo.Height := 22;
  FInfo.BorderSpacing.Left := 10;

  FView := TEventView.Create(Self);
  FView.Parent := Self;
  FView.Align := alClient;
  FView.BorderSpacing.Around := 6;
  FView.OnUserScroll := @UserScroll;
  FView.Rebuild;
end;

procedure TEventsForm.FormCloseEv(Sender: TObject; var CloseAction: TCloseAction);
begin
  CloseAction := caHide;
end;

procedure TEventsForm.Tick;
begin
  FView.PullEvents;
  if Visible then
    FInfo.Caption := Format('%d rows shown   |   %d events since start   |   log: %s',
      [FView.Count, Sim.EventCount, ExtractFileName(LogFileName(Now))]);
end;

procedure TEventsForm.FilterChange(Sender: TObject);
begin
  FView.Filter := FFilterSeg.ItemIndex;
end;

procedure TEventsForm.AutoChange(Sender: TObject);
begin
  FView.AutoScroll := FAuto.Checked;
  if FAuto.Checked then
    FView.Rebuild;
end;

procedure TEventsForm.UserScroll(Sender: TObject);
begin
  FAuto.Checked := FView.AutoScroll;
end;

procedure TEventsForm.LogFileChange(Sender: TObject);
begin
  HmiOpt.LogToFile := FLogFile.Checked;
  if not HmiOpt.LogToFile then
    LogClose;
  Sim.Log(-1, HmiOpt.LogToFile, 'Log file ' + OnOff(HmiOpt.LogToFile));
  try
    SaveConfig;
  except
  end;
end;

procedure TEventsForm.ClearClick(Sender: TObject);
begin
  FView.ClearView;
end;

procedure TEventsForm.SaveClick(Sender: TObject);
var
  dlg: TSaveDialog;
  idx: TIntArray;
  i: Integer;
begin
  dlg := TSaveDialog.Create(Self);
  try
    dlg.Filter := 'CSV (*.csv)|*.csv';
    dlg.DefaultExt := 'csv';
    dlg.FileName := 'Events_' + FormatDateTime('yyyymmdd_hhnnss', Now) + '.csv';
    if not dlg.Execute then Exit;
    SetLength(idx, FView.Count);
    for i := 0 to FView.Count - 1 do
      idx[i] := FView.FIdx[i];
    ExportEventsCsv(dlg.FileName, idx);
    Sim.Log(-1, True, Format('Events saved: %d rows -> %s', [Length(idx), dlg.FileName]));
  finally
    dlg.Free;
  end;
end;

procedure TEventsForm.FolderClick(Sender: TObject);
begin
  ForceDirectories(LogDir);
  OpenDocument(LogDir);
end;

end.
