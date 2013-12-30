require 'mkmf'

$CFLAGS += ' ' unless $CFLAGS.empty?
$CFLAGS += '-D_GNU_SOURCE'

extension_name = 'poseidon_ext'
dir_config(extension_name)
create_makefile(extension_name)
