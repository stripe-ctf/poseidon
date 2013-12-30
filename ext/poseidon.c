#include "ruby.h"

VALUE method_test(VALUE self) {
  return Qnil;
}

void Init_poseidon_ext() {
  VALUE Poseidon = rb_define_class("Poseidon", rb_cObject);
  VALUE Ext = rb_define_module_under(Poseidon, "Ext");
  rb_define_singleton_method(Ext, "test", method_test, 0);
}
