-- ==============================================================================================
-- ROLLBACK SCRIPT: rollback_all.sql
-- DESCRIPTION: Unified rollback script reversing 004, 003, 002, and 001 in safe reverse dependency order.
-- TRANSACTION: Atomic with TRY/CATCH and rollback on failure.
-- ==============================================================================================

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;

BEGIN TRY
    BEGIN TRANSACTION;

    PRINT '================================================================================';
    PRINT 'EXECUTING COMPLETE UNIFIED ROLLBACK (004 -> 003 -> 002 -> 001)';
    PRINT '================================================================================';

    -- STEP 1: ROLL BACK 004 (OTP HARDENING)
    PRINT '--- STEP 1: Rolling back 004_harden_otp_schema ---';
    DROP INDEX IF EXISTS IX_OtpVerification_Lookup ON dbo.OtpVerification;
    DROP INDEX IF EXISTS IX_OtpVerification_IpRateLimit ON dbo.OtpVerification;

    DECLARE @dfFailed NVARCHAR(128);
    SELECT @dfFailed = dc.name
    FROM sys.default_constraints dc
    JOIN sys.columns c ON dc.parent_object_id = c.object_id AND dc.parent_column_id = c.column_id
    WHERE dc.parent_object_id = OBJECT_ID('dbo.OtpVerification') AND c.name = 'failed_attempts';
    IF @dfFailed IS NOT NULL EXEC('ALTER TABLE dbo.OtpVerification DROP CONSTRAINT ' + @dfFailed);

    DECLARE @dfMax NVARCHAR(128);
    SELECT @dfMax = dc.name
    FROM sys.default_constraints dc
    JOIN sys.columns c ON dc.parent_object_id = c.object_id AND dc.parent_column_id = c.column_id
    WHERE dc.parent_object_id = OBJECT_ID('dbo.OtpVerification') AND c.name = 'max_attempts';
    IF @dfMax IS NOT NULL EXEC('ALTER TABLE dbo.OtpVerification DROP CONSTRAINT ' + @dfMax);

    IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.OtpVerification') AND name = 'ip_address')
        ALTER TABLE dbo.OtpVerification DROP COLUMN ip_address;
    IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.OtpVerification') AND name = 'lockout_until')
        ALTER TABLE dbo.OtpVerification DROP COLUMN lockout_until;
    IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.OtpVerification') AND name = 'max_attempts')
        ALTER TABLE dbo.OtpVerification DROP COLUMN max_attempts;
    IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.OtpVerification') AND name = 'failed_attempts')
        ALTER TABLE dbo.OtpVerification DROP COLUMN failed_attempts;
    IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.OtpVerification') AND name = 'otp_hash')
        ALTER TABLE dbo.OtpVerification DROP COLUMN otp_hash;

    -- STEP 2: ROLL BACK 003 (SOFT DELETE)
    PRINT '--- STEP 2: Rolling back 003_soft_delete_support ---';
    DROP INDEX IF EXISTS IX_Persons_IsDeleted ON dbo.Persons;
    DROP INDEX IF EXISTS IX_Expenses_IsDeleted ON dbo.Expenses;
    DROP INDEX IF EXISTS IX_Trips_IsDeleted ON dbo.Trips;

    DECLARE @dfPersons NVARCHAR(128);
    SELECT @dfPersons = dc.name FROM sys.default_constraints dc JOIN sys.columns c ON dc.parent_object_id = c.object_id AND dc.parent_column_id = c.column_id WHERE dc.parent_object_id = OBJECT_ID('dbo.Persons') AND c.name = 'is_deleted';
    IF @dfPersons IS NOT NULL EXEC('ALTER TABLE dbo.Persons DROP CONSTRAINT ' + @dfPersons);
    IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.Persons') AND name = 'deleted_at') ALTER TABLE dbo.Persons DROP COLUMN deleted_at;
    IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.Persons') AND name = 'is_deleted') ALTER TABLE dbo.Persons DROP COLUMN is_deleted;

    DECLARE @dfExpenses NVARCHAR(128);
    SELECT @dfExpenses = dc.name FROM sys.default_constraints dc JOIN sys.columns c ON dc.parent_object_id = c.object_id AND dc.parent_column_id = c.column_id WHERE dc.parent_object_id = OBJECT_ID('dbo.Expenses') AND c.name = 'is_deleted';
    IF @dfExpenses IS NOT NULL EXEC('ALTER TABLE dbo.Expenses DROP CONSTRAINT ' + @dfExpenses);
    IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.Expenses') AND name = 'deleted_at') ALTER TABLE dbo.Expenses DROP COLUMN deleted_at;
    IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.Expenses') AND name = 'is_deleted') ALTER TABLE dbo.Expenses DROP COLUMN is_deleted;

    DECLARE @dfTrips NVARCHAR(128);
    SELECT @dfTrips = dc.name FROM sys.default_constraints dc JOIN sys.columns c ON dc.parent_object_id = c.object_id AND dc.parent_column_id = c.column_id WHERE dc.parent_object_id = OBJECT_ID('dbo.Trips') AND c.name = 'is_deleted';
    IF @dfTrips IS NOT NULL EXEC('ALTER TABLE dbo.Trips DROP CONSTRAINT ' + @dfTrips);
    IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.Trips') AND name = 'deleted_at') ALTER TABLE dbo.Trips DROP COLUMN deleted_at;
    IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.Trips') AND name = 'is_deleted') ALTER TABLE dbo.Trips DROP COLUMN is_deleted;

    -- STEP 3: ROLL BACK 002 (COMPOSITE FOREIGN KEYS)
    PRINT '--- STEP 3: Rolling back 002_composite_foreign_keys ---';
    ALTER TABLE dbo.ExpenseSplits DROP CONSTRAINT IF EXISTS FK_ExpenseSplits_Expenses_Trip;
    ALTER TABLE dbo.ExpenseSplits DROP CONSTRAINT IF EXISTS FK_ExpenseSplits_Expense_Trip;
    ALTER TABLE dbo.ExpenseSplits DROP CONSTRAINT IF EXISTS FK_ExpenseSplits_Persons_Trip;
    ALTER TABLE dbo.ExpenseSplits DROP CONSTRAINT IF EXISTS FK_ExpenseSplits_Person_Trip;
    ALTER TABLE dbo.Expenses DROP CONSTRAINT IF EXISTS FK_Expenses_Persons_Trip;
    ALTER TABLE dbo.Expenses DROP CONSTRAINT IF EXISTS FK_Expenses_PaidBy_Trip;
    ALTER TABLE dbo.SettlementTransactions DROP CONSTRAINT IF EXISTS FK_Settlements_FromPersons_Trip;
    ALTER TABLE dbo.SettlementTransactions DROP CONSTRAINT IF EXISTS FK_Settlements_FromPerson_Trip;
    ALTER TABLE dbo.SettlementTransactions DROP CONSTRAINT IF EXISTS FK_Settlements_ToPersons_Trip;
    ALTER TABLE dbo.SettlementTransactions DROP CONSTRAINT IF EXISTS FK_Settlements_ToPerson_Trip;

    DROP INDEX IF EXISTS IX_ExpenseSplits_ExpenseTrip ON dbo.ExpenseSplits;
    DROP INDEX IF EXISTS IX_ExpenseSplits_PersonTrip ON dbo.ExpenseSplits;
    DROP INDEX IF EXISTS IX_Expenses_PaidByTrip ON dbo.Expenses;
    DROP INDEX IF EXISTS IX_SettlementTransactions_FromPersonTrip ON dbo.SettlementTransactions;
    DROP INDEX IF EXISTS IX_SettlementTransactions_ToPersonTrip ON dbo.SettlementTransactions;

    ALTER TABLE dbo.Expenses DROP CONSTRAINT IF EXISTS UQ_Expenses_ExpenseTrip;
    ALTER TABLE dbo.Persons DROP CONSTRAINT IF EXISTS UQ_Persons_PersonTrip;

    -- STEP 4: ROLL BACK 001 (GOA RECONCILIATION WITH SAFETY PRECHECKS)
    PRINT '--- STEP 4: Rolling back 001_reconcile_production_goa_trip ---';
    DECLARE @trip_id NVARCHAR(100) = N'8092c57a-8638-4dc9-8969-748a9607d834';
    DECLARE @friend_person_id NVARCHAR(100) = N'cf8806d1-a3f4-4aa1-bf3f-6df25fe23e12';
    DECLARE @dipa_person_id NVARCHAR(100) = N'76810b14-585c-438e-a3ed-2150440a2985';
    DECLARE @soumya_person_id NVARCHAR(100) = N'4bc5674a-b769-461e-ab38-c470ab10fd0b';

    -- Safety Check: Verify no settlements exist for Goa trip
    IF EXISTS (SELECT 1 FROM dbo.SettlementTransactions WHERE trip_id = @trip_id)
    BEGIN
        THROW 50010, 'Rollback refused: Settlement transactions exist for Goa trip.', 1;
    END

    -- Safety Check: Verify no subsequent expenses exist for Goa trip
    IF EXISTS (
        SELECT 1 FROM dbo.Expenses 
        WHERE trip_id = @trip_id 
          AND expense_id NOT IN (
              N'7f28d135-2d7d-4369-8d36-b50b6e61e84a',
              N'79d4d8ad-0df4-4896-a863-b18fe1a0919f',
              N'c4dab9a5-cd80-407f-8b1e-55f849328446'
          )
    )
    BEGIN
        THROW 50011, 'Rollback refused: Subsequent expenses exist for Goa trip.', 1;
    END

    -- Remove Restored Splits
    DELETE FROM dbo.ExpenseSplits
    WHERE split_id IN (
        N'b1e0f001-food-4000-friend-split0000001',
        N'b1e0f002-room-5000-friend-split0000002',
        N'b1e0f003-car0-4520-friend-split0000003',
        N'b1e0f004-car0-4520-dipa00-split0000004'
    );

    -- Remove Restored Persons
    DELETE FROM dbo.Persons WHERE person_id IN (@friend_person_id, @dipa_person_id);

    -- Reset Soumya's balance
    UPDATE dbo.Persons
    SET paid_amount = 4000.00, owed_amount = 6006.66, balance = -2006.66
    WHERE person_id = @soumya_person_id;

    -- Audit log
    INSERT INTO dbo.ActivityLogs (log_id, user_id, trip_id, action_type, details, created_at)
    VALUES (NEWID(), N'0d979a07-3c0b-4efc-a6ec-d3199f51335b', @trip_id, N'RECONCILIATION_ROLLBACK', N'Unified rollback: Reverted Goa reconciliation.', GETUTCDATE());

    COMMIT TRANSACTION;
    PRINT '================================================================================';
    PRINT 'UNIFIED ROLLBACK COMPLETED SUCCESSFULLY';
    PRINT '================================================================================';
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0
        ROLLBACK TRANSACTION;
    PRINT 'ERROR in unified rollback: ' + ERROR_MESSAGE();
    THROW;
END CATCH;
GO
