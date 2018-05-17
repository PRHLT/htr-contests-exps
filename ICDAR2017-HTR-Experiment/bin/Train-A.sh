#!/bin/bash
set -e;
export LC_NUMERIC=C;
export PATH=$PATH:$(pwd)/bin

# Train a model using the Train-A material fo the ICDAR 2017 dataset                                                                                                         # Author: Verónica Romero <vromero@prhlt.upv.es>

#Download the training data                                                                                                                                                 
#-Train-A: https://doi.org/10.5281/zenodo.439807

### Install textFeats ###
# https://github.com/mauvilsa/textfeats

### Install Laia ###
# https://github.com/jpuigcerver/Laia

### Install other dependencies ###
# sudo apt-get install xmlstarlet gawk python


# Extracting text lines images and preprocessing them
[ -d $(pwd)/data/Train-A/page ] || mkdir $(pwd)/data/Train-A/page  && cp $(pwd)/data/Train-A/*xml $(pwd)/data/Train-A/page;

ln -sf $(pwd)/data/Train-A/*jpg data/Train-A/page

for f in data/Train-A/page/*xml; do 
	page_format_generate_contour -a 75 -d 25 -p $f -o $f ; 
done

[ -d WORK ] || mkdir WORK

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


[ -d WORK/Lines-A ] || {

mkdir WORK/Lines-A
export htrsh_valschema="no"

for i in data/Train-A/page/*xml
do
  N=`basename $i .xml`
  textFeats --cfg <( echo "$textFeats_cfg" ) --outdir WORK/Lines-A/ $i
done

ls -1  WORK/Lines-A | sed 's/\.png//g' |sort > WORK/Lines-A/index

}

#Extracting the text transcripts in the PAGE files and cleaning them
[ -d WORK/TEXT-A ] || {
mkdir WORK/TEXT-A
for i in data/Train-A/page/*xml
do
  N=`basename $i .xml`;
  xmlstarlet sel -t -m '//_:TextLine' -v ../../@imageFilename -o '.' -v @id -o " " -v _:TextEquiv/_:Unicode -n $i | sed -r "s/\.jpg//" > WORK/TEXT-A/$N.tab
done

for i in WORK/TEXT-A/*tab
do
  sed 's/\&amp;/ \& /g' $i |  awk '{if(NF>1) {printf("%s ",$1); for (i=2; i<=NF; i++) printf(" %s",$i);printf("\n")};}' > kk
  mv kk $i
done

cat WORK/TEXT-A/*tab | awk '{printf("%s\n",$1)}' | sort > WORK/TEXT-A/index
cat WORK/TEXT-A/*tab > WORK/TEXT-A/index.words
}


#Preparing lists of training and validation samples and preparing GTs
cd WORK

[ -d PARTITIONS ] || {
mkdir PARTITIONS
cd PARTITIONS/
sdiff ../Lines-A/index ../TEXT-A/index | grep -v "<" | grep -v "<" | grep -v "|" | awk '{printf("%s\n",$1)}' > list-A

head -1000 list-A > train-A.lst
tail -379 list-A > val-A.lst
sed 's/^/data\//g' -i train-A.lst
sed 's/$/.png/g' -i train-A.lst
sed 's/^/data\//g' -i val-A.lst
sed 's/$/.png/g' -i val-A.lst
cd ..
}

[ -d lang-A/char ] || {
mkdir -p lang-A/char
cd lang-A/char


for p in train-A val-A;
do
for f in $(<../../PARTITIONS/${p}.lst); do grep `basename ${f/\.png/}` ../../TEXT-A/index.words; done | \
awk '{
  printf("%s", $1);
  for(i=2;i<=NF;++i) {
    for(j=1;j<=length($i);++j)
      printf(" %s", substr($i, j, 1));
    if (i < NF) printf(" <space>");
  }
  printf("\n");
}' | sed 's/"/'\'' '\''/g;s/#/<stroke>/g' > char.${p}.txt
done

for p in train-A val-A; do cat char.$p.txt | cut -f 2- -d\  | tr \  \\n; done | sort -u -V | awk 'BEGIN{
  N=0;
  printf("%-12s %d\n", "<eps>", N++);
  printf("%-12s %d\n", "<ctc>", N++);
}NF==1{
  printf("%-12s %d\n", $1, N++);
}' >  symb.txt


cd ../../ 
}

[ -d models-A ] || { 
mkdir models-A
cd models-A

# Count the number of symbols to use in the output layer of the model.
# Note: We subtract 1 from the list, because the symbols list includes the
# <eps> symbol typically used by Kaldi
NSYMBOLS=$(sed -n '${ s|.* ||; p; }' "../lang-A/char/symb.txt");

 # Create model
[ -f train.t7 ] || {
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

ln -s ../Lines-A/ data

#Train model
laia-train-ctc 	--use_distortions true        --batch_size 3        --progress_table_output train.dat        --early_stop_epochs 50         --learning_rate 0.0003        --log_level info         --log_file train.log        train.t7 ../lang-A/char/symb.txt ../PARTITIONS/train-A.lst ../lang-A/char/char.train-A.txt ../PARTITIONS/val-A.lst ../lang-A/char/char.val-A.txt 
}
cd ..
}
exit 0
