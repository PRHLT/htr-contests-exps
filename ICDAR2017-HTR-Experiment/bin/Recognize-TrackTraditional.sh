#!/bin/bash
set -e;
export LC_NUMERIC=C;
export LUA_PATH="$(pwd)/../../?/init.lua;$(pwd)/../../?.lua;$LUA_PATH";
export PATH=$PATH:$(pwd)/bin

batch_size=16;
height=96;
overwrite=false;

mkdir TraditionalTrack
mkdir Test-A

ln -s $(pwd)/data/Test-A/*jpg
ln -s $(pwd)/data/Test-A/page/*xml .

for f in *xml; do 
page_format_generate_contour -a 75 -d 25 -p $f -o $f ; 
done

textFeats_cfg='
TextFeatExtractor: {
  type            = "raw";
  format          = "img";
  fpgram          = true;
  fcontour        = true;
  fcontour_dilate = 0;
  padding         = 12;
  normheight      = 64;
  momentnorm      = true;
  enh_win         = 30;
  enh_prm         = [ 0.1, 0.2, 0.4 ];
}';

cd ..
[ -d LINES ] || mkdir LINES/


export htrsh_valschema="no"

for i in Test-A/*xml
do
  N=`basename $i .xml`
  textFeats --cfg <( echo "$textFeats_cfg" ) --outdir LINES/ $i
done

cd LINES
ls -1 | sed 's/\.png//g' |sort > index


mkdir PARTITIONS
cd PARTITIONS
cat  ../LINES/index  | awk '{printf("%s\n",$1)}' > test.lst


sed 's/^/data\//g' -i test.lst
sed 's/$/.png/g' -i test.lst
cd ..

mkdir decode
cd decode
ln -s ../LINES/ data
laia-decode --batch_size 3 --symbols_table ../../lang-AB/char/symb.txt ../../models-AB/train.t7 ../PARTITIONS/test.lst > test.txt


# Obtaining confMats
laia-netout --batch_size "3" --batcher_cache_gpu 1  --log_level info --log_also_to_stderr info --output_format matrix  --prior ../../models-AB/priors.txt --prior_alpha 0.3 ../../models-AB/train.t7 ../PARTITIONS/test.lst confMats_ark.txt

awk 'NR>1{print $1}' ../../lang-AB/char/symb.txt > chars.lst


#Processing development feature samples into Kaldi format
mkdir -p test

copy-matrix "ark,t:confMats_ark.txt" "ark,scp:test/confMats_alp0.3.ark,test/confMats_alp0.3.scp"

ASF=1.33984344; WIP=-1.10681197

decode-faster-mapped --verbose=2 --allow-partial=true --acoustic-scale=${ASF} --max-active=${MAX_NUM_ACT_STATES} --beam=${BEAM_SEARCH} ../../models-AB/HMMs/train/new.mdl ../../models-AB/HMMs/test/graph/HCLG.fst scp:test/confMats_alp0.3.scp  ark,t:RES 2>LOG

int2sym.pl -f 2- ../../models-AB/HMMs/test/graph/words.txt RES > hypotheses_t


mkdir word-lm

awk '{
  printf("%s ", $1);
  for (i=2;i<=NF;++i) {
    if ($i == "<space>")
      printf(" ");
    else
      printf("%s", $i);
  }
  printf("\n");
}' hypotheses_t > word-lm/hyp_word.txt

cd word-lm
cp -r ../../Test-A/ .
mkdir newpage
for f in *.xml; do echo $f; done > DECODE_LIST

awk '{page=$1; gsub("\\..*","",page); gsub(page"\\.","",$1);  print $0 >> page".txt" }' hyp_word.txt

for f in $(<DECODE_LIST); do
   nn=`basename ${f/xml/txt}`;
   awk -v p=$nn 'BEGIN{while(getline < p) {line=$1; $1=""; l[line]=$0}}{if($0~"<TextLine id="){ line=$2; gsub("id=\"","",line); gsub("\".*","",line);print $0}else if($0~"<Baseline"){print $0;print "        <TextEquiv>"; print "                   <Unicode>"l[line]"</Unicode>"; print "         </TextEquiv>"} else print $0;}' $f > newpage/${nn/txt/xml};
done
cd newpage
ln -s ../*jpg .
cd ..
rm 0*txt

