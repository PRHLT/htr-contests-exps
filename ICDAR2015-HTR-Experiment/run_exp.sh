#!/usr/bin/env bash

# Handwritten text recognition experiment using the ICDAR 2015 dataset
#
# Author: Mauricio Villegas <mauricio_ville@yahoo.com>
#
# Requirements:
# - NVIDIA GPU with at least 6GB of memory
# - Recent linux distribution (only tested in Ubuntu but should work in others)
# - CUDA 8
# - docker-ce (docker runnable without the need of sudo)
# - nvidia-docker

### Download and extract dataset ###
# wget https://zenodo.org/record/1136294/files/ICDAR-HTR-Competition-2015-data.zip
# unzip ICDAR-HTR-Competition-2015-data.zip

### Install textFeats ###
# docker pull mauvilsa/textfeats:2018.01.06
# docker tag mauvilsa/textfeats:2018.01.06 textfeats:active
# docker run --rm -u $(id -u):$(id -g) -v $(pwd):$(pwd) textfeats:active bash -c "cp /usr/local/bin/textFeats-docker $(pwd)/bin"

### Install Laia ###
# docker pull mauvilsa/laia:2018.01.09-cuda8.0-ubuntu16.04
# docker tag mauvilsa/laia:2018.01.09-cuda8.0-ubuntu16.04 laia:active
# docker run --rm -u $(id -u):$(id -g) -v $(pwd):$(pwd) laia:active bash -c "cp /usr/local/bin/laia-docker $(pwd)/bin"

### Install Kaldi ###
# docker pull mauvilsa/kaldi:2018.01.07
# docker tag mauvilsa/kaldi:2018.01.07 kaldi:active
# docker run --rm -u $(id -u):$(id -g) -v $(pwd):$(pwd) kaldi:active bash -c "cp /usr/local/bin/kaldi-docker $(pwd)/bin"

### Install MITLM toolkit ###
# docker pull mauvilsa/mitlm:0.4.2
# docker tag mauvilsa/mitlm:0.4.2 mitlm:active
# docker run --rm -u $(id -u):$(id -g) -v $(pwd):$(pwd) mitlm:active bash -c "cp /usr/local/bin/mitlm-docker $(pwd)/bin"

### Install tesseract-recognize ###
# docker pull mauvilsa/tesseract-recognize:2017.12.18-github-master
# docker tag mauvilsa/tesseract-recognize:2017.12.18-github-master tesseract-recognize:active
# docker run --rm -u $(id -u):$(id -g) -v $(pwd):$(pwd) tesseract-recognize:active bash -c "cp /usr/local/bin/tesseract-recognize-docker $(pwd)/bin"

### Install other dependencies ###
# sudo apt-get install xmlstarlet gawk python python-pip
# sudo pip install numpy editdistance


### Create directories and add bin to PATH ###
mkdir -p lists logs lines/{train,valid,traindet,test} models decode/postprob;
export PATH="$(pwd)/bin:$PATH";

### Load htrsh library ###
. htrsh.inc.sh;

### Configuration ###
. filter.cfg;

EPS_SYMB="<eps>";
BLANK_SYMB="{blank}";
DUMMY_CHAR="{dummy}";

HMM_LOOP_PROB="0.6";
HMM_BLANK_PROB="0.5";
NGRAM_ORDER="8";

INPUT_HEIGHT="64";
CHANNELS="3";
BATCH="20";
BATCH_ALIGN="18";

ADVERSARIAL_WEIGHT="0.5";
USE_DISTORTIONS="true";
EARLY_STOP_EPOCHS="10";
LEARNING_RATE="0.0005";
LEARNING_RATE_DECAY="0.99";
NUM_SAMPLES_EPOCH="0";
MAX_EPOCHS_FINAL="15";
LEARNING_RATE_FINAL=$(echo 0.05*$LEARNING_RATE | bc -l);

LOGLKH_ALPHA_FACTOR="0.3";
GSF="0.5";
WIP="-1.0";
ASF="0.8";
MAX_NUM_ACT_STATES="40000";
BEAM_SEARCH="24";
LATTICE_BEAM="6";

sed_tokenizer () { sed "$htrsh_sed_tokenize_simplest"; }


### Create batch 1 train and valid partitions ###
echo "Creating 1stBatch partitions";
ls data/TRAIN/1stBatch/*xml | sort -R > lists/1stBatch.rnd;
sed -n '1,43p' lists/1stBatch.rnd > lists/valid_1stBatch_pages.lst;
sed -n '44,$p' lists/1stBatch.rnd > lists/train_1stBatch_pages.lst;
rm lists/1stBatch.rnd;

### Extract line images from batch 1 ###
for list in valid train; do
  echo "Extracting batch 1 $list text line images";
  textFeats-docker --cfg feats.cfg --outdir lines/$list --featlist $(cat lists/${list}_1stBatch_pages.lst) \
    > lists/${list}_1stBatch_lines.lst 2> logs/feats_${list}_1stBatch.log;
done

### Extract train batch 1 character level ground truth transcripts ###
echo "Extracting batch 1 character level ground truth";
cat lists/{valid,train}_1stBatch_pages.lst \
  | run_parallel -p no -e yes -T $(nproc) -l - \
      htrsh_pagexml_textequiv '{*}' -f tab-chars -F text_filter \
  > lists/1stBatch_gt_chars.tab;

echo "Extracting batch 2 character level ground truth";
cat data/TRAIN/2ndBatch/*.txt \
  | htrsh_text_to_chars - -F text_filter \
  > lists/2ndBatch_gt_chars.txt;

echo "Creating symbols list";
{ sed 's|^[^ ]* ||; s| |\n|g' lists/1stBatch_gt_chars.tab;
  cat lists/2ndBatch_gt_chars.txt;
} | awk '{char[$1]++}END{for(c in char)printf("%d %s\n",char[c],c)}' \
  | sort -k 1rn,1 \
  > lists/gt_chars.txt;

awk -v EPS="$EPS_SYMB" -v BLANK="$BLANK_SYMB" -v N=1 '
  BEGIN {
    printf("%s 0\n",EPS);
    printf("%s 1\n",BLANK);
  }
  { if( ARGIND == 1 || ( !($2 in char) ) )
      printf("%s %d\n",$2,++N);
    char[$2]="";
  }' lists/gt_chars.txt \
  > models/symbols.txt;


### Train HTR model from scratch with batch 1 train and valid ###
echo "Training HTR model from scratch using 1st batch";
NSYMBOLS=$(sed -n '${ s|.* ||; p; }' models/symbols.txt);
laia-docker create-model \
    --cnn_batch_norm true \
    --cnn_kernel_size 3 \
    --cnn_maxpool_size 2,2 2,2 0 2,2 \
    --cnn_num_features 16 16 32 32 \
    --cnn_type leakyrelu \
    --rnn_type blstm --rnn_num_layers 3 \
    --rnn_num_units 256 \
    "$CHANNELS" "$INPUT_HEIGHT" "$NSYMBOLS" models/model_batch1.t7 \
  &> logs/train_1stBatch_init.log;
laia-docker train-ctc \
  --batch_size "$BATCH" \
  --cer_trim $(awk -v s="$htrsh_symb_space" '{if($1==s){printf("%s",$2);exit;}}' models/symbols.txt) \
  --adversarial_weight "$ADVERSARIAL_WEIGHT" \
  --use_distortions "$USE_DISTORTIONS" \
  --early_stop_epochs "$EARLY_STOP_EPOCHS" \
  --learning_rate "$LEARNING_RATE" \
  --learning_rate_decay "$LEARNING_RATE_DECAY" \
  --num_samples_epoch "$NUM_SAMPLES_EPOCH" \
  --log_level info \
  --progress_table_output logs/train_1stBatch_ctc.csv \
  models/model_batch1.t7 models/symbols.txt \
  lists/train_1stBatch_lines.lst lists/1stBatch_gt_chars.tab \
  lists/valid_1stBatch_lines.lst lists/1stBatch_gt_chars.tab \
  &> logs/train_1stBatch_ctc.log;


### Extract line images from test ###
echo "Extracting test text line images";
for list in 38 12; do
  textFeats --cfg feats.cfg --outdir lines/test --featlist data/TEST/$list-pages-dataset/*.xml \
    | tee lists/test-${list}_lines.lst;
done 2> logs/feats_test.log > lists/test-all_lines.lst;

### Extract text word level ground truth transcripts ###
echo "Extracting test word level ground truth";
for list in 38 12; do
  ls data/TEST/$list-pages-dataset/*.xml \
    | run_parallel -p no -e yes -T $(nproc) -l - \
        htrsh_pagexml_textequiv '{*}' -f tab \
    > lists/test-${list}_gt_words.tab;
done

### Function to convert character recognition output to words ###
decode_chars_to_words () {
  gawk -v SPACE="$htrsh_symb_space" '
      BEGIN { symb[SPACE] = " "; }
      { if ( ARGIND == 1 )
          symb[$2] = $1;
        else {
          printf("%s ",$1);
          for ( n=2; n<=NF; n++ )
            printf( "%s", $n in symb ? symb[$n] : $n );
          printf("\n");
        }
      }' <( echo "$htrsh_special_chars" ) - \
  | sed 's|   *| |g; s|  *$||;'
}

### Recognize text in test using model from batch 1 ###
laia-docker decode \
    --batch_size "$BATCH" \
    --symbols_table models/symbols.txt \
    models/model_batch1.t7 \
    lists/test-all_lines.lst \
  | decode_chars_to_words \
  > decode/test_model1.tab;


### Detect text lines in 2ndBatch ###
for f in data/TRAIN/2ndBatch/*.xml; do
  ff=$(echo $f | sed 's|.*/||; s|\.xml||;');
  echo $ff;
  tesseract-recognize-docker --only-layout $f lines/traindet/$ff.xml;
  ln -s ../../data/TRAIN/2ndBatch/$ff.jpg lines/traindet/$ff.jpg;
done &> logs/linedet_2ndBatch.log;

### Extract detected line images from batch 2 ###
echo "Extracting batch 2 train detected text line images";
textFeats --cfg feats.cfg --outdir lines/traindet --featlist lines/traindet/*.xml \
  > lists/train_2ndBatch_lines.lst 2> logs/feats_train_2ndBatch.log;
xargs identify -format "%w %i\n" < lists/train_2ndBatch_lines.lst \
  | awk '{ if( $1 > 256 && $1 < 5000 ) print $2; }' \
  > lists/train_2ndBatch_lines_for_rec.lst;

### Recognize text in batch 2 detected lines using model from batch 1 ###
laia-docker decode \
    --batch_size "$BATCH" \
    --symbols_table models/symbols.txt \
    models/model_batch1.t7 \
    lists/train_2ndBatch_lines_for_rec.lst \
  > decode/train_2ndBatch_model1.tab;

### Align recognized text from batch 2 ###
for f in data/TRAIN/2ndBatch/*.txt; do
  ff=$(echo $f | sed 's|.*/||; s|\.txt$||;');
  align_text_lines.py --min_length 5 --dist_threshold 0.3 <( htrsh_text_to_chars - -E no -F text_filter < $f ) <( grep "^$ff\." decode/train_2ndBatch_model1.tab );
done > decode/train_2ndBatch_align1.tab;

### Train HTR model using batch 1 and aligned batch 2 starting from previous model ###
echo "Training HTR model using batch 1 and aligned batch 2";
{ cat lists/train_1stBatch_lines.lst;
  awk '{ if($1<0.1) print("lines/traindet/"$2".png"); }' decode/train_2ndBatch_align1.tab;
} > lists/train_align1_lines.lst;
{ cat lists/1stBatch_gt_chars.tab;
  cat decode/train_2ndBatch_align1.tab \
    | awk '{ if($1<0.1) print; }' \
    | sed 's|^[^ ]* ||';
} > lists/align1_gt_chars.tab;
awk '{ for( n=2; n<=NF; n++ ) print $n; }' lists/align1_gt_chars.tab \
  | sort -u \
  | awk '
      { if( ARGIND == 1 ) {
          print;
          seen[$1] = "";
          NUM = $2;
        }
        else {
          if( ! ( $1 in seen ) )
            print($1" "(++NUM));
        }
      }' models/symbols.txt - \
  > models/symbols_align1.txt;
NSYMBOLS=$(sed -n '${ s|.* ||; p; }' models/symbols_align1.txt);
laia-docker reuse-model models/model_batch1.t7 $NSYMBOLS models/model_align1.t7;
laia-docker train-ctc \
  --batch_size "$BATCH_ALIGN" \
  --cer_trim $(awk -v s="$htrsh_symb_space" '{if($1==s){printf("%s",$2);exit;}}' models/symbols.txt) \
  --adversarial_weight "$ADVERSARIAL_WEIGHT" \
  --use_distortions "$USE_DISTORTIONS" \
  --early_stop_epochs "$EARLY_STOP_EPOCHS" \
  --learning_rate "$LEARNING_RATE" \
  --learning_rate_decay "$LEARNING_RATE_DECAY" \
  --num_samples_epoch "$NUM_SAMPLES_EPOCH" \
  --log_level info \
  --progress_table_output logs/train_align1_ctc.csv \
  models/model_align1.t7 models/symbols_align1.txt \
  lists/train_align1_lines.lst lists/align1_gt_chars.tab \
  lists/valid_1stBatch_lines.lst lists/1stBatch_gt_chars.tab \
  &> logs/train_align1_ctc.log;

### Recognize text in batch 2 detected lines using model from align 1 ###
laia-docker decode \
    --batch_size "$BATCH" \
    --symbols_table models/symbols_align1.txt \
    models/model_align1.t7 \
    lists/train_2ndBatch_lines_for_rec.lst \
  > decode/train_2ndBatch_model2_align1.tab;

### Align recognized text from batch 2 ###
for f in data/TRAIN/2ndBatch/*.txt; do
  ff=$(echo $f | sed 's|.*/||; s|\.txt$||;');
  align_text_lines.py --min_length 5 --dist_threshold 0.3 <( htrsh_text_to_chars - -E no -F text_filter < $f ) <( grep "^$ff\." decode/train_2ndBatch_model2_align1.tab );
done > decode/train_2ndBatch_align2.tab;


### Train HTR model using batch 1 and aligned batch 2 starting from previous model ###
echo "Training HTR model using batch 1 and aligned batch 2";
{ cat lists/train_1stBatch_lines.lst;
  awk '{ if($1<0.1) print("lines/traindet/"$2".png"); }' decode/train_2ndBatch_align2.tab;
} > lists/train_align2_lines.lst;
{ cat lists/1stBatch_gt_chars.tab;
  cat decode/train_2ndBatch_align2.tab \
    | awk '{ if($1<0.1) print; }' \
    | sed 's|^[^ ]* ||';
} > lists/align2_gt_chars.tab;
awk '{ for( n=2; n<=NF; n++ ) print $n; }' lists/align2_gt_chars.tab \
  | sort -u \
  | awk '
      { if( ARGIND == 1 ) {
          print;
          seen[$1] = "";
          NUM = $2;
        }
        else {
          if( ! ( $1 in seen ) )
            print($1" "(++NUM));
        }
      }' models/symbols.txt - \
  > models/symbols_align2.txt;
if [ $(diff models/symbols_align[12].txt | wc -l) = 0 ]; then
  LEARNING_RATE_ALIGN=$(echo 0.1*$LEARNING_RATE | bc -l);
  cp -p models/model_align1.t7 models/model_align2.t7;
else
  LEARNING_RATE_ALIGN=$LEARNING_RATE;
  NSYMBOLS=$(sed -n '${ s|.* ||; p; }' models/symbols_align2.txt);
  laia-docker reuse-model models/model_align1.t7 $NSYMBOLS models/model_align2.t7;
fi
laia-docker train-ctc \
  --batch_size "$BATCH_ALIGN" \
  --cer_trim $(awk -v s="$htrsh_symb_space" '{if($1==s){printf("%s",$2);exit;}}' models/symbols.txt) \
  --adversarial_weight "$ADVERSARIAL_WEIGHT" \
  --use_distortions "$USE_DISTORTIONS" \
  --early_stop_epochs "$EARLY_STOP_EPOCHS" \
  --learning_rate "$LEARNING_RATE_ALIGN" \
  --learning_rate_decay "$LEARNING_RATE_DECAY" \
  --num_samples_epoch "$NUM_SAMPLES_EPOCH" \
  --log_level info \
  --progress_table_output logs/train_align2_ctc.csv \
  models/model_align2.t7 models/symbols_align2.txt \
  lists/train_align2_lines.lst lists/align2_gt_chars.tab \
  lists/valid_1stBatch_lines.lst lists/1stBatch_gt_chars.tab \
  &> logs/train_align2_ctc.log;

### Recognize text in batch 2 detected lines using model from align 2 ###
laia-docker decode \
    --batch_size "$BATCH" \
    --symbols_table models/symbols_align2.txt \
    models/model_align2.t7 \
    lists/train_2ndBatch_lines_for_rec.lst \
  > decode/train_2ndBatch_model3_align2.tab;

### Align recognized text from batch 2 ###
for f in data/TRAIN/2ndBatch/*.txt; do
  ff=$(echo $f | sed 's|.*/||; s|\.txt$||;');
  align_text_lines.py --min_length 5 --dist_threshold 0.3 <( htrsh_text_to_chars - -E no -F text_filter < $f ) <( grep "^$ff\." decode/train_2ndBatch_model3_align2.tab );
done > decode/train_2ndBatch_align3.tab;


### Train HTR model using all batch 1 (no validation) and aligned batch 2 starting from previous model ###
echo "Training HTR model using batch 1 and aligned batch 2";
{ cat lists/train_1stBatch_lines.lst lists/valid_1stBatch_lines.lst;
  awk '{ if($1<0.1) print("lines/traindet/"$2".png"); }' decode/train_2ndBatch_align3.tab;
} > lists/train_final_lines.lst;
cp -p models/symbols_align2.txt models/symbols_final.txt;
{ cat lists/1stBatch_gt_chars.tab;
  cat decode/train_2ndBatch_align3.tab \
    | awk '
        { if( ARGIND == 1 )
            symbs[$1]="";
          else {
            for(n=3;n<=NF;n++)
              if(!($n in symbs))
                $n = "";
            if($1<0.1) print;
          }
        }' models/symbols_final.txt - \
    | sed 's|^[^ ]* ||';
} > lists/final_gt_chars.tab;
cp -p models/model_align2.t7 models/model_final.t7;
laia-docker train-ctc \
  --batch_size "$BATCH_ALIGN" \
  --cer_trim $(awk -v s="$htrsh_symb_space" '{if($1==s){printf("%s",$2);exit;}}' models/symbols.txt) \
  --adversarial_weight "$ADVERSARIAL_WEIGHT" \
  --use_distortions "$USE_DISTORTIONS" \
  --early_stop_epochs "$EARLY_STOP_EPOCHS" \
  --learning_rate "$LEARNING_RATE_FINAL" \
  --learning_rate_decay "$LEARNING_RATE_DECAY" \
  --num_samples_epoch "$NUM_SAMPLES_EPOCH" \
  --best_criterion train_loss \
  --max_epochs "$MAX_EPOCHS_FINAL" \
  --log_level info \
  --progress_table_output logs/train_final_ctc.csv \
  models/model_final.t7 models/symbols_final.txt \
  lists/train_final_lines.lst lists/final_gt_chars.tab \
  &> logs/train_final_ctc.log;

### Recognize text in test using final model ###
laia-docker decode \
    --batch_size "$BATCH" \
    --symbols_table models/symbols_final.txt \
    models/model_final.t7 \
    lists/test-all_lines.lst \
  | decode_chars_to_words \
  > decode/test_model_final.tab;


### Recongition with n-gram language model ###
echo "Training n-gram character language model";

### Estimate network outputs priors ###
laia-docker force-align \
  --skip_alignments true \
  --batch_size "$BATCH" \
  models/model_final.t7 models/symbols_final.txt \
  lists/train_final_lines.lst lists/final_gt_chars.tab \
  models/align_final.txt models/priors_final.txt;

### Prepare training text ###
{ cut -d " " -f 2- < lists/1stBatch_gt_chars.tab;
  cat data/TRAIN/2ndBatch/*.txt \
    | htrsh_text_to_chars - -F text_filter \
    | awk '
        { if( ARGIND == 1 )
            symbs[$1] = "";
          else {
            for(n=1;n<=NF;n++)
              if( ! ( $n in symbs ) )
                $n = "";
            print;
          }
        }' models/symbols_final.txt - \
    | sed 's|   *| |g';
} > lists/train_lm_chars.txt;

### prepare Lexic (L) ###
mkdir -p models/lm/data/train;
prepare_lang_cl-ds.sh models/lm/data/train models/symbols_final.txt "$BLANK_SYMB" "$htrsh_symb_space" "$DUMMY_CHAR";

### prepare LM (G) ###
mitlm-docker estimate-ngram -text lists/train_lm_chars.txt -write-lm models/lm/data/train/lang/LM.arpa -order $NGRAM_ORDER -smoothing ModKN;
prepare_lang_test-ds.sh models/lm/data/train/lang/LM.arpa models/lm/data/train/lang \
  models/lm/data/train/lang_test "$DUMMY_CHAR";

### create HMM topology file ###
mkdir models/lm/train;
phones_list=( $(cat "models/lm/data/train/lang_test/phones/"{,non}silence.int) );
featdim=$(sed -n '${ s|.* ||; p; }' "models/symbols_final.txt");
dummyID=$(awk -v d="$DUMMY_CHAR" '{if (d==$1) print $2}' "models/lm/data/train/lang/phones.txt");
blankID="0";
create_proto_rnn-ds.sh "$featdim" "$HMM_LOOP_PROB" "$HMM_BLANK_PROB" "models/lm/train" "$dummyID" "$blankID" "${phones_list[@]}";

### Compose FSTs ###
mkdir models/lm/test;
mkgraph.sh --mono --transition-scale 1.0 --self-loop-scale 1.0 \
  "models/lm/data/train/lang_test" "models/lm/train/new.mdl" "models/lm/train/new.tree" "models/lm/test/graph";
mv "models/lm/train/new.mdl" "models/model.mdl";
mv "models/lm/test/graph/HCLG.fst" "models";

### Create alignment to char table ###
kaldi-docker gmm-copy --print-args=false --binary=false "models/model.mdl" - \
  | awk -v symbols="models/symbols_final.txt" '
      BEGIN {
        while( getline < symbols > 0 )
          if( $2 > 1 ) {
            symb[$2] = $1;
            NCHARS = $2 > NCHARS ? $2 : NCHARS ;
          }
        NCHARS--;
      }
      /^<Triples>/,/^<\/Triples>/ {
        if( $1 == "<Triples>" ) {
          ### num_models = num_chars + 1 (DUMMY) ###
          ### 2 emitting states per char and one for DUMMY ###
          if( $2 != 1+2*NCHARS )
            exit(1);
          next;
        }
        ### 2 transitions for all models ###
        printf( "%d %s\n", ++IDX, $3 == 0 ? 1 : ($1+1)" "symb[$1+1] );
        printf( "%d %s\n", ++IDX, $3 == 0 ? 1 : ($1+1)" "symb[$1+1] );
        if( $1 > NCHARS )
          exit(0);
      }' \
  > "models/ali-to-char.txt";

### Compute posterior matrices ###
laia-docker netout \
    --batch_size "$BATCH" \
    --output_format htk \
    --output_transform softmax \
    models/model_final.t7 lists/test-all_lines.lst decode/postprob;

### Generate 1-best recognition with final model including the LM ###
{ find -L decode/postprob -name '*.fea' \
    | python2.7 ./bin/kaldi-htk-to-ark.py --loglkh models/priors_final.txt --alpha "$LOGLKH_ALPHA_FACTOR" - - \
    | kaldi-docker latgen-faster-mapped-parallel --print-args=false --verbose=2 --num-threads=$(nproc) \
        --acoustic-scale=$ASF --max-active=$MAX_NUM_ACT_STATES --beam=$BEAM_SEARCH --lattice-beam=$LATTICE_BEAM \
        models/model.mdl models/HCLG.fst ark:- ark:- \
    | kaldi-docker lattice-scale --print-args=false --inv-acoustic-scale=$GSF ark:- ark:- \
    | kaldi-docker lattice-add-penalty --print-args=false --word-ins-penalty=$WIP ark:- ark:- \
    | kaldi-docker lattice-to-nbest --print-args=false --n=1 ark:- ark,t:- \
    | kaldi-nbest-to-align --ali-to-char models/ali-to-char.txt --space "$htrsh_symb_space" \
    | python2.7 ./bin/kaldi-align-to-words.py --htk --postprob decode/postprob fea --space "$htrsh_symb_space" --special <( echo "$htrsh_special_chars" ) - models/symbols_final.txt \
    | python2.7 ./bin/kaldi-nbest-word-score.py --space "$htrsh_symb_space" --scofact 0.1 --logfact 0.5 - \
    | awk '{printf("%s",$1);for(n=6;n<=NF;n+=4)if($n!="'"$htrsh_symb_space"'")printf(" %s",$n);printf("\n");}';
} 2> logs/decode_lm.log > decode/test_model_final_lm.tab;


### Function for evaluating ###
evaluate_results () {
  local GT="$1";
  local HYP="$2";
  local TMP_GT=$(mktemp --tmpdir=.);
  local TMP_HYP=$(mktemp --tmpdir=.);

  htrsh_text_to_chars "$GT" -E no -f tab > "$TMP_GT";
  htrsh_text_to_chars "$HYP" -E no -f tab > "$TMP_HYP";
  kaldi-docker compute-wer --print-args=false --text --mode=present ark:"$TMP_GT" ark:"$TMP_HYP" \
    | sed -n '/^%WER/{ s|%WER|%CER|; p; }';

  paste -d " " <( awk '{print $1}' "$GT" ) <( sed 's|^[^ ]* ||' "$GT" | sed_tokenizer ) > "$TMP_GT";
  paste -d " " <( awk '{print $1}' "$HYP" ) <( sed 's|^[^ ]* ||' "$HYP" | sed_tokenizer ) > "$TMP_HYP";
  kaldi-docker compute-wer --print-args=false --text --mode=present ark:"$TMP_GT" ark:"$TMP_HYP" \
    | sed -n '/^%WER/p';

  rm "$TMP_GT" "$TMP_HYP";
}

{ ### Evaluate test recognition using model from batch 1 ###
  for list in 38 12; do
    echo "=== Batch 1 model only NN list=$list ===";
    evaluate_results lists/test-${list}_gt_words.tab decode/test_model1.tab;
  done

  ### Evaluate test recognition using final model ###
  for list in 38 12; do
    echo "=== Final model only NN list=$list ===";
    evaluate_results lists/test-${list}_gt_words.tab decode/test_model_final.tab;
  done

  ### Evaluate test recognition using final model including the LM ###
  for list in 38 12; do
    echo "=== Final model with LM list=$list ===";
    evaluate_results lists/test-${list}_gt_words.tab decode/test_model_final_lm.tab;
  done
} > RESULTS.txt;
