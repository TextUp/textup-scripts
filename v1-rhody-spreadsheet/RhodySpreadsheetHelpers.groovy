import groovy.sql.BatchingPreparedStatementWrapper
import groovy.sql.Sql
import groovy.transform.CompileStatic
import groovy.transform.ToString

// Reconciling spreadsheet and the db status
// 1. preference is explicitly NO
// 		1a. contact doesn't exist
// 			contact is created but added to no tags
// 		1b. contact already exists
// 			contact is explicitly removed from all tags
// 2. preference is to add to town
// 		2a. existing contact is member of All Markets tag
//			do nothing
// 		2b. existing contact is NOT member of All Markets
// 			add contact to tags, preserving tags contact is already a member of
// 		2c. contact doesn't exist
// 			create contact
// 			new contact is added to towns specified, if any
// 3. preference is to add to All Markets
// 		3a. existing contact is member of All Markets
// 			do nothing
// 		3b. existing contact is NOT member of All Markets
// 			remove contact from all existing tags, add only to All Markets
// 		3c. contact doesn't exist
// 			create contact
// 			add contact to All Markets
// 4. preference is blank
// 		4a. spreadsheet has towns specified
// 			see #2 (preference is to add to town)
// 		4b. spreadsheet doesn't have towns specified
// 			create contact if doesn't exist
// 			do nothing

@CompileStatic
enum SubscriberPreference {
	REMOVE_FROM_ALL,
	ADD_TO_ALL,
	ADD_TO_CITY,
	NOT_SPECIFIED
}

@CompileStatic
@ToString
class Subscriber {
	String name, phoneNumber, group, email
	List<String> cities = []
	SubscriberPreference preference

	String getNote() {
		StringBuilder builder = new StringBuilder()
		if (this.group) { builder << (this.group + "\n") }
		if (this.cities) { builder << (this.cities.join(", ") + "\n") }
		if (this.email) { builder << this.email }
		builder.toString()
	}
}

@Grapes([
	@GrabConfig(systemClassLoader=true),
	@Grab("mysql:mysql-connector-java:5.1.29")
])
@CompileStatic
class RhodySpreadsheetHelpers {

	Sql sql
	long phoneId
	String allMarketsTagName

	Subscriber extractRow(String info) {
		List<String> data = extractCSV(info)
		new Subscriber(name:"${data[1]} ${data[2]}",
			group:data[3],
			email:data[0],
			phoneNumber:cleanPhoneNumber(data[5]),
			preference:cleanSubscriberResponse(data[6]),
			cities:extractCSV(data[4]))
	}
	boolean processRow(Subscriber sub) {
		if (!sub.phoneNumber) { return true }
		long contactId = contactExists(sub.phoneNumber) ?: addNewContact(sub)
		switch (sub.preference) {
			case SubscriberPreference.ADD_TO_ALL:
				removeFromTagsByIds(contactId, tagIdsForContactId(contactId))
				addToTag(contactId, [allMarketsTagName])
				break
			case SubscriberPreference.ADD_TO_CITY:
				if (!contactInAllMarkets(contactId)) {
					addToTag(contactId, sub.cities)
				}
				break
			case SubscriberPreference.REMOVE_FROM_ALL:
				removeFromTagsByIds(contactId, tagIdsForContactId(contactId))
				break
			case SubscriberPreference.NOT_SPECIFIED:
				if (sub.cities && !contactInAllMarkets(contactId)) {
					addToTag(contactId, sub.cities)
				}
		}
		return true
	}

	// Extraction helper methods
	// -------------------------

	List<String> extractCSV(String info) {
		List<String> data = []
		boolean ignoreCommas = false
		int infoLastIndex = info.size() - 1
		StringBuilder cellSoFar = new StringBuilder()
		info.eachWithIndex { String letter, int index ->
			// cell delimiter that we ignore if ignoreCommas is true
			if (letter == "," && ignoreCommas == false) {
				data << cellSoFar.toString()
				cellSoFar = new StringBuilder()
				// pad with additional blank entry if comma is last character
				if (index == infoLastIndex ) { data << "" }
			}
			// indicates that contents has comma, toggle ignoreCommas delimiter
			else if (letter == "\"") { ignoreCommas = !ignoreCommas  }
			// standard case where we are adding to cell contents
			else { cellSoFar << letter }
		}
		// add last entry if still data in StringBuilder
		String lastEntry = cellSoFar.toString()
		if (lastEntry) { data << lastEntry }
		// trim whitespace on each entry
		data*.trim()
		data
	}
	String cleanPhoneNumber(String rawNumber) {
		String cleaned = rawNumber.replaceAll(/\D/, "")
		(cleaned.size() == 10) ? cleaned : ""
	}
	SubscriberPreference cleanSubscriberResponse(String info) {
		switch (info) {
			case ~/(?i).*(market).*/:
				SubscriberPreference.ADD_TO_ALL
				break
			case ~/(?i).*(no).*/:
				SubscriberPreference.REMOVE_FROM_ALL
				break
			case ~/(?i).*(town).*/:
				SubscriberPreference.ADD_TO_CITY
				break
			default:
				SubscriberPreference.NOT_SPECIFIED
		}
	}

	// Functions to check database
	// ---------------------------

	// check that tag exists by name
	// returns tag id if exists, null otherwise
	Long tagExists(String name) {
		sql.firstRow("""
			SELECT id
			FROM contact_tag
			WHERE phone_id = ?
			AND name = ?
		""", [phoneId, name]*.asType(Object))?.id as Long
	}
	// check that contact exists by phone number
	// return contact id if exists, null otherwise
	Long contactExists(String phoneNumber) {
		sql.firstRow("""
			SELECT c1.id
			FROM contact as c1
			INNER JOIN contact_number as cn
			ON c1.id = cn.owner_id
			WHERE cn.number = ?
			AND c1.phone_id = ?
		""", [phoneNumber, phoneId]*.asType(Object))?.id as Long
	}
	// retrieve list of tag ids that contact is a member of
	Collection<Long> tagIdsForContactId(long contactId) {
		sql.rows("""
			SELECT contact_tag_members_id AS id
			FROM contact_tag_contact
			WHERE contact_id = ?
		""", [contactId]*.asType(Object)).collect { it.id }
	}
	boolean contactInAllMarkets(long contactId) {
		sql.firstRow("""
			SELECT COUNT(*) as num
			FROM contact_tag_contact
			WHERE contact_id = ?
			AND contact_tag_members_id = (SELECT id
				FROM contact_tag
				WHERE name = ?)
		""", [contactId, allMarketsTagName]*.asType(Object)).num?.asType(Integer) > 0
	}

	// Functions to modify database
	// ----------------------------

	// create new contact if absent, returning contact id
	long addNewContact(Subscriber sub) {
		// create new record, storing returned record id
		long recordId = createNewRecord()
		// insert contact, storing returned contact id
		long contactId = sql.executeInsert("""
			INSERT INTO contact (version, name, note, phone_id, record_id, status)
			VALUES (?, ?, ?, ?, ?, ?)
		""", [1, sub.name, sub.note, phoneId, recordId, "ACTIVE"]*.asType(Object))[0][0] as Long
		// insert phone number for newly created contact
		sql.executeInsert("""
			INSERT INTO contact_number (version, number, owner_id, preference, numbers_idx)
			VALUES (?, ?, ?, ?, ?)
		""", [1, sub.phoneNumber, contactId, 0, 0]*.asType(Object))

		contactId
	}
	long addNewTag(String tagName) {
		// create new record, storing returned record id
		long recordId = createNewRecord()
		sql.executeInsert("""
			INSERT INTO contact_tag (version, hex_color, is_deleted, name, phone_id, record_id)
			VALUES (?, ?, ?, ?, ?, ?)
		""", [1, "#1BA5E0", 0, tagName, phoneId, recordId]*.asType(Object))[0][0] as Long
	}
	// add an existing contact to new tags, creating one if none exists
	Collection<Long> addToTag(long contactId, Collection<String> tagNames) {
		if (!tagNames) { return [] }
		HashSet<Long> targetTagIds = new HashSet<>(tagNames.collect { String tagName ->
			tagExists(tagName) ?: addNewTag(tagName)
		})
		HashSet<Long> existingTagIds = new HashSet<>(tagIdsForContactId(contactId))
		Set<Long> overlappingTagIds = existingTagIds.intersect(targetTagIds)
		Collection<Long> tagIdsToAdd = targetTagIds - overlappingTagIds
		// execute insert
		sql.withBatch("""
			INSERT INTO contact_tag_contact (contact_tag_members_id, contact_id)
			VALUES (?, ?)
		""") { BatchingPreparedStatementWrapper ps ->
			tagIdsToAdd.each { Long tagId -> ps.addBatch(tagId, contactId) }
		}.toList()
	}
	// remove existing contact from tags specified BY ID
	void removeFromTagsByIds(long contactId, Collection<Long> tagIds) {
		if (!tagIds) { return }
		sql.execute ("""
			DELETE FROM contact_tag_contact
			WHERE contact_id = ?
			AND contact_tag_members_id IN (?)
		""", [contactId, tagIds]*.asType(Object))
	}
	// create a new record, returning its id
	long createNewRecord() {
		sql.executeInsert("""
			INSERT INTO record (version, last_record_activity)
			VALUES (?, ?)
		""", [1, "2016-08-08 00:00:00"]*.asType(Object))[0][0] as Long
	}
}
