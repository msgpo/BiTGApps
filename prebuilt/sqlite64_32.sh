#!/system/bin/sh
#
##############################################################
# File name       : sqlite64_32.sh
#
# Description     : Database optimization using sqlite tool
#
# Build Date      : Tuesday March 03 20:05:36 IST 2020
#
# BiTGApps Author : TheHitMan @ xda-developers
#
# Copyright       : Copyright (C) 2020 TheHitMan7 (Kartik Verma)
#
# License         : SPDX-License-Identifier: GPL-3.0-or-later
##############################################################
# The BiTGApps scripts are free software: you can redistribute it
# and/or modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation, either version 3 of
# the License, or (at your option) any later version.
#
# These scripts are distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
##############################################################
# This script is the part of android init script and executed
# after boot.
##############################################################
# Frequent inserts, updates, and deletes can cause the database
# file to become fragmented where data for a single table or index
# is scattered around the database file.
# Running VACUUM ensures that each table and index is largely stored
# contiguously within the database file. In some cases, VACUUM may
# also reduce the number of partially filled pages in the database,
# reducing the size of the database file further.
##############################################################

# Set sqlite defaults
SQLITE_LOG="/cache/sqlite.log";
SQLITE_TOOL="/system/bin/sqlite3";

# Delete log file
if [ -e $SQLITE_LOG ]; then
  rm $SQLITE_LOG;
fi;

# SQLite database vaccum
database_opt() {
  for i in `find /d* -iname "*.db"`; do
    # Running VACUUM
    $SQLITE_TOOL $i 'VACUUM;';
    resVac=$?
    if [ $resVac == 0 ]; then
      resVac="SUCCESS";
    else
      resVac="ERRCODE-$resVac";
    fi;
    # Running INDEX
    $SQLITE_TOOL $i 'REINDEX;';
    resIndex=$?
    if [ $resIndex == 0 ]; then
      resIndex="SUCCESS";
    else
      resIndex="ERRCODE-$resIndex";
    fi;
    echo "Database $i:  VACUUM=$resVac  REINDEX=$resIndex" >> "$SQLITE_LOG";
  done
}
database_opt;

# end method