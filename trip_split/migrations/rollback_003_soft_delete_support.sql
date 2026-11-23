-- ==============================================================================================
-- ROLLBACK SCRIPT: rollback_002_soft_delete_support.sql
-- DESCRIPTION: Reverses soft-delete columns, default constraints, and performance indexes.
-- TRANSACTION: Atomic with TRY/CATCH and rollback.
-- ==============================================================================================

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;

BEGIN TRY
    BEGIN TRANSACTION;

    PRINT '--- ROLLING BACK SOFT DELETE INDEXES ---';

    DROP INDEX IF EXISTS IX_Persons_IsDeleted ON dbo.Persons;
    DROP INDEX IF EXISTS IX_Expenses_IsDeleted ON dbo.Expenses;
    DROP INDEX IF EXISTS IX_Trips_IsDeleted ON dbo.Trips;

    PRINT '--- ROLLING BACK SOFT DELETE DEFAULT CONSTRAINTS & COLUMNS ---';

    -- 1. Persons table
    DECLARE @dfPersons NVARCHAR(128);
    SELECT @dfPersons = dc.name
    FROM sys.default_constraints dc
    JOIN sys.columns c ON dc.parent_object_id = c.object_id AND dc.parent_column_id = c.column_id
    WHERE dc.parent_object_id = OBJECT_ID('dbo.Persons') AND c.name = 'is_deleted';

    IF @dfPersons IS NOT NULL
    BEGIN
        EXEC('ALTER TABLE dbo.Persons DROP CONSTRAINT ' + @dfPersons);
        PRINT 'Dropped default constraint on Persons.is_deleted.';
    END;

    IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.Persons') AND name = 'deleted_at')
    BEGIN
        ALTER TABLE dbo.Persons DROP COLUMN deleted_at;
        PRINT 'Dropped column Persons.deleted_at.';
    END;

    IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.Persons') AND name = 'is_deleted')
    BEGIN
        ALTER TABLE dbo.Persons DROP COLUMN is_deleted;
        PRINT 'Dropped column Persons.is_deleted.';
    END;

    -- 2. Expenses table
    DECLARE @dfExpenses NVARCHAR(128);
    SELECT @dfExpenses = dc.name
    FROM sys.default_constraints dc
    JOIN sys.columns c ON dc.parent_object_id = c.object_id AND dc.parent_column_id = c.column_id
    WHERE dc.parent_object_id = OBJECT_ID('dbo.Expenses') AND c.name = 'is_deleted';

    IF @dfExpenses IS NOT NULL
    BEGIN
        EXEC('ALTER TABLE dbo.Expenses DROP CONSTRAINT ' + @dfExpenses);
        PRINT 'Dropped default constraint on Expenses.is_deleted.';
    END;

    IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.Expenses') AND name = 'deleted_at')
    BEGIN
        ALTER TABLE dbo.Expenses DROP COLUMN deleted_at;
        PRINT 'Dropped column Expenses.deleted_at.';
    END;

    IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.Expenses') AND name = 'is_deleted')
    BEGIN
        ALTER TABLE dbo.Expenses DROP COLUMN is_deleted;
        PRINT 'Dropped column Expenses.is_deleted.';
    END;

    -- 3. Trips table
    DECLARE @dfTrips NVARCHAR(128);
    SELECT @dfTrips = dc.name
    FROM sys.default_constraints dc
    JOIN sys.columns c ON dc.parent_object_id = c.object_id AND dc.parent_column_id = c.column_id
    WHERE dc.parent_object_id = OBJECT_ID('dbo.Trips') AND c.name = 'is_deleted';

    IF @dfTrips IS NOT NULL
    BEGIN
        EXEC('ALTER TABLE dbo.Trips DROP CONSTRAINT ' + @dfTrips);
        PRINT 'Dropped default constraint on Trips.is_deleted.';
    END;

    IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.Trips') AND name = 'deleted_at')
    BEGIN
        ALTER TABLE dbo.Trips DROP COLUMN deleted_at;
        PRINT 'Dropped column Trips.deleted_at.';
    END;

    IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.Trips') AND name = 'is_deleted')
    BEGIN
        ALTER TABLE dbo.Trips DROP COLUMN is_deleted;
        PRINT 'Dropped column Trips.is_deleted.';
    END;

    COMMIT TRANSACTION;
    PRINT 'Rollback of 002_soft_delete_support completed successfully.';
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0
        ROLLBACK TRANSACTION;

    DECLARE @ErrMsg NVARCHAR(4000) = ERROR_MESSAGE();
    DECLARE @ErrSev INT = ERROR_SEVERITY();
    DECLARE @ErrState INT = ERROR_STATE();
    RAISERROR(@ErrMsg, @ErrSev, @ErrState);
END CATCH;
