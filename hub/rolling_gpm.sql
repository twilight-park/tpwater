#!/usr/bin/env tclsh
# rolling_gpm.tcl

# Purpose:
# This script calculates rolling Gallons Per Minute (GPM) from time-series flow rate data
# stored in a SQLite database. It provides a flexible way to analyze water flow rates
# over specified time windows and at desired output frequencies.
#
# Usage:
# tclsh rolling_gpm.tcl <db_file> <table_name> <time_column> <flow_column> <lookback> <window> <frequency>
#
# Parameters:
# - db_file: Path to the SQLite database file.
# - table_name: Name of the table containing the flow rate data.
# - time_column: Name of the column containing timestamps.
# - flow_column: Name of the column containing flow rate values.
# - lookback_hours: Number of hours to look back from the current time.
# - window_minutes: Size of the rolling window in minutes.
# - frequency_minutes: Desired output frequency in minutes.
#
# Example:
# tclsh rolling_gpm.tcl ../tpwater.db waterplant time_recorded flow 24 10 1
#
# Note: This script currently performs calculations using SQL queries.
# A future version will implement the computation in Tcl for improved efficiency.

package require tdbc::sqlite3

package require jbr::print
package require jbr::seconds

proc calculate_rolling_gpm {db_connection table_name time_column flow_column lookback window frequency} {
    # Convert time parameters to seconds
    set lookback [expr { int([seconds $lookback]) }]
    set window [expr { int([seconds $window]) }]
    set frequency [expr { int([seconds $frequency]) }]

    set start [expr { [clock seconds] - $lookback }]
    print $lookback $window $frequency : $start [clock seconds]

    # Construct the SQL query using subst for table and column names, and TDBC's parameterized query syntax for other values
    set query [subst {
        WITH base_data AS (
            SELECT
                $time_column as time_recorded,
                $flow_column as flow_rate,
                LEAD($time_column) OVER (ORDER BY $time_column) AS next_time_recorded,
                LEAD($flow_column) OVER (ORDER BY $time_column) AS next_flow_rate
            FROM $table_name
            WHERE $time_column >= :start
        ),
        interval_calculations AS (
            SELECT
                time_recorded,
                (flow_rate + next_flow_rate) / 2 *
                (next_time_recorded - time_recorded) / 60.0 AS interval_gallons,
                next_time_recorded - time_recorded AS interval_duration
            FROM base_data
            WHERE next_time_recorded IS NOT NULL
        ),
        windowed_calculations AS (
            SELECT
                ic1.time_recorded,
                ic1.interval_gallons,
                ic1.interval_duration,
                (
                    SELECT SUM(ic2.interval_gallons)
                    FROM interval_calculations ic2
                    WHERE ic2.time_recorded > ic1.time_recorded - :window
                      AND ic2.time_recorded <= ic1.time_recorded
                ) AS window_gallons,
                (
                    SELECT SUM(ic2.interval_duration)
                    FROM interval_calculations ic2
                    WHERE ic2.time_recorded > ic1.time_recorded - :window
                      AND ic2.time_recorded <= ic1.time_recorded
                ) AS window_seconds
            FROM interval_calculations ic1
        ),
        results_with_groups AS (
            SELECT
                time_recorded,
                CASE
                    WHEN window_seconds > 0
                    THEN window_gallons / (window_seconds / 60.0)
                    ELSE NULL
                END AS gpm,
                (time_recorded - :start) / :frequency AS group_number
            FROM windowed_calculations
            WHERE time_recorded >= :start
        )
        SELECT time_recorded, gpm
        FROM (
            SELECT *,
                   ROW_NUMBER() OVER (PARTITION BY group_number ORDER BY time_recorded DESC) AS row_within_group
            FROM results_with_groups
        )
        WHERE row_within_group = 1
        ORDER BY time_recorded
    }]

    # Prepare and execute the query
    set statement [$db_connection prepare $query]
    set results [$statement execute]

    # Fetch the results
    set output [$results allrows -as dicts]

    $results close
    $statement close

    return $output
}

proc main {argv} {
    if {[llength $argv] != 7} {
        puts "Usage: [info script] <db_file> <table_name> <time_column> <flow_column> <lookback_hours> <window_minutes> <frequency_minutes>"
        exit 1
    }

    lassign $argv db_file table_name time_column flow_column lookback window frequency

    # Validate numeric inputs
    foreach {param value} [list "lookback" $lookback "window" $window "frequency" $frequency] {
        if {![string is double [seconds $value]]} {
            puts "Error: $param must be a number"
            exit 1
        }
    }

    # Open database connection
    if {[catch {tdbc::sqlite3::connection create db $db_file} err]} {
        puts "Error opening database: $err"
        exit 1
    }

    # Call the calculate_rolling_gpm procedure
    if {[catch {
        set results [calculate_rolling_gpm db $table_name $time_column $flow_column $lookback $window $frequency]
    } err]} {
        puts "Error calculating rolling GPM: $err"
        puts $::errorInfo
        db close
        exit 1
    }

    # Print results
    puts "Timestamp,GPM"
    foreach row $results {
        puts "[clock format [dict get $row time_recorded]]  $row"
    }

    # Close database connection
    db close
}

# Check if the script is being run directly
if {[info script] eq $::argv0} {
    main $::argv
}
