#/bin/bash

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
if [ $# -ne 3 ]; then
  echo "Usage: $NAME <Transcripts-Dir> <Hypotheses-Dir> <Output-Dir>" 1>&2
  exit 1
fi

DTXT=$1
DREC=$2
DOUT=$3

[ -d $DTXT ] || { echo "ERROR: Dir \"$DTXT\" does not exist "'!' 1>&2; exit 1; }
[ -d $DREC ] || { echo "ERROR: Dir \"$DREC\" does not exist "'!' 1>&2; exit 1; }

if [ -d $DOUT ]; then
  echo "WARNING: Dir \"$DOUT\" already exists "'!' 1>&2;
else
  mkdir -p $DOUT 2>/dev/null
fi

########################################################################
function filter
{
  cat $1 |
  sed -r "\
    s/\\\303\\\255/í/g; \
    s/\\\303\\\261/ñ/g; \
    s/\\\303\\\263/ó/g; \
    s/\\\303\\\272/ú/g; \
    s/\\\303\\\251/é/g; \
    s/\\\303\\\250/è/g; \
    s/\\\303\\\242/â/g; \
    s/\\\303\\\241/á/g; \
    s/\\\302\\\272/º/g; \
    s/\\\303\\\252/ê/g; \
    s/\\\303\\\247/ç/g; \
    s/\\\303\\\215/Í/g; \
    s/\\\303\\\223/Ó/g; \
    s/\\\303\\\274/ü/g; \
    s/\\\303\\\207/Ç/g; \
    s/\\\302\\\255/­/g; \
    s/\\\302\\\243/£/g; \
    s/\\\303\\\240/à/g; \
    s/\\\302\\\247/§/g; \
    s/\\\305\\\223/œ/g"
}



########################################################################

for f in $DTXT/*.txt; do
  F=$(basename $f .txt);
#  {
#    echo "#ID-Ln   $   Rec-Hyp-String"
#    echo "##################################"
#  } > $DOUT/${F}_1hyp.inf;
  for l in $DREC/${F}*.rec; do
    L=$(basename $l .rec);
    ID=$(echo $L | cut -d "." -f 2 | sed "s/_/ /");
    echo -n "$ID \$ ";
    awk '{
           print $0 
	 }' $l;
  done |
  filter - >> $DOUT/${F}_1hyp.inf;
done

