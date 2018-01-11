Handwritten text recognition experiment using the ICDAR 2015 dataset

# Basic system requirements

- NVIDIA GPU with at least 6GB of memory
- Recent linux distribution (only tested in Ubuntu but should work in others)
- CUDA 8
- docker-ce (docker runnable without the need of sudo)
- nvidia-docker

# Steps for running the experiment

## Download and extract dataset

In the same directory as this readme, download and extract the dataset.

    wget https://zenodo.org/record/1136294/files/ICDAR-HTR-Competition-2015-data.zip
    unzip ICDAR-HTR-Competition-2015-data.zip

## Install required software

Install some dependencies.

    sudo apt-get install xmlstarlet gawk python python-pip
    sudo pip install numpy editdistance

Install textFeats.

    docker pull mauvilsa/textfeats:2018.01.06
    docker tag mauvilsa/textfeats:2018.01.06 textfeats:active
    docker run --rm -u $(id -u):$(id -g) -v $(pwd):$(pwd) textfeats:active bash -c "cp /usr/local/bin/textFeats-docker $(pwd)/bin"

Install Laia.

    docker pull mauvilsa/laia:2018.01.09-cuda8.0-ubuntu16.04
    docker tag mauvilsa/laia:2018.01.09-cuda8.0-ubuntu16.04 laia:active
    docker run --rm -u $(id -u):$(id -g) -v $(pwd):$(pwd) laia:active bash -c "cp /usr/local/bin/laia-docker $(pwd)/bin"

Install Kaldi.

    docker pull mauvilsa/kaldi:2018.01.07
    docker tag mauvilsa/kaldi:2018.01.07 kaldi:active
    docker run --rm -u $(id -u):$(id -g) -v $(pwd):$(pwd) kaldi:active bash -c "cp /usr/local/bin/kaldi-docker $(pwd)/bin"

Install MITLM.

    docker pull mauvilsa/mitlm:0.4.2
    docker tag mauvilsa/mitlm:0.4.2 mitlm:active
    docker run --rm -u $(id -u):$(id -g) -v $(pwd):$(pwd) mitlm:active bash -c "cp /usr/local/bin/mitlm-docker $(pwd)/bin"

Install tesseract-recognize.

    docker pull mauvilsa/tesseract-recognize:2017.12.18-github-master
    docker tag mauvilsa/tesseract-recognize:2017.12.18-github-master tesseract-recognize:active
    docker run --rm -u $(id -u):$(id -g) -v $(pwd):$(pwd) tesseract-recognize:active bash -c "cp /usr/local/bin/tesseract-recognize-docker $(pwd)/bin"

## Run the experiment script

The experiment script is the file run_exp.sh. If the script is run directly it might work without problems. However, the full execution can take a couple of days and there is a possibility that there is some dependency not included above. So it might be better to run the experiment step by step by copy pasting checking that the execution works correctly.

In the end a RESULTS.txt file would be created that includes the performance measures of the system for the two test sets (38 and 12).

# Contact person

Mauricio Villegas <mauricio_ville@yahoo.com>
