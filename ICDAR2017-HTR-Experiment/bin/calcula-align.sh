#!/bin/bash
D=`pwd`
set -e

PROG=${0##*/}
if [ $# -ne 2 ]; then
  echo "Usage: $PROG alignments_file threshold" 1>&2
  exit 1
fi
FILE=$1
TRS=$2

sed -r 's/\( +/\(/g' ${FILE}  |
awk -v Tres=${TRS} '{                           if($1~"FILE:"){
       file=$2;
       gsub("HYP\/","",file);
       gsub("_1hyp.inf","",file);
    }
    if($0~"-->"){
      if($7>=Tres){
       if($1!~"<"){
          ref=file"_"$1".txt";
          if($4!~"<"){
             img=file"."$(NF-1)"_"$NF;
             print "cp",ref,img".tab";
          }
       }
    }
   }
 }'  > alineamiento_${TRS}.sh


