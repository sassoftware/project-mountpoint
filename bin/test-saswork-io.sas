/*
Copyright © 2026, SAS Institute Inc., Cary, NC, USA.  All Rights Reserved.
SPDX-License-Identifier: Apache-2.0
*/

/* --------------------------------------------
   SASWORK Throughput Benchmarking 
   --------------------------------------------
   This code heavily utilizes the SASWORK library to benchmark I/O throughput
   performance using SAS data steps and procedures. It generates a large dataset,
   performs multiple sorting operations, and records the time taken and
   throughput metrics for each step.

   Run this program in multiple environments (or with different storage backends
   for SASWORK) to compare throughput performance.
*/

options fullstimer;

/* Initialize empty metrics tracking dataset */
data work.throughput_results;
    length step $40 dataset $32 elapsed_sec filesize_mb mb_per_sec 8;
    format elapsed_sec filesize_mb mb_per_sec comma10.2;
    stop;
run;

/* Macro to record metrics to the tracking table and print to log */
%macro log_throughput(dsn=, start_time=, step_desc=);
    %local end_time elapsed filesize_bytes filesize_mb mb_per_sec;
    
    %let end_time = %sysfunc(datetime());
    %let elapsed = %sysevalf(&end_time - &start_time);
    
    /* Fetch exact dataset size in bytes from DICTIONARY.TABLES */
    proc sql noprint;
        select filesize into :filesize_bytes
        from dictionary.tables
        where libname = 'WORK' and memname = "%upcase(%scan(&dsn, 2, .))";
    quit;

    %let filesize_mb = %sysevalf(&filesize_bytes / 1048576);
    %let mb_per_sec = 0;
    
    %if %sysevalf(&elapsed > 0) %then %do;
        %let mb_per_sec = %sysevalf(&filesize_mb / &elapsed);
    %end;

    /* Write record to tracking table */
    proc sql noprint;
        insert into work.throughput_results
        values ("&step_desc", "&dsn", &elapsed, &filesize_mb, &mb_per_sec);
    quit;

    %put NOTE: [THROUGHPUT] &step_desc | Size: %sysfunc(putn(&filesize_mb, comma10.2)) MB | Time: %sysfunc(putn(&elapsed, comma10.2)) s | Speed: %sysfunc(putn(&mb_per_sec, comma10.2)) MB/sec;
%mend log_throughput;


/* 1. Generate 1,000,000 rows of random data */
%let t1 = %sysfunc(datetime());

data work.random_data;
    call streaminit(12345);
    
    do i = 1 to 1000000;
        length product $20;
        product = cats("Product_", rand("Integer", 1, 100));
        sales_amount = rand("Uniform") * 10000;
        quantity = rand("Integer", 1, 500);
        transaction_date = '01JAN2024'd + rand("Integer", 0, 365);
        format transaction_date date9.;
        
        length is_active $3;
        is_active = ifc(rand("Uniform") > 0.5, "Yes", "No");
        
        length comments $1000;
        text_length = rand("Integer", 10, 1000);
        comments = repeat("X", text_length - 1);
        
        output;
    end;
    
    drop i text_length;
run;

%log_throughput(dsn=work.random_data, start_time=&t1, step_desc=Data Step Generation);

/* Display first 10 observations */
proc print data=work.random_data(obs=10);
run;

/* Dataset stats */
proc contents data=work.random_data; 
run;

/* 2. Sort by product name */
%let t1 = %sysfunc(datetime());
proc sort data=work.random_data out=work.sorted_by_product;
    by product;
run;
%log_throughput(dsn=work.sorted_by_product, start_time=&t1, step_desc=Sort by Product);

/* 3. Sort by sales amount */
%let t1 = %sysfunc(datetime());
proc sort data=work.random_data out=work.sorted_by_sales;
    by sales_amount;
run;
%log_throughput(dsn=work.sorted_by_sales, start_time=&t1, step_desc=Sort by Sales);

/* 4. Sort by transaction date */
%let t1 = %sysfunc(datetime());
proc sort data=work.random_data out=work.sorted_by_date;
    by transaction_date;
run;
%log_throughput(dsn=work.sorted_by_date, start_time=&t1, step_desc=Sort by Date);

/* 5. Sort by product, sales amount, and transaction date combined */
%let t1 = %sysfunc(datetime());
proc sort data=work.random_data out=work.sorted_by_all;
    by product sales_amount transaction_date;
run;
%log_throughput(dsn=work.sorted_by_all, start_time=&t1, step_desc=Sort by All);

/* Print throughput benchmark summary */
title "Throughput Performance Summary";
proc print data=work.throughput_results noobs;
run;
title;

/* Clean up temporary datasets including throughput tracking table */
proc datasets library=work nolist;
   delete random_data sorted_by_product sorted_by_sales sorted_by_date sorted_by_all throughput_results;
quit;