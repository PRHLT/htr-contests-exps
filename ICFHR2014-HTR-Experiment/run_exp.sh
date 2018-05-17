#!/bin/bash
set -e

# Handwritten text recognition experiment using the ICFHR 2014 dataset

# Author: Joan Andreu Sánchez <jandreu@prhlt.upv.es>
#
# Requirements:
# - NVIDIA GPU with at least 6GB of memory
# - Recent linux distribution (only tested in Ubuntu but should work in others)
# - CUDA 8

### Download and extract dataset ###
# wget https://zenodo.org/record/44519/files/BenthamDatasetR0-GT.tbz
# tar xzf Train-And-Val-ICFHR-2016.tgz

### Install textFeats ###
# https://github.com/mauvilsa/textfeats

### Install Laia ###
# https://github.com/jpuigcerver/Laia

### Install Kaldi ###
# https://github.com/kaldi-asr/kaldi

### Install SRILM toolkit ###
# http://www.speech.sri.com/projects/srilm/

### Install other dependencies ###
# sudo apt-get install xmlstarlet gawk python

### Create directories and add bin to PATH ###

export LC_NUMERIC=C;
export PATH=$PATH:.:~/Competition-2014/utils

# Working folder
WD=/tmp/ICFHR-2014
# Data folder
D=${WD}/BenthamDatasetR0-GT/
# Experiment folder
EXPF=${WD}/EXP

# Create data folder and download the data
[ -d ${WD} ] || mkdir ${WD}
cd ${WD}
[ -f BenthamDatasetR0-GT.tbz ] || \
    {
	wget https://zenodo.org/record/44519/files/BenthamDatasetR0-GT.tbz
    }
[ -d BenthamDatasetR0-GT ] || tar jxf BenthamDatasetR0-GT.tbz

# Create experiment folder
[ -d ${EXPF} ] ||  mkdir ${EXPF}
cd ${EXPF} && echo "Current folder: " ${EXPF}

## Variable related to the training process
overwrite=false;
batch_size=8;  # Adjust to the GPU
height=128;     # Change according to the image resolution

## Create link to image line folder
[ -d Images ] || ln -s ${D}/Images/Lines/ Images
## Create link to transcript folder
[ -d Transcriptions ] || ln -s ${D}/Transcriptions Transcriptions

## Prepare transcripts
mkdir -p TEXT
for i in ${D}/Transcriptions/*txt
do
  NAMEF=`basename $i .txt`
  echo ${NAMEF} " <space> " "`cat $i | sed 's/ \+/ /g' | sed -e 's/./& /g' -e 's/   / <space> /g'`" "<space>" >> TEXT/text.txt
done

cut -f 2- -d\  TEXT/text.txt |  tr \  \\n | \
  sort -u -V | awk 'BEGIN{
      N=0;
      printf("%-12s %d\n", "<eps>", N++);
      printf("%-12s %d\n", "<ctc>", N++);
    }NF==1{
      printf("%-12s %d\n", $1, N++);
    }' > TEXT/symb.txt 

## Processing the images
mkdir -p imgs_proc
TMPD="$(mktemp -d)";
bkg_pids=();
np="$(nproc)";

for f in $(cat ${D}/Partitions/{TrainLines,ValidationLines,TestLines}.lst); do
    (
        echo "File $f.png ..." 
        echo "File $f.png ..." >&2;
        NAMEB=`basename $f`
        imgtxtenh -u mm -d 118.1102362205 Images/$f.png imgs_proc/${NAMEB}.jpg;
        convert imgs_proc/${NAMEB}.jpg -fuzz 5% -trim +repage imgs_proc/${NAMEB}.jpg;
        convert imgs_proc/${NAMEB}.jpg -resize "x$height" -strip imgs_proc/${NAMEB}.jpg;
    ) &> "$TMPD/${#bkg_pids[@]}" &
    bkg_pids+=("$!");

## Wait for jobs to finish when number of running jobs = number of processors

if [ "${#bkg_pids[@]}" -eq "$np" ]; then
    for n in $(seq 1 "${#bkg_pids[@]}"); do
        wait "${bkg_pids[n-1]}" || (
            echo "Failed image processing:" >&2 && cat "$TMPD/$[n-1]" >&2 && exit 1;
        );
    done;
    bkg_pids=();
fi;
done;

## Wait for jobs to finish
for n in $(seq 1 "${#bkg_pids[@]}"); do
    wait "${bkg_pids[n-1]}" || (
	echo "Failed image processing:" >&2 && cat "$TMPD/$[n-1]" >&2 && exit 1;
    );
done;
bkg_pids=();
rm -rf "$TMPD";

num_symbols=$[$(wc -l TEXT/symb.txt | cut -d\  -f1) - 1];
laia-create-model \
    --cnn_type leakyrelu \
    --cnn_kernel_size 3 \
    --cnn_num_features 12 24 48 96 \
    --cnn_maxpool_size 2,2 2,2 1,2 1,2 \
    --cnn_batch_norm false \
    --rnn_num_layers 4 \
    --rnn_num_units 256 \
    --rnn_dropout 0.5 \
    --linear_dropout 0.5 \
    --log_level info \
    1 "$height" "$num_symbols" model.t7;

cat ${D}/Partitions/TrainLines.lst | awk '{printf("imgs_proc/%s.jpg\n",$1);}' > tr-imgs.lst
cat ${D}/Partitions/ValidationLines.lst | awk '{printf("imgs_proc/%s.jpg\n",$1);}' > va-imgs.lst
cat ${D}/Partitions/TestLines.lst | awk '{printf("imgs_proc/%s.jpg\n",$1);}' > test-imgs.lst
cat tr-imgs.lst va-imgs.lst >> tr-full-imgs.lst

laia-train-ctc --use_distortions true --batch_size ${batch_size} --progress_table_output train.dat --early_stop_epochs 20 --learning_rate 0.00027 --log_also_to_stderr debug --log_level debug --log_file train.log model.t7 TEXT/symb.txt tr-imgs.lst TEXT/text.txt va-imgs.lst TEXT/text.txt 

# Decoding
laia-decode --batch_size  ${batch_size} --log_file test.log --log_level info --symbols_table TEXT/symb.txt model.t7 test-imgs.lst > test-hyp.lst

prepare_transc_cl.sh ${D}/Transcriptions/ txt . ${D}/Partitions/TestLines.lst

## Prepare transcripts
for i in $(<${D}/Partitions/TestLines.lst); do 
  echo ${i} " <space> " "`cat ${D}/Transcriptions/${i}.txt | sed 's/ \+/ /g' | sed -e 's/./& /g' -e 's/   / <space> /g'`" >> test-ref.lst
done
cat test-ref.lst | awk '
  {
    printf("%s ",$1);
    if ($2=="<space>") i=3; else i=2; 
    for (;i<NF;i++) printf("%s ",$i);
    if ($NF=="<space>") printf("\n"); else  printf("<space>\n");
  }' > test-ref-no-space.lst
cat test-hyp.lst | awk '
  {
    printf("%s ",$1);
    if ($2=="<space>") i=3; else i=2; 
    for (;i<NF;i++) printf("%s ",$i);
    if ($NF=="<space>") printf("\n"); else  printf("<space>\n");
  }' > test-hyp-no-space.lst

# Compute CER from the net output
compute-wer --mode=strict ark:test-ref-no-space.lst ark:test-hyp-no-space.lst

for i in $(<${D}/Partitions/TestLines.lst); do
    echo $i " " "`cat ${D}/Transcriptions/${i}.txt`" >> test-ref-words.lst;
done
cat test-ref-words.lst | sed -e 's/\./ \./g' -e 's/:/ :/g' -e 's/(/ ( /g' -e 's/)/ ) /g' -e 's/;/ ;/g' -e 's/,/ ,/g' -e "s/\"/ \" /g" -e 's/\[/ \[ /' -e 's/\]/ \] /' > test-ref-words-new.lst
awk '{printf $1"\t"; for (i=2;i<=NF;i++) {if ($i=="<space>") $i=" "; printf $i;} print ""}' test-hyp.lst > test-hyp-words.lst
cat test-hyp-words.lst | awk '{if ($2 != ":") printf("%s\n",$0); else {printf("%s     :",$1);for (i=3;i<NF;i++) printf("%s ",$i);printf("%s\n",$NF);}}' > temp00
mv temp00  test-hyp-words.lst

# Compute WER from the net output
compute-wer --mode=strict ark:test-ref-words-new.lst ark:test-hyp-words.lst | grep WER

cp model.t7 model.t7.1

#  Train the net with the full training for 1 epoch
laia-train-ctc --use_distortions true --batch_size ${batch_size} --progress_table_output train-full.dat --max_epochs 1 --learning_rate 0.00027 --log_also_to_stderr debug --log_level debug --log_file train-full.log model.t7.1 TEXT/symb.txt tr-full-imgs.lst TEXT/text.txt 
laia-decode --batch_size ${batch_size} --log_file test.log --log_level info --symbols_table TEXT/symb.txt model.t7.1 test-imgs.lst > test-hyp-1.lst

cat test-hyp-1.lst | awk '
  {
    printf("%s ",$1);
    if ($2=="<space>") i=3; else i=2; 
    for (;i<NF;i++) printf("%s ",$i);
    if ($NF=="<space>") printf("\n"); else  printf("<space>\n");
  }' > test-hyp-1-no-space.lst

# Compute WER from the net output
compute-wer --mode=strict ark:test-ref.lst ark:test-hyp-1-no-space.lst | grep WER

awk '{printf $1"\t"; for (i=2;i<=NF;i++) {if ($i=="<space>") $i=" "; printf $i;} print ""}' test-hyp-1-no-space.lst > test-hyp-words-1-no-space.lst
cat test-hyp-words-1-no-space.lst  | awk '{if ($2 != ":") printf("%s\n",$0); else {printf("%s     :",$1);for (i=3;i<NF;i++) printf("%s ",$i);printf("%s\n",$NF);}}' > temp00
mv temp00 test-hyp-words-1-no-space.lst
compute-wer --mode=present ark:test-ref-words-new.lst ark:test-hyp-words-1-no-space.lst | grep WER

# --------------------------------------
# --------------------------------------
# Experiment with character-based language model
# --------------------------------------
# --------------------------------------
[ -d ${WD}/LM_EXP ] || mkdir ${WD}/LM_EXP
LMDIR=${WD}/LM_EXP
cd $LMDIR
CHRS_LST=${LMDIR}/chars.txt
awk 'NR>1{print $1 " " $2}' ${EXPF}/TEXT/symb.txt  > $CHRS_LST

DEVEL_PM_DIR=confMats			  # Directory of Validation Confidence Matrices
GT_FILE=${EXPF}/TEXT/text.txt		  # File containing ground-truth in Kaldi format
EXT_PM_FILE=txt				  # File extension of confidence matrix files

TRAIN_ID_LST=${D}/Partitions/TrainLines.lst       # List of line IDs of Training set
DEVEL_ID_LST=${D}/Partitions/ValidationLines.lst  # List of line IDs of Validation set

# --------------------------------------
# Special symbols
# --------------------------------------
BLANK_SYMB="<ctc>"                        # BLSTM non-character symbol
WHITESPACE_SYMB="<space>"                 # White space symbol
DUMMY_CHAR="<DUMMY>"                      # Especial HMM used for modelling "</s>" end-sentence
# --------------------------------------
# Feature processing settings
# --------------------------------------
LOGLKH_ALPHA_FACTOR=0.3                   # p(x|s) = P(s|x) / P(s)^LOGLKH_ALPHA_FACTOR
# --------------------------------------
# Modelling settings
# --------------------------------------
HMM_LOOP_PROB=0.5			  # Self-Loop HMM-state probability
HMM_NAC_PROB=0.5			  # BLSTM-NaC HMM-state probability
GSF=0.9424088
WIP=-4.7415619
ASF=0.818				  # Acoustic Scale Factor
NGRAM_ORDER=7				  # N-Gram Language Model Order
# --------------------------------------
# Decoding settings
# --------------------------------------
MAX_NUM_ACT_STATES=15000000		  # Maximum number of active states
BEAM_SEARCH=12				  # Beam search
LATTICE_BEAM=10				  # Lattice generation beam
# --------------------------------------
# System settings
# --------------------------------------
N_CORES=`nproc`


ln -s $D/Partitions/TrainLines.lst       tr-id.lst
ln -s $D/Partitions/ValidationLines.lst  va-id.lst
ln -s $D/Partitions/TestLines.lst        test-id.lst

[ -f data/train/text ] ||
    {
	echo "Processing training transcripts into Kaldi format ..." 1>&2
	[ -d data/train/ ] || mkdir -p data/train/
	awk -v idf="tr-id.lst" 'BEGIN{while (getline < idf > 0) IDs[$1]=""}
                              {if ($1 in IDs) print}' $GT_FILE > data/train/text
    }
[ -f data/test/text ] ||
    {
	echo "Processing development transcripts into Kaldi format ..." 1>&2
	[ -d data/test/ ] || mkdir -p data/test/
	awk -v idf="va-id.lst" 'BEGIN{while (getline < idf > 0) IDs[$1]=""}
                              {if ($1 in IDs) print}' $GT_FILE > data/test/text
    }
###################################################################################
# Processing training data: Computation of Char Priors
###################################################################################
ln -s $EXPF/imgs_proc/
laia-force-align \
  --batch_size ${batch_size} \
  --log_level info \
  --log_also_to_stderr info \
  ${EXPF}/model.t7 ${CHRS_LST} \
  ${EXPF}/tr-imgs.lst ${GT_FILE} \
  align_output.txt priors.txt

laia-netout \
  --batch_size ${batch_size} \
  --log_level info \
  --log_also_to_stderr info \
  --output_format matrix \
  --prior priors.txt --prior_alpha 0.3 \
  ${EXPF}/model.t7 ${EXPF}/va-imgs.lst confMats_ark.txt

###################################################################################
# Processing development feature samples into Kaldi format
###################################################################################
[ -e data/test/${DEVEL_PM_DIR}_alp${LOGLKH_ALPHA_FACTOR}.ark ] ||
    {
	echo "Processing development samples into Kaldi format ..." 1>&2
	copy-matrix "ark,t:confMats_ark.txt" "ark,scp:data/test/${DEVEL_PM_DIR}_alp${LOGLKH_ALPHA_FACTOR}.ark,data/test/${DEVEL_PM_DIR}_alp${LOGLKH_ALPHA_FACTOR}.scp"
    }
###################################################################################
# Prepare Kaldi's lang directories
###################################################################################
[ -d data/train/lang ] ||
    {
	echo "Generating lexic model ..." 1>&2
	prepare_lang_cl-ds.sh data/train "${CHRS_LST}" "${BLANK_SYMB}" "${WHITESPACE_SYMB}" "${DUMMY_CHAR}"
    }

# Preparing LM (G)
[ -f data/train/lang/LM${NGRAM_ORDER}.arpa ] ||
    {
	echo "Generating ${NGRAM_ORDER} character-level language model ..." 1>&2
	cat data/train/text | cut -d " " -f 2- | \
	    ngram-count -text - -lm data/train/lang/LM${NGRAM_ORDER}.arpa -order ${NGRAM_ORDER} -kndiscount -interpolate
	prepare_lang_test-ds.sh data/train/lang/LM${NGRAM_ORDER}.arpa data/train/lang data/train/lang_test "$DUMMY_CHAR"
    }
###################################################################################
#  Prepare HMM models
###################################################################################
# Create HMM topology file
[ -d train ] ||
    {
	echo "Creating character HMM topologies ..." 1>&2
	mkdir train
	phones_list=( $(cat data/train/lang_test/phones/{,non}silence.int) )
	featdim=$(feat-to-dim scp:data/test/${DEVEL_PM_DIR}_alp${LOGLKH_ALPHA_FACTOR}.scp - 2>/dev/null)
	dummyID=$(awk -v d="$DUMMY_CHAR" '{if (d==$1) print $2}' data/train/lang/phones.txt)
	blankID=$(awk -v bs="${BLANK_SYMB}" '{if (bs==$1) print $2}' data/train/lang/pdf_blank.txt)
	create_proto_rnn-ds.sh $featdim ${HMM_LOOP_PROB} ${HMM_NAC_PROB} train ${dummyID} ${blankID} ${phones_list[@]}
}
###################################################################################
#  Compose FSTs
###################################################################################
[ -d test/ ] ||
    {
	echo "Creating global SFS automaton for decoding ..." 1>&2
	mkdir test
	mkgraph.sh --mono --transition-scale 1.0 --self-loop-scale 1.0 \
                   data/train/lang_test train/new.mdl train/new.tree test/graph
    }
###################################################################################
#  Lattice Generation
###################################################################################
[ -f lat.gz ] ||
    {
	echo "Generating lattices ..." 1>&2
	split -d -n l/${N_CORES} -a 3 data/test/${DEVEL_PM_DIR}_alp${LOGLKH_ALPHA_FACTOR}.scp part-
	mkdir lattices
	for n in $(seq -f "%03.0f" 0 1 $[N_CORES-1]); do
	    echo "launching subprocess in core $n ..." 1>&2
	    latgen-faster-mapped --verbose=2 --acoustic-scale=${ASF} --max-active=${MAX_NUM_ACT_STATES} \
				 --beam=${BEAM_SEARCH} --lattice-beam=${LATTICE_BEAM} train/new.mdl \
				 test/graph/HCLG.fst scp:part-$n "ark:|gzip -c > lattices/lat_$n.gz" \
    				 ark,t:lattices/RES_$n 2>lattices/LOG-Lats-$n &
	done
	echo "Waiting for finalization of the ${N_CORES} subprocesses ..." 1>&2
	wait
	lattice-copy "ark:gunzip -c lattices/lat_*.gz |" "ark:|gzip -c > lat.gz"
	rm lattices/*.gz part-*
    }
########################
# Tunning GSF and WIP 
########################
ln -s va-id.lst de-ref.lst
simplex.py -m "opt_gsf-wip_cl.sh {1.0} {-0.4}" > simplex_out
GSF=`grep "Optimum command" simplex_out | awk '{print $4}'`
WIP=`grep "Optimum command" simplex_out | awk '{print $5}'`

###################################################################################
#  Add development set to the training and test on test dataset
###################################################################################
cat tr-id.lst va-id.lst > tr-full-id.lst
awk -v idf=tr-full-id.lst 'BEGIN{while (getline < idf > 0) IDs[$1]=""}
                           {if ($1 in IDs) print}' $GT_FILE > data/train/text-full

laia-force-align \
  --batch_size ${batch_size} \
  --log_level info \
  --log_also_to_stderr info \
  ${EXPF}/model.t7.1 ${CHRS_LST} \
  ${EXPF}/tr-full-imgs.lst ${GT_FILE} \
  align_output_full.txt priors_full.txt

laia-netout \
  --batch_size ${batch_size} \
  --log_level info \
  --log_also_to_stderr info \
  --output_format matrix \
  --prior priors_full.txt --prior_alpha 0.3 \
  ${EXPF}/model.t7.1 ${EXPF}/test-imgs.lst confMats_ark_full.txt

copy-matrix "ark,t:confMats_ark_full.txt" "ark,scp:data/test/${DEVEL_PM_DIR}_alp${LOGLKH_ALPHA_FACTOR}_full.ark,data/test/${DEVEL_PM_DIR}_alp${LOGLKH_ALPHA_FACTOR}_full.scp"

# Preparing LM
echo "Generating ${NGRAM_ORDER} character-level language model ..." 1>&2
cat data/train/text-full | cut -d " " -f 2- | \
ngram-count -text - -lm data/train/lang/LM_full${NGRAM_ORDER}.arpa -order ${NGRAM_ORDER} -kndiscount -interpolate
prepare_lang_test-ds.sh data/train/lang/LM_full${NGRAM_ORDER}.arpa data/train/lang data/train/lang_test "$DUMMY_CHAR"

mkdir test-full
mkgraph.sh --mono --transition-scale 1.0 --self-loop-scale 1.0 \
           data/train/lang_test train/new.mdl train/new.tree test-full/graph

decode-faster-mapped --acoustic-scale=${GSF} --beam=${BEAM_SEARCH} train/new.mdl test-full/graph/HCLG.fst scp:data/test/confMats_alp${LOGLKH_ALPHA_FACTOR}_full.scp ark,t:- > hypotheses-test

int2sym.pl -f 2- test-full/graph/words.txt hypotheses-test > hypotheses-test_t

cat hypotheses-test_t | awk '
  {
    printf("%s ",$1);
    if ($2=="<space>") i=3; else i=2; 
    for (;i<NF;i++) printf("%s ",$i);
    if ($NF=="<space>") printf("\n"); else  printf("<space>\n");
  }' > tmp-test
mv tmp-test hypotheses-test_t
compute-wer --mode=strict ark:../EXP/test-ref.lst ark:hypotheses-test_t | grep WER

awk '{printf $1"\t"; for (i=2;i<=NF;i++) {if ($i=="<space>") $i=" "; printf $i;} print ""}' hypotheses-test_t > hypotheses-test_t_words
cat hypotheses-test_t_words  | awk '{if ($2 != ":") printf("%s\n",$0); else {printf("%s     :",$1);for (i=3;i<NF;i++) printf("%s ",$i);printf("%s\n",$NF);}}' > tmp-test2
mv tmp-test2 hypotheses-test_t_words
compute-wer --mode=present ark:../EXP/test-ref-words-new.lst ark:hypotheses-test_t_words | grep WER

exit 0
