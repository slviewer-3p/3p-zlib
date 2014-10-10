
# Linden hand-generated makefile for minizip.lib on windows.
#
# As with the other makefile, it wouldn't be too hard getting
# this working under cmake or incorporating it in the special
# project files we actually use to do builds on windows.  This
# was just a quick way to get away from magic binary blobs
# found in colladadom distributions.

CFLAGS = /nologo /W3 /D_CRT_SECURE_NO_DEPRECATE /I. /I..\..\..\stage\include\zlib
LDFLAGS = /nologo
!ifdef DEBUG
CFLAGS = $(CFLAGS) /Od /Z7 /MDd
ZLIB_LIB = zlibd.lib
ZLIB_LIBPATH = ..\..\..\stage\lib\debug
!else
CFLAGS = $(CFLAGS) /Ot /MD
ZLIB_LIB = zlib.lib
ZLIB_LIBPATH = ..\..\..\stage\lib\release
!endif

TARGETS = \
		minizip.lib \
		minizip.exe \
		miniunz.exe

LIB_OBJS = \
		ioapi.obj \
		iowin32.obj \
		unzip.obj \
		zip.obj

.c.obj:
		$(CC) $(CFLAGS) /c $*.c

all: $(TARGETS)

clean:
		del /Q *.obj *.pdb *.exp $(TARGETS)

minizip.lib: $(LIB_OBJS)
!ifndef DLLBUILD
		lib /nologo /OUT:$@ $**
!else
		lib /nologo /NAME:$*.dll /DEF /OUT:$@ $**
!endif

minizip.exe: $*.c minizip.lib
		$(CC) $(CFLAGS) /DZLIB_WINAPI $*.c minizip.lib $(ZLIB_LIB) /link /LIBPATH:$(ZLIB_LIBPATH) 

miniunz.exe: $*.c minizip.lib
		$(CC) $(CFLAGS) /DZLIB_WINAPI $*.c minizip.lib $(ZLIB_LIB) /link /LIBPATH:$(ZLIB_LIBPATH) 


