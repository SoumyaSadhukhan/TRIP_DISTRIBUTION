-- Complete forensic inventory of SPLIT_BILL_DB
SET NOCOUNT ON;

PRINT '================================================================================';
PRINT '1. SERVER AND DATABASE IDENTITY';
PRINT '================================================================================';
SELECT 
    CAST(SERVERPROPERTY('MachineName') AS NVARCHAR(50)) AS MachineName,
    CAST(SERVERPROPERTY('ServerName') AS NVARCHAR(50)) AS ServerName,
    CAST(SERVERPROPERTY('InstanceName') AS NVARCHAR(50)) AS InstanceName,
    CAST(SERVERPROPERTY('Edition') AS NVARCHAR(50)) AS Edition,
    CAST(SERVERPROPERTY('ProductVersion') AS NVARCHAR(50)) AS ProductVersion,
    d.database_id,
    d.name AS DatabaseName,
    CONVERT(VARCHAR(25), d.create_date, 120) AS CreateDate,
    d.compatibility_level AS CompatibilityLevel,
    d.recovery_model_desc AS RecoveryModel,
    d.state_desc AS StateDesc
FROM sys.databases d
WHERE d.name = 'SPLIT_BILL_DB';

PRINT '================================================================================';
PRINT '2. USER TABLE INVENTORY & DIRECT COUNT(*) IN SPLIT_BILL_DB';
PRINT '================================================================================';
USE SPLIT_BILL_DB;

DECLARE @tbls TABLE (TableName NVARCHAR(100), ExactRowCount INT, ColumnCount INT);
DECLARE @t NVARCHAR(100);
DECLARE cur CURSOR LOCAL FAST_FORWARD FOR 
    SELECT TABLE_NAME FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_TYPE = 'BASE TABLE' ORDER BY TABLE_NAME;

OPEN cur;
FETCH NEXT FROM cur INTO @t;
WHILE @@FETCH_STATUS = 0
BEGIN
    DECLARE @c INT, @colCount INT;
    DECLARE @q NVARCHAR(MAX) = N'SELECT @cnt = COUNT(*) FROM dbo.[' + @t + '];';
    EXEC sp_executesql @q, N'@cnt INT OUTPUT', @cnt = @c OUTPUT;
    
    SELECT @colCount = COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = @t;
    
    INSERT INTO @tbls VALUES (@t, @c, @colCount);
    FETCH NEXT FROM cur INTO @t;
END
CLOSE cur;
DEALLOCATE cur;

SELECT 
    TableName, 
    ColumnCount, 
    ExactRowCount 
FROM @tbls 
ORDER BY TableName;

SELECT SUM(ExactRowCount) AS TotalRowsAcrossAllTables FROM @tbls;

PRINT '================================================================================';
PRINT '3. COMPLETE COLUMN DEFINITIONS IN SPLIT_BILL_DB';
PRINT '================================================================================';
SELECT 
    TABLE_NAME,
    ORDINAL_POSITION,
    COLUMN_NAME,
    DATA_TYPE + 
        CASE 
            WHEN CHARACTER_MAXIMUM_LENGTH = -1 THEN '(MAX)'
            WHEN CHARACTER_MAXIMUM_LENGTH IS NOT NULL THEN '(' + CAST(CHARACTER_MAXIMUM_LENGTH AS VARCHAR(10)) + ')'
            WHEN NUMERIC_PRECISION IS NOT NULL AND DATA_TYPE IN ('decimal', 'numeric') THEN '(' + CAST(NUMERIC_PRECISION AS VARCHAR(10)) + ',' + CAST(NUMERIC_SCALE AS VARCHAR(10)) + ')'
            ELSE ''
        END AS FULL_DATA_TYPE,
    IS_NULLABLE
FROM INFORMATION_SCHEMA.COLUMNS
ORDER BY TABLE_NAME, ORDINAL_POSITION;

PRINT '================================================================================';
PRINT '4. PRIMARY KEYS AND UNIQUE CONSTRAINTS IN SPLIT_BILL_DB';
PRINT '================================================================================';
SELECT 
    t.name AS TableName,
    k.name AS ConstraintName,
    k.type_desc AS ConstraintType,
    c.name AS ColumnName,
    ic.key_ordinal AS KeyOrdinal
FROM sys.key_constraints k
JOIN sys.tables t ON k.parent_object_id = t.object_id
JOIN sys.index_columns ic ON ic.object_id = t.object_id AND ic.index_id = k.unique_index_id
JOIN sys.columns c ON ic.object_id = c.object_id AND ic.column_id = c.column_id
ORDER BY t.name, k.name, ic.key_ordinal;

PRINT '================================================================================';
PRINT '5. FOREIGN KEYS IN SPLIT_BILL_DB';
PRINT '================================================================================';
SELECT 
    fk.name AS ForeignKeyName,
    tp.name AS ParentTable,
    tr.name AS ReferencedTable,
    fk.is_disabled,
    fk.delete_referential_action_desc,
    fk.update_referential_action_desc
FROM sys.foreign_keys fk
JOIN sys.tables tp ON fk.parent_object_id = tp.object_id
JOIN sys.tables tr ON fk.referenced_object_id = tr.object_id;
