#!/bin/bash
set -e;
export LC_NUMERIC=C;
export LUA_PATH="$(pwd)/../../?/init.lua;$(pwd)/../../?.lua;$LUA_PATH";
export PATH=$PATH:$(pwd)/bin

batch_size=3;
height=96;
overwrite=false;

cd WORK


mkdir TEXT
cd TEXT
for f in ../Train-A/TEXT/*.tab; do
        awk '{for(i=2;i<=NF;i++) printf("%s ",$i) > $1".tab" ; printf("\n") > $1".tab" ;}' $f
done

ln -s ../Train-B/Alineamientos/TXT-0.7/*.tab .
ls -1 | sed 's/\.tab//g' | sort > index
cd ..

mkdir  LINES
cd LINES
ln -s ../Train-A/LINES/*.png .
ln -s ../Train-B/LINES/*.png .
ls -1 | sed 's/\.png//g' |sort > index
cd ..

cd PARTITIONS
sdiff ../LINES/index ../TEXT/index | grep -v "<" | grep -v "<" | grep -v "|" | awk '{printf("%s\n",$1)}' > list
head -85000 list > tr.lst
tail -1254 list > va.lst
sed 's/^/data\//g' -i tr.lst
sed 's/$/.png/g' -i tr.lst
sed 's/^/data\//g' -i va.lst
sed 's/$/.png/g' -i va.lst
cat tr.lst va.lst >> total.lst


cd ..

cd ..
# Create data dir
mkdir -p lang-AB/char
cd lang-AB/char

for p in tr va;
do
for f in $(<../../PARTITIONS/${p}.lst); do n=`basename $f`; cat ../../TEXT/${n/png/tab} | \
awk -v n=$n '{
  printf("%s", n);
  for(i=1;i<=NF;++i) {
    for(j=1;j<=length($i);++j)
      printf(" %s", substr($i, j, 1));
    if (i < NF) printf(" <space>");
  }
  printf("\n");
}' | sed 's/"/'\'' '\''/g;s/#/<stroke>/g' >> char.${p}.txt

done

cat char.train.txt >> char.total.txt
cat char.va.txt >> char.total.txt

for p in tr va; do cat char.${p}.txt | cut -f 2- -d\  | tr \  \\n; done | sort -u -V | awk 'BEGIN{
  N=0;
  printf("%-12s %d\n", "<eps>", N++);
  printf("%-12s %d\n", "<ctc>", N++);
}NF==1{
  printf("%-12s %d\n", $1, N++);
}' >  symb.txt



NSYMBOLS=$(sed -n '${ s|.* ||; p; }' "symb.txt");
cd ../../ 
mkdir models-AB
cd models-AB


NSYMBOLS=$(sed -n '${ s|.* ||; p; }' "../lang/char/symb.txt");
  # Create model
laia-create-model \
      --cnn_batch_norm true \
      --cnn_kernel_size 16 \
      --cnn_maxpool_size 2,2 2,2 0 2,2 \
      --cnn_num_features 16 32 64 96 \
      --cnn_type leakyrelu \
      --rnn_type blstm --rnn_num_layers 3 \
      --rnn_num_units 512 \
      3 64  "$NSYMBOLS" train.t7 \
      &> init.log;

ln -s ../LINES/ data
 #Train model
laia-train-ctc \ 
	--use_distortions true \
        --batch_size 16 \
        --progress_table_output train.dat \ 
        --early_stop_epochs 50 \
        --learning_rate 0.0005 \
        --log_level info \
        --log_file train.log \
       train.t7 ../lang-AB/char/symb.txt ../PARTITIONS/total.lst ../lang/char/char.total.txt ../PARTITIONS/val-A.lst ../lang-AB/char/char.va.txt 

#Include Languaje model

# Force alignment

laia-force-align --batch_size "16"  --batcher_cache_gpu 1  --log_level info  --log_also_to_stderr info   train.t7 ../lang-AB/char/symb.txt ../PARTITIONS/total.lst ../lang-AB/char/char.total.txt  align_output.txt priors.txt


# Prepare Kaldi's lang directories
# Preparing Lexic (L)
cd ../lang-AB
awk 'NR>1{print $1}' ./char/symb.txt > chars.lst
mkdir lm

BLANK_SYMB="<ctc>"                        # BLSTM non-character symbol
WHITESPACE_SYMB="<space>"                 # White space symbol
DUMMY_CHAR="<DUMMY>"                      # Especial HMM used for modelling "</s>" end-sentence

prepare_lang_cl-ds.sh lm chars.lst "${BLANK_SYMB}" "${WHITESPACE_SYMB}" "${DUMMY_CHAR}"

cd lm/

# Preparing LM (G)
cat ../char/char.total.txt | cut -d " " -f 2- | ngram-count -vocab ../chars.lst -text - -lm lang/LM.arpa -order 8 -wbdiscount1 -kndiscount -interpolate
prepare_lang_test-ds.sh lang/LM.arpa lang lang_test "$DUMMY_CHAR"

##########################################################################################################
# Prepare HMM models
##########################################################################################################
# Create HMM topology file
cd ../../models-AB
mkdir HMMs/train

phones_list=( $(cat ../lang-AB/lm/lang_test/phones/{,non}silence.int) )
featdim=$(feat-to-dim scp:test/confMats_alp0.3.scp - 2>/dev/null)
dummyID=$(awk -v d="$DUMMY_CHAR" '{if (d==$1) print $2}' ../lang-AB/lm/lang/phones.txt)
blankID=$(awk -v bs="${BLANK_SYMB}" '{if (bs==$1) print $2}' ../lang-AB/lm/lang/pdf_blank.txt)

HMM_LOOP_PROB=0.5                         # Self-Loop HMM-state probability
HMM_NAC_PROB=0.5                          # BLSTM-NaC HMM-state probability

create_proto_rnn-ds.sh $featdim ${HMM_LOOP_PROB} ${HMM_NAC_PROB} HMMs/train ${dummyID} ${blankID} ${phones_list[@]}


# Compose FSTs
############################################################################################################

mkdir HMMs/test
mkgraph.sh --mono --transition-scale 1.0 --self-loop-scale 1.0 ../lang/lm/lang_test HMMs/train/new.mdl HMMs/train/new.tree HMMs/test/graph














