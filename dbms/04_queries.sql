-- ==============================================================================
-- 04_queries.sql
-- Trellis - Knowledge Graph Study Platform
-- Every SQL query used by the application, with JOINs utilized where possible.
-- Each query is categorized with an ID (R1..Rn for READ, W1..Wn for WRITE).
-- ==============================================================================

-- ==============================================================================
-- TABLE OF CONTENTS
-- ------------------------------------------------------------------------------
-- 1. AUTHENTICATION & SESSION MANAGEMENT
--    - R1: Database Connectivity Probe
--    - R2: User Login Lookup by Email
--    - R3: Active Session Validation with User Details (INNER JOIN)
--    - R4: User Lookup by Email for Password Reset
--    - R5: Password Reset Token Validation (INNER JOIN)
--    - W1: Register Password User
--    - W2: Save Refresh Token
--    - W3: Sliding Extension of Refresh Token
--    - W4: Revoke Single Refresh Token (Logout)
--    - W5: Revoke All User Refresh Tokens (Global Logout)
--    - W6: Invalidate Pending Password Reset Tokens
--    - W7: Store Password Reset Token
--    - W8: Consume Password Reset Token
--    - W9: Update Password Hash
--
-- 2. GOOGLE OAUTH
--    - R6: Google Account Lookup by Subject Identifier
--    - R7: Google Sign-in Account Lookup by Email with Row Lock
--    - W10: Clear Password on Google Link for Unverified User
--    - W11: Link Google Subject and Mark Email Verified
--    - W12: Register Verified User via Google OAuth
--
-- 3. STUDENT PROFILE & ACCOUNT MANAGEMENT
--    - R8: Student Profile with Enrolled Goals (LEFT JOIN)
--    - R9: Verify Password Hash Before Account Deletion
--    - R10: Account Export Metadata
--    - W13: Update Student Name
--    - W14: Delete Account and Cascade Student Records
--
-- 4. LEARNING GOALS & SUBJECT REQUESTS
--    - R11: List Student Goals
--    - W15: Upsert Student Learning Goal
--    - R12: List Subject Requests with User Profile (LEFT JOIN)
--    - W16: Submit Subject Request
--
-- 5. KNOWLEDGE GRAPH PROGRESS: CLAIMS & OPENED TOPICS
--    - R13: List Student Self-Assessment Claims
--    - W17: Batch Insert Claims (Unnest Arrays)
--    - R14: List Manually Opened Topics
--    - W18: Mark Topic Opened Early
--
-- 6. CHAT MESSAGES & HELPER CONVERSATIONS
--    - R15: Paginated Chat History with Cursor (Self-JOIN)
--    - R16: Verify Chat Message Existence
--    - R17: Find Specific Chat Messages by IDs
--    - R18: Count Student Messages Typed Today (Rate Limiting)
--    - W19: Insert Chat Message
--
-- 7. PROPOSALS ENGINE
--    - R19: Fetch Proposals with Check-ins and Experiences (Aggregations)
--    - R20: Lock Open Proposal for Save Decision (Row Lock)
--    - R21: Verify Proposal Existence
--    - W20: Cancel Stale Open Proposal in Subject
--    - W21: Insert Helper Proposal Linked to Chat Message
--    - W22: Mark Proposal Saved
--    - W23: Guarded Proposal State Move (Cancel / Undo)
--    - W24: Delete Check-ins of Undone Proposal (JOIN with USING)
--    - W25: Delete Experiences of Undone Proposal (JOIN with USING)
--
-- 8. CHECK-INS (TOPIC STATUS TRACKING)
--    - R22: List Check-ins with Origin Message ID (LEFT JOIN)
--    - R23: Fetch Single Check-in by ID (LEFT JOIN)
--    - R24: List Check-ins Linked to Specific Proposal (LEFT JOIN)
--    - W26: Insert Subtopic Check-in
--    - W27: Update Check-in Details
--    - W28: Delete Single Check-in
--
-- 9. EXPERIENCES (STUDENT LEARNING NOTES)
--    - R25: List Experiences with Origin Message ID (LEFT JOIN)
--    - R26: Fetch Single Experience by ID (LEFT JOIN)
--    - R27: List Experiences Linked to Specific Proposal (LEFT JOIN)
--    - W29: Insert Experience Note
--    - W30: Update Experience Note Details
--    - W31: Delete Single Experience Note
--
-- 10. PROMPT TAKES & PROMPT INSTRUCTIONS
--    - R28: List Recent Prompt Takes
--    - W32: Record Prompt Take Event
--    - R29: List Prompt Assembly Instructions
--    - W33: Upsert Prompt Instruction (Seeding)
--    - W34: Delete Obsolete Instructions (Seeding)
--
-- 11. AI COST ACCOUNTING & RESOURCE LIMITS
--    - R30: Calculate AI Spend in Time Windows (CTE + LEFT JOIN)
--    - R31: Acquire Transaction Advisory Lock for Budget Reservation
--    - R32: AI Spend Summary by Time Periods (CTE + CROSS JOIN LATERAL + LEFT JOIN)
--    - R33: AI Top Spending Accounts with User Details (CTE + INNER JOIN + LEFT JOIN)
--    - R34: Count Stuck Pending AI Calls
--    - R35: Helper Reader Classification Breakdown (7 Days)
--    - R36: AI Call Latency Percentiles & Error Distribution (7 Days)
--    - W35: Reserve AI Call Budget
--    - W36: Settle Completed AI Call
--
-- 12. DATABASE MIGRATIONS INFRASTRUCTURE
--    - R37: List Executed Migrations
--    - W37: Record Applied Migration
-- ==============================================================================


-- ==============================================================================
-- 1. AUTHENTICATION & SESSION MANAGEMENT
-- ==============================================================================

-- READ
-- Id: R1
-- Feature: Health check probe to ensure Postgres connectivity
-- Source: backend/src/app.ts (GET /api/health), backend/src/index.ts (start)
SELECT 1;


-- READ
-- Id: R2
-- Feature: Lookup user credentials by email for password authentication
-- Source: backend/src/repos/users.repo.ts (findLoginByEmail)
-- Parameters: $1 = email (text)
SELECT id, hashed_password
FROM users
WHERE email = $1;


-- READ
-- Id: R3
-- Feature: Validate active refresh token and retrieve user profile using an INNER JOIN
-- Source: backend/src/repos/auth.repo.ts (useRefreshToken), backend/src/repos/users.repo.ts (getStudent)
-- Parameters: $1 = token_hash (text)
SELECT u.id, u.name, u.email, u.joined_at, rt.id AS token_id, rt.expires_at
FROM refresh_tokens rt
JOIN users u ON u.id = rt.user_id
WHERE rt.token_hash = $1
  AND rt.expires_at > NOW();


-- READ
-- Id: R4
-- Feature: Lookup user ID by email to issue password reset token
-- Source: backend/src/repos/auth.repo.ts (createPasswordReset)
-- Parameters: $1 = email (text)
SELECT id
FROM users
WHERE email = $1;


-- READ
-- Id: R5
-- Feature: Validate unused password reset link and fetch user profile using an INNER JOIN
-- Source: backend/src/repos/auth.repo.ts (usePasswordReset)
-- Parameters: $1 = token_hash (text)
SELECT pr.id, pr.user_id, pr.expires_at, u.email, u.name
FROM password_resets pr
JOIN users u ON u.id = pr.user_id
WHERE pr.token_hash = $1
  AND pr.used_at IS NULL
  AND pr.expires_at > NOW();


-- WRITE
-- Id: W1
-- Feature: Register new student account with password
-- Source: backend/src/repos/users.repo.ts (createPasswordUser)
-- Parameters: $1 = name (text), $2 = email (text), $3 = hashed_password (text)
INSERT INTO users (name, email, hashed_password)
VALUES ($1, $2, $3)
ON CONFLICT (email) DO NOTHING
RETURNING id;


-- WRITE
-- Id: W2
-- Feature: Store new SHA-256 hashed refresh token with expiry window
-- Source: backend/src/repos/auth.repo.ts (saveRefreshToken)
-- Parameters: $1 = user_id (int), $2 = token_hash (text), $3 = refresh_token_days (int)
INSERT INTO refresh_tokens (user_id, token_hash, expires_at)
VALUES ($1, $2, NOW() + make_interval(days => $3));


-- WRITE
-- Id: W3
-- Feature: Extend expiry of valid refresh token upon session refresh (sliding window)
-- Source: backend/src/repos/auth.repo.ts (useRefreshToken)
-- Parameters: $1 = token_hash (text), $2 = refresh_token_days (int)
UPDATE refresh_tokens
SET expires_at = NOW() + make_interval(days => $2)
WHERE token_hash = $1
  AND expires_at > NOW()
RETURNING user_id;


-- WRITE
-- Id: W4
-- Feature: Revoke specific refresh token upon user logout
-- Source: backend/src/repos/auth.repo.ts (deleteRefreshToken)
-- Parameters: $1 = token_hash (text)
DELETE FROM refresh_tokens
WHERE token_hash = $1;


-- WRITE
-- Id: W5
-- Feature: Invalidate all active refresh tokens for a user (global logout on password change/unlink)
-- Source: backend/src/repos/auth.repo.ts (usePasswordReset), backend/src/repos/users.repo.ts (signInWithGoogle)
-- Parameters: $1 = user_id (int)
DELETE FROM refresh_tokens
WHERE user_id = $1;


-- WRITE
-- Id: W6
-- Feature: Invalidate previous pending password reset tokens when issuing a new one
-- Source: backend/src/repos/auth.repo.ts (createPasswordReset)
-- Parameters: $1 = user_id (int)
DELETE FROM password_resets
WHERE user_id = $1
  AND used_at IS NULL;


-- WRITE
-- Id: W7
-- Feature: Create new password reset token with 1-hour expiration
-- Source: backend/src/repos/auth.repo.ts (createPasswordReset)
-- Parameters: $1 = user_id (int), $2 = token_hash (text)
INSERT INTO password_resets (user_id, token_hash, expires_at)
VALUES ($1, $2, NOW() + INTERVAL '1 hour');


-- WRITE
-- Id: W8
-- Feature: Mark password reset token as used (single-use guard against replay attacks)
-- Source: backend/src/repos/auth.repo.ts (usePasswordReset)
-- Parameters: $1 = token_hash (text)
UPDATE password_resets
SET used_at = NOW()
WHERE token_hash = $1
  AND used_at IS NULL
  AND expires_at > NOW()
RETURNING user_id;


-- WRITE
-- Id: W9
-- Feature: Update password hash after successful password reset verification
-- Source: backend/src/repos/auth.repo.ts (usePasswordReset)
-- Parameters: $1 = user_id (int), $2 = hashed_password (text)
UPDATE users
SET hashed_password = $2
WHERE id = $1;


-- ==============================================================================
-- 2. GOOGLE OAUTH
-- ==============================================================================

-- READ
-- Id: R6
-- Feature: Lookup existing user ID linked to Google OAuth subject identifier
-- Source: backend/src/repos/users.repo.ts (signInWithGoogle)
-- Parameters: $1 = google_sub (text)
SELECT id
FROM users
WHERE google_sub = $1;


-- READ
-- Id: R7
-- Feature: Lookup and lock user row by email during Google OAuth login/link transaction
-- Source: backend/src/repos/users.repo.ts (signInWithGoogle)
-- Parameters: $1 = email (text)
SELECT id, email_verified_at
FROM users
WHERE email = $1
FOR UPDATE;


-- WRITE
-- Id: W10
-- Feature: Strip unverified password when linking Google OAuth to prevent account takeover
-- Source: backend/src/repos/users.repo.ts (signInWithGoogle)
-- Parameters: $1 = user_id (int)
UPDATE users
SET hashed_password = NULL
WHERE id = $1;


-- WRITE
-- Id: W11
-- Feature: Link Google subject identifier to existing user and mark email verified
-- Source: backend/src/repos/users.repo.ts (signInWithGoogle)
-- Parameters: $1 = user_id (int), $2 = google_sub (text)
UPDATE users
SET google_sub = $2,
    email_verified_at = COALESCE(email_verified_at, NOW())
WHERE id = $1;


-- WRITE
-- Id: W12
-- Feature: Create new verified student account directly from Google OAuth profile
-- Source: backend/src/repos/users.repo.ts (signInWithGoogle)
-- Parameters: $1 = name (text), $2 = email (text), $3 = google_sub (text)
INSERT INTO users (name, email, google_sub, email_verified_at)
VALUES ($1, $2, $3, NOW())
ON CONFLICT (email) DO NOTHING
RETURNING id;


-- ==============================================================================
-- 3. STUDENT PROFILE & ACCOUNT MANAGEMENT
-- ==============================================================================

-- READ
-- Id: R8
-- Feature: Fetch student profile joined with active learning goals using a LEFT JOIN
-- Source: backend/src/repos/users.repo.ts (getStudent), backend/src/repos/goals.repo.ts (listGoals)
-- Parameters: $1 = user_id (int)
SELECT u.id, u.name, u.email, u.joined_at,
       u.hashed_password IS NOT NULL AS has_password,
       g.subject_id, g.goal_id, g.since AS goal_since
FROM users u
LEFT JOIN student_goals g ON g.user_id = u.id
WHERE u.id = $1
ORDER BY g.since, g.subject_id;


-- READ
-- Id: R9
-- Feature: Fetch password hash by user ID to verify password before account deletion
-- Source: backend/src/repos/users.repo.ts (findLoginById)
-- Parameters: $1 = user_id (int)
SELECT id, hashed_password
FROM users
WHERE id = $1;


-- READ
-- Id: R10
-- Feature: Retrieve user metadata and authentication provider status for data export
-- Source: backend/src/repos/users.repo.ts (getAccountForExport)
-- Parameters: $1 = user_id (int)
SELECT name, email, joined_at,
       hashed_password IS NOT NULL AS has_password,
       google_sub IS NOT NULL AS google,
       email_verified_at
FROM users
WHERE id = $1;


-- WRITE
-- Id: W13
-- Feature: Update student display name
-- Source: backend/src/repos/users.repo.ts (updateName)
-- Parameters: $1 = user_id (int), $2 = name (text)
UPDATE users
SET name = $2
WHERE id = $1;


-- WRITE
-- Id: W14
-- Feature: Permanently delete student account (cascades to all user records via ON DELETE CASCADE)
-- Source: backend/src/repos/users.repo.ts (deleteUser)
-- Parameters: $1 = user_id (int)
DELETE FROM users
WHERE id = $1;


-- ==============================================================================
-- 4. LEARNING GOALS & SUBJECT REQUESTS
-- ==============================================================================

-- READ
-- Id: R11
-- Feature: List learning goals selected by a student across all subjects
-- Source: backend/src/repos/goals.repo.ts (listGoals)
-- Parameters: $1 = user_id (int)
SELECT subject_id, goal_id, since
FROM student_goals
WHERE user_id = $1
ORDER BY since, subject_id;


-- WRITE
-- Id: W15
-- Feature: Upsert student learning goal, preserving choice timestamp if goal unchanged
-- Source: backend/src/repos/goals.repo.ts (setGoal)
-- Parameters: $1 = user_id (int), $2 = subject_id (text), $3 = goal_id (text)
INSERT INTO student_goals (user_id, subject_id, goal_id)
VALUES ($1, $2, $3)
ON CONFLICT (user_id, subject_id) DO UPDATE
  SET goal_id = EXCLUDED.goal_id,
      since   = CASE WHEN student_goals.goal_id = EXCLUDED.goal_id
                     THEN student_goals.since ELSE NOW() END
RETURNING subject_id, goal_id, since;


-- READ
-- Id: R12
-- Feature: List student's requested subjects joined with user profile using a LEFT JOIN
-- Source: backend/src/repos/subject-requests.repo.ts (listSubjectRequests)
-- Parameters: $1 = user_id (int)
SELECT sr.id, sr.text, sr.at, u.email, u.name
FROM subject_requests sr
LEFT JOIN users u ON u.id = sr.user_id
WHERE sr.user_id = $1
ORDER BY sr.at, sr.id;


-- WRITE
-- Id: W16
-- Feature: Record requested new subject submitted via "Learning something else?" form
-- Source: backend/src/repos/subject-requests.repo.ts (addSubjectRequest)
-- Parameters: $1 = user_id (int), $2 = text (text)
INSERT INTO subject_requests (user_id, text)
VALUES ($1, $2);


-- ==============================================================================
-- 5. KNOWLEDGE GRAPH PROGRESS: CLAIMS & OPENED TOPICS
-- ==============================================================================

-- READ
-- Id: R13
-- Feature: Retrieve chronological history of self-assessment claims (know/shaky/new)
-- Source: backend/src/repos/claims.repo.ts (listClaims)
-- Parameters: $1 = user_id (int)
SELECT topic_id, claim, at
FROM claims
WHERE user_id = $1
ORDER BY at, id;


-- WRITE
-- Id: W17
-- Feature: Batch insert topic claims in a single statement using unnest()
-- Source: backend/src/repos/claims.repo.ts (addClaims)
-- Parameters: $1 = user_id (int), $2 = topic_ids (text[]), $3 = claims (text[])
INSERT INTO claims (user_id, topic_id, claim)
SELECT $1, t.topic_id, t.claim
FROM unnest($2::text[], $3::text[]) AS t(topic_id, claim)
RETURNING topic_id, claim, at;


-- READ
-- Id: R14
-- Feature: Retrieve list of big topics manually opened early by student
-- Source: backend/src/repos/opened.repo.ts (listOpened)
-- Parameters: $1 = user_id (int)
SELECT topic_id
FROM opened_topics
WHERE user_id = $1
ORDER BY at, topic_id;


-- WRITE
-- Id: W18
-- Feature: Idempotently record a big topic opened early via "Look inside now"
-- Source: backend/src/repos/opened.repo.ts (openTopic)
-- Parameters: $1 = user_id (int), $2 = topic_id (text)
INSERT INTO opened_topics (user_id, topic_id)
VALUES ($1, $2)
ON CONFLICT (user_id, topic_id) DO NOTHING;


-- ==============================================================================
-- 6. CHAT MESSAGES & HELPER CONVERSATIONS
-- ==============================================================================

-- READ
-- Id: R15
-- Feature: Retrieve paginated chat history using a Self-JOIN on cursor message ID
-- Source: backend/src/repos/chat.repo.ts (listMessages)
-- Parameters: $1 = user_id (int), $2 = subject_id (text), $3 = limit (int), $4 = before_id (uuid)
SELECT m.id, m.subject_id, m.role, m.text, m.cards, m.asks, m.at
FROM chat_messages m
LEFT JOIN chat_messages cur ON cur.id = $4 AND cur.user_id = $1
WHERE m.user_id = $1
  AND m.subject_id = $2
  AND ($4::uuid IS NULL OR (m.at, m.id) < (cur.at, cur.id))
ORDER BY m.at DESC, m.id DESC
LIMIT $3;


-- READ
-- Id: R16
-- Feature: Verify chat message ownership and existence (cursor validation)
-- Source: backend/src/repos/chat.repo.ts (messageExists)
-- Parameters: $1 = id (uuid), $2 = user_id (int), $3 = subject_id (text)
SELECT 1
FROM chat_messages
WHERE id = $1
  AND user_id = $2
  AND subject_id = $3;


-- READ
-- Id: R17
-- Feature: Fetch specific chat messages by array of UUIDs
-- Source: backend/src/repos/chat.repo.ts (findMessages)
-- Parameters: $1 = user_id (int), $2 = ids (uuid[])
SELECT id, subject_id, role, text, cards, asks, at
FROM chat_messages
WHERE user_id = $1
  AND id = ANY($2::uuid[])
ORDER BY at, id;


-- READ
-- Id: R18
-- Feature: Count student messages typed today to enforce daily AI usage allowance
-- Source: backend/src/repos/chat.repo.ts (typedToday)
-- Parameters: $1 = user_id (int)
SELECT COUNT(*)::int AS n
FROM chat_messages
WHERE user_id = $1
  AND role = 'student'
  AND read_by IN ('model', 'rules')
  AND at >= date_trunc('day', NOW() AT TIME ZONE 'UTC') AT TIME ZONE 'UTC';


-- WRITE
-- Id: W19
-- Feature: Insert chat message with JSON payload for cards and asks
-- Source: backend/src/repos/chat.repo.ts (insertMessage)
-- Parameters: $1 = id (uuid), $2 = user_id (int), $3 = subject_id (text), $4 = role (text),
--             $5 = text (text), $6 = cards (jsonb), $7 = asks (jsonb), $8 = read_by (text)
INSERT INTO chat_messages (id, user_id, subject_id, role, text, cards, asks, read_by, at)
VALUES ($1, $2, $3, $4, $5, $6, $7, $8, clock_timestamp());


-- ==============================================================================
-- 7. PROPOSALS ENGINE
-- ==============================================================================

-- READ
-- Id: R19
-- Feature: Fetch proposals by IDs with aggregated check-in and experience IDs (JOINs & array_agg)
-- Source: backend/src/repos/chat.repo.ts (toMessages)
-- Parameters: $1 = user_id (int), $2 = proposal_ids (uuid[])
SELECT p.id, p.state, p.payload,
       COALESCE((SELECT array_agg(c.id ORDER BY c.at) FROM check_ins c WHERE c.proposal_id = p.id), '{}') AS check_in_ids,
       COALESCE((SELECT array_agg(e.id ORDER BY e.at) FROM experiences e WHERE e.proposal_id = p.id), '{}') AS experience_ids
FROM proposals p
WHERE p.user_id = $1
  AND p.id = ANY($2::uuid[]);


-- READ
-- Id: R20
-- Feature: Lock open proposal row for update during save decision (concurrency guard)
-- Source: backend/src/repos/proposals.repo.ts (lockOpenProposal)
-- Parameters: $1 = id (uuid), $2 = user_id (int)
SELECT subject_id, message_id, payload
FROM proposals
WHERE id = $1
  AND user_id = $2
  AND state = 'open'
FOR UPDATE;


-- READ
-- Id: R21
-- Feature: Check proposal existence to distinguish 409 (already decided) from 404 (not found)
-- Source: backend/src/repos/proposals.repo.ts (proposalExists)
-- Parameters: $1 = id (uuid), $2 = user_id (int)
SELECT 1
FROM proposals
WHERE id = $1
  AND user_id = $2;


-- WRITE
-- Id: W20
-- Feature: Automatically cancel older open proposal when helper creates a new proposal
-- Source: backend/src/repos/chat.repo.ts (insertMessage)
-- Parameters: $1 = user_id (int), $2 = subject_id (text)
UPDATE proposals
SET state = 'cancelled',
    decided_at = NOW()
WHERE user_id = $1
  AND subject_id = $2
  AND state = 'open';


-- WRITE
-- Id: W21
-- Feature: Insert open proposal offered by helper message
-- Source: backend/src/repos/chat.repo.ts (insertMessage)
-- Parameters: $1 = id (uuid), $2 = user_id (int), $3 = subject_id (text), $4 = message_id (uuid), $5 = payload (jsonb)
INSERT INTO proposals (id, user_id, subject_id, message_id, payload)
VALUES ($1, $2, $3, $4, $5);


-- WRITE
-- Id: W22
-- Feature: Mark proposal saved with updated student payload
-- Source: backend/src/repos/proposals.repo.ts (markSaved)
-- Parameters: $1 = id (uuid), $2 = payload (jsonb)
UPDATE proposals
SET state = 'saved',
    payload = $2,
    decided_at = NOW()
WHERE id = $1;


-- WRITE
-- Id: W23
-- Feature: Guarded state transition for proposals (open -> cancelled, saved -> undone)
-- Source: backend/src/repos/proposals.repo.ts (moveState)
-- Parameters: $1 = id (uuid), $2 = user_id (int), $3 = from_state (text), $4 = to_state (text)
UPDATE proposals
SET state = $4,
    decided_at = NOW()
WHERE id = $1
  AND user_id = $2
  AND state = $3
RETURNING message_id;


-- WRITE
-- Id: W24
-- Feature: Undo proposal - remove saved check-ins using a JOIN with USING clause
-- Source: backend/src/repos/proposals.repo.ts (deleteSavedRows)
-- Parameters: $1 = user_id (int), $2 = proposal_id (uuid)
DELETE FROM check_ins c
USING proposals p
WHERE c.proposal_id = p.id
  AND c.user_id = $1
  AND p.id = $2;


-- WRITE
-- Id: W25
-- Feature: Undo proposal - remove saved experiences using a JOIN with USING clause
-- Source: backend/src/repos/proposals.repo.ts (deleteSavedRows)
-- Parameters: $1 = user_id (int), $2 = proposal_id (uuid)
DELETE FROM experiences e
USING proposals p
WHERE e.proposal_id = p.id
  AND e.user_id = $1
  AND p.id = $2;


-- ==============================================================================
-- 8. CHECK-INS (TOPIC STATUS TRACKING)
-- ==============================================================================

-- READ
-- Id: R22
-- Feature: List all check-ins for student joined with proposals via LEFT JOIN
-- Source: backend/src/repos/check-ins.repo.ts (listCheckIns)
-- Parameters: $1 = user_id (int)
SELECT c.id, c.topic_id, c.outcome, c.text, c.at, p.message_id
FROM check_ins c
LEFT JOIN proposals p ON p.id = c.proposal_id
WHERE c.user_id = $1
ORDER BY c.at DESC, c.id;


-- READ
-- Id: R23
-- Feature: Fetch single check-in by ID joined with proposal via LEFT JOIN
-- Source: backend/src/repos/check-ins.repo.ts (updateCheckIn)
-- Parameters: $1 = user_id (int), $2 = id (uuid)
SELECT c.id, c.topic_id, c.outcome, c.text, c.at, p.message_id
FROM check_ins c
LEFT JOIN proposals p ON p.id = c.proposal_id
WHERE c.user_id = $1
  AND c.id = $2;


-- READ
-- Id: R24
-- Feature: List check-ins created by a specific proposal via LEFT JOIN
-- Source: backend/src/repos/check-ins.repo.ts (listCheckInsOfProposal)
-- Parameters: $1 = user_id (int), $2 = proposal_id (uuid)
SELECT c.id, c.topic_id, c.outcome, c.text, c.at, p.message_id
FROM check_ins c
LEFT JOIN proposals p ON p.id = c.proposal_id
WHERE c.user_id = $1
  AND c.proposal_id = $2
ORDER BY c.at, c.id;


-- WRITE
-- Id: W26
-- Feature: Insert check-in progress update linked to saved proposal
-- Source: backend/src/repos/check-ins.repo.ts (insertCheckIns)
-- Parameters: $1 = user_id (int), $2 = topic_id (text), $3 = outcome (text), $4 = text (text), $5 = proposal_id (uuid)
INSERT INTO check_ins (user_id, topic_id, outcome, text, proposal_id, at)
VALUES ($1, $2, $3, $4, $5, clock_timestamp());


-- WRITE
-- Id: W27
-- Feature: Update check-in topic, outcome, or text with partial COALESCE
-- Source: backend/src/repos/check-ins.repo.ts (updateCheckIn)
-- Parameters: $1 = user_id (int), $2 = id (uuid), $3 = topic_id (text), $4 = outcome (text), $5 = text (text)
UPDATE check_ins
SET topic_id = COALESCE($3, topic_id),
    outcome  = COALESCE($4, outcome),
    text     = COALESCE($5, text)
WHERE user_id = $1
  AND id = $2
RETURNING id;


-- WRITE
-- Id: W28
-- Feature: Delete single check-in record
-- Source: backend/src/repos/check-ins.repo.ts (deleteCheckIn)
-- Parameters: $1 = user_id (int), $2 = id (uuid)
DELETE FROM check_ins
WHERE user_id = $1
  AND id = $2;


-- ==============================================================================
-- 9. EXPERIENCES (STUDENT LEARNING NOTES)
-- ==============================================================================

-- READ
-- Id: R25
-- Feature: List all student experiences joined with proposals via LEFT JOIN
-- Source: backend/src/repos/experiences.repo.ts (listExperiences)
-- Parameters: $1 = user_id (int)
SELECT e.id, e.topic_id, e.kind, e.text, e.line, e.at, p.message_id
FROM experiences e
LEFT JOIN proposals p ON p.id = e.proposal_id
WHERE e.user_id = $1
ORDER BY e.at DESC, e.id;


-- READ
-- Id: R26
-- Feature: Fetch single experience note by ID joined with proposal via LEFT JOIN
-- Source: backend/src/repos/experiences.repo.ts (updateExperience)
-- Parameters: $1 = user_id (int), $2 = id (uuid)
SELECT e.id, e.topic_id, e.kind, e.text, e.line, e.at, p.message_id
FROM experiences e
LEFT JOIN proposals p ON p.id = e.proposal_id
WHERE e.user_id = $1
  AND e.id = $2;


-- READ
-- Id: R27
-- Feature: List experiences created by a specific proposal via LEFT JOIN
-- Source: backend/src/repos/experiences.repo.ts (listExperiencesOfProposal)
-- Parameters: $1 = user_id (int), $2 = proposal_id (uuid)
SELECT e.id, e.topic_id, e.kind, e.text, e.line, e.at, p.message_id
FROM experiences e
LEFT JOIN proposals p ON p.id = e.proposal_id
WHERE e.user_id = $1
  AND e.proposal_id = $2
ORDER BY e.at, e.id;


-- WRITE
-- Id: W29
-- Feature: Insert student learning experience note linked to proposal
-- Source: backend/src/repos/experiences.repo.ts (insertExperiences)
-- Parameters: $1 = user_id (int), $2 = topic_id (text), $3 = kind (text), $4 = text (text),
--             $5 = line (text), $6 = proposal_id (uuid)
INSERT INTO experiences (user_id, topic_id, kind, text, line, proposal_id, at)
VALUES ($1, $2, $3, $4, $5, $6, clock_timestamp());


-- WRITE
-- Id: W30
-- Feature: Update experience note text, compiled line, and category
-- Source: backend/src/repos/experiences.repo.ts (updateExperience)
-- Parameters: $1 = user_id (int), $2 = id (uuid), $3 = text (text), $4 = line (text), $5 = kind (text)
UPDATE experiences
SET text = $3,
    line = $4,
    kind = COALESCE($5, kind)
WHERE user_id = $1
  AND id = $2;


-- WRITE
-- Id: W31
-- Feature: Delete single learning experience record
-- Source: backend/src/repos/experiences.repo.ts (deleteExperience)
-- Parameters: $1 = user_id (int), $2 = id (uuid)
DELETE FROM experiences
WHERE user_id = $1
  AND id = $2;


-- ==============================================================================
-- 10. PROMPT TAKES & PROMPT INSTRUCTIONS
-- ==============================================================================

-- READ
-- Id: R28
-- Feature: List recent prompts taken/copied by student for "how did it go?" re-engagement
-- Source: backend/src/repos/prompt-takes.repo.ts (listPromptTakes)
-- Parameters: $1 = user_id (int), $2 = limit (int)
SELECT id, topic_id, via, at
FROM prompt_takes
WHERE user_id = $1
ORDER BY at DESC, id DESC
LIMIT $2;


-- WRITE
-- Id: W32
-- Feature: Record prompt take event (copied to clipboard or opened in ChatGPT/Claude)
-- Source: backend/src/repos/prompt-takes.repo.ts (addPromptTake)
-- Parameters: $1 = user_id (int), $2 = topic_id (text), $3 = via (text)
INSERT INTO prompt_takes (user_id, topic_id, via)
VALUES ($1, $2, $3)
RETURNING id, topic_id, via, at;


-- READ
-- Id: R29
-- Feature: List prompt assembly instructions in fixed position order
-- Source: backend/src/repos/instructions.repo.ts (listInstructions)
SELECT id, scope, status, topic_id, text
FROM prompt_instructions
ORDER BY position;


-- WRITE
-- Id: W33
-- Feature: Upsert prompt instruction during system seeding
-- Source: backend/src/db/instructions-seed.ts (seedInstructions)
-- Parameters: $1 = id (text), $2 = scope (text), $3 = status (text), $4 = topic_id (text),
--             $5 = text (text), $6 = position (int)
INSERT INTO prompt_instructions (id, scope, status, topic_id, text, position)
VALUES ($1, $2, $3, $4, $5, $6)
ON CONFLICT (id) DO UPDATE SET
    scope    = EXCLUDED.scope,
    status   = EXCLUDED.status,
    topic_id = EXCLUDED.topic_id,
    text     = EXCLUDED.text,
    position = EXCLUDED.position;


-- WRITE
-- Id: W34
-- Feature: Delete obsolete prompt instructions not found in source definitions
-- Source: backend/src/db/instructions-seed.ts (seedInstructions)
-- Parameters: $1 = valid_ids (text[])
DELETE FROM prompt_instructions
WHERE NOT (id = ANY($1));


-- ==============================================================================
-- 11. AI COST ACCOUNTING & RESOURCE LIMITS
-- ==============================================================================

-- READ
-- Id: R30
-- Feature: Compute site daily and user daily/weekly AI spend across UTC windows using CTE and LEFT JOIN
-- Source: backend/src/repos/ai-calls.repo.ts (spendFor)
-- Parameters: $1 = user_id (int)
WITH w AS (
  SELECT date_trunc('day',  NOW() AT TIME ZONE 'UTC') AT TIME ZONE 'UTC' AS day_start,
         date_trunc('week', NOW() AT TIME ZONE 'UTC') AT TIME ZONE 'UTC' AS week_start,
         (date_trunc('day',  NOW() AT TIME ZONE 'UTC') + INTERVAL '1 day')  AT TIME ZONE 'UTC' AS day_ends,
         (date_trunc('week', NOW() AT TIME ZONE 'UTC') + INTERVAL '7 days') AT TIME ZONE 'UTC' AS week_ends
)
SELECT COALESCE(SUM(COALESCE(a.cost_usd, a.reserved_usd, 0)) FILTER (WHERE a.at >= w.day_start), 0) AS site_day,
       COALESCE(SUM(COALESCE(a.cost_usd, a.reserved_usd, 0)) FILTER (WHERE a.user_id = $1 AND a.at >= w.day_start), 0) AS user_day,
       COALESCE(SUM(COALESCE(a.cost_usd, a.reserved_usd, 0)) FILTER (WHERE a.user_id = $1), 0) AS user_week,
       w.day_ends, w.week_ends
FROM w
LEFT JOIN ai_calls a ON a.at >= w.week_start AND (a.user_id = $1 OR a.at >= w.day_start)
GROUP BY w.day_ends, w.week_ends;


-- READ
-- Id: R31
-- Feature: Acquire transaction-level advisory lock to serialize AI limit checks and reservations
-- Source: backend/src/repos/ai-calls.repo.ts (reserveAiCall)
-- Parameters: $1 = lock_key (bigint, e.g. 16713 / 0x4149)
SELECT pg_advisory_xact_lock($1::bigint);


-- READ
-- Id: R32
-- Feature: Operator AI spend summary across periods using CTE, CROSS JOIN LATERAL, and LEFT JOIN
-- Source: backend/src/repos/ai-calls.repo.ts (spendReport)
WITH w AS (
  SELECT date_trunc('day',  NOW() AT TIME ZONE 'UTC') AT TIME ZONE 'UTC' AS day_start,
         date_trunc('week', NOW() AT TIME ZONE 'UTC') AT TIME ZONE 'UTC' AS week_start
)
SELECT p.label,
       COUNT(a.id)::int AS calls,
       COALESCE(SUM(COALESCE(a.cost_usd, a.reserved_usd, 0)), 0) AS usd
FROM w
CROSS JOIN LATERAL (VALUES (1, 'today', w.day_start),
                           (2, 'this week', w.week_start),
                           (3, 'last 30 days', NOW() - INTERVAL '30 days')) AS p(n, label, since)
LEFT JOIN ai_calls a ON a.at >= p.since
GROUP BY p.n, p.label
ORDER BY p.n;


-- READ
-- Id: R33
-- Feature: Identify top AI-spending accounts joined with user profile using CTE, INNER JOIN, and LEFT JOIN
-- Source: backend/src/repos/ai-calls.repo.ts (spendReport)
-- Parameters: $1 = top_limit (int)
WITH w AS (
  SELECT date_trunc('day',  NOW() AT TIME ZONE 'UTC') AT TIME ZONE 'UTC' AS day_start,
         date_trunc('week', NOW() AT TIME ZONE 'UTC') AT TIME ZONE 'UTC' AS week_start
)
SELECT a.user_id,
       u.name,
       u.email,
       COALESCE(SUM(COALESCE(a.cost_usd, a.reserved_usd, 0)) FILTER (WHERE a.at >= w.day_start), 0) AS usd_day,
       SUM(COALESCE(a.cost_usd, a.reserved_usd, 0)) AS usd_week
FROM w
JOIN ai_calls a ON a.at >= w.week_start
LEFT JOIN users u ON u.id = a.user_id
WHERE a.user_id IS NOT NULL
GROUP BY a.user_id, u.name, u.email
ORDER BY usd_week DESC, a.user_id
LIMIT $1;


-- READ
-- Id: R34
-- Feature: Count calls reserved > 5 minutes ago and never settled (server crash mid-call)
-- Source: backend/src/repos/ai-calls.repo.ts (spendReport)
SELECT COUNT(*)::int AS n
FROM ai_calls a
WHERE a.error = 'pending'
  AND a.at < NOW() - INTERVAL '5 minutes';


-- READ
-- Id: R35
-- Feature: Breakdown of student messages read by Bedrock model vs rules engine over last 7 days
-- Source: backend/src/repos/ai-calls.repo.ts (aiHealthReport)
SELECT read_by, COUNT(*)::int AS messages
FROM chat_messages
WHERE role = 'student'
  AND read_by IN ('model', 'rules')
  AND at >= NOW() - INTERVAL '7 days'
GROUP BY read_by
ORDER BY read_by;


-- READ
-- Id: R36
-- Feature: Bedrock model latency percentiles (p50, p90) and error breakdown over last 7 days
-- Source: backend/src/repos/ai-calls.repo.ts (aiHealthReport)
SELECT error,
       COUNT(*)::int AS calls,
       percentile_cont(0.5) WITHIN GROUP (ORDER BY latency_ms) AS p50_ms,
       percentile_cont(0.9) WITHIN GROUP (ORDER BY latency_ms) AS p90_ms
FROM ai_calls
WHERE purpose = 'read'
  AND at >= NOW() - INTERVAL '7 days'
GROUP BY error
ORDER BY calls DESC, error NULLS FIRST;


-- WRITE
-- Id: W35
-- Feature: Reserve worst-case AI call budget before initiating model inference
-- Source: backend/src/repos/ai-calls.repo.ts (reserveAiCall)
-- Parameters: $1 = user_id (int), $2 = model (text), $3 = purpose (text), $4 = reserved_usd (numeric)
INSERT INTO ai_calls (user_id, model, purpose, reserved_usd, latency_ms, ok, error)
VALUES ($1, $2, $3, $4, 0, false, 'pending')
RETURNING id;


-- WRITE
-- Id: W36
-- Feature: Settle completed AI call with actual token counts, cost, and latency
-- Source: backend/src/repos/ai-calls.repo.ts (settleAiCall)
-- Parameters: $1 = id (bigint), $2 = input_tokens (int), $3 = output_tokens (int),
--             $4 = cost_usd (numeric), $5 = latency_ms (int), $6 = ok (boolean), $7 = error (text)
UPDATE ai_calls
SET input_tokens  = $2,
    output_tokens = $3,
    cost_usd      = $4,
    latency_ms    = $5,
    ok            = $6,
    error         = $7
    WHERE id = $1;


-- ==============================================================================
-- 12. DATABASE MIGRATIONS INFRASTRUCTURE
-- ==============================================================================

-- READ
-- Id: R37
-- Feature: List executed database migration filenames in sequential order
-- Source: backend/src/db/migrate.ts (migrate)
SELECT filename
FROM _migrations
ORDER BY filename ASC;


-- WRITE
-- Id: W37
-- Feature: Record successful execution of a database migration file
-- Source: backend/src/db/migrate.ts (migrate)
-- Parameters: $1 = filename (text)
INSERT INTO _migrations (filename)
VALUES ($1);
