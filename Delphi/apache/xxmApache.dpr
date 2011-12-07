library xxmApache;

{$R '..\common\xxmData.res' '..\common\xxmData.rc'}

uses
  HTTPD2 in 'HTTPD2.pas',
  xxm in '..\bin\public\xxm.pas',
  xxmHeaders in '..\bin\public\xxmHeaders.pas',
  xxmParUtils in '..\common\xxmParUtils.pas',
  xxmParams in '..\common\xxmParams.pas',
  xxmApacheModule in 'xxmApacheModule.pas',
  xxmApacheContext in 'xxmApacheContext.pas',
  xxmCommonUtils in '..\common\xxmCommonUtils.pas',
  xxmPReg in '..\common\xxmPReg.pas',
  xxmHttpPReg in '..\http\xxmHttpPReg.pas',
  xxmApacheClientStream in 'xxmApacheClientStream.pas',
  xxmApachePars in 'xxmApachePars.pas',
  MSXML2_TLB in '..\common\MSXML2_TLB.pas',
  xxmContext in '..\common\xxmContext.pas';

{$R *.RES}

end.
