#!/usr/bin/env python

##
## A tool that aligns text lines based on Levenshtein distance.
##
## @author Mauricio Villegas <mauricio_ville@yahoo.com>
## @license MIT License
##

import sys, argparse
import numpy as np
import editdistance

### Parse input arguments ###
parser = argparse.ArgumentParser(description='Aligns text lines based on Levenshtein distance')
parser.add_argument('-s','--space',metavar='SYMB',default='{space}',
                    help="symbol for space (default: %(default)s)")
parser.add_argument('-m','--min_length',type=float,default=1,
                    help="minimum string length to consider (default: %(default)s)")
parser.add_argument('-t','--dist_threshold',type=float,default=0.1,
                    help="levenshtein distance threshold for matching (default: %(default)s)")
parser.add_argument('gt_strings',
                    help="file with ground truth strings (each line a string, symbols separated by space)")
parser.add_argument('rec_tab',
                    help="file with kaldi table with recognitions (each line id followed by symbols separated by space)")
args = parser.parse_args()
#args = parser.parse_args('--min_length 5 --dist_threshold 0.3 gt_strings rec_tab'.split())

### Read ground truth strings ###
gt_strings = []
with sys.stdin if args.gt_strings == '-' else open(args.gt_strings) as input_file:
    for line in input_file:
        line = line.strip().split()
        if len(line) >= args.min_length:
            gt_strings.append( line )

### Read recognition strings table ###
rec_ids = []
rec_strings = []
with sys.stdin if args.rec_tab == '-' else open(args.rec_tab) as input_file:
    for line in input_file:
        line = line.strip().split()
        if len(line) < 3:
            continue
        rec_ids.append(line[0])
        del line[0]
        if line[0] == args.space:
            del line[0]
        if line[len(line)-1] == args.space:
            del line[len(line)-1]
        rec_strings.append(line)

### Check input non-empty ###
gt_num = len(gt_strings)
rec_num = len(rec_strings)
if gt_num == 0 or rec_num == 0:
    sys.exit()

### Compute pairwise distances ###
dists = np.empty([rec_num, gt_num])
for m in range(0,gt_num):
    gt_string_m = gt_strings[m]
    gt_len_m = len(gt_string_m)
    for n in range(0,rec_num):
        dists[n,m] = editdistance.eval( rec_strings[n], gt_string_m ) / gt_len_m

### Print assigned recognitions to ground truth strings ###
for mm in range(0,gt_num):
    m = np.argmin(dists.min(0))
    n = np.argmin(dists[:,m])
    dist = dists[n,m]
    if dist >= args.dist_threshold:
       break
    dists[n,:] = float('Inf')
    print(str(dist)+' '+rec_ids[n]+' '+args.space+' '+' '.join(gt_strings[m])+' '+args.space)
