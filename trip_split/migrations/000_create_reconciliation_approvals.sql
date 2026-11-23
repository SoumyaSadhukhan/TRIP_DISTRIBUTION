-- ============================================================================
-- Migration: 000_create_reconciliation_approvals.sql
-- Sequence: Prerequisite Setup (Prior to Migration 001)
-- Purpose: Create persistent administrative governance tables:
--          1. dbo.AuthorizedReconciliationApprovers (Authorized Business Principals)
--          2. dbo.ReconciliationApprovals (Tamper-evident, single-use approval records)
-- ============================================================================

SET NOCOUNT ON;

-- 1. Create Authorized Business Principals Registry
IF OBJECT_ID('dbo.AuthorizedReconciliationApprovers', 'U') IS NULL
BEGIN
    PRINT 'Creating dbo.AuthorizedReconciliationApprovers registry...';
    CREATE TABLE dbo.AuthorizedReconciliationApprovers (
        approver_id NVARCHAR(100) NOT NULL,
        principal_name NVARCHAR(200) NOT NULL,
        email NVARCHAR(255) NOT NULL,
        role NVARCHAR(100) NOT NULL, -- 'CHIEF_FINANCIAL_OFFICER', 'LEAD_AUDITOR', 'FINANCIAL_CONTROLLER'
        is_active BIT NOT NULL DEFAULT 1,
        authorized_from DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
        authorized_until DATETIME2 NULL,
        created_at DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
        CONSTRAINT PK_AuthorizedReconciliationApprovers PRIMARY KEY CLUSTERED (approver_id),
        CONSTRAINT CK_AuthorizedApprovers_Role CHECK (role IN ('CHIEF_FINANCIAL_OFFICER', 'LEAD_AUDITOR', 'FINANCIAL_CONTROLLER'))
    );

    IF EXISTS (SELECT 1 FROM sys.database_principals WHERE name = 'public')
    BEGIN
        DENY INSERT, UPDATE, DELETE ON dbo.AuthorizedReconciliationApprovers TO public;
    END

    PRINT 'dbo.AuthorizedReconciliationApprovers created successfully.';
END
ELSE
BEGIN
    PRINT 'dbo.AuthorizedReconciliationApprovers already exists.';
END

-- 2. Create Persistent Governance Approvals Table
IF OBJECT_ID('dbo.ReconciliationApprovals', 'U') IS NULL
BEGIN
    PRINT 'Creating persistent administrative governance table: dbo.ReconciliationApprovals...';
    CREATE TABLE dbo.ReconciliationApprovals (
        approval_id UNIQUEIDENTIFIER NOT NULL DEFAULT NEWID(),
        trip_id NVARCHAR(100) NOT NULL,
        reconciliation_reference NVARCHAR(100) NOT NULL,
        reconciliation_version NVARCHAR(50) NOT NULL DEFAULT N'1.0',
        status NVARCHAR(50) NOT NULL, -- 'PENDING', 'APPROVED', 'REJECTED'
        approver_id NVARCHAR(100) NULL,
        approver_name NVARCHAR(200) NULL,
        approved_at DATETIME2 NULL,
        reason NVARCHAR(MAX) NOT NULL,
        reconciliation_type NVARCHAR(50) NOT NULL, -- 'ADMINISTRATIVE_ASSUMPTION_OVERRIDE' vs 'HISTORICAL_VERIFIED'
        original_values_json NVARCHAR(MAX) NOT NULL,
        proposed_values_json NVARCHAR(MAX) NOT NULL,
        is_administrative_override BIT NOT NULL DEFAULT 1,
        approval_signature NVARCHAR(64) NULL, -- SHA-256 tamper-evident payload hash
        is_consumed BIT NOT NULL DEFAULT 0, -- Prevents reuse
        consumed_at DATETIME2 NULL,
        consumed_by_migration NVARCHAR(100) NULL,
        created_at DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
        CONSTRAINT PK_ReconciliationApprovals PRIMARY KEY CLUSTERED (approval_id),
        CONSTRAINT UQ_ReconciliationApprovals_TripRef UNIQUE (trip_id, reconciliation_reference, reconciliation_version),
        CONSTRAINT CK_ReconciliationApprovals_Status CHECK (status IN ('PENDING', 'APPROVED', 'REJECTED')),
        CONSTRAINT CK_ReconciliationApprovals_Type CHECK (reconciliation_type IN ('ADMINISTRATIVE_ASSUMPTION_OVERRIDE', 'HISTORICAL_VERIFIED')),
        CONSTRAINT CK_ReconciliationApprovals_ApprovalState CHECK (
            (status = 'APPROVED' AND approved_at IS NOT NULL AND approver_id IS NOT NULL AND LEN(LTRIM(RTRIM(approver_id))) > 0 AND approval_signature IS NOT NULL) OR
            (status IN ('PENDING', 'REJECTED'))
        ),
        CONSTRAINT FK_ReconciliationApprovals_Approver FOREIGN KEY (approver_id) REFERENCES dbo.AuthorizedReconciliationApprovers(approver_id)
    );

    IF EXISTS (SELECT 1 FROM sys.database_principals WHERE name = 'public')
    BEGIN
        DENY INSERT, UPDATE, DELETE ON dbo.ReconciliationApprovals TO public;
    END

    PRINT 'dbo.ReconciliationApprovals created successfully with security constraints.';
END
ELSE
BEGIN
    PRINT 'dbo.ReconciliationApprovals already exists.';
END
GO
