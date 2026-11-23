-- ==============================================================================================
-- MIGRATION SCRIPT: 003_harden_otp_schema.sql
-- DESCRIPTION: Hardens OtpVerification table with HMAC-SHA256 hash storage, failed attempt counters,
--              lockout timestamps, IP rate tracking, and redacts legacy plaintext OTPs.
-- IDEMPOTENCY: Guaranteed via sys catalog checks.
-- TRANSACTION: Atomic with TRY/CATCH and rollback.
-- ==============================================================================================

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;

BEGIN TRY
    BEGIN TRANSACTION;

    PRINT '--- PHASE 1: ADD OTP SECURITY COLUMNS ---';

    -- 1. otp_hash column
    IF NOT EXISTS (
        SELECT 1 
        FROM sys.columns 
        WHERE object_id = OBJECT_ID('dbo.OtpVerification') AND name = 'otp_hash'
    )
    BEGIN
        ALTER TABLE dbo.OtpVerification ADD otp_hash NVARCHAR(128) NULL;
        PRINT 'Added otp_hash column to dbo.OtpVerification.';
    END
    ELSE
    BEGIN
        PRINT 'Column otp_hash already exists on dbo.OtpVerification.';
    END;

    -- 2. failed_attempts column with default constraint
    IF NOT EXISTS (
        SELECT 1 
        FROM sys.columns 
        WHERE object_id = OBJECT_ID('dbo.OtpVerification') AND name = 'failed_attempts'
    )
    BEGIN
        ALTER TABLE dbo.OtpVerification ADD failed_attempts INT NOT NULL CONSTRAINT DF_OtpVerification_FailedAttempts DEFAULT 0;
        PRINT 'Added failed_attempts column with default 0 to dbo.OtpVerification.';
    END
    ELSE
    BEGIN
        PRINT 'Column failed_attempts already exists on dbo.OtpVerification.';
    END;

    -- 3. max_attempts column with default constraint
    IF NOT EXISTS (
        SELECT 1 
        FROM sys.columns 
        WHERE object_id = OBJECT_ID('dbo.OtpVerification') AND name = 'max_attempts'
    )
    BEGIN
        ALTER TABLE dbo.OtpVerification ADD max_attempts INT NOT NULL CONSTRAINT DF_OtpVerification_MaxAttempts DEFAULT 5;
        PRINT 'Added max_attempts column with default 5 to dbo.OtpVerification.';
    END
    ELSE
    BEGIN
        PRINT 'Column max_attempts already exists on dbo.OtpVerification.';
    END;

    -- 4. lockout_until column
    IF NOT EXISTS (
        SELECT 1 
        FROM sys.columns 
        WHERE object_id = OBJECT_ID('dbo.OtpVerification') AND name = 'lockout_until'
    )
    BEGIN
        ALTER TABLE dbo.OtpVerification ADD lockout_until DATETIME NULL;
        PRINT 'Added lockout_until column to dbo.OtpVerification.';
    END
    ELSE
    BEGIN
        PRINT 'Column lockout_until already exists on dbo.OtpVerification.';
    END;

    -- 5. ip_address column
    IF NOT EXISTS (
        SELECT 1 
        FROM sys.columns 
        WHERE object_id = OBJECT_ID('dbo.OtpVerification') AND name = 'ip_address'
    )
    BEGIN
        ALTER TABLE dbo.OtpVerification ADD ip_address NVARCHAR(45) NULL;
        PRINT 'Added ip_address column to dbo.OtpVerification.';
    END
    ELSE
    BEGIN
        PRINT 'Column ip_address already exists on dbo.OtpVerification.';
    END;

    PRINT '--- PHASE 2: HISTORICAL OTP DATA SANITIZATION ---';

    -- Securely redact legacy plaintext OTP codes
    EXEC('UPDATE dbo.OtpVerification SET otp_code = ''REDACTED'' WHERE otp_code IS NOT NULL AND otp_code <> ''REDACTED'';');
    PRINT 'Sanitized historical OTP records: plaintext otp_code permanently replaced with REDACTED.';

    -- Invalidate any historical active unverified rows without hash or already expired
    EXEC('UPDATE dbo.OtpVerification SET is_verified = 1 WHERE is_verified = 0 AND (otp_hash IS NULL OR expires_at < GETUTCDATE());');
    PRINT 'Invalidated legacy unhashed or expired OTP records.';

    PRINT '--- PHASE 3: PERFORMANCE AND RATE LIMITING INDEXES ---';

    IF NOT EXISTS (
        SELECT 1 
        FROM sys.indexes 
        WHERE object_id = OBJECT_ID('dbo.OtpVerification') AND name = 'IX_OtpVerification_Lookup'
    )
    BEGIN
        EXEC('CREATE INDEX IX_OtpVerification_Lookup ON dbo.OtpVerification (purpose, is_verified, expires_at);');
        PRINT 'Created index IX_OtpVerification_Lookup.';
    END
    ELSE
    BEGIN
        PRINT 'Index IX_OtpVerification_Lookup already exists.';
    END;

    IF NOT EXISTS (
        SELECT 1 
        FROM sys.indexes 
        WHERE object_id = OBJECT_ID('dbo.OtpVerification') AND name = 'IX_OtpVerification_IpRateLimit'
    )
    BEGIN
        EXEC('CREATE INDEX IX_OtpVerification_IpRateLimit ON dbo.OtpVerification (ip_address, created_at);');
        PRINT 'Created index IX_OtpVerification_IpRateLimit.';
    END
    ELSE
    BEGIN
        PRINT 'Index IX_OtpVerification_IpRateLimit already exists.';
    END;

    COMMIT TRANSACTION;
    PRINT 'Migration 003_harden_otp_schema completed successfully.';
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0
        ROLLBACK TRANSACTION;

    DECLARE @ErrMsg NVARCHAR(4000) = ERROR_MESSAGE();
    DECLARE @ErrSev INT = ERROR_SEVERITY();
    DECLARE @ErrState INT = ERROR_STATE();
    RAISERROR(@ErrMsg, @ErrSev, @ErrState);
END CATCH;
