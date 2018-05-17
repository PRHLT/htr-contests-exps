CC        =   gcc

#CFLAGS    =  -m32
#STATIC    =  -static #-L/usr/lib/x86_64-linux-gnu/
#GPROF     =  -pg
#DEBUG     =  -g $(GPROF)
LIBS      =  
INC	  =  
OPTIONS   =  -Wall -O4 -ansi
DOPTIONS  =  -Wall
LDFLAGS   =  -lm $(STATIC)

ifndef DEBUG
export CFLAGS = $(OPTIONS) $(INC)
else
export CFLAGS = $(DOPTIONS) $(DEBUG) $(INC)
endif

all: align-GTvsHYP

% :: %.c
	$(CC) $(CFLAGS) $< -o $@ $(LIBS) $(LDFLAGS)
ifndef DEBUG
	strip $@
endif

clean:
	@-rm -f *.o *~ gmon.out $(BINARIES)

pack:	$(addsuffix .c, $(BINARIES)) Makefile README Test
	@cd ../; tar --atime-preserve --exclude-vcs -cvjhf AlignMentTools.tar.bz2 $(addprefix $(notdir $(PWD))/, $^)

### Para Optimizar tiempos de ejecución
########################################################
# gprof --flat-profile <BINARY> gmon.out | less   #
########################################################

# Determinacion de dependencias
# g++ -Wall -O3 -MM -c <SRCFILE>.c
