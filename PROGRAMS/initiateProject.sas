/****************************************************
Program: autoexec_initiateProject.sas
Author: Patrick F. McArdle
Date: 1 August 2016

This program is meant to be included in the autoexec process flow.

It performs the following:
	- Assigns the project directory as the directory the project file is stored in
	- Assigns libraries
	- Searches for formats stored in the main project library
	- loads macros used in the rest of the project

Ensure the autoexec process flow is run when the project opens by:
Tools -> Options -> General -> Automatically run Autoexec process flow when project opens


***************************************************/

* Assign root directory;
%let PROJECTdir = 	%sysfunc(substr(%sysfunc(tranwrd(%sysfunc(dequote(&_clientprojectpath)),
									 %sysfunc(dequote(&_clientprojectname)),
									 %sysfunc(dequote('')))),1,
					%sysfunc(length(%sysfunc(tranwrd(%sysfunc(dequote(&_clientprojectpath)),
									 %sysfunc(dequote(&_clientprojectname)),
									 %sysfunc(dequote(''))))))-1));

* Create directory paths;
%let PROGRAMdir 	= &PROJECTdir\PROGRAMS;
%let MACROdir 		= &PROJECTdir\PROGRAMS\MACROS;
%let DOCUMENTdir  	= &PROJECTdir\DOCUMENTATION;
%let RAWDATAdir 	= &PROJECTdir\DATA\RAW DATA;

* Assign libraries;
libname PROJ 		"&PROJECTdir\DATA\DATA WAREHOUSE";
libname PROJsa		"&PROJECTdir\DATA\STAGING AREA";

* Search for formats stored in the main project library;
options fmtsearch=(PROJ);

* Compile Macros;
options mautosource sasautos=("&MACROdir");

quit;
