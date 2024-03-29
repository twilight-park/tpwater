package require jbr::func
package require jbr::set

proc sql { db sql } {
    set stmt [db prepare $sql]
    uplevel [list $stmt execute]
    $stmt close
}

proc migrate-create { db table schema } {
	log sql db "create table $table ( [join $schema ,] )"
	sql db "create table $table ( [join $schema ,] )"
}
proc migrate-table { db table schema } {
    intersect3 [dict keys [db columns $table]] [map l $schema { string tolower [lindex $l 0] }] inDB inSchema inBoth

    foreach column $inDB {
        log  sql db "alter table $table drop column $column"
        sql db "alter table $table drop column $column"
    }
    foreach column $inSchema {
        log  sql db "alter table $table add column [lsearch -inline -regex $schema $column]"
        sql db "alter table $table add column [lsearch -inline -regex $schema $column]"
    }
}

proc migrate-db { db schema } {
    intersect3 [dict keys [db tables]] [dict keys $schema] inDB inSchema inBoth

    foreach table $inDB {
        log  SCARY db drop $table
    }
    foreach table $inSchema {
        migrate-create db $table [dict get $schema $table]
    }
    foreach table $inBoth {
        migrate-table  db $table [dict get $schema $table]
    }

    # log  [join [db tables] \n]
}


