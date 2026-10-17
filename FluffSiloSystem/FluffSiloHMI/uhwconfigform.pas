unit uHwConfigForm;

{ Hardware Config: protocol (Modbus TCP / Siemens S7), PLC connection and the
  register map (tag table, one Modbus and one S7 address per tag) }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, Forms, Controls, Graphics, Dialogs, ExtCtrls, StdCtrls,
  Grids, Spin, uModbus, uS7, uPlcLink, uSim;

type
  TColKind = (ckGroup, ckKey, ckAcc, ckArea, ckAddr, ckBit, ckS7, ckType, ckScale, ckEn, ckLive, ckDesc);

  { THwConfigForm }

  THwConfigForm = class(TForm)
  private
    FTags: TTagDefs;
    FProto: TPlcProtocol;
    CmbProto: TComboBox;
    EdHost: TEdit;
    SpPort, SpTimeout, SpPoll, SpPulse, SpGap: TSpinEdit;
    PnlModbus, PnlS7: TPanel;
    SpUnit, SpRack, SpSlot: TSpinEdit;
    CmbBase, CmbWord, CmbConn, CmbFilter: TComboBox;
    ChkAuto, ChkStartPlc: TCheckBox;
    BtnDb: TButton;
    GrpMap: TGroupBox;
    Grid: TStringGrid;
    LblInfo: TLabel;
    Timer: TTimer;
    FRowTag: array of Integer;
    FCols: array of TColKind;
    procedure BuildUI;
    procedure BuildColumns;
    function Col(K: TColKind): Integer;
    procedure LoadFrom(const S: TPlcSettings);
    procedure ReadSettings(out S: TPlcSettings);
    procedure FillGrid;
    procedure GridToTags;
    procedure ApplyProtocol;
    procedure ProtoChange(Sender: TObject);
    procedure TestClick(Sender: TObject);
    procedure DefaultsClick(Sender: TObject);
    procedure ImportClick(Sender: TObject);
    procedure ExportClick(Sender: TObject);
    procedure SaveClick(Sender: TObject);
    procedure DbClick(Sender: TObject);
    procedure FilterChange(Sender: TObject);
    procedure TimerTick(Sender: TObject);
    procedure GridSelectEditor(Sender: TObject; aCol, aRow: Integer; var Editor: TWinControl);
    procedure GridPrepareCanvas(Sender: TObject; aCol, aRow: Integer; aState: TGridDrawState);
  public
    constructor CreateCfg(AOwner: TComponent);
  end;

{ returns True when the configuration was saved }
function ShowHardwareConfig: Boolean;

implementation

const
  READONLY_COLS = [ckGroup, ckKey, ckAcc, ckLive, ckDesc];

function ShowHardwareConfig: Boolean;
var
  F: THwConfigForm;
begin
  F := THwConfigForm.CreateCfg(Application);
  try
    Result := F.ShowModal = mrOk;
  finally
    F.Free;
  end;
end;

function FloatTxt(V: Double): string;
var
  fs: TFormatSettings;
begin
  fs := DefaultFormatSettings;
  fs.DecimalSeparator := '.';
  Result := FloatToStr(V, fs);
end;

function TxtFloat(const S: string; Def: Double): Double;
var
  fs: TFormatSettings;
  t: string;
begin
  fs := DefaultFormatSettings;
  fs.DecimalSeparator := '.';
  t := StringReplace(Trim(S), ',', '.', []);
  if not TryStrToFloat(t, Result, fs) then
    Result := Def;
end;

{ THwConfigForm }

constructor THwConfigForm.CreateCfg(AOwner: TComponent);
begin
  inherited CreateNew(AOwner);
  FTags := Copy(Tags);
  FProto := PlcCfg.Protocol;
  BuildUI;
  LoadFrom(PlcCfg);
  ApplyProtocol;
end;

procedure THwConfigForm.BuildUI;
var
  g: TGroupBox;
  pBtn, pRight: TPanel;
  b: TButton;

  function Lbl(AParent: TWinControl; X, Y: Integer; const S: string): TLabel;
  begin
    Result := TLabel.Create(Self);
    Result.Parent := AParent;
    Result.SetBounds(X, Y + 4, 150, 20);
    Result.Caption := S;
  end;

  function Spin(AParent: TWinControl; X, Y, AMin, AMax: Integer): TSpinEdit;
  begin
    Result := TSpinEdit.Create(Self);
    Result.Parent := AParent;
    Result.SetBounds(X, Y, 100, 26);
    Result.MinValue := AMin;
    Result.MaxValue := AMax;
  end;

  function Combo(AParent: TWinControl; X, Y, W: Integer): TComboBox;
  begin
    Result := TComboBox.Create(Self);
    Result.Parent := AParent;
    Result.Style := csDropDownList;
    Result.SetBounds(X, Y, W, 26);
  end;

  function Btn(AParent: TWinControl; X, W: Integer; const S: string; AClick: TNotifyEvent): TButton;
  begin
    Result := TButton.Create(Self);
    Result.Parent := AParent;
    Result.SetBounds(X, 8, W, 30);
    Result.Caption := S;
    Result.OnClick := AClick;
  end;

  function SubPanel: TPanel;
  begin
    Result := TPanel.Create(Self);
    Result.Parent := g;
    Result.BevelOuter := bvNone;
    Result.SetBounds(0, 68, 975, 34);
  end;

begin
  Caption := 'FluffSilo HMI - Hardware Config (PLC: Modbus TCP / Siemens S7)';
  Width := Min(1180, Screen.WorkAreaWidth);
  Height := Min(820, Screen.WorkAreaHeight - 40);
  Position := poMainFormCenter;
  BorderIcons := [biSystemMenu, biMaximize];

  { ---------- connection ---------- }
  g := TGroupBox.Create(Self);
  g.Parent := Self;
  g.Align := alTop;
  g.Height := 160;
  g.Caption := ' PLC Connection ';
  g.BorderSpacing.Around := 6;

  Lbl(g, 12, 6, 'Protocol');
  CmbProto := Combo(g, 130, 6, 160);
  CmbProto.Items.Add(ProtocolName(ppModbusTcp));
  CmbProto.Items.Add(ProtocolName(ppS7));
  CmbProto.OnChange := @ProtoChange;
  Lbl(g, 320, 6, 'PLC IP address');
  EdHost := TEdit.Create(Self);
  EdHost.Parent := g;
  EdHost.SetBounds(450, 6, 160, 26);
  Lbl(g, 640, 6, 'TCP port');
  SpPort := Spin(g, 760, 6, 1, 65535);

  Lbl(g, 12, 38, 'Timeout (ms)');
  SpTimeout := Spin(g, 130, 38, 100, 30000);
  Lbl(g, 320, 38, 'Poll interval (ms)');
  SpPoll := Spin(g, 450, 38, 20, 60000);
  Lbl(g, 640, 38, 'Command pulse (ms)');
  SpPulse := Spin(g, 760, 38, 50, 10000);

  { protocol specific row }
  PnlModbus := SubPanel;
  Lbl(PnlModbus, 12, 2, 'Unit ID (slave)');
  SpUnit := Spin(PnlModbus, 130, 2, 0, 255);
  Lbl(PnlModbus, 320, 2, 'Address base');
  CmbBase := Combo(PnlModbus, 450, 2, 180);
  CmbBase.Items.Add('0 - protocol offset');
  CmbBase.Items.Add('1 - 1-based');
  Lbl(PnlModbus, 640, 2, '32-bit word order');
  CmbWord := Combo(PnlModbus, 760, 2, 200);
  CmbWord.Items.Add('High word first (AB CD)');
  CmbWord.Items.Add('Low word first (CD AB)');

  PnlS7 := SubPanel;
  Lbl(PnlS7, 12, 2, 'Rack');
  SpRack := Spin(PnlS7, 130, 2, 0, 7);
  Lbl(PnlS7, 320, 2, 'Slot');
  SpSlot := Spin(PnlS7, 450, 2, 0, 31);
  SpSlot.Hint := 'S7-1200 / S7-1500: rack 0 slot 1'#13'S7-300: rack 0 slot 2'#13'S7-400: see hardware config';
  SpSlot.ShowHint := True;
  Lbl(PnlS7, 640, 2, 'Connection type');
  CmbConn := Combo(PnlS7, 760, 2, 200);
  CmbConn.Items.Add('PG (programming device)');
  CmbConn.Items.Add('OP (operator panel)');
  CmbConn.Items.Add('S7 Basic');

  Lbl(g, 12, 104, 'Merge read gap');
  SpGap := Spin(g, 130, 104, 0, 100);
  SpGap.Hint := 'Read neighbouring addresses in one request when the gap is not larger than this'#13 +
    '(registers / bits for Modbus, bytes for S7). Keep 0 if the PLC rejects unmapped addresses.';
  SpGap.ShowHint := True;
  ChkAuto := TCheckBox.Create(Self);
  ChkAuto.Parent := g;
  ChkAuto.SetBounds(320, 108, 250, 22);
  ChkAuto.Caption := 'Connect automatically at start-up';
  ChkStartPlc := TCheckBox.Create(Self);
  ChkStartPlc.Parent := g;
  ChkStartPlc.SetBounds(640, 108, 250, 22);
  ChkStartPlc.Caption := 'Start in PLC mode';

  b := TButton.Create(Self);
  b.Parent := g;
  b.SetBounds(990, 6, 160, 58);
  b.Caption := 'Test connection';
  b.OnClick := @TestClick;

  { ---------- buttons ---------- }
  pBtn := TPanel.Create(Self);
  pBtn.Parent := Self;
  pBtn.Align := alBottom;
  pBtn.Height := 46;
  pBtn.BevelOuter := bvNone;
  Btn(pBtn, 8, 130, 'Load defaults', @DefaultsClick);
  Btn(pBtn, 144, 130, 'Import CSV...', @ImportClick);
  Btn(pBtn, 280, 130, 'Export CSV...', @ExportClick);
  pRight := TPanel.Create(Self);
  pRight.Parent := pBtn;
  pRight.Align := alRight;
  pRight.Width := 300;
  pRight.BevelOuter := bvNone;
  b := Btn(pRight, 6, 140, 'Save && Apply', @SaveClick);
  b.Default := True;
  b := Btn(pRight, 156, 130, 'Cancel', nil);
  b.ModalResult := mrCancel;
  b.Cancel := True;

  { ---------- tag table ---------- }
  GrpMap := TGroupBox.Create(Self);
  GrpMap.Parent := Self;
  GrpMap.Align := alClient;
  GrpMap.BorderSpacing.Around := 6;

  pBtn := TPanel.Create(Self);
  pBtn.Parent := GrpMap;
  pBtn.Align := alTop;
  pBtn.Height := 34;
  pBtn.BevelOuter := bvNone;
  Lbl(pBtn, 6, 2, 'Show group');
  CmbFilter := Combo(pBtn, 90, 4, 180);
  CmbFilter.Items.CommaText :=
    '"All","Device Status","System Status","Command","Device Command","Parameter","Process","Pattern"';
  CmbFilter.ItemIndex := 0;
  CmbFilter.OnChange := @FilterChange;
  BtnDb := TButton.Create(Self);
  BtnDb.Parent := pBtn;
  BtnDb.SetBounds(280, 3, 150, 28);
  BtnDb.Caption := 'Change DB number...';
  BtnDb.OnClick := @DbClick;
  LblInfo := TLabel.Create(Self);
  LblInfo.Parent := pBtn;
  LblInfo.SetBounds(440, 8, 720, 20);
  LblInfo.Font.Color := clGrayText;

  Grid := TStringGrid.Create(Self);
  Grid.Parent := GrpMap;
  Grid.Align := alClient;
  Grid.FixedCols := 0;
  Grid.RowCount := 1;
  Grid.FixedRows := 1;
  Grid.DefaultRowHeight := 24;
  Grid.Options := Grid.Options + [goEditing, goColSizing] - [goRangeSelect];
  Grid.OnSelectEditor := @GridSelectEditor;
  Grid.OnPrepareCanvas := @GridPrepareCanvas;

  Timer := TTimer.Create(Self);
  Timer.Interval := 300;
  Timer.OnTimer := @TimerTick;
end;

procedure THwConfigForm.BuildColumns;

  procedure AddCol(K: TColKind; const ATitle: string; AWidth: Integer);
  var
    c: TGridColumn;
  begin
    c := Grid.Columns.Add;
    c.Title.Caption := ATitle;
    c.Width := AWidth;
    c.ReadOnly := K in READONLY_COLS;
    case K of
      ckArea:
        begin
          c.ButtonStyle := cbsPickList;
          c.PickList.Add(AreaName(maCoil));
          c.PickList.Add(AreaName(maDiscrete));
          c.PickList.Add(AreaName(maInputReg));
          c.PickList.Add(AreaName(maHoldingReg));
        end;
      ckType:
        begin
          c.ButtonStyle := cbsPickList;
          c.PickList.CommaText := 'BOOL,INT16,UINT16,INT32,FLOAT32';
        end;
      ckEn:
        begin
          c.ButtonStyle := cbsCheckboxColumn;
          c.ValueChecked := '1';
          c.ValueUnchecked := '0';
        end;
    end;
    SetLength(FCols, Length(FCols) + 1);
    FCols[High(FCols)] := K;
  end;

begin
  Grid.Columns.Clear;
  SetLength(FCols, 0);
  AddCol(ckGroup, 'Group', 110);
  AddCol(ckKey, 'Tag', 210);
  AddCol(ckAcc, 'R/W', 40);
  if FProto = ppS7 then
    AddCol(ckS7, 'S7 Address', 150)
  else
  begin
    AddCol(ckArea, 'Area', 150);
    AddCol(ckAddr, 'Address', 70);
    AddCol(ckBit, 'Bit', 40);
  end;
  AddCol(ckType, 'Type', 80);
  AddCol(ckScale, 'Scale', 55);
  AddCol(ckEn, 'Use', 40);
  AddCol(ckLive, 'Live value', 80);
  AddCol(ckDesc, 'Description', 300);
end;

function THwConfigForm.Col(K: TColKind): Integer;
var
  i: Integer;
begin
  for i := 0 to High(FCols) do
    if FCols[i] = K then
      Exit(i);
  Result := -1;
end;

procedure THwConfigForm.ApplyProtocol;
begin
  CmbProto.ItemIndex := Ord(FProto);
  PnlModbus.Visible := FProto = ppModbusTcp;
  PnlS7.Visible := FProto = ppS7;
  BtnDb.Visible := FProto = ppS7;
  if FProto = ppS7 then
    GrpMap.Caption := ' Register map - S7 address per tag (DB must be non-optimized, PUT/GET enabled) '
  else
    GrpMap.Caption := ' Register map - Modbus address per tag (as in the PLC Modbus table) ';
  BuildColumns;
  FillGrid;
end;

procedure THwConfigForm.ProtoChange(Sender: TObject);
var
  np: TPlcProtocol;
begin
  np := TPlcProtocol(Max(0, CmbProto.ItemIndex));
  if np = FProto then Exit;
  GridToTags;
  { keep the well-known port in step with the protocol }
  if (np = ppS7) and (SpPort.Value = 502) then SpPort.Value := 102;
  if (np = ppModbusTcp) and (SpPort.Value = 102) then SpPort.Value := 502;
  FProto := np;
  ApplyProtocol;
end;

procedure THwConfigForm.LoadFrom(const S: TPlcSettings);
begin
  EdHost.Text := S.Host;
  SpPort.Value := S.Port;
  SpUnit.Value := S.UnitId;
  SpTimeout.Value := S.TimeoutMs;
  SpPoll.Value := S.PollMs;
  SpPulse.Value := S.PulseMs;
  CmbBase.ItemIndex := EnsureRange(S.AddrBase, 0, 1);
  CmbWord.ItemIndex := Ord(S.WordSwap);
  SpRack.Value := S.S7Rack;
  SpSlot.Value := S.S7Slot;
  CmbConn.ItemIndex := EnsureRange(S.S7ConnType, 1, 3) - 1;
  SpGap.Value := S.MaxGap;
  ChkAuto.Checked := S.AutoConnect;
  ChkStartPlc.Checked := S.StartInPlc;
end;

procedure THwConfigForm.ReadSettings(out S: TPlcSettings);
begin
  S.Protocol := FProto;
  S.Host := Trim(EdHost.Text);
  S.Port := SpPort.Value;
  S.UnitId := SpUnit.Value;
  S.TimeoutMs := SpTimeout.Value;
  S.PollMs := SpPoll.Value;
  S.PulseMs := SpPulse.Value;
  S.AddrBase := Max(0, CmbBase.ItemIndex);
  S.WordSwap := CmbWord.ItemIndex = 1;
  S.S7Rack := SpRack.Value;
  S.S7Slot := SpSlot.Value;
  S.S7ConnType := Max(0, CmbConn.ItemIndex) + 1;
  S.MaxGap := SpGap.Value;
  S.AutoConnect := ChkAuto.Checked;
  S.StartInPlc := ChkStartPlc.Checked;
end;

procedure THwConfigForm.FillGrid;
var
  i, r: Integer;
  t: TTagDef;
  flt: string;

  procedure Put(K: TColKind; const S: string);
  begin
    if Col(K) >= 0 then
      Grid.Cells[Col(K), r + 1] := S;
  end;

begin
  if CmbFilter.ItemIndex > 0 then flt := CmbFilter.Text else flt := '';
  SetLength(FRowTag, 0);
  for i := 0 to High(FTags) do
    if (flt = '') or (FTags[i].Group = flt) then
    begin
      SetLength(FRowTag, Length(FRowTag) + 1);
      FRowTag[High(FRowTag)] := i;
    end;
  Grid.RowCount := Length(FRowTag) + 1;
  for r := 0 to High(FRowTag) do
  begin
    t := FTags[FRowTag[r]];
    Put(ckGroup, t.Group);
    Put(ckKey, t.Key);
    Put(ckAcc, AccessName(t.Access));
    Put(ckArea, AreaName(t.Area));
    Put(ckAddr, IntToStr(t.Address));
    if t.Bit >= 0 then Put(ckBit, IntToStr(t.Bit)) else Put(ckBit, '');
    Put(ckS7, t.S7Addr);
    Put(ckType, TypeName(t.DType));
    Put(ckScale, FloatTxt(t.Scale));
    Put(ckEn, IntToStr(Ord(t.Enabled)));
    Put(ckLive, '');
    Put(ckDesc, t.Desc);
  end;
  if FProto = ppS7 then
    LblInfo.Caption := Format('%d of %d tags.  S7 address: DB10.DBX0.0  DB10.DBW20  DB10.DBD40  M10.3  MW20  Q0.1 ' +
      '(BOOL=X/bit, INT=W, DINT/REAL=D)', [Length(FRowTag), Length(FTags)])
  else
    LblInfo.Caption := Format('%d of %d tags.  Edit Area / Address / Bit / Type / Scale / Use.  ' +
      'Bit = bit 0..15 of a register for BOOL (blank = whole value).', [Length(FRowTag), Length(FTags)]);
end;

procedure THwConfigForm.GridToTags;
var
  r, i: Integer;
  a: TMbArea;
  ty: TTagType;
  s: string;

  function Get(K: TColKind; out V: string): Boolean;
  begin
    Result := Col(K) >= 0;
    if Result then V := Grid.Cells[Col(K), r + 1];
  end;

begin
  for r := 0 to High(FRowTag) do
  begin
    i := FRowTag[r];
    if Get(ckArea, s) then
      for a := Low(TMbArea) to High(TMbArea) do
        if s = AreaName(a) then
          FTags[i].Area := a;
    if Get(ckAddr, s) then
      FTags[i].Address := StrToIntDef(Trim(s), FTags[i].Address);
    if Get(ckBit, s) then
    begin
      s := Trim(s);
      if s = '' then FTags[i].Bit := -1 else FTags[i].Bit := StrToIntDef(s, FTags[i].Bit);
    end;
    if Get(ckS7, s) then
      FTags[i].S7Addr := UpperCase(Trim(s));
    if Get(ckType, s) then
      for ty := Low(TTagType) to High(TTagType) do
        if s = TypeName(ty) then
          FTags[i].DType := ty;
    if Get(ckScale, s) then
      FTags[i].Scale := TxtFloat(s, FTags[i].Scale);
    if Get(ckEn, s) then
      FTags[i].Enabled := s = '1';
  end;
end;

procedure THwConfigForm.FilterChange(Sender: TObject);
begin
  GridToTags;
  FillGrid;
end;

procedure THwConfigForm.GridSelectEditor(Sender: TObject; aCol, aRow: Integer;
  var Editor: TWinControl);
begin
  if (aCol < 0) or (aCol > High(FCols)) or (FCols[aCol] in READONLY_COLS) then
    Editor := nil;
end;

procedure THwConfigForm.GridPrepareCanvas(Sender: TObject; aCol, aRow: Integer;
  aState: TGridDrawState);
var
  a: TS7Address;
begin
  if (aRow < 1) or (aCol > High(FCols)) then Exit;
  if FCols[aCol] in READONLY_COLS then
    Grid.Canvas.Brush.Color := $00F4F0EC;
  if Grid.Cells[Col(ckEn), aRow] <> '1' then
    Grid.Canvas.Font.Color := clGray
  else if (FCols[aCol] = ckS7) and not ParseS7Address(Grid.Cells[aCol, aRow], a) then
    Grid.Canvas.Font.Color := clRed;
  if (FCols[aCol] = ckLive) and (Grid.Cells[aCol, aRow] = 'ON') then
    Grid.Canvas.Font.Color := $00009000;
end;

procedure THwConfigForm.TimerTick(Sender: TObject);
var
  r, i, j, c: Integer;
  s: string;
begin
  { live values come from the running link (it uses the saved map) }
  c := Col(ckLive);
  if c < 0 then Exit;
  for r := 0 to High(FRowTag) do
  begin
    i := FRowTag[r];
    s := '';
    if Link.Running then
    begin
      j := FindTag(FTags[i].Key);
      if (j >= 0) and (j <= High(Link.Valid)) then
      begin
        if Tags[j].Access = acWrite then
          s := '(write)'
        else if not Tags[j].Enabled then
          s := ''
        else if Link.Valid[j] then
          s := FormatTagValue(Tags[j], Link.Values[j])
        else
          s := '?';
      end;
    end;
    if Grid.Cells[c, r + 1] <> s then
      Grid.Cells[c, r + 1] := s;
  end;
end;

procedure THwConfigForm.TestClick(Sender: TObject);
var
  cfg: TPlcSettings;
  mb: TModbusTcpClient;
  s7: TS7Client;
  i, off: Integer;
  msg: string;
  t0: QWord;
  a: TS7Address;
begin
  ReadSettings(cfg);
  GridToTags;
  Screen.Cursor := crHourGlass;
  mb := nil;
  s7 := nil;
  try
    t0 := GetTickCount64;
    try
      if cfg.Protocol = ppS7 then
      begin
        s7 := TS7Client.Create(cfg.Host, cfg.Port, cfg.S7Rack, cfg.S7Slot, cfg.S7ConnType, cfg.TimeoutMs);
        s7.Connect;
        msg := Format('S7 connect to %s:%d rack %d slot %d OK (%d ms), PDU size %d',
          [cfg.Host, cfg.Port, cfg.S7Rack, cfg.S7Slot, GetTickCount64 - t0, s7.PduSize]);
      end
      else
      begin
        mb := TModbusTcpClient.Create(cfg.Host, cfg.Port, cfg.UnitId, cfg.TimeoutMs);
        mb.Connect;
        msg := Format('TCP connect to %s:%d OK (%d ms)', [cfg.Host, cfg.Port, GetTickCount64 - t0]);
      end;
      { read the first readable tag as a protocol check }
      for i := 0 to High(FTags) do
        if TagReadable(FTags[i]) then
        begin
          try
            if cfg.Protocol = ppS7 then
            begin
              if not ParseS7Address(FTags[i].S7Addr, a) then
                raise EPlcDevice.Create('invalid S7 address');
              s7.ReadArea(a.Area, a.DB, a.Start, Max(1, a.Size));
            end
            else
            begin
              off := FTags[i].Address - cfg.AddrBase;
              case FTags[i].Area of
                maCoil: mb.ReadBits(1, off, 1);
                maDiscrete: mb.ReadBits(2, off, 1);
                maInputReg: mb.ReadRegs(4, off, 1);
                maHoldingReg: mb.ReadRegs(3, off, 1);
              end;
            end;
            msg := msg + LineEnding + Format('Read %s [%s] OK',
              [FTags[i].Key, TagAddrText(FTags[i], cfg.Protocol)]);
          except
            on E: EPlcDevice do
              msg := msg + LineEnding + Format('PLC answered, but %s [%s]: %s',
                [FTags[i].Key, TagAddrText(FTags[i], cfg.Protocol), E.Message]);
          end;
          Break;
        end;
      Screen.Cursor := crDefault;
      MessageDlg('Test connection', msg, mtInformation, [mbOK], 0);
    except
      on E: Exception do
      begin
        Screen.Cursor := crDefault;
        MessageDlg('Test connection', Format('Failed: %s %s:%d'#13'%s',
          [ProtocolName(cfg.Protocol), cfg.Host, cfg.Port, E.Message]), mtError, [mbOK], 0);
      end;
    end;
  finally
    mb.Free;
    s7.Free;
    Screen.Cursor := crDefault;
  end;
end;

procedure THwConfigForm.DbClick(Sender: TObject);
var
  sOld, sNew: string;
  n: Integer;
begin
  sOld := '10';
  sNew := '';
  if not InputQuery('Change DB number', 'Current DB number used by the tags:', sOld) then Exit;
  if not InputQuery('Change DB number', 'New DB number:', sNew) then Exit;
  GridToTags;
  n := ChangeS7DbNumber(FTags, StrToIntDef(sOld, -1), StrToIntDef(sNew, -1));
  if StrToIntDef(sNew, 0) < 1 then
    n := 0;
  FillGrid;
  MessageDlg('Change DB number', Format('%d tags changed to DB%s.', [n, sNew]), mtInformation, [mbOK], 0);
end;

procedure THwConfigForm.DefaultsClick(Sender: TObject);
var
  s: TPlcSettings;
begin
  if MessageDlg('Load defaults', 'Replace the whole register map (Modbus and S7 addresses) with the default map?' +
    #13'(IP address and connection settings are kept)', mtConfirmation, [mbYes, mbNo], 0) <> mrYes then
    Exit;
  FTags := DefaultTags;
  DefaultSettings(s);
  CmbBase.ItemIndex := s.AddrBase;
  FillGrid;
end;

procedure THwConfigForm.ImportClick(Sender: TObject);
var
  dlg: TOpenDialog;
  log: TStringList;
  n: Integer;
begin
  dlg := TOpenDialog.Create(Self);
  log := TStringList.Create;
  try
    dlg.Filter := 'CSV (*.csv)|*.csv|All files|*.*';
    if not dlg.Execute then Exit;
    GridToTags;
    n := ImportTagsCsv(dlg.FileName, FTags, log);
    FillGrid;
    if log.Count > 0 then
      MessageDlg('Import CSV', Format('%d tags imported, %d problems:'#13'%s',
        [n, log.Count, log.Text]), mtWarning, [mbOK], 0)
    else
      MessageDlg('Import CSV', Format('%d tags imported.', [n]), mtInformation, [mbOK], 0);
  finally
    log.Free;
    dlg.Free;
  end;
end;

procedure THwConfigForm.ExportClick(Sender: TObject);
var
  dlg: TSaveDialog;
begin
  dlg := TSaveDialog.Create(Self);
  try
    dlg.Filter := 'CSV (*.csv)|*.csv';
    dlg.DefaultExt := 'csv';
    dlg.FileName := 'FluffSiloHMI_RegisterMap.csv';
    if not dlg.Execute then Exit;
    GridToTags;
    ExportTagsCsv(dlg.FileName, FTags);
  finally
    dlg.Free;
  end;
end;

procedure THwConfigForm.SaveClick(Sender: TObject);
var
  cfg: TPlcSettings;
  err: TStringList;
  wasRunning: Boolean;
begin
  ReadSettings(cfg);
  GridToTags;
  err := TStringList.Create;
  try
    if not ValidateTags(cfg, FTags, err) then
    begin
      while err.Count > 25 do
        err.Delete(err.Count - 1);
      MessageDlg('Hardware Config', 'Please correct:'#13 + err.Text, mtError, [mbOK], 0);
      Exit;
    end;
  finally
    err.Free;
  end;
  wasRunning := Link.Running;
  if wasRunning then
    Link.Stop;
  PlcCfg := cfg;
  Tags := Copy(FTags);
  IndexTags;
  try
    SaveConfig;
  except
    on E: Exception do
      MessageDlg('Hardware Config', 'Could not save ' + ConfigFileName + #13 + E.Message,
        mtError, [mbOK], 0);
  end;
  Sim.Log(-1, True, 'Hardware Config saved (' + ProtocolName(cfg.Protocol) + '): ' + ConfigFileName);
  if wasRunning then
    Link.Start;
  ModalResult := mrOk;
end;

end.
