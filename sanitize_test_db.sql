SET NOCOUNT ON;

USE [SPLIT_BILL_DB_TEST];

PRINT '=== SANITIZING SPLIT_BILL_DB_TEST FOR SECURE TESTING ===';

-- 1. Invalidate all User Tokens
UPDATE UserTokens 
SET is_active = 0, 
    expires_at = DATEADD(DAY, -7, GETDATE()), 
    auth_token = 'REVOKED_TEST_TOKEN_' + CAST(token_id AS NVARCHAR(200));

PRINT 'Invalidated ' + CAST(@@ROWCOUNT AS VARCHAR) + ' UserTokens.';

-- 2. Invalidate all OTPs
UPDATE OtpVerification 
SET is_verified = 1, 
    expires_at = DATEADD(DAY, -7, GETDATE()), 
    otp_code = 'EXPIRED';

PRINT 'Invalidated ' + CAST(@@ROWCOUNT AS VARCHAR) + ' OtpVerification records.';

-- 3. Anonymize real user phone numbers & emails
-- Map of real users to synthetic test addresses:
-- Soumya: 7319261013 -> +919999000006, test_soumya@test.local
-- Dipa: +919832542323 -> +919999000007, test_dipa@test.local
-- Ranit: +919046978291 -> +919999000008, test_ranit@test.local
-- MANIK: +919046978292 -> +919999000009, test_manik@test.local

DECLARE @UserMappings TABLE (
    user_id NVARCHAR(200),
    old_phone NVARCHAR(40),
    new_phone NVARCHAR(40),
    new_email NVARCHAR(510)
);

INSERT INTO @UserMappings VALUES
('0d979a07-3c0b-4efc-a6ec-d3199f51335b', '7319261013', '+919999000006', 'test_soumya@test.local'),
('4f16ae4b-63e0-453a-9e35-27e6a754981a', '+919832542323', '+919999000007', 'test_dipa@test.local'),
('5278654b-4b32-4357-b0cb-daa8465460ac', '+919046978291', '+919999000008', 'test_ranit@test.local'),
('054020a2-f190-440c-9ae5-e8f1845e311f', '+919046978292', '+919999000009', 'test_manik@test.local');

-- Update Users
UPDATE u
SET u.phone_number = m.new_phone,
    u.email = m.new_email,
    u.username = 'test_user_' + SUBSTRING(m.new_phone, 8, 5)
FROM Users u
JOIN @UserMappings m ON u.user_id = m.user_id;

-- Update Persons
UPDATE p
SET p.phone_number = m.new_phone
FROM Persons p
JOIN @UserMappings m ON p.phone_number = m.old_phone;

-- Update TripCollaborators
UPDATE tc
SET tc.phone_number = m.new_phone
FROM TripCollaborators tc
JOIN @UserMappings m ON tc.phone_number = m.old_phone;

-- Update FriendConnections
UPDATE fc
SET fc.friend_phone = m.new_phone
FROM FriendConnections fc
JOIN @UserMappings m ON fc.friend_phone = m.old_phone;

PRINT '=== SANITIZATION COMPLETE ON SPLIT_BILL_DB_TEST ===';

SELECT user_id, phone_number, email, username FROM Users ORDER BY created_at;
