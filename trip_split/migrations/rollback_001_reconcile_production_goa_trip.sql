-- ============================================================================
-- Rollback Migration: rollback_001_reconcile_production_goa_trip.sql
-- Sequence: Rollback 001 of 004
-- Purpose: Safely reverse the Goa trip reconciliation in case of emergency rollback
-- Hardened Safety (Phase 2.6 Mandate):
-- Detects and aborts if ANY of the following 8 dependencies exist:
--   1. Subsequent expenses for the trip.
--   2. Subsequent expense-split modifications.
--   3. Subsequent settlements for the trip.
--   4. Person balance changes for any member in the trip.
--   5. Person deletion or restoration state modifications.
--   6. Trip membership changes (new persons added/removed).
--   7. Modifications to restored person rows (Friend, Dipa MOndal).
--   8. Subsequent relevant activity-log entries.
-- ============================================================================

SET NOCOUNT ON;
SET XACT_ABORT ON;

BEGIN TRANSACTION;

DECLARE @trip_id NVARCHAR(100) = N'8092c57a-8638-4dc9-8969-748a9607d834';
DECLARE @friend_person_id NVARCHAR(100) = N'cf8806d1-a3f4-4aa1-bf3f-6df25fe23e12';
DECLARE @dipa_person_id NVARCHAR(100) = N'76810b14-585c-438e-a3ed-2150440a2985';
DECLARE @soumya_person_id NVARCHAR(100) = N'4bc5674a-b769-461e-ab38-c470ab10fd0b';

PRINT '>>> Validating hardened rollback preconditions for Trip ' + @trip_id + '...';

-- 0. Idempotency Check: If already rolled back, exit cleanly
IF NOT EXISTS (SELECT 1 FROM dbo.Persons WHERE person_id = @friend_person_id)
   AND NOT EXISTS (SELECT 1 FROM dbo.Persons WHERE person_id = @dipa_person_id)
   AND NOT EXISTS (SELECT 1 FROM dbo.ExpenseSplits WHERE split_id = N'b1e0f001-food-4000-friend-split0000001')
BEGIN
    PRINT 'Idempotency check: Migration 001 changes are already absent / rolled back. No-op.';
    COMMIT TRANSACTION;
    RETURN;
END

-- 1. Dependency Check: Verify no settlements exist for this trip
IF EXISTS (SELECT 1 FROM dbo.SettlementTransactions WHERE trip_id = @trip_id)
BEGIN
    ROLLBACK TRANSACTION;
    THROW 50010, 'Rollback aborted: Subsequent settlement transactions exist for this trip.', 1;
END

-- 2. Dependency Check: Verify no subsequent expenses exist and existing expense amounts are unchanged
IF EXISTS (
    SELECT 1 FROM dbo.Expenses 
    WHERE trip_id = @trip_id 
      AND expense_id NOT IN (
          N'7f28d135-2d7d-4369-8d36-b50b6e61e84a', -- food
          N'79d4d8ad-0df4-4896-a863-b18fe1a0919f', -- room
          N'c4dab9a5-cd80-407f-8b1e-55f849328446'  -- Car
      )
)
BEGIN
    ROLLBACK TRANSACTION;
    THROW 50011, 'Rollback aborted: Subsequent expenses exist for this trip.', 1;
END

-- Verify existing expense amounts have not been modified
IF EXISTS (
    SELECT 1 FROM dbo.Expenses
    WHERE (expense_id = N'7f28d135-2d7d-4369-8d36-b50b6e61e84a' AND amount <> 4000.00)
       OR (expense_id = N'79d4d8ad-0df4-4896-a863-b18fe1a0919f' AND amount <> 5000.00)
       OR (expense_id = N'c4dab9a5-cd80-407f-8b1e-55f849328446' AND amount <> 4520.00)
)
BEGIN
    ROLLBACK TRANSACTION;
    THROW 50011, 'Rollback aborted: Existing expense amounts have been modified.', 1;
END

-- 3. Dependency Check: Verify no subsequent split modifications and split amounts are intact
IF EXISTS (
    SELECT 1 FROM dbo.ExpenseSplits
    WHERE trip_id = @trip_id
      AND split_id NOT IN (
          N'168453e1-937f-4c61-9a5e-c45a800d5cc4',
          N'1bcda526-a219-4332-b319-0653612350ac',
          N'27a6e5b9-0038-4300-836b-ea73b7fc1ba5',
          N'b1e0f001-food-4000-friend-split0000001',
          N'b1e0f002-room-5000-friend-split0000002',
          N'b1e0f003-car0-4520-friend-split0000003',
          N'b1e0f004-car0-4520-dipa00-split0000004'
      )
)
BEGIN
    ROLLBACK TRANSACTION;
    THROW 50012, 'Rollback aborted: Subsequent or unrecognized expense splits exist for this trip.', 1;
END

-- Verify existing split amounts have not been modified
IF EXISTS (
    SELECT 1 FROM dbo.ExpenseSplits
    WHERE (split_id = N'b1e0f001-food-4000-friend-split0000001' AND amount <> 2000.00)
       OR (split_id = N'b1e0f002-room-5000-friend-split0000002' AND amount <> 2500.00)
       OR (split_id = N'b1e0f003-car0-4520-friend-split0000003' AND amount <> 1506.67)
       OR (split_id = N'b1e0f004-car0-4520-dipa00-split0000004' AND amount <> 1506.67)
)
BEGIN
    ROLLBACK TRANSACTION;
    THROW 50012, 'Rollback aborted: Existing expense split amounts have been modified.', 1;
END

-- 4. Dependency Check: Verify person balances match exact reconciled state
DECLARE @friend_balance DECIMAL(18,2);
DECLARE @dipa_balance   DECIMAL(18,2);
DECLARE @soumya_balance DECIMAL(18,2);

SELECT @friend_balance = balance FROM dbo.Persons WHERE person_id = @friend_person_id;
SELECT @dipa_balance   = balance FROM dbo.Persons WHERE person_id = @dipa_person_id;
SELECT @soumya_balance = balance FROM dbo.Persons WHERE person_id = @soumya_person_id;

IF (@friend_balance IS NULL OR @friend_balance <> -1006.67)
BEGIN
    ROLLBACK TRANSACTION;
    THROW 50013, 'Rollback aborted: Friend person balance has evolved or been modified since reconciliation.', 1;
END

IF (@dipa_balance IS NULL OR @dipa_balance <> 3013.33)
BEGIN
    ROLLBACK TRANSACTION;
    THROW 50014, 'Rollback aborted: Dipa MOndal person balance has evolved or been modified since reconciliation.', 1;
END

IF (@soumya_balance IS NULL OR @soumya_balance <> -2006.66)
BEGIN
    ROLLBACK TRANSACTION;
    THROW 50015, 'Rollback aborted: Soumya person balance has evolved or been modified since reconciliation.', 1;
END

-- 5. Dependency Check: Verify no soft-delete mutations (is_deleted = 1)
IF COL_LENGTH('dbo.Persons', 'is_deleted') IS NOT NULL
BEGIN
    EXEC sp_executesql N'IF EXISTS (SELECT 1 FROM dbo.Persons WHERE trip_id = @tid AND is_deleted = 1) THROW 50016, ''Rollback aborted: One or more persons in this trip have been deleted.'', 1;', N'@tid NVARCHAR(100)', @tid = @trip_id;
    EXEC sp_executesql N'IF EXISTS (SELECT 1 FROM dbo.Expenses WHERE trip_id = @tid AND is_deleted = 1) THROW 50017, ''Rollback aborted: One or more expenses in this trip have been deleted.'', 1;', N'@tid NVARCHAR(100)', @tid = @trip_id;
END

-- 6. Dependency Check: Verify trip membership count matches exactly 3 persons
DECLARE @member_count INT;
SELECT @member_count = COUNT(*) FROM dbo.Persons WHERE trip_id = @trip_id;
IF (@member_count <> 3)
BEGIN
    ROLLBACK TRANSACTION;
    THROW 50018, 'Rollback aborted: Trip membership count has changed since reconciliation.', 1;
END

-- 7. Dependency Check: Verify restored row identity integrity
IF NOT EXISTS (SELECT 1 FROM dbo.Persons WHERE person_id = @friend_person_id AND name = N'Friend' AND paid_amount = 5000.00)
BEGIN
    ROLLBACK TRANSACTION;
    THROW 50019, 'Rollback aborted: Friend person record attributes have been modified.', 1;
END

IF NOT EXISTS (SELECT 1 FROM dbo.Persons WHERE person_id = @dipa_person_id AND name = N'Dipa MOndal' AND paid_amount = 4520.00)
BEGIN
    ROLLBACK TRANSACTION;
    THROW 50020, 'Rollback aborted: Dipa MOndal person record attributes have been modified.', 1;
END

-- 8. Dependency Check: Verify no unrecognized activity logs after reconciliation
DECLARE @recon_log_time DATETIME;
SELECT @recon_log_time = MAX(created_at) FROM dbo.ActivityLogs WHERE trip_id = @trip_id AND action_type = N'RECONCILIATION_AUDIT';

IF EXISTS (
    SELECT 1 FROM dbo.ActivityLogs 
    WHERE trip_id = @trip_id 
      AND created_at > @recon_log_time 
      AND action_type NOT IN (N'RECONCILIATION_AUDIT', N'RECONCILIATION_ROLLBACK')
)
BEGIN
    ROLLBACK TRANSACTION;
    THROW 50021, 'Rollback aborted: New activity log entries exist for this trip after reconciliation.', 1;
END

-- 9. Complete-Row Snapshot Verification (NIST FIPS 180-4 SHA-256)
IF OBJECT_ID('dbo.__GoaReconciliationSnapshot', 'U') IS NOT NULL
BEGIN
    -- Check Expense row hashes
    IF EXISTS (
        SELECT 1
        FROM dbo.Expenses e
        JOIN dbo.__GoaReconciliationSnapshot s ON s.entity_type = 'Expense' AND s.entity_id = e.expense_id
        WHERE e.trip_id = @trip_id
          AND s.full_row_sha256 <> CONVERT(VARCHAR(64), HASHBYTES('SHA2_256', 
                e.expense_id + N'|' + e.trip_id + N'|' + e.description + N'|' + CAST(e.amount AS VARCHAR(30)) + N'|' + e.paid_by_person_id + N'|' + CONVERT(VARCHAR(30), e.expense_date, 120)
              ), 2)
    )
    BEGIN
        ROLLBACK TRANSACTION;
        THROW 50023, 'Rollback aborted: Complete-row snapshot comparison failed on Expenses. Attributes (payer, date, description, or amount) have been modified.', 1;
    END

    -- Check ExpenseSplit row hashes
    IF EXISTS (
        SELECT 1
        FROM dbo.ExpenseSplits es
        JOIN dbo.__GoaReconciliationSnapshot s ON s.entity_type = 'Split' AND s.entity_id = es.split_id
        WHERE es.trip_id = @trip_id
          AND s.full_row_sha256 <> CONVERT(VARCHAR(64), HASHBYTES('SHA2_256', 
                es.split_id + N'|' + es.expense_id + N'|' + es.trip_id + N'|' + es.person_id + N'|' + CAST(es.amount AS VARCHAR(30))
              ), 2)
    )
    BEGIN
        ROLLBACK TRANSACTION;
        THROW 50023, 'Rollback aborted: Complete-row snapshot comparison failed on ExpenseSplits. Attributes (person, expense, or amount) have been modified.', 1;
    END

    -- Check Person row hashes
    IF EXISTS (
        SELECT 1
        FROM dbo.Persons p
        JOIN dbo.__GoaReconciliationSnapshot s ON s.entity_type = 'Person' AND s.entity_id = p.person_id
        WHERE p.trip_id = @trip_id
          AND s.full_row_sha256 <> CONVERT(VARCHAR(64), HASHBYTES('SHA2_256', 
                p.person_id + N'|' + p.trip_id + N'|' + p.name + N'|' + CAST(p.paid_amount AS VARCHAR(30)) + N'|' + CAST(p.owed_amount AS VARCHAR(30)) + N'|' + CAST(p.balance AS VARCHAR(30))
              ), 2)
    )
    BEGIN
        ROLLBACK TRANSACTION;
        THROW 50023, 'Rollback aborted: Complete-row snapshot comparison failed on Persons. Attributes (name, balance, paid, or owed) have been modified.', 1;
    END
END

-- 10. Mutation Ledger Check (Direct SQL mutations without activity logs)
IF OBJECT_ID('dbo.__ReconciliationMutationLedger', 'U') IS NOT NULL
BEGIN
    IF EXISTS (SELECT 1 FROM dbo.__ReconciliationMutationLedger WHERE trip_id = @trip_id)
    BEGIN
        ROLLBACK TRANSACTION;
        THROW 50022, 'Rollback aborted: Direct SQL mutations detected on trip records in mutation ledger since reconciliation.', 1;
    END
END

-- ALL DEPENDENCY & SNAPSHOT CHECKS PASSED. Proceed with atomic rollback.
PRINT 'All dependency and complete-row snapshot checks passed. Proceeding with safe rollback...';

-- Remove Restored ExpenseSplits
PRINT 'Removing restored expense splits...';
DELETE FROM dbo.ExpenseSplits
WHERE split_id IN (
    N'b1e0f001-food-4000-friend-split0000001',
    N'b1e0f002-room-5000-friend-split0000002',
    N'b1e0f003-car0-4520-friend-split0000003',
    N'b1e0f004-car0-4520-dipa00-split0000004'
);

-- Remove Restored Persons
PRINT 'Removing restored persons...';
DELETE FROM dbo.Persons
WHERE person_id IN (@friend_person_id, @dipa_person_id);

-- Reset Soumya's values to pre-reconciliation values
UPDATE dbo.Persons
SET paid_amount = 4000.00, owed_amount = 6006.66, balance = -2006.66
WHERE person_id = @soumya_person_id;

-- Cleanup Snapshot & Triggers
IF OBJECT_ID('dbo.__GoaReconciliationSnapshot', 'U') IS NOT NULL
    DROP TABLE dbo.__GoaReconciliationSnapshot;

IF OBJECT_ID('dbo.__ReconciliationMutationLedger', 'U') IS NOT NULL
    DROP TABLE dbo.__ReconciliationMutationLedger;

-- Audit Log
INSERT INTO dbo.ActivityLogs (log_id, user_id, trip_id, action_type, details, created_at)
VALUES (
    NEWID(), N'0d979a07-3c0b-4efc-a6ec-d3199f51335b', @trip_id, N'RECONCILIATION_ROLLBACK',
    N'Phase 2.8 hardened safety rollback: Reverted Goa trip reconciliation after verifying all snapshot and dependency guards.',
    GETDATE()
);

COMMIT TRANSACTION;
GO

-- Drop Triggers outside transaction batch
IF OBJECT_ID('dbo.TR_GoaTrip_Persons_MutationAudit', 'TR') IS NOT NULL
    DROP TRIGGER dbo.TR_GoaTrip_Persons_MutationAudit;
GO
IF OBJECT_ID('dbo.TR_GoaTrip_Expenses_MutationAudit', 'TR') IS NOT NULL
    DROP TRIGGER dbo.TR_GoaTrip_Expenses_MutationAudit;
GO
IF OBJECT_ID('dbo.TR_GoaTrip_ExpenseSplits_MutationAudit', 'TR') IS NOT NULL
    DROP TRIGGER dbo.TR_GoaTrip_ExpenseSplits_MutationAudit;
GO
