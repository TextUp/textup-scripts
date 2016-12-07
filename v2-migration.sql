-- Migration script from v2.beta to v2
-- -----------
-- ASSUMPTIONS
-- -----------
-- No shared contacts (for simplicity)
-- Teams do not have phones
-- Contact tags do not have pre-existing records
-- Role (ADMIN vs STAFF) are in the same order in both databases

USE prodDb;
DROP PROCEDURE IF EXISTS transfer_organization;
DROP PROCEDURE IF EXISTS transfer_staffs;
DROP PROCEDURE IF EXISTS transfer_team_memberships;
DROP PROCEDURE IF EXISTS transfer_teams;
DROP PROCEDURE IF EXISTS transfer_staffs_and_teams;
DROP PROCEDURE IF EXISTS transfer_phones;
DROP PROCEDURE IF EXISTS transfer_tag_memberships;
DROP PROCEDURE IF EXISTS transfer_contact_numbers;
DROP PROCEDURE IF EXISTS transfer_tags;
DROP PROCEDURE IF EXISTS transfer_contacts;
DROP PROCEDURE IF EXISTS transfer_record_items;
DROP PROCEDURE IF EXISTS transfer_receipts;
DROP PROCEDURE IF EXISTS transfer_contacts_and_tags;
DROP PROCEDURE IF EXISTS do_migration;

DELIMITER $$

	CREATE PROCEDURE transfer_receipts(IN prev_item_id BIGINT(20),
		IN new_item_id BIGINT(20))
	BEGIN
		DECLARE i_version BIGINT(20);
		DECLARE i_api_id VARCHAR(255);
		DECLARE i_received_by_number BIGINT(20);
		DECLARE i_status VARCHAR(255);

		DECLARE is_finished INTEGER DEFAULT 0;
		DECLARE receipt_cursor CURSOR FOR
			SELECT version,
				api_id,
				received_by_number,
				status
			FROM record_item_receipt
			WHERE item_id = prev_item_id;
		DECLARE CONTINUE HANDLER FOR NOT FOUND SET is_finished = 1;
		OPEN receipt_cursor;

		get_receipt: LOOP
			FETCH receipt_cursor INTO i_version,
									i_api_id,
									i_received_by_number,
									i_status;
			IF is_finished = 1 THEN
				LEAVE get_receipt;
			END IF;
			INSERT INTO v2Schema.record_item_receipt (item_id,
													version,
													api_id,
													received_by_as_string,
													status)
			VALUES(new_item_id,
				i_version,
				i_api_id,
				i_received_by_number,
				UPPER(i_status));
		END LOOP get_receipt;
		CLOSE receipt_cursor;
	END $$

	CREATE PROCEDURE transfer_record_items(IN prev_record_id BIGINT(20),
		IN new_record_id BIGINT(20))
	this_procedure: BEGIN
		DECLARE prev_item_id BIGINT(20);
		DECLARE c_version BIGINT(20);
		DECLARE c_outgoing BIT;
		DECLARE c_when_created DATETIME;
		DECLARE c_class VARCHAR(255);
		DECLARE c_duration_in_seconds INT(20);
		DECLARE c_voicemail_in_seconds INT(20);
		DECLARE c_contents VARCHAR(320);

		DECLARE new_item_id BIGINT(20);

		DECLARE is_finished INTEGER DEFAULT 0;
		DECLARE item_cursor CURSOR FOR
			SELECT id,
				version,
				date_created,
				outgoing,
				class,
				duration_in_seconds,
				voicemail_in_seconds,
				contents
			FROM record_item
			WHERE record_id = prev_record_id;
		DECLARE CONTINUE HANDLER FOR NOT FOUND SET is_finished = 1;

		IF prev_record_id IS NULL THEN
			LEAVE this_procedure;
		END IF;

		OPEN item_cursor;

		get_item: LOOP
			FETCH item_cursor INTO prev_item_id,
								c_version,
								c_when_created,
								c_outgoing,
								c_class,
								c_duration_in_seconds,
								c_voicemail_in_seconds,
								c_contents;
			IF is_finished = 1 THEN
				LEAVE get_item;
			END IF;
			INSERT INTO v2Schema.record_item (version,
											has_away_message,
											is_announcement,
											outgoing,
											record_id,
											when_created,
											class,
											duration_in_seconds,
											voicemail_in_seconds,
											contents)
			VALUES(c_version,
				false,
				false,
				c_outgoing,
				new_record_id,
				c_when_created,
				c_class,
				c_duration_in_seconds,
				c_voicemail_in_seconds,
				c_contents);

			SELECT LAST_INSERT_ID() INTO new_item_id;

			CALL transfer_receipts(prev_item_id, new_item_id);
		END LOOP get_item;
		CLOSE item_cursor;
	END $$

	CREATE PROCEDURE transfer_tag_memberships(IN prev_contact_id BIGINT(20),
		IN new_contact_id BIGINT(20))
	BEGIN
		DECLARE prev_tag_id BIGINT(20);
		DECLARE this_new_tag_id BIGINT(20);

		DECLARE is_finished INTEGER DEFAULT 0;
		DECLARE member_cursor CURSOR FOR
			SELECT tag_id
			FROM tag_membership
			WHERE contact_id = prev_contact_id;
		DECLARE CONTINUE HANDLER FOR NOT FOUND SET is_finished = 1;
		OPEN member_cursor;

		get_member: LOOP
			FETCH member_cursor INTO prev_tag_id;
			IF is_finished = 1 THEN
				LEAVE get_member;
			END IF;

			SELECT new_tag_id
			INTO this_new_tag_id
			FROM tag_id_conversion
			WHERE old_tag_id = prev_tag_id;

			INSERT INTO v2Schema.contact_tag_contact (contact_tag_members_id, contact_id)
			VALUES (this_new_tag_id,
					new_contact_id);
		END LOOP get_member;
		CLOSE member_cursor;
	END $$

	CREATE PROCEDURE transfer_contact_numbers(IN prev_contact_id BIGINT(20),
		IN new_contact_id BIGINT(20))
	BEGIN
		DECLARE n_version BIGINT(20);
		DECLARE n_number VARCHAR(255);
		DECLARE n_preference INT(11);
		DECLARE n_numbers_idx INT(11);

		DECLARE is_finished INTEGER DEFAULT 0;
		DECLARE num_cursor CURSOR FOR
			SELECT version,
				number,
				preference,
				numbers_idx
			FROM phone_number
			WHERE class = 'org.textup.ContactNumber'
				AND contact_id = prev_contact_id;
		DECLARE CONTINUE HANDLER FOR NOT FOUND SET is_finished = 1;

		OPEN num_cursor;
		get_num: LOOP
			FETCH num_cursor INTO n_version,
								n_number,
								n_preference,
								n_numbers_idx;
			IF is_finished = 1 THEN
				LEAVE get_num;
			END IF;
			INSERT INTO v2Schema.contact_number (version,
												number,
												owner_id,
												preference,
												numbers_idx)
			VALUES (n_version,
					n_number,
					new_contact_id,
					n_preference,
					n_numbers_idx);
		END LOOP get_num;
		CLOSE num_cursor;
	END $$

	CREATE PROCEDURE transfer_contacts(IN prev_phone_id BIGINT(20),
		IN new_phone_id BIGINT(20))
	BEGIN
		DECLARE prev_contact_id BIGINT(20);
		DECLARE c_version BIGINT(20);
		DECLARE c_last_record_activity DATETIME;
		DECLARE c_name VARCHAR(255);
		DECLARE c_note VARCHAR(1000);
		DECLARE prev_record_id BIGINT(20);
		DECLARE c_status VARCHAR(8);

		DECLARE new_record_id BIGINT(20);
		DECLARE new_contact_id BIGINT(20);

		DECLARE is_finished INTEGER DEFAULT 0;
		DECLARE contact_cursor CURSOR FOR
			SELECT id,
				version,
				last_record_activity,
				name,
				note,
				record_id,
				status
			FROM contact
			WHERE phone_id = prev_phone_id;
		DECLARE CONTINUE HANDLER FOR NOT FOUND SET is_finished = 1;
		OPEN contact_cursor;

		get_contact: LOOP
			FETCH contact_cursor INTO prev_contact_id,
									c_version,
									c_last_record_activity,
									c_name,
									c_note,
									prev_record_id,
									c_status;
			IF is_finished = 1 THEN
				LEAVE get_contact;
			END IF;

			INSERT INTO v2Schema.record (version, last_record_activity)
			VALUES(0,
				c_last_record_activity);

			SELECT LAST_INSERT_ID() INTO new_record_id;

			INSERT INTO v2Schema.contact(version, name, note, phone_id, record_id, status)
			VALUES (c_version,
				c_name,
				c_note,
				new_phone_id,
				new_record_id,
				UPPER(c_status));

			SELECT LAST_INSERT_ID() INTO new_contact_id;

			CALL transfer_record_items(prev_record_id, new_record_id);
			CALL transfer_contact_numbers(prev_contact_id, new_contact_id);
			CALL transfer_tag_memberships(prev_contact_id, new_contact_id);
		END LOOP get_contact;
		CLOSE contact_cursor;
	END $$

	CREATE PROCEDURE transfer_tags(IN prev_phone_id BIGINT(20),
		IN new_phone_id BIGINT(20))
	BEGIN
		DECLARE prev_tag_id BIGINT(20);
		DECLARE t_version BIGINT(20);
		DECLARE t_hex_color VARCHAR(255);
		DECLARE t_name VARCHAR(255);
		DECLARE t_last_record_activity DATETIME;

		DECLARE this_tag_id BIGINT(20);
		DECLARE new_record_id BIGINT(20);

		DECLARE is_finished INTEGER DEFAULT 0;
		DECLARE tag_cursor CURSOR FOR
			SELECT id,
			       VERSION,
			       hex_color,
			       name,
			       last_record_activity
			FROM contact_tag
			WHERE phone_id = prev_phone_id
			    AND CLASS = 'org.textup.ContactTag';
		DECLARE CONTINUE HANDLER FOR NOT FOUND SET is_finished = 1;
		OPEN tag_cursor;
		-- for each tag
		 get_tag: LOOP
	 		FETCH tag_cursor INTO prev_tag_id,
	 							  t_version,
	                              t_hex_color,
	                              t_name,
	                              t_last_record_activity;
	        IF is_finished = 1 THEN
	        	LEAVE get_tag;
	        END IF;
	        IF t_last_record_activity IS NULL THEN
	        	SET t_last_record_activity = NOW();
	        END IF;
			-- create a record for that tag
			INSERT INTO v2Schema.record (version, last_record_activity)
			VALUES (0,
			        t_last_record_activity);
			-- get id of this newly inserted record
			SELECT LAST_INSERT_ID() INTO new_record_id;
			-- copy over contact tag and associate with new record
			INSERT INTO v2Schema.contact_tag(hex_color, is_deleted, name, phone_id, record_id, version)
			VALUES (t_hex_color,
			        0,
			        t_name,
			        new_phone_id,
			        new_record_id,
			        0);
			SELECT LAST_INSERT_ID() INTO this_tag_id;
			-- populate tag id conversion table
			INSERT INTO tag_id_conversion (old_tag_id, new_tag_id)
			VALUES (prev_tag_id,
				this_tag_id);
		 END LOOP get_tag;
		CLOSE tag_cursor;
	END $$

	CREATE PROCEDURE transfer_contacts_and_tags(IN prev_phone_id BIGINT(20),
		IN new_phone_id BIGINT(20))
	BEGIN
		DROP TEMPORARY TABLE IF EXISTS tag_id_conversion;
		CREATE TEMPORARY TABLE tag_id_conversion (
			old_tag_id BIGINT(20),
			new_tag_id BIGINT(20));
		-- populates temporary table
		CALL transfer_tags(prev_phone_id, new_phone_id);
		-- uses populated temporary table
		CALL transfer_contacts(prev_phone_id, new_phone_id);
		-- clean up temporary table
		DROP TEMPORARY TABLE tag_id_conversion;
	END $$

	CREATE PROCEDURE transfer_phones(IN prev_staff_id BIGINT(20),
		IN new_staff_id BIGINT(20))
	BEGIN
		-- declare variables
		DECLARE prev_phone_id BIGINT(20);
		DECLARE p_version BIGINT(20);
		DECLARE p_api_id VARCHAR(255);
		DECLARE p_number VARCHAR(255);
		DECLARE p_away_message VARCHAR(160);

		DECLARE new_ownership_id BIGINT(20);
		DECLARE new_phone_id BIGINT(20);

		DECLARE EXIT HANDLER FOR NOT FOUND BEGIN END;
		-- select prev phone values
		SELECT ph.id,
			ph.version,
			ph.api_id,
			ph.number_number,
			st.away_message
		INTO prev_phone_id,
			p_version,
			p_api_id,
			p_number,
			p_away_message
		FROM phone as ph
		JOIN staff AS st ON st.id = ph.owner_id
		WHERE ph.class = 'org.textup.StaffPhone'
			AND ph.api_id IS NOT NULL
			AND st.id = prev_staff_id;
		-- create a phone
		INSERT INTO v2Schema.phone (version, api_id, away_message, number_as_string)
		VALUES(p_version,
			p_api_id,
			p_away_message,
			p_number);
		SELECT LAST_INSERT_ID() INTO new_phone_id;
		-- create a phone ownership
		INSERT INTO v2Schema.phone_ownership (version, owner_id, phone_id, type)
		VALUES (0,
		        new_staff_id,
		        new_phone_id,
		        'INDIVIDUAL');
		SELECT LAST_INSERT_ID() INTO new_ownership_id;
		-- update previously inserted phone with accurate owner id
		-- recall that before we substituted owner_id for the
		UPDATE v2Schema.phone as ph
		SET ph.owner_id = new_ownership_id
		WHERE ph.id = new_phone_id;

		CALL transfer_contacts_and_tags(prev_phone_id, new_phone_id);
	END $$

	CREATE PROCEDURE transfer_team_memberships(IN prev_staff_id BIGINT(20),
		IN new_staff_id BIGINT(20))
	BEGIN
		DECLARE prev_team_id BIGINT(20);
		DECLARE this_new_team_id BIGINT(20);

		DECLARE is_finished INTEGER DEFAULT 0;
		DECLARE member_cursor CURSOR FOR
			SELECT team_id
			FROM team_membership
			WHERE staff_id = prev_staff_id;
		DECLARE CONTINUE HANDLER FOR NOT FOUND SET is_finished = 1;

		OPEN member_cursor;
		get_member: LOOP
			FETCH member_cursor INTO prev_team_id;
			IF is_finished = 1 THEN
				LEAVE get_member;
			END IF;
			-- convert to team id in the new (target) db
			SELECT new_team_id
			INTO this_new_team_id
			FROM team_id_conversion
			WHERE old_team_id = prev_team_id;
			-- create new team membership
			INSERT INTO v2Schema.team_staff (team_members_id, staff_id)
			VALUES (this_new_team_id,
					new_staff_id);
		END LOOP get_member;
		CLOSE member_cursor;
	END $$

	CREATE PROCEDURE transfer_staffs(IN prev_org_id BIGINT(20),
		IN new_org_id BIGINT(20))
	BEGIN
		DECLARE s_version BIGINT(20);
		DECLARE s_account_expired BIT;
		DECLARE s_account_locked BIT;
		DECLARE s_email VARCHAR(255);
		DECLARE s_enabled BIT;
		DECLARE s_is_available BIT;
		DECLARE s_manual_schedule BIT;
		DECLARE s_name VARCHAR(255);
		DECLARE s_password VARCHAR(255);
		DECLARE s_password_expired BIT;
		DECLARE s_personal_phone_number_number VARCHAR(255);
		DECLARE s_status VARCHAR(7);
		DECLARE s_username VARCHAR(255);
		DECLARE prev_staff_id BIGINT(20);
		DECLARE prev_phone_id BIGINT(20);
		DECLARE prev_schedule_id BIGINT(20);

		DECLARE this_role_id BIGINT(20);
		DECLARE new_schedule_id BIGINT(20);
		DECLARE new_staff_id BIGINT(20);

		DECLARE is_finished INTEGER DEFAULT 0;
		DECLARE staff_cursor CURSOR FOR
			SELECT version,
			       account_expired,
			       account_locked,
			       email,
			       enabled,
			       is_available,
			       manual_schedule,
			       name,
			       password,
			       password_expired,
			       personal_phone_number_number,
			       status,
			       username,
			       id,
			       phone_id,
			       schedule_id
			FROM staff
			WHERE org_id = prev_org_id;
		DECLARE CONTINUE HANDLER FOR NOT FOUND SET is_finished = 1;
		OPEN staff_cursor;

		get_staff: LOOP
			FETCH staff_cursor INTO s_version,
									s_account_expired,
									s_account_locked,
									s_email,
									s_enabled,
									s_is_available,
									s_manual_schedule,
									s_name,
									s_password,
									s_password_expired,
									s_personal_phone_number_number,
									s_status,
									s_username,
									prev_staff_id,
									prev_phone_id,
									prev_schedule_id;
			IF is_finished = 1 THEN
				LEAVE get_staff;
			END IF;

			 -- schedule
			INSERT INTO v2Schema.schedule (version,
				class,
				friday,
				monday,
				saturday,
				sunday,
				thursday,
				tuesday,
				wednesday)
			SELECT version,
				class,
				friday,
				monday,
				saturday,
				sunday,
				thursday,
				tuesday,
				wednesday
			FROM schedule
			WHERE id = prev_schedule_id;

			SELECT LAST_INSERT_ID() INTO new_schedule_id;

			-- staff
			INSERT INTO v2Schema.staff (version,
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
				s_is_available,
				s_manual_schedule,
				s_name,
				new_org_id,
				s_password,
				s_password_expired,
				s_personal_phone_number_number,
				new_schedule_id,
				UPPER(s_status),
				s_username);

			SELECT LAST_INSERT_ID() INTO new_staff_id;

			-- staff role
			SELECT role_id INTO this_role_id
			FROM staff_role
			WHERE staff_id = prev_staff_id;

			INSERT INTO v2Schema.staff_role (role_id, staff_id)
			VALUES(this_role_id,
				new_staff_id);

			-- transfer phone if we have a phone
			IF prev_phone_id IS NOT NULL THEN
				CALL transfer_phones(prev_staff_id, new_staff_id);
			END IF;
			CALL transfer_team_memberships(prev_staff_id, new_staff_id);
		END LOOP get_staff;
		CLOSE staff_cursor;
	END $$

	CREATE PROCEDURE transfer_teams(IN prev_org_id BIGINT(20),
		IN new_org_id BIGINT(20))
	BEGIN
		DECLARE prev_team_id BIGINT(20);
		DECLARE t_version BIGINT(20);
		DECLARE t_hex_color VARCHAR(255);
		DECLARE prev_location_id BIGINT(20);
		DECLARE t_name VARCHAR(255);

		DECLARE new_location_id BIGINT(20);
		DECLARE this_new_team_id BIGINT(20);

		DECLARE is_finished INTEGER DEFAULT 0;
		DECLARE team_cursor CURSOR FOR
			SELECT id,
				version,
				hex_color,
				location_id,
				name
			FROM team
			WHERE org_id = prev_org_id;
		DECLARE CONTINUE HANDLER FOR NOT FOUND SET is_finished = 1;

		OPEN team_cursor;
		get_team: LOOP
			FETCH team_cursor INTO prev_team_id,
								t_version,
								t_hex_color,
								prev_location_id,
								t_name;
			IF is_finished = 1 THEN
				LEAVE get_team;
			END IF;
			-- location
			INSERT INTO v2Schema.location (version, address, lat, lon)
			SELECT version,
				address,
				lat,
				lon
			FROM location
			WHERE id = prev_location_id;

			SELECT LAST_INSERT_ID() INTO new_location_id;
			-- team (assume no phone)
			INSERT INTO v2Schema.team (version,
									hex_color,
									is_deleted,
									location_id,
									name,
									org_id)
			VALUES (t_version,
					t_hex_color,
					0,
					new_location_id,
					t_name,
					new_org_id);

			SELECT LAST_INSERT_ID() INTO this_new_team_id;
			-- populate team id conversion temporary table
			INSERT INTO team_id_conversion (old_team_id, new_team_id)
			VALUES (prev_team_id,
				this_new_team_id);
		END LOOP get_team;
		CLOSE team_cursor;
	END $$

	CREATE PROCEDURE transfer_staffs_and_teams(IN prev_org_id BIGINT(20),
		IN new_org_id BIGINT(20))
	BEGIN
		DROP TEMPORARY TABLE IF EXISTS team_id_conversion;
		CREATE TEMPORARY TABLE team_id_conversion (
			old_team_id BIGINT(20),
			new_team_id BIGINT(20));
		-- populate temporary table
		CALL transfer_teams(prev_org_id, new_org_id);
		-- use temporary table to recreate team memberships
		CALL transfer_staffs(prev_org_id, new_org_id);
		-- clean up temporary table
		DROP TEMPORARY TABLE team_id_conversion;
	END $$

	CREATE PROCEDURE transfer_organization(IN org_to_transfer BIGINT(20))
	BEGIN
		DECLARE prev_location_id BIGINT(20);
		DECLARE o_version BIGINT(20);
		DECLARE o_name VARCHAR(255);
		DECLARE o_status VARCHAR(255);

		DECLARE new_location_id BIGINT(20);
		DECLARE new_org_id BIGINT(20);

		SELECT version,
		       location_id,
		       name,
		       status
		INTO o_version,
			prev_location_id,
			o_name,
			o_status
		FROM organization
		WHERE id = org_to_transfer;

		INSERT INTO v2Schema.location (version, address, lat, lon)
		SELECT version,
			address,
			lat,
			lon
		FROM location
		WHERE id = prev_location_id;

		SELECT LAST_INSERT_ID() INTO new_location_id;

		INSERT INTO v2Schema.organization (version, location_id, name, status)
		VALUES (o_version,
			new_location_id,
			o_name,
			UPPER(o_status));

		SELECT LAST_INSERT_ID() INTO new_org_id;

		-- set off transfer cascade
		CALL transfer_staffs_and_teams(org_to_transfer, new_org_id);
	END $$

	CREATE PROCEDURE do_migration(IN org_to_transfer BIGINT(20))
	BEGIN
		DECLARE has_error INTEGER DEFAULT 0;
		DECLARE CONTINUE HANDLER FOR SQLEXCEPTION
		BEGIN
			SET has_error = 1;
			SHOW ERRORS;
		END;

		SET FOREIGN_KEY_CHECKS = 0;

		START TRANSACTION;
		CALL transfer_organization(org_to_transfer);
		IF has_error = 1 THEN
			ROLLBACK;
		ELSE
			COMMIT;
			SELECT 'Successfully completed migration';
		END IF;

		SET FOREIGN_KEY_CHECKS = 1;
	END $$
DELIMITER ;

CALL do_migration(9);
