-- ============================================
-- ZARQ MESSENGER - DAILY TASKS FEATURE
-- Database Schema (PostgreSQL)
-- ============================================

-- 1. DAILY TASKS TABLE
-- Stores the daily tasks created by admin
CREATE TABLE IF NOT EXISTS daily_tasks (
    id SERIAL PRIMARY KEY,
    task_date DATE NOT NULL UNIQUE,
    title_en VARCHAR(255) NOT NULL,
    title_hi VARCHAR(255) NOT NULL,
    description_en TEXT NOT NULL,
    description_hi TEXT NOT NULL,
    category VARCHAR(50) NOT NULL, -- 'safe_fun', 'skill_based'
    difficulty VARCHAR(20) NOT NULL DEFAULT 'easy', -- 'easy', 'medium', 'hard'
    points INT NOT NULL DEFAULT 10,
    ai_verification_prompt TEXT, -- Prompt for Gemini Vision API
    require_verification BOOLEAN DEFAULT TRUE,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Index for quick daily task lookup
CREATE INDEX IF NOT EXISTS idx_daily_tasks_date ON daily_tasks(task_date DESC);
CREATE INDEX IF NOT EXISTS idx_daily_tasks_active ON daily_tasks(is_active, task_date DESC);

-- 2. TASK SUBMISSIONS TABLE
-- Stores user submissions for tasks
CREATE TABLE IF NOT EXISTS task_submissions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    task_id INT REFERENCES daily_tasks(id) ON DELETE SET NULL,
    is_task_submission BOOLEAN DEFAULT TRUE, -- false for free-form posts
    media_type VARCHAR(10) NOT NULL, -- 'image', 'video'
    media_url TEXT NOT NULL, -- Cloud storage URL
    thumbnail_url TEXT, -- For videos
    encrypted_media_key TEXT, -- For E2EE friends-only posts
    caption TEXT,
    visibility VARCHAR(20) NOT NULL CHECK (visibility IN ('friends', 'global')),
    ai_verified BOOLEAN DEFAULT FALSE,
    ai_verification_confidence INT DEFAULT 0, -- 0-100
    ai_verification_details JSONB, -- What AI detected
    points_earned INT DEFAULT 0,
    is_deleted BOOLEAN DEFAULT FALSE, -- Soft delete flag
    expires_at TIMESTAMP NOT NULL, -- Auto-delete after 24 hours
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Indexes for performance
CREATE INDEX IF NOT EXISTS idx_submissions_user ON task_submissions(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_submissions_global_feed ON task_submissions(visibility, created_at DESC, is_deleted)
    WHERE visibility = 'global' AND is_deleted = FALSE;
CREATE INDEX IF NOT EXISTS idx_submissions_task ON task_submissions(task_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_submissions_expires ON task_submissions(expires_at) WHERE is_deleted = FALSE;

-- 3. TASK SHARE RECIPIENTS TABLE
-- For E2EE friends-only sharing (stores encrypted keys per friend)
CREATE TABLE IF NOT EXISTS task_share_recipients (
    id SERIAL PRIMARY KEY,
    submission_id UUID NOT NULL REFERENCES task_submissions(id) ON DELETE CASCADE,
    recipient_user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    encrypted_media_key TEXT NOT NULL, -- Media key encrypted with recipient's public key
    has_viewed BOOLEAN DEFAULT FALSE,
    viewed_at TIMESTAMP,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(submission_id, recipient_user_id)
);

-- Index for friend feed queries
CREATE INDEX IF NOT EXISTS idx_share_recipients_user ON task_share_recipients(recipient_user_id, created_at DESC);

-- 4. REACTIONS TABLE
-- Store user reactions on submissions
CREATE TABLE IF NOT EXISTS task_reactions (
    id SERIAL PRIMARY KEY,
    submission_id UUID NOT NULL REFERENCES task_submissions(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    reaction_type VARCHAR(20) NOT NULL CHECK (reaction_type IN ('like', 'love', 'fire', 'clap', 'wow')),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(submission_id, user_id)
);

-- Index for reaction counts
CREATE INDEX IF NOT EXISTS idx_reactions_submission ON task_reactions(submission_id, reaction_type);
CREATE INDEX IF NOT EXISTS idx_reactions_user ON task_reactions(user_id, created_at DESC);

-- 5. USER TASK STATS TABLE
-- Gamification: User's points, streaks, badges
CREATE TABLE IF NOT EXISTS user_task_stats (
    user_id UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    total_points INT DEFAULT 0,
    current_streak INT DEFAULT 0,
    longest_streak INT DEFAULT 0,
    tasks_completed INT DEFAULT 0,
    free_posts INT DEFAULT 0,
    last_task_date DATE,
    badges JSONB DEFAULT '[]', -- Array of earned badge IDs
    rank INT DEFAULT 0, -- Updated periodically
    weekly_points INT DEFAULT 0,
    weekly_rank INT DEFAULT 0,
    last_weekly_reset DATE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Index for leaderboards
CREATE INDEX IF NOT EXISTS idx_user_stats_total_points ON user_task_stats(total_points DESC);
CREATE INDEX IF NOT EXISTS idx_user_stats_weekly_points ON user_task_stats(weekly_points DESC);
CREATE INDEX IF NOT EXISTS idx_user_stats_streak ON user_task_stats(current_streak DESC);

-- 6. BADGES TABLE
-- Define all available badges
CREATE TABLE IF NOT EXISTS badges (
    id SERIAL PRIMARY KEY,
    badge_key VARCHAR(50) UNIQUE NOT NULL, -- 'streak_3', 'points_100', etc.
    name_en VARCHAR(100) NOT NULL,
    name_hi VARCHAR(100) NOT NULL,
    description_en TEXT,
    description_hi TEXT,
    icon_emoji VARCHAR(10), -- 🔥, ⚡, 🏆, etc.
    icon_url TEXT,
    requirement_type VARCHAR(50) NOT NULL, -- 'streak', 'total_tasks', 'points', 'weekly_top'
    requirement_value INT NOT NULL,
    badge_tier VARCHAR(20) DEFAULT 'bronze', -- 'bronze', 'silver', 'gold', 'diamond'
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Index for badge lookup
CREATE INDEX IF NOT EXISTS idx_badges_active ON badges(is_active, requirement_type);

-- 7. COMMENTS TABLE (Optional - for engagement)
CREATE TABLE IF NOT EXISTS task_comments (
    id SERIAL PRIMARY KEY,
    submission_id UUID NOT NULL REFERENCES task_submissions(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    comment_text TEXT NOT NULL,
    is_deleted BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Index for comments
CREATE INDEX IF NOT EXISTS idx_comments_submission ON task_comments(submission_id, created_at DESC, is_deleted)
    WHERE is_deleted = FALSE;

-- 8. REPORTS TABLE
-- Content moderation and reporting
CREATE TABLE IF NOT EXISTS task_reports (
    id SERIAL PRIMARY KEY,
    submission_id UUID NOT NULL REFERENCES task_submissions(id) ON DELETE CASCADE,
    reporter_user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    reason VARCHAR(50) NOT NULL, -- 'inappropriate', 'spam', 'fake', 'violence', 'hate'
    details TEXT,
    status VARCHAR(20) DEFAULT 'pending', -- 'pending', 'under_review', 'resolved', 'dismissed'
    admin_notes TEXT,
    reviewed_by UUID REFERENCES users(id), -- Admin user ID
    reviewed_at TIMESTAMP,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(submission_id, reporter_user_id) -- Can't report same post twice
);

-- Index for admin moderation panel
CREATE INDEX IF NOT EXISTS idx_reports_status ON task_reports(status, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_reports_submission ON task_reports(submission_id);

-- 9. USER BANS TABLE
-- Track banned users
CREATE TABLE IF NOT EXISTS user_task_bans (
    id SERIAL PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    ban_type VARCHAR(20) NOT NULL, -- 'temporary', 'permanent'
    reason TEXT NOT NULL,
    banned_until TIMESTAMP, -- NULL for permanent bans
    banned_by UUID REFERENCES users(id), -- Admin user ID
    violations_count INT DEFAULT 1,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Index for ban checks
CREATE INDEX IF NOT EXISTS idx_user_bans_active ON user_task_bans(user_id, is_active, banned_until);

-- 10. AUTOMATED REPORT TRIGGERS TABLE
-- Track when posts hit 7 reports threshold
CREATE TABLE IF NOT EXISTS report_thresholds (
    id SERIAL PRIMARY KEY,
    submission_id UUID NOT NULL UNIQUE REFERENCES task_submissions(id) ON DELETE CASCADE,
    report_count INT DEFAULT 0,
    threshold_reached BOOLEAN DEFAULT FALSE,
    admin_notified BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ============================================
-- FUNCTIONS AND TRIGGERS
-- ============================================

-- Function: Update user streak
-- FIXED: Now also handles UPDATE events when ai_verified changes to TRUE
CREATE OR REPLACE FUNCTION update_user_streak()
RETURNS TRIGGER AS $$
DECLARE
    new_streak INT;
BEGIN
    -- Only process when task is verified
    -- For UPDATE: only run if ai_verified changed from FALSE to TRUE
    IF (TG_OP = 'INSERT' AND NEW.is_task_submission = TRUE AND NEW.ai_verified = TRUE) OR
       (TG_OP = 'UPDATE' AND NEW.is_task_submission = TRUE AND OLD.ai_verified = FALSE AND NEW.ai_verified = TRUE) THEN

        -- Get current stats to calculate new streak
        SELECT
            CASE
                WHEN last_task_date = CURRENT_DATE - INTERVAL '1 day' THEN current_streak + 1
                WHEN last_task_date = CURRENT_DATE THEN current_streak
                WHEN last_task_date IS NULL THEN 1
                ELSE 1
            END INTO new_streak
        FROM user_task_stats
        WHERE user_id = NEW.user_id;

        -- If user doesn't exist yet, streak is 1
        IF new_streak IS NULL THEN
            new_streak := 1;
        END IF;

        -- Update user stats with correctly calculated streak
        UPDATE user_task_stats
        SET
            tasks_completed = tasks_completed + 1,
            total_points = total_points + NEW.points_earned,
            weekly_points = weekly_points + NEW.points_earned,
            current_streak = new_streak,
            longest_streak = GREATEST(longest_streak, new_streak),
            last_task_date = CURRENT_DATE,
            updated_at = CURRENT_TIMESTAMP
        WHERE user_id = NEW.user_id;

        -- Insert if user doesn't exist
        INSERT INTO user_task_stats (user_id, tasks_completed, total_points, weekly_points, current_streak, longest_streak, last_task_date)
        VALUES (NEW.user_id, 1, NEW.points_earned, NEW.points_earned, 1, 1, CURRENT_DATE)
        ON CONFLICT (user_id) DO NOTHING;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger: Update streak on task submission
-- FIXED: Now fires on both INSERT and UPDATE (when ai_verified changes)
DROP TRIGGER IF EXISTS trigger_update_streak ON task_submissions;
CREATE TRIGGER trigger_update_streak
    AFTER INSERT OR UPDATE ON task_submissions
    FOR EACH ROW
    EXECUTE FUNCTION update_user_streak();

-- Function: Increment report count
CREATE OR REPLACE FUNCTION increment_report_count()
RETURNS TRIGGER AS $$
BEGIN
    -- Update or insert report threshold
    INSERT INTO report_thresholds (submission_id, report_count, threshold_reached, admin_notified)
    VALUES (NEW.submission_id, 1, FALSE, FALSE)
    ON CONFLICT (submission_id)
    DO UPDATE SET
        report_count = report_thresholds.report_count + 1,
        threshold_reached = CASE WHEN report_thresholds.report_count + 1 >= 7 THEN TRUE ELSE FALSE END,
        updated_at = CURRENT_TIMESTAMP;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger: Increment report count on new report
DROP TRIGGER IF EXISTS trigger_increment_reports ON task_reports;
CREATE TRIGGER trigger_increment_reports
    AFTER INSERT ON task_reports
    FOR EACH ROW
    EXECUTE FUNCTION increment_report_count();

-- ============================================
-- INITIAL DATA - SAMPLE BADGES
-- ============================================

INSERT INTO badges (badge_key, name_en, name_hi, description_en, description_hi, icon_emoji, requirement_type, requirement_value, badge_tier) VALUES
('streak_3', '3-Day Streak', '3-दिन स्ट्रीक', 'Complete tasks for 3 days in a row', '3 दिन लगातार टास्क पूरे करें', '🔥', 'streak', 3, 'bronze'),
('streak_7', '7-Day Streak', '7-दिन स्ट्रीक', 'Complete tasks for 7 days in a row', '7 दिन लगातार टास्क पूरे करें', '⚡', 'streak', 7, 'silver'),
('streak_30', '30-Day Streak', '30-दिन स्ट्रीक', 'Complete tasks for 30 days in a row', '30 दिन लगातार टास्क पूरे करें', '🏆', 'streak', 30, 'gold'),
('points_100', '100 Points', '100 अंक', 'Earn 100 total points', 'कुल 100 अंक अर्जित करें', '⭐', 'points', 100, 'bronze'),
('points_500', '500 Points', '500 अंक', 'Earn 500 total points', 'कुल 500 अंक अर्जित करें', '🌟', 'points', 500, 'silver'),
('points_1000', '1000 Points', '1000 अंक', 'Earn 1000 total points', 'कुल 1000 अंक अर्जित करें', '💫', 'points', 1000, 'gold'),
('tasks_10', '10 Tasks', '10 टास्क', 'Complete 10 tasks', '10 टास्क पूरे करें', '🎯', 'total_tasks', 10, 'bronze'),
('tasks_50', '50 Tasks', '50 टास्क', 'Complete 50 tasks', '50 टास्क पूरे करें', '🎪', 'total_tasks', 50, 'silver'),
('tasks_100', '100 Tasks', '100 टास्क', 'Complete 100 tasks', '100 टास्क पूरे करें', '🎨', 'total_tasks', 100, 'gold'),
('weekly_top10', 'Top 10 This Week', 'इस हफ्ते टॉप 10', 'Rank in top 10 users this week', 'इस हफ्ते शीर्ष 10 उपयोगकर्ताओं में रैंक करें', '👑', 'weekly_top', 10, 'gold')
ON CONFLICT (badge_key) DO NOTHING;

-- ============================================
-- SAMPLE TASKS (First 7 days)
-- ============================================

INSERT INTO daily_tasks (task_date, title_en, title_hi, description_en, description_hi, category, difficulty, points, ai_verification_prompt) VALUES
(CURRENT_DATE, 'Share Your Morning Coffee', 'अपनी सुबह की कॉफी शेयर करें', 'Take a photo of your morning coffee or tea', 'अपनी सुबह की कॉफी या चाय की फोटो लें', 'safe_fun', 'easy', 10, 'Does this image show a cup, mug, or glass containing coffee, tea, or any beverage? Return JSON: {verified: true/false, confidence: 0-100, detected: "description"}'),
(CURRENT_DATE + INTERVAL '1 day', 'Sunset Capture', 'सूर्यास्त की तस्वीर', 'Capture a beautiful sunset photo', 'एक सुंदर सूर्यास्त की फोटो कैप्चर करें', 'safe_fun', 'easy', 10, 'Is this a sunset or sunrise scene with orange/red/pink sky colors? Return JSON: {verified: true/false, confidence: 0-100, detected: "description"}'),
(CURRENT_DATE + INTERVAL '2 days', 'Teach 5 Words', '5 शब्द सिखाएं', 'Teach 5 new words in simple language with examples', '5 नए शब्दों को सरल भाषा में उदाहरण के साथ सिखाएं', 'skill_based', 'medium', 25, 'Does this content show teaching or explaining of words/vocabulary? Count how many words are being taught. Return JSON: {verified: true/false, word_count: number, confidence: 0-100}'),
(CURRENT_DATE + INTERVAL '3 days', 'Your Workspace', 'आपकी कार्यस्थल', 'Show us your creative workspace or study desk', 'हमें अपनी रचनात्मक कार्यस्थल या अध्ययन डेस्क दिखाएं', 'safe_fun', 'easy', 10, 'Does this image show a desk, table, or workspace setup? Return JSON: {verified: true/false, confidence: 0-100, detected: "description"}'),
(CURRENT_DATE + INTERVAL '4 days', 'Share a Life Hack', 'एक लाइफ हैक शेयर करें', 'Share a useful life hack that helped you', 'एक उपयोगी लाइफ हैक शेयर करें जिसने आपकी मदद की', 'skill_based', 'medium', 25, 'Does this content demonstrate or explain a useful tip, trick, or life hack? Return JSON: {verified: true/false, confidence: 0-100, detected: "description"}'),
(CURRENT_DATE + INTERVAL '5 days', 'Something Blue', 'कुछ नीला', 'Find and photograph something blue around you', 'अपने आसपास कुछ नीला खोजें और फोटो लें', 'safe_fun', 'easy', 10, 'Is there a blue colored object prominently visible in this image? Return JSON: {verified: true/false, confidence: 0-100, detected: "description"}'),
(CURRENT_DATE + INTERVAL '6 days', 'Explain a Skill', 'एक कौशल समझाएं', 'Explain a skill you have in under 1 minute', '1 मिनट में अपना कोई कौशल समझाएं', 'skill_based', 'hard', 50, 'Does this content show someone teaching or demonstrating a skill or ability? Return JSON: {verified: true/false, confidence: 0-100, detected: "description"}')
ON CONFLICT (task_date) DO NOTHING;

-- ============================================
-- COMMENTS
-- ============================================

COMMENT ON TABLE daily_tasks IS 'Stores daily tasks created by admin';
COMMENT ON TABLE task_submissions IS 'User submissions for tasks - images/videos with 24h expiry';
COMMENT ON TABLE task_share_recipients IS 'E2EE sharing - encrypted keys for friends-only posts';
COMMENT ON TABLE task_reactions IS 'User reactions on task submissions';
COMMENT ON TABLE user_task_stats IS 'User gamification stats - points, streaks, badges';
COMMENT ON TABLE badges IS 'Available badges users can earn';
COMMENT ON TABLE task_comments IS 'Comments on task submissions';
COMMENT ON TABLE task_reports IS 'Content moderation reports';
COMMENT ON TABLE user_task_bans IS 'Banned users tracking';
COMMENT ON TABLE report_thresholds IS 'Tracks posts reaching 7+ reports for admin review';
