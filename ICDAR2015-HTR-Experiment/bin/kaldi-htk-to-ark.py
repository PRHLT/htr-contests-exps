#!/usr/bin/env python

##
## A tool that convert HTK matrices into a Kaldi binary ark file.
##
## @author Mauricio Villegas <mauricio_ville@yahoo.com>
## @license MIT License
##

import sys, argparse
import numpy as np
import struct
import math
import re

### Parse input arguments ###
parser = argparse.ArgumentParser(description='Convert HTK matrices into a Kaldi binary ark file')
parser.add_argument('-l','--loglkh',metavar='PRIORS',default='',
                    help="compute log-likelihoods using given priors")
parser.add_argument('-a','--alpha',type=float,default=0.3,
                    help="p(x|s) = P(s|x) / P(s)^LOGLKH_ALPHA (default: %(default)s)")
parser.add_argument('htklist',
                    help="list of HTK feature files, '-' for stdin")
parser.add_argument('arkfile',
                    help="file for output ark, '-' for stdout")
args = parser.parse_args()
#args = parser.parse_args('--postprob rnnsoftmax_valid fea - test/graph/phones.txt'.split())

### Function for reading HTK matrix files ###
def read_htk( fname ):
  with open( fname, "rb" ) as fh:
    nSamples, sampPeriod, sampSize, parmKind = struct.unpack( ">IIHH", fh.read(12) )
    mat = np.reshape( np.fromfile( fh, dtype=np.float32 ).byteswap(), (-1,sampSize//4) )
    if mat.shape[0] != nSamples:
      raise IOError('HTK file appears to be truncated: '+fname)
    return mat

### Function for printing a matrix in kaldi ark format ###
def print_ark( fh, samp, mat ):
  fh.write( (samp+' \0BFM ').encode() )
  fh.write( '\04'.encode() + struct.pack('I',mat.shape[0]) )
  fh.write( '\04'.encode() + struct.pack('I',mat.shape[1]) )
  mat.tofile( fh, sep="" )

### Read priors for log-likelihood mode ###
loglkh = True if args.loglkh != '' else False
if loglkh:
  logprior = []
  zeroprior = []
  with open(args.loglkh) as input_file:
    for line in input_file:
      prior = float(line.split()[-1])
      logprior.append( -float('inf') if prior == 0.0 else math.log(prior)*args.alpha )
      zeroprior.append( True if prior == 0.0 else False )

### Regular expressions for obtaining sample identifier ###
regex1 = re.compile(r"^.*/")
regex2 = re.compile(r"\.[^.]*$")

### Process data ###
#with ( sys.stdout.buffer if hasattr(sys.stdout,'buffer') else sys.stdout ) if args.arkfile == '-' else open(args.arkfile,'wb') as output_file:
with sys.stdout if args.arkfile == '-' else open(args.arkfile,'wb') as output_file:
  with sys.stdin if args.htklist == '-' else open(args.htklist) as input_file:
    ### Loop for processing each HTK matrix file ###
    for line in input_file:
      line = line.strip()
      samp = regex2.sub( '', regex1.sub('',line) )
      mat = read_htk( line )

      ### Compute log-likelihoods ###
      if loglkh:
        if len(logprior) != mat.shape[1]:
          raise ValueError('number of priors and matrix columns differs: '+samp)
        for n in range(len(logprior)):
          if zeroprior[n]:
            mat[:,n] = -743.747
          else:
            mat[:,n] = np.log(mat[:,n]) - logprior[n]

      ### Output matrix ###
      print_ark( output_file, samp, mat )
