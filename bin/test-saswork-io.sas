/*
Copyright © 2026, SAS Institute Inc., Cary, NC, USA.  All Rights Reserved.
SPDX-License-Identifier: Apache-2.0
*/

/* Generate 1,000,000 rows of random data with 6 different data types */
data work.random_data;
    call streaminit(12345); /* Set random seed for reproducibility */
    
    /* 1 million obs ==> 1 GB file size */
    do i = 1 to 1000000;
        /* Character variable - random product names */
        length product $20;
        product = cats("Product_", rand("Integer", 1, 100));
        
        /* Numeric variable - random sales amount */
        sales_amount = rand("Uniform") * 10000;
        
        /* Integer variable - random quantity */
        quantity = rand("Integer", 1, 500);
        
        /* Date variable - random dates in 2024 */
        transaction_date = '01JAN2024'd + rand("Integer", 0, 365);
        format transaction_date date9.;
        
        /* Binary/Boolean variable - random yes/no flag */
        length is_active $3;
        is_active = ifc(rand("Uniform") > 0.5, "Yes", "No");
        
        /* Variable-length character data - random text from 10-1000 characters */
        length comments $1000;
        text_length = rand("Integer", 10, 1000);
        comments = repeat("X", text_length - 1);
        
        output;
    end;
    
    drop i text_length;
run;

/* Display first 10 observations */
proc print data=work.random_data(obs=10);
run;

/* Dataset stats */
proc contents data=work.random_data; 
run;

/* Sort by product name */
proc sort data=work.random_data out=work.sorted_by_product;
    by product;
run;

/* Sort by sales amount */
proc sort data=work.random_data out=work.sorted_by_sales;
    by sales_amount;
run;

/* Sort by transaction date */
proc sort data=work.random_data out=work.sorted_by_date;
    by transaction_date;
run;

/* Sort by product, sales amount, and transaction date combined */
proc sort data=work.random_data out=work.sorted_by_all;
    by product sales_amount transaction_date;
run;

/* Be nice: clean up temporary datasets */
proc datasets library=work nolist;
   delete random_data sorted_by_product sorted_by_sales sorted_by_date sorted_by_all;
quit;
