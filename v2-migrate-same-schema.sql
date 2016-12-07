-- Migration script between two databases with the exact same schema
-- This was written to migrate the data to a new schema that was
-- exactly the same except for the new utf8mb4 full unicode encoding
-- -----------
-- ASSUMPTIONS
-- -----------

USE v2Schema;

DROP PROCEDURE IF EXISTS migrate_tables;
DROP PROCEDURE IF EXISTS do_migration;

DELIMITER $$
	CREATE PROCEDURE migrate_tables()
	BEGIN
		DECLARE t_name VARCHAR(64);

		DECLARE is_finished INTEGER DEFAULT 0;
		DECLARE table_cursor CURSOR FOR
			SELECT TABLE_NAME
			FROM information_schema.TABLES
			WHERE TABLE_SCHEMA = 'v2Schema';
		DECLARE CONTINUE HANDLER FOR NOT FOUND SET is_finished = 1;

		OPEN table_cursor;
		get_table: LOOP
			FETCH table_cursor INTO t_name;
			IF is_finished = 1 THEN
				LEAVE get_table;
			END IF;

			IF t_name != 'DATABASECHANGELOG' AND t_name != 'DATABASECHANGELOGLOCK' THEN
				SET @copy_data = CONCAT('INSERT INTO fullDb.', t_name,
					' SELECT * FROM ', t_name);
				PREPARE stmt from @copy_data;
				EXECUTE stmt;
			END IF;
		END LOOP get_table;
		CLOSE table_cursor;
	END $$

	CREATE PROCEDURE do_migration()
	BEGIN
		DECLARE has_error INTEGER DEFAULT 0;
		DECLARE CONTINUE HANDLER FOR SQLEXCEPTION
			BEGIN
				SET has_error = 1;
				SHOW ERRORS;
			END;

		SET FOREIGN_KEY_CHECKS = 0;

		START TRANSACTION;
		CALL migrate_tables();
		IF has_error = 1 THEN
			ROLLBACK;
		ELSE
			COMMIT;
			SELECT 'Successfully copied over data';
		END IF;

		SET FOREIGN_KEY_CHECKS = 1;
	END $$
DELIMITER ;

CALL do_migration();
