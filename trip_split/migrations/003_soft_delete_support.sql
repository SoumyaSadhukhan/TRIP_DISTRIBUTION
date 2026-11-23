-- ==============================================================================================
-- MIGRATION SCRIPT: 002_soft_delete_support.sql
-- DESCRIPTION: Adds is_deleted and deleted_at columns with supporting indexes to Trips, Expenses, and Persons.
-- IDEMPOTENCY: Guaranteed via table-specific sys catalog checks.
-- TRANSACTION: Atomic with TRY/CATCH and rollback.
-- ROLLBACK PROCEDURE:
--   DROP INDEX IF EXISTS IX_Persons_IsDeleted ON dbo.Persons;
--   ALTER TABLE dbo.Persons DROP COLUMN IF EXISTS deleted_at, is_deleted;
--   DROP INDEX IF EXISTS IX_Expenses_IsDeleted ON dbo.Expenses;
--   ALTER TABLE dbo.Expenses DROP COLUMN IF EXISTS deleted_at, is_deleted;
--   DROP INDEX IF EXISTS IX_Trips_IsDeleted ON dbo.Trips;
--   ALTER TABLE dbo.Trips DROP COLUMN IF EXISTS deleted_at, is_deleted;
-- ==============================================================================================

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;

BEGIN TRY
    BEGIN TRANSACTION;

    PRINT '--- PHASE 1: TRIPS SOFT DELETE COLUMNS & INDEXES ---';

    IF NOT EXISTS (
        SELECT 1 
        FROM sys.columns 
        WHERE object_id = OBJECT_ID('dbo.Trips') AND name = 'is_deleted'
    )
    BEGIN
        ALTER TABLE dbo.Trips ADD is_deleted BIT NOT NULL CONSTRAINT DF_Trips_IsDeleted DEFAULT 0;
        PRINT 'Added is_deleted column to dbo.Trips.';
    END
    ELSE
    BEGIN
        PRINT 'Column is_deleted already exists on dbo.Trips.';
    END;

    IF NOT EXISTS (
        SELECT 1 
        FROM sys.columns 
        WHERE object_id = OBJECT_ID('dbo.Trips') AND name = 'deleted_at'
    )
    BEGIN
        ALTER TABLE dbo.Trips ADD deleted_at DATETIME NULL;
        PRINT 'Added deleted_at column to dbo.Trips.';
    END
    ELSE
    BEGIN
        PRINT 'Column deleted_at already exists on dbo.Trips.';
    END;

    IF NOT EXISTS (
        SELECT 1 
        FROM sys.indexes 
        WHERE object_id = OBJECT_ID('dbo.Trips') AND name = 'IX_Trips_IsDeleted'
    )
    BEGIN
        CREATE INDEX IX_Trips_IsDeleted ON dbo.Trips (is_deleted);
        PRINT 'Created index IX_Trips_IsDeleted.';
    END
    ELSE
    BEGIN
        PRINT 'Index IX_Trips_IsDeleted already exists.';
    END;

    PRINT '--- PHASE 2: EXPENSES SOFT DELETE COLUMNS & INDEXES ---';

    IF NOT EXISTS (
        SELECT 1 
        FROM sys.columns 
        WHERE object_id = OBJECT_ID('dbo.Expenses') AND name = 'is_deleted'
    )
    BEGIN
        ALTER TABLE dbo.Expenses ADD is_deleted BIT NOT NULL CONSTRAINT DF_Expenses_IsDeleted DEFAULT 0;
        PRINT 'Added is_deleted column to dbo.Expenses.';
    END
    ELSE
    BEGIN
        PRINT 'Column is_deleted already exists on dbo.Expenses.';
    END;

    IF NOT EXISTS (
        SELECT 1 
        FROM sys.columns 
        WHERE object_id = OBJECT_ID('dbo.Expenses') AND name = 'deleted_at'
    )
    BEGIN
        ALTER TABLE dbo.Expenses ADD deleted_at DATETIME NULL;
        PRINT 'Added deleted_at column to dbo.Expenses.';
    END
    ELSE
    BEGIN
        PRINT 'Column deleted_at already exists on dbo.Expenses.';
    END;

    IF NOT EXISTS (
        SELECT 1 
        FROM sys.indexes 
        WHERE object_id = OBJECT_ID('dbo.Expenses') AND name = 'IX_Expenses_IsDeleted'
    )
    BEGIN
        CREATE INDEX IX_Expenses_IsDeleted ON dbo.Expenses (is_deleted);
        PRINT 'Created index IX_Expenses_IsDeleted.';
    END
    ELSE
    BEGIN
        PRINT 'Index IX_Expenses_IsDeleted already exists.';
    END;

    PRINT '--- PHASE 3: PERSONS SOFT DELETE COLUMNS & INDEXES ---';

    IF NOT EXISTS (
        SELECT 1 
        FROM sys.columns 
        WHERE object_id = OBJECT_ID('dbo.Persons') AND name = 'is_deleted'
    )
    BEGIN
        ALTER TABLE dbo.Persons ADD is_deleted BIT NOT NULL CONSTRAINT DF_Persons_IsDeleted DEFAULT 0;
        PRINT 'Added is_deleted column to dbo.Persons.';
    END
    ELSE
    BEGIN
        PRINT 'Column is_deleted already exists on dbo.Persons.';
    END;

    IF NOT EXISTS (
        SELECT 1 
        FROM sys.columns 
        WHERE object_id = OBJECT_ID('dbo.Persons') AND name = 'deleted_at'
    )
    BEGIN
        ALTER TABLE dbo.Persons ADD deleted_at DATETIME NULL;
        PRINT 'Added deleted_at column to dbo.Persons.';
    END
    ELSE
    BEGIN
        PRINT 'Column deleted_at already exists on dbo.Persons.';
    END;

    IF NOT EXISTS (
        SELECT 1 
        FROM sys.indexes 
        WHERE object_id = OBJECT_ID('dbo.Persons') AND name = 'IX_Persons_IsDeleted'
    )
    BEGIN
        CREATE INDEX IX_Persons_IsDeleted ON dbo.Persons (is_deleted);
        PRINT 'Created index IX_Persons_IsDeleted.';
    END
    ELSE
    BEGIN
        PRINT 'Index IX_Persons_IsDeleted already exists.';
    END;

    COMMIT TRANSACTION;
    PRINT 'Migration 002_soft_delete_support committed successfully.';
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0
    BEGIN
        ROLLBACK TRANSACTION;
        PRINT 'Transaction rolled back due to error.';
    END;
    THROW;
END CATCH;


