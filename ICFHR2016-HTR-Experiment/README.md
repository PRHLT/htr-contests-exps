Handwritten text recognition experiment using the ICFHR 2016 dataset

# Basic system requirements

- NVIDIA GPU with at least 6GB of memory
- Recent linux distribution (only tested in Ubuntu but should work in others)
- CUDA 8

# Steps for running the experiment

## Download and extract dataset

In the same directory as this readme, download and extract the dataset.

    wget https://zenodo.org/record/1164045/files/Train-And-Val-ICFHR-2016.tgz
    tar xzf Train-And-Val-ICFHR-2016.tgz
    wget https://zenodo.org/record/1164045/files/Test-ICFHR-2016.tgz
    tar xzf Test-ICFHR-2016.tgz

## Install required software

    textFeats: https://github.com/mauvilsa/textfeats
         Laia: https://github.com/jpuigcerver/Laia
        kaldi: https://github.com/kaldi-asr/kaldi
        SRILM: http://www.speech.sri.com/projects/srilm/

       Others: sudo apt-get install xmlstarlet gawk python

## Run the experiment script

The experiment script is the file run_exp.sh. If the script is run directly it might work without problems. However, the full execution can take a couple of days and there is a possibility that there is some dependency not included above. So it might be better to run the experiment step by step by copy pasting checking that the execution works correctly.

In the end a RESULTS.txt file would be created that includes the performance measures of the system for the test set.

# Contact person

Alejandro H. Toselli <ahector@prhlt.upv.es>
