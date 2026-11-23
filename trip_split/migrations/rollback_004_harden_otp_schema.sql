-- ==============================================================================================
-- ROLLBACK SCRIPT: rollback_003_harden_otp_schema.sql
-- DESCRIPTION: Reverses OTP hardening columns, default constraints, and lookup indexes.
-- TRANSACTION: Atomic with TRY/CATCH and rollback.
-- ==============================================================================================

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;

BEGIN TRY
    BEGIN TRANSACTION;

    PRINT '--- ROLLING BACK OTP HARDENING INDEXES ---';

    DROP INDEX IF EXISTS IX_OtpVerification_Lookup ON dbo.OtpVerification;
    DROP INDEX IF EXISTS IX_OtpVerification_IpRateLimit ON dbo.OtpVerification;

    PRINT '--- ROLLING BACK OTP HARDENING CONSTRAINTS & COLUMNS ---';

    -- Drop default constraints
    DECLARE @dfFailed NVARCHAR(128);
    SELECT @dfFailed = dc.name
    FROM sys.default_constraints dc
    JOIN sys.columns c ON dc.parent_object_id = c.object_id AND dc.parent_column_id = c.column_id
    WHERE dc.parent_object_id = OBJECT_ID('dbo.OtpVerification') AND c.name = 'failed_attempts';

    IF @dfFailed IS NOT NULL
    BEGIN
        EXEC('ALTER TABLE dbo.OtpVerification DROP CONSTRAINT ' + @dfFailed);
        PRINT 'Dropped default constraint on OtpVerification.failed_attempts.';
    END;

    DECLARE @dfMax NVARCHAR(128);
    SELECT @dfMax = dc.name
    FROM sys.default_constraints dc
    JOIN sys.columns c ON dc.parent_object_id = c.object_id AND dc.parent_column_id = c.column_id
    WHERE dc.parent_object_id = OBJECT_ID('dbo.OtpVerification') AND c.name = 'max_attempts';

    IF @dfMax IS NOT NULL
    BEGIN
        EXEC('ALTER TABLE dbo.OtpVerification DROP CONSTRAINT ' + @dfMax);
        PRINT 'Dropped default constraint on OtpVerification.max_attempts.';
    END;

    -- Drop columns
    IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.OtpVerification') AND name = 'ip_address')
    BEGIN
        ALTER TABLE dbo.OtpVerification DROP COLUMN ip_address;
        PRINT 'Dropped column OtpVerification.ip_address.';
    END;

    IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.OtpVerification') AND name = 'lockout_until')
    BEGIN
        ALTER TABLE dbo.OtpVerification DROP COLUMN lockout_until;
        PRINT 'Dropped column OtpVerification.lockout_until.';
    END;

    IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.OtpVerification') AND name = 'max_attempts')
    BEGIN
        ALTER TABLE dbo.OtpVerification DROP COLUMN max_attempts;
        PRINT 'Dropped column OtpVerification.max_attempts.';
    END;

    IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.OtpVerification') AND name = 'failed_attempts')
    BEGIN
        ALTER TABLE dbo.OtpVerification DROP COLUMN failed_attempts;
        PRINT 'Dropped column OtpVerification.failed_attempts.';
    END;

    IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.OtpVerification') AND name = 'otp_hash')
    BEGIN
        ALTER TABLE dbo.OtpVerification DROP COLUMN otp_hash;
        PRINT 'Dropped column OtpVerification.otp_hash.';
    END;

    COMMIT TRANSACTION;
    PRINT 'Rollback of 003_harden_otp_schema completed successfully.';
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0
        ROLLBACK TRANSACTION;

    DECLARE @ErrMsg NVARCHAR(4000) = ERROR_MESSAGE();
    DECLARE @ErrSev INT = ERROR_SEVERITY();
    DECLARE @ErrState INT = ERROR_STATE();
    RAISERROR(@ErrMsg, @ErrSev, @ErrState);
END CATCH;
