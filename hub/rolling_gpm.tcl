proc rolling_gpm {db_connection table_name time_column flow_column lookback window frequency points} {
    # Convert time parameters to seconds
    set lookback [expr { int([seconds $lookback]) }]
    set window [expr { int([seconds $window]) }]
    set frequency [expr { int([seconds $frequency]) }]

    set lookback [expr { $lookback - $lookback % $frequency }]
    set lookback [expr { $lookback + $window }]

    set start [expr { [clock seconds] - $lookback }]

    # Query the database for data
    set query "SELECT $time_column, $flow_column FROM $table_name WHERE $time_column >= :start ORDER BY $time_column"
    set statement [$db_connection prepare $query]
    set results [$statement execute]

    set data [$results allrows -as dicts]
    $results close
    $statement close

    set output {}
    set window_data {}
    set last_output_time 0
    set window_start_index 0
    set window_flow_sum 0
    set window_time_sum 0

    set total_seconds 0

    for {set i 1} {$i < [llength $data]} {incr i} {
        set row [lindex $data $i]
        set current_time [dict get $row $time_column]
        set current_flow [dict get $row $flow_column]

        # Add current data to the window sums
        set prev_row [lindex $data [expr {$i - 1}]]
        set prev_time [dict get $prev_row $time_column]
        set prev_flow [dict get $prev_row $flow_column]
        set interval_seconds [expr { int($current_time - $prev_time) }]
        set avg_flow [expr {($prev_flow + $current_flow) / 2.0}]
        set interval_gallons [expr {$avg_flow * $interval_seconds / 60.0}]
        set window_flow_sum [expr {$window_flow_sum + $interval_gallons}]
        set window_time_sum [expr {$window_time_sum + $interval_seconds}]
        incr total_seconds $interval_seconds

        # Remove old data from the window
        while {$window_start_index < $i && 
               [dict get [lindex $data $window_start_index] $time_column] < $current_time - $window} {
            if {$window_start_index + 1 < [llength $data]} {
                set exit_row [lindex $data $window_start_index]
                set next_row [lindex $data [expr {$window_start_index + 1}]]
                set exit_time [dict get $exit_row $time_column]
                set exit_flow [dict get $exit_row $flow_column]
                set next_time [dict get $next_row $time_column]
                set next_flow [dict get $next_row $flow_column]
                set exit_interval_seconds [expr {$next_time - $exit_time}]
                set exit_avg_flow [expr {($exit_flow + $next_flow) / 2.0}]
                set exit_interval_gallons [expr {$exit_avg_flow * $exit_interval_seconds / 60.0}]
                set window_flow_sum [expr {$window_flow_sum - $exit_interval_gallons}]
                set window_time_sum [expr {$window_time_sum - $exit_interval_seconds}]
            }
            incr window_start_index
        }

        # Calculate GPM if we have at least two points in the window
        set npoints [expr { $i - $window_start_index }]
        if { ($i > $window_start_index && $total_seconds >= $window && $npoints >= $points ) || $i == [llength $data] - 1} {
            set gpm [expr {$window_flow_sum / ($window_time_sum / 60.0)}]

            # Output result if it's time
            set output_seconds [expr { $current_time - $last_output_time }]
            if {$output_seconds >= $frequency || $i == [llength $data] - 1} {
                lappend output [list $current_time $gpm $output_seconds $window_time_sum $npoints]
                set last_output_time $current_time 
            }
        }
    }

    return $output
}

proc main {argv} {

    set HOME $::env(HOME)
    ::tcl::tm::path add $HOME/lib/tcl8/site-tcl


    package require tdbc::sqlite3
    package require jbr::print
    package require jbr::seconds
    package require jbr::unix

    set config [cat ../share/config/waterplant.cfg]
    set zero [dict get $config flow zero]
    set scale [dict get $config flow scale]

    if {[llength $argv] != 8} {
        puts "Usage: [info script] <db_file> <table_name> <time_column> <flow_column> <lookback_hours> <window_minutes> <frequency_minutes> <points>"
        exit 1
    }

    lassign $argv db_file table_name time_column flow_column lookback window frequency points

    # Validate numeric inputs
    foreach {param value} [list lookback $lookback window $window frequency $frequency points $points] {
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
        set results [rolling_gpm db $table_name $time_column $flow_column $lookback $window $frequency $points]
    } err]} {
        puts "Error calculating rolling GPM: $err"
        puts $::errorInfo
        db close
        exit 1
    }

    # Print results as a Starbase ASCII data table
    puts "Rolling GPM"
    puts ""
    puts "This table contains rolling GPM calculations"
    puts ""
    puts "db_file\t$db_file"
    puts "table_name\t$table_name"
    puts "time_column\t$time_column"
    puts "flow_column\t$flow_column"
    puts "lookback_hours\t$lookback"
    puts "window_minutes\t$window"
    puts "frequency_minutes\t$frequency"
    puts "data_points\t$points"
    puts ""
    puts "date\ttimestamp\tgpm\toutput\twindow\tpoints"
    puts "----------\t---------\t---\t-----\t-------\t-----"
    foreach row $results {
        lassign $row timestamp gpm output_seconds window_seconds points
        puts "[clock format $timestamp]\t$timestamp\t[format %.2f [expr { ($gpm-$zero)*$scale }]]\t$output_seconds\t$window_seconds\t$points"
    }

    # Close database connection
    db close
}

# Check if the script is being run directly
if {[info script] eq $::argv0} {
    main $::argv
}
