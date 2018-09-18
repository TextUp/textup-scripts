-- Update database with voicemail details for missing voicemails.
-- Sets the voicemail duration and away message flag to true in record_item table
-- -----------
-- ASSUMPTIONS
-- -----------
-- All call ids point to existing record items. This script will only update existing calls,
--      not create new ones

USE prodDb;
DROP PROCEDURE IF EXISTS update_voicemail_data;
DROP PROCEDURE IF EXISTS update_voicemail_row;

DELIMITER $$
CREATE PROCEDURE update_voicemail_row(IN this_api_id VARCHAR(255), IN this_duration INT)
BEGIN
    UPDATE record_item as i
    JOIN record_item_receipt as rir
        ON rir.item_id = i.id
    SET voicemail_in_seconds = this_duration,
        has_away_message = 1
    WHERE rir.api_id = this_api_id COLLATE utf8mb4_general_ci;
END $$

CREATE PROCEDURE update_voicemail_data()
BEGIN
    DECLARE has_error INTEGER DEFAULT 0;
    DECLARE CONTINUE HANDLER FOR SQLEXCEPTION
        BEGIN
            SET has_error = 1;
            SHOW ERRORS;
        END;

    START TRANSACTION;

    -- Sample call
    -- CALL update_voicemail_row("api_id_string", 12);

    IF has_error = 1 THEN
        ROLLBACK;
    ELSE
        COMMIT;
        SELECT "Successfully updated voicemail data";
    END IF;
END $$
DELIMITER ;

CALL update_voicemail_data();
