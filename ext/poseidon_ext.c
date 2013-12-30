#include "ruby.h"
#include <errno.h>
#include <sys/types.h>
#include <unistd.h>

static VALUE Intern_fileno;
static VALUE Intern_new;
static VALUE Identity;

#ifndef __APPLE__
// TODO: Add more platform support?

#include <linux/socket.h>
#include <sys/socket.h>
int getpeereid(int s, uid_t *euid, gid_t *egid)
{
  struct ucred cred;
  socklen_t len = sizeof(cred);

  if (getsockopt(s, SOL_SOCKET, SO_PEERCRED, &cred, &len) < 0)
    return -1;
  *euid = cred.uid;
  *egid = cred.gid;

  return 0;
}
#endif

VALUE method_get_identity(VALUE self, VALUE conn) {
  VALUE fileno = rb_funcall(conn, Intern_fileno, 0);
  int s = NUM2INT(fileno);

  uid_t euid;
  gid_t egid;

  if (getpeereid(s, &euid, &egid) < 0) {
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
