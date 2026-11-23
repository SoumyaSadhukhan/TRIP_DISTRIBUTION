-- ============================================================================
-- Migration: 001_reconcile_production_goa_trip.sql
-- Sequence: 001 of 004
-- Purpose: Authoritatively restore missing persons and expense splits for 
--          production trip '8092c57a-8638-4dc9-8969-748a9607d834' ('goa')
--
-- BUSINESS APPROVAL BOUNDARY (Phase 2.6 Mandate):
-- The split allocation for Car expense (₹4,520.00) between Friend and Dipa MOndal
-- is an UNVERIFIED ASSUMPTION because physical split rows in dbo.ExpenseSplits
-- were permanently deleted.
-- THIS MIGRATION WILL REFUSE TO EXECUTE UNLESS AN EXPLICIT ADMINISTRATIVE APPROVAL
-- RECORD (status = 'APPROVED') EXISTS IN dbo.ReconciliationApprovals.
-- ============================================================================

SET NOCOUNT ON;
SET XACT_ABORT ON;

BEGIN TRANSACTION;

DECLARE @trip_id NVARCHAR(100) = N'8092c57a-8638-4dc9-8969-748a9607d834';
DECLARE @group_id NVARCHAR(100) = N'56582c9f-db3c-4755-800d-77b371878f52';
DECLARE @creator_user_id NVARCHAR(100) = N'0d979a07-3c0b-4efc-a6ec-d3199f51335b';

DECLARE @friend_person_id NVARCHAR(100) = N'cf8806d1-a3f4-4aa1-bf3f-6df25fe23e12';
DECLARE @dipa_person_id NVARCHAR(100) = N'76810b14-585c-438e-a3ed-2150440a2985';
DECLARE @dipa_user_id NVARCHAR(100) = N'4f16ae4b-63e0-453a-9e35-27e6a754981a';
DECLARE @soumya_person_id NVARCHAR(100) = N'4bc5674a-b769-461e-ab38-c470ab10fd0b';

DECLARE @food_expense_id NVARCHAR(100) = N'7f28d135-2d7d-4369-8d36-b50b6e61e84a'; -- 4000.00
DECLARE @room_expense_id NVARCHAR(100) = N'79d4d8ad-0df4-4896-a863-b18fe1a0919f'; -- 5000.00
DECLARE @car_expense_id  NVARCHAR(100) = N'c4dab9a5-cd80-407f-8b1e-55f849328446'; -- 4520.00

PRINT '>>> Beginning 001 Reconciliation for Trip ' + @trip_id + ' (goa)...';

-- 0. Pre-Flight Verification: Verify trip exists
IF NOT EXISTS (SELECT 1 FROM dbo.Trips WHERE trip_id = @trip_id)
BEGIN
    ROLLBACK TRANSACTION;
    THROW 50000, 'Pre-flight check failed: Target trip does not exist.', 1;
END

-- 0.1 Ensure ReconciliationApprovals table exists to support administrative auditing
IF OBJECT_ID('dbo.ReconciliationApprovals', 'U') IS NULL
BEGIN
    PRINT 'CRITICAL ERROR: Administrative table dbo.ReconciliationApprovals does not exist in the database.';
    ROLLBACK TRANSACTION;
    THROW 50049, 'Reconciliation blocked: Prerequisite table dbo.ReconciliationApprovals does not exist.', 1;
END

-- 0.2 MANDATORY BUSINESS APPROVAL GATE:
-- Check for an explicit administrative approval record for the unverified Car split assumption
DECLARE @approval_count INT = 0;
DECLARE @app_id UNIQUEIDENTIFIER;
DECLARE @app_version NVARCHAR(50);
DECLARE @app_status NVARCHAR(50);
DECLARE @app_approver_id NVARCHAR(100);
DECLARE @app_approved_at DATETIME2;
DECLARE @app_type NVARCHAR(50);
DECLARE @app_is_admin_override BIT;
DECLARE @app_orig_json NVARCHAR(MAX);
DECLARE @app_proposed_json NVARCHAR(MAX);
DECLARE @app_signature NVARCHAR(64);
DECLARE @app_is_consumed BIT;

SELECT TOP 1
    @approval_count = 1,
    @app_id = approval_id,
    @app_version = reconciliation_version,
    @app_status = status,
    @app_approver_id = approver_id,
    @app_approved_at = approved_at,
    @app_type = reconciliation_type,
    @app_is_admin_override = is_administrative_override,
    @app_orig_json = original_values_json,
    @app_proposed_json = proposed_values_json,
    @app_signature = approval_signature,
    @app_is_consumed = is_consumed
FROM dbo.ReconciliationApprovals
WHERE trip_id = @trip_id 
  AND reconciliation_reference = N'GOA_CAR_EXPENSE_202611';

IF (@approval_count = 0)
BEGIN
    PRINT 'CRITICAL ERROR: No reconciliation approval record exists for reference GOA_CAR_EXPENSE_202611.';
    ROLLBACK TRANSACTION;
    THROW 50050, 'Reconciliation blocked: Missing approval record in dbo.ReconciliationApprovals.', 1;
END

IF (@app_status <> N'APPROVED')
BEGIN
    PRINT 'CRITICAL ERROR: Reconciliation approval status is ''' + ISNULL(@app_status, 'NULL') + ''', expected ''APPROVED''.';
    ROLLBACK TRANSACTION;
    THROW 50051, 'Reconciliation blocked: Reconciliation approval status is not APPROVED.', 1;
END

IF (@app_approver_id IS NULL OR LEN(LTRIM(RTRIM(@app_approver_id))) = 0)
BEGIN
    PRINT 'CRITICAL ERROR: Approver identity is missing or empty.';
    ROLLBACK TRANSACTION;
    THROW 50052, 'Reconciliation blocked: Approver identity is missing or unauthenticated.', 1;
END

IF (@app_approved_at IS NULL)
BEGIN
    PRINT 'CRITICAL ERROR: Approval timestamp is missing.';
    ROLLBACK TRANSACTION;
    THROW 50053, 'Reconciliation blocked: Approval timestamp is mandatory.', 1;
END

IF (@app_type <> N'ADMINISTRATIVE_ASSUMPTION_OVERRIDE')
BEGIN
    PRINT 'CRITICAL ERROR: Invalid reconciliation type ''' + ISNULL(@app_type, 'NULL') + '''.';
    ROLLBACK TRANSACTION;
    THROW 50054, 'Reconciliation blocked: Invalid reconciliation type.', 1;
END

IF (@app_is_admin_override <> 1)
BEGIN
    PRINT 'CRITICAL ERROR: Administrative override flag is not set to 1.';
    ROLLBACK TRANSACTION;
    THROW 50055, 'Reconciliation blocked: Administrative override flag must be 1.', 1;
END

IF (@app_version <> N'1.0')
BEGIN
    PRINT 'CRITICAL ERROR: Reconciliation version mismatch. Expected ''1.0'', found ''' + ISNULL(@app_version, 'NULL') + '''.';
    ROLLBACK TRANSACTION;
    THROW 50060, 'Reconciliation blocked: Reconciliation version mismatch.', 1;
END

IF (@app_is_consumed = 1)
BEGIN
    PRINT 'CRITICAL ERROR: Reconciliation approval has already been consumed by a prior migration run.';
    ROLLBACK TRANSACTION;
    THROW 50059, 'Reconciliation blocked: Approval record has already been consumed.', 1;
END

-- Verify approver is an active, authorized business principal
IF NOT EXISTS (
    SELECT 1 
    FROM dbo.AuthorizedReconciliationApprovers 
    WHERE approver_id = @app_approver_id 
      AND is_active = 1 
      AND (authorized_until IS NULL OR authorized_until > SYSUTCDATETIME())
      AND role IN (N'CHIEF_FINANCIAL_OFFICER', N'LEAD_AUDITOR', N'FINANCIAL_CONTROLLER')
)
BEGIN
    PRINT 'CRITICAL ERROR: Approver ''' + @app_approver_id + ''' is not an active authorized business principal.';
    ROLLBACK TRANSACTION;
    THROW 50057, 'Reconciliation blocked: Approver is not an authorized business principal.', 1;
END

-- Cryptographic tamper-evident payload verification
DECLARE @computed_signature NVARCHAR(64) = CONVERT(VARCHAR(64), HASHBYTES('SHA2_256', 
    @trip_id + N'|' + 
    N'GOA_CAR_EXPENSE_202611' + N'|' + 
    @app_type + N'|' + 
    @app_approver_id + N'|' + 
    CONVERT(VARCHAR(19), @app_approved_at, 126) + N'|' + 
    @app_orig_json + N'|' + 
    @app_proposed_json
), 2);

IF (@app_signature IS NULL OR @app_signature <> @computed_signature)
BEGIN
    PRINT 'CRITICAL ERROR: Approval signature verification failed. Payload has been tampered with after approval.';
    ROLLBACK TRANSACTION;
    THROW 50058, 'Reconciliation blocked: Approval payload signature verification failed. Approval has been tampered with.', 1;
END

-- Verify proposed allocation matches the exact migration allocation
DECLARE @car_friend_prop DECIMAL(18,2) = TRY_CAST(JSON_VALUE(@app_proposed_json, '$.car_splits.Friend') AS DECIMAL(18,2));
DECLARE @car_dipa_prop   DECIMAL(18,2) = TRY_CAST(JSON_VALUE(@app_proposed_json, '$.car_splits.Dipa') AS DECIMAL(18,2));
DECLARE @food_prop       DECIMAL(18,2) = TRY_CAST(JSON_VALUE(@app_proposed_json, '$.food_splits.Friend') AS DECIMAL(18,2));
DECLARE @room_prop       DECIMAL(18,2) = TRY_CAST(JSON_VALUE(@app_proposed_json, '$.room_splits.Friend') AS DECIMAL(18,2));

IF (@car_friend_prop <> 1506.67 OR @car_dipa_prop <> 1506.67 OR @food_prop <> 2000.00 OR @room_prop <> 2500.00)
BEGIN
    PRINT 'CRITICAL ERROR: Proposed allocation in approval does not match migration allocation.';
    ROLLBACK TRANSACTION;
    THROW 50056, 'Reconciliation blocked: Proposed allocation mismatch with migration script.', 1;
END

PRINT 'Administrative approval verified in dbo.ReconciliationApprovals. Proceeding with reconciliation.';

-- Check if soft-delete columns currently exist
DECLARE @hasSoftDelete BIT = 0;
IF COL_LENGTH('dbo.Persons', 'is_deleted') IS NOT NULL
    SET @hasSoftDelete = 1;

-- 1. Dependency-Safe Order Step 1: Restore Persons First
-- 1.1 Restore 'Friend' into dbo.Persons if missing
IF NOT EXISTS (SELECT 1 FROM dbo.Persons WHERE person_id = @friend_person_id)
BEGIN
    PRINT 'Restoring Person: Friend (' + @friend_person_id + ')';
    IF @hasSoftDelete = 1
    BEGIN
        EXEC('INSERT INTO dbo.Persons (person_id, group_id, trip_id, user_id, name, phone_number, paid_amount, owed_amount, balance, created_at, is_deleted, deleted_at)
              VALUES (''' + @friend_person_id + ''', ''' + @group_id + ''', ''' + @trip_id + ''', NULL, N''Friend'', NULL, 5000.00, 6006.67, -1006.67, ''2026-11-17 11:45:23'', 0, NULL);');
    END
    ELSE
    BEGIN
        INSERT INTO dbo.Persons (person_id, group_id, trip_id, user_id, name, phone_number, paid_amount, owed_amount, balance, created_at)
        VALUES (@friend_person_id, @group_id, @trip_id, NULL, N'Friend', NULL, 5000.00, 6006.67, -1006.67, '2026-11-17 11:45:23');
    END
END
ELSE
BEGIN
    PRINT 'Person Friend already exists. Updating financial balances.';
    IF @hasSoftDelete = 1
        EXEC('UPDATE dbo.Persons SET paid_amount = 5000.00, owed_amount = 6006.67, balance = -1006.67, is_deleted = 0, deleted_at = NULL WHERE person_id = ''' + @friend_person_id + ''';');
    ELSE
        UPDATE dbo.Persons SET paid_amount = 5000.00, owed_amount = 6006.67, balance = -1006.67 WHERE person_id = @friend_person_id;
END

-- 1.2 Restore 'Dipa MOndal' into dbo.Persons if missing
IF NOT EXISTS (SELECT 1 FROM dbo.Persons WHERE person_id = @dipa_person_id)
BEGIN
    PRINT 'Restoring Person: Dipa MOndal (' + @dipa_person_id + ')';
    IF @hasSoftDelete = 1
    BEGIN
        EXEC('INSERT INTO dbo.Persons (person_id, group_id, trip_id, user_id, name, phone_number, paid_amount, owed_amount, balance, created_at, is_deleted, deleted_at)
              VALUES (''' + @dipa_person_id + ''', ''' + @group_id + ''', ''' + @trip_id + ''', ''' + @dipa_user_id + ''', N''Dipa MOndal'', N''+919832542323'', 4520.00, 1506.67, 3013.33, ''2026-11-18 00:52:53'', 0, NULL);');
    END
    ELSE
    BEGIN
        INSERT INTO dbo.Persons (person_id, group_id, trip_id, user_id, name, phone_number, paid_amount, owed_amount, balance, created_at)
        VALUES (@dipa_person_id, @group_id, @trip_id, @dipa_user_id, N'Dipa MOndal', N'+919832542323', 4520.00, 1506.67, 3013.33, '2026-11-18 00:52:53');
    END
END
ELSE
BEGIN
    PRINT 'Person Dipa MOndal already exists. Updating financial balances.';
    IF @hasSoftDelete = 1
        EXEC('UPDATE dbo.Persons SET paid_amount = 4520.00, owed_amount = 1506.67, balance = 3013.33, is_deleted = 0, deleted_at = NULL WHERE person_id = ''' + @dipa_person_id + ''';');
    ELSE
        UPDATE dbo.Persons SET paid_amount = 4520.00, owed_amount = 1506.67, balance = 3013.33 WHERE person_id = @dipa_person_id;
END

-- 1.3 Update Soumya's balance in dbo.Persons
IF @hasSoftDelete = 1
    EXEC('UPDATE dbo.Persons SET paid_amount = 4000.00, owed_amount = 6006.66, balance = -2006.66, is_deleted = 0, deleted_at = NULL WHERE person_id = ''' + @soumya_person_id + ''';');
ELSE
    UPDATE dbo.Persons SET paid_amount = 4000.00, owed_amount = 6006.66, balance = -2006.66 WHERE person_id = @soumya_person_id;

-- 2. Dependency-Safe Order Step 2: Restore Missing ExpenseSplits
-- Food (4000.00) -> Friend's share = 2000.00 (Historical 50/50 Verified)
IF NOT EXISTS (SELECT 1 FROM dbo.ExpenseSplits WHERE expense_id = @food_expense_id AND person_id = @friend_person_id)
BEGIN
    PRINT 'Restoring ExpenseSplit: Food for Friend';
    INSERT INTO dbo.ExpenseSplits (split_id, expense_id, trip_id, person_id, amount, created_at)
    VALUES (N'b1e0f001-food-4000-friend-split0000001', @food_expense_id, @trip_id, @friend_person_id, 2000.00, '2026-11-17 11:45:43');
END

-- Room (5000.00) -> Friend's share = 2500.00 (Historical 50/50 Verified)
IF NOT EXISTS (SELECT 1 FROM dbo.ExpenseSplits WHERE expense_id = @room_expense_id AND person_id = @friend_person_id)
BEGIN
    PRINT 'Restoring ExpenseSplit: Room for Friend';
    INSERT INTO dbo.ExpenseSplits (split_id, expense_id, trip_id, person_id, amount, created_at)
    VALUES (N'b1e0f002-room-5000-friend-split0000002', @room_expense_id, @trip_id, @friend_person_id, 2500.00, '2026-11-17 11:46:01');
END

-- Car (4520.00) -> Friend's share = 1506.67 (Administrative Assumption Override)
IF NOT EXISTS (SELECT 1 FROM dbo.ExpenseSplits WHERE expense_id = @car_expense_id AND person_id = @friend_person_id)
BEGIN
    PRINT 'Restoring ExpenseSplit: Car for Friend (Administrative Assumption Override)';
    INSERT INTO dbo.ExpenseSplits (split_id, expense_id, trip_id, person_id, amount, created_at)
    VALUES (N'b1e0f003-car0-4520-friend-split0000003', @car_expense_id, @trip_id, @friend_person_id, 1506.67, '2026-11-18 00:53:30');
END

-- Car (4520.00) -> Dipa's share = 1506.67 (Administrative Assumption Override)
IF NOT EXISTS (SELECT 1 FROM dbo.ExpenseSplits WHERE expense_id = @car_expense_id AND person_id = @dipa_person_id)
BEGIN
    PRINT 'Restoring ExpenseSplit: Car for Dipa MOndal (Administrative Assumption Override)';
    INSERT INTO dbo.ExpenseSplits (split_id, expense_id, trip_id, person_id, amount, created_at)
    VALUES (N'b1e0f004-car0-4520-dipa00-split0000004', @car_expense_id, @trip_id, @dipa_person_id, 1506.67, '2026-11-18 00:53:30');
END

-- 3. Dependency-Safe Order Step 3: Record Audit Log
INSERT INTO dbo.ActivityLogs (log_id, user_id, trip_id, action_type, details, created_at)
VALUES (
    NEWID(), @creator_user_id, @trip_id, N'RECONCILIATION_AUDIT',
    N'Production safety gate Phase 2.6: Restored orphan persons (Friend, Dipa MOndal) and splits under approved administrative assumption override reference GOA_CAR_EXPENSE_202611.',
    GETDATE()
);

-- 4. STRICT FINANCIAL INVARIANT VERIFICATION (INCLUDING SETTLEMENTS)
DECLARE @TotalExpense DECIMAL(18,2);
DECLARE @TotalSplits  DECIMAL(18,2);
DECLARE @SumBalance   DECIMAL(18,2);
DECLARE @TotalSettlementsPaid DECIMAL(18,2);

IF @hasSoftDelete = 1
BEGIN
    EXEC sp_executesql 
        N'SELECT @totExp = ISNULL(SUM(amount), 0.00) FROM dbo.Expenses WHERE trip_id = @tid AND ISNULL(is_deleted, 0) = 0;
          SELECT @sumBal = ISNULL(SUM(balance), 0.00) FROM dbo.Persons WHERE trip_id = @tid AND ISNULL(is_deleted, 0) = 0;',
        N'@tid NVARCHAR(100), @totExp DECIMAL(18,2) OUTPUT, @sumBal DECIMAL(18,2) OUTPUT',
        @tid = @trip_id, @totExp = @TotalExpense OUTPUT, @sumBal = @SumBalance OUTPUT;
END
ELSE
BEGIN
    SELECT @TotalExpense = ISNULL(SUM(amount), 0.00) FROM dbo.Expenses WHERE trip_id = @trip_id;
    SELECT @SumBalance   = ISNULL(SUM(balance), 0.00) FROM dbo.Persons WHERE trip_id = @trip_id;
END

SELECT @TotalSplits  = ISNULL(SUM(amount), 0.00) FROM dbo.ExpenseSplits WHERE trip_id = @trip_id;
SELECT @TotalSettlementsPaid = ISNULL(SUM(amount), 0.00) FROM dbo.SettlementTransactions WHERE trip_id = @trip_id AND is_completed = 1;

PRINT 'Reconciliation Invariants Verification:';
PRINT '  Total Expenses:            ' + CAST(@TotalExpense AS NVARCHAR(30));
PRINT '  Total Splits:              ' + CAST(@TotalSplits AS NVARCHAR(30));
PRINT '  Total Completed Settlements:' + CAST(@TotalSettlementsPaid AS NVARCHAR(30));
PRINT '  Net Balance Sum:           ' + CAST(@SumBalance AS NVARCHAR(30));

IF (@TotalExpense <> @TotalSplits)
BEGIN
    PRINT 'ERROR: Total Expenses does not equal Total Splits!';
    ROLLBACK TRANSACTION;
    THROW 50001, 'Reconciliation failed: Total Expenses <> Total Splits', 1;
END

IF (ABS(@SumBalance) > 0.01)
BEGIN
    PRINT 'ERROR: Net balance sum is not zero!';
    ROLLBACK TRANSACTION;
    THROW 50002, 'Reconciliation failed: Balance sum is non-zero', 1;
END

-- 5. RECORD COMPLETE-ROW RECONCILIATION SNAPSHOT & MUTATION LEDGER
PRINT 'Creating complete-row snapshot and mutation audit guard...';

-- Mark approval consumed
UPDATE dbo.ReconciliationApprovals 
SET is_consumed = 1, 
    consumed_at = SYSUTCDATETIME(), 
    consumed_by_migration = N'001_reconcile_production_goa_trip.sql' 
WHERE trip_id = @trip_id AND reconciliation_reference = N'GOA_CAR_EXPENSE_202611';

-- Create or replace snapshot table
IF OBJECT_ID('dbo.__GoaReconciliationSnapshot', 'U') IS NOT NULL
    DROP TABLE dbo.__GoaReconciliationSnapshot;

CREATE TABLE dbo.__GoaReconciliationSnapshot (
    entity_type NVARCHAR(50) NOT NULL,
    entity_id NVARCHAR(100) NOT NULL,
    full_row_sha256 NVARCHAR(64) NOT NULL,
    created_at DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
    CONSTRAINT PK_GoaReconciliationSnapshot PRIMARY KEY CLUSTERED (entity_type, entity_id)
);

-- Snapshot Expenses (all columns)
INSERT INTO dbo.__GoaReconciliationSnapshot (entity_type, entity_id, full_row_sha256)
SELECT 'Expense', expense_id, 
       CONVERT(VARCHAR(64), HASHBYTES('SHA2_256', 
           expense_id + N'|' + trip_id + N'|' + description + N'|' + CAST(amount AS VARCHAR(30)) + N'|' + paid_by_person_id + N'|' + CONVERT(VARCHAR(30), expense_date, 120)
       ), 2)
FROM dbo.Expenses WHERE trip_id = @trip_id;

-- Snapshot ExpenseSplits (all columns)
INSERT INTO dbo.__GoaReconciliationSnapshot (entity_type, entity_id, full_row_sha256)
SELECT 'Split', split_id,
       CONVERT(VARCHAR(64), HASHBYTES('SHA2_256', 
           split_id + N'|' + expense_id + N'|' + trip_id + N'|' + person_id + N'|' + CAST(amount AS VARCHAR(30))
       ), 2)
FROM dbo.ExpenseSplits WHERE trip_id = @trip_id;

-- Snapshot Persons (all columns)
INSERT INTO dbo.__GoaReconciliationSnapshot (entity_type, entity_id, full_row_sha256)
SELECT 'Person', person_id,
       CONVERT(VARCHAR(64), HASHBYTES('SHA2_256', 
           person_id + N'|' + trip_id + N'|' + name + N'|' + CAST(paid_amount AS VARCHAR(30)) + N'|' + CAST(owed_amount AS VARCHAR(30)) + N'|' + CAST(balance AS VARCHAR(30))
       ), 2)
FROM dbo.Persons WHERE trip_id = @trip_id;

-- Create mutation ledger
IF OBJECT_ID('dbo.__ReconciliationMutationLedger', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.__ReconciliationMutationLedger (
        mutation_id UNIQUEIDENTIFIER NOT NULL DEFAULT NEWID(),
        trip_id NVARCHAR(100) NOT NULL,
        table_name NVARCHAR(100) NOT NULL,
        operation NVARCHAR(20) NOT NULL,
        mutated_at DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME()
    );
END;

PRINT '>>> All financial invariants verified successfully. Committing transaction.';
COMMIT TRANSACTION;
GO

-- Create Audit Triggers outside transaction batch
IF OBJECT_ID('dbo.TR_GoaTrip_Persons_MutationAudit', 'TR') IS NOT NULL
    DROP TRIGGER dbo.TR_GoaTrip_Persons_MutationAudit;
GO
CREATE TRIGGER dbo.TR_GoaTrip_Persons_MutationAudit
ON dbo.Persons
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;
    IF EXISTS (SELECT 1 FROM inserted WHERE trip_id = '8092c57a-8638-4dc9-8969-748a9607d834')
       OR EXISTS (SELECT 1 FROM deleted WHERE trip_id = '8092c57a-8638-4dc9-8969-748a9607d834')
    BEGIN
        INSERT INTO dbo.__ReconciliationMutationLedger (trip_id, table_name, operation)
        VALUES ('8092c57a-8638-4dc9-8969-748a9607d834', 'Persons', 'MUTATION');
    END
END;
GO

IF OBJECT_ID('dbo.TR_GoaTrip_Expenses_MutationAudit', 'TR') IS NOT NULL
    DROP TRIGGER dbo.TR_GoaTrip_Expenses_MutationAudit;
GO
CREATE TRIGGER dbo.TR_GoaTrip_Expenses_MutationAudit
ON dbo.Expenses
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;
    IF EXISTS (SELECT 1 FROM inserted WHERE trip_id = '8092c57a-8638-4dc9-8969-748a9607d834')
       OR EXISTS (SELECT 1 FROM deleted WHERE trip_id = '8092c57a-8638-4dc9-8969-748a9607d834')
    BEGIN
        INSERT INTO dbo.__ReconciliationMutationLedger (trip_id, table_name, operation)
        VALUES ('8092c57a-8638-4dc9-8969-748a9607d834', 'Expenses', 'MUTATION');
    END
END;
GO

IF OBJECT_ID('dbo.TR_GoaTrip_ExpenseSplits_MutationAudit', 'TR') IS NOT NULL
    DROP TRIGGER dbo.TR_GoaTrip_ExpenseSplits_MutationAudit;
GO
CREATE TRIGGER dbo.TR_GoaTrip_ExpenseSplits_MutationAudit
ON dbo.ExpenseSplits
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;
    IF EXISTS (SELECT 1 FROM inserted WHERE trip_id = '8092c57a-8638-4dc9-8969-748a9607d834')
       OR EXISTS (SELECT 1 FROM deleted WHERE trip_id = '8092c57a-8638-4dc9-8969-748a9607d834')
    BEGIN
        INSERT INTO dbo.__ReconciliationMutationLedger (trip_id, table_name, operation)
        VALUES ('8092c57a-8638-4dc9-8969-748a9607d834', 'ExpenseSplits', 'MUTATION');
    END
END;
GO
