# Makefile for udev
#
# Copyright (C) 2003  Greg Kroah-Hartman <greg@kroah.com>
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; version 2 of the License.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
# General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA 02111-1307 USA
#

# Set the following to `true' to make a debuggable build.
# Leave this set to `false' for production use.
DEBUG = true


ROOT =		udev
VERSION =	003_bk
INSTALL_DIR =	/usr/local/bin
RELEASE_NAME =	$(ROOT)-$(VERSION)

# override this to make udev look in a different location for it's config files
prefix =
exec_prefix =	${prefix}
etcdir =	${prefix}/etc
sbindir =	${exec_prefix}/sbin
mandir =	${prefix}/usr/share/man
hotplugdir =	${etcdir}/hotplug.d/default
configdir =	${etcdir}/udev/
srcdir = .

INSTALL = /usr/bin/install -c
INSTALL_PROGRAM = ${INSTALL}
INSTALL_DATA  = ${INSTALL} -m 644
INSTALL_SCRIPT = ${INSTALL_PROGRAM}


# place to put our device nodes
udevdir = ${prefix}/udev/

# Comment out this line to build with something other 
# than the local version of klibc
#KLIBC = true

# If you are running a cross compiler, you may want to set this
# to something more interesting, like "arm-linux-".  I you want
# to compile vs uClibc, that can be done here as well.
CROSS = #/usr/i386-linux-uclibc/usr/bin/i386-uclibc-
CC = $(CROSS)gcc
AR = $(CROSS)ar
STRIP = $(CROSS)strip
RANLIB = $(CROSS)ranlib

export CROSS CC AR STRIP RANLIB

# code taken from uClibc to determine the current arch
ARCH := ${shell $(CC) -dumpmachine | sed -e s'/-.*//' -e 's/i.86/i386/' -e 's/sparc.*/sparc/' \
	-e 's/arm.*/arm/g' -e 's/m68k.*/m68k/' -e 's/ppc/powerpc/g'}

# code taken from uClibc to determine the gcc include dir
GCCINCDIR := ${shell $(CC) -print-search-dirs | sed -ne "s/install: \(.*\)/\1include/gp"}

# code taken from uClibc to determine the libgcc.a filename
GCC_LIB := $(shell $(CC) -print-libgcc-file-name )

# use '-Os' optimization if available, else use -O2
OPTIMIZATION := ${shell if $(CC) -Os -S -o /dev/null -xc /dev/null >/dev/null 2>&1; \
		then echo "-Os"; else echo "-O2" ; fi}

WARNINGS := -Wall -Wshadow -Wstrict-prototypes 

# Some nice architecture specific optimizations
ifeq ($(strip $(TARGET_ARCH)),arm)
	OPTIMIZATION+=-fstrict-aliasing
endif
ifeq ($(strip $(TARGET_ARCH)),i386)
	OPTIMIZATION+=-march=i386
	OPTIMIZATION += ${shell if $(CC) -mpreferred-stack-boundary=2 -S -o /dev/null -xc \
		/dev/null >/dev/null 2>&1; then echo "-mpreferred-stack-boundary=2"; fi}
	OPTIMIZATION += ${shell if $(CC) -malign-functions=0 -malign-jumps=0 -S -o /dev/null -xc \
		/dev/null >/dev/null 2>&1; then echo "-malign-functions=0 -malign-jumps=0"; fi}
	CFLAGS+=-pipe
else
	CFLAGS+=-pipe
endif

# if DEBUG is enabled, then we do not strip or optimize
ifeq ($(strip $(DEBUG)),true)
	CFLAGS  += $(WARNINGS) -O1 -g -DDEBUG -D_GNU_SOURCE
	LDFLAGS += -Wl,-warn-common
	STRIPCMD = /bin/true -Since_we_are_debugging
else
	CFLAGS  += $(WARNINGS) $(OPTIMIZATION) -fomit-frame-pointer -D_GNU_SOURCE
	LDFLAGS += -s -Wl,-warn-common
	STRIPCMD = $(STRIP) -s --remove-section=.note --remove-section=.comment
endif

# If we are using our version of klibc, then we need to build and link it.
# Otherwise, use glibc and link statically.
ifeq ($(strip $(KLIBC)),true)
	KLIBC_DIR	= klibc
	INCLUDE_DIR	:= $(KLIBC_DIR)/include
	# arch specific objects
	ARCH_LIB_OBJS =	\
			$(KLIBC_DIR)/bin-$(ARCH)/start.o	\
			$(KLIBC_DIR)/bin-$(ARCH)/klibc.a

	LIB_OBJS =	$(GCC_LIB)

	LIBC =	$(ARCH_LIB_OBJS) $(LIB_OBJS)
	CFLAGS += -nostdinc -I$(INCLUDE_DIR) -I$(GCCINCDIR)
	LDFLAGS = --static --nostdlib -nostartfiles
else
	LIBC = 
	CFLAGS += -I$(GCCINCDIR)
	LIB_OBJS = -lc
	LDFLAGS = --static 
endif

LIB=libsysfs

all: $(LIBC) $(ROOT)

$(ARCH_LIB_OBJS) :
	$(MAKE) -C klibc

LIBSYSFS = libsysfs/libsysfs.a
TDB = tdb/tdb.o tdb/spinlock.o

OBJS =	udev.o		\
	udev-add.o	\
	udev-remove.o	\
	udevdb.o	\
	logging.o	\
	namedev.o	\
	$(TDB)

libsysfs/libsysfs.a:
	$(MAKE) -C libsysfs

tdb/tdb.o:
	$(MAKE) -C tdb

# header files automatically generated
GEN_HEADERS =	udev_version.h

# Rules on how to create the generated header files
udev_version.h:
	@echo \#define UDEV_VERSION	\"$(VERSION)\" > $@
	@echo \#define UDEV_CONFIG_DIR	\"$(configdir)\" >> $@
	@echo \#define UDEV_ROOT	\"$(udevdir)\" >> $@


$(ROOT): $(GEN_HEADERS) $(OBJS) $(LIBSYSFS) $(TDB)
	$(MAKE) -C libsysfs
	$(CC) $(LDFLAGS) -o $(ROOT) $(OBJS) -lsysfs $(LIB_OBJS) -L$(LIB) $(ARCH_LIB_OBJS)
	$(STRIPCMD) $(ROOT)

clean:
	-find . \( -not -type d \) -and \( -name '*~' -o -name '*.[oas]' \) -type f -print \
	 | xargs rm -f 
	-rm -f core $(ROOT) $(GEN_HEADERS)
	$(MAKE) -C klibc clean
	$(MAKE) -C libsysfs clean
	$(MAKE) -C tdb clean

DISTFILES = $(shell find . \( -not -name '.' \) -print | grep -v CVS | grep -v "\.tar\.gz" | grep -v "\/\." | grep -v releases | grep -v BitKeeper | grep -v SCCS | grep -v "\.tdb" | sort )
DISTDIR := $(RELEASE_NAME)
srcdir = .
release: $(DISTFILES) clean
#	@echo $(DISTFILES)
	@-rm -rf $(DISTDIR)
	@mkdir $(DISTDIR)
	@-chmod 777 $(DISTDIR)
	@for file in $(DISTFILES); do			\
		if test -d $$file; then			\
		  	mkdir $(DISTDIR)/$$file;	\
		else					\
			cp -p $$file $(DISTDIR)/$$file;	\
		fi;					\
	done
	@tar -c $(DISTDIR) | gzip -9 > $(RELEASE_NAME).tar.gz
	@rm -rf $(DISTDIR)
	@echo "Built $(RELEASE_NAME).tar.gz"


install: all
	$(INSTALL) -d $(udevdir)
	$(INSTALL) -d $(configdir)
	$(INSTALL) -d $(hotplugdir)
	$(INSTALL_PROGRAM) -D $(ROOT) $(sbindir)/$(ROOT)
	$(INSTALL_DATA) -D udev.8 $(mandir)/man8/udev.8
	$(INSTALL_DATA) namedev.config $(configdir)
	$(INSTALL_DATA) namedev.permissions $(configdir)
	- ln -s $(sbindir)/$(ROOT) $(hotplugdir)/udev.hotplug

uninstall:
	- rm $(hotplugdir)/udev.hotplug
	- rm $(configdir)/namedev.permissions
	- rm $(configdir)/namedev.config
	- rm $(mandir)/man8/udev.8
	- rm $(sbindir)/$(ROOT)
	- rmdir $(hotplugdir)
	- rmdir $(configdir)
	- rmdir $(udevdir)


