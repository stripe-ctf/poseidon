#include "ruby.h"
#include <errno.h>
#include <sys/types.h>
#include <unistd.h>

static VALUE Intern_fileno;
static VALUE Intern_new;
static VALUE Identity;

VALUE method_get_identity(VALUE self, VALUE conn) {
  VALUE fileno = rb_funcall(conn, Intern_fileno, 0);
  int fd = NUM2INT(fileno);

  uid_t euid;
  gid_t egid;
  // Darwin-only
  if (getpeereid(fd, &euid, &egid) < 0) {
    VALUE error = rb_funcall(rb_eSystemCallError, Intern_new, 1, INT2NUM(errno));
    rb_exc_raise(error);
  }

  return rb_funcall(Identity, Intern_new, 2, INT2NUM(euid), INT2NUM(egid));
}

void Init_poseidon_ext() {
  Intern_fileno = rb_intern("fileno");
  Intern_new = rb_intern("new");

  VALUE PoseidonClass = rb_define_class("Poseidon", rb_cObject);
  VALUE PoseidonExt = rb_define_module_under(PoseidonClass, "Ext");

  VALUE Struct = rb_const_get(rb_cObject, rb_intern("Struct"));
  Identity = rb_funcall(Struct, Intern_new, 2, ID2SYM(rb_intern("uid")), ID2SYM(rb_intern("gid")));
  rb_define_const(PoseidonExt, "Identity", Identity);
  rb_define_singleton_method(PoseidonExt, "get_identity", method_get_identity, 1);
}
