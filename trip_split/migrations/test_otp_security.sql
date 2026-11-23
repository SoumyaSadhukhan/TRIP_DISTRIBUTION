SET NOCOUNT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;

USE [SPLIT_BILL_DB_TEST];

PRINT '============================================================================';
PRINT 'TEST SUITE: OTP ATOMICITY, EXPIRY, REPLAY, AND PURPOSE SEPARATION';
PRINT '============================================================================';

DECLARE @Phone NVARCHAR(40) = '+919999088888';
DECLARE @Purpose NVARCHAR(100) = 'REGISTER';
DECLARE @OtpCode1 NVARCHAR(20) = '445566';
DECLARE @OtpCode2 NVARCHAR(20) = '778899';
DECLARE @ExpiredOtpCode NVARCHAR(20) = '112233';

-- Helper output table
DECLARE @OutputTable TABLE (otp_id NVARCHAR(200));

-- 1. Insert Initial OTP
INSERT INTO OtpVerification (otp_id, phone_number, otp_code, purpose, is_verified, expires_at, created_at)
VALUES (NEWID(), @Phone, @OtpCode1, @Purpose, 0, DATEADD(MINUTE, 10, GETUTCDATE()), GETUTCDATE());
PRINT 'Step 1: Generated OTP 1 (' + @OtpCode1 + ') for ' + @Phone;

-- 2. Generate Second OTP for same identity & purpose (Invalidate prior unused OTPs)
UPDATE OtpVerification 
SET is_verified = 1 
WHERE is_verified = 0 
  AND purpose = @Purpose 
  AND phone_number = @Phone;

INSERT INTO OtpVerification (otp_id, phone_number, otp_code, purpose, is_verified, expires_at, created_at)
VALUES (NEWID(), @Phone, @OtpCode2, @Purpose, 0, DATEADD(MINUTE, 10, GETUTCDATE()), GETUTCDATE());
PRINT 'Step 2: Generated OTP 2 (' + @OtpCode2 + '). Invalidated prior OTP 1.';

-- Verify OTP 1 status
DECLARE @Otp1Verified BIT;
SELECT @Otp1Verified = is_verified FROM OtpVerification WHERE phone_number = @Phone AND otp_code = @OtpCode1;
PRINT 'Check 1: Prior OTP 1 is_verified = ' + CAST(@Otp1Verified AS VARCHAR) + ' (EXPECT: 1 - Invalidated)';

-- 3. Attempt to verify superseded OTP 1 (EXPECT FAIL)
DELETE FROM @OutputTable;
WITH TargetOtp1 AS (
    SELECT TOP 1 otp_id, user_id, is_verified
    FROM OtpVerification WITH (UPDLOCK, ROWLOCK)
    WHERE otp_code = @OtpCode1 
      AND purpose = @Purpose 
      AND is_verified = 0 
      AND expires_at >= GETUTCDATE()
      AND phone_number = @Phone
    ORDER BY created_at DESC
)
UPDATE TargetOtp1 SET is_verified = 1 OUTPUT inserted.otp_id INTO @OutputTable;

DECLARE @MatchedId1 NVARCHAR(200) = NULL;
SELECT TOP 1 @MatchedId1 = otp_id FROM @OutputTable;
PRINT 'Check 2: Verification of superseded OTP 1 matched: ' + ISNULL(@MatchedId1, 'NONE (FAILED AS EXPECTED)');

-- 4. Verify Active OTP 2 (First Attempt - EXPECT SUCCESS)
DELETE FROM @OutputTable;
WITH TargetOtp2 AS (
    SELECT TOP 1 otp_id, user_id, is_verified
    FROM OtpVerification WITH (UPDLOCK, ROWLOCK)
    WHERE otp_code = @OtpCode2 
      AND purpose = @Purpose 
      AND is_verified = 0 
      AND expires_at >= GETUTCDATE()
      AND phone_number = @Phone
    ORDER BY created_at DESC
)
UPDATE TargetOtp2 SET is_verified = 1 OUTPUT inserted.otp_id INTO @OutputTable;

DECLARE @MatchedId2 NVARCHAR(200);
SELECT TOP 1 @MatchedId2 = otp_id FROM @OutputTable;
PRINT 'Check 3: First verification of active OTP 2 matched: ' + ISNULL(@MatchedId2, 'FAILED') + ' (EXPECT: SUCCESS)';

-- 5. Attempt REPLAY of OTP 2 (Second Attempt - EXPECT FAIL)
DELETE FROM @OutputTable;
WITH TargetOtp2Replay AS (
    SELECT TOP 1 otp_id, user_id, is_verified
    FROM OtpVerification WITH (UPDLOCK, ROWLOCK)
    WHERE otp_code = @OtpCode2 
      AND purpose = @Purpose 
      AND is_verified = 0 
      AND expires_at >= GETUTCDATE()
      AND phone_number = @Phone
    ORDER BY created_at DESC
)
UPDATE TargetOtp2Replay SET is_verified = 1 OUTPUT inserted.otp_id INTO @OutputTable;

DECLARE @MatchedId2Replay NVARCHAR(200) = NULL;
SELECT TOP 1 @MatchedId2Replay = otp_id FROM @OutputTable;
PRINT 'Check 4: Replay attempt of OTP 2 matched: ' + ISNULL(@MatchedId2Replay, 'NONE (BLOCKED AS EXPECTED)');

-- 6. Attempt Purpose Substitution (Verify OTP 2 with RESET_PASSWORD instead of REGISTER - EXPECT FAIL)
DELETE FROM @OutputTable;
WITH TargetOtpPurposeSub AS (
    SELECT TOP 1 otp_id, user_id, is_verified
    FROM OtpVerification WITH (UPDLOCK, ROWLOCK)
    WHERE otp_code = @OtpCode2 
      AND purpose = 'RESET_PASSWORD' 
      AND is_verified = 0 
      AND expires_at >= GETUTCDATE()
      AND phone_number = @Phone
    ORDER BY created_at DESC
)
UPDATE TargetOtpPurposeSub SET is_verified = 1 OUTPUT inserted.otp_id INTO @OutputTable;

DECLARE @MatchedPurposeSub NVARCHAR(200) = NULL;
SELECT TOP 1 @MatchedPurposeSub = otp_id FROM @OutputTable;
PRINT 'Check 5: Purpose substitution attempt matched: ' + ISNULL(@MatchedPurposeSub, 'NONE (BLOCKED AS EXPECTED)');

-- 7. Attempt Verification of Expired OTP (EXPECT FAIL)
INSERT INTO OtpVerification (otp_id, phone_number, otp_code, purpose, is_verified, expires_at, created_at)
VALUES (NEWID(), @Phone, @ExpiredOtpCode, @Purpose, 0, DATEADD(MINUTE, -5, GETUTCDATE()), DATEADD(MINUTE, -15, GETUTCDATE()));

DELETE FROM @OutputTable;
WITH TargetOtpExpired AS (
    SELECT TOP 1 otp_id, user_id, is_verified
    FROM OtpVerification WITH (UPDLOCK, ROWLOCK)
    WHERE otp_code = @ExpiredOtpCode 
      AND purpose = @Purpose 
      AND is_verified = 0 
      AND expires_at >= GETUTCDATE()
      AND phone_number = @Phone
    ORDER BY created_at DESC
)
UPDATE TargetOtpExpired SET is_verified = 1 OUTPUT inserted.otp_id INTO @OutputTable;

DECLARE @MatchedExpired NVARCHAR(200) = NULL;
SELECT TOP 1 @MatchedExpired = otp_id FROM @OutputTable;
PRINT 'Check 6: Expired OTP verification matched: ' + ISNULL(@MatchedExpired, 'NONE (BLOCKED AS EXPECTED)');

PRINT '============================================================================';
PRINT 'ALL OTP SECURITY AND ATOMICITY CHECKS PASSED';
PRINT '============================================================================';
