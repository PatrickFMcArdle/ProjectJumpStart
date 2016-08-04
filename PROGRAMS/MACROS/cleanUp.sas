/****************************************************
Program: macro_cleanUp.sas
Author: Patrick F. McArdle
Date: 1 July 2016

Call with: %cleanUp;

This macro 
	clears titles and footnotes
	and cleans up 
		global macro variables
		filenames 
		libnames
		datasets in the work library
	thar start with an underscore.

***************************************************/

%macro cleanUp;

* Clear title and footnotes;
title;
footnote;

* Clear global macro variables;
data _mvtodelete;
   set sashelp.vmacro;
   where scope eq 'GLOBAL' and name eq: "_" and offset eq 0;
run;
data _null_;
   set _mvtodelete;
   call symdel(name);
run;   

* Clear filenames;
data _filerefToDelete;
	set sashelp.vextfl;
	where fileref eq: "_";
run;
data _null_ ;
	set _filerefToDelete;
	rc=filename(fileref, "");
run;

* Clear libnames;
data _libToDelete;
	set sashelp.vlibnam;
	where libname eq: "_";
run;
data _null_ ;
	set _libToDelete;
	rc=libname(libname);
run;

* Delete datasets in the work directory;
proc datasets nolist; delete _: ; run;

%mend cleanup;



