#!/usr/bin/env groovy

// step 1: gather args
boolean paramsHasError = false
String bucketName
Boolean doActualRun
if (this.args.size() > 0) {
    bucketName = this.args[0]
    doActualRun = this.args.size() < 2 ? false : this.args[1].toBoolean()
}
else {
    System.err.println("Must specify a S3 bucket name to flatten")
    paramsHasError = true
}
if (paramsHasError) {
    System.err.println """
        USAGE: <path-to-script> <0> <1>
        0 = name of s3 bucket
        1 = (optional) `true` for actual run, `false` for dryrun; default is `false`

        EXAMPLE: ./flatten-s3-hierarchy.groovy dev-media-textup-org
    """
    System.exit(1)
}
// step 2: list assets in provided bucket and find ones that require flattening
String result = "aws s3 ls s3://${bucketName}".execute().text
def m =  result =~ /(note-\d+)/
int numToFlatten = m.size()
// step 3: iterate through all unique prefixes found and rename without prefix
// because we have mandatory sse, we need to enable it too for copying: https://serverfault.com/a/874370
String commandBase = "aws s3 cp --sse AES256 --recursive" + " " + (doActualRun ? "" : "--dryrun")
println "Number of found folders to flatten is: ${numToFlatten}"
m.eachWithIndex { obj, index ->
    String matched = obj[0]
    String toExecute = "${commandBase} s3://${bucketName}/${matched}/ s3://${bucketName}/"
    println "******** Working on ${index + 1} of ${numToFlatten} --> ${matched} ********"
    println toExecute
    println toExecute.execute().text
}
