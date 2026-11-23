SET NOCOUNT ON;

PRINT '=== 1. SERVER PROPERTIES ===';
SELECT 
    CAST(SERVERPROPERTY('MachineName') AS VARCHAR(50)) AS MachineName,
    CAST(SERVERPROPERTY('ServerName') AS VARCHAR(50)) AS ServerName,
    CAST(SERVERPROPERTY('InstanceName') AS VARCHAR(50)) AS InstanceName,
    CAST(SERVERPROPERTY('Edition') AS VARCHAR(50)) AS Edition,
    CAST(SERVERPROPERTY('ProductVersion') AS VARCHAR(30)) AS ProductVersion;

PRINT '=== 2. DATABASE METADATA ===';
SELECT 
    database_id,
    name,
    CONVERT(VARCHAR(25), create_date, 120) AS create_date,
    compatibility_level,
    recovery_model_desc,
    state_desc
FROM sys.databases
WHERE name IN ('SPLIT_BILL_DB', 'SPLIT_BILL_DB_TEST', 'SPLIT_BILL_DB_PROD_REHEARSAL', 'SPLIT_BILL_DB_HARDENING_TEST')
ORDER BY name;

PRINT '=== 3. PRODUCTION TABLE INVENTORY & EXACT ROW COUNTS ===';
USE SPLIT_BILL_DB;

SELECT 
    t.name AS TableName,
    (SELECT COUNT(*) FROM sys.columns c WHERE c.object_id = t.object_id) AS ColumnCount
FROM sys.tables t
ORDER BY t.name;

SELECT 'ActivityLogs' AS TableName, COUNT(*) AS ExactRows FROM dbo.ActivityLogs
UNION ALL SELECT 'AppUsers', COUNT(*) FROM dbo.AppUsers
UNION ALL SELECT 'BalanceSettlements', COUNT(*) FROM dbo.BalanceSettlements
UNION ALL SELECT 'ExpenseSplits', COUNT(*) FROM dbo.ExpenseSplits
UNION ALL SELECT 'Expenses', COUNT(*) FROM dbo.Expenses
UNION ALL SELECT 'GroupMembers', COUNT(*) FROM dbo.GroupMembers
UNION ALL SELECT 'Groups', COUNT(*) FROM dbo.Groups
UNION ALL SELECT 'Notifications', COUNT(*) FROM dbo.Notifications
UNION ALL SELECT 'OtpVerification', COUNT(*) FROM dbo.OtpVerification
UNION ALL SELECT 'Persons', COUNT(*) FROM dbo.Persons
UNION ALL SELECT 'SettlementTransactions', COUNT(*) FROM dbo.SettlementTransactions
UNION ALL SELECT 'TripInvites', COUNT(*) FROM dbo.TripInvites
UNION ALL SELECT 'Trips', COUNT(*) FROM dbo.Trips
ORDER BY TableName;

PRINT '=== 4. PRIMARY KEYS IN SPLIT_BILL_DB ===';
SELECT 
    t.name AS TableName,
    k.name AS ConstraintName,
    c.name AS ColumnName
FROM sys.key_constraints k
JOIN sys.tables t ON k.parent_object_id = t.object_id
JOIN sys.index_columns ic ON ic.object_id = t.object_id AND ic.index_id = k.unique_index_id
JOIN sys.columns c ON ic.object_id = c.object_id AND ic.column_id = c.column_id
ORDER BY t.name;

PRINT '=== 5. FOREIGN KEYS IN SPLIT_BILL_DB ===';
SELECT 
    fk.name AS ForeignKeyName,
    tp.name AS ParentTable,
    tr.name AS ReferencedTable
FROM sys.foreign_keys fk
JOIN sys.tables tp ON fk.parent_object_id = tp.object_id
JOIN sys.tables tr ON fk.referenced_object_id = tr.object_id;
