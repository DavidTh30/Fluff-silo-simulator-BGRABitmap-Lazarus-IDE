unit uWidgets;

{ FluffSilo HMI2 - BGRABitmap widget set (every control is painted with BGRABitmap)
  TSimButton  : push button with indicator lamp and/or vector icon
  TSimSegment : segmented selector (no drop-down popping over the UI)
  TSimPanel   : card with a title band (container for the other widgets)
  TSimLabel   : anti-aliased text
  TSimSpin    : numeric editor  [-] value [+]  (wheel, click+type, Enter / Esc)
  TSimToggle  : switch with caption
  Graphic controls are painted on a transparent bitmap and alpha-blended onto the
  parent, so rounded corners show the card / window behind them. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Controls, Graphics, ExtCtrls, Math, LCLType, BGRABitmap, BGRABitmapTypes, uDraw;

type

  { TSimButton }

  TSimButton = class(TGraphicControl)
  private
    FDown: Boolean;
    FHover: Boolean;
    FLamp: Boolean;
    FShowLamp: Boolean;
    FBaseColor: TColor;
    FLampColor: TColor;
    FSubText: string;
    FIcon: TIconKind;
    FCaptionSize: Integer;
    FCenter: Boolean;
    procedure SetLamp(V: Boolean);
    procedure SetSubText(const V: string);
    procedure SetBaseColor(V: TColor);
  protected
    procedure Paint; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseEnter; override;
    procedure MouseLeave; override;
    procedure SetEnabled(Value: Boolean); override;
    procedure TextChanged; override;
  public
    constructor Create(AOwner: TComponent); override;
    property Lamp: Boolean read FLamp write SetLamp;
    property ShowLamp: Boolean read FShowLamp write FShowLamp;
    property BaseColor: TColor read FBaseColor write SetBaseColor;
    property LampColor: TColor read FLampColor write FLampColor;
    property SubText: string read FSubText write SetSubText;
    property Icon: TIconKind read FIcon write FIcon;
    property CaptionSize: Integer read FCaptionSize write FCaptionSize;
    property CenterText: Boolean read FCenter write FCenter;
    property Caption;
    property OnClick;
  end;

  { TSimSegment }

  TSimSegment = class(TGraphicControl)
  private
    FItems: TStringList;
    FItemIndex: Integer;
    FHover: Integer;
    FAccentColor: TColor;
    FOnChange: TNotifyEvent;
    procedure SetItemIndex(V: Integer);
    procedure ItemsChanged(Sender: TObject);
    function ItemAt(X: Integer): Integer;
  protected
    procedure Paint; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseLeave; override;
    procedure SetEnabled(Value: Boolean); override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    property Items: TStringList read FItems;
    { setting ItemIndex in code does not fire OnChange }
    property ItemIndex: Integer read FItemIndex write SetItemIndex;
    property AccentColor: TColor read FAccentColor write FAccentColor;
    property OnChange: TNotifyEvent read FOnChange write FOnChange;
  end;

  { TSimPanel }

  TSimPanel = class(TCustomControl)
  private
    FTitle: string;
    FAccent: TColor;
    FTitleH: Integer;
    FOnPaintBody: TNotifyEvent;
    procedure SetTitle(const V: string);
  protected
    procedure Paint; override;
    procedure EraseBackground(DC: HDC); override;
  public
    Bmp: TBGRABitmap;   { valid during OnPaintBody: draw extra content into it }
    constructor Create(AOwner: TComponent); override;
    function BodyTop: Integer;
    property Title: string read FTitle write SetTitle;
    property Accent: TColor read FAccent write FAccent;
    property TitleHeight: Integer read FTitleH write FTitleH;
    property OnPaintBody: TNotifyEvent read FOnPaintBody write FOnPaintBody;
    property OnClick;
    property OnDragOver;
    property OnDragDrop;
    property OnMouseDown;
    property OnResize;
  end;

  { TSimLabel }

  TSimLabel = class(TGraphicControl)
  private
    FTextColor: TColor;
    FSize: Integer;
    FBold: Boolean;
    FAlign: TAlignment;
    procedure SetTextColor(V: TColor);
  protected
    procedure Paint; override;
    procedure TextChanged; override;
  public
    constructor Create(AOwner: TComponent); override;
    property TextColor: TColor read FTextColor write SetTextColor;
    property TextSize: Integer read FSize write FSize;
    property Bold: Boolean read FBold write FBold;
    property Alignment: TAlignment read FAlign write FAlign;
    property Caption;
    property OnClick;
  end;

  { TSimSpin }

  TSimSpin = class(TCustomControl)
  private
    FValue, FMin, FMax, FInc: Double;
    FDecimals: Integer;
    FSuffix: string;
    FEditing: Boolean;
    FBuf: string;
    FHoverPart, FDownPart: Integer;   { 0 = none, 1 = minus, 2 = text, 3 = plus }
    FRepeat: TTimer;
    FRepeatCount: Integer;
    FOnChange: TNotifyEvent;
    FHighlight: Boolean;
    function PartAt(X: Integer): Integer;
    procedure SetValue(V: Double);
    procedure Bump(Dir: Integer);
    procedure Commit;
    procedure RepeatTick(Sender: TObject);
    function FmtValue(V: Double): string;
  protected
    procedure Paint; override;
    procedure EraseBackground(DC: HDC); override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseLeave; override;
    function DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean; override;
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
    procedure UTF8KeyPress(var UTF8Key: TUTF8Char); override;
    procedure DoExit; override;
    procedure SetEnabled(Value: Boolean); override;
  public
    constructor Create(AOwner: TComponent); override;
    function Editing: Boolean;
    { setting Value in code does not fire OnChange }
    property Value: Double read FValue write SetValue;
    property MinValue: Double read FMin write FMin;
    property MaxValue: Double read FMax write FMax;
    property Increment: Double read FInc write FInc;
    property Decimals: Integer read FDecimals write FDecimals;
    property Suffix: string read FSuffix write FSuffix;
    property Highlight: Boolean read FHighlight write FHighlight;
    property OnChange: TNotifyEvent read FOnChange write FOnChange;
  end;

  { TSimToggle }

  TSimToggle = class(TGraphicControl)
  private
    FChecked: Boolean;
    FOnChange: TNotifyEvent;
    procedure SetChecked(V: Boolean);
  protected
    procedure Paint; override;
    procedure Click; override;
  public
    constructor Create(AOwner: TComponent); override;
    { setting Checked in code does not fire OnChange }
    property Checked: Boolean read FChecked write SetChecked;
    property OnChange: TNotifyEvent read FOnChange write FOnChange;
    property Caption;
  end;

{ quick constructors used by the forms }
function NewButton(AOwner: TComponent; AParent: TWinControl; X, Y, W, H: Integer; const ACaption: string;
  AColor: TColor; AIcon: TIconKind; AClick: TNotifyEvent): TSimButton;
function NewLabel(AOwner: TComponent; AParent: TWinControl; X, Y, W: Integer; const ACaption: string;
  ASize: Integer = 13; ABold: Boolean = False; AColor: TColor = clThemeText): TSimLabel;
function NewSpin(AOwner: TComponent; AParent: TWinControl; X, Y, W: Integer; AMin, AMax, AInc: Double;
  ADecimals: Integer; const ASuffix: string): TSimSpin;
function NewPanel(AOwner: TComponent; AParent: TWinControl; const ATitle: string; AAccent: TColor): TSimPanel;

implementation

{ draw the finished bitmap with alpha onto the parent background }
procedure BlendOnto(bmp: TBGRABitmap; ACanvas: TCanvas; AEnabled: Boolean);
begin
  if not AEnabled then
    bmp.ApplyGlobalOpacity(120);
  bmp.Draw(ACanvas, 0, 0, False);
end;

function NewButton(AOwner: TComponent; AParent: TWinControl; X, Y, W, H: Integer; const ACaption: string;
  AColor: TColor; AIcon: TIconKind; AClick: TNotifyEvent): TSimButton;
begin
  Result := TSimButton.Create(AOwner);
  Result.Parent := AParent;
  Result.SetBounds(X, Y, W, H);
  Result.Caption := ACaption;
  Result.BaseColor := AColor;
  Result.Icon := AIcon;
  Result.ShowLamp := False;
  Result.CaptionSize := 13;
  Result.OnClick := AClick;
end;

function NewLabel(AOwner: TComponent; AParent: TWinControl; X, Y, W: Integer; const ACaption: string;
  ASize: Integer; ABold: Boolean; AColor: TColor): TSimLabel;
begin
  Result := TSimLabel.Create(AOwner);
  Result.Parent := AParent;
  Result.SetBounds(X, Y, W, ASize + 9);
  Result.TextSize := ASize;
  Result.Bold := ABold;
  Result.TextColor := AColor;
  Result.Caption := ACaption;
end;

function NewSpin(AOwner: TComponent; AParent: TWinControl; X, Y, W: Integer; AMin, AMax, AInc: Double;
  ADecimals: Integer; const ASuffix: string): TSimSpin;
begin
  Result := TSimSpin.Create(AOwner);
  Result.Parent := AParent;
  Result.SetBounds(X, Y, W, 28);
  Result.MinValue := AMin;
  Result.MaxValue := AMax;
  Result.Increment := AInc;
  Result.Decimals := ADecimals;
  Result.Suffix := ASuffix;
end;

function NewPanel(AOwner: TComponent; AParent: TWinControl; const ATitle: string; AAccent: TColor): TSimPanel;
begin
  Result := TSimPanel.Create(AOwner);
  Result.Parent := AParent;
  Result.Title := ATitle;
  Result.Accent := AAccent;
end;

{ TSimButton }

constructor TSimButton.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  ControlStyle := ControlStyle - [csOpaque];   { transparent: the parent paints first }
  Width := 120;
  Height := 44;
  FBaseColor := $00E0E0E0;
  FLampColor := clLime;
  FShowLamp := True;
  FCaptionSize := 15;
end;

procedure TSimButton.SetLamp(V: Boolean);
begin
  if V = FLamp then Exit;
  FLamp := V;
  Invalidate;
end;

procedure TSimButton.SetSubText(const V: string);
begin
  if V = FSubText then Exit;
  FSubText := V;
  Invalidate;
end;

procedure TSimButton.SetBaseColor(V: TColor);
begin
  if V = FBaseColor then Exit;
  FBaseColor := V;
  Invalidate;
end;

procedure TSimButton.TextChanged;
begin
  inherited TextChanged;
  Invalidate;
end;

procedure TSimButton.SetEnabled(Value: Boolean);
begin
  if Value = Enabled then Exit;
  inherited SetEnabled(Value);
  Invalidate;
end;

procedure TSimButton.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  FDown := True;
  Invalidate;
  inherited MouseDown(Button, Shift, X, Y);
end;

procedure TSimButton.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  FDown := False;
  Invalidate;
  inherited MouseUp(Button, Shift, X, Y);
end;

procedure TSimButton.MouseEnter;
begin
  inherited MouseEnter;
  FHover := True;
  Invalidate;
end;

procedure TSimButton.MouseLeave;
begin
  inherited MouseLeave;
  FHover := False;
  FDown := False;
  Invalidate;
end;

procedure TSimButton.Paint;
var
  bmp: TBGRABitmap;
  c, tc, lc: TBGRAPixel;
  r, cx, cy, isz: Single;
  lum, tx, ty, tw: Integer;
begin
  if (Width < 4) or (Height < 4) then Exit;
  bmp := TBGRABitmap.Create(Width, Height, BGRAPixelTransparent);
  try
    c := TB(FBaseColor);
    if FDown then
      c := Darker(c, 0.8)
    else if FHover and Enabled then
      c := Lighter(c, 0.14);
    { shadow, face, gloss, border }
    bmp.FillRoundRectAntialias(1, 2, Width - 2, Height - 1, 8, 8, BGRA(0, 0, 0, 60));
    if FDown then
      bmp.FillRoundRectAntialias(1, 2, Width - 2, Height - 2, 8, 8, c)
    else
      bmp.FillRoundRectAntialias(1, 1, Width - 2, Height - 4, 8, 8, c);
    bmp.FillRoundRectAntialias(4, 3, Width - 5, Height div 2 - 2, 6, 6, BGRA(255, 255, 255, 50));
    bmp.RoundRectAntialias(1, 1, Width - 2, Height - 3, 8, 8, Darker(c, 0.55), 1.2);

    lum := (c.red * 30 + c.green * 59 + c.blue * 11) div 100;
    if lum < 150 then tc := BGRA(255, 255, 255) else tc := BGRA(20, 25, 35);

    tx := 10;
    if FShowLamp then
    begin
      r := Min(9, Height / 2 - 7);
      cx := 10 + r;
      cy := Height / 2;
      lc := TB(FLampColor);
      DrawLed(bmp, cx, cy, r, lc, FLamp);
      tx := Round(cx + r + 10);
    end;
    if FIcon <> ikNone then
    begin
      isz := Min(18, Height - 14);
      DrawIcon(bmp, FIcon, tx, (Height - 2 - isz) / 2, isz, tc);
      tx := tx + Round(isz) + 8;
    end;
    if FCenter or ((FIcon = ikNone) and not FShowLamp) then
    begin
      bmp.FontHeight := FCaptionSize;
      bmp.FontStyle := [fsBold];
      tw := bmp.TextSize(Caption).cx;
      tx := Max(tx, (Width - tw) div 2);
    end;
    if FSubText = '' then
    begin
      ty := (Height - FCaptionSize) div 2 - 2;
      PText(bmp, tx, ty, Caption, FCaptionSize, tc, True);
    end
    else
    begin
      PText(bmp, tx, Height div 2 - FCaptionSize - 2, Caption, FCaptionSize, tc, True);
      PText(bmp, tx, Height div 2 + 1, FSubText, 12, tc, False);
    end;
    BlendOnto(bmp, Canvas, Enabled);
  finally
    bmp.Free;
  end;
end;

{ TSimSegment }

constructor TSimSegment.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FItems := TStringList.Create;
  FItems.OnChange := @ItemsChanged;
  FItemIndex := -1;
  FHover := -1;
  ControlStyle := ControlStyle - [csOpaque];
  FAccentColor := clThemeAccent;
  Width := 200;
  Height := 28;
end;

destructor TSimSegment.Destroy;
begin
  FItems.Free;
  inherited Destroy;
end;

procedure TSimSegment.ItemsChanged(Sender: TObject);
begin
  if FItemIndex >= FItems.Count then
    FItemIndex := FItems.Count - 1;
  Invalidate;
end;

procedure TSimSegment.SetItemIndex(V: Integer);
begin
  V := EnsureRange(V, -1, FItems.Count - 1);
  if V = FItemIndex then Exit;
  FItemIndex := V;
  Invalidate;
end;

procedure TSimSegment.SetEnabled(Value: Boolean);
begin
  if Value = Enabled then Exit;
  inherited SetEnabled(Value);
  Invalidate;
end;

function TSimSegment.ItemAt(X: Integer): Integer;
begin
  if (FItems.Count = 0) or (X < 0) or (X >= Width) then
    Exit(-1);
  Result := Min(FItems.Count - 1, X * FItems.Count div Max(1, Width));
end;

procedure TSimSegment.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  i: Integer;
begin
  inherited MouseDown(Button, Shift, X, Y);
  if (Button <> mbLeft) or not Enabled then Exit;
  i := ItemAt(X);
  if (i >= 0) and (i <> FItemIndex) then
  begin
    FItemIndex := i;
    Invalidate;
    if Assigned(FOnChange) then
      FOnChange(Self);
  end;
end;

procedure TSimSegment.MouseMove(Shift: TShiftState; X, Y: Integer);
var
  i: Integer;
begin
  inherited MouseMove(Shift, X, Y);
  i := ItemAt(X);
  if i <> FHover then
  begin
    FHover := i;
    Invalidate;
  end;
end;

procedure TSimSegment.MouseLeave;
begin
  inherited MouseLeave;
  if FHover <> -1 then
  begin
    FHover := -1;
    Invalidate;
  end;
end;

procedure TSimSegment.Paint;
var
  bmp: TBGRABitmap;
  n, i: Integer;
  segW, x1, x2: Single;
  acc, tc: TBGRAPixel;
begin
  n := FItems.Count;
  if (Width < 8) or (Height < 8) or (n = 0) then Exit;
  bmp := TBGRABitmap.Create(Width, Height, BGRAPixelTransparent);
  try
    acc := TB(FAccentColor);
    { track }
    bmp.FillRoundRectAntialias(0.5, 0.5, Width - 1.5, Height - 1.5, Height / 2, Height / 2, BGRA(226, 230, 236));
    bmp.RoundRectAntialias(0.5, 0.5, Width - 1.5, Height - 1.5, Height / 2, Height / 2, BGRA(150, 158, 170), 1);
    segW := (Width - 4) / n;
    for i := 0 to n - 1 do
    begin
      x1 := 2 + i * segW;
      x2 := x1 + segW;
      if i = FItemIndex then
      begin
        { selected: raised accent pill }
        bmp.FillRoundRectAntialias(x1, 3, x2 - 1, Height - 3, (Height - 6) / 2, (Height - 6) / 2,
          BGRA(0, 0, 0, 50));
        bmp.FillRoundRectAntialias(x1, 2, x2 - 1, Height - 4, (Height - 6) / 2, (Height - 6) / 2, acc);
        bmp.FillRoundRectAntialias(x1 + 3, 3, x2 - 4, Height / 2 - 1, (Height - 10) / 2, (Height - 10) / 2,
          BGRA(255, 255, 255, 45));
        tc := BGRA(255, 255, 255);
      end
      else
      begin
        if (i = FHover) and Enabled then
          bmp.FillRoundRectAntialias(x1, 2, x2 - 1, Height - 4, (Height - 6) / 2, (Height - 6) / 2,
            BGRA(255, 255, 255, 170));
        if i > 0 then
          if (i <> FItemIndex + 1) and (i <> FHover) and (i - 1 <> FHover) then
            bmp.DrawLineAntialias(x1, 7, x1, Height - 8, BGRA(170, 176, 186), 1);
        tc := BGRA(45, 55, 70);
      end;
      PText(bmp, Round((x1 + x2) / 2), (Height - 17) div 2, FItems[i], 13, tc, i = FItemIndex, taCenter);
    end;
    BlendOnto(bmp, Canvas, Enabled);
  finally
    bmp.Free;
  end;
end;

{ TSimPanel }

constructor TSimPanel.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  ControlStyle := ControlStyle + [csAcceptsControls, csOpaque];
  DoubleBuffered := True;
  FAccent := clThemeAccent;
  FTitleH := 26;
  Width := 300;
  Height := 120;
end;

function TSimPanel.BodyTop: Integer;
begin
  if FTitle = '' then Result := 8 else Result := FTitleH + 6;
end;

procedure TSimPanel.SetTitle(const V: string);
begin
  if V = FTitle then Exit;
  FTitle := V;
  Invalidate;
end;

procedure TSimPanel.EraseBackground(DC: HDC);
begin
  { everything is painted in Paint (no flicker) }
end;

procedure TSimPanel.Paint;
var
  bg: TColor;
begin
  if (Width < 4) or (Height < 4) then Exit;
  if Parent <> nil then bg := Parent.Color else bg := clThemeBg;
  if bg = clDefault then bg := clThemeBg;
  Bmp := TBGRABitmap.Create(Width, Height, TB(bg));
  try
    DrawCard(Bmp, 1, 1, Width - 3, Height - 4, FTitle, TB(FAccent), FTitleH);
    if Assigned(FOnPaintBody) then
      FOnPaintBody(Self);
    Bmp.Draw(Canvas, 0, 0, True);
  finally
    FreeAndNil(Bmp);
  end;
end;

{ TSimLabel }

constructor TSimLabel.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  ControlStyle := ControlStyle - [csOpaque];
  FTextColor := clThemeText;
  FSize := 13;
  FAlign := taLeftJustify;
  Width := 120;
  Height := 22;
end;

procedure TSimLabel.SetTextColor(V: TColor);
begin
  if V = FTextColor then Exit;
  FTextColor := V;
  Invalidate;
end;

procedure TSimLabel.TextChanged;
begin
  inherited TextChanged;
  Invalidate;
end;

procedure TSimLabel.Paint;
var
  bmp: TBGRABitmap;
  x: Integer;
begin
  if (Width < 2) or (Height < 2) or (Caption = '') then Exit;
  bmp := TBGRABitmap.Create(Width, Height, BGRAPixelTransparent);
  try
    case FAlign of
      taCenter: x := Width div 2;
      taRightJustify: x := Width - 2;
    else
      x := 0;
    end;
    PText(bmp, x, (Height - FSize) div 2 - 2, Caption, FSize, TB(FTextColor), FBold, FAlign);
    BlendOnto(bmp, Canvas, Enabled);
  finally
    bmp.Free;
  end;
end;

{ TSimSpin }

constructor TSimSpin.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  ControlStyle := ControlStyle + [csOpaque];
  DoubleBuffered := True;
  TabStop := True;
  FMin := 0;
  FMax := 100;
  FInc := 1;
  FDecimals := 1;
  Width := 130;
  Height := 28;
  FRepeat := TTimer.Create(Self);
  FRepeat.Enabled := False;
  FRepeat.OnTimer := @RepeatTick;
end;

function TSimSpin.Editing: Boolean;
begin
  Result := FEditing;
end;

function TSimSpin.FmtValue(V: Double): string;
begin
  if FDecimals <= 0 then
    Result := IntToStr(Round(V))
  else
    Result := FloatToStrF(V, ffFixed, 15, FDecimals);
end;

procedure TSimSpin.SetValue(V: Double);
begin
  V := EnsureRange(V, FMin, FMax);
  if (V = FValue) or FEditing then Exit;
  FValue := V;
  Invalidate;
end;

procedure TSimSpin.SetEnabled(Value: Boolean);
begin
  if Value = Enabled then Exit;
  inherited SetEnabled(Value);
  Invalidate;
end;

function TSimSpin.PartAt(X: Integer): Integer;
var
  bw: Integer;
begin
  bw := Height;
  if X < bw then Result := 1
  else if X >= Width - bw then Result := 3
  else Result := 2;
end;

procedure TSimSpin.Bump(Dir: Integer);
var
  v: Double;
begin
  v := EnsureRange(Round((FValue + Dir * FInc) / FInc) * FInc, FMin, FMax);
  if Abs(v - FValue) < 1e-9 then Exit;
  FValue := v;
  Invalidate;
  if Assigned(FOnChange) then
    FOnChange(Self);
end;

procedure TSimSpin.Commit;
var
  v: Double;
  fs: TFormatSettings;
begin
  if not FEditing then Exit;
  FEditing := False;
  fs := DefaultFormatSettings;
  fs.DecimalSeparator := '.';
  if TryStrToFloat(StringReplace(FBuf, ',', '.', []), v, fs) then
  begin
    v := EnsureRange(v, FMin, FMax);
    if Abs(v - FValue) > 1e-9 then
    begin
      FValue := v;
      if Assigned(FOnChange) then
        FOnChange(Self);
    end;
  end;
  Invalidate;
end;

procedure TSimSpin.RepeatTick(Sender: TObject);
begin
  Inc(FRepeatCount);
  FRepeat.Interval := 70;
  if FDownPart = 1 then Bump(-1)
  else if FDownPart = 3 then Bump(1);
end;

procedure TSimSpin.EraseBackground(DC: HDC);
begin
end;

procedure TSimSpin.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseDown(Button, Shift, X, Y);
  if (Button <> mbLeft) or not Enabled then Exit;
  SetFocus;
  FDownPart := PartAt(X);
  case FDownPart of
    1, 3:
      begin
        Commit;
        if FDownPart = 1 then Bump(-1) else Bump(1);
        FRepeatCount := 0;
        FRepeat.Interval := 400;
        FRepeat.Enabled := True;
      end;
    2:
      if not FEditing then
      begin
        FEditing := True;
        FBuf := FmtValue(FValue);
      end;
  end;
  Invalidate;
end;

procedure TSimSpin.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseUp(Button, Shift, X, Y);
  FRepeat.Enabled := False;
  FDownPart := 0;
  Invalidate;
end;

procedure TSimSpin.MouseMove(Shift: TShiftState; X, Y: Integer);
var
  p: Integer;
begin
  inherited MouseMove(Shift, X, Y);
  p := PartAt(X);
  if p <> FHoverPart then
  begin
    FHoverPart := p;
    Invalidate;
  end;
end;

procedure TSimSpin.MouseLeave;
begin
  inherited MouseLeave;
  FHoverPart := 0;
  FRepeat.Enabled := False;
  FDownPart := 0;
  Invalidate;
end;

function TSimSpin.DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean;
begin
  Result := True;
  if not Enabled then Exit;
  Commit;
  if WheelDelta > 0 then Bump(1) else Bump(-1);
end;

procedure TSimSpin.KeyDown(var Key: Word; Shift: TShiftState);
begin
  case Key of
    VK_RETURN:
      begin
        if FEditing then Commit;
        Key := 0;
      end;
    VK_ESCAPE:
      if FEditing then
      begin
        FEditing := False;
        Invalidate;
        Key := 0;
      end;
    VK_UP, VK_ADD:
      begin
        Commit;
        Bump(1);
        Key := 0;
      end;
    VK_DOWN, VK_SUBTRACT:
      begin
        Commit;
        Bump(-1);
        Key := 0;
      end;
    VK_BACK:
      begin
        if not FEditing then
        begin
          FEditing := True;
          FBuf := FmtValue(FValue);
        end;
        if FBuf <> '' then
          Delete(FBuf, Length(FBuf), 1);
        Invalidate;
        Key := 0;
      end;
  end;
  inherited KeyDown(Key, Shift);
end;

procedure TSimSpin.UTF8KeyPress(var UTF8Key: TUTF8Char);
begin
  if (Length(UTF8Key) = 1) and (UTF8Key[1] in ['0'..'9', '.', ',', '-']) then
  begin
    if not FEditing then
    begin
      FEditing := True;
      FBuf := '';
    end;
    if Length(FBuf) < 12 then
      FBuf := FBuf + UTF8Key;
    Invalidate;
    UTF8Key := '';
  end;
  inherited UTF8KeyPress(UTF8Key);
end;

procedure TSimSpin.DoExit;
begin
  Commit;
  inherited DoExit;
end;

procedure TSimSpin.Paint;
var
  bmp: TBGRABitmap;
  bg: TColor;
  bw, cy, tw: Integer;
  face, fr, tc: TBGRAPixel;
  s: string;

  procedure Btn(x1, x2: Integer; Part: Integer; Plus: Boolean);
  var
    c: TBGRAPixel;
    mx: Single;
  begin
    if (FDownPart = Part) then c := BGRA(190, 205, 225)
    else if (FHoverPart = Part) and Enabled then c := BGRA(222, 232, 246)
    else c := BGRA(238, 242, 248);
    bmp.FillRoundRectAntialias(x1 + 2, 2, x2 - 2, Height - 3, 5, 5, c);
    mx := (x1 + x2) / 2;
    bmp.DrawLineAntialias(mx - 5, cy, mx + 5, cy, BGRA(50, 70, 100), 2);
    if Plus then
      bmp.DrawLineAntialias(mx, cy - 5, mx, cy + 5, BGRA(50, 70, 100), 2);
  end;

begin
  if (Width < 10) or (Height < 10) then Exit;
  if Parent <> nil then bg := Parent.Color else bg := clThemeCard;
  if (bg = clDefault) or (Parent is TSimPanel) then bg := clThemeCard;
  bmp := TBGRABitmap.Create(Width, Height, TB(bg));
  try
    bw := Height;
    cy := Height div 2 - 1;
    if FHighlight then face := BGRA(255, 248, 225) else face := BGRA(255, 255, 255);
    if Focused then fr := TB(clThemeAccent) else fr := BGRA(160, 170, 185);
    bmp.FillRoundRectAntialias(0.5, 0.5, Width - 1.5, Height - 1.5, 6, 6, face);
    Btn(0, bw, 1, False);
    Btn(Width - bw, Width, 3, True);
    bmp.RoundRectAntialias(0.5, 0.5, Width - 1.5, Height - 1.5, 6, 6, fr, 1.2);
    if FEditing then
    begin
      s := FBuf;
      tc := BGRA(0, 60, 160);
    end
    else
    begin
      s := FmtValue(FValue) + FSuffix;
      tc := BGRA(20, 25, 35);
    end;
    PText(bmp, Width div 2, (Height - 15) div 2 - 1, s, 15, tc, True, taCenter);
    if FEditing then
    begin
      bmp.FontHeight := 15;
      bmp.FontStyle := [fsBold];
      tw := bmp.TextSize(s).cx;
      bmp.DrawLineAntialias(Width div 2 + tw / 2 + 2, 6, Width div 2 + tw / 2 + 2, Height - 7,
        BGRA(0, 60, 160), 1.5);
    end;
    if not Enabled then
      bmp.FillRectAntialias(0, 0, Width, Height, BGRA(255, 255, 255, 110));
    bmp.Draw(Canvas, 0, 0, True);
  finally
    bmp.Free;
  end;
end;

{ TSimToggle }

constructor TSimToggle.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  ControlStyle := ControlStyle - [csOpaque];
  Width := 150;
  Height := 24;
end;

procedure TSimToggle.SetChecked(V: Boolean);
begin
  if V = FChecked then Exit;
  FChecked := V;
  Invalidate;
end;

procedure TSimToggle.Click;
begin
  FChecked := not FChecked;
  Invalidate;
  if Assigned(FOnChange) then
    FOnChange(Self);
  inherited Click;
end;

procedure TSimToggle.Paint;
var
  bmp: TBGRABitmap;
  h, w: Single;
  kx: Single;
begin
  if (Width < 10) or (Height < 10) then Exit;
  bmp := TBGRABitmap.Create(Width, Height, BGRAPixelTransparent);
  try
    h := Min(Height - 4, 20);
    w := h * 1.8;
    if FChecked then
    begin
      bmp.FillRoundRectAntialias(1, (Height - h) / 2, 1 + w, (Height + h) / 2, h / 2, h / 2, TB(clThemeAccent));
      kx := 1 + w - h / 2;
    end
    else
    begin
      bmp.FillRoundRectAntialias(1, (Height - h) / 2, 1 + w, (Height + h) / 2, h / 2, h / 2, BGRA(185, 192, 204));
      kx := 1 + h / 2;
    end;
    bmp.FillEllipseAntialias(kx, Height / 2, h / 2 - 2, h / 2 - 2, BGRA(255, 255, 255));
    PText(bmp, Round(w) + 9, (Height - 13) div 2 - 2, Caption, 13, TB(clThemeText), False);
    BlendOnto(bmp, Canvas, Enabled);
  finally
    bmp.Free;
  end;
end;

end.
