#!/bin/bash
set -e;

# Handwritten text recognition experiment using the ICDAR 2017 dataset
#
# Author: Verónica Romero <vromero@prhlt.upv.es>
#
# Requirements:
# - NVIDIA GPU 
# - Recent linux distribution (only tested in Ubuntu but should work in others)
# - CUDA 8

#Download the trainin data 
#-Train-A: https://doi.org/10.5281/zenodo.439807
#-Train-B: https://doi.org/10.5281/zenodo.439811

#Download the test data 
#-Test-A (Track 1): https://doi.org/10.5281/zenodo.821879
#-Test-B1 (Track 2): https://doi.org/10.5281/zenodo.821132
#-Test-B2 (Track 2): https://doi.org/10.5281/zenodo.821143

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

### Install other dependencies ###
# sudo apt-get install xmlstarlet gawk python

### Add bin to PATH ###
export PATH="$(pwd)/bin:$PATH";

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


#Extracting the corpus
[ -d data ] || {
mkdir -p data
mv Test-A.tgz Test-B1.tgz Test-B2.tgz Train-A.tbz2 Train-B_batch1.tbz2 Train-B_batch2.tbz2 data

tar -xzvf  data/Test-A.tgz -C data/
tar -xzvf  data/Test-B1.tgz  -C data/
tar -xzvf  data/Test-B2.tgz -C data/
bunzip2 data/Train-A.tbz2 && tar -xf data/Train-A.tar -C data/
bunzip2 data/Train-B_batch1.tbz2 && tar -xvf data/Train-B_batch1.tar -C data/
bunzip2 data/Train-B_batch2.tbz2 && tar -xvf data/Train-B_batch2.tar -C data/
rm data/*tgz data/*tar
}

#Training a model using the Train-A material
Train-A.sh
echo "The training using the Trian-A material has been completed"


#./Alignment-B.sh

#./Train-AB.sh

#./Recognize-TrackTraditional.sh

#./Recognize-AdvancedTrack.sh
