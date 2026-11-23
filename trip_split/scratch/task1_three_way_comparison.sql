-- Complete 3-Way Comparative Inventory
USE master;
SET NOCOUNT ON;

PRINT '================================================================================';
PRINT 'THREE-WAY DATABASE METADATA COMPARISON';
PRINT '================================================================================';
SELECT 
    d.database_id,
    d.name AS DatabaseName,
    CONVERT(VARCHAR(25), d.create_date, 120) AS CreateDate,
    d.compatibility_level AS CompatLevel,
    d.recovery_model_desc AS RecoveryModel,
    d.state_desc AS StateDesc
FROM sys.databases d
WHERE d.name IN ('SPLIT_BILL_DB', 'SPLIT_BILL_DB_PROD_REHEARSAL', 'SPLIT_BILL_DB_HARDENING_TEST')
ORDER BY d.name;

PRINT '================================================================================';
PRINT 'THREE-WAY TABLE INVENTORY AND ROW COUNT COMPARISON';
PRINT '================================================================================';

DECLARE @comp3 TABLE (
    TableName NVARCHAR(100),
    ProdRows INT,
    RehearsalRows INT,
    HardeningRows INT,
    ProdCols INT,
    RehearsalCols INT,
    HardeningCols INT
);

DECLARE @t NVARCHAR(100);
DECLARE cur CURSOR LOCAL FAST_FORWARD FOR 
    SELECT TABLE_NAME FROM SPLIT_BILL_DB.INFORMATION_SCHEMA.TABLES WHERE TABLE_TYPE = 'BASE TABLE' ORDER BY TABLE_NAME;

OPEN cur;
FETCH NEXT FROM cur INTO @t;
WHILE @@FETCH_STATUS = 0
BEGIN
    DECLARE @pRow INT, @rRow INT, @hRow INT;
    DECLARE @pCol INT, @rCol INT, @hCol INT;

    DECLARE @q1 NVARCHAR(MAX) = N'SELECT @cnt = COUNT(*) FROM SPLIT_BILL_DB.dbo.[' + @t + '];';
    EXEC sp_executesql @q1, N'@cnt INT OUTPUT', @cnt = @pRow OUTPUT;

    DECLARE @q2 NVARCHAR(MAX) = N'SELECT @cnt = COUNT(*) FROM SPLIT_BILL_DB_PROD_REHEARSAL.dbo.[' + @t + '];';
    EXEC sp_executesql @q2, N'@cnt INT OUTPUT', @cnt = @rRow OUTPUT;

    DECLARE @q3 NVARCHAR(MAX) = N'SELECT @cnt = COUNT(*) FROM SPLIT_BILL_DB_HARDENING_TEST.dbo.[' + @t + '];';
    EXEC sp_executesql @q3, N'@cnt INT OUTPUT', @cnt = @hRow OUTPUT;

    SELECT @pCol = COUNT(*) FROM SPLIT_BILL_DB.INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = @t;
    SELECT @rCol = COUNT(*) FROM SPLIT_BILL_DB_PROD_REHEARSAL.INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = @t;
    SELECT @hCol = COUNT(*) FROM SPLIT_BILL_DB_HARDENING_TEST.INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = @t;

    INSERT INTO @comp3 VALUES (@t, @pRow, @rRow, @hRow, @pCol, @rCol, @hCol);
    FETCH NEXT FROM cur INTO @t;
END
CLOSE cur;
DEALLOCATE cur;

SELECT 
    TableName,
    ProdRows,
    RehearsalRows,
    HardeningRows,
    CASE WHEN ProdRows = RehearsalRows AND ProdRows = HardeningRows THEN 'MATCH' ELSE 'MISMATCH' END AS RowMatch,
    ProdCols,
    RehearsalCols,
    HardeningCols,
    CASE WHEN ProdCols = RehearsalCols AND ProdCols = HardeningCols THEN 'MATCH' ELSE 'MISMATCH' END AS ColMatch
FROM @comp3
ORDER BY TableName;

SELECT 
    SUM(ProdRows) AS TotalProdRows,
    SUM(RehearsalRows) AS TotalRehearsalRows,
    SUM(HardeningRows) AS TotalHardeningRows
FROM @comp3;
