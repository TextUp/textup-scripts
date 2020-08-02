-- Batch importing contacts with notes, languages, numbers, and tags
-- -----------
-- ASSUMPTIONS
-- -----------
-- All contacts to be exported to an existing phone manually specified in @phone_id
-- See line starting with `CALL import_contact_row(this_phone_id` for an example of the
--      input data required. The easiest way to gather this input data is via a
--      properly-formatted CSV file.

SET @phone_id = 2;

-- ensure that our timestamps use utc
SET time_zone = '+00:00';

USE prodDb;
DROP PROCEDURE IF EXISTS import_contact_row;
DROP PROCEDURE IF EXISTS do_import_contacts;

DELIMITER $$
CREATE PROCEDURE import_contact_row(IN this_phone_id bigint(20), IN this_name varchar(255),
    IN this_note varchar(1000), IN this_language varchar(255), IN this_numbers TEXT, IN this_tags TEXT)
    BEGIN
        DECLARE contact_record_id BIGINT;
        DECLARE contact_id BIGINT;

        DECLARE current_numbers_string TEXT DEFAULT this_numbers;
        DECLARE current_number TEXT;
        DECLARE current_number_pref INT DEFAULT 0;
        DECLARE prev_numbers_string TEXT DEFAULT "";

        DECLARE current_tags_string TEXT DEFAULT this_tags;
        DECLARE current_tag_name TEXT;
        DECLARE prev_tags_string TEXT DEFAULT "";

        DECLARE tag_record_id BIGINT;
        DECLARE tag_members_id BIGINT;

        -- create contact's record
        INSERT INTO record (last_record_activity, language)
        VALUES (NOW(), this_language);

        SELECT LAST_INSERT_ID() INTO contact_record_id;

        -- create contact
        INSERT INTO phone_record (
            class,
            name,
            individual_note,
            phone_id,
            record_id,
            status,
            is_deleted,
            when_created,
            last_touched)
        VALUES (
            "org.textup.IndividualPhoneRecord",
            this_name,
            this_note,
            this_phone_id,
            contact_record_id,
            "ACTIVE",
            0,
            NOW(),
            NOW());

        SELECT LAST_INSERT_ID() INTO contact_id;

        INSERT INTO debug_messages SELECT CONCAT_WS(" ", "created contact with id", contact_id, "and name", this_name);

        -- for each comma-separated number...
        WHILE current_numbers_string != prev_numbers_string DO

            SET current_number = TRIM(SUBSTRING_INDEX(current_numbers_string, ",", 1));
            SET prev_numbers_string = current_numbers_string;
            SET current_numbers_string = SUBSTRING(current_numbers_string, INSTR(current_numbers_string, ",") + 1);

            -- create numbers associated with this new contact
            INSERT INTO contact_number (
                version,
                number,
                owner_id,
                preference)
            VALUES (
                0,
                current_number,
                contact_id,
                current_number_pref);

            INSERT INTO debug_messages SELECT CONCAT_WS(" ", "created number", current_number, "for contact", contact_id, "with number pref", current_number_pref);

            SET current_number_pref = current_number_pref + 1;
        END WHILE;

        -- for each comma-separated tag...
        WHILE current_tags_string != prev_tags_string DO

            SET current_tag_name = TRIM(SUBSTRING_INDEX(current_tags_string, ",", 1));
            SET prev_tags_string = current_tags_string;
            SET current_tags_string = SUBSTRING(current_tags_string, INSTR(current_tags_string, ",") + 1);

            -- check if tag exists - if exists store tag id
            SELECT members_id
            FROM phone_record
            WHERE class = "org.textup.GroupPhoneRecord"
                AND phone_id = this_phone_id
                AND name = current_tag_name
                AND is_deleted = 0
                AND status = "ACTIVE"
            LIMIT 1
            INTO tag_members_id;

            -- if tag does not exist
            IF tag_members_id IS NULL THEN
                -- create tag's record
                INSERT INTO record (last_record_activity, language)
                VALUES (NOW(), "ENGLISH"); -- defaults to English

                SELECT LAST_INSERT_ID() INTO tag_record_id;

                -- create tag's members object
                INSERT INTO phone_record_members (version)
                VALUES (0);

                SELECT LAST_INSERT_ID() INTO tag_members_id;

                -- create tag, storing newly create tag's id
                INSERT INTO phone_record (
                    class,
                    group_hex_color,
                    is_deleted,
                    name,
                    phone_id,
                    record_id,
                    members_id,
                    when_created,
                    last_touched,
                    status)
                VALUES (
                    "org.textup.GroupPhoneRecord",
                    "#1BA5E0",
                    0,
                    current_tag_name,
                    this_phone_id,
                    tag_record_id,
                    tag_members_id,
                    NOW(),
                    NOW(),
                    "ACTIVE");

                INSERT INTO debug_messages SELECT CONCAT_WS(" ", "created tag with MEMBERS id", tag_members_id, "and name", current_tag_name);
            ELSE
                INSERT INTO debug_messages SELECT CONCAT_WS(" ", "found existing tag with MEMBERS id", tag_members_id, "and name", current_tag_name);
            END IF;

            -- add newly-created contact to tag
            INSERT INTO phone_record_members_phone_record (
                phone_record_members_phone_records_id,
                phone_record_id)
            VALUES (
                tag_members_id,
                contact_id);
        END WHILE;
    END $$

CREATE PROCEDURE do_import_contacts(IN this_phone_id BIGINT)
BEGIN
    DECLARE has_error INTEGER DEFAULT 0;
    DECLARE CONTINUE HANDLER FOR SQLEXCEPTION
        BEGIN
            SET has_error = 1;
            SHOW ERRORS;
        END;

    START TRANSACTION;

    DROP TEMPORARY TABLE IF EXISTS debug_messages;
    CREATE TEMPORARY TABLE debug_messages (message TEXT);

    -- call stored procedures - one call per contact
    CALL import_contact_row(this_phone_id, "Eric Bai","TextUp programmer","ENGLISH","6261238888,4019328888","TextUp Team,Housemates");

    IF has_error = 1 THEN
        ROLLBACK;
        SELECT message as "OUTCOME: Rolled back" FROM debug_messages;
    ELSE
        COMMIT;
        SELECT message as "OUTCOME: Successfully imported contacts" FROM debug_messages;
    END IF;

    DROP TEMPORARY TABLE debug_messages;
END $$

DELIMITER ;

CALL do_import_contacts(@phone_id);
