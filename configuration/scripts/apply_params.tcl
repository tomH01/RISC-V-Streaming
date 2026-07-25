set bottle_dir "/local/hageltom/teda/bottles/risc-v-streaming"
set params_file [file join $bottle_dir "configuration" "params.tcl"]

set allowed_params [list \
    N_STREAMS \
    M_MACROS \
    DATA_WIDTH \
    ADDR_WIDTH \
    W_WORKERS \
    B_BANKS \
    MACRO_DEPTH \
    BANK_DEPTH \
    STREAM_OFFSET_WIDTH \
]

if {![file exists $params_file]} {
    error "Parameter file $params_file does not exist!"
}

puts "Loading parameters from $params_file"
source $params_file

if {![info exists ::params]} {
    error "\$::params is not defined in $params_file"
}

set vivado_generics {}

dict for {param value} $::params {
    if {$param in $allowed_params} {
        lappend vivado_generics "${param}=${value}"
        puts "Applying generic: ${param}=${value}"
    }
}

set_property generic $vivado_generics [current_fileset]

puts "Generics set to:"
puts [get_property generic [current_fileset]]