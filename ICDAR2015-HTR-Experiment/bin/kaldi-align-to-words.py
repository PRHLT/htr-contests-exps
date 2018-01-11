#!/usr/bin/env python

##
## A tool that converts a frame alignment into a word alignment.
##
## @author Mauricio Villegas <mauricio_ville@yahoo.com>
## @license MIT License
##

import sys, argparse
import numpy as np
import struct

### Parse input arguments ###
parser = argparse.ArgumentParser(description='Converts a frame alignment into a word alignment')
parser.add_argument('-s','--space',metavar='SYMB',default='{space}',
                    help="symbol for space (default: %(default)s)")
parser.add_argument('-b','--blank',metavar='SYMB',default='{blank}',
                    help="symbol for blank (default: %(default)s)")
parser.add_argument('-S','--special',metavar='FILE',default=False,
                    help="list of special symbols (default: %(default)s)")
parser.add_argument('-p','--postprob',metavar=('DIR','EXT'),nargs=2,
                    help="posteriors for scoring, providing directory and extension of files")
parser.add_argument('-k','--htk',action='store_true',default=False,
                    help="read posteriors in HTK format (default: %(default)s)")
parser.add_argument('-i','--ipostprob',action='store_true',default=False,
                    help="inline posteriors (default: %(default)s)")
parser.add_argument('alignments',
                    help="file with alignment information (i.e. output from ali-to-pdf)")
parser.add_argument('charlist',
                    help="file with character list")
args = parser.parse_args()
#args = parser.parse_args('--postprob rnnsoftmax_valid fea - test/graph/phones.txt'.split())

### Function for reading HTK matrix files ###
def read_htk( fname ):
  with open( fname, "rb" ) as fh:
    nSamples, sampPeriod, sampSize, parmKind = struct.unpack( ">IIHH", fh.read(12) )
    mat = np.reshape( np.fromfile( fh, dtype=np.float32 ).byteswap(), (-1,sampSize/4) )
    if mat.shape[0] != nSamples:
      raise IOError('HTK file appears to be truncated: '+fname)
    return mat

### Auxiliary variables ###
fpostprob = ''
args.postprob = False if args.ipostprob else args.postprob
blank = 0

### Load special character list ###
speclist = {}
if args.special:
  with open(args.special) as input_file:
    for line in input_file:
      spec = line.split()
      if len(spec) == 2:
        speclist[spec[1]] = spec[0]

### Load character list ###
charlist = {}
with open(args.charlist) as input_file:
  for line in input_file:
    [ char, num ] = line.split()
    if char in speclist:
      char = speclist[char]
    charlist[int(num)] = char
    if char == args.blank:
      blank = int(num)

### Loop for processing each alignment ###
with sys.stdin if args.alignments == '-' else open(args.alignments) as input_file:
  for line in input_file:
    [ samp, logl, idx ] = line.split(' ',2)
    if args.ipostprob:
      postprob = [ float(i.split(':')[1]) for i in idx.split() ]
    idx = [ int(i.split(':')[0]) for i in idx.split() ]

    ### Load posterior probability matrix ###
    if args.postprob and samp != fpostprob:
      fpostprob = samp
      try:
        if args.htk:
          postprob = read_htk( args.postprob[0]+'/'+samp+'.'+args.postprob[1] )
        else:
          postprob = np.loadtxt( args.postprob[0]+'/'+samp+'.'+args.postprob[1] )
          #with open(args.postprob[0]+'/'+samp+'.'+args.postprob[1],"r") as file:
          #  postprob = [[float(x) for x in line.split()] for line in file]
      except:
        raise IOError('problems reading posterior matrix: '+args.postprob[0]+'/'+samp+'.'+args.postprob[1])

    ### Get ranges and scores for characters ###
    SYM = []
    RNG = []
    SCO = []
    prev = 0
    for n, idxn in enumerate(idx):
      if idxn != blank:
        if not idxn in charlist:
          raise ValueError('no character for index '+str(idxn)+'\n')
        sco = postprob[n] if args.ipostprob else postprob[n][idxn] if args.postprob else 1
        if idxn != prev:
          SYM.append( charlist[idxn] )
          RNG.append( [ n, n ] )
          SCO.append( [ 1, sco ] )
        else:
          RNG[-1][1] = n
          SCO[-1][1] = max( SCO[-1][1], sco )
      prev = idxn

    ### Get ranges and scores for words and spaces ###
    n = 0
    nwords = 0
    while n < len(SYM):
      if SYM[n] != args.space:
        nwords += 1
        while n < len(SYM)-1 and SYM[n+1] != args.space:
          SYM[n] += SYM[n+1]
          RNG[n][1] = RNG[n+1][1]
          SCO[n][0] += SCO[n+1][0]
          SCO[n][1] += SCO[n+1][1]
          del SYM[n+1], RNG[n+1], SCO[n+1]
      else:
        while n < len(SYM)-1 and SYM[n+1] == args.space:
          RNG[n][1] = RNG[n+1][1]
          SCO[n][0] += SCO[n+1][0]
          SCO[n][1] += SCO[n+1][1]
          del SYM[n+1], RNG[n+1], SCO[n+1]
      n += 1

    if nwords > 0:
      ### Enlarge spaces ###
      for n in range(len(SYM)):
        if SYM[n] == args.space:
          RNG[n][0] = min( len(idx)-1, 0 if n == 0 else RNG[n-1][1]+1 )
          RNG[n][1] = max( 0, len(idx)-1 if n == len(RNG)-1 else RNG[n+1][0]-1 )

      ### Add extreme spaces ###
      if SYM[0] != args.space:
        SYM.insert( 0, args.space )
        RNG.insert( 0, [ 0, max(0,RNG[0][0]-1) ] )
        SCO.insert( 0, [ 1, 1 ] )
      if SYM[-1] != args.space:
        SYM.append( args.space )
        RNG.append( [ min(len(idx)-1,RNG[-1][1]+1), len(idx)-1 ] )
        SCO.append( [ 1, 1 ] )

    # @todo space for empty hypothesis?
    #else:
    #  SYM.append( args.space )
    #  RNG.append( [ 0, len(idx)-1 ] )
    #  SCO.append( [ 1, 1 ] )

    ### Output result ###
    sys.stdout.write(samp+'\t'+str(len(idx))+'\t'+logl)
    for n in range(len(SCO)):
      sys.stdout.write('\t'+str(RNG[n][0])+' '+str(RNG[n][1])+' '+SYM[n]+' '+str(SCO[n][1]/SCO[n][0]))
    sys.stdout.write('\n')
