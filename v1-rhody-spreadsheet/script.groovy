import groovy.sql.Sql

/**
 * Script to read in entries in spreadsheet (formatted as a csv file)
 * as contacts and tags into the v2 database
 *
 * See RhodySpreadsheetHelpers for specification
 */

// Parameters
// ----------

String allMarketsTagName
long phoneId
String inputPath
String dbUrl
String dbUsername
String dbPassword // from password prompt
boolean paramsHasError = false

if (this.args.size() == 5) {
	allMarketsTagName = this.args[0]
	inputPath = this.args[2]
	dbUrl = this.args[3]
	dbUsername = this.args[4]
	if (this.args[1].isLong()) {
		phoneId = this.args[1].toLong()
	}
	else {
		System.err.println("Phone id must be a number")
		paramsHasError = true
	}
}
else { paramsHasError = true }

if (paramsHasError) {
	System.err.println """
		USAGE: groovy run-script <path-to-script> <0> <1> <2> <3> <4>
		0 = name of the all markets tag
		1 = id of the phone to add contacts and tags to
		2 = path to the input csv file
		3 = JDBC url for the database
		4 = database username
	"""
	System.exit(1)
}

Console console = System.console()
if (console == null) {
    println("Couldn't get Console instance")
    System.exit(0)
}
dbPassword = new String(console.readPassword("Database password: "))

// Load helpers
// ------------

String parentDir = new File(getClass().protectionDomain.codeSource.location.path).parent
String helpersFileName = "RhodySpreadsheetHelpers"
this.class.classLoader.parseClass(new File("${parentDir}/${helpersFileName}.groovy"))

// Start script
// ------------

Sql sql = Sql.newInstance(dbUrl, dbUsername, dbPassword)
File inputFile = new File(inputPath)
try {
	def helpers = Class.forName(helpersFileName).newInstance(sql:sql, phoneId:phoneId,
		allMarketsTagName:allMarketsTagName)

	reportStatus(sql, "BEFORE")

	sql.withTransaction { // start transaction
		// process input line by line, indexing lines from 0
		inputFile.eachLine(0) { String data, int lineNum ->
			if (lineNum > 0) {
				if (!helpers.processRow(helpers.extractRow(data))) {
					sql.rollback()
					System.err.println("Exited early with error.")
					System.exit(1)
				}
			}
		}
	}

	reportStatus(sql, "\nAFTER")
}
finally { sql.close() }

void reportStatus(Sql db, String prefix = null, String suffix = null) {
	if (prefix != null) { println prefix }
	println "# contacts: " + db.firstRow("SELECT COUNT(*) AS num FROM contact").num
	println "# contact numbers: " + db.firstRow("SELECT COUNT(*) AS num FROM contact_number").num
	println "# tags: " + db.firstRow("SELECT COUNT(*) AS num FROM contact_tag").num
	if (suffix != null) { println suffix }
}
