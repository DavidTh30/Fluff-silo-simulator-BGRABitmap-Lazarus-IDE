unit uDraw;

{ Shared BGRABitmap drawing helpers.
  All V* routines work in "design" coordinates transformed by SetView. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, Graphics, BGRABitmap, BGRABitmapTypes, uSim;

var
  VS: Single = 1;
  VOX: Single = 0;
  VOY: Single = 0;

procedure SetView(AScale, AOX, AOY: Single);
function VX(x: Single): Single;
function VY(y: Single): Single;
function VL(v: Single): Single;

function StateColor(V: TDevVisual): TBGRAPixel;
function IsManualVis(V: TDevVisual): Boolean;
function StateText(V: TDevVisual): string;
function Darker(c: TBGRAPixel; f: Single): TBGRAPixel;
function Lighter(c: TBGRAPixel; f: Single): TBGRAPixel;
function WithAlpha(c: TBGRAPixel; a: Byte): TBGRAPixel;

procedure VRect(bmp: TBGRABitmap; x1, y1, x2, y2: Single; c: TBGRAPixel);
procedure VFrame(bmp: TBGRABitmap; x1, y1, x2, y2: Single; c: TBGRAPixel; w: Single);
procedure VRound(bmp: TBGRABitmap; x1, y1, x2, y2, r: Single; c: TBGRAPixel);
procedure VRoundFrame(bmp: TBGRABitmap; x1, y1, x2, y2, r: Single; c: TBGRAPixel; w: Single);
procedure VLine(bmp: TBGRABitmap; x1, y1, x2, y2: Single; c: TBGRAPixel; w: Single);
procedure VCircle(bmp: TBGRABitmap; cx, cy, r: Single; c: TBGRAPixel);
procedure VRing(bmp: TBGRABitmap; cx, cy, r: Single; c: TBGRAPixel; w: Single);
procedure VPoly(bmp: TBGRABitmap; const pts: array of TPointF; c: TBGRAPixel);
procedure VPolyLine(bmp: TBGRABitmap; const pts: array of TPointF; c: TBGRAPixel; w: Single);
procedure VText(bmp: TBGRABitmap; x, y: Single; const s: string; size: Single;
  c: TBGRAPixel; bold: Boolean = False; align: TAlignment = taLeftJustify);
procedure PText(bmp: TBGRABitmap; x, y: Integer; const s: string; size: Integer;
  c: TBGRAPixel; bold: Boolean = False; align: TAlignment = taLeftJustify);

procedure DrawStripe(bmp: TBGRABitmap; x1, y1, x2, y2: Single);
procedure DrawMotor(bmp: TBGRABitmap; x, y, w, h: Single; V: TDevVisual);
procedure DrawGearMotor(bmp: TBGRABitmap; x, y, w, h: Single; V: TDevVisual);
procedure DrawBlower(bmp: TBGRABitmap; cx, cy, r: Single; V: TDevVisual; Phase: Single);
procedure DrawLed(bmp: TBGRABitmap; cx, cy, r: Single; OnColor: TBGRAPixel; IsOn: Boolean);

function CL_GREEN: TBGRAPixel;
function CL_LGRAY: TBGRAPixel;
function CL_DGRAY: TBGRAPixel;
function CL_RED: TBGRAPixel;
function CL_ORANGE: TBGRAPixel;

implementation

function CL_GREEN: TBGRAPixel;
begin
  Result := BGRA(40, 185, 70);
end;

function CL_LGRAY: TBGRAPixel;
begin
  Result := BGRA(205, 205, 205);
end;

function CL_DGRAY: TBGRAPixel;
begin
  Result := BGRA(85, 85, 85);
end;

function CL_RED: TBGRAPixel;
begin
  Result := BGRA(225, 40, 40);
end;

function CL_ORANGE: TBGRAPixel;
begin
  Result := BGRA(255, 140, 0);
end;

procedure SetView(AScale, AOX, AOY: Single);
begin
  VS := AScale;
  VOX := AOX;
  VOY := AOY;
end;

function VX(x: Single): Single;
begin
  Result := VOX + x * VS;
end;

function VY(y: Single): Single;
begin
  Result := VOY + y * VS;
end;

function VL(v: Single): Single;
begin
  Result := v * VS;
end;

function StateColor(V: TDevVisual): TBGRAPixel;
begin
  case V of
    dvAutoRun, dvManualRun: Result := CL_GREEN;
    dvDisabled: Result := CL_DGRAY;
    dvFault: Result := CL_RED;
  else
    Result := CL_LGRAY;
  end;
end;

function IsManualVis(V: TDevVisual): Boolean;
begin
  Result := V in [dvManualRun, dvManualStop];
end;

function StateText(V: TDevVisual): string;
begin
  case V of
    dvAutoRun: Result := 'AUTO RUN';
    dvManualRun: Result := 'MANUAL RUN';
    dvManualStop: Result := 'MANUAL STOP';
    dvDisabled: Result := 'DISABLED';
    dvFault: Result := 'FAULT';
  else
    Result := 'STOP';
  end;
end;

function Darker(c: TBGRAPixel; f: Single): TBGRAPixel;
begin
  Result := BGRA(Round(c.red * f), Round(c.green * f), Round(c.blue * f), c.alpha);
end;

function Lighter(c: TBGRAPixel; f: Single): TBGRAPixel;
begin
  Result := BGRA(Round(c.red + (255 - c.red) * f), Round(c.green + (255 - c.green) * f),
    Round(c.blue + (255 - c.blue) * f), c.alpha);
end;

function WithAlpha(c: TBGRAPixel; a: Byte): TBGRAPixel;
begin
  Result := c;
  Result.alpha := a;
end;

procedure VRect(bmp: TBGRABitmap; x1, y1, x2, y2: Single; c: TBGRAPixel);
begin
  bmp.FillRectAntialias(VX(x1), VY(y1), VX(x2), VY(y2), c);
end;

procedure VFrame(bmp: TBGRABitmap; x1, y1, x2, y2: Single; c: TBGRAPixel; w: Single);
begin
  bmp.RectangleAntialias(VX(x1), VY(y1), VX(x2), VY(y2), c, Max(1, VL(w)));
end;

procedure VRound(bmp: TBGRABitmap; x1, y1, x2, y2, r: Single; c: TBGRAPixel);
begin
  bmp.FillRoundRectAntialias(VX(x1), VY(y1), VX(x2), VY(y2), VL(r), VL(r), c);
end;

procedure VRoundFrame(bmp: TBGRABitmap; x1, y1, x2, y2, r: Single; c: TBGRAPixel; w: Single);
begin
  bmp.RoundRectAntialias(VX(x1), VY(y1), VX(x2), VY(y2), VL(r), VL(r), c, Max(1, VL(w)));
end;

procedure VLine(bmp: TBGRABitmap; x1, y1, x2, y2: Single; c: TBGRAPixel; w: Single);
begin
  bmp.DrawLineAntialias(VX(x1), VY(y1), VX(x2), VY(y2), c, Max(1, VL(w)));
end;

procedure VCircle(bmp: TBGRABitmap; cx, cy, r: Single; c: TBGRAPixel);
begin
  bmp.FillEllipseAntialias(VX(cx), VY(cy), VL(r), VL(r), c);
end;

procedure VRing(bmp: TBGRABitmap; cx, cy, r: Single; c: TBGRAPixel; w: Single);
begin
  bmp.EllipseAntialias(VX(cx), VY(cy), VL(r), VL(r), c, Max(1, VL(w)));
end;

procedure VPoly(bmp: TBGRABitmap; const pts: array of TPointF; c: TBGRAPixel);
var
  a: array of TPointF;
  i: Integer;
begin
  SetLength(a, Length(pts));
  for i := 0 to High(pts) do
    a[i] := PointF(VX(pts[i].x), VY(pts[i].y));
  bmp.FillPolyAntialias(a, c);
end;

procedure VPolyLine(bmp: TBGRABitmap; const pts: array of TPointF; c: TBGRAPixel; w: Single);
var
  a: array of TPointF;
  i: Integer;
begin
  SetLength(a, Length(pts));
  for i := 0 to High(pts) do
    a[i] := PointF(VX(pts[i].x), VY(pts[i].y));
  bmp.DrawPolyLineAntialias(a, c, Max(1, VL(w)));
end;

procedure PText(bmp: TBGRABitmap; x, y: Integer; const s: string; size: Integer;
  c: TBGRAPixel; bold: Boolean; align: TAlignment);
var
  w: Integer;
begin
  bmp.FontName := 'Segoe UI';
  bmp.FontHeight := Max(6, size);
  if bold then bmp.FontStyle := [fsBold] else bmp.FontStyle := [];
  w := bmp.TextSize(s).cx;
  case align of
    taCenter: x := x - w div 2;
    taRightJustify: x := x - w;
  end;
  bmp.TextOut(x, y, s, c);
end;

procedure VText(bmp: TBGRABitmap; x, y: Single; const s: string; size: Single;
  c: TBGRAPixel; bold: Boolean; align: TAlignment);
begin
  PText(bmp, Round(VX(x)), Round(VY(y)), s, Round(VL(size)), c, bold, align);
end;

procedure DrawStripe(bmp: TBGRABitmap; x1, y1, x2, y2: Single);
var
  x: Single;
begin
  VRect(bmp, x1, y1, x2, y2, CL_ORANGE);
  x := x1 + 4;
  while x < x2 - 2 do
  begin
    VLine(bmp, x, y2, Min(x + (y2 - y1), x2), y1, BGRA(255, 200, 80), 1.5);
    x := x + 9;
  end;
  VFrame(bmp, x1, y1, x2, y2, BGRA(150, 70, 0), 1);
end;

procedure DrawLed(bmp: TBGRABitmap; cx, cy, r: Single; OnColor: TBGRAPixel; IsOn: Boolean);
begin
  if IsOn then
  begin
    bmp.FillEllipseAntialias(cx, cy, r + 3, r + 3, WithAlpha(OnColor, 70));
    bmp.FillEllipseAntialias(cx, cy, r, r, OnColor);
    bmp.FillEllipseAntialias(cx - r * 0.3, cy - r * 0.3, r * 0.35, r * 0.35, BGRA(255, 255, 255, 170));
  end
  else
    bmp.FillEllipseAntialias(cx, cy, r, r, BGRA(70, 70, 70));
  bmp.EllipseAntialias(cx, cy, r, r, BGRA(20, 20, 20), 1);
end;

{ motor with the shaft on the right side (towards the silo) }
procedure DrawMotor(bmp: TBGRABitmap; x, y, w, h: Single; V: TDevVisual);
var
  c, cd, cl: TBGRAPixel;
  i: Integer;
  fx, bx1, bx2: Single;
begin
  c := StateColor(V);
  cd := Darker(c, 0.6);
  cl := Lighter(c, 0.45);
  bx1 := x + w * 0.16;
  bx2 := x + w * 0.88;
  { feet }
  VRect(bmp, bx1 + w * 0.08, y + h * 0.82, bx2 - w * 0.08, y + h, cd);
  { fan cover }
  VRound(bmp, x, y + h * 0.12, bx1 + 2, y + h * 0.80, 4, cd);
  { body }
  VRound(bmp, bx1, y, bx2, y + h * 0.88, 6, c);
  VRect(bmp, bx1 + 3, y + h * 0.1, bx2 - 3, y + h * 0.26, cl);
  for i := 1 to 7 do
  begin
    fx := bx1 + (bx2 - bx1) * i / 8;
    VLine(bmp, fx, y + h * 0.06, fx, y + h * 0.82, WithAlpha(cd, 160), 1.2);
  end;
  { terminal box }
  VRect(bmp, (bx1 + bx2) / 2 - w * 0.11, y - h * 0.16, (bx1 + bx2) / 2 + w * 0.11, y + 1, cd);
  { flange + shaft }
  VRect(bmp, bx2, y + h * 0.15, bx2 + w * 0.04, y + h * 0.75, cd);
  VRect(bmp, bx2 + w * 0.04, y + h * 0.36, x + w, y + h * 0.52, BGRA(170, 170, 175));
  VRoundFrame(bmp, bx1, y, bx2, y + h * 0.88, 6, BGRA(40, 40, 40), 1.2);
  if IsManualVis(V) then
    DrawStripe(bmp, bx1, y + h * 0.34, bx2, y + h * 0.56);
end;

procedure DrawGearMotor(bmp: TBGRABitmap; x, y, w, h: Single; V: TDevVisual);
var
  c, cd: TBGRAPixel;
  gx: Single;
begin
  gx := x + w * 0.66;
  DrawMotor(bmp, x, y, w * 0.68, h, V);
  c := StateColor(V);
  cd := Darker(c, 0.65);
  { gearbox }
  VRound(bmp, gx, y - h * 0.1, x + w * 0.92, y + h * 0.95, 5, Lighter(c, 0.25));
  VRoundFrame(bmp, gx, y - h * 0.1, x + w * 0.92, y + h * 0.95, 5, BGRA(40, 40, 40), 1.2);
  VLine(bmp, gx + 4, y + h * 0.4, x + w * 0.92 - 4, y + h * 0.4, cd, 1);
  { output flange }
  VRect(bmp, x + w * 0.92, y + h * 0.1, x + w, y + h * 0.8, cd);
  if IsManualVis(V) then
    DrawStripe(bmp, gx, y + h * 0.5, x + w * 0.92, y + h * 0.7);
end;

procedure DrawBlower(bmp: TBGRABitmap; cx, cy, r: Single; V: TDevVisual; Phase: Single);
var
  c, cd: TBGRAPixel;
  k: Integer;
  a: Single;
  pts: array[0..3] of TPointF;
begin
  c := StateColor(V);
  cd := Darker(c, 0.55);
  { base }
  VRect(bmp, cx - r * 0.7, cy + r * 0.9, cx + r * 0.7, cy + r * 1.08, BGRA(40, 40, 40));
  { outlet (scroll) }
  VRect(bmp, cx + r * 0.45, cy - r * 1.25, cx + r * 1.05, cy, c);
  VFrame(bmp, cx + r * 0.45, cy - r * 1.25, cx + r * 1.05, cy, BGRA(40, 40, 40), 1.2);
  { housing }
  VCircle(bmp, cx, cy, r, c);
  VRing(bmp, cx, cy, r, BGRA(40, 40, 40), 1.5);
  VCircle(bmp, cx, cy, r * 0.74, BGRA(235, 238, 240));
  VRing(bmp, cx, cy, r * 0.74, cd, 2);
  { impeller }
  for k := 0 to 7 do
  begin
    a := Phase + k * Pi / 4;
    pts[0] := PointF(cx + Cos(a) * r * 0.16, cy + Sin(a) * r * 0.16);
    pts[1] := PointF(cx + Cos(a + 0.42) * r * 0.68, cy + Sin(a + 0.42) * r * 0.68);
    pts[2] := PointF(cx + Cos(a + 0.62) * r * 0.66, cy + Sin(a + 0.62) * r * 0.66);
    pts[3] := PointF(cx + Cos(a + 0.35) * r * 0.16, cy + Sin(a + 0.35) * r * 0.16);
    VPoly(bmp, pts, Darker(c, 0.75));
  end;
  VCircle(bmp, cx, cy, r * 0.16, cd);
  VCircle(bmp, cx, cy, r * 0.06, BGRA(220, 220, 220));
  if IsManualVis(V) then
    VRing(bmp, cx, cy, r * 0.87, CL_ORANGE, r * 0.16);
end;

end.
