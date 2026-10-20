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

const
  { HMI2 theme (TColor = $00BBGGRR) }
  clThemeBg      = TColor($00E2DBD6);   { window background   214,219,226 }
  clThemeCard    = TColor($00FBF8F6);   { card face           246,248,251 }
  clThemeBorder  = TColor($00C8BAB0);   { card border         176,186,200 }
  clThemeTitle   = TColor($00783C1E);   { card title           30, 60,120 }
  clThemeAccent  = TColor($00C86E28);   { accent / selection   40,110,200 }
  clThemeText    = TColor($002D231E);   { normal text          30, 35, 45 }
  clThemeMuted   = TColor($00877866);   { secondary text      110,120,135 }

type
  TIconKind = (ikNone, ikSave, ikOpen, ikUpload, ikDownload, ikAdd, ikInsert, ikDelete,
    ikClear, ikDefault, ikChart, ikList, ikGear, ikPattern, ikPlay, ikStop, ikWarning,
    ikFolder, ikUp, ikDown, ikCopy);

function TB(c: TColor): TBGRAPixel;
procedure DrawIcon(bmp: TBGRABitmap; Kind: TIconKind; x, y, s: Single; c: TBGRAPixel);
procedure DrawCard(bmp: TBGRABitmap; x1, y1, x2, y2: Single; const ATitle: string;
  Accent: TBGRAPixel; TitleH: Integer = 26);
procedure DrawHatch(bmp: TBGRABitmap; x1, y1, x2, y2: Single; c: TBGRAPixel; Gap: Single = 6);
procedure DrawScrollBar(bmp: TBGRABitmap; x, y, h: Integer; Total, Visible, First: Integer);

implementation

function TB(c: TColor): TBGRAPixel;
begin
  Result := ColorToBGRA(ColorToRGB(c));
end;

procedure DrawCard(bmp: TBGRABitmap; x1, y1, x2, y2: Single; const ATitle: string;
  Accent: TBGRAPixel; TitleH: Integer);
begin
  { soft shadow, face, title band with accent bar }
  bmp.FillRoundRectAntialias(x1 + 1, y1 + 2, x2 + 1, y2 + 2, 9, 9, BGRA(0, 0, 0, 28));
  bmp.FillRoundRectAntialias(x1, y1, x2, y2, 9, 9, TB(clThemeCard));
  if ATitle <> '' then
  begin
    bmp.FillRoundRectAntialias(x1, y1, x2, y1 + TitleH, 9, 9, BGRA(232, 237, 244));
    bmp.FillRectAntialias(x1, y1 + TitleH - 9, x2, y1 + TitleH, BGRA(232, 237, 244));
    bmp.DrawLineAntialias(x1, y1 + TitleH, x2, y1 + TitleH, BGRA(205, 212, 222), 1);
    bmp.FillRoundRectAntialias(x1 + 8, y1 + 7, x1 + 12, y1 + TitleH - 7, 2, 2, Accent);
    PText(bmp, Round(x1) + 18, Round(y1) + (TitleH - 17) div 2, ATitle, 13, TB(clThemeTitle), True);
  end;
  bmp.RoundRectAntialias(x1, y1, x2, y2, 9, 9, TB(clThemeBorder), 1);
end;

procedure DrawHatch(bmp: TBGRABitmap; x1, y1, x2, y2: Single; c: TBGRAPixel; Gap: Single);
var
  x: Single;
begin
  x := x1 - (y2 - y1);
  while x < x2 do
  begin
    bmp.DrawLineAntialias(Max(x1, x), y1 + Max(0, x1 - x), Min(x2, x + (y2 - y1)),
      y2 - Max(0, x + (y2 - y1) - x2), c, 1);
    x := x + Gap;
  end;
end;

procedure DrawScrollBar(bmp: TBGRABitmap; x, y, h: Integer; Total, Visible, First: Integer);
var
  th, ty: Single;
begin
  if (Total <= Visible) or (Total <= 0) then Exit;
  bmp.FillRoundRectAntialias(x, y, x + 8, y + h, 4, 4, BGRA(0, 0, 0, 25));
  th := Max(24, h * Visible / Total);
  ty := y + (h - th) * First / Max(1, Total - Visible);
  bmp.FillRoundRectAntialias(x + 1, ty, x + 7, ty + th, 3, 3, BGRA(90, 105, 130, 170));
end;

procedure DrawIcon(bmp: TBGRABitmap; Kind: TIconKind; x, y, s: Single; c: TBGRAPixel);
var
  w: Single;
  arc: array of TPointF;
  i: Integer;

  procedure L(ax, ay, bx, by: Single);
  begin
    bmp.DrawLineAntialias(x + ax * s, y + ay * s, x + bx * s, y + by * s, c, w);
  end;

  procedure Box(ax, ay, bx, by: Single);
  begin
    bmp.RectangleAntialias(x + ax * s, y + ay * s, x + bx * s, y + by * s, c, w);
  end;

  procedure Arrow(ax, ay, bx, by: Single);
  var
    dx, dy, ln: Single;
  begin
    L(ax, ay, bx, by);
    dx := bx - ax;
    dy := by - ay;
    ln := Max(0.001, Hypot(dx, dy));
    dx := dx / ln * 0.28;
    dy := dy / ln * 0.28;
    L(bx, by, bx - dx - dy, by - dy + dx);
    L(bx, by, bx - dx + dy, by - dy - dx);
  end;

begin
  { icons are drawn in a 1 x 1 box scaled by s, top-left at (x, y) }
  w := Max(1.2, s * 0.09);
  case Kind of
    ikSave:
      begin
        Box(0.12, 0.12, 0.88, 0.88);
        Box(0.3, 0.12, 0.7, 0.38);
        Box(0.26, 0.56, 0.74, 0.88);
      end;
    ikOpen, ikFolder:
      begin
        L(0.08, 0.25, 0.4, 0.25);
        L(0.4, 0.25, 0.48, 0.35);
        L(0.48, 0.35, 0.92, 0.35);
        L(0.92, 0.35, 0.92, 0.85);
        L(0.92, 0.85, 0.08, 0.85);
        L(0.08, 0.85, 0.08, 0.25);
        if Kind = ikOpen then
          L(0.08, 0.85, 0.25, 0.5);
      end;
    ikUpload:
      begin
        Arrow(0.5, 0.75, 0.5, 0.1);
        L(0.12, 0.62, 0.12, 0.9);
        L(0.12, 0.9, 0.88, 0.9);
        L(0.88, 0.9, 0.88, 0.62);
      end;
    ikDownload:
      begin
        Arrow(0.5, 0.1, 0.5, 0.72);
        L(0.12, 0.62, 0.12, 0.9);
        L(0.12, 0.9, 0.88, 0.9);
        L(0.88, 0.9, 0.88, 0.62);
      end;
    ikAdd:
      begin
        L(0.5, 0.15, 0.5, 0.85);
        L(0.15, 0.5, 0.85, 0.5);
      end;
    ikInsert:
      begin
        L(0.1, 0.2, 0.9, 0.2);
        L(0.1, 0.8, 0.9, 0.8);
        L(0.5, 0.35, 0.5, 0.65);
        L(0.35, 0.5, 0.65, 0.5);
      end;
    ikDelete:
      begin
        L(0.2, 0.2, 0.8, 0.8);
        L(0.8, 0.2, 0.2, 0.8);
      end;
    ikClear:
      begin
        L(0.15, 0.25, 0.85, 0.25);
        Box(0.25, 0.25, 0.75, 0.9);
        L(0.4, 0.1, 0.6, 0.1);
        L(0.42, 0.4, 0.42, 0.78);
        L(0.58, 0.4, 0.58, 0.78);
      end;
    ikDefault:
      begin
        SetLength(arc, 13);
        for i := 0 to 12 do
          arc[i] := PointF(x + (0.5 + 0.34 * Cos(-0.6 - i * 0.43)) * s, y + (0.5 + 0.34 * Sin(-0.6 - i * 0.43)) * s);
        bmp.DrawPolyLineAntialias(arc, c, w);
        Arrow(0.78, 0.12, 0.79, 0.3);
      end;
    ikChart:
      begin
        L(0.1, 0.1, 0.1, 0.9);
        L(0.1, 0.9, 0.9, 0.9);
        L(0.2, 0.7, 0.42, 0.4);
        L(0.42, 0.4, 0.6, 0.55);
        L(0.6, 0.55, 0.88, 0.2);
      end;
    ikList:
      begin
        L(0.1, 0.22, 0.9, 0.22);
        L(0.1, 0.5, 0.9, 0.5);
        L(0.1, 0.78, 0.9, 0.78);
      end;
    ikGear:
      begin
        bmp.EllipseAntialias(x + 0.5 * s, y + 0.5 * s, 0.24 * s, 0.24 * s, c, w);
        L(0.5, 0.05, 0.5, 0.22);
        L(0.5, 0.78, 0.5, 0.95);
        L(0.05, 0.5, 0.22, 0.5);
        L(0.78, 0.5, 0.95, 0.5);
        L(0.18, 0.18, 0.3, 0.3);
        L(0.7, 0.7, 0.82, 0.82);
        L(0.82, 0.18, 0.7, 0.3);
        L(0.3, 0.7, 0.18, 0.82);
      end;
    ikPattern:
      begin
        bmp.FillRectAntialias(x + 0.1 * s, y + 0.15 * s, x + 0.45 * s, y + 0.35 * s, c);
        bmp.FillRectAntialias(x + 0.45 * s, y + 0.42 * s, x + 0.75 * s, y + 0.6 * s, c);
        bmp.FillRectAntialias(x + 0.25 * s, y + 0.68 * s, x + 0.9 * s, y + 0.86 * s, c);
      end;
    ikPlay:
      bmp.FillPolyAntialias([PointF(x + 0.25 * s, y + 0.15 * s), PointF(x + 0.85 * s, y + 0.5 * s),
        PointF(x + 0.25 * s, y + 0.85 * s)], c);
    ikStop:
      bmp.FillRectAntialias(x + 0.22 * s, y + 0.22 * s, x + 0.78 * s, y + 0.78 * s, c);
    ikWarning:
      begin
        bmp.DrawPolygonAntialias([PointF(x + 0.5 * s, y + 0.08 * s), PointF(x + 0.95 * s, y + 0.9 * s),
          PointF(x + 0.05 * s, y + 0.9 * s)], c, w);
        L(0.5, 0.35, 0.5, 0.62);
        L(0.5, 0.74, 0.5, 0.78);
      end;
    ikUp:
      Arrow(0.5, 0.85, 0.5, 0.15);
    ikDown:
      Arrow(0.5, 0.15, 0.5, 0.85);
    ikCopy:
      begin
        Box(0.1, 0.1, 0.62, 0.62);
        Box(0.38, 0.38, 0.9, 0.9);
      end;
  end;
end;

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
