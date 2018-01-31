#!/bin/bash
set -e;
export LC_NUMERIC=C;
export LUA_PATH="$(pwd)/../../?/init.lua;$(pwd)/../../?.lua;$LUA_PATH";
export PATH=$PATH:$(pwd)/bin

batch_size=3;
height=96;
overwrite=false;

# Directory where the run.sh script is placed.
SDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)";
[ "$(pwd)" != "$SDIR" ] && \
  echo "Please, run this script from the experiment top directory!" && \
  exit 1;

# Check the tools
for tool in page_format_generate_contour; do
  which "$tool" > /dev/null || \
    (echo "Required tool $tool was not found!" >&2 && exit 1);
done;


#Extract corpus
mkdir -p data;
mv Train-A.tbz2 data/

[ -d data/corpus ] || \
  mkdir data/corpus && bunzip2 data/Train-A.tbz2 && tar -xf data/Train-A.tar -C data/corpus;

#Extract lines and preproces them
[ -d data/corpus/Train-A/page ] || \
  mkdir data/corpus/Train-A/page  && cp data/corpus/Train-A/*xml data/corpus/Train-A/page;

ln -s $(pwd)/data/corpus/Train-A/*jpg data/corpus/Train-A/page

for f in data/corpus/Train-A/page/*xml; do 
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


[ -d LINES ] || mkdir LINES/


export htrsh_valschema="no"

for i in data/corpus/Train-A/page/*xml
do
  N=`basename $i .xml`
  textFeats --cfg <( echo "$textFeats_cfg" ) --outdir LINES/ $i
done

mkdir TEXT
for i in data/corpus/Train-A/page/*xml
do
  N=`basename $i .xml`;
  htrsh_pagexml_textequiv $i -f tab > TEXT/$N.tab;
done


mkdir PARTITIONS
cd LINES
ls -1  | sed 's/\.png//' > ../PARTITIONS/train-lst
cd ..

# For cleaning the text
cd TEXT/
for i in *tab
do
  sed 's/\&amp;/ \& /g' $i | awk '{printf("%s ",$1); for (i=2; i<=NF; i++) printf(" %s",$i);printf("\n");}' > kk
  mv kk $i
done

# Preparing data
cd TEXT
cat *tab | awk '{printf("%s\n",$1)}' | sort > index
cat *tab > index.words
cd ../LINES
ls -1 | sed 's/\.png//g' |sort > index
cd ../PARTITIONS/
sdiff ../LINES/index ../TEXT/index | grep -v "<" | grep -v "<" | grep -v "|" | awk '{printf("%s\n",$1)}' > list

head -1103 list > tr.txt
head -1236 list | tail -133 > va.txt
cat list  | tail -143 > te.txt
cd ..

# Create data dir
mkdir -p htr/lang/char
cd htr/lang/char


for p in te tr va;
do
grep -f ../../../PARTITIONS/$p.txt ../../../TEXT/index.words | \
awk '{
  printf("%s", $1);
  for(i=2;i<=NF;++i) {
    for(j=1;j<=length($i);++j)
      printf(" %s", substr($i, j, 1));
    if (i < NF) printf(" <space>");
  }
  printf("\n");
}' | sed 's/"/'\'' '\''/g;s/#/<stroke>/g' > char.$p.txt
done

for p in tr va; do cat char.$p.txt | cut -f 2- -d\  | tr \  \\n; done | sort -u -V | awk 'BEGIN{
  N=0;
  printf("%-12s %d\n", "<eps>", N++);
  printf("%-12s %d\n", "<ctc>", N++);
}NF==1{
  printf("%-12s %d\n", $1, N++);
}' >  symb.txt

cd ../../ 
mkdir models
cd models


NSYMBOLS=$(sed -n '${ s|.* ||; p; }' "../lang/char/symb.txt");
  # Create model
laia-create-model \
      --cnn_batch_norm true \
      --cnn_kernel_size 3 \
      --cnn_maxpool_size 2,2 2,2 0 2,2 \
      --cnn_num_features 16 16 32 32 \
      --cnn_type leakyrelu \
      --rnn_type blstm --rnn_num_layers 3 \
      --rnn_num_units 256 \
      3 64  "$NSYMBOLS" train.t7 \
      &> init.log;

cd ..
ln -s ../LINES/ data
sed 's/^/data\//g' ../PARTITIONS/tr.txt  | sed 's/$/.png/g'  > tr.lst
sed 's/^/data\//g' ../PARTITIONS/va.txt  | sed 's/$/.png/g'  > va.lst

laia-train-ctc \ 
	--use_distortions true \
        --batch_size 3 \
        --progress_table_output train.dat \ 
        --early_stop_epochs 50 \
        --learning_rate 0.0005 \
        --log_level info \
        --log_file train.log \
        models/train.t7 lang/char/symb.txt tr.lst lang/char/char.tr.txt va.lst lang/char/char.va.txt 





mkdir -p decode/{char,word};
cd decode
sed 's/^/data\//g' ../../PARTITIONS/te.txt  | sed 's/$/.png/g'  > te.lst
ln -s ../../LINES/ data


# Get char-level transcript hypotheses
laia-decode --batch_size 3  --symbols_table ../lang/char/symb.txt ../models/train.t7 te.lst > char/test.txt 


# Get word-level transcript hypotheses
awk '{
  printf("%s ", $1);
  for (i=2;i<=NF;++i) {
    if ($i == "<space>")
      printf(" ");
    else
      printf("%s", $i);
  }
  printf("\n");
}' char/test.txt > word/test.txt;





# Incluir en los ficheros PAGE
 cd word
 cp -r  ../../../data/corpus/Train-A/page .
 mkdir newpage
 for f in page/*; do echo $f; done > DECODE_LIST
  
 awk '{page=$1; gsub("\\..*","",page); gsub(page"\\.","",$1);  print $0 >> page".txt" }' test.txt 

 for f in $(<DECODE_LIST); do 
     nn=`basename ${f/xml/txt}`;
    awk -v p=$nn 'BEGIN{while(getline < p) {line=$1; $1=""; l[line]=$0}}{if($0~"<TextLine id="){ line=$2; gsub("id=\"","",line); gsub("\".*","",line);print $0}else if($0~"Unicode"){print "                                <Unicode>"l[line]"</Unicode>"} else print $0;}' $f > newpage/${nn/txt/xml};
 done
 cd newpage
 ln -s ../page/*jpg .
 cd ..
 rm 00*txt

#Calcular el error
 ../../../scripts/Create_WER-PAGE.sh newpage/ page/


