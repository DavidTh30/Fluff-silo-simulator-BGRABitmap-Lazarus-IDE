unit uPatternForm;

{ FluffSilo HMI2 - Paddle Patterns + Delay Settings window (BGRABitmap)
  The editor works on a DRAFT copy of the pattern:
    Pattern -> File   save the draft as CSV          File -> Pattern   load a CSV into the draft
    Pattern -> PLC    write the draft to the PLC     PLC -> Pattern    read the PLC table into the draft
  (in simulation mode "PLC" is the simulator).  Up to MAX_STEPS steps x MAX_PADDLES paddles.
  Delay Settings and "Paddles installed" are written at once, like in HMI1. }

{$mode objfpc}{$H+}
{$COPERATORS ON}

interface

uses
  Classes, SysUtils, Math, Forms, Controls, Graphics, ExtCtrls, Dialogs, LCLType,
  BGRABitmap, BGRABitmapTypes, uSim, uDraw, uWidgets, uPlcLink;

type
  PPattern = ^TPattern;

  { TPatternGrid }

  TPatternGrid = class(TCustomControl)
  private
    FData: PPattern;
    FRow, FCol: Integer;            { selection: col 0 step, 1..7 paddles, 8 time }
    FHoverRow, FHoverCol: Integer;
    FPaint: Integer;                { -1 none, 0/1 = value painted while dragging }
    FEditing: Boolean;
    FBuf: string;
    FOnChange: TNotifyEvent;
    FActiveStep: Integer;           { step running in the PLC (-1 = not shown) }
    FTopRow: Integer;               { first row shown (scrolling) }
    FDragSB: Boolean;               { dragging the scroll bar }
    function VisRows: Integer;
    function ContentW: Integer;
    procedure SBScrollTo(Y: Integer);
    procedure EnsureVisible(R: Integer);
    procedure ScrollRows(D: Integer);
    function ColX(C: Integer): Integer;
    function ColW(C: Integer): Integer;
    procedure CellAt(X, Y: Integer; out C, R: Integer);
    procedure Changed;
    procedure SetCell(R, C: Integer; V: Boolean);
    procedure CommitEdit;
    procedure BumpTime(R: Integer; D: Double);
    function EnsureStep(R: Integer): Boolean;
    function RowTime(R: Integer): Double;
  protected
    procedure Paint; override;
    procedure EraseBackground(DC: HDC); override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseLeave; override;
    function DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean; override;
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
    procedure UTF8KeyPress(var UTF8Key: TUTF8Char); override;
    procedure DoExit; override;
  public
    constructor Create(AOwner: TComponent); override;
    procedure SelectRow(R: Integer);
    property Data: PPattern read FData write FData;
    property Row: Integer read FRow;
    property ActiveStep: Integer read FActiveStep write FActiveStep;
    property OnChange: TNotifyEvent read FOnChange write FOnChange;
  end;

  { TPatternForm }

  TPatternForm = class(TForm)
  private
    FDraft: TPattern;
    FFileName: string;
    FBar, FEdCard, FDelayCard, FSysCard, FLineCard: TSimPanel;
    FGrid: TPatternGrid;
    FTimeline: TPaintBox;
    FStatus, FHelp: TSimLabel;
    FBtnToPlc, FBtnFromPlc: TSimButton;
    FSpinDelay: array[0..DELAY_COUNT - 1] of TSimSpin;
    FSpinPaddles: TSimSpin;
    FUpdating: Boolean;
    FLastKey: string;
    procedure BuildUI;
    procedure DraftChanged(Sender: TObject);
    procedure EdResize(Sender: TObject);
    procedure ToFileClick(Sender: TObject);
    procedure FromFileClick(Sender: TObject);
    procedure ToPlcClick(Sender: TObject);
    procedure FromPlcClick(Sender: TObject);
    procedure AddClick(Sender: TObject);
    procedure InsertClick(Sender: TObject);
    procedure DeleteClick(Sender: TObject);
    procedure UpClick(Sender: TObject);
    procedure DownClick(Sender: TObject);
    procedure CopyClick(Sender: TObject);
    procedure ClearClick(Sender: TObject);
    procedure DefaultClick(Sender: TObject);
    procedure DelayChange(Sender: TObject);
    procedure PaddlesChange(Sender: TObject);
    procedure SysPaintBody(Sender: TObject);
    procedure TimelinePaint(Sender: TObject);
    procedure FormCloseEv(Sender: TObject; var CloseAction: TCloseAction);
    function DraftIsActive: Boolean;
    function PatternFolder: string;
  public
    constructor CreatePattern(AOwner: TComponent);
    procedure Tick;
    procedure LoadFromActive;
  end;

procedure ShowPatternForm;
procedure RefreshPatternForm;

var
  PatternForm: TPatternForm = nil;

implementation

const
  HEAD_H = 30;
  ROW_H = 22;
  STEP_W = 54;
  PAD_W = 62;
  TIME_W = 118;
  COL_TIME = MAX_PADDLES + 1;
  SB_W = 16;          { scroll bar strip at the right edge of the grid }

  PADDLE_COLORS: array[0..MAX_PADDLES - 1] of TColor =
    ($0040A040, $00C08030, $003080E0, $00B050B0, $0000A0C0, $00A0A000, $005060D0);

procedure ShowPatternForm;
begin
  if PatternForm = nil then
  begin
    PatternForm := TPatternForm.CreatePattern(Application);
    PatternForm.LoadFromActive;
  end;
  PatternForm.Show;
  PatternForm.BringToFront;
end;

procedure RefreshPatternForm;
begin
  if (PatternForm <> nil) and PatternForm.Visible then
    PatternForm.Tick;
end;

function PaddleColor(K: Integer): TBGRAPixel;
begin
  Result := TB(PADDLE_COLORS[K mod MAX_PADDLES]);
end;

{ ======================= TPatternGrid ======================= }

constructor TPatternGrid.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  ControlStyle := ControlStyle + [csOpaque];
  DoubleBuffered := True;
  TabStop := True;
  FPaint := -1;
  FHoverRow := -1;
  FActiveStep := -1;
  FCol := 1;
end;

function TPatternGrid.ColX(C: Integer): Integer;
begin
  if C = 0 then Result := 0
  else if C <= MAX_PADDLES then Result := STEP_W + (C - 1) * PAD_W
  else if C = COL_TIME then Result := STEP_W + MAX_PADDLES * PAD_W
  else Result := STEP_W + MAX_PADDLES * PAD_W + TIME_W;
end;

function TPatternGrid.ColW(C: Integer): Integer;
begin
  if C = 0 then Result := STEP_W
  else if C <= MAX_PADDLES then Result := PAD_W
  else if C = COL_TIME then Result := TIME_W
  else Result := Max(40, ContentW - ColX(C));
end;

procedure TPatternGrid.CellAt(X, Y: Integer; out C, R: Integer);
var
  i: Integer;
begin
  C := -1;
  R := -1;
  if (FData = nil) or (Y < HEAD_H) or (X >= ContentW) then Exit;
  { all MAX_STEPS rows are cells: an empty row becomes a step when it is edited }
  R := FTopRow + (Y - HEAD_H) div ROW_H;
  if R >= MAX_STEPS then R := -1;
  for i := 0 to COL_TIME + 1 do
    if (X >= ColX(i)) and (X < ColX(i) + ColW(i)) then
    begin
      C := i;
      Break;
    end;
end;

procedure TPatternGrid.Changed;
begin
  Invalidate;
  if Assigned(FOnChange) then
    FOnChange(Self);
end;

function TPatternGrid.VisRows: Integer;
begin
  Result := Max(1, (Height - HEAD_H) div ROW_H);
end;

function TPatternGrid.ContentW: Integer;
begin
  { cells end here; the strip on the right belongs to the scroll bar }
  Result := Max(40, Width - SB_W);
end;

procedure TPatternGrid.SBScrollTo(Y: Integer);
begin
  { centre the thumb on the mouse }
  ScrollRows(Round((Y - HEAD_H) / Max(1, Height - HEAD_H) * MAX_STEPS - VisRows / 2) - FTopRow);
end;

procedure TPatternGrid.ScrollRows(D: Integer);
begin
  { the view always covers all MAX_STEPS rows (used + empty) }
  D := EnsureRange(FTopRow + D, 0, Max(0, MAX_STEPS - VisRows));
  if D <> FTopRow then
  begin
    FTopRow := D;
    Invalidate;
  end;
end;

procedure TPatternGrid.EnsureVisible(R: Integer);
begin
  if R < FTopRow then ScrollRows(R - FTopRow)
  else if R >= FTopRow + VisRows then ScrollRows(R - FTopRow - VisRows + 1)
  else ScrollRows(0);
end;

procedure TPatternGrid.SelectRow(R: Integer);
begin
  if FData = nil then Exit;
  FRow := EnsureRange(R, 0, Max(0, High(FData^)));
  EnsureVisible(FRow);
  Invalidate;
end;

function TPatternGrid.EnsureStep(R: Integer): Boolean;
var
  n, i: Integer;
begin
  { editing an empty row adds steps (pause, 5 s) up to and including it }
  Result := (FData <> nil) and (R >= 0) and (R < MAX_STEPS);
  if not Result then Exit;
  n := Length(FData^);
  if R < n then Exit;
  SetLength(FData^, R + 1);
  for i := n to R do
  begin
    FillChar(FData^[i], SizeOf(TPatternStep), 0);
    FData^[i].Duration := 5;
  end;
  Changed;
end;

procedure TPatternGrid.SetCell(R, C: Integer; V: Boolean);
begin
  if (FData = nil) or (R < 0) or (C < 1) or (C > MAX_PADDLES) then Exit;
  if C > Sim.PaddleCount then Exit;   { not installed }
  if not EnsureStep(R) then Exit;
  if FData^[R].P[C - 1] = V then Exit;
  FData^[R].P[C - 1] := V;
  Changed;
end;

procedure TPatternGrid.BumpTime(R: Integer; D: Double);
var
  v: Double;
begin
  if not EnsureStep(R) then Exit;
  v := NormStepTime(FData^[R].Duration + D);
  if Abs(v - FData^[R].Duration) < 1e-9 then Exit;
  FData^[R].Duration := v;
  Changed;
end;

procedure TPatternGrid.CommitEdit;
var
  v: Double;
  fs: TFormatSettings;
begin
  if not FEditing then Exit;
  FEditing := False;
  fs := DefaultFormatSettings;
  fs.DecimalSeparator := '.';
  if TryStrToFloat(StringReplace(FBuf, ',', '.', []), v, fs) and EnsureStep(FRow) then
  begin
    FData^[FRow].Duration := NormStepTime(v);
    Changed;
  end
  else
    Invalidate;
end;

procedure TPatternGrid.EraseBackground(DC: HDC);
begin
end;

procedure TPatternGrid.Paint;
var
  bmp: TBGRABitmap;
  r, c, x, y, n, w: Integer;
  st: TPatternStep;
  inst, isOn, running: Boolean;
  pc, cellC: TBGRAPixel;
  s: string;
begin
  if (Width < 20) or (Height < 20) then Exit;
  bmp := TBGRABitmap.Create(Width, Height, BGRA(252, 253, 255));
  try
    { header }
    bmp.GradientFill(0, 0, Width, HEAD_H, BGRA(236, 241, 248), BGRA(218, 226, 238), gtLinear,
      PointF(0, 0), PointF(0, HEAD_H), dmSet);
    PText(bmp, ColX(0) + STEP_W div 2, 7, 'Step', 13, TB(clThemeTitle), True, taCenter);
    for c := 1 to MAX_PADDLES do
    begin
      x := ColX(c);
      inst := c <= Sim.PaddleCount;
      if inst then
      begin
        bmp.FillRoundRectAntialias(x + 6, 6, x + 14, HEAD_H - 6, 2, 2, PaddleColor(c - 1));
        PText(bmp, x + PAD_W div 2 + 4, 7, 'P' + IntToStr(c), 13, TB(clThemeTitle), True, taCenter);
      end
      else
        PText(bmp, x + PAD_W div 2, 7, 'P' + IntToStr(c), 13, BGRA(170, 175, 185), False, taCenter);
    end;
    PText(bmp, ColX(COL_TIME) + TIME_W div 2, 7, 'Time (s)', 13, TB(clThemeTitle), True, taCenter);
    PText(bmp, ColX(COL_TIME + 1) + 8, 7, 'Paddles', 13, TB(clThemeTitle), True);
    bmp.DrawLineAntialias(0, HEAD_H - 0.5, Width, HEAD_H - 0.5, BGRA(180, 190, 205), 1);

    if FData = nil then n := 0 else n := Length(FData^);
    for r := FTopRow to Min(n - 1, FTopRow + VisRows) do
    begin
      y := HEAD_H + (r - FTopRow) * ROW_H;
      st := FData^[r];
      running := r = FActiveStep;
      if running then
        bmp.FillRectAntialias(0, y, ContentW, y + ROW_H, BGRA(214, 245, 214))
      else if r = FRow then
        bmp.FillRectAntialias(0, y, ContentW, y + ROW_H, BGRA(222, 234, 252))
      else if Odd(r) then
        bmp.FillRectAntialias(0, y, ContentW, y + ROW_H, BGRA(244, 247, 251));
      { step number }
      if running then
      begin
        bmp.FillRoundRectAntialias(4, y + 3, STEP_W - 4, y + ROW_H - 3, 5, 5, BGRA(40, 170, 60));
        PText(bmp, STEP_W div 2, y + 3, IntToStr(r + 1), 13, BGRA(255, 255, 255), True, taCenter);
      end
      else
        PText(bmp, STEP_W div 2, y + 3, IntToStr(r + 1), 13, BGRA(60, 70, 90), r = FRow, taCenter);
      { paddle cells }
      for c := 1 to MAX_PADDLES do
      begin
        x := ColX(c);
        inst := c <= Sim.PaddleCount;
        isOn := st.P[c - 1];
        if not inst then
        begin
          DrawHatch(bmp, x + 3, y + 3, x + PAD_W - 3, y + ROW_H - 3, BGRA(200, 205, 212), 5);
          if isOn then
            PText(bmp, x + PAD_W div 2, y + 3, 'x', 13, BGRA(200, 80, 80), True, taCenter);
          Continue;
        end;
        pc := PaddleColor(c - 1);
        if isOn then
        begin
          cellC := pc;
          if running then cellC := Lighter(pc, 0.0);
          bmp.FillRoundRectAntialias(x + 4, y + 3, x + PAD_W - 4, y + ROW_H - 3, 6, 6, cellC);
          bmp.FillRoundRectAntialias(x + 6, y + 4, x + PAD_W - 6, y + ROW_H div 2, 4, 4, BGRA(255, 255, 255, 60));
          PText(bmp, x + PAD_W div 2, y + 4, 'RUN', 12, BGRA(255, 255, 255), True, taCenter);
        end
        else
        begin
          bmp.RoundRectAntialias(x + 4, y + 3, x + PAD_W - 4, y + ROW_H - 3, 6, 6, BGRA(205, 212, 222), 1);
          PText(bmp, x + PAD_W div 2, y + 4, '-', 12, BGRA(170, 178, 190), False, taCenter);
        end;
        if (r = FHoverRow) and (c = FHoverCol) then
          bmp.RoundRectAntialias(x + 3, y + 2, x + PAD_W - 3, y + ROW_H - 2, 6, 6, TB(clThemeAccent), 1.5);
      end;
      { time }
      x := ColX(COL_TIME);
      if FEditing and (r = FRow) then
      begin
        bmp.FillRoundRectAntialias(x + 4, y + 2, x + TIME_W - 4, y + ROW_H - 2, 5, 5, BGRA(255, 250, 225));
        bmp.RoundRectAntialias(x + 4, y + 2, x + TIME_W - 4, y + ROW_H - 2, 5, 5, TB(clThemeAccent), 1.5);
        s := FBuf + '_';
        PText(bmp, x + TIME_W div 2, y + 3, s, 13, BGRA(0, 60, 160), True, taCenter);
      end
      else
      begin
        if (r = FRow) and (FCol = COL_TIME) then
          bmp.RoundRectAntialias(x + 4, y + 2, x + TIME_W - 4, y + ROW_H - 2, 5, 5, TB(clThemeAccent), 1.2)
        else if (r = FHoverRow) and (FHoverCol = COL_TIME) then
          bmp.RoundRectAntialias(x + 4, y + 2, x + TIME_W - 4, y + ROW_H - 2, 5, 5, BGRA(160, 175, 200), 1);
        PText(bmp, x + TIME_W div 2, y + 3, FormatFloat('0.0', st.Duration), 13, BGRA(25, 30, 40), True,
          taCenter);
      end;
      { label + duration bar }
      x := ColX(COL_TIME + 1);
      s := StepLabel(st, Sim.PaddleCount);
      if s = 'Pause' then
        PText(bmp, x + 8, y + 3, 'Pause', 13, BGRA(140, 145, 160), False)
      else
        PText(bmp, x + 8, y + 3, s, 13, BGRA(30, 40, 60), True);
      w := ColW(COL_TIME + 1);
      if w > 150 then
        bmp.FillRoundRectAntialias(x + w - 70, y + 9, x + w - 70 + Min(60, st.Duration * 6), y + ROW_H - 9, 3, 3,
          BGRA(120, 150, 200, 150));
    end;
    { empty rows (capacity) }
    for r := Max(n, FTopRow) to MAX_STEPS - 1 do
    begin
      y := HEAD_H + (r - FTopRow) * ROW_H;
      if y > Height then Break;
      if r = FRow then
        bmp.FillRectAntialias(0, y, ContentW, y + ROW_H, BGRA(232, 240, 252));
      PText(bmp, STEP_W div 2, y + 3, IntToStr(r + 1), 12, BGRA(185, 192, 204), r = FRow, taCenter);
      if FEditing and (r = FRow) then
      begin
        x := ColX(COL_TIME);
        bmp.FillRoundRectAntialias(x + 4, y + 2, x + TIME_W - 4, y + ROW_H - 2, 5, 5, BGRA(255, 250, 225));
        bmp.RoundRectAntialias(x + 4, y + 2, x + TIME_W - 4, y + ROW_H - 2, 5, 5, TB(clThemeAccent), 1.5);
        PText(bmp, x + TIME_W div 2, y + 3, FBuf + '_', 13, BGRA(0, 60, 160), True, taCenter);
      end
      else if (r = FHoverRow) and (FHoverCol >= 1) and (FHoverCol <= Sim.PaddleCount) then
      begin
        x := ColX(FHoverCol);
        bmp.RoundRectAntialias(x + 4, y + 3, x + PAD_W - 4, y + ROW_H - 3, 6, 6, TB(clThemeAccent), 1);
      end;
      if (r = n) or (r = FRow) then
        PText(bmp, ColX(COL_TIME + 1) + 8, y + 4, 'empty - click a P cell or type a time to add', 11,
          BGRA(165, 172, 185), False);
      bmp.DrawLineAntialias(STEP_W, y + ROW_H - 0.5, ContentW, y + ROW_H - 0.5, BGRA(238, 241, 245), 1);
    end;
    { grid lines }
    for c := 1 to COL_TIME + 1 do
      bmp.DrawLineAntialias(ColX(c) - 0.5, 0, ColX(c) - 0.5, HEAD_H + Max(n, MAX_STEPS) * ROW_H,
        BGRA(225, 230, 238), 1);
    { scroll bar strip (rows never draw over it) }
    bmp.FillRectAntialias(ContentW, HEAD_H, Width, Height, BGRA(238, 241, 246));
    bmp.DrawLineAntialias(ContentW + 0.5, HEAD_H, ContentW + 0.5, Height, BGRA(215, 221, 230), 1);
    DrawScrollBar(bmp, ContentW + (SB_W - 8) div 2, HEAD_H + 2, Height - HEAD_H - 4, MAX_STEPS, VisRows, FTopRow);
    if n = 0 then
      PText(bmp, Width div 2, HEAD_H + 40, 'Empty pattern - press "Add step"', 15, BGRA(150, 160, 175), True,
        taCenter);
    if Focused then
      bmp.RectangleAntialias(0.5, 0.5, Width - 0.5, Height - 0.5, TB(clThemeAccent), 1);
    bmp.Draw(Canvas, 0, 0, True);
  finally
    bmp.Free;
  end;
end;

procedure TPatternGrid.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  c, r: Integer;
begin
  inherited MouseDown(Button, Shift, X, Y);
  SetFocus;
  if Button <> mbLeft then Exit;
  if (X >= ContentW) and (Y >= HEAD_H) then
  begin
    { scroll bar: jump there and keep dragging }
    CommitEdit;
    FDragSB := True;
    SBScrollTo(Y);
    Exit;
  end;
  CellAt(X, Y, c, r);
  if r < 0 then Exit;
  if FEditing and ((r <> FRow) or (c <> COL_TIME)) then
    CommitEdit;
  FRow := r;
  if c >= 0 then FCol := c;
  if (c >= 1) and (c <= MAX_PADDLES) then
  begin
    { click toggles, dragging paints the same value over more cells }
    FPaint := Ord(not ((r < Length(FData^)) and FData^[r].P[c - 1]));
    SetCell(r, c, FPaint = 1);
  end
  else if c = COL_TIME then
  begin
    if not FEditing then
    begin
      FEditing := True;
      FBuf := FormatFloat('0.0', RowTime(r));
    end;
  end;
  Invalidate;
end;

function TPatternGrid.RowTime(R: Integer): Double;
begin
  if (FData <> nil) and (R >= 0) and (R < Length(FData^)) then
    Result := FData^[R].Duration
  else
    Result := 5;
end;

procedure TPatternGrid.MouseMove(Shift: TShiftState; X, Y: Integer);
var
  c, r: Integer;
begin
  inherited MouseMove(Shift, X, Y);
  if FDragSB then
  begin
    SBScrollTo(Y);
    Exit;
  end;
  CellAt(X, Y, c, r);
  if (c <> FHoverCol) or (r <> FHoverRow) then
  begin
    FHoverCol := c;
    FHoverRow := r;
    if (FPaint >= 0) and (ssLeft in Shift) and (r >= 0) then
      SetCell(r, c, FPaint = 1);
    Invalidate;
  end;
  if (c >= 1) and (c <= MAX_PADDLES) and (r >= 0) then Cursor := crHandPoint
  else if c = COL_TIME then Cursor := crIBeam
  else Cursor := crDefault;
end;

procedure TPatternGrid.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseUp(Button, Shift, X, Y);
  FPaint := -1;
  FDragSB := False;
end;

procedure TPatternGrid.MouseLeave;
begin
  inherited MouseLeave;
  FHoverRow := -1;
  FHoverCol := -1;
  Invalidate;
end;

function TPatternGrid.DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean;
var
  c, r: Integer;
  d: Double;
begin
  Result := True;
  { wheel = scroll; Ctrl + wheel over a Time cell = +/-0.5 s (Ctrl + Shift = 5 s) }
  CellAt(MousePos.X, MousePos.Y, c, r);
  if (ssCtrl in Shift) and (c = COL_TIME) and (r >= 0) then
  begin
    CommitEdit;
    if ssShift in Shift then d := 5 else d := 0.5;
    BumpTime(r, Sign(WheelDelta) * d);
  end
  else
    ScrollRows(-Sign(WheelDelta) * 2);
end;

procedure TPatternGrid.KeyDown(var Key: Word; Shift: TShiftState);
var
  n: Integer;
begin
  if FData = nil then Exit;
  n := Length(FData^);
  case Key of
    VK_RETURN:
      if FEditing then CommitEdit
      else if FCol = COL_TIME then
      begin
        FEditing := True;
        FBuf := FormatFloat('0.0', RowTime(FRow));
        Invalidate;
      end;
    VK_ESCAPE:
      begin
        FEditing := False;
        Invalidate;
      end;
    VK_UP:
      begin
        CommitEdit;
        FRow := Max(0, FRow - 1);
        EnsureVisible(FRow);
        Invalidate;
      end;
    VK_DOWN:
      begin
        CommitEdit;
        FRow := Min(MAX_STEPS - 1, FRow + 1);
        EnsureVisible(FRow);
        Invalidate;
      end;
    VK_LEFT:
      begin
        CommitEdit;
        FCol := Max(1, FCol - 1);
        Invalidate;
      end;
    VK_RIGHT:
      begin
        CommitEdit;
        FCol := Min(COL_TIME, FCol + 1);
        Invalidate;
      end;
    VK_SPACE:
      if (FCol >= 1) and (FCol <= MAX_PADDLES) then
        SetCell(FRow, FCol, not ((FRow < n) and FData^[FRow].P[FCol - 1]));
    VK_HOME:
      begin
        CommitEdit;
        FRow := 0;
        EnsureVisible(FRow);
        Invalidate;
      end;
    VK_END:
      begin
        CommitEdit;
        FRow := MAX_STEPS - 1;
        EnsureVisible(FRow);
        Invalidate;
      end;
    VK_ADD, VK_PRIOR:
      BumpTime(FRow, 0.5);
    VK_SUBTRACT, VK_NEXT:
      BumpTime(FRow, -0.5);
    VK_BACK:
      if FEditing and (FBuf <> '') then
      begin
        Delete(FBuf, Length(FBuf), 1);
        Invalidate;
      end;
  else
    begin
      inherited KeyDown(Key, Shift);
      Exit;
    end;
  end;
  Key := 0;
end;

procedure TPatternGrid.UTF8KeyPress(var UTF8Key: TUTF8Char);
begin
  if (FData <> nil) and (FRow < MAX_STEPS) and (Length(UTF8Key) = 1) and
     (UTF8Key[1] in ['0'..'9', '.', ',']) then
  begin
    if not FEditing then
    begin
      FEditing := True;
      FCol := COL_TIME;
      FBuf := '';
    end;
    if Length(FBuf) < 6 then
      FBuf := FBuf + UTF8Key;
    Invalidate;
    UTF8Key := '';
  end;
  inherited UTF8KeyPress(UTF8Key);
end;

procedure TPatternGrid.DoExit;
begin
  CommitEdit;
  inherited DoExit;
end;

{ ======================= TPatternForm ======================= }

constructor TPatternForm.CreatePattern(AOwner: TComponent);
begin
  inherited CreateNew(AOwner);
  Caption := 'FluffSilo HMI2 - Paddle Patterns & Delay Settings';
  Color := clThemeBg;
  DoubleBuffered := True;
  ClientWidth := Min(1290, Screen.WorkAreaWidth - 20);
  ClientHeight := Min(900, Screen.WorkAreaHeight - 40);
  Position := poMainFormCenter;
  KeyPreview := True;
  OnClose := @FormCloseEv;
  ShowHint := True;
  BuildUI;
end;

procedure TPatternForm.BuildUI;
const
  DELAY_NAMES: array[0..DELAY_COUNT - 1] of string =
    ('Blower -> Screw start', 'External Request hold', 'Screw -> Paddle Patterns',
     'Request lost -> Screw stop', 'Screw stopped -> Blower stop', 'Auto Stop -> Blower stop');
var
  right: TPanel;
  bx, i, y, dy: Integer;
  b: TSimButton;

  function TB2(X: Integer; const ACap: string; AIcon: TIconKind; AClick: TNotifyEvent; const AHint: string;
    AColor: TColor = $00EAE4DE; W: Integer = 104): TSimButton;
  begin
    Result := NewButton(Self, FEdCard, X, FEdCard.BodyTop, W, 30, ACap, AColor, AIcon, AClick);
    Result.Hint := AHint;
  end;

begin
  { ---------- transfer bar ---------- }
  FBar := NewPanel(Self, Self, 'Transfer', clThemeAccent);
  FBar.Align := alTop;
  FBar.Height := 92;
  FBar.BorderSpacing.Around := 6;
  bx := 12;
  b := NewButton(Self, FBar, bx, FBar.BodyTop, 176, 48, 'Pattern  >  File', $00F0E6DC, ikSave, @ToFileClick);
  b.SubText := 'save the draft (CSV)';
  b.Hint := 'Save the pattern in the editor to a CSV file';
  b := NewButton(Self, FBar, bx + 184, FBar.BodyTop, 176, 48, 'File  >  Pattern', $00F0E6DC, ikOpen, @FromFileClick);
  b.SubText := 'load a CSV into the editor';
  b.Hint := 'Load a pattern file into the editor (the PLC is not changed yet)';
  FBtnToPlc := NewButton(Self, FBar, bx + 380, FBar.BodyTop, 186, 48, 'Pattern  >  PLC', $0040A040, ikUpload,
    @ToPlcClick);
  FBtnToPlc.SubText := 'write the draft';
  FBtnToPlc.Hint := 'Write the pattern in the editor to the PLC (only changed steps are sent)';
  FBtnFromPlc := NewButton(Self, FBar, bx + 574, FBar.BodyTop, 186, 48, 'PLC  >  Pattern', $00C08040, ikDownload,
    @FromPlcClick);
  FBtnFromPlc.SubText := 'read the active table';
  FBtnFromPlc.Hint := 'Copy the pattern that is active in the PLC into the editor';
  FStatus := NewLabel(Self, FBar, bx + 774, FBar.BodyTop + 2, 480, '', 13, True, clThemeText);
  FStatus.Height := 44;

  { ---------- right column: delays + system ---------- }
  right := TPanel.Create(Self);
  right.Parent := Self;
  right.Align := alRight;
  right.Width := 380;
  right.BevelOuter := bvNone;
  right.Color := clThemeBg;
  right.ParentBackground := False;

  { short screens (e.g. 1366 x 768): tighter rows, smaller timeline }
  if ClientHeight < 860 then dy := 34 else dy := 40;
  FDelayCard := NewPanel(Self, right, 'Delay Settings (seconds)', $0030A0F0);
  FDelayCard.Align := alTop;
  FDelayCard.Height := DELAY_COUNT * dy + 66;
  FDelayCard.BorderSpacing.Around := 6;
  for i := 0 to DELAY_COUNT - 1 do
  begin
    y := FDelayCard.BodyTop + 4 + i * dy;
    NewLabel(Self, FDelayCard, 14, y + 3, 190, DELAY_NAMES[i], 13, False, clThemeText);
    FSpinDelay[i] := NewSpin(Self, FDelayCard, 210, y, 150, 0, 600, 0.5, 1, ' s');
    FSpinDelay[i].Tag := i;
    FSpinDelay[i].Value := SimDelay(i);
    FSpinDelay[i].OnChange := @DelayChange;
  end;
  NewLabel(Self, FDelayCard, 14, FDelayCard.BodyTop + 2 + DELAY_COUNT * dy, 350,
    'Written at once to the ' + 'PLC / simulator (wheel, +/-, type + Enter)', 11, False, clThemeMuted);

  FSysCard := NewPanel(Self, right, 'System', $00808080);
  FSysCard.Align := alTop;
  FSysCard.Top := 2000;
  FSysCard.Height := 140;
  FSysCard.BorderSpacing.Around := 6;
  FSysCard.OnPaintBody := @SysPaintBody;
  NewLabel(Self, FSysCard, 14, FSysCard.BodyTop + 7, 190, 'Paddles installed', 13, True, clThemeText);
  FSpinPaddles := NewSpin(Self, FSysCard, 210, FSysCard.BodyTop + 4, 150, 1, MAX_PADDLES, 1, 0, '');
  FSpinPaddles.Value := Sim.PaddleCount;
  FSpinPaddles.OnChange := @PaddlesChange;
  FSpinPaddles.Hint := Format('1..%d paddles; the others are hidden and never run', [MAX_PADDLES]);

  { ---------- timeline (bottom) ---------- }
  FLineCard := NewPanel(Self, Self, 'Timeline  (draft above, active below)', $00C08040);
  FLineCard.Align := alBottom;
  if dy < 40 then
    FLineCard.Height := 2 * (MAX_PADDLES * 6 + 20) + 44
  else
    FLineCard.Height := 2 * (MAX_PADDLES * 9 + 22) + 46;
  FLineCard.BorderSpacing.Around := 6;
  FTimeline := TPaintBox.Create(Self);
  FTimeline.Parent := FLineCard;
  FTimeline.SetBounds(10, FLineCard.BodyTop, FLineCard.Width - 22, FLineCard.Height - FLineCard.BodyTop - 10);
  FTimeline.Anchors := [akLeft, akTop, akRight, akBottom];
  FTimeline.OnPaint := @TimelinePaint;

  { ---------- editor ---------- }
  FEdCard := NewPanel(Self, Self, Format('Pattern Editor (draft)  -  max %d steps x %d paddles',
    [MAX_STEPS, MAX_PADDLES]), $0040A040);
  FEdCard.Align := alClient;
  FEdCard.BorderSpacing.Around := 6;
  TB2(12, 'Add', ikAdd, @AddClick, 'Add a step at the end', $00EAE4DE, 82);
  TB2(98, 'Insert', ikInsert, @InsertClick, 'Insert a step before the selected one', $00EAE4DE, 96);
  TB2(198, 'Delete', ikDelete, @DeleteClick, 'Delete the selected step', $00EAE4DE, 96);
  TB2(298, 'Up', ikUp, @UpClick, 'Move the selected step up', $00EAE4DE, 70);
  TB2(372, 'Down', ikDown, @DownClick, 'Move the selected step down', $00EAE4DE, 82);
  TB2(458, 'Copy', ikCopy, @CopyClick, 'Duplicate the selected step', $00EAE4DE, 82);
  TB2(544, 'Clear', ikClear, @ClearClick, 'Remove all steps', $00EAE4DE, 82);
  TB2(630, 'Default', ikDefault, @DefaultClick, 'Concept pattern: each paddle 8 s + 2 s pause', $00EAE4DE, 100);
  FGrid := TPatternGrid.Create(Self);
  FGrid.Parent := FEdCard;
  FGrid.Data := @FDraft;
  FGrid.OnChange := @DraftChanged;
  FHelp := NewLabel(Self, FEdCard, 12, 0, 760,
    'Wheel / scroll bar = scroll.  Click P cell = RUN/pause.  Time: type or Ctrl+wheel.  ' +
    'Keys: arrows, Home/End, Space.  Empty row: edit = add steps.',
    11, False, clThemeMuted);
  FEdCard.OnResize := @EdResize;
  EdResize(nil);
end;

procedure TPatternForm.EdResize(Sender: TObject);
var
  h: Integer;
begin
  { the grid takes the card height (all 20 rows when there is room, else it scrolls) }
  h := Min(HEAD_H + MAX_STEPS * ROW_H + 2, FEdCard.Height - FEdCard.BodyTop - 38 - 30);
  FGrid.SetBounds(10, FEdCard.BodyTop + 38, FEdCard.Width - 22, Max(HEAD_H + ROW_H * 3, h));
  FHelp.SetBounds(12, FGrid.Top + FGrid.Height + 4, FEdCard.Width - 24, 20);
end;

procedure TPatternForm.FormCloseEv(Sender: TObject; var CloseAction: TCloseAction);
begin
  CloseAction := caHide;
end;

function TPatternForm.PatternFolder: string;
begin
  Result := HmiOpt.PatternDir;
  if (Result = '') or not DirectoryExists(Result) then
    Result := ExtractFilePath(ParamStr(0)) + 'patterns';
end;

procedure TPatternForm.LoadFromActive;
begin
  FDraft := Copy(Sim.Pattern);
  FFileName := '';
  FGrid.SelectRow(0);
  DraftChanged(nil);
end;

function TPatternForm.DraftIsActive: Boolean;
begin
  Result := PatternsEqual(FDraft, Sim.Pattern, MAX_PADDLES);
end;

procedure TPatternForm.DraftChanged(Sender: TObject);
begin
  FGrid.Invalidate;
  FTimeline.Invalidate;
  FLastKey := '';
  Tick;
end;

procedure TPatternForm.Tick;
var
  i: Integer;
  key, s: string;
  same: Boolean;
begin
  FUpdating := True;
  try
    for i := 0 to DELAY_COUNT - 1 do
      if (not FSpinDelay[i].Focused) and (Abs(FSpinDelay[i].Value - SimDelay(i)) > 1e-6) then
        FSpinDelay[i].Value := SimDelay(i);
    if not FSpinPaddles.Focused then
      FSpinPaddles.Value := Sim.PaddleCount;
  finally
    FUpdating := False;
  end;

  same := DraftIsActive;
  if same and Sim.PatternActive then FGrid.ActiveStep := Sim.PatStep else FGrid.ActiveStep := -1;
  key := Format('%d|%d|%d|%d|%d|%d|%d', [Ord(same), Sim.PatStep, Ord(Sim.PatternActive), Sim.PatternSeq,
    Sim.PaddleCount, Ord(PlcMode), Ord(Sim.CommOK)]);
  FBtnToPlc.Caption := 'Pattern  >  ' + TargetName;
  FBtnFromPlc.Caption := TargetName + '  >  Pattern';
  FBtnToPlc.Enabled := (not PlcMode) or Link.Running;
  if key <> FLastKey then
  begin
    FLastKey := key;
    if same then
    begin
      s := 'Editor = ' + TargetName + '  (in use)';
      FStatus.TextColor := $00008000;
    end
    else
    begin
      s := 'Editor modified - not in ' + TargetName + ' yet  (press "Pattern > ' + TargetName + '")';
      FStatus.TextColor := $000060D0;
    end;
    if PlcMode and not Sim.CommOK then
      s := s + '   [PLC values not live]';
    FStatus.Caption := s;
    FGrid.Invalidate;
    FSysCard.Invalidate;
  end;
  FTimeline.Invalidate;
end;

{ ---------------- transfer ---------------- }

procedure TPatternForm.ToFileClick(Sender: TObject);
var
  dlg: TSaveDialog;
begin
  dlg := TSaveDialog.Create(Self);
  try
    dlg.Filter := 'Paddle pattern (*.csv)|*.csv|All files|*.*';
    dlg.DefaultExt := 'csv';
    dlg.InitialDir := PatternFolder;
    ForceDirectories(dlg.InitialDir);
    if FFileName <> '' then
      dlg.FileName := ExtractFileName(FFileName)
    else
      dlg.FileName := 'Pattern_' + FormatDateTime('yyyymmdd_hhnn', Now) + '.csv';
    dlg.Options := dlg.Options + [ofOverwritePrompt];
    if not dlg.Execute then Exit;
    SavePatternCsv(dlg.FileName, FDraft);
    FFileName := dlg.FileName;
    HmiOpt.PatternDir := ExtractFilePath(dlg.FileName);
    Sim.Log(-1, True, Format('Pattern -> File: %d steps -> %s', [Length(FDraft), dlg.FileName]));
  finally
    dlg.Free;
  end;
end;

procedure TPatternForm.FromFileClick(Sender: TObject);
var
  dlg: TOpenDialog;
  p: TPattern;
  err: string;
begin
  dlg := TOpenDialog.Create(Self);
  try
    dlg.Filter := 'Paddle pattern (*.csv)|*.csv|All files|*.*';
    dlg.InitialDir := PatternFolder;
    if not dlg.Execute then Exit;
    if not LoadPatternCsv(dlg.FileName, p, err) then
    begin
      MessageDlg('File > Pattern', 'Cannot read ' + dlg.FileName + #13 + err, mtError, [mbOK], 0);
      Exit;
    end;
    FDraft := p;
    FFileName := dlg.FileName;
    HmiOpt.PatternDir := ExtractFilePath(dlg.FileName);
    FGrid.SelectRow(0);
    Sim.Log(-1, True, Format('File -> Pattern: %d steps from %s', [Length(p), dlg.FileName]));
    DraftChanged(nil);
  finally
    dlg.Free;
  end;
end;

procedure TPatternForm.ToPlcClick(Sender: TObject);
var
  i, k, bad: Integer;
  n: Integer;
begin
  if PlcMode and not Link.Online then
  begin
    MessageDlg('Pattern > PLC', 'The PLC is not online. Connect first.', mtWarning, [mbOK], 0);
    Exit;
  end;
  bad := 0;
  for i := 0 to High(FDraft) do
    for k := Sim.PaddleCount to MAX_PADDLES - 1 do
      if FDraft[i].P[k] then
        Inc(bad);
  if bad > 0 then
    if MessageDlg('Pattern > ' + TargetName, Format('%d cell(s) use paddles that are not installed ' +
      '(only %d installed). They will be ignored.'#13'Continue?', [bad, Sim.PaddleCount]),
      mtConfirmation, [mbYes, mbNo], 0) <> mrYes then
      Exit;
  if Sim.PatternActive then
    if MessageDlg('Pattern > ' + TargetName, 'Paddle Patterns are running. Apply the new pattern now?',
      mtConfirmation, [mbYes, mbNo], 0) <> mrYes then
      Exit;
  n := HmiPatternWrite(FDraft);
  if PlcMode then
    FStatus.Caption := Format('%d value(s) sent to the PLC - waiting for read back...', [n]);
  FLastKey := '';
end;

procedure TPatternForm.FromPlcClick(Sender: TObject);
begin
  if PlcMode and not Sim.CommOK then
    if MessageDlg('PLC > Pattern', 'The PLC values are not live (not connected). Copy anyway?',
      mtConfirmation, [mbYes, mbNo], 0) <> mrYes then
      Exit;
  LoadFromActive;
  Sim.Log(-1, True, Format('%s -> Pattern: %d steps', [TargetName, Length(FDraft)]));
end;

{ ---------------- editing ---------------- }

procedure TPatternForm.AddClick(Sender: TObject);
var
  n: Integer;
begin
  n := Length(FDraft);
  if n >= MAX_STEPS then
  begin
    MessageDlg('Add step', Format('A pattern has at most %d steps.', [MAX_STEPS]), mtInformation, [mbOK], 0);
    Exit;
  end;
  SetLength(FDraft, n + 1);
  FillChar(FDraft[n], SizeOf(TPatternStep), 0);
  FDraft[n].Duration := 5;
  FGrid.SelectRow(n);
  DraftChanged(nil);
end;

procedure TPatternForm.InsertClick(Sender: TObject);
var
  n, r, i: Integer;
begin
  n := Length(FDraft);
  if n >= MAX_STEPS then
  begin
    MessageDlg('Insert step', Format('A pattern has at most %d steps.', [MAX_STEPS]), mtInformation, [mbOK], 0);
    Exit;
  end;
  r := EnsureRange(FGrid.Row, 0, n);
  SetLength(FDraft, n + 1);
  for i := n downto r + 1 do
    FDraft[i] := FDraft[i - 1];
  FillChar(FDraft[r], SizeOf(TPatternStep), 0);
  FDraft[r].Duration := 5;
  FGrid.SelectRow(r);
  DraftChanged(nil);
end;

procedure TPatternForm.DeleteClick(Sender: TObject);
var
  r: Integer;
begin
  if Length(FDraft) = 0 then Exit;
  r := EnsureRange(FGrid.Row, 0, High(FDraft));
  Delete(FDraft, r, 1);
  FGrid.SelectRow(r);
  DraftChanged(nil);
end;

procedure TPatternForm.UpClick(Sender: TObject);
var
  r: Integer;
  t: TPatternStep;
begin
  r := FGrid.Row;
  if (r <= 0) or (r > High(FDraft)) then Exit;
  t := FDraft[r - 1];
  FDraft[r - 1] := FDraft[r];
  FDraft[r] := t;
  FGrid.SelectRow(r - 1);
  DraftChanged(nil);
end;

procedure TPatternForm.DownClick(Sender: TObject);
var
  r: Integer;
  t: TPatternStep;
begin
  r := FGrid.Row;
  if (r < 0) or (r >= High(FDraft)) then Exit;
  t := FDraft[r + 1];
  FDraft[r + 1] := FDraft[r];
  FDraft[r] := t;
  FGrid.SelectRow(r + 1);
  DraftChanged(nil);
end;

procedure TPatternForm.CopyClick(Sender: TObject);
var
  r: Integer;
begin
  if (Length(FDraft) = 0) or (Length(FDraft) >= MAX_STEPS) then Exit;
  r := EnsureRange(FGrid.Row, 0, High(FDraft));
  Insert(FDraft[r], FDraft, r + 1);
  FGrid.SelectRow(r + 1);
  DraftChanged(nil);
end;

procedure TPatternForm.ClearClick(Sender: TObject);
begin
  if Length(FDraft) = 0 then Exit;
  if MessageDlg('Clear', 'Remove all steps from the editor?', mtConfirmation, [mbYes, mbNo], 0) <> mrYes then Exit;
  SetLength(FDraft, 0);
  FGrid.SelectRow(0);
  DraftChanged(nil);
end;

procedure TPatternForm.DefaultClick(Sender: TObject);
begin
  FDraft := DefaultPattern(Sim.PaddleCount);
  FGrid.SelectRow(0);
  DraftChanged(nil);
end;

procedure TPatternForm.DelayChange(Sender: TObject);
begin
  if FUpdating then Exit;
  HmiSetDelay(TSimSpin(Sender).Tag, TSimSpin(Sender).Value);
end;

procedure TPatternForm.PaddlesChange(Sender: TObject);
var
  n: Integer;
begin
  if FUpdating then Exit;
  n := Round(FSpinPaddles.Value);
  HmiSetPaddleCount(n);
  if not PlcMode then
  begin
    HmiOpt.SimPaddleCount := n;
    try
      SaveConfig;
    except
    end;
  end;
  DraftChanged(nil);
end;

procedure TPatternForm.SysPaintBody(Sender: TObject);
var
  b: TBGRABitmap;
  y, x: Integer;
  s: string;
begin
  b := FSysCard.Bmp;
  y := FSysCard.BodyTop + 40;
  x := 16;
  PText(b, x, y, Format('%s: %d / %d steps, cycle %.1f s', [TargetName, Length(Sim.Pattern), MAX_STEPS,
    Sim.CycleTime]), 13, TB(clThemeTitle), True);
  Inc(y, 18);
  if Sim.PatternActive then
    s := Format('Running step %d  [%s]  %.1f / %.1f s', [Sim.PatStep + 1, Sim.StepText(Sim.PatStep),
      Sim.PatElapsed, Sim.Pattern[Sim.PatStep].Duration])
  else
    s := 'Paddle Patterns stopped';
  PText(b, x, y, s, 12, TB(clThemeText), Sim.PatternActive);
  Inc(y, 18);
  s := Format('Editor: %d steps, cycle %.1f s', [Length(FDraft), PatternTotal(FDraft)]);
  if FFileName <> '' then
    s := s + '   ' + ExtractFileName(FFileName);
  PText(b, x, y, s, 12, TB(clThemeMuted));
end;

procedure TPatternForm.TimelinePaint(Sender: TObject);
var
  bmp: TBGRABitmap;
  w, h, laneH, labelW, k, i, nP: Integer;
  span: Single;

  procedure Lane(const P: TPattern; Y0: Integer; const ATitle: string; ShowCursor: Boolean);
  var
    t, x1, x2, cx: Single;
    s, kk: Integer;
    c: TBGRAPixel;
  begin
    PText(bmp, 4, Y0 - 2, ATitle, 12, TB(clThemeTitle), True);
    for kk := 0 to nP - 1 do
    begin
      c := PaddleColor(kk);
      PText(bmp, labelW - 6, Y0 + 14 + kk * laneH - 3, 'P' + IntToStr(kk + 1), 10, BGRA(90, 100, 120), False,
        taRightJustify);
      bmp.DrawLineAntialias(labelW, Y0 + 14 + kk * laneH + laneH / 2, w - 4, Y0 + 14 + kk * laneH + laneH / 2,
        BGRA(225, 230, 238), 1);
    end;
    t := 0;
    for s := 0 to High(P) do
    begin
      x1 := labelW + t / span * (w - labelW - 6);
      x2 := labelW + (t + P[s].Duration) / span * (w - labelW - 6);
      if StepMask(P[s]) and ((1 shl nP) - 1) = 0 then
        DrawHatch(bmp, x1, Y0 + 14, x2, Y0 + 14 + nP * laneH, BGRA(215, 220, 228), 6)
      else
        for kk := 0 to nP - 1 do
          if P[s].P[kk] then
            bmp.FillRoundRectAntialias(x1 + 0.5, Y0 + 14 + kk * laneH + 1, x2 - 0.5, Y0 + 14 + (kk + 1) * laneH - 1,
              2, 2, PaddleColor(kk));
      bmp.DrawLineAntialias(x1, Y0 + 12, x1, Y0 + 16 + nP * laneH, BGRA(190, 198, 210), 1);
      if x2 - x1 > 18 then
        PText(bmp, Round((x1 + x2) / 2), Y0 + 1, IntToStr(s + 1), 9, BGRA(130, 140, 155), False, taCenter);
      if ShowCursor and Sim.PatternActive and (s = Sim.PatStep) then
      begin
        cx := x1 + Min(P[s].Duration, Sim.PatElapsed) / span * (w - labelW - 6);
        bmp.FillRectAntialias(x1, Y0 + 12, cx, Y0 + 16 + nP * laneH, BGRA(40, 170, 60, 40));
        bmp.DrawLineAntialias(cx, Y0 + 8, cx, Y0 + 18 + nP * laneH, BGRA(220, 30, 30), 2);
      end;
      t := t + P[s].Duration;
    end;
    if Length(P) = 0 then
      PText(bmp, labelW + 10, Y0 + 14, '(empty)', 12, BGRA(150, 160, 175), False);
  end;

begin
  w := FTimeline.Width;
  h := FTimeline.Height;
  if (w < 50) or (h < 30) then Exit;
  bmp := TBGRABitmap.Create(w, h, TB(clThemeCard));
  try
    nP := Sim.PaddleCount;
    labelW := 34;
    laneH := Max(4, Min(11, (h div 2 - 22) div Max(1, nP)));
    span := Max(1, Max(PatternTotal(FDraft), Sim.CycleTime));
    Lane(FDraft, 2, Format('Editor  %.1f s', [PatternTotal(FDraft)]), DraftIsActive);
    Lane(Sim.Pattern, h div 2 + 2, Format('%s  %.1f s', [TargetName, Sim.CycleTime]), True);
    { time ticks }
    k := 1;
    while span / k > 12 do
      k := k * 2 + Ord(k = 1) * 3;
    i := 0;
    while i <= span do
    begin
      PText(bmp, Round(labelW + i / span * (w - labelW - 6)), h - 13, IntToStr(i) + 's', 9, BGRA(150, 160, 175),
        False, taCenter);
      Inc(i, k);
    end;
    bmp.Draw(FTimeline.Canvas, 0, 0, True);
  finally
    bmp.Free;
  end;
end;

end.
