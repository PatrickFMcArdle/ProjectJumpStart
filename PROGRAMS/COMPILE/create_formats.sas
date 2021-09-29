* Delete the catalog if it exists, so it can bre recreated;
proc datasets library=DW nolist; delete frmts / memtype=catalog; run;


proc format library = DW.frmts;
	value yesNoF 
		1='Yes' 
		0='No'
	;
run;
quit;
