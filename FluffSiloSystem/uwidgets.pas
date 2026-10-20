unit uWidgets;

{ BGRABitmap widgets
  TSimButton  : push button with indicator lamp
  TSimSegment : segmented selector (replaces a drop-down list: nothing pops over the UI)
  Both are painted on a transparent bitmap and alpha-blended onto the parent,
  so the rounded corners show the parent background (no black frame). }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Controls, Graphics, Math, BGRABitmap, BGRABitmapTypes, uDraw;

type

  { TSimButton }

  TSimButton = class(TGraphicControl)
  private
    FDown: Boolean;
    FHover: Boolean;
    FLamp: Boolean;
    FBaseColor: TColor;
    FLampColor: TColor;
    FSubText: string;
    procedure SetLamp(V: Boolean);
    procedure SetSubText(const V: string);
  protected
    procedure Paint; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseEnter; override;
    procedure MouseLeave; override;
    procedure SetEnabled(Value: Boolean); override;
  public
    constructor Create(AOwner: TComponent); override;
    property Lamp: Boolean read FLamp write SetLamp;
    property BaseColor: TColor read FBaseColor write FBaseColor;
    property LampColor: TColor read FLampColor write FLampColor;
    property SubText: string read FSubText write SetSubText;
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

implementation

{ draw the finished bitmap with alpha onto the parent background }
procedure BlendOnto(bmp: TBGRABitmap; ACanvas: TCanvas; AEnabled: Boolean);
begin
  if not AEnabled then
    bmp.ApplyGlobalOpacity(120);
  bmp.Draw(ACanvas, 0, 0, False);
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
  r, cx, cy: Single;
  lum, tx, ty: Integer;
begin
  if (Width < 4) or (Height < 4) then Exit;
  bmp := TBGRABitmap.Create(Width, Height, BGRAPixelTransparent);
  try
    c := ColorToBGRA(ColorToRGB(FBaseColor));
    if FDown then
      c := Darker(c, 0.8)
    else if FHover and Enabled then
      c := Lighter(c, 0.12);
    { shadow, face, gloss, border }
    bmp.FillRoundRectAntialias(1, 2, Width - 2, Height - 1, 8, 8, BGRA(0, 0, 0, 60));
    if FDown then
      bmp.FillRoundRectAntialias(1, 2, Width - 2, Height - 2, 8, 8, c)
    else
      bmp.FillRoundRectAntialias(1, 1, Width - 2, Height - 4, 8, 8, c);
    bmp.FillRoundRectAntialias(4, 3, Width - 5, Height div 2 - 2, 6, 6, BGRA(255, 255, 255, 50));
    bmp.RoundRectAntialias(1, 1, Width - 2, Height - 3, 8, 8, Darker(c, 0.55), 1.2);

    r := Min(9, Height / 2 - 7);
    cx := 10 + r;
    cy := Height / 2;
    lc := ColorToBGRA(ColorToRGB(FLampColor));
    DrawLed(bmp, cx, cy, r, lc, FLamp);

    lum := (c.red * 30 + c.green * 59 + c.blue * 11) div 100;
    if lum < 140 then tc := BGRA(255, 255, 255) else tc := BGRA(20, 20, 20);
    tx := Round(cx + r + 10);
    if FSubText = '' then
    begin
      ty := (Height - 16) div 2 - 1;
      PText(bmp, tx, ty, Caption, 15, tc, True);
    end
    else
    begin
      PText(bmp, tx, Height div 2 - 17, Caption, 15, tc, True);
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
  FAccentColor := $00C08040;
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
    acc := ColorToBGRA(ColorToRGB(FAccentColor));
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

end.
