#!/usr/bin/env bash
set -e

# Handwritten text recognition experiment using the ICFHR 2016 dataset
#
# Author: Alejandro H. Toselli <ahector@prhlt.upv.es.com>
#
# Requirements:
# - NVIDIA GPU with at least 6GB of memory
# - Recent linux distribution (only tested in Ubuntu but should work in others)
# - CUDA 8
# - docker-ce (docker runnable without the need of sudo)
# - nvidia-docker

### Download and extract dataset ###
# wget https://zenodo.org/record/218236/files/PublicData.tgz
# tar xzf PublicData.tgz; rm PublicData.tgz
# The Test is in: ts@tranScripTorium:/home2/tsdataupv/Bozen/Contest-data/Test/

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
export PATH="$(pwd)/bin:$PATH";
if [ ! -d work ]; then 
  mkdir work; cd work
  ln -s ../PublicData/Training/page IMAGES-Train
  ln -s ../PublicData/Validation/page IMAGES-Val
  ln -s ../Test IMAGES-Test
else
  cd work
fi



#===============================================
#===================  TRAIN  ===================
#===============================================

# Extracting and processing text line images and their transcrips
[ -d Lines-Processed-Train -a -f Line-Transcripts-Train.txt ] ||
{
  mkdir Lines-Processed-Train
  for i in IMAGES-Train/*.xml; do
    textFeats --cfg ../feats.cfg --outdir ./Lines-Processed-Train $i;
  done
  for f in IMAGES-Train/*.xml; do
    xmlstarlet sel -t -m '//_:TextLine' -v ../../@imageFilename -o '.' -v @id -o " " -v _:TextEquiv/_:Unicode -n $f;
  done | 
  sed -r "s/\.JPG//" > Line-Transcripts-Train.txt
}

[ -d Lines-Processed-Val -a -f Line-Transcripts-Val.txt ] ||
{
  mkdir Lines-Processed-Val
  for i in IMAGES-Val/*.xml; do
    textFeats --cfg ../feats.cfg --outdir ./Lines-Processed-Val $i;
  done
  for f in IMAGES-Val/*.xml; do
    xmlstarlet sel -t -m '//_:TextLine' -v ../../@imageFilename -o '.' -v @id -o " " -v _:TextEquiv/_:Unicode -n $f;
  done |
  sed -r "s/\.JPG//" > Line-Transcripts-Val.txt
}

# Preparing GTs and Lists of training and validation samples
cut -d " " -f1 Line-Transcripts-Train.txt > train.lst
ls Lines-Processed-Train/*.png > train_imgs.lst
[ -f train_gt.txt ] ||
{
  filter-ext.py --sepsym "<space>" 1 Line-Transcripts-Train.txt |
  awk 'BEGIN{while (getline < "train.lst" > 0) T[$1]=""}
       {
          if ($1 in T) {
  	    printf $1"\t<space>";
	    for (i=2;i<=NF;i++) printf " "$i;
	    print " <space>"
 	  }
       }' > train_gt.txt
}
cut -d " " -f1 Line-Transcripts-Val.txt > valid.lst
ls Lines-Processed-Val/*.png > valid_imgs.lst
[ -f valid_gt.txt ] ||
{
  filter-ext.py --sepsym "<space>" 1 Line-Transcripts-Val.txt |
  awk 'BEGIN{while (getline < "valid.lst" > 0) T[$1]=""}
       {
         if ($1 in T) {
           printf $1"\t<space>";
           for (i=2;i<=NF;i++) printf " "$i;
	   print " <space>"
         } 
       }' > valid_gt.txt
}

awk '{for (i=2;i<=NF;i++) L[$i]=""}END{for (l in L) print l}' train_gt.txt valid_gt.txt |
sort |
awk 'BEGIN{print "<eps>\t0\n<ctc>\t1"}{print $1"\t"NR+1}' > symbols.txt

# Count the number of symbols to use in the output layer of the model.
# Note: We subtract 1 from the list, because the symbols list includes the
# <eps> symbol typically used by Kaldi.
num_symbols=$[$(wc -l symbols.txt | cut -d\  -f1) - 1];

# Create and train model
[ -f model.t7 ] ||
{
  # Create model
  laia-create-model \
    --cnn_type leakyrelu \
    --cnn_kernel_size 7,7 5,5 3,3 3,3 \
    --cnn_num_features 12 24 48 48 \
    --cnn_maxpool_size 2,2 2,2 0 2,2 \
    --cnn_batch_norm false false true false \
    --rnn_num_layers 3 \
    --rnn_num_units 256 \
    --rnn_dropout 0.5 \
    --linear_dropout 0.5 \
    --log_level info \
    3 64 "$num_symbols" model.t7

  # Train model
  laia-train-ctc \
    --batch_size "16" \
    --log_also_to_stderr info \
    --log_level info \
    --log_file train.log \
    --progress_table_output train.dat \
    --use_distortions true \
    --learning_rate 0.0005 \
    --early_stop_epochs 50 \
    model.t7 symbols.txt \
    train_imgs.lst train_gt.txt \
    valid_imgs.lst valid_gt.txt

  # Including validation in the training
  cat {train,valid}_imgs.lst > full_imgs.lst
  cat {train,valid}_gt.txt > full_gt.txt

  # Train model with validation
  cp model.t7 model_full.t7
  laia-train-ctc \
    --batch_size "16" \
    --max_epochs 3 \
    --best_criterion train_cer \
    --log_also_to_stderr info \
    --log_level info \
    --log_file train.log \
    --progress_table_output train.dat \
    --use_distortions true \
    --learning_rate 0.0001 \
    --early_stop_epochs 5 \
    model_full.t7 symbols.txt \
    full_imgs.lst full_gt.txt \
    valid_imgs.lst valid_gt.txt
}

# Force alignment in the training to compute char priors
[ -f align_output.txt -a -f priors.txt ] ||
laia-force-align \
  --batch_size "16" \
  --batcher_cache_gpu 1 \
  --log_level info \
  --log_also_to_stderr info \
  model.t7 symbols.txt \
  train_imgs.lst train_gt.txt \
  align_output.txt priors.txt



#==============================================
#===================  TEST  ===================
#==============================================

# Extracting and processing text line images and their transcrips
[ -d Lines-Processed-Test -a -f Line-Transcripts-Test.txt ] ||
{
  mkdir Lines-Processed-Test
  for i in IMAGES-Test/*.xml; do
    textFeats --cfg ../feats.cfg --outdir ./Lines-Processed-Test $i;
  done
  for f in IMAGES-Test/*.xml; do
    xmlstarlet sel -t -m '//_:TextLine' -v ../../@imageFilename -o '.' -v @id -o " " -v _:TextEquiv/_:Unicode -n $f;
  done |
  sed -r "s/\.JPG//" > Line-Transcripts-Test.txt
}

# Preparing GTs and Lists of test samples
cut -d " " -f1 Line-Transcripts-Test.txt > test.lst
ls Lines-Processed-Test/*.png > test_imgs.lst
[ -f test_gt.txt ] ||
{
  filter-ext.py --sepsym "<space>" 1 Line-Transcripts-Test.txt |
  awk 'BEGIN{while (getline < "test.lst" > 0) T[$1]=""}
       {
         if ($1 in T) {
	   printf $1"\t<space>";
	   for (i=2;i<=NF;i++) printf " "$i;
	   print " <space>"
	 }
       }' > test_gt.txt
}

# Get character-level transcript hypotheses
[ -f rec.txt ] ||
laia-decode \
  --batch_size "16" \
  --log_level info \
  --symbols_table symbols.txt \
  model_full.t7 test_imgs.lst > rec.txt;

# Computing CER without initial and final <space>
awk '{$2=""; $NF=""; print}' rec.txt > raux; awk '{$2=""; $NF=""; print}' test_gt.txt > taux
( echo -en "CER without LM\t"
  compute-wer --mode=strict \
    ark:taux ark:raux | grep WER | sed -r 's|%WER|%CER|g' ) > ../RESULTS.txt
rm raux taux

# Computing WER according to the way of the contest
paste <(cut -d " " -f 1 Line-Transcripts-Test.txt) <(cut -d " " -f 2- Line-Transcripts-Test.txt | sed -r "s/[-\xe2\x80\x94.,;:?\xc2\xac=+)\&]/ & /g; s/\(/& /g") > raux
awk '{printf $1"\t"; for (i=2;i<=NF;i++) {if ($i=="<space>") $i=" "; printf $i;} print ""}' rec.txt > rec_word.txt
paste <(cut -d " " -f 1 rec_word.txt) <(cut -d " " -f 2- rec_word.txt | sed -r "s/[-\xe2\x80\x94.,;:?\xc2\xac=+)\&]/ & /g; s/\(/& /g") > taux
( echo -en "WER without LM\t"
  compute-wer --mode=strict ark:taux ark:raux | grep WER ) >> ../RESULTS.txt
rm raux taux

# Obtaining ConfMats required by Test-LM
[ -f confMats_ark.txt ] ||
laia-netout \
  --batch_size "16" \
  --batcher_cache_gpu 1 \
  --log_level info \
  --log_also_to_stderr info \
  --output_format matrix \
  --prior priors.txt \
  --prior_alpha 0.3 \
  model_full.t7 test_imgs.lst confMats_ark.txt

# Incorporating LM
[ -d Test-LM ] ||
{
  mkdir Test-LM; cd Test-LM

  # Data preparation
  awk '{print $1}' ../{train,valid}_gt.txt > ID_train.lst
  awk '{print $1}' ../test_gt.txt > ID_test.lst
  cat ../{train,valid}_gt.txt ../test_gt.txt > grnTruth.dat
  awk 'NR>1{print $1}' ../symbols.txt > chars.lst
  ln -s ../confMats_ark.txt confMats

  # Add LM using Kaldi toolkit
  run-with-LM.sh

  # Compute CER without initial and final <space>
  awk '{$2=""; $NF=""; print}' hypotheses_t > raux; awk '{$2=""; $NF=""; print}' data/test/text > taux
  ( echo -en "CER  with   LM\t"
    compute-wer --mode=strict \
      ark:taux ark:raux | grep WER | sed -r 's|%WER|%CER|g' ) >> ../../RESULTS.txt

  # Computing WER according to the way of the contest
  ln -s ../Line-Transcripts-Test.txt
  paste <(cut -d " " -f 1 Line-Transcripts-Test.txt) <(cut -d " " -f 2- Line-Transcripts-Test.txt | sed -r "s/[-\xe2\x80\x94.,;:?\xc2\xac=+)\&]/ & /g; s/\(/& /g") > raux
  awk '{printf $1"\t"; for (i=2;i<=NF;i++) {if ($i=="<space>") $i=" "; printf $i;} print ""}' hypotheses_t > rec_word.txt
  paste <(cut -d " " -f 1 rec_word.txt) <(cut -d " " -f 2- rec_word.txt | sed -r "s/[-\xe2\x80\x94.,;:?\xc2\xac=+)\&]/ & /g; s/\(/& /g") > taux
  ( echo -en "WER  with   LM\t"
    compute-wer --mode=strict ark:taux ark:raux | grep WER ) >> ../../RESULTS.txt
  rm raux taux
}

exit 0
