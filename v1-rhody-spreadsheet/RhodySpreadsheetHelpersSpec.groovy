import spock.lang.*

@Grab(group='org.spockframework', module='spock-core', version='1.0-groovy-2.4')
@Unroll
class RhodySpreadsheetHelpersSpec extends Specification {

	@Shared
	def script // instance of the script

	void setupSpec() {
		String parentDir = new File(getClass().protectionDomain.codeSource.location.path).parent
		String helpersFile = "RhodySpreadsheetHelpers"
		this.class.classLoader.parseClass(new File("${parentDir}/${helpersFile}.groovy"))
		script = Class.forName(helpersFile).newInstance()
	}

	void "test extracting and cleaning csv"() {
		when:
		def subscriber = script.extractRow(info)

		then:
		subscriber.name                  == name
		subscriber.email                 == email
		subscriber.phoneNumber           == phoneNumber
		subscriber.group                 == group
		subscriber.cities.size()         == numCities
		subscriber.preference.toString() == pref

		where:
		info                                                        || name  | email     | phoneNumber  | group | numCities | pref
		'E@E.com,A,B,G,,111-222-3333,'                              || "A B" | "E@E.com" | "1112223333" | "G"   | 0         | "NOT_SPECIFIED"
		'E@E.com,A,B,,"1, 2",1112223333,"Yes, for my town (below)"' || "A B" | "E@E.com" | "1112223333" | ""    | 2         | "ADD_TO_CITY"
		'E@E.com,A,B,,"1 2, 3, 4, 5 6",111-  222-3333,No'           || "A B" | "E@E.com" | "1112223333" | ""    | 4         | "REMOVE_FROM_ALL"
		'E@E.com,A,B,G,,111-222-3333,"Yes, for all markets!"'       || "A B" | "E@E.com" | "1112223333" | "G"   | 0         | "ADD_TO_ALL"
	}
}
