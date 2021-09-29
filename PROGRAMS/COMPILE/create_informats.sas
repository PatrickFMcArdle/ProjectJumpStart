/***************************
Program : create_informats.sas
Author  : Patrick F. McArdle 
Date    : 1 July 2016

This program creates a informats to be used 

**************************/
* Delete the catalog if it exists, so it can bre recreated;
proc datasets library=DW nolist; delete infrmts / memtype=catalog; run;

proc format library = DW.infrmts;
	invalue messyDate
		"/^\d{1,2}\D\d{1,2}\D\d{4}/" (regexp)	= [mmddyy10.]    
		"/^\d{4}/" (regexp) 					= [B8601DA4.]
		other 									= [anydtdte32.]
	;
run;

quit;
