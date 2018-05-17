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
  {
    echo "#ID-Ln   $   Rec-Hyp-String"
    echo "##################################"
  } > $DOUT/${F}_1hyp.inf;
  for l in $DREC/${F}*.rec; do
    L=$(basename $l .rec);
    ID=$(echo $L | cut -d "_" -f 6- | sed "s/_/ /");
    echo -n "$ID \$";
    awk '{
           if ($1=="." || $1=="///") exit;
           L=length($3);
	   if (substr($3,1,1)=="\x27" && "\x27"==substr($3,L,1)) $3=substr($3,2,L-2);
	   printf " "$3
	 }
	 END{print ""}' $l;
  done |
  filter - >> $DOUT/${F}_1hyp.inf;
done

# for n-bests
for f in $DTXT/*.txt; do
  F=$(basename $f .txt);
  {
    echo "#ID-Ln   $   LKH-1Ln   LKH-2Ln   LKH-3Ln   ...   LKH-NLn   #FRMs"
    echo "######################################################################"
  } > $DOUT/${F}_nbst.inf;
  for l in $DREC/${F}*.rec; do
    L=$(basename $l .rec);
    ID=$(echo $L | cut -d "_" -f 6- | sed "s/_/ /");
    echo -n "$ID \$";
    awk 'BEGIN{ sum=0.0 }
         {
	   if ($1=="///") {
	     print sum,nfr; sum=0;
	   } else {
	     sum+=$4; L=length($3);
	     if (substr($3,1,1)=="\x27" && "\x27"==substr($3,L,1)) $3=substr($3,2,L-2);
	     nfr=int($2/100000);
	     printf $3" "
	   }
	 }
	 END{ print sum,nfr }' $l |
    filter - |
    awk -v fl=$f 'BEGIN{ cnt=0; cnt2=0; while (getline < fl > 0) S[++cnt]=$0 }
                  {
		    scr[++cnt2]=$(NF-1);
		    time[cnt2]=$NF; NF=NF-2; L[cnt2]=$0
		  }
		  END{
		       ind=0;
		       for (i=1;i<=cnt;i++) {
		         flg=0;
		 	 for (j=1;j<=cnt2;j++)
			   if (S[i]==L[j]) { flg=1; ind=j; printf " "scr[j]; }
			 if (!flg) printf " -inf";
		       }
		       if (ind) print " "time[ind]; else print " "0
		     }';
  done >> $DOUT/${F}_nbst.inf;
done
