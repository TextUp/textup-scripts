-- Migration script from v1 to v2
-- -----------
-- ASSUMPTIONS
-- -----------
-- No locations in the database, so we need to hardcode in a default location
-- Organization has one team containing all staff members
-- That one team has an associated phone
-- Place keywords become tags within the team's phone
-- Each tag has its own record containing texts and receipts
-- Subscribers have unique phone numbers and become contacts
-- Each contact has its own record containing received texts and receipts
-- Role (ADMIN vs STAFF) are in the same order in both databases
-- Will not infer any RecordItemReceipts
-- Existing staff keywords are unique, if existing duplicate, migration will fail
-- Subscriptions by staff members to keywords will not be migrated since staff
-- 		members are not migrated as contacts

USE prototypeDb;
DROP PROCEDURE IF EXISTS create_default_location;
DROP PROCEDURE IF EXISTS create_empty_schedule;
DROP PROCEDURE IF EXISTS create_empty_record;
DROP PROCEDURE IF EXISTS create_team_with_phone;
DROP PROCEDURE IF EXISTS create_record_text;
DROP PROCEDURE IF EXISTS create_contact_for_subscriber;
DROP PROCEDURE IF EXISTS transfer_staffs_no_phones;
DROP PROCEDURE IF EXISTS transfer_subscribers_for_place;
DROP PROCEDURE IF EXISTS transfer_places;
DROP PROCEDURE IF EXISTS transfer_alerts_for_subscribers;
DROP PROCEDURE IF EXISTS transfer_alerts;
DROP PROCEDURE IF EXISTS transfer_agency;
DROP PROCEDURE IF EXISTS do_migration;

DELIMITER $$

/*
Creation utility stored procedures
 */

CREATE PROCEDURE create_default_location(OUT new_location_id BIGINT(20))
BEGIN
	INSERT INTO prodDb.location (version, address, lat, lon)
	VALUES (0,
		'Providence, RI',
		41.8240,
		-71.4128);

	SELECT LAST_INSERT_ID() INTO new_location_id;
END $$

CREATE PROCEDURE create_team_with_phone(IN new_org_id BIGINT(20),
	IN a_name VARCHAR(255), OUT new_team_id BIGINT(20), OUT new_phone_id BIGINT(20))
BEGIN
	DECLARE new_location_id BIGINT(20);
	DECLARE new_owner_id BIGINT(20);
	-- create the default location
	CALL create_default_location(new_location_id);
	-- insert team
	INSERT INTO prodDb.team (version,
							hex_color,
							is_deleted,
							location_id,
							name,
							org_id)
	VALUES (0,
			'#1BA5E0', -- TextUp blue
			0,
			new_location_id,
			a_name,
			new_org_id);
	-- store inserted id
	SELECT LAST_INSERT_ID() INTO new_team_id;
	-- create empty phone
	INSERT INTO prodDb.phone(version,
							away_message)
	VALUES(0,
		"Sorry. I'm currently not available. I'll reply when I am back.");
	-- store id of empty phone for team
	SELECT LAST_INSERT_ID() INTO new_phone_id;
	-- create a new phone ownership to associate team with phone
	INSERT INTO prodDb.phone_ownership(version,
									owner_id,
									phone_id,
									type)
	VALUES(0,
		new_team_id,
		new_phone_id,
		'GROUP');
	-- store ownership id
	SELECT LAST_INSERT_ID() INTO new_owner_id;
	-- update phone with the ownership to associate phone with team
	UPDATE prodDb.phone
	SET owner_id = new_owner_id
	WHERE id = new_phone_id;
END $$

CREATE PROCEDURE create_empty_schedule(OUT new_schedule_id BIGINT(20))
BEGIN
	INSERT INTO prodDb.schedule (version,
								class,
								monday,
								tuesday,
								wednesday,
								thursday,
								friday,
								saturday,
								sunday)
	VALUES (0,
			'org.textup.WeeklySchedule',
			'',
			'',
			'',
			'',
			'',
			'',
			'');

	SELECT LAST_INSERT_ID() INTO new_schedule_id;
END $$

CREATE PROCEDURE create_empty_record(OUT new_record_id BIGINT(20))
BEGIN
	INSERT INTO prodDb.record(version,
							last_record_activity)
	VALUES(0,
		'2016-07-01 13:48:35');

	SELECT LAST_INSERT_ID() INTO new_record_id;
END $$

CREATE PROCEDURE create_record_text(IN this_record_id BIGINT(20),
	IN text_contents VARCHAR(255), IN text_created DATETIME)
BEGIN

	IF this_record_id = NULL THEN
		SELECT this_record_id;
		SELECT text_contents;
		SELECT text_contents;
	END IF;

	INSERT INTO prodDb.record_item (version,
									has_away_message,
									is_announcement,
									outgoing,
									record_id,
									when_created,
									class,
									contents)
	VALUES (0,
			0,
			0,
			1,
			this_record_id,
			text_created,
			'org.textup.RecordText',
			text_contents);
END $$

CREATE PROCEDURE create_contact_for_subscriber(IN this_phone_id BIGINT(20),
	IN personal_phone_number VARCHAR(255), OUT new_contact_id BIGINT(20))
BEGIN
	DECLARE new_record_id BIGINT(20);
	-- create new empty record for contact
	CALL create_empty_record(new_record_id);
	-- insert subscriber as contact
	INSERT INTO prodDb.contact (version,
								phone_id,
								record_id,
								status)
	VALUES (0,
			this_phone_id,
			new_record_id,
			'ACTIVE');
	-- store id of newly created contact
	SELECT LAST_INSERT_ID() INTO new_contact_id;
	-- insert subscriber phone number as contact number
	INSERT INTO prodDb.contact_number (version,
									number,
									owner_id,
									preference,
									numbers_idx)
	VALUES (0,
			personal_phone_number,
			new_contact_id,
			0,
			0);
END $$

/*
Transfer utility stored procedures
 */

CREATE PROCEDURE transfer_staffs_no_phones(IN agency_to_transfer BIGINT(20),
	IN new_org_id BIGINT(20), IN new_team_id BIGINT(20))
BEGIN
	DECLARE s_version BIGINT(20);
	DECLARE s_account_expired BIT;
	DECLARE s_account_locked BIT;
	DECLARE s_enabled BIT;
	DECLARE s_password_expired BIT;
	DECLARE s_name VARCHAR(255);
	DECLARE s_keyword VARCHAR(255);
	DECLARE s_email VARCHAR(255);
	DECLARE s_password VARCHAR(255);
	DECLARE s_personal_phone_number VARCHAR(255);
	DECLARE prev_person_id BIGINT(20);

	DECLARE this_role_id BIGINT(20);
	DECLARE new_schedule_id BIGINT(20);
	DECLARE new_staff_id BIGINT(20);

	DECLARE is_finished INTEGER DEFAULT 0;
	DECLARE staff_cursor CURSOR FOR
		SELECT e.version,
			e.account_expired,
			e.account_locked,
			e.enabled,
			e.password_expired,
			e.name,
			e.keyword,
			e.email,
			e.password,
			e.personal_phone_number,
			e.id
		FROM entity_relationship as er
		INNER JOIN entity  as e
		ON e.id = er.entity_id
		WHERE er.entity_id != agency_to_transfer
		AND e.class = 'co.textup.Person'
		AND e.is_claimed = 1
		AND (er.id IN (SELECT member1_id as member_id
				FROM relationship
				WHERE id IN (SELECT relationship_id
					FROM entity_relationship
					WHERE entity_id = agency_to_transfer))
			OR er.id IN (SELECT member2_id as member_id
				FROM relationship
				WHERE id IN (SELECT relationship_id
					FROM entity_relationship
					WHERE entity_id = agency_to_transfer)));
	DECLARE CONTINUE HANDLER FOR NOT FOUND SET is_finished = 1;
	OPEN staff_cursor;

	get_staff: LOOP
		FETCH staff_cursor INTO s_version,
								s_account_expired,
								s_account_locked,
								s_enabled,
								s_password_expired,
								s_name,
								s_keyword,
								s_email,
								s_password,
								s_personal_phone_number,
								prev_person_id;
		IF is_finished = 1 THEN
			LEAVE get_staff;
		END IF;
		-- create an empty schedule
		CALL create_empty_schedule(new_schedule_id);
		-- insert person as new staff member
		INSERT INTO prodDb.staff (version,
						       account_expired,
						       account_locked,
						       email,
						       enabled,
						       is_available,
						       manual_schedule,
						       name,
						       org_id,
						       password,
						       password_expired,
						       personal_phone_as_string,
						       schedule_id,
						       status,
						       username)
		VALUES (s_version,
				s_account_expired,
				s_account_locked,
				s_email,
				s_enabled,
				true,
				true,
				s_name,
				new_org_id,
				s_password,
				s_password_expired,
				s_personal_phone_number,
				new_schedule_id,
				'ADMIN',
				s_keyword);
		-- store id of new staff member
		SELECT LAST_INSERT_ID() INTO new_staff_id;
		-- extracting existing role ID (assuming that the order of roles is same)
		SELECT role_id
		INTO this_role_id
		FROM person_role
		WHERE person_id = prev_person_id;
		-- insert this role with the new staff member created
		INSERT INTO prodDb.staff_role (role_id, staff_id)
		VALUES(this_role_id,
			new_staff_id);
		-- associate new staff member with the agency's single team
		INSERT INTO prodDb.team_staff (team_members_id,
									staff_id)
		VALUES (new_team_id,
			new_staff_id);
	END LOOP get_staff;
	CLOSE staff_cursor;
END $$

CREATE PROCEDURE transfer_subscribers_for_place(IN this_place_id BIGINT(20),
	IN new_tag_id BIGINT(20), IN this_phone_id BIGINT(20))
BEGIN
	DECLARE new_record_id, new_contact_id, old_subscriber_id BIGINT(20);
	DECLARE personal_phone_number VARCHAR(255);

	DECLARE is_finished, contact_already_exists INTEGER DEFAULT 0;
	DECLARE subscriber_cursor CURSOR FOR
		SELECT e.personal_phone_number,
			e.id
		FROM entity_relationship as er
		INNER JOIN entity  as e
		ON e.id = er.entity_id
		WHERE er.entity_id != this_place_id
		AND e.class = 'co.textup.Person'
		AND e.is_claimed = 0
		AND (er.id IN (SELECT member1_id as member_id
				FROM relationship
				WHERE id IN (SELECT relationship_id
					FROM entity_relationship
					WHERE entity_id = this_place_id))
			OR er.id IN (SELECT member2_id as member_id
				FROM relationship
				WHERE id IN (SELECT relationship_id
					FROM entity_relationship
					WHERE entity_id = this_place_id)));
	DECLARE CONTINUE HANDLER FOR NOT FOUND SET is_finished = 1;

	OPEN subscriber_cursor;
	get_subscriber: LOOP
		FETCH subscriber_cursor INTO personal_phone_number,
									old_subscriber_id;
		IF is_finished = 1 THEN
			LEAVE get_subscriber;
		END IF;
		-- see if contact already exists for subscriber
		SELECT COUNT(*)
		INTO contact_already_exists
		FROM subscriber_to_contact_ids
		WHERE subscriber_id = old_subscriber_id;
		-- retrieve contact id if one already exists
		IF contact_already_exists > 0 THEN
			SELECT contact_id
			INTO new_contact_id
			FROM subscriber_to_contact_ids
			WHERE subscriber_id = old_subscriber_id;
		ELSE -- migrate subscriber to contact if contact does not already exist
			CALL create_contact_for_subscriber(this_phone_id, personal_phone_number,
				new_contact_id);
			-- associate id of newly created contact with id of subscriber
			INSERT INTO subscriber_to_contact_ids (subscriber_id,
												contact_id)
			VALUES (old_subscriber_id,
					new_contact_id);
		END IF;
		-- add the newly created contact to the appropriate tag
		INSERT INTO prodDb.contact_tag_contact (contact_tag_members_id,
												contact_id)
		VALUES (new_tag_id,
				new_contact_id);
	END LOOP get_subscriber;
	CLOSE subscriber_cursor;
END $$

CREATE PROCEDURE transfer_places(IN agency_to_transfer BIGINT(20),
	IN this_phone_id BIGINT(20))
BEGIN
	DECLARE t_version, new_record_id, new_tag_id, old_place_id BIGINT(20);
	DECLARE t_name VARCHAR(255);

	DECLARE is_finished INTEGER DEFAULT 0;
	DECLARE place_cursor CURSOR FOR
		SELECT e.version,
			e.name,
			e.id
		FROM entity_relationship as er
		INNER JOIN entity  as e
		ON e.id = er.entity_id
		WHERE er.entity_id != agency_to_transfer
		AND e.class = 'co.textup.Place'
		AND (er.id IN (SELECT member1_id as member_id
				FROM relationship
				WHERE id IN (SELECT relationship_id
					FROM entity_relationship
					WHERE entity_id = agency_to_transfer))
			OR er.id IN (SELECT member2_id as member_id
				FROM relationship
				WHERE id IN (SELECT relationship_id
					FROM entity_relationship
					WHERE entity_id = agency_to_transfer)));
	DECLARE CONTINUE HANDLER FOR NOT FOUND SET is_finished = 1;

	OPEN place_cursor;
	get_place: LOOP
		FETCH place_cursor INTO t_version,
								t_name,
								old_place_id;
		IF is_finished = 1 THEN
			LEAVE get_place;
		END IF;
		-- create an empty record
		CALL create_empty_record(new_record_id);
		-- create a contact tag
		INSERT INTO prodDb.contact_tag (version,
										hex_color,
										is_deleted,
										name,
										phone_id,
										record_id)
		VALUES (t_version,
				'#1BA5E0',
				0,
				t_name,
				this_phone_id,
				new_record_id);
		-- store id of newly created tag
		SELECT LAST_INSERT_ID() INTO new_tag_id;
		-- associate place id with newly created tag id
		INSERT INTO place_to_tag_ids (place_id,
									tag_id)
		VALUES (old_place_id,
				new_tag_id);
		-- transfer subscribers to this place as contacts
		CALL transfer_subscribers_for_place(old_place_id, new_tag_id, this_phone_id);
	END LOOP get_place;
	CLOSE place_cursor;
END $$

CREATE PROCEDURE transfer_alerts_for_subscribers(IN this_alert_id BIGINT(20),
	IN text_contents VARCHAR(255), IN text_created DATETIME)
BEGIN
	DECLARE subscriber_record_id BIGINT(20);

	DECLARE is_finished INTEGER DEFAULT 0;
	DECLARE alert_subscriber_cursor CURSOR FOR
		SELECT record_id
		FROM prodDb.contact
		WHERE id IN (SELECT contact_id
			FROM subscriber_to_contact_ids
			WHERE subscriber_id IN (SELECT sent_string
				FROM alert_sent
				WHERE alert_id = this_alert_id));
	DECLARE CONTINUE HANDLER FOR NOT FOUND SET is_finished = 1;

	OPEN alert_subscriber_cursor;
	get_alert_for_subscriber: LOOP
		-- FETCH alert_subscriber_cursor INTO subscriber_record_id;
		FETCH alert_subscriber_cursor INTO subscriber_record_id;
		IF is_finished THEN
			LEAVE get_alert_for_subscriber;
		END IF;
		-- create a record text for the alert in the contact's record
		CALL create_record_text(subscriber_record_id, text_contents, text_created);
	END LOOP get_alert_for_subscriber;
	CLOSE alert_subscriber_cursor;
END $$

CREATE PROCEDURE transfer_alerts(IN agency_to_transfer BIGINT(20))
BEGIN
	DECLARE old_place_id, this_alert_id, tag_record_id BIGINT(20);
	DECLARE t_contents VARCHAR(255);
	DECLARE t_created DATETIME;

	DECLARE is_finished INTEGER DEFAULT 0;
	DECLARE alert_cursor CURSOR FOR
		SELECT selection_value,
			created,
			place_id,
			id
		FROM choice_group
		WHERE class = 'co.textup.Alert'
		AND place_id IN (SELECT e.id
			FROM entity_relationship as er
			INNER JOIN entity  as e
			ON e.id = er.entity_id
			WHERE er.entity_id != agency_to_transfer
			AND e.class = 'co.textup.Place'
			AND (er.id IN (SELECT member1_id as member_id
					FROM relationship
					WHERE id IN (SELECT relationship_id
						FROM entity_relationship
						WHERE entity_id = agency_to_transfer))
				OR er.id IN (SELECT member2_id as member_id
					FROM relationship
					WHERE id IN (SELECT relationship_id
						FROM entity_relationship
						WHERE entity_id = agency_to_transfer))));
	DECLARE CONTINUE HANDLER FOR NOT FOUND SET is_finished = 1;

	OPEN alert_cursor;
	get_alert: LOOP
		FETCH alert_cursor INTO t_contents,
								t_created,
								old_place_id,
								this_alert_id;
		IF is_finished = 1 THEN
			LEAVE get_alert;
		END IF;
		-- retrieve id of the record of the tag the associated place was migrated to
		SELECT record_id
		INTO tag_record_id
		FROM prodDb.contact_tag
		WHERE id = (SELECT tag_id
			FROM place_to_tag_ids
			WHERE place_id = old_place_id);
		-- insert the alert as a text into the tag's record
		CALL create_record_text(tag_record_id, t_contents, t_created);
		-- also insert alert as text for all of the contacts associated in this tag
		CALL transfer_alerts_for_subscribers(this_alert_id, t_contents, t_created);
	END LOOP get_alert;
	CLOSE alert_cursor;
END $$

CREATE PROCEDURE transfer_agency(IN agency_to_transfer BIGINT(20))
BEGIN
	DECLARE a_id BIGINT(20);
	DECLARE a_version BIGINT(20);
	DECLARE a_name VARCHAR(255);

	DECLARE new_location_id BIGINT(20);
	DECLARE new_org_id BIGINT(20);
	DECLARE new_team_id BIGINT(20);
	DECLARE new_phone_id BIGINT(20);
	-- extract agency information
	SELECT id,
		version,
		name
	INTO a_id,
		a_version,
		a_name
	FROM entity
	WHERE class = 'co.textup.Agency'
	AND id = agency_to_transfer;
	-- create a default location for agency
	CALL create_default_location(new_location_id);
	-- create new organization using agency information and default location
	INSERT INTO prodDb.organization (version, location_id, name, status)
	VALUES (a_version,
		new_location_id,
		a_name,
		'APPROVED');
	-- store id of newly created organization
	SELECT LAST_INSERT_ID() INTO new_org_id;
	-- creating one team for agency that shares agency's name WITH TEAM PHONE
	CALL create_team_with_phone(new_org_id, a_name, new_team_id, new_phone_id);
	-- transfer staffs and add to single team
	CALL transfer_staffs_no_phones(agency_to_transfer, new_org_id, new_team_id);
	-- create temporary tables for places and subscribers
	DROP TEMPORARY TABLE IF EXISTS place_to_tag_ids;
	DROP TEMPORARY TABLE IF EXISTS subscriber_to_contact_ids;
	CREATE TEMPORARY TABLE place_to_tag_ids (
		place_id BIGINT(20),
		tag_id BIGINT(20));
	CREATE TEMPORARY TABLE subscriber_to_contact_ids (
		subscriber_id BIGINT(20),
		contact_id BIGINT(20));
	-- transfer places ("keywords") as contact tags in the team's phone
	CALL transfer_places(agency_to_transfer, new_phone_id);
	-- looping over alerts, adding to records with receipts
	CALL transfer_alerts(agency_to_transfer);
	-- drop temporary tables now that they are un-needed
	DROP TEMPORARY TABLE place_to_tag_ids;
	DROP TEMPORARY TABLE subscriber_to_contact_ids;
END $$

/*
Initializing stored procedure
 */

CREATE PROCEDURE do_migration(IN agency_to_transfer BIGINT(20))
BEGIN
	DECLARE has_error INTEGER DEFAULT 0;
	DECLARE CONTINUE HANDLER FOR SQLEXCEPTION
	BEGIN
		SET has_error = 1;
		SHOW ERRORS;
	END;

	SET FOREIGN_KEY_CHECKS = 0;

	START TRANSACTION;
	CALL transfer_agency(agency_to_transfer);
	IF has_error = 1 THEN
		ROLLBACK;
	ELSE
		COMMIT;
		SELECT 'Successfully completed migration from v1 to v2.5';
	END IF;

	SET FOREIGN_KEY_CHECKS = 1;
END $$

DELIMITER ;

CALL do_migration(33);
