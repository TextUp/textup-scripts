-- Archiving all contacts withing the specific tags, then archiving the tags themselves
-- -----------
-- ASSUMPTIONS
-- -----------
-- Relevant phone ID manually specified in @phone_id_to_archive_all

SET @phone_id_to_archive_all = 2;

USE prodDb;
DROP PROCEDURE IF EXISTS archive_all_contacts_and_delete_tag;
DROP PROCEDURE IF EXISTS do_archive_tag_and_all_contacts;

DELIMITER $$

CREATE PROCEDURE archive_all_contacts_and_delete_tag(
    IN this_phone_id BIGINT,
    IN this_tag_id BIGINT)
BEGIN
    DECLARE tag_members_id BIGINT;

    SELECT members_id
    FROM phone_record
    WHERE class = 'org.textup.GroupPhoneRecord'
        AND phone_id = this_phone_id
        AND id = this_tag_id
        AND is_deleted = 0
        AND STATUS = 'ACTIVE'
    LIMIT 1
    INTO tag_members_id;

    UPDATE phone_record
    SET status = 'ARCHIVED'
    WHERE class = 'org.textup.IndividualPhoneRecord'
        AND phone_id = this_phone_id
        AND id IN (
            SELECT phone_record_id
            FROM phone_record_members_phone_record
            WHERE phone_record_members_phone_records_id = tag_members_id);

    UPDATE phone_record
    SET is_deleted = 1
    WHERE class = 'org.textup.GroupPhoneRecord'
        AND phone_id = this_phone_id
        AND id = this_tag_id;
END $$

CREATE PROCEDURE do_archive_tag_and_all_contacts(IN this_phone_id BIGINT)
BEGIN
    DECLARE has_error INTEGER DEFAULT 0;
    DECLARE CONTINUE HANDLER FOR SQLEXCEPTION
        BEGIN
            SET has_error = 1;
            SHOW ERRORS;
        END;

    START TRANSACTION;

    -- call stored procedures - one call per tag id
    CALL archive_all_contacts_and_delete_tag(this_phone_id, 0);

    IF has_error = 1 THEN
        ROLLBACK;
        SELECT 'OUTCOME: Rolled back';
    ELSE
        COMMIT;
        SELECT 'OUTCOME: Successfully deleted tag and archived all contacts within specified tags';
    END IF;
END $$

DELIMITER ;

CALL do_archive_tag_and_all_contacts(@phone_id_to_archive_all);
