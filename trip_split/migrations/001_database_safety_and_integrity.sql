-- ============================================================================
-- SCRIPT: 001_database_safety_and_integrity.sql
-- TARGET: SQL Server (SPLIT_BILL_DB or SPLIT_BILL_DB_TEST)
-- PREREQUISITE: Run 002_reconcile_existing_data.sql first to ensure clean state
-- DESCRIPTION: Enforces trip-level composite relational integrity, cycle-free cascades,
--              and unique constraints across all 13 tables without triggering Error 1785.
-- ============================================================================

SET NOCOUNT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;

PRINT '============================================================================';
PRINT 'STEP 1: CREATING UNIQUE CONSTRAINTS & COMPOSITE ALTERNATE KEYS';
PRINT '============================================================================';

-- 1. Unique phone number on Users
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UQ_Users_Phone' AND object_id = OBJECT_ID('Users'))
BEGIN
    CREATE UNIQUE NONCLUSTERED INDEX UQ_Users_Phone ON Users(phone_number);
    PRINT 'Created unique index: UQ_Users_Phone.';
END;

-- 2. Unique email on Users (Filtered index for non-null/non-empty values)
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UQ_Users_Email' AND object_id = OBJECT_ID('Users'))
BEGIN
    CREATE UNIQUE NONCLUSTERED INDEX UQ_Users_Email ON Users(email) 
    WHERE email IS NOT NULL AND email <> '';
    PRINT 'Created unique filtered index: UQ_Users_Email.';
END;

-- 3. Unique FriendConnection pair (user_id, friend_user_id)
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UQ_FriendConnections_Pair' AND object_id = OBJECT_ID('FriendConnections'))
BEGIN
    CREATE UNIQUE NONCLUSTERED INDEX UQ_FriendConnections_Pair ON FriendConnections(user_id, friend_user_id);
    PRINT 'Created unique index: UQ_FriendConnections_Pair.';
END;

-- 4. Composite unique constraint on Persons(person_id, trip_id)
-- Required to enable trip-scoped foreign key references from Expenses and ExpenseSplits
IF NOT EXISTS (SELECT 1 FROM sys.key_constraints WHERE name = 'UQ_Persons_PersonId_TripId')
BEGIN
    ALTER TABLE Persons ADD CONSTRAINT UQ_Persons_PersonId_TripId UNIQUE (person_id, trip_id);
    PRINT 'Created composite unique constraint: UQ_Persons_PersonId_TripId.';
END;

-- 5. Composite unique constraint on Expenses(expense_id, trip_id)
-- Required to enable trip-scoped foreign key references from ExpenseSplits
IF NOT EXISTS (SELECT 1 FROM sys.key_constraints WHERE name = 'UQ_Expenses_ExpenseId_TripId')
BEGIN
    ALTER TABLE Expenses ADD CONSTRAINT UQ_Expenses_ExpenseId_TripId UNIQUE (expense_id, trip_id);
    PRINT 'Created composite unique constraint: UQ_Expenses_ExpenseId_TripId.';
END;

-- 6. Unique expense split per person per expense
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UQ_ExpenseSplits_Expense_Person' AND object_id = OBJECT_ID('ExpenseSplits'))
BEGIN
    CREATE UNIQUE NONCLUSTERED INDEX UQ_ExpenseSplits_Expense_Person ON ExpenseSplits(expense_id, person_id);
    PRINT 'Created unique index: UQ_ExpenseSplits_Expense_Person.';
END;

PRINT '============================================================================';
PRINT 'STEP 2: ENFORCING TRIP-LEVEL RELATIONAL INTEGRITY (FOREIGN KEYS)';
PRINT '============================================================================';

-- A. Trips -> Persons (Cascading delete on trip deletion)
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_Persons_Trips')
BEGIN
    ALTER TABLE Persons ADD CONSTRAINT FK_Persons_Trips 
    FOREIGN KEY (trip_id) REFERENCES Trips(trip_id) ON DELETE CASCADE;
    PRINT 'Created FK: FK_Persons_Trips (ON DELETE CASCADE).';
END;

-- B. Trips -> Expenses (Cascading delete on trip deletion)
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_Expenses_Trips')
BEGIN
    ALTER TABLE Expenses ADD CONSTRAINT FK_Expenses_Trips 
    FOREIGN KEY (trip_id) REFERENCES Trips(trip_id) ON DELETE CASCADE;
    PRINT 'Created FK: FK_Expenses_Trips (ON DELETE CASCADE).';
END;

-- C. Composite FK: Expenses(paid_by_person_id, trip_id) -> Persons(person_id, trip_id)
-- Enforces that the payer person belongs to the exact same trip as the expense.
-- Uses ON DELETE NO ACTION to prevent multiple cascade paths and accidental orphan expenses.
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_Expenses_Persons_Trip')
BEGIN
    ALTER TABLE Expenses ADD CONSTRAINT FK_Expenses_Persons_Trip 
    FOREIGN KEY (paid_by_person_id, trip_id) REFERENCES Persons(person_id, trip_id) ON DELETE NO ACTION;
    PRINT 'Created Composite FK: FK_Expenses_Persons_Trip (NO ACTION).';
END;

-- D. Composite FK: ExpenseSplits(expense_id, trip_id) -> Expenses(expense_id, trip_id)
-- Enforces that splits belong to the exact same trip as the expense.
-- Cascading delete: deleting an expense automatically deletes its split rows.
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_ExpenseSplits_Expenses_Trip')
BEGIN
    ALTER TABLE ExpenseSplits ADD CONSTRAINT FK_ExpenseSplits_Expenses_Trip 
    FOREIGN KEY (expense_id, trip_id) REFERENCES Expenses(expense_id, trip_id) ON DELETE CASCADE;
    PRINT 'Created Composite FK: FK_ExpenseSplits_Expenses_Trip (CASCADE).';
END;

-- E. Composite FK: ExpenseSplits(person_id, trip_id) -> Persons(person_id, trip_id)
-- Enforces that the person sharing the expense belongs to the exact same trip.
-- Uses ON DELETE NO ACTION to prevent multiple cascade paths (Cycle prevention).
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_ExpenseSplits_Persons_Trip')
BEGIN
    ALTER TABLE ExpenseSplits ADD CONSTRAINT FK_ExpenseSplits_Persons_Trip 
    FOREIGN KEY (person_id, trip_id) REFERENCES Persons(person_id, trip_id) ON DELETE NO ACTION;
    PRINT 'Created Composite FK: FK_ExpenseSplits_Persons_Trip (NO ACTION).';
END;

-- F. SettlementTransactions Foreign Keys (Trip-Scoped)
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_Settlements_Trips')
BEGIN
    ALTER TABLE SettlementTransactions ADD CONSTRAINT FK_Settlements_Trips 
    FOREIGN KEY (trip_id) REFERENCES Trips(trip_id) ON DELETE CASCADE;
    PRINT 'Created FK: FK_Settlements_Trips (CASCADE).';
END;

IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_Settlements_Persons_From_Trip')
BEGIN
    ALTER TABLE SettlementTransactions ADD CONSTRAINT FK_Settlements_Persons_From_Trip 
    FOREIGN KEY (from_person_id, trip_id) REFERENCES Persons(person_id, trip_id) ON DELETE NO ACTION;
    PRINT 'Created Composite FK: FK_Settlements_Persons_From_Trip (NO ACTION).';
END;

IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_Settlements_Persons_To_Trip')
BEGIN
    ALTER TABLE SettlementTransactions ADD CONSTRAINT FK_Settlements_Persons_To_Trip 
    FOREIGN KEY (to_person_id, trip_id) REFERENCES Persons(person_id, trip_id) ON DELETE NO ACTION;
    PRINT 'Created Composite FK: FK_Settlements_Persons_To_Trip (NO ACTION).';
END;

-- G. TripCollaborators -> Trips (Cascading delete on trip deletion)
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_TripCollaborators_Trips')
BEGIN
    ALTER TABLE TripCollaborators ADD CONSTRAINT FK_TripCollaborators_Trips 
    FOREIGN KEY (trip_id) REFERENCES Trips(trip_id) ON DELETE CASCADE;
    PRINT 'Created FK: FK_TripCollaborators_Trips (CASCADE).';
END;

-- H. Users Entity Foreign Keys
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_UserTokens_Users')
BEGIN
    ALTER TABLE UserTokens ADD CONSTRAINT FK_UserTokens_Users 
    FOREIGN KEY (user_id) REFERENCES Users(user_id) ON DELETE CASCADE;
    PRINT 'Created FK: FK_UserTokens_Users (CASCADE).';
END;

IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_Notifications_Users')
BEGIN
    ALTER TABLE Notifications ADD CONSTRAINT FK_Notifications_Users 
    FOREIGN KEY (user_id) REFERENCES Users(user_id) ON DELETE CASCADE;
    PRINT 'Created FK: FK_Notifications_Users (CASCADE).';
END;

IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_FriendConnections_Users')
BEGIN
    ALTER TABLE FriendConnections ADD CONSTRAINT FK_FriendConnections_Users 
    FOREIGN KEY (user_id) REFERENCES Users(user_id) ON DELETE CASCADE;
    PRINT 'Created FK: FK_FriendConnections_Users (CASCADE).';
END;

IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_FriendConnections_Friend_Users')
BEGIN
    ALTER TABLE FriendConnections ADD CONSTRAINT FK_FriendConnections_Friend_Users 
    FOREIGN KEY (friend_user_id) REFERENCES Users(user_id) ON DELETE NO ACTION;
    PRINT 'Created FK: FK_FriendConnections_Friend_Users (NO ACTION).';
END;

PRINT '============================================================================';
PRINT 'MIGRATION 001 EXECUTION & VERIFICATION COMPLETE';
PRINT '============================================================================';
