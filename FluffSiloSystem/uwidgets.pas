unit uWidgets;

{ TSimButton: push button with indicator lamp, painted with BGRABitmap }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Controls, Graphics, Math, BGRABitmap, BGRABitmapTypes, uDraw;

type

  { TSimButton }

  TSimButton = class(TGraphicControl)
  private
    FDown: Boolean;
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
  public
    constructor Create(AOwner: TComponent); override;
    property Lamp: Boolean read FLamp write SetLamp;
    property BaseColor: TColor read FBaseColor write FBaseColor;
    property LampColor: TColor read FLampColor write FLampColor;
    property SubText: string read FSubText write SetSubText;
    property Caption;
    property OnClick;
  end;

implementation

constructor TSimButton.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
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

procedure TSimButton.Paint;
var
  bmp: TBGRABitmap;
  c, tc, lc: TBGRAPixel;
  r, cx, cy: Single;
  lum, tx, ty: Integer;
begin
  if (Width < 4) or (Height < 4) then Exit;
  bmp := TBGRABitmap.Create(Width, Height, ColorToBGRA(ColorToRGB(Color)));
  try
    c := ColorToBGRA(ColorToRGB(FBaseColor));
    if FDown then c := Darker(c, 0.8);
    bmp.FillRoundRectAntialias(1, 2, Width - 2, Height - 1, 8, 8, Darker(c, 0.6));
    if FDown then
      bmp.FillRoundRectAntialias(1, 2, Width - 2, Height - 2, 8, 8, c)
    else
      bmp.FillRoundRectAntialias(1, 1, Width - 2, Height - 4, 8, 8, c);
    bmp.FillRoundRectAntialias(4, 3, Width - 5, Height div 2 - 2, 6, 6, BGRA(255, 255, 255, 50));
    bmp.RoundRectAntialias(1, 1, Width - 2, Height - 2, 8, 8, BGRA(40, 40, 40), 1.2);

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
    bmp.Draw(Canvas, 0, 0, True);
  finally
    bmp.Free;
  end;
end;

end.
