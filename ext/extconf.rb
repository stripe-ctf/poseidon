require 'mkmf'
File.write('Makefile', <<EOF)
CC = gcc
all:
	$(CC) -o ../bin/poseidon-client poseidon-client.c
EOF
