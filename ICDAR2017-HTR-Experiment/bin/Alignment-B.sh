#!/bin/bash 
set -e;

#Train a line detection model and then segment the Train-B material
#Recognize the detected lines with a model trained using the Train-A material
#Alignment of the lines with the available trainscripts for the Train-B
#Author: Verónica Romero <vromero@prhlt.upv.es>

#Download the training data                                                                                                                                                 
#-Train-A: https://doi.org/10.5281/zenodo.439807

### Install textFeats ###
# https://github.com/mauvilsa/textfeats

### Install Laia ###
# https://github.com/jpuigcerver/Laia

### Install Kaldi ###
# https://github.com/kaldi-asr/kaldi

### Install SRILM toolkit ###
# http://www.speech.sri.com/projects/srilm/

### Install BaseLinePage toolkit ###
# https://github.com/PRHLT/BaseLinePage.git

### Install imgtxtenh toolkit ###
#https://github.com/mauvilsa/imgtxtenh

### Install other dependencies ###
# sudo apt-get install xmlstarlet gawk python

#Add bin to PATH 
export PATH=$PATH:$(pwd)/bin
. htrsh.inc.sh

############################################################################################################
###### Training a line segmentation system using Train-A and performing the segmentation of Train-B ########
############################################################################################################



#Trainig a line segmentation system using Train-A 
[ -d $(pwd)/data/Train-B/page ] || {
mkdir $(pwd)/data/Train-B/page  
cp $(pwd)/data/Train-B/batch1/page/*xml $(pwd)/data/Train-B/page 
cp $(pwd)/data/Train-B/batch2/page/*xml $(pwd)/data/Train-B/page
ln -sf $(pwd)/data/Train-B/batch1/*jpg $(pwd)/data/Train-B/page
ln -sf $(pwd)/data/Train-B/batch2/*jpg $(pwd)/data/Train-B/page
}

cd WORK
[ -d Segmentation-B ] || mkdir Segmentation-B
cd Segmentation-B 

[ -d prep ] || { 
mkdir prep
for f in ../../data/Train-A/page/*.jpg; do
 n=`basename $f`;
 imgtxtenh -i $f -o prep/${n} -w 30 -p 0.7 -s 0.5 -S 1;
done
}

for f in ../../data/Train-A/page/*xml; do echo `basename ${f/.xml/}`; done  > corpus.lst

[ -d Trees ] || {
mkdir Trees
cp -l prep/*.jpg ../../data/Train-A/page/*xml  Trees 
trainForestNPages.sh corpus.lst Trees/ 50 ../../segmentation.cnf 
}

#Using the trained model the pages of the Train-B are segmented
[ -d Segmented ] || {

for f in ../../data/Train-B/page/*.jpg; do 
 n=`basename $f`;
 ~/HTR/SRC/imgtxtenh/imgtxtenh -i $f -o prep/${n} -w 30 -p 0.7 -s 0.5 -S 1; 
done

for f in ../../data/Train-B/page/*xml ; do echo `basename ${f/.xml/}`; done > Test.lst

mkdir Segmented 
cd Segmented
ln -s ../prep/*jpg .
ln -s ../../../data/Train-B/page/*xml .
cd ..
}

[ -d Segmented_icdar_50.ert ] || {
test.sh Test.lst Segmented/ Trees/icdar_50.ert ../../segmentation.cnf
} 

cd Segmented_icdar_50.ert
[ -d NewPage ] || { mkdir NewPage

for f in *xml; do 
page_format_generate_contour -a 75 -d 25 -p $f -o NewPage/$f ; 
done
}
cd ../..

#Extracting the detected lines
[ -d Lines-B ] || {

cd ./Segmentation-B/Segmented_icdar_50.ert/NewPage

[ -d reorderXML ] || { mkdir reorderXML

for f in *xml; do 
        htrsh_pagexml_sort_lines < $f > k.xml;
        htrsh_pagexml_relabel < k.xml > reorderXML/$f; 
done

cd reorderXML
ln -s ../../../../../data/Train-B/page/*.jpg .
cd ..
}

cd reorderXML

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


mkdir ../../../../Lines-B


export htrsh_valschema="no"

for i in *xml
do
  N=`basename $i .xml`
  textFeats --cfg <( echo "$textFeats_cfg" ) --outdir ../../../../Lines-B/ $i
done
cd ../../../../
}

############################################################################################################
###### Recognition of Train-B using the model trained with Train-A material ################################
############################################################################################################


[ -d decode-B ] || {
mkdir decode-B
cd decode-B
ln -s ../Lines-B/ data
for f in data/*.png; do  echo $f; done > batch1-2.lst
laia-decode --batch_size 3  --symbols_table ../lang-A/char/symb.txt ../models-A/train.t7 batch1-2.lst  > test.txt

awk '{
  printf("%s ", $1);
  for (i=2;i<=NF;++i) {
    if ($i == "<space>")
      printf(" ");
    else
      printf("%s", $i);
  }
  printf("\n");
}' test.txt > wordtest.txt;
cd ..
}



############################################################################################################
###### Alignment of detected lines with the transcription available ########################################
############################################################################################################

[ -d Alignments-B ] || mkdir Alignments-B
cd Alignments-B

[ -d TXT  ] || {

mkdir TXT

for f in ../../data/Train-B/page/*xml; do awk '{if($0~"<Unicode>"){trans="si";};if(trans=="si"){print $0;};if($0~"</Unicode>"){trans="no";}}' $f > TXT/`basename ${f/xml/txt}`; done 

cd TXT
for f in *; do sed 's/<Unicode>//g;s/<\/Unicode>//g' -i $f; done 
for f in *; do awk '{if(NF>0) print $0 > "k"}' $f ; mv k $f; done 

cd ..
}
[ -f wordtest.txt ] || ln -s ../decode-B/wordtest.txt .

[ -d REC ] || {

mkdir REC

for i in {1..223739};do 
  head -$i wordtest.txt | tail -1 |   awk '{for(i=2;i<NF;i++) printf($i" ") > "REC/"$1".rec"; print $NF > "REC/"$1".rec"}' 
done
}


[ -d HYP ] || pre-RecHyp.sh TXT REC HYP 


for t in TXT/*.txt; do
n=`basename ${t/.txt/}`;
align-GTvsHYP -v 2 -t 0.8 $t HYP/${n}_1hyp.inf  >> alineamientos.txt
done


cd TXT
for f in *; do  awk -v n=${f/.txt/} '{if(NF>0){print $0 > n"_"NR".txt"}}' $f; done
cd ..


calcula-align.sh alineamientos.txt 0.6

chmod +x alineamiento_0.6.sh
cd TXT
../alineamiento_0.6.sh

cd ..
mkdir TXT_0.6
mv TXT/010*.tab TXT_0.6
mv TXT/011*.tab TXT_0.6
mv TXT/012*.tab TXT_0.6
mv TXT/013*.tab TXT_0.6
mv TXT/014*.tab TXT_0.6
mv TXT/015*.tab TXT_0.6
mv TXT/016*.tab TXT_0.6
mv TXT/017*.tab TXT_0.6
mv TXT/018*.tab TXT_0.6
mv TXT/019*.tab TXT_0.6
mv TXT/02*.tab TXT_0.6
mv TXT/*.tab TXT_0.6














