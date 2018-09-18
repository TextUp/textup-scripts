#!/usr/bin/env groovy

// step 1: gather args
String sid, auth, idsPath
if (this.args.size() >= 3) {
    sid = this.args[0]
    auth = this.args[1]
    idsPath = this.args[2]
}
else {
    System.err.println """
        USAGE: <path-to-script> <0> <1> <2>
        0 = twilio SID
        1 = twilio Auth Token
        2 = path to file with each line being `<recording id>,<call id>`
    """
    System.exit(1)
}
// step 2: read in the recording ids to fetch
List<String> idsList = []
new File(idsPath).eachLine { String id -> idsList << id }
println "Found ${idsList.size()} recording ids"
// step 3: fetch each recording id and save with call sid name in the working directory
String credentials = "${sid}:${auth}".bytes.encodeBase64().toString()
idsList.eachWithIndex { String idInfo, int index ->
    def (String recId, String callId) = idInfo.tokenize(",")
    println "Working on ${index + 1} for recording `${recId}` and call `${callId}`..."
    URLConnection connection = "https://api.twilio.com/2010-04-01/Accounts/${sid}/Recordings/${recId}.mp3"
        .toURL()
        .openConnection()
    connection.setRequestProperty("Authorization", "Basic ${credentials}")
    if (connection.responseCode == 200) {
        println "...success ${connection.responseCode}"
        connection.inputStream.withStream { InputStream istream ->
            new FileOutputStream(callId).withStream { OutputStream oStream ->
                oStream.write(istream.bytes)
            }
        }
    }
    else {
        println "...failed ${connection.responseCode}: ${connection.responseMessage}"
    }
}
