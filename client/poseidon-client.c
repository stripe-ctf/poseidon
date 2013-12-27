#include <stdio.h>
#include <stdlib.h>
#include <errno.h>
#include <stdio.h>
#include <string.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>

void read_errorfile() {
  char buf[1024];
  char *errorfile = getenv("POSEIDON_ERRORFILE");
  if (errorfile) {
    FILE *fr = fopen(errorfile, "r");
    if (fr) {
      while(fgets(buf, sizeof(buf), fr) != NULL) {
	fprintf(stderr, "%s", buf);
      }
      fclose(fr);
      fprintf(stderr, "\nError details:\n\n");
    }
  }
}

void handle_error(char *message)
{
  int err = errno;
  read_errorfile();
  errno = err;
  if (err) {
    perror(message);
  } else {
    printf("%s.\n", message);
  }
  exit(200);
}

void checked_send(int s, void *buffer, int length)
{
  if (send(s, buffer, length, 0) < 0) {
    handle_error("Could not write bytes");
  }
}

// Copied from http://code.swtch.com/plan9port/src/0e6ae8ed3276/src/lib9/sendfd.c
int checked_sendfd(int s, int fd)
{
  char buf[1];
  struct iovec iov;
  struct msghdr msg;
  struct cmsghdr *cmsg;
  int n;
  char cms[CMSG_SPACE(sizeof(int))];
  
  buf[0] = 0;
  iov.iov_base = buf;
  iov.iov_len = 1;

  memset(&msg, 0, sizeof msg);
  msg.msg_iov = &iov;
  msg.msg_iovlen = 1;
  msg.msg_control = (caddr_t)cms;
  msg.msg_controllen = CMSG_LEN(sizeof(int));

  cmsg = CMSG_FIRSTHDR(&msg);
  cmsg->cmsg_len = CMSG_LEN(sizeof(int));
  cmsg->cmsg_level = SOL_SOCKET;
  cmsg->cmsg_type = SCM_RIGHTS;
  memmove(CMSG_DATA(cmsg), &fd, sizeof(int));

  if((n=sendmsg(s, &msg, 0)) != iov.iov_len) {
    handle_error("Could not send file descriptors");
  }
  return 0;
}

void pack_int(unsigned char bytes[4], unsigned long n)
{
  bytes[0] = n & 0xFF;
  bytes[1] = (n >> 8) & 0xFF;
  bytes[2] = (n >> 16) & 0xFF;
  bytes[3] = (n >> 24) & 0xFF;
}

int unpack_int(unsigned char bytes[4])
{
  int output = 0;
  output += bytes[0];
  output += bytes[1] << 8;
  output += bytes[2] << 16;
  output += bytes[3] << 24;
  return output;
}

int main(int argc, char **argv)
{
  char *sock_path = getenv("POSEIDON_SOCK");
  if (!sock_path)
    sock_path = "/tmp/poseidon.sock";

  int s;
  if ((s = socket(AF_UNIX, SOCK_STREAM, 0)) < 0) {
    handle_error("Could not create socket");
  }

  struct sockaddr_un remote;
  remote.sun_family = AF_UNIX;
  strncpy(remote.sun_path, sock_path, sizeof(remote.sun_path)-1);
  if (connect(s, (struct sockaddr *) &remote, sizeof(remote)) < 0) {
    handle_error("Could not connect to UNIX socket for master process");
  }

  checked_sendfd(s, 0);
  checked_sendfd(s, 1);
  checked_sendfd(s, 2);

  unsigned char bytes[4];
  pack_int(bytes, argc - 1);
  // Write argument count
  checked_send(s, bytes, 4);

  for (int i = 1; i < argc; i++) {
    // Write all arguments (including null terminators)
    checked_send(s, argv[i], strlen(argv[i]) + 1);
  }

  int t, total = 0;
  unsigned char exitstatus[4];

  // Maybe should replace this janky buffering with fread or
  // something.
  while (total < 4) {
    // Handle errors as well as closed other ends
    if ((t = recv(s, exitstatus + total, 4 - total, 0)) < 0) {
      handle_error("Could not receive exitstatus from master");
    } else if (t == 0) {
      handle_error("Master hung up connection");
    }
    total += t;
  }

  close(s);

  return unpack_int(exitstatus);
}
