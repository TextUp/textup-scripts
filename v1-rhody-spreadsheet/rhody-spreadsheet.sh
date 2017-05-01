#!/bin/bash
#
# Convenience script for import data from spreadsheet csv into v2 database

phone_id=$1
db_username=$2

groovy script.groovy "All Markets" ${phone_id} data.csv "jdbc:mysql://localhost/prodDb?useUnicode=true" ${db_username}
