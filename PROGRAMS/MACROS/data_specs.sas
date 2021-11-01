/*------------------------------------------------------------------*
| MACRO NAME  : data_specs
| SHORT DESC  : Creates a specifications document on a library of
|               datasets
*------------------------------------------------------------------*
| CREATED BY  : Meyers, Jeffrey                 (07/28/2016 3:00)
*------------------------------------------------------------------*
| VERSION UPDATES:
| 04/22/2019:
|   Added the option CONDESED to the fORMAT parameter
|   Turned off the listing output when tables print
|   Turned on NORESULTS when tables print
| 04/28/2017:
|   Fixed the macro mapping its own temporary datasets when referencing
      the WORK library.
| 03/07/2017:
|   Streamlined code to run faster
|   Added progress notes to log
|   Added unformatted values to discrete summary
| 08/03/2016: Initial Release
*------------------------------------------------------------------*
| PURPOSE
| Create a data specifications sheet for a designated library.  Allows
| for a quick look at the data within a library or allows for a simple
| data dictionary to be built.
| The macro outputs a report with three types of tables.  The first is
| a listing of the datasets included in the library along with
| the number of rows, number of unique indexes, and number of variables.
| The second table is the number of variables that exist across multiple
| datasets along with any different labels given to them.  The last type 
| of table is built for each dataset on a separate tab that lists the
| variables and specs (label, format, and values) for each.
|
| 1.0: REQUIRED PARAMETERS
| LIBN = Specifies the library to generate the report on
| OUT = Designates where to save the file.  Must have path and file name
|       in XLSX format
| 
| 2.0: Optional PARAMETERS
| INDEX = Allows the designation of multiple index variables to determine
|         number of patients or other interest within a dataset.
| CAT_THRESHOLD = Determines the number of variable levels that can exist
|                 before the program will not output the frequency and 
|                 percentage of each level.  If numeric variable exceeds
|                 this many levels then distribution statistics will be 
|                 used instead.  Must be greater than or equal to 0.
| WHERE = Allows a where clause to be used on the dictionary table to 
|         subset.
| FORMAT = For the summary of individual datasets this determines if the
|          variables will be listed in CONDENSED (one row per variable),
|          LONG (one column), or WIDE (One row) format.  Options are LONG, 
|          CONDENSED, and WIDE. Default is LONG.
| ORDER = Determines how the variables will be ordered in the dataset summary
|         tabs.  VARNUM will order by the variable order in the dataset and
|         NAME will order alphabetically.  Options are VARNUM and NAME.
          Default is VARNUM.
*------------------------------------------------------------------*
| OPERATING SYSTEM COMPATIBILITY
| SAS v9.4 or Higher: Yes
*------------------------------------------------------------------*
| MACRO CALL
|
| %data_specs (
|            LIBN=,
|            OUT=,
|            INDEX=,
|            CAT_THRESHOLD=,
|            WHERE=,
|            FORMAT=,
|            ORDER=
|          );
*------------------------------------------------------------------*
| EXAMPLES
*------------------------------------------------------------------*
| This program is free software; you can redistribute it and/or
| modify it under the terms of the GNU General Public License as
| published by the Free Software Foundation; either version 2 of
| the License, or (at your option) any later version.
|
| This program is distributed in the hope that it will be useful,
| but WITHOUT ANY WARRANTY; without even the implied warranty of
| MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
| General Public License for more details.
*------------------------------------------------------------------*/

%macro data_specs(
    /*Required Parameters*/
    libn=,out=,
    /*Optional Parameters*/
    index=,cat_threshold=10,where=,format=long,order=varnum);



    /**Save current options to reset after macro runs**/
    %local _mergenoby _notes _quotelenmax _starttime _listing;
    %let _starttime=%sysfunc(time());
    %let _notes=%sysfunc(getoption(notes));
    %let _mergenoby=%sysfunc(getoption(mergenoby));
    %let _quotelenmax=%sysfunc(getoption(quotelenmax));
    
    /*Set Options*/
    options NOQUOTELENMAX nonotes mergenoby=nowarn;
    /**See if the listing output is turned on**/
    proc sql noprint;
        select 1 into :_listing separated by '' from sashelp.vdest where upcase(destination)='LISTING';
    quit;
    
    /**Process Error Handling**/
    %if &sysver < 9.4 %then %do;
        %put ERROR: SAS must be version 9.4 or later;
        %goto errhandl;
    %end;     
    %else %if %sysevalf(%superq(libn)=,boolean)=1 %then %do;
        %put ERROR: LIBN parameter is required;
        %put ERROR: Please enter a valid library;
        %goto errhandl;
    %end;  
    %else %if %sysfunc(libref(&libn))^=0 %then %do;
        %put ERROR: Library &libn is not assigned;
        %put ERROR: Please enter a valid libname;
        %goto errhandl;
    %end;
    
    %local nerror;
    %let nerror=0;
    /**Error Handling on Global Parameters**/
    %macro _gparmcheck(parm, parmlist);          
        %local _test _z;
        /**Check if values are in approved list**/
        %do _z=1 %to %sysfunc(countw(&parmlist,|,m));
            %if %qupcase(%superq(&parm))=%qupcase(%scan(&parmlist,&_z,|,m)) %then %let _test=1;
        %end;
        %if &_test ^= 1 %then %do;
            /**If not then throw error**/
            %put ERROR: (Global: %qupcase(&parm)): %superq(&parm) is not a valid value;
            %put ERROR: (Global: %qupcase(&parm)): Possible values are &parmlist;
            %let nerror=%eval(&nerror+1);
        %end;
    %mend;
    /*Data display format*/
    %_gparmcheck(format,condensed|wide|long)
    /*Variable Order*/
    %_gparmcheck(order,varnum|name)
    /**Error Handling on Global Model Numeric Variables**/
    %macro _gnumcheck(parm, min);
        /**Check if missing**/
        %if %sysevalf(%superq(&parm)^=,boolean) %then %do;
            %if %sysfunc(notdigit(%sysfunc(compress(%superq(&parm),-.)))) > 0 %then %do;
                /**Check if character value**/
                %put ERROR: (Global: %qupcase(&parm)) Must be numeric.  %qupcase(%superq(&parm)) is not valid.;
                %let nerror=%eval(&nerror+1);
            %end;
            %else %if %superq(&parm) < &min %then %do;
                /**Makes sure number is not less than the minimum**/
                %put ERROR: (Global: %qupcase(&parm)) Must be greater than %superq(min). %qupcase(%superq(&parm)) is not valid.;
                %let nerror=%eval(&nerror+1);
            %end;
        %end;
        %else %do;
            /**Throw Error**/
            %put ERROR: (Global: %qupcase(&parm)) Cannot be missing;
            %put ERROR: (Global: %qupcase(&parm)) Possible values are numeric values greater than or equal to %superq(min);
            %let nerror=%eval(&nerror+1);           
        %end;       
    %mend;
    /*Categories cut-off*/
    %_gnumcheck(cat_threshold,0);
    
    /*** If any errors exist, stop macro and send to end ***/
    %if &nerror > 0 %then %do;
        %put ERROR: &nerror pre-run errors listed;
        %put ERROR: Macro DATA_SPECS will cease;
        %goto errhandl;
    %end;    
    
    /*Creates dictionary table for library*/
    proc contents data=&libn.._all_
        out=_specs_ (%if %sysevalf(%superq(where)^=,boolean) %then %do;
                     where=(&where)
                     %end;) noprint;
    run;
    /*Sorts by VARNUM or NAME*/
    proc sort data=_specs_;
        by memname %superq(order);
    run;
    
    /**Set up Data sets to insert into**/
    proc sql;
        /**Data set for specifications**/
        create table _data_specs_
            (data_id num,
            dsn char(300) 'Data Set Name (Label)',
            var_name char(40) 'Name',
            type char(10) 'Type',
            length char(20) 'Length', 
            format char(40) 'Format',
            informat char(40) 'Informat',
            label char(256) 'Label',
            cat_values char(10000) 'Category Values',
            spec char(30) 'Specification',
            value char(10000) 'Value');
        /**Data set for high level summary of library**/
        create table _libn_summary_
            (dsn char(300) 'Data Set Name',
            obs num 'Observations',
            unique_index num "Unique Index Values (%qupcase(%sysfunc(tranwrd(&index,|,%str( or )))))",
            variables num 'Number of Variables');
        /**Data set for variables in multiple datasets**/
        create table _var_summary_
            (var_name char(40) 'Variable Name',
            dsn_list char(10000) 'Datasets Containing Variable',
            labels char(10000) 'Variable Label(s)');            
        quit;
        
    
    /*Gets list of datasets within library*/
    %local datalists;
    proc sql noprint;
        select distinct memname into :datalist separated by ' '
            from _specs_;
        quit;
    /*Loops between datasets in library*/
    %local i j varlist curr_index n_numeric;
    %do i = 1 %to %sysfunc(countw(&datalist,%str( )));
        %put Progress: %scan(&datalist,&i,%str( )): &i of %sysfunc(countw(&datalist,%str( )));
        %local varlist&i;
        %let varlist&i=;
        /*Creates list of all variables in data set*/
        proc sql noprint;
            select name into :varlist&i separated by ' '
                from _specs_ where upcase(memname)=upcase("%scan(&datalist,&i,%str( ))");
        quit;
        %let curr_index=;
        /*Determine if index variables are present*/
        %local index_varn index_set j k l;
        %let index_varn=;%let index_set=;
        %if %sysevalf(%superq(index)^=,boolean) %then %do j = 1 %to %sysfunc(countw(&&varlist&i,%str( ))); 
            %do k=1 %to %sysfunc(countw(%superq(index),|));
                %if %sysevalf(%superq(index_set)=,boolean) or %sysevalf(%superq(index_set)=&k,boolean) %then %do l = 1 %to %sysfunc(countw(%scan(&index,&k,|),%str( )));
                    %if %sysevalf(%qupcase(%scan(&&varlist&i,&j,%str( )))=%qupcase(%qscan(%qscan(&index,&k,|),&l,%str( ))),boolean) %then %let index_varn=&index_varn &j;
                %end;
            %end;
        %end;
        /*Creates macro variables for variable format and type*/
        data __temp;
            set &libn..%scan(&datalist,&i,%str( ));
            if _n_=1 then do;
                %do j = 1 %to %sysfunc(countw(&&varlist&i,%str( )));
                    %local v&j.format v&j.type;
                    call symput("v&j.format",vformat(%scan(&&varlist&i,&j,%str( ))));
                    call symput("v&j.type",vtype(%scan(&&varlist&i,&j,%str( ))));
                %end;
            end;
            rename %do j = 1 %to %sysfunc(countw(&&varlist&i,%str( ))); %scan(&&varlist&i,&j,%str( ))=_var&j %end;;
        run;
        %if %sysevalf(%superq(index_varn)^=,boolean) %then %do;
            proc sort data=__temp;
                by %do j=1 %to %sysfunc(countw(&index_varn,%str( ))); _var%scan(&index_varn,&j,%str( )) %end;;
            run;
            
            data __temp;
                set __temp;
                by %do j=1 %to %sysfunc(countw(&index_varn,%str( ))); _var%scan(&index_varn,&j,%str( )) %end;;
                if first._var%scan(&index_varn,&j-1,%str( )) then _index_+1;
            run;
        %end;
        /*Creates variable lists*/
        proc sql noprint;
            /*Finds number of numeric values*/
            select sum(ifn(type=1,1,0)) into :n_numeric separated by ' '
                from _specs_ where upcase(memname)=upcase("%scan(&datalist,&i,%str( ))");
                
            /*Inserts current dataset specs into table*/
            insert into _data_specs_
                select &i,
                strip(memname)||
                   case(memlabel)
                       when '' then ''
                else ' ('||strip(memlabel)||')' end,
                name,
                case(type)
                  when 1 then 'Numeric'
                  when 2 then 'Character'
                else '' end,
                strip(put(length,12.)),
                format,
                informat,
                label,
                '',
                '',
                ''
                from _specs_ where upcase(memname)=upcase("%scan(&datalist,&i,%str( ))");
            
            /*Inserts high level dataset specs into library table*/
            insert into _libn_summary_
                select a.dsn,
                a.nobs,
                b.unique_index,
                a.n
                from (select distinct &i as data_id, strip(memname)||
                   case(memlabel)
                       when '' then ''
                    else ' ('||strip(memlabel)||')' end as dsn,nobs,count(distinct name) as n from _specs_
                         where upcase(memname)=upcase("%scan(&datalist,&i,%str( ))") group by nobs) as a left join
                  %if %sysevalf(%superq(index_varn)^=,boolean) %then %do;
                     (select distinct &i as data_id,"%scan(&datalist,&i,%str( ))" as dsn,count(distinct _index_) as unique_index 
                        from __temp) as b
                      %end;
                  %else %do;
                     (select distinct &i as data_id,"%scan(&datalist,&i,%str( ))" as dsn,0 as unique_index
                          from &libn..%scan(&datalist,&i,%str( ))) as b
                     %end;
                  on a.data_id=b.data_id;
            /*Initializes and creates macro variables for levels of each variable*/
            %local n nothing;
            %do j = 1 %to %sysfunc(countw(&&varlist&i,%str( )));
               %local n_&j levels_&j;
               %let n_&j=;%let levels_&j=;
               %end;
            select %do j = 1 %to %sysfunc(countw(&&varlist&i,%str( )));
                count(distinct _var&j),
                %end;
                count(*) into
                %do j = 1 %to %sysfunc(countw(&&varlist&i,%str( )));
                  :n_&j,
                  %end; :n from __temp;
               
        quit;
        
        %local n_frq n_dist n_miss;
        %let n_frq=;%let n_dist=;%let n_miss=;
        %if &n > 0 %then %do;
            /**Determine how each variable should be summarized**/
            %do j = 1 %to %sysfunc(countw(&&varlist&i,%str( )));
                %if %superq(v&j.type)=N %then %do;
                    %if %superq(n_&j) <= &cat_threshold %then %let n_frq=&n_frq &j;
                    %else %let n_dist=&n_dist &j;                    
                %end;
                %else %do;
                    %if %superq(n_&j) <= &cat_threshold %then %let n_frq=&n_frq &j;
                    %else %let n_miss=&n_miss &j;
                %end;
            %end;
            ods select none;
            ods noresults;     
            /*Creates frequencies for all variables under the threshold*/  
            %if %sysevalf(%superq(n_frq)^=,boolean) %then %do;
                proc freq data=__temp;
                    table %do j = 1 %to %sysfunc(countw(&n_frq,%str( ))); 
                              _var%scan(&n_frq,&j,%str( ))
                          %end; / missing;
                    ods output onewayfreqs=_frqs_;
                run; 
            %end;  
            /*Creates distributions for all numeric variables above the threshold*/    
            %if %sysevalf(%superq(n_dist)^=,boolean) %then %do;
                proc means data=__temp missing noprint;
                    var %do j = 1 %to %sysfunc(countw(&n_dist,%str( ))); 
                             _var%scan(&n_dist,&j,%str( ))
                         %end;;
                    output out=_distribution_ n= nmiss= mean= std= median= min= max= / autoname;
                run;
            %end;
            ods select all;
            ods results;
        %end;
        proc sql noprint;            
            /*Creates macro variables for values of variables*/ 
            %do j = 1 %to %sysfunc(countw(&&varlist&i,%str( )));
                /*If number of distinct levels are less than the threshold*/ 
                %if &n > 0 and %superq(n_&j) <= &cat_threshold %then %do;
                    select case (missing(f__var&j))
                        when 1 then 'Missing'
                        else case 
                             when %if %superq(v&j.type)=N %then %do; strip(put(_var&j,best12.)) %end;
                                  %else %do; strip(_var&j) %end; = strip(f__var&j) then strip(f__var&j)
                             else %if %superq(v&j.type)=N %then %do; strip(put(_var&j,best12.)) %end;
                                  %else %do; strip(_var&j) %end; ||' (' || strip(f__var&j)||')' end end
                        ||': '||strip(put(frequency,comma12.))||' ('||strip(put(percent,12.1))||'%)'
                        into :levels_&j separated by '^n '
                        from _frqs_ where upcase(table)=upcase("Table _var&j");
                    %end;
                %else %if &n > 0 and %superq(v&j.type)=N and %sysevalf(%superq(n_dist)^=,boolean) %then %do;
                    /*If number of distinct levels are greater than the threshold and variable is numeric*/ 
                    select 'N (N Missing): '||strip(put(_var&j._n,comma12.0))||' ('||strip(put(_var&j._nmiss,comma12.0))||')^n '||
                        'Median: '||strip(Put(_var&j._median,&&v&j.format))||'^n '||
                        'Range: '||strip(put(_var&j._min,&&v&j.format))||' - '||strip(put(_var&j._max,&&v&j.format))
                        into :levels_&j separated by '' from _distribution_;
                %end;
                /*Otherwise leave blank*/ 
                %else %do;
                    select 'N (N Missing): ' ||strip(put(sum(^missing(_var&j)),12.0)) ||' ('||
                        strip(put(sum(missing(_var&j)),12.0)) ||')' into :levels_&j separated by ''
                        from __temp;
                %end;
            %end;
            /*Delete temporary datasets*/ 
            %if %sysevalf(%superq(n_frq)^=,boolean) %then %do;
                drop table _frqs_;
            %end;
            %if %sysevalf(%superq(n_dist)^=,boolean) %then %do;
                drop table _distribution_;
            %end;
            
            /*Update formats and values into the specifications data set*/ 
            update _data_specs_
                set format=case (upcase(var_name))
                %do j = 1 %to %sysfunc(countw(&&varlist&i,%str( )));
                  when upcase("%scan(&&varlist&i,&j,%str( ))") then "%superq(v&j.format)"
                  %end;
                else '' end,
                cat_values=case (upcase(var_name))
                %do j = 1 %to %sysfunc(countw(&&varlist&i,%str( )));
                  when upcase("%scan(&&varlist&i,&j,%str( ))") then "%superq(levels_&j)"
                  %end;
                else '' end    
                where strip(scan(upcase(dsn),1,'('))=upcase("%scan(&datalist,&i,%str( ))");
            drop table __temp;
        quit;
    %end;
    /*Transposes some specifications to long form*/ 
    data _data_specs_;
        set _data_specs_;

        spec='Variable';value=strip(var_name);output;
        spec='Label';value=strip(label);output;
        spec='Format';
        if upcase(type)='NUMERIC' then value='Numeric with format '||strip(format);
        else if upcase(type)='CHARACTER' then value='Character string of length '||strip(length)||' and format '||
            strip(format);
        output;
        %if %sysevalf(%qupcase(&format)=LONG, boolean) %then %do; if ^missing(cat_values) then do; %end;
            spec='Values';value=strip(cat_values);output;
             %if %sysevalf(%qupcase(&format)=LONG, boolean) %then %do; end; %end;
    run;
    /*Transpose into condensed form*/
    proc transpose data=_data_specs_ out=_data_specs_condensed (drop=_name_ _label_);
        by data_id notsorted var_name;
        id spec;
        var value;
    run;    
    /*Merges variables into wide dataset*/ 
    %if %sysevalf(%qupcase(&format)=WIDE, boolean) %then %do; 
        %do i = 1 %to %sysfunc(countw(&datalist,%str( )));
            data _data_specs_wide&i;
                merge             
                    %do j = 1 %to %sysfunc(countw(&&varlist&i,%str( )));
                        _data_specs_ (keep=data_id dsn spec value var_name where=(data_id=&i and var_name&j="%scan(%superq(varlist&i),&j,%str( ))")
                                      rename=(var_name=var_name&j value=value&j))
                    %end;;
            run;
        %end;
        data _data_specs_wide;
            set %do i = 1 %to %sysfunc(countw(&datalist,%str( ))); _data_specs_wide&i %End;;
        run;
    %end;
    /*Completes variables across multiple datasets table*/
    proc sql noprint;
        %let multilist=;
        /*Find variables in multiple datasets*/
        select distinct upcase(name) into :multilist separated by ' '
            from _specs_ where upcase(name) ^in("%sysfunc(tranwrd(%upcase(&index),%str( ), " "))")
            group by upcase(name) having count(*)>1;
        /*Find Dataset name and label for variables*/
        %do i = 1 %to %sysfunc(countw(&multilist,%str( )));
            %local dlist&i dlabels&i;
            %let dlist&i=;%let dlabels&i=;
            select memname into :dlist&i separated by ', '
                from _specs_ where upcase(name)="%scan(&multilist,&i,%str( ))";
            select distinct strip(label) into :dlabels&i separated by '^n'
                from _specs_ where upcase(name)="%scan(&multilist,&i,%str( ))";
            %end;
        /*Insert values into dataset*/
        %if %sysevalf(%superq(multilist)^=,boolean) %then %do;
            insert into _var_summary_
                %do i = 1 %to %sysfunc(countw(&multilist,%str( )));
                    set var_name="%scan(&multilist,&i,%str( ))",
                        dsn_list="%superq(dlist&i)",
                        labels="%superq(dlabels&i)"
                    %end;
                ;
        %end;       
    quit;


    /*Print out datasets*/
    ods escapechar='^';
    %if &_listing=1 %then %do;
        ods listing close;
    %end;
    ods noresults;
    /*First tab has library summary and variables in multiple datasets summary*/
    ods excel file="&out" options(sheet_name="Library %qupcase(&libn) - Summary" sheet_interval='none');
    proc report data=_libn_summary_ nowd
            style(header)={background=white just=c fontfamily='Times New Roman' fontsize=9pt}
            style(column)={background=white just=left vjust=top fontfamily='Times New Roman' fontsize=9pt};
            columns ("Summary of Datasets within Library - %qupcase(&libn)" dsn obs unique_index variables);

            define dsn / display width=50;
            define unique_index / display width=50 center;
            define obs / display width=50 center;
            define variables / display width=50 center;

            compute variables;
                shade+1;
                if mod(shade,2)=0 then call define(_row_,'style/merge','style={background=greyef}');
                endcomp;
        run;
    proc report data=_var_summary_ nowd
            style(header)={background=white just=c fontfamily='Times New Roman' fontsize=9pt}
            style(column)={background=white just=left vjust=top fontfamily='Times New Roman' fontsize=9pt};
            columns ("Variables that Exist Across Multiple Datasets" var_name dsn_list labels);

            define dsn_list / display width=50;
            define var_name / display width=50;
            define labels / display width=50;

            compute labels;
                shade+1;
                if mod(shade,2)=0 then call define(_row_,'style/merge','style={background=greyef}');
                endcomp;
        run;
        
    
    /*Print one tab for each dataset: either long or wide form*/
    %do i = 1 %to %sysfunc(countw(&datalist,%str( )));
        %if %sysevalf(%qupcase(&format)=LONG, boolean) %then %do;
            ods excel options(sheet_name="Dataset - %scan(&datalist,&i,%str( ))" sheet_interval='table' frozen_headers='2');
            proc report data=_data_specs_ nowd
                style(header)={background=white just=c fontfamily='Times New Roman' fontsize=9pt}
                style(column)={background=white just=left vjust=top fontfamily='Times New Roman' fontsize=9pt};
                columns ("Dataset Name: %scan(&datalist,&i,%str( ))" var_name spec value);

                define var_name / order order=data width=50 noprint;
                define spec / display width=50;
                define value / display width=50;

                compute value;
                    if ^missing(var_name) then do;
                        shade+1;
                        call define(_row_,'style/merge','style={bordertopwidth=0.5pt bordertopcolor=black bordertopstyle=solid}');
                        end;
                    if mod(shade,2)=0 then call define(_row_,'style/merge','style={background=greyef}');
                    endcomp;
                where data_id=&i;
            run;
        %end;
        %else %if %sysevalf(%qupcase(&format)=CONDENSED, boolean) %then %do;
            ods excel options(sheet_name="Dataset - %scan(&datalist,&i,%str( ))" sheet_interval='table' frozen_headers='2');
            proc report data=_data_specs_condensed nowd
                style(header)={background=white just=c fontfamily='Times New Roman' fontsize=9pt}
                style(column)={background=white just=left vjust=top fontfamily='Times New Roman' fontsize=9pt};
                columns ("Dataset Name: %scan(&datalist,&i,%str( ))" var_name label format values);

                define var_name / order order=data width=50 'Variable';
                define label / display width=50;
                define format / display width=50;
                define values / display width=50;

                compute values;
                    shade+1;
                    call define(_row_,'style/merge','style={bordertopwidth=0.5pt bordertopcolor=black bordertopstyle=solid}');
                    if mod(shade,2)=0 then call define(_row_,'style/merge','style={background=greyef}');
                    endcomp;
                where data_id=&i;
            run;
        %end;
        %else %if %sysevalf(%qupcase(&format)=WIDE, boolean) %then %do;
            ods excel options(sheet_name="Dataset - %scan(&datalist,&i,%str( ))" sheet_interval='table' frozen_headers='1' frozen_rowheaders='1');
            proc report data=_data_specs_wide nowd
                style(header)={background=white just=c fontfamily='Times New Roman' fontsize=9pt}
                style(column)={background=white just=left vjust=top fontfamily='Times New Roman' fontsize=9pt};
                columns ("Dataset Name: %scan(&datalist,&i,%str( ))" spec 
                
                %do j = 1 %to %sysfunc(countw(&&varlist&i,%str( ))); 
                    value&j
                %end;);
                
                define spec / display width=50 ' ';                
                %do j = 1 %to %sysfunc(countw(&&varlist&i,%str( ))); 
                    define value&j / display width=50 ' ' style={cellwidth=2in};
                %end;

                compute spec;
                    shade+1;
                    if mod(shade,2)=0 then call define(_row_,'style/merge','style={background=greyef}');
                    endcomp;
                where data_id=&i;
            run;
        %end;
    %end;
    ods excel close;
        
    ods results;
    %if &_listing=1 %then %do;
        ods listing;
    %end;
    /**Delete temporary datasets**/    
    proc datasets nolist nodetails;
        delete _data_specs_ _data_specs_condensed _data_specs_wide _libn_summary_ _specs_ _var_summary_
            %do i = 1 %to %sysfunc(countw(&datalist,%str( ))); _data_specs_wide&i %end;;
    quit;
    
    %errhandl:
    /**Reload previous Options**/ 
    options mergenoby=&_mergenoby &_notes &_quotelenmax;
    %put DATA_SPECS has finished processing, runtime: %sysfunc(putn(%sysevalf(%sysfunc(TIME())-&_starttime.),mmss.)); 
%mend;
