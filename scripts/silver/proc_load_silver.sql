
CREATE OR ALTER PROCEDURE silver.load_silver AS
BEGIN
    DECLARE @start_time DATETIME, @end_time DATETIME, @batch_start_time DATETIME, @batch_end_time DATETIME
    BEGIN TRY

        SET @batch_start_time =  GETDATE()
        PRINT('=============================================================');
		PRINT('Loading Silver Layer');
		PRINT('=============================================================');

		
		PRINT('Loading CRM Tables');
		PRINT('-------------------------------------------------------------');
        SET @start_time = GETDATE()
        PRINT '>>Truncating Data:silver.crm_cust_info'
        TRUNCATE TABLE silver.crm_cust_info;
        PRINT '>>Inserting Data into:silver.crm_cust_info'
        INSERT INTO silver.crm_cust_info(
        cst_id,
        cst_key,
        cst_firstname,
        cst_lastname,
        cst_marital_status,
        cst_gndr,
        cst_create_date
        )
        SELECT
        cst_id,
        cst_key,
        --Remove unwanted spaces--
        TRIM(cst_firstname) cst_firstname,
        TRIM(cst_lastname) cst_lastname,

        CASE WHEN UPPER(TRIM(cst_marital_status)) = 'M' THEN 'Married'
	         WHEN UPPER(TRIM(cst_marital_status)) = 'S' THEN 'Single'
        ELSE 'n/a'
        END cst_marital_status, --Normalize marital status value to readable format

        CASE WHEN UPPER(TRIM(cst_gndr)) = 'M' THEN 'Male'
	         WHEN UPPER(TRIM(cst_gndr)) = 'F' THEN 'Female'
        ELSE 'n/a' ----Normalize gender value to readable format
        END cst_gndr,
        cst_create_date
        FROM
        (
        SELECT
        *,
        ROW_NUMBER() OVER (PARTITION BY cst_id ORDER BY cst_create_date DESC) as Flag_last
        FROM
        bronze.crm_cust_info
        WHERE cst_id IS NOT NULL
        ) t
        WHERE Flag_last = 1; --Select the most recent record per customer;

        SET @end_time = GETDATE()
        PRINT '>> Load Duration:' + CAST(DATEDIFF(second,@start_time, @end_time) AS NVARCHAR) + 'Seconds'
        PRINT '-----------------------------------------------------------------------------------------------';


        SET @start_time = GETDATE()
        PRINT '>>Truncating Data:silver.crm_prd_info'
        TRUNCATE TABLE silver.crm_prd_info
        PRINT '>>Inserting Data into:silver.crm_prd_info'
        INSERT INTO silver.crm_prd_info (
	        prd_id,
	        cat_id,
	        prd_key,
	        prd_nm,
	        prd_cost,
	        prd_line,
	        prd_start_dt,
	        prd_end_dt 
        )
        SELECT
        prd_id,
        REPLACE(SUBSTRING(prd_key,1,5),'-','_') cat_id, --extract category ID
        SUBSTRING(prd_key,7,len(prd_key)) prd_key, --extract prodcut ID
        prd_nm,
        ISNULL(prd_cost,0) prd_cost, --replacing NULL
        CASE UPPER(TRIM(prd_line))
	         WHEN 'R' THEN 'Road'
	         WHEN 'M' THEN 'Mountain'
	         WHEN 'S' THEN 'Other Sales'
	         WHEN 'T' THEN 'Touring'
	         ELSE 'n/a'
        END prd_line,
        prd_start_dt,
        DATEADD(DAY,-1,LEAD(prd_start_dt) OVER(PARTITION BY prd_key ORDER BY prd_start_dt)) as prd_end_dt
        FROM 
        bronze.crm_prd_info;

        SET @end_time = GETDATE()
        PRINT'>>Loading Duration:' + CAST(DATEDIFF(second, @start_time,@end_time) AS NVARCHAR) + 'Seconds';
        PRINT '------------------------------------------------------------------------------------------';

        SET @start_time = GETDATE()
        PRINT '>>Truncating Data: silver.crm_sales_details'
        TRUNCATE TABLE silver.crm_sales_details;
        PRINT '>>Inserting Data into:silver.crm_sales_details'
        INSERT INTO silver.crm_sales_details (
            sls_ord_num, 
	        sls_prd_key ,
	        sls_cust_id ,
	        sls_order_dt ,
	        sls_ship_dt ,
	        sls_due_dt, 
	        sls_sales ,
	        sls_quantity ,
	        sls_price 

        )

        SELECT 
            sls_ord_num,
            sls_prd_key,
            sls_cust_id,
     
            CASE 
               WHEN sls_order_dt = 0 OR LEN(sls_order_dt) !=8 THEN NULL
               ELSE CAST(CAST(sls_order_dt AS NVARCHAR) AS DATE)
             END sls_order_dt,

       
             CASE 
                WHEN sls_ship_dt = 0 OR LEN(sls_ship_dt) !=8 THEN NULL
                ELSE CAST(CAST(sls_ship_dt AS NVARCHAR) AS DATE)
             END sls_ship_dt,

        
              CASE 
                 WHEN sls_due_dt = 0 OR LEN(sls_due_dt) !=8 THEN NULL
                 ELSE CAST(CAST(sls_due_dt AS NVARCHAR) AS DATE)
               END sls_due_dt,


               CASE 
                  WHEN sls_sales IS NULL OR sls_sales <=0 OR sls_sales != sls_quantity * ABS(sls_price)
                  THEN sls_quantity * ABS(sls_price)
                  ELSE sls_sales
               END sls_sales,
          
        
                sls_quantity,

               CASE WHEN sls_price IS NULL OR sls_price <=0 
                    THEN sls_sales / NULLIF(sls_quantity,0)
                    ELSE sls_price
               END sls_price       
                
               FROM
               bronze.crm_sales_details;
        SET @end_time = GETDATE()
        PRINT'>>Loading Duration:' + CAST(DATEDIFF(second, @start_time,@end_time) AS NVARCHAR) + 'Seconds';
        
     
        PRINT('-------------------------------------------------------------');
		PRINT('Loading ERP Tables');
		PRINT('-------------------------------------------------------------');

        SET @start_time = GETDATE()
        PRINT '>>Truncating Data:silver.erp_cust_az12 '
        TRUNCATE TABLE silver.erp_cust_az12;
        PRINT '>>Inserting Data into:silver.erp_cust_az12'
        INSERT INTO silver.erp_cust_az12 (
            cid,
            bdate,
            gen
        )
        SELECT
            CASE 
                WHEN cid LIKE 'NAS%' THEN SUBSTRING(cid,4,LEN(cid))
                ELSE cid
            END cid,
            CASE 
                WHEN bdate > GETDATE() THEN NULL
                ELSE bdate
            END  bdate,

           CASE 
                WHEN UPPER(TRIM(gen)) IN ('F', 'Female') THEN 'Female'
                WHEN UPPER(TRIM(gen)) IN ('M', 'Male') THEN 'Male'
                ELSE 'n/a'
            END gen      
            FROM
            bronze.erp_cust_az12;
        SET @end_time = GETDATE()
        PRINT '>>Loading Duration:' + CAST(DATEDIFF(second, @start_time, @end_time) AS NVARCHAR) + 'Seconds';
        PRINT '--------------------------------------------------------------------------------------------';

        SET @start_time = GETDATE()
        PRINT '>>Truncating Data:silver.erp_loc_a101'
        TRUNCATE TABLE silver.erp_loc_a101;
        PRINT '>>Inserting Data into:silver.erp_loc_a101'
        INSERT INTO silver.erp_loc_a101(
        cid,
        cntry)

        SELECT 
        REPLACE(cid,'-','') cid,
        CASE 
	        WHEN TRIM(cntry) = 'DE' THEN 'Germany'
	        WHEN TRIM(cntry) IN ('US','USA') THEN 'United States'
	        WHEN TRIM(cntry) = '' or cntry IS NULL THEN 'n/a'
	        ELSE TRIM(cntry)
        END cntry
        FROM bronze.erp_loc_a101;
        SET @end_time = GETDATE()
        PRINT '>>Loading Duration:' + CAST(DATEDIFF(second, @start_time, @end_time) AS NVARCHAR) + 'Seconds';
        PRINT '--------------------------------------------------------------------------------------------';

        SET @start_time = GETDATE()
        PRINT '>>Truncating Data: silver.erp_px_cat_g1v2'
        TRUNCATE TABLE silver.erp_px_cat_g1v2;
        PRINT '>>Inserting Data into :silver.erp_px_cat_g1v2'
        INSERT INTO silver.erp_px_cat_g1v2(
        id,
        cat,
        subcat,
        maintenance
        )
        SELECT
        id,
        cat,
        subcat,
        maintenance
        FROM
        bronze.erp_px_cat_g1v2;
        SET @end_time = GETDATE()
        PRINT '>>Loading Duration:' + CAST(DATEDIFF(second, @start_time, @end_time) AS NVARCHAR) + 'Seconds';
        PRINT '-------------------------------------------------------------------------------------------';
        SET @batch_end_time = GETDATE()
        
        PRINT '>>LOADING SILVER LAYER COMPLETED...:' + CAST(DATEDIFF(second, @batch_start_time, @batch_end_time) AS NVARCHAR) + 'Seconds';


      END TRY
      BEGIN CATCH
      PRINT '==============================================================================';
      PRINT ' ERROR OCCURED DURING SILVER LAYER LOADING..'
      PRINT 'ERROR MESSAGE' + ERROR_MESSAGE();
      PRINT 'ERROR NUMBER' + CAST(ERROR_NUMBER()AS NVARCHAR);
      PRINT 'ERROR STATE' + CAST(ERROR_STATE() AS NVARCHAR);
      PRINT '==============================================================================';
      END CATCH
END



    

     




 








