-- ============================================
-- FIX: Add UPDATE trigger for streak calculation
-- ============================================
-- The issue: Streak trigger only fires on INSERT, but ai_verified
-- is set to TRUE later via UPDATE, so stats never get updated.
--
-- Solution: Also trigger on UPDATE when ai_verified changes to TRUE
-- ============================================

-- Drop existing trigger
DROP TRIGGER IF EXISTS trigger_update_streak ON task_submissions;

-- Recreate trigger to fire on both INSERT and UPDATE
CREATE TRIGGER trigger_update_streak
    AFTER INSERT OR UPDATE ON task_submissions
    FOR EACH ROW
    EXECUTE FUNCTION update_user_streak();

-- ============================================
-- Also fix the longest_streak calculation bug
-- ============================================
-- The GREATEST() was using the OLD value of current_streak
-- instead of the newly calculated one

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

-- ============================================
-- IMPORTANT: After running this, test it!
-- ============================================
-- 1. Submit a new task
-- 2. Wait for AI verification
-- 3. Check user_task_stats - streak should update
