unit xxmWebProject;

interface

uses Windows, SysUtils, Classes, MSXML2_TLB, xxmPageParse;

type
  TXxmWebProjectOutput=procedure(const Msg:AnsiString);

  TXxmWebProject=class(TObject)
  private
    Data:DOMDocument;
    DataStartSize:integer;
    DataFileName,FProjectName,FRootFolder,FSrcFolder,
    FHandlerPath,FProtoPathDef,FProtoPath:AnsiString;
    RootNode,DataFiles:IXMLDOMElement;
    Modified,DoLineMaps:boolean;
    Signatures:TStringList;
    FOnOutput:TXxmWebProjectOutput;
    FParserValues:TXxmPageParserValueList;

    function ForceNode(element:IXMLDOMElement;
      const tagname,id:AnsiString;indentlevel:integer):IXMLDOMElement;
    function NodesText(element:IXMLDOMElement;const xpath:AnsiString):AnsiString;

    function ReadString(const FilePath:AnsiString):AnsiString;
    procedure BuildOutput(const Msg:AnsiString);
  public

    constructor Create(const SourcePath:AnsiString;
      OnOutput:TXxmWebProjectOutput; CanCreate:boolean);
    destructor Destroy; override;

    function CheckFiles(Rebuild:boolean;ExtraFields:TStrings):boolean;
    function GenerateProjectFiles(Rebuild:boolean;ExtraFields:TStrings):boolean;
    function ResolveErrorLines(const BuildOutput:AnsiString):AnsiString;

    function Compile:boolean;
    procedure Update;

    property ProjectName:AnsiString read FProjectName;
    property RootFolder:AnsiString read FRootFolder;
    property ProjectFile:AnsiString read DataFileName;

    property SrcFolder:AnsiString read FSrcFolder write FSrcFolder;
    property ProtoFolder:AnsiString read FProtoPath write FProtoPath;
    property LineMaps:boolean read DoLineMaps write DoLineMaps;
  end;

  EXxmWebProjectNotFound=class(Exception);
  EXxmWebProjectLoad=class(Exception);
  EXxmWebProjectCompile=class(Exception);

implementation

uses Variants, ComObj, xxmUtilities, xxmProtoParse, xxmCommonUtils;

{  }

const
  DefaultParserValues:TXxmPageParserValueList=(
    (Code:'Context.Send(';EOLs:0),//pvSend
    (Code:');';EOLs:0),//pvSendClose
    (Code:'Context.SendHTML(';EOLs:0),//pvSendHTML
    (Code:');';EOLs:0),//pvSendHTMLClose
    (Code:'Context.Send(URLEncode([';EOLs:0),//pvURLEncode
    (Code:']));';EOLs:0),//pvURLEncodeClose
    (Code:'Extra1(';EOLs:0),(Code:');';EOLs:0),//pvExtra1
    (Code:'Extra2(';EOLs:0),(Code:');';EOLs:0),//pvExtra2
    (Code:'Extra3(';EOLs:0),(Code:');';EOLs:0),//pvExtra3
    (Code:'Extra4(';EOLs:0),(Code:');';EOLs:0),//pvExtra4
    (Code:'Extra5(';EOLs:0),(Code:');';EOLs:0),//pvExtra5
    //add new above
    (Code:'';EOLs:0)
  );

  ParserValueElement:array[TXxmPageParserValues] of string=(
    'SendOpen','SendClose',
    'SendHTMLOpen','SendHTMLClose',
    'URLEncodeOpen','URLEncodeClose',
    'Extra1Open','Extra1Close',
    'Extra2Open','Extra2Close',
    'Extra3Open','Extra3Close',
    'Extra4Open','Extra4Close',
    'Extra5Open','Extra5Close',
    ''
  );

//TODO: project defaults (folder defaults?)

{ TXxmWebProject }

const
  SXxmWebProjectNotFound='Web Project File not found for "__"';
  SXxmWebProjectLoad='Could not read "__"';

constructor TXxmWebProject.Create(const SourcePath: AnsiString;
  OnOutput:TXxmWebProjectOutput; CanCreate:boolean);
var
  x:IXMLDOMElement;
  i,j,l:integer;
  s:AnsiString;
  f:TFileStream;
  pv:TXxmPageParserValues;
begin
  inherited Create;
  Modified:=false;
  DoLineMaps:=true;
  FOnOutput:=OnOutput;
  FProjectName:='';

  //assert full expanded path
  //SourcePath:=ExpandFileName(SourcePath);

  i:=Length(SourcePath);
  while (i<>0) and (SourcePath[i]<>'.') do dec(i);
  if LowerCase(Copy(SourcePath,i,Length(SourcePath)-i+1))=XxmFileExtension[ftProject] then
   begin
    //project file specified
    while (i<>0) and (SourcePath[i]<>PathDelim) do dec(i);
    FRootFolder:=Copy(SourcePath,1,i);
    DataFileName:=Copy(SourcePath,i+1,Length(SourcePath)-i);
   end
  else
   begin
    //find
    DataFileName:=XxmProjectFileName;
    FRootFolder:=IncludeTrailingPathDelimiter(SourcePath);
    i:=Length(FRootFolder);
    while (i<>0) and not(FileExists(FRootFolder+DataFileName)) do
     begin
      dec(i);
      while (i<>0) and (FRootFolder[i]<>PathDelim) do dec(i);
      SetLength(FRootFolder,i);
     end;
    if i=0 then
      if CanCreate then
       begin
        //create empty project
        if DirectoryExists(SourcePath) then
          FRootFolder:=IncludeTrailingPathDelimiter(SourcePath)
        else
         begin
          i:=Length(SourcePath);
          while (i<>0) and (SourcePath[i]<>PathDelim) do dec(i);
          FRootFolder:=Copy(SourcePath,1,i);
         end;
        i:=Length(FRootFolder)-1;
        while (i<>0) and (FRootFolder[i]<>PathDelim) do dec(i);
        FProjectName:=Copy(FRootFolder,i+1,Length(FRootFolder)-i-1);
        s:='<XxmWebProject>'#13#10#9'<ProjectName></ProjectName>'#13#10#9+
          '<CompileCommand>dcc32 -U[[HandlerPath]]public -Q [[ProjectName]].dpr</CompileCommand>'#13#10'</XxmWebProject>';
        f:=TFileStream.Create(FRootFolder+DataFileName,fmCreate);
        try
          f.Write(s[1],Length(s));
        finally
          f.Free;
        end;
       end
      else
        raise EXxmWebProjectNotFound.Create(StringReplace(
          SXxmWebProjectNotFound,'__',SourcePath,[]));
   end;

  FHandlerPath:=GetSelfPath;
  FProtoPathDef:=FHandlerPath+ProtoDirectory+PathDelim;
  FSrcFolder:=FRootFolder+SourceDirectory+PathDelim;

  Data:=CoDOMDocument.Create;
  Data.async:=false;
  Data.preserveWhiteSpace:=true;
  if not(Data.load(FRootFolder+DataFileName)) then
    raise EXxmWebProjectLoad.Create(StringReplace(
      SXxmWebProjectLoad,'__',FRootFolder+DataFileName,[])+
      #13#10+Data.parseError.reason);
  RootNode:=Data.documentElement;

  DataStartSize:=Length(Data.xml);

  x:=ForceNode(RootNode,'UUID','',1);
  if x.text='' then x.text:=CreateClassID;//other random info?

  x:=ForceNode(RootNode,'ProjectName','',1);
  if x.text='' then
   begin
    if FProjectName='' then
     begin
      i:=Length(DataFileName);
      while (i<>0) and (DataFileName[i]<>'.') do dec(i);
      FProjectName:=Copy(DataFileName,1,Length(DataFileName)-i-1);
     end;
    x.text:=FProjectName;
   end
  else
    FProjectName:=x.text;

  DataFiles:=ForceNode(RootNode,'Files','',1);

  if DirectoryExists(FRootFolder+ProtoDirectory) then
    FProtoPath:=FRootFolder+ProtoDirectory+PathDelim
  else
    FProtoPath:=FProtoPathDef;

  FParserValues:=DefaultParserValues;
  pv:=TXxmPageParserValues(0);
  while (pv<>pv_Unknown) do
   begin
    x:=RootNode.selectSingleNode('ParserValues/'+
      ParserValueElement[pv]) as IXMLDOMElement;
    if x<>nil then
     begin
      s:=StringReplace(StringReplace(x.text,
        '$v',FParserValues[pv].Code,[rfReplaceAll]),
        '$d',FParserValues[pv].Code,[rfReplaceAll]);
      l:=Length(s);
      j:=0;
      for i:=1 to l-1 do if (s[i]=#13) and (s[i+1]=#10) then inc(j);
      FParserValues[pv].Code:=s;
      FParserValues[pv].EOLs:=j;
     end;
    inc(pv);
   end;
end;

destructor TXxmWebProject.Destroy;
begin
  //Update was here before
  Data:=nil;
  Signatures.Free;
  inherited;
end;

procedure TXxmWebProject.Update;
var
  fn:AnsiString;
begin
  if Modified then
   begin
    if DataStartSize<>Length(Data.xml) then
     begin
      ForceNode(RootNode,'LastModified','',1).text:=
        FormatDateTime('yyyy-mm-dd"T"hh:nn:ss',Now);//timezone?
      Data.save(FRootFolder+DataFileName);
      Modified:=false;
     end;

    //save signatures
    try
      fn:=FSrcFolder+SignaturesFileName;
      SetFileAttributesA(PAnsiChar(fn),0);
      Signatures.SaveToFile(fn);
      //SetFileAttributesA(PAnsiChar(fn),FILE_ATTRIBUTE_HIDDEN or FILE_ATTRIBUTE_SYSTEM);
    except
      //silent?
    end;

   end;
end;

function TXxmWebProject.CheckFiles(Rebuild:boolean;ExtraFields:TStrings): boolean;
var
  p:TXxmProtoParser;
  q:TXxmPageParser;
  m:TXxmLineNumbersMap;
  xl:IXMLDOMNodeList;
  xFile,x:IXMLDOMElement;
  xn:IXMLDOMNode;
  fn,fnu,s,cid,uname,upath,uext:AnsiString;
  sl,sl1:TStringList;
  sl_i,i,cPathIndex,fExtIndex,fPathIndex:integer;
begin
  Result:=false;

  //TODO: setting autoaddfiles
  //TODO: autoremove files?

  Signatures:=TStringList.Create;
  try
    Signatures.LoadFromFile(FSrcFolder+SignaturesFileName);
  except
    //silent
  end;

  p:=TXxmProtoParser.Create;
  q:=TXxmPageParser.Create(FParserValues);
  m:=TXxmLineNumbersMap.Create;
  try
    sl:=TStringList.Create;
    sl1:=TStringList.Create;
    try

      xl:=DataFiles.selectNodes('File');
      try
        x:=xl.nextNode as IXMLDOMElement;
        while x<>nil do
         begin
          sl1.Add(x.getAttribute('ID'));
          x:=xl.nextNode as IXMLDOMElement;
         end;
      finally
        x:=nil;
        xl:=nil;
      end;

      ListFilesInPath(sl,FRootFolder);

      for sl_i:=0 to sl.Count-1 do
       begin
        fn:=sl[sl_i];
        cid:=GetInternalIdentifier(fn,cPathIndex,fExtIndex,fPathIndex);
        xFile:=ForceNode(DataFiles,'File',cid,2);
        i:=sl1.IndexOf(cid);
        if i<>-1 then sl1.Delete(i);
        //fn fit for URL
        fnu:=StringReplace(fn,'\','/',[rfReplaceAll]);
        x:=ForceNode(xFile,'Path','',-1);
        x.text:=fnu;
        //pascal unit name
        upath:=VarToStr(xFile.getAttribute('UnitPath'));
        uname:=VarToStr(xFile.getAttribute('UnitName'));
        if fExtIndex=0 then uext:='' else uext:=Copy(fn,fExtIndex+1,Length(fn)-fExtIndex);

        if uname='' then
         begin
          //unique counter for project
          uname:=Copy(cid,cPathIndex,Length(cid)-cPathIndex+1);
          if not(uname[1] in ['A'..'Z','a'..'z']) then uname:='x'+uname;
          i:=0;
          repeat
            inc(i);
            s:=uname+IntToStr(i);
            x:=DataFiles.selectSingleNode('File[@UnitName="'+s+'"]') as IXMLDOMElement;
          until (x=nil);
          uname:=s;
          xFile.setAttribute('UnitName',uname);
          Modified:=true;
         end;
        if upath='' then
         begin
          upath:=Copy(fn,1,fPathIndex);
          xFile.setAttribute('UnitPath',upath);
         end;

        //TODO: setting no pas subdirs?

        //TODO: proto signature? (setting?)
        s:=GetFileSignature(FRootFolder+fn);
        if Rebuild or (Signatures.Values[uname]<>s) or not(
          FileExists(FSrcFolder+upath+uname+DelphiExtension)) then
         begin
          Signatures.Values[uname]:=s;
          Modified:=true;
          BuildOutput(':'+FProjectName+':'+fn+':'+uname+':'+cid+#13#10);

          try
            //TODO: alternate proto? either XML tag or default file.
            s:=FRootFolder+fn+XxmProtoExtension;
            if not(FileExists(s)) then s:=FProtoPath+uext+DelphiExtension;
            if not(FileExists(s)) then s:=FProtoPathDef+uext+DelphiExtension;
            p.Parse(ReadString(s),ExtraFields);
            q.Parse(ReadString(FRootFolder+fn));
            m.Clear;
            repeat
              m.MapLine(p.NextEOLs,0);
              case p.GetNext of
                ptProjectName:p.Output(FProjectName);
                ptProjectPath:p.Output(FRootFolder);
                ptProtoFile:p.Output(FProtoPath+uext+DelphiExtension);
                ptFragmentID:p.Output(cid);
                ptFragmentUnit:p.Output(uname);
                ptFragmentAddress:p.Output(fnu);
                ptUsesClause:p.Output(q.AllSectionsCheckComma(psUses,m));
                ptFragmentDefinitions:p.Output(q.AllSections(psDefinitions,m));
                ptFragmentHeader:p.Output(q.AllSections(psHeader,m));
                ptFragmentBody:p.Output(q.BuildBody(m));
                ptFragmentFooter:p.Output(q.AllSections(psFooter,m));
                pt_Unknown:
                  if not p.Done then p.Output(ExtraFields.Values[p.GetTagLabel]);
                //else raise?
              end;
            until p.Done;
            //m.MapLine(0,q.TotalLines);//map EOF?
            ForceDirectories(FSrcFolder+upath);
            p.Save(FSrcFolder+upath+uname+DelphiExtension);
            if DoLineMaps then
              m.Save(FSrcFolder+upath+uname+LinesMapExtension);
            if not Result then
              Signatures.Values[SignaturesUpdateReasonKey]:=uname;
            Result:=true;
          except
            on e:Exception do
             begin
              e.Message:=fn+':'+uname+':'+cid+#13#10+e.Message;
              raise;
             end;
          end;
         end;
       end;

      //delete missing files
      for sl_i:=0 to sl1.Count-1 do
       begin
        cid:=sl1[sl_i];
        xFile:=ForceNode(DataFiles,'File',cid,2);
        //TODO: setting keep pas?
        uname:=VarToStr(xFile.getAttribute('UnitName'));
        upath:=VarToStr(xFile.getAttribute('UnitPath'));
        DeleteFile(FSrcFolder+upath+uname+DelphiExtension);
        DeleteFile(FSrcFolder+upath+uname+LinesMapExtension);
        //remove whitespace
        xn:=xFile.previousSibling;
        if (xn<>nil) and (xn.nodeType=NODE_TEXT) then
          xFile.parentNode.removeChild(xn);
        //remove file tag
        xFile.parentNode.removeChild(xFile);
        Modified:=true;
        if not Result then
          Signatures.Values[SignaturesUpdateReasonKey]:='<'+uname;
        Result:=true;
       end;
       
    finally
      sl.Free;
      sl1.Free;
      x:=nil;
      xFile:=nil;
    end;

    //check units
    xl:=DataFiles.selectNodes('Unit');
    try
      xFile:=xl.nextNode as IXMLDOMElement;
      while xFile<>nil do
       begin
        uname:=VarToStr(xFile.getAttribute('UnitName'));
        upath:=VarToStr(xFile.getAttribute('UnitPath'));
        fn:=upath+uname+DelphiExtension;
        s:=GetFileSignature(FRootFolder+fn);
        if Signatures.Values[uname]<>s then
         begin
          Signatures.Values[uname]:=s;
          Modified:=true;
          if not Result then
            Signatures.Values[SignaturesUpdateReasonKey]:=uname;
          Result:=true;
         end;
        xFile:=xl.nextNode as IXMLDOMElement;
       end;
    finally
      xFile:=nil;
      xl:=nil;
    end;
    //missing? delete?

    //check resource files
    xl:=DataFiles.selectNodes('Resource');
    try
      xFile:=xl.nextNode as IXMLDOMElement;
      while xFile<>nil do
       begin
        fn:=ForceNode(xFile,'Path','',-1).text;
        s:=GetFileSignature(FRootFolder+fn);
        uname:=':'+StringReplace(fn,'=','_',[rfReplaceAll]);
        if Signatures.Values[uname]<>s then
         begin
          Signatures.Values[uname]:=s;
          Modified:=true;
          if not Result then
            Signatures.Values[SignaturesUpdateReasonKey]:=uname;
          Result:=true;
         end;
        xFile:=xl.nextNode as IXMLDOMElement;
       end;
    finally
      xFile:=nil;
      xl:=nil;
    end;

    GenerateProjectFiles(Rebuild,ExtraFields);

  finally
    p.Free;
    q.Free;
    m.Free;
  end;
end;

function TXxmWebProject.GenerateProjectFiles(Rebuild:boolean;
  ExtraFields:TStrings):boolean;
var
  p:TXxmProtoParser;
  x:IXMLDOMElement;
  xl:IXMLDOMNodeList;
  fh:THandle;
  fd:TWin32FindDataA;
  fn1,fn2,s:AnsiString;
  i:integer;
begin
  Result:=false;
  //project files
  fn1:=FSrcFolder+FProjectName+DelphiProjectExtension;
  fn2:=FRootFolder+ProtoProjectPas;
  if Modified or Rebuild or not(FileExists(fn1)) or not(FileExists(fn2)) then
   begin
    p:=TXxmProtoParser.Create;
    try
      //[[ProjectName]].dpr
      BuildOutput(FProjectName+DelphiProjectExtension+#13#10);
      s:=FProtoPath+ProtoProjectDpr;
      if not(FileExists(s)) then s:=FProtoPathDef+ProtoProjectDpr;
      p.Parse(ReadString(s),ExtraFields);
      repeat
        case p.GetNext of
          ptProjectName:p.Output(FProjectName);
          ptProjectPath:p.Output(FRootFolder);
          ptProtoFile:p.Output(FProtoPath+ProtoProjectDpr);
          ptIterateFragment:
           begin
            xl:=DataFiles.selectNodes('File');
            x:=xl.nextNode as IXMLDOMElement;
            p.IterateBegin(x<>nil);
           end;
          ptIterateInclude:
           begin
            xl:=DataFiles.selectNodes('Unit');
            x:=xl.nextNode as IXMLDOMElement;
            p.IterateBegin(x<>nil);
           end;
          ptFragmentUnit:p.Output(VarToStr(x.getAttribute('UnitName')));
          ptFragmentPath:p.Output(VarToStr(x.getAttribute('UnitPath')));
          ptFragmentAddress:p.Output((x.selectSingleNode('Path') as IXMLDOMElement).text);
          ptIncludeUnit:p.Output(VarToStr(x.getAttribute('UnitName')));
          ptIncludePath:p.Output(VarToStr(x.getAttribute('UnitPath')));
          ptIterateEnd:
           begin
            x:=xl.nextNode as IXMLDOMElement;
            p.IterateNext(x<>nil);
           end;
          ptUsesClause:     p.Output(NodesText(RootNode,'UsesClause'));
          ptProjectHeader:  p.Output(NodesText(RootNode,'Header'));
          ptProjectBody:    p.Output(NodesText(RootNode,'Body'));
          ptProjectSwitches:p.Output(NodesText(RootNode,'Switches'));
          pt_Unknown:
            if not p.Done then p.Output(ExtraFields.Values[p.GetTagLabel]);
        end;
      until p.Done;
      ForceDirectories(FSrcFolder+'dcu');//TODO: setting "create dcu folder"?
      p.Save(fn1);

      //xxmp.pas
      if not(FileExists(fn2)) then
       begin
        BuildOutput(ProtoProjectPas+#13#10);
        s:=FProtoPath+ProtoProjectPas;
        if not(FileExists(s)) then s:=FProtoPathDef+ProtoProjectPas;
        p.Parse(ReadString(s),ExtraFields);
        repeat
          case p.GetNext of
            ptProjectName:p.Output(FProjectName);
            ptProjectPath:p.Output(FRootFolder);
            ptProtoFile:p.Output(FProtoPath+ProtoProjectPas);
            pt_Unknown:
              if not p.Done then p.Output(ExtraFields.Values[p.GetTagLabel]);
            //else raise?
          end;
        until p.Done;
        p.Save(fn2);
       end;

      //copy other files the first time (cfg,dof,res...)
      fh:=FindFirstFileA(PAnsiChar(FProtoPath+ProtoProjectMask),fd);
      if fh<>INVALID_HANDLE_VALUE then
       begin
        repeat
          s:=fd.cFileName;
          if s<>ProtoProjectDpr then
           begin
            i:=Length(s);
            while (i<>0) and (s[i]<>'.') do dec(i);
            fn1:=FSrcFolder+FProjectName+Copy(s,i,Length(s)-i+1);
            if not(FileExists(fn1)) then
             begin
              BuildOutput(fn1+#13#10);
              CopyFileA(PAnsiChar(FProtoPath+s),PAnsiChar(fn1),false);
             end;
           end;
        until not(FindNextFileA(fh,fd));
        Windows.FindClose(fh);
       end;

      //proto\Web.*
      fh:=FindFirstFileA(PAnsiChar(FProtoPathDef+ProtoProjectMask),fd);
      if fh<>INVALID_HANDLE_VALUE then
       begin
        repeat
          s:=fd.cFileName;
          if s<>ProtoProjectDpr then
           begin
            i:=Length(s);
            while (i<>0) and (s[i]<>'.') do dec(i);
            fn1:=FSrcFolder+FProjectName+Copy(s,i,Length(s)-i+1);
            if not(FileExists(fn1)) then
             begin
              BuildOutput(fn1+#13#10);
              CopyFileA(PAnsiChar(FProtoPathDef+s),PAnsiChar(fn1),false);
             end;
           end;
        until not(FindNextFileA(fh,fd));
        Windows.FindClose(fh);
       end;

    finally
      p.Free;
    end;
    Result:=true;
   end;
end;

function TXxmWebProject.ForceNode(element:IXMLDOMElement;
  const tagname,id:AnsiString;indentlevel:integer): IXMLDOMElement;
var
  ind:string;
  i:integer;
  isfirst:boolean;
begin
  if id='' then
    Result:=element.selectSingleNode(tagname) as IXMLDOMElement
  else
    Result:=element.selectSingleNode(tagname+'[@ID="'+id+'"]') as IXMLDOMElement;
  if Result=nil then
   begin
    //not found: add
    if indentlevel>-1 then
     begin
      isfirst:=element.firstChild=nil;
      ind:=#13#10;
      SetLength(ind,1+indentlevel);
      for i:=1 to indentlevel-1 do ind[2+i]:=#9;
      if isfirst then
        element.appendChild(element.ownerDocument.createTextNode(ind+#9))
      else
        element.appendChild(element.ownerDocument.createTextNode(#9));
     end;
    //then tag
    Result:=element.ownerDocument.createElement(tagname);
    if id<>'' then Result.setAttribute('ID',id);
    element.appendChild(Result);
    //and suffix whitespace on first elem
    if indentlevel>-1 then
      element.appendChild(element.ownerDocument.createTextNode(ind));
    Modified:=true;
   end;
end;

function TXxmWebProject.ReadString(const FilePath: AnsiString): AnsiString;
var
  f:TFileStream;
  l:int64;
begin
  f:=TFileStream.Create(FilePath,fmOpenRead or fmShareDenyNone);
  try
    l:=f.Size;
    SetLength(Result,l);
    f.Read(Result[1],l);
  finally
    f.Free;
  end;
end;

function TXxmWebProject.NodesText(element:IXMLDOMElement;const xpath:AnsiString):AnsiString;
var
  xl:IXMLDOMNodeList;
  x:IXMLDOMElement;
  s:TStringStream;
begin
  //CDATA? seems to work with .text
  xl:=element.selectNodes(xpath);
  x:=xl.nextNode as IXMLDOMElement;
  s:=TStringStream.Create('');
  try
    while x<>nil do
     begin
      s.WriteString(x.text);
      x:=xl.nextNode as IXMLDOMElement;
     end;
    Result:=
      StringReplace(
      StringReplace(
        s.DataString,
        #13#10,#10,[rfReplaceAll]),
        #10,#13#10,[rfReplaceAll]);
  finally
    s.Free;
  end;
end;

{$IF not Declared(TStartupInfoA)}
type
  TStartupInfoA=TStartupInfo;
{$IFEND}

function TXxmWebProject.Compile:boolean;
var
  cl:TStringList;
  cli:integer;
  clx,cld,d1:AnsiString;
  pi:TProcessInformation;
  si:TStartupInfoA;
  h1,h2:THandle;
  sa:TSecurityAttributes;
  f:TFileStream;
  d:array[0..$FFF] of AnsiChar;
  procedure GetNodesText(element: IXMLDOMElement; xpath, prefix: AnsiString);
  var
    xl:IXMLDOMNodeList;
    x:IXMLDOMNode;
    s1,s2:WideString;
  begin
    xl:=element.selectNodes(xpath);
    x:=xl.nextNode;
    while x<>nil do
     begin
      s1:=Trim(x.text);
      s2:=VarToStr((x as IXMLDOMElement).getAttribute('Path'));
      if s1<>'' then
        if s2='' then
          cl.Add(prefix+s1)
        else
         begin
          cl.Add('4'+s2);
          cl.Add('5'+s1);
         end;
      x:=xl.nextNode;
     end;
  end;
  function DoCommand(cmd,fld:AnsiString):boolean;
  var
    c:cardinal;
    running:boolean;
  begin
    if not(CreateProcessA(nil,PAnsiChar(AnsiString(
      StringReplace(
      StringReplace(
      StringReplace(
      StringReplace(
        cmd,
          '[[ProjectName]]',FProjectName,[rfReplaceAll]),
          '[[SrcPath]]',FSrcFolder,[rfReplaceAll]),
          '[[ProjectPath]]',FRootFolder,[rfReplaceAll]),
          '[[HandlerPath]]',FHandlerPath,[rfReplaceAll])
          //more?
      )),
      nil,nil,true,NORMAL_PRIORITY_CLASS,nil,PAnsiChar(fld),si,pi)) then
      //RaiseLastOSError;
      raise EXxmWebProjectCompile.Create('Error performing'#13#10'"'+cmd+'":'#13#10+SysErrorMessage(GetLastError));
    CloseHandle(pi.hThread);
    try
      running:=true;
      repeat
        if running then
          running:=WaitForSingleObject(pi.hProcess,50)=WAIT_TIMEOUT;
        if not PeekNamedPipe(h1,nil,0,nil,@c,nil) then c:=0;//RaiseLastOSError;
        if c<>0 then
         begin
          if not ReadFile(h1,d[0],$FFF,c,nil) then c:=0;//RaiseLastOSError;
          if c<>0 then
           begin
            f.Write(d[0],c);
            d[c]:=#0;
            BuildOutput(d);
           end;
         end;
      until not(running) and (c=0);
      if GetExitCodeProcess(pi.hProcess,c) then
        if c=0 then
          Result:=true
        else
         begin
          Result:=false;
          BuildOutput('Command "'+cmd+'" failed with code '+IntToStr(integer(c)));
         end
      else
       begin
        Result:=false;
        BuildOutput('GetExitCodeProcess('+cmd+'):'+SysErrorMessage(GetLastError));
       end;
    finally
      CloseHandle(pi.hProcess);
    end;
  end;
begin
  cl:=TStringList.Create;
  try
    GetNodesText(RootNode,'PreCompileCommand','1');
    GetNodesText(RootNode,'CompileCommand','2');
    GetNodesText(RootNode,'PostCompileCommand','3');
    if cl.Count=0 then
      Result:=true
    else
     begin
      d1:=GetCurrentDir;
      f:=TFileStream.Create(FRootFolder+FProjectName+ProjectLogExtension,fmCreate);
      try
        sa.nLength:=SizeOf(TSecurityAttributes);
        sa.lpSecurityDescriptor:=nil;
        sa.bInheritHandle:=true;
        if not(CreatePipe(h1,h2,@sa,$10000)) then RaiseLastOSError;
        ZeroMemory(@si,SizeOf(TStartupInfo));
        si.cb:=SizeOf(TStartupInfo);
        si.dwFlags:=STARTF_USESHOWWINDOW or STARTF_USESTDHANDLES;
        si.wShowWindow:=SW_HIDE;
        si.hStdOutput:=h2;
        si.hStdError:=h2;
        Result:=true;//default
        try
          cli:=0;
          while (cli<cl.Count) and Result do
           begin
            clx:=cl[cli];
            inc(cli);
            //TODO: switch for DoOutput(clx)?
            case clx[1] of
              '1','3':cld:=FRootFolder;
              '2':cld:=FSrcFolder;
              '4':cld:=Copy(clx,2,Length(clx)-1);
              '5':;//assert cld set by preceding '4' (see GetNodesText)
            end;
            if clx[1]<>'4' then
             begin
              SetCurrentDir(cld);
              Result:=DoCommand(Copy(clx,2,Length(clx)-1),cld);
             end;
           end;
        finally
          CloseHandle(h1);
          CloseHandle(h2);
        end;
      finally
        f.Free;
        SetCurrentDir(d1);
      end;
     end;
  finally
    cl.Free;
  end;
end;

procedure TXxmWebProject.BuildOutput(const Msg: AnsiString);
begin
  FOnOutput(Msg);
end;

function TXxmWebProject.ResolveErrorLines(
  const BuildOutput: AnsiString): AnsiString;
var
  sl_in,sl_out:TStringList;
  sl_x:integer;
  s,t:string;
  i,j,k,l:integer;
  map:TXxmLineNumbersMap;
  x:IXMLDOMElement;
begin
  //TODO: call ResolveErrorLines from xxmConv also
  map:=TXxmLineNumbersMap.Create;
  sl_in:=TStringList.Create;
  sl_out:=TStringList.Create;
  try
    sl_in.Text:=BuildOutput;
    for sl_x:=0 to sl_in.Count-1 do
     begin
      s:=sl_in[sl_x];
      if (s='') or (s[2]=':') or (s[2]='\') then i:=0 else i:=Pos('.pas(',s);
      if i<>0 then
       begin
        k:=i;
        while (k<>0) and (s[k]<>'\') do dec(k);
        inc(i,5);
        j:=i;
        l:=Length(s);
        while (j<=l) and (s[j]<>')') do inc(j);
        try
          t:=Copy(s,1,i-2);
          map.Load(ChangeFileExt(FSrcFolder+t,LinesMapExtension));
          x:=DataFiles.selectSingleNode('File[@UnitName="'+
            Copy(s,k+1,i-k-6)+'"]/Path') as IXMLDOMElement;
          if x<>nil then t:=x.text;
          s:=t+'['+map.GetXxmLines(StrToInt(Copy(s,i,j-i)))+
            ']'+Copy(s,j+1,Length(s)-j);
        except
          //silent
        end;
       end;
      if s<>'' then sl_out.Add(s);
     end;
    Result:=sl_out.Text;
  finally
    sl_in.Free;
    sl_out.Free;
    map.Free;
  end;
end;

end.
