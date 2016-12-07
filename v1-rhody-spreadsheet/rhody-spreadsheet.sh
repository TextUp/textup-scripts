#!/bin/bash
#
# Convenience script for import data from spreadsheet csv into v2 database

groovy script.groovy "All Markets" 6 data.csv "jdbc:mysql://localhost/prodDb?useUnicode=true" prod
