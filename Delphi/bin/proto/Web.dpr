library [[ProjectName]];

{
  --- ATTENTION! ---

  This file is re-constructed when the xxm source file changes.
  Any changes to this file will be overwritten.
  If you require changes to this file that can not be defined
  in the xxm source file, set up an alternate prototype-file.

  Prototype-file used:
  "[[ProtoFile]]"
  $Rev: 273 $ $Date: 2013-02-22 22:34:20 +0100 (vr, 22 feb 2013) $
}

[[ProjectSwitches]]
uses
	[[@Include]][[IncludeUnit]] in '..\[[IncludePath]][[IncludeUnit]].pas',
	[[@]][[@Fragment]][[FragmentUnit]] in '[[FragmentPath]][[FragmentUnit]].pas', {[[FragmentAddress]]}
	[[@]][[UsesClause]]
	xxmp in '..\xxmp.pas';

{$E xxl}
[[ProjectHeader]]
exports
	XxmProjectLoad;
begin
[[ProjectBody]]
end.
