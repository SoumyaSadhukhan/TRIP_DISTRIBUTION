-- ==============================================================================================
-- ROLLBACK SCRIPT: rollback_001_composite_foreign_keys.sql
-- DESCRIPTION: Safely reverses all composite foreign keys and composite unique constraints.
-- TRANSACTION: Atomic with TRY/CATCH and rollback.
-- ==============================================================================================

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;

BEGIN TRY
    BEGIN TRANSACTION;

    PRINT '--- ROLLING BACK COMPOSITE FOREIGN KEYS ---';

    -- 1. Settlement composite foreign keys
    IF EXISTS (SELECT 1 FROM sys.foreign_keys WHERE parent_object_id = OBJECT_ID('dbo.SettlementTransactions') AND name = 'FK_Settlements_Persons_To_Trip')
    BEGIN
        ALTER TABLE dbo.SettlementTransactions DROP CONSTRAINT FK_Settlements_Persons_To_Trip;
        PRINT 'Dropped FK_Settlements_Persons_To_Trip.';
    END;

    IF EXISTS (SELECT 1 FROM sys.foreign_keys WHERE parent_object_id = OBJECT_ID('dbo.SettlementTransactions') AND name = 'FK_Settlements_Persons_From_Trip')
    BEGIN
        ALTER TABLE dbo.SettlementTransactions DROP CONSTRAINT FK_Settlements_Persons_From_Trip;
        PRINT 'Dropped FK_Settlements_Persons_From_Trip.';
    END;

    -- 2. ExpenseSplits composite foreign keys
    IF EXISTS (SELECT 1 FROM sys.foreign_keys WHERE parent_object_id = OBJECT_ID('dbo.ExpenseSplits') AND name = 'FK_ExpenseSplits_Persons_Trip')
    BEGIN
        ALTER TABLE dbo.ExpenseSplits DROP CONSTRAINT FK_ExpenseSplits_Persons_Trip;
        PRINT 'Dropped FK_ExpenseSplits_Persons_Trip.';
    END;

    IF EXISTS (SELECT 1 FROM sys.foreign_keys WHERE parent_object_id = OBJECT_ID('dbo.ExpenseSplits') AND name = 'FK_ExpenseSplits_Expenses_Trip')
    BEGIN
        ALTER TABLE dbo.ExpenseSplits DROP CONSTRAINT FK_ExpenseSplits_Expenses_Trip;
        PRINT 'Dropped FK_ExpenseSplits_Expenses_Trip.';
    END;

    -- 3. Expenses composite foreign keys
    IF EXISTS (SELECT 1 FROM sys.foreign_keys WHERE parent_object_id = OBJECT_ID('dbo.Expenses') AND name = 'FK_Expenses_Persons_Trip')
    BEGIN
        ALTER TABLE dbo.Expenses DROP CONSTRAINT FK_Expenses_Persons_Trip;
        PRINT 'Dropped FK_Expenses_Persons_Trip.';
    END;

    PRINT '--- ROLLING BACK COMPOSITE UNIQUE CONSTRAINTS ---';

    -- 4. Expenses composite unique constraint
    IF EXISTS (SELECT 1 FROM sys.key_constraints WHERE parent_object_id = OBJECT_ID('dbo.Expenses') AND name = 'UQ_Expenses_ExpenseTrip')
    BEGIN
        ALTER TABLE dbo.Expenses DROP CONSTRAINT UQ_Expenses_ExpenseTrip;
        PRINT 'Dropped UQ_Expenses_ExpenseTrip.';
    END;

    -- 5. Persons composite unique constraint
    IF EXISTS (SELECT 1 FROM sys.key_constraints WHERE parent_object_id = OBJECT_ID('dbo.Persons') AND name = 'UQ_Persons_PersonTrip')
    BEGIN
        ALTER TABLE dbo.Persons DROP CONSTRAINT UQ_Persons_PersonTrip;
        PRINT 'Dropped UQ_Persons_PersonTrip.';
    END;

    COMMIT TRANSACTION;
    PRINT 'Rollback of 001_composite_foreign_keys completed successfully.';
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0
        ROLLBACK TRANSACTION;

    DECLARE @ErrMsg NVARCHAR(4000) = ERROR_MESSAGE();
    DECLARE @ErrSev INT = ERROR_SEVERITY();
    DECLARE @ErrState INT = ERROR_STATE();
    RAISERROR(@ErrMsg, @ErrSev, @ErrState);
END CATCH;
