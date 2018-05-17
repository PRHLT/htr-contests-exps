#!/bin/bash  

#*****************************************************************************
# \author  Alejandro H. Toselli <ahector@iti.upv.es>
# \version 1.0
# \date    2014
#

# Copyright (C) 2014 by Pattern Recognition and Human Language
# Technology Group, Technological Institute of Computer Science,
# Valencia University of Technology, Valencia (Spain).

# Permission to use, copy, modify, and distribute this software and
# its documentation for any purpose and without fee is hereby
# granted, provided that the above copyright notice appear in all
# copies and that both that copyright notice and this permission
# notice appear in supporting documentation.  This software is
# provided "as is" without express or implied warranty.
#
#*****************************************************************************

NAME=${0##*/}
if [ $# -ne 2 ]; then
  echo "Usage: $NAME <Input-Dir> <Output-Dir>" 1>&2
  exit 1
fi

DORIG=$1
DDEST=$2

[ -d $DORIG ] || { echo "ERROR: Dir \"$DORIG\" does not exist "'!' 1>&2; exit 1; }
[ -d $DDEST ] && { echo "WARNING: Dir \"$DDEST\" already exists "'!' 1>&2; }
mkdir -p $DDEST 2>/dev/null

for f in $(find ${DORIG} -name *.xml); do

   n=`basename $f .xml`		
   
   cat $f |
   dos2unix |
   sed -rn "/<text>/,/<\/text>/p" |
   paste -s |
   sed -r "s/<del>|<\/del>//g; s/<hi[^>]*>|<\/hi>//g; s/<pageNum[^>]*>|<\/pageNum>//g; s/<unclear>|<\/unclear>//g" |
   sed -r "s/<sic>|<\/sic>//g; s/<foreign>|<\/foreign>//g; s/<sup>|<\/sup>//g" |
   sed -r "s/<note>/\n&/g; s/<\/note>/&\n/g" |
   sed -r "/^<note>/d" |
   paste -s |
   sed -r "s/<!--/\n&/g" | sed -r "s/-->/&\n/g" |
   sed -r "/^<!--/d" |
   paste -s |
   sed -r "s/<head>/\n/g; s/<\/head>/\n/g" |
   sed -r "s/<p>/\n/g; s/<\/p>/\n/g" |
   sed -r "s/<catchword>/\n/g; s/<\/catchword>/\n/g" |
   sed -r "s/<lb\/>/\n/g" |
   awk '{
          mflg=0; flg=0; delete CAD; L=length($0);
	  for (l=1;l<=L;l++) {
	    if (substr($0,l,5)=="<add>") {
	      addflg=1; l+=4; flg++;
	      if (mflg<flg) mflg=flg;
	      CAD[flg]=CAD[flg]" ";
	      continue;
	    }
	    if (substr($0,l,6)=="</add>") {printf" "; l+=5; flg--; continue; }
	    CAD[flg]=CAD[flg]""substr($0,l,1)
	  }
	  for (i=mflg;i>=0;i--) print CAD[i]
	}' |
   sed -r "s/<text>|<\/text>|<body>|<\/body>|<div>|<\/div>//g" |
   #sed -r "s/<gap\/>//g" |
   sed 's/\&\#x2014;/_/g'|
   sed -r "s/^[ \t]+//; s/[ \t]+$//; s/[ \t]+/ /g" |
   sed -r "/^[ \t]*$/d" |
   sed 's/\&amp;/\&/g' > ${DDEST}/$n.txt

done 

exit 0

# Replaced part for detecting <add> ... </add> tags
   awk '{
          addflg=0; flg=0; CAD=""; L=length($0);
          for (l=1;l<=L;l++) {
	    if (substr($0,l,5)=="<add>") {addflg=1; l+=4; flg=1; continue; }
	    if (substr($0,l,6)=="</add>") {printf" "; l+=5; flg=0; continue; }
	    if (flg) printf substr($0,l,1);
	    else CAD=CAD""substr($0,l,1);
	  }
	  if (addflg) CAD="\n"CAD; print CAD
        }' |

