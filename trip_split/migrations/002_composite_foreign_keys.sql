-- ==============================================================================================
-- MIGRATION SCRIPT: 001_composite_foreign_keys.sql
-- DESCRIPTION: Enforces relational trip-level composite integrity across Persons, Expenses, Splits, and Settlements.
-- IDEMPOTENCY: Guaranteed via table-specific sys catalog checks.
-- PREFLIGHT CHECKS: Validates zero orphan references and zero duplicate keys prior to schema changes.
-- TRANSACTION: Atomic with TRY/CATCH and rollback.
-- ROLLBACK PROCEDURE:
--   ALTER TABLE dbo.SettlementTransactions DROP CONSTRAINT IF EXISTS FK_Settlements_Persons_To_Trip;
--   ALTER TABLE dbo.SettlementTransactions DROP CONSTRAINT IF EXISTS FK_Settlements_Persons_From_Trip;
--   ALTER TABLE dbo.ExpenseSplits DROP CONSTRAINT IF EXISTS FK_ExpenseSplits_Persons_Trip;
--   ALTER TABLE dbo.ExpenseSplits DROP CONSTRAINT IF EXISTS FK_ExpenseSplits_Expenses_Trip;
--   ALTER TABLE dbo.Expenses DROP CONSTRAINT IF EXISTS FK_Expenses_Persons_Trip;
--   ALTER TABLE dbo.Expenses DROP CONSTRAINT IF EXISTS UQ_Expenses_ExpenseTrip;
--   ALTER TABLE dbo.Persons DROP CONSTRAINT IF EXISTS UQ_Persons_PersonTrip;
-- ==============================================================================================

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;

BEGIN TRY
    BEGIN TRANSACTION;

    PRINT '--- PHASE 1: PREFLIGHT INTEGRITY CHECKS ---';

    -- 1. Check duplicate composite keys on Persons
    IF EXISTS (
        SELECT person_id, trip_id 
        FROM dbo.Persons 
        GROUP BY person_id, trip_id 
        HAVING COUNT(1) > 1
    )
    BEGIN
        THROW 50001, 'PREFLIGHT FAILED: Duplicate (person_id, trip_id) discovered in Persons table.', 1;
    END;

    -- 2. Check duplicate composite keys on Expenses
    IF EXISTS (
        SELECT expense_id, trip_id 
        FROM dbo.Expenses 
        GROUP BY expense_id, trip_id 
        HAVING COUNT(1) > 1
    )
    BEGIN
        THROW 50002, 'PREFLIGHT FAILED: Duplicate (expense_id, trip_id) discovered in Expenses table.', 1;
    END;

    -- 3. Check orphan payer references in Expenses
    IF EXISTS (
        SELECT 1 
        FROM dbo.Expenses e
        LEFT JOIN dbo.Persons p ON e.paid_by_person_id = p.person_id AND e.trip_id = p.trip_id
        WHERE p.person_id IS NULL
    )
    BEGIN
        THROW 50003, 'PREFLIGHT FAILED: Orphan payer references found in Expenses table.', 1;
    END;

    -- 4. Check orphan expense references in ExpenseSplits
    IF EXISTS (
        SELECT 1 
        FROM dbo.ExpenseSplits es
        LEFT JOIN dbo.Expenses e ON es.expense_id = e.expense_id AND es.trip_id = e.trip_id
        WHERE e.expense_id IS NULL
    )
    BEGIN
        THROW 50004, 'PREFLIGHT FAILED: Orphan expense references found in ExpenseSplits table.', 1;
    END;

    -- 5. Check orphan person references in ExpenseSplits
    IF EXISTS (
        SELECT 1 
        FROM dbo.ExpenseSplits es
        LEFT JOIN dbo.Persons p ON es.person_id = p.person_id AND es.trip_id = p.trip_id
        WHERE p.person_id IS NULL
    )
    BEGIN
        THROW 50005, 'PREFLIGHT FAILED: Orphan person references found in ExpenseSplits table.', 1;
    END;

    -- 6. Check orphan person references in SettlementTransactions
    IF EXISTS (
        SELECT 1 
        FROM dbo.SettlementTransactions st
        LEFT JOIN dbo.Persons p1 ON st.from_person_id = p1.person_id AND st.trip_id = p1.trip_id
        LEFT JOIN dbo.Persons p2 ON st.to_person_id = p2.person_id AND st.trip_id = p2.trip_id
        WHERE p1.person_id IS NULL OR p2.person_id IS NULL
    )
    BEGIN
        THROW 50006, 'PREFLIGHT FAILED: Orphan from/to person references found in SettlementTransactions table.', 1;
    END;

    PRINT 'Preflight checks passed: zero duplicate keys and zero orphan references.';

    PRINT '--- PHASE 2: COMPOSITE UNIQUE CONSTRAINTS ---';

    -- Unique constraint on Persons(person_id, trip_id)
    IF NOT EXISTS (
        SELECT 1 
        FROM sys.key_constraints 
        WHERE parent_object_id = OBJECT_ID('dbo.Persons') AND name = 'UQ_Persons_PersonTrip'
    )
    BEGIN
        ALTER TABLE dbo.Persons ADD CONSTRAINT UQ_Persons_PersonTrip UNIQUE (person_id, trip_id);
        PRINT 'Created unique constraint UQ_Persons_PersonTrip on dbo.Persons.';
    END
    ELSE
    BEGIN
        PRINT 'Unique constraint UQ_Persons_PersonTrip already exists on dbo.Persons.';
    END;

    -- Unique constraint on Expenses(expense_id, trip_id)
    IF NOT EXISTS (
        SELECT 1 
        FROM sys.key_constraints 
        WHERE parent_object_id = OBJECT_ID('dbo.Expenses') AND name = 'UQ_Expenses_ExpenseTrip'
    )
    BEGIN
        ALTER TABLE dbo.Expenses ADD CONSTRAINT UQ_Expenses_ExpenseTrip UNIQUE (expense_id, trip_id);
        PRINT 'Created unique constraint UQ_Expenses_ExpenseTrip on dbo.Expenses.';
    END
    ELSE
    BEGIN
        PRINT 'Unique constraint UQ_Expenses_ExpenseTrip already exists on dbo.Expenses.';
    END;

    PRINT '--- PHASE 3: COMPOSITE FOREIGN KEY CONSTRAINTS ---';

    -- 1. Expenses -> Persons(paid_by_person_id, trip_id)
    IF NOT EXISTS (
        SELECT 1 
        FROM sys.foreign_keys 
        WHERE parent_object_id = OBJECT_ID('dbo.Expenses') AND name = 'FK_Expenses_Persons_Trip'
    )
    BEGIN
        ALTER TABLE dbo.Expenses
        ADD CONSTRAINT FK_Expenses_Persons_Trip
        FOREIGN KEY (paid_by_person_id, trip_id)
        REFERENCES dbo.Persons (person_id, trip_id)
        ON DELETE NO ACTION;
        PRINT 'Created FK_Expenses_Persons_Trip.';
    END
    ELSE
    BEGIN
        PRINT 'FK_Expenses_Persons_Trip already exists.';
    END;

    -- 2. ExpenseSplits -> Expenses(expense_id, trip_id)
    IF NOT EXISTS (
        SELECT 1 
        FROM sys.foreign_keys 
        WHERE parent_object_id = OBJECT_ID('dbo.ExpenseSplits') AND name = 'FK_ExpenseSplits_Expenses_Trip'
    )
    BEGIN
        ALTER TABLE dbo.ExpenseSplits
        ADD CONSTRAINT FK_ExpenseSplits_Expenses_Trip
        FOREIGN KEY (expense_id, trip_id)
        REFERENCES dbo.Expenses (expense_id, trip_id)
        ON DELETE CASCADE;
        PRINT 'Created FK_ExpenseSplits_Expenses_Trip (CASCADE).';
    END
    ELSE
    BEGIN
        PRINT 'FK_ExpenseSplits_Expenses_Trip already exists.';
    END;

    -- 3. ExpenseSplits -> Persons(person_id, trip_id)
    IF NOT EXISTS (
        SELECT 1 
        FROM sys.foreign_keys 
        WHERE parent_object_id = OBJECT_ID('dbo.ExpenseSplits') AND name = 'FK_ExpenseSplits_Persons_Trip'
    )
    BEGIN
        ALTER TABLE dbo.ExpenseSplits
        ADD CONSTRAINT FK_ExpenseSplits_Persons_Trip
        FOREIGN KEY (person_id, trip_id)
        REFERENCES dbo.Persons (person_id, trip_id)
        ON DELETE NO ACTION;
        PRINT 'Created FK_ExpenseSplits_Persons_Trip.';
    END
    ELSE
    BEGIN
        PRINT 'FK_ExpenseSplits_Persons_Trip already exists.';
    END;

    -- 4. SettlementTransactions -> Persons(from_person_id, trip_id)
    IF NOT EXISTS (
        SELECT 1 
        FROM sys.foreign_keys 
        WHERE parent_object_id = OBJECT_ID('dbo.SettlementTransactions') AND name = 'FK_Settlements_Persons_From_Trip'
    )
    BEGIN
        ALTER TABLE dbo.SettlementTransactions
        ADD CONSTRAINT FK_Settlements_Persons_From_Trip
        FOREIGN KEY (from_person_id, trip_id)
        REFERENCES dbo.Persons (person_id, trip_id)
        ON DELETE NO ACTION;
        PRINT 'Created FK_Settlements_Persons_From_Trip.';
    END
    ELSE
    BEGIN
        PRINT 'FK_Settlements_Persons_From_Trip already exists.';
    END;

    -- 5. SettlementTransactions -> Persons(to_person_id, trip_id)
    IF NOT EXISTS (
        SELECT 1 
        FROM sys.foreign_keys 
        WHERE parent_object_id = OBJECT_ID('dbo.SettlementTransactions') AND name = 'FK_Settlements_Persons_To_Trip'
    )
    BEGIN
        ALTER TABLE dbo.SettlementTransactions
        ADD CONSTRAINT FK_Settlements_Persons_To_Trip
        FOREIGN KEY (to_person_id, trip_id)
        REFERENCES dbo.Persons (person_id, trip_id)
        ON DELETE NO ACTION;
        PRINT 'Created FK_Settlements_Persons_To_Trip.';
    END
    ELSE
    BEGIN
        PRINT 'FK_Settlements_Persons_To_Trip already exists.';
    END;

    COMMIT TRANSACTION;
    PRINT 'Migration 001_composite_foreign_keys committed successfully.';
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0
    BEGIN
        ROLLBACK TRANSACTION;
        PRINT 'Transaction rolled back due to error.';
    END;
    THROW;
END CATCH;

