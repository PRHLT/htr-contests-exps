#!/usr/bin/env python

##
## A tool that computes n-best word scores for a given word alignment.
##
## @author Mauricio Villegas <mauricio_ville@yahoo.com>
## @license MIT License
##

import sys, argparse
import numpy as np
from math import log, exp

### Parse input arguments ###
parser = argparse.ArgumentParser(description='Computes n-best word scores for a given word alignment')
parser.add_argument('-s','--space',metavar='SYMB',default='{space}',
                    help="symbol for space (default: %(default)s)")
parser.add_argument('-f','--scofact',type=float,default=0.1,
                    help="combination factor for combining provided score and the computed (default: %(default)s)")
parser.add_argument('-b','--logfact',type=float,default=0.02,
                    help="log base factor for spreading probabilities (default: %(default)s)")
parser.add_argument('alignments',
                    help="file with alignment information")
args = parser.parse_args()

### Function for splitting sets of consecutive numbers in a list ###
def consecutive( data, stepsize=1 ):
  return [] if len(data) == 0 else np.split( data, np.where(np.diff(data)!=stepsize)[0]+1 )

### Function that computes n-best word scores and prints the results ###
def score_nbest( SAMP, FRAMES, LOGL, SYM, RNG, SCO, DIC ):
  NBEST = len(SYM)
  if NBEST > 0:
    ### Normalize probabilities ###
    PROB = np.array(LOGL) * args.logfact
    for n in range(NBEST):
      totPROB = PROB[n] if n == 0 else PROB[n] + log( 1 + exp(totPROB-PROB[n]) )
    for n in range(NBEST):
      PROB[n] = exp(PROB[n]-totPROB)
    #PROB /= PROB.sum()

    ### Compute word frame probabilities ###
    wordProb = np.zeros(( FRAMES, len(DIC) ))
    for n in range(NBEST):
      PROBn = PROB[n]
      SYMn = SYM[n]
      RNGn = RNG[n]
      for m in range(len(SYMn)):
        ### Skip start/end zero length space ###
        if SYMn[m] == args.space and len(SYMn) > 1:
          if m == 0 and RNGn[m+1][0] == 0:
            continue
          if m == len(SYMn)-1 and RNGn[m-1][1] == FRAMES-1:
            continue
        ### Add probability to word ranges ###
        wordProb[ RNGn[m][0]:1+RNGn[m][1], DIC[SYMn[m]] ] += PROBn

    ### Get maximum of word probabilities ###
    for n in range(len(DIC)):
      idx = consecutive( np.where( wordProb[:,n] > 0 )[0] )
      for m in range(len(idx)):
        wordProb[ idx[m][0]:idx[m][-1]+1, n ] = wordProb[ idx[m][0]:idx[m][-1]+1, n ].max()

    ### Output result ###
    for n in range(NBEST):
      SYMn = SYM[n]
      RNGn = RNG[n]
      SCOn = SCO[n]

      sys.stdout.write(SAMP+'\t'+str(FRAMES)+'\t'+str(PROB[n]))
      for m in range(len(SCOn)):
        sco = args.scofact*SCOn[m] + (1-args.scofact)*wordProb[ RNGn[m][0], DIC[SYMn[m]] ]
        sys.stdout.write('\t'+str(RNGn[m][0])+' '+str(RNGn[m][1])+' '+SYMn[m]+' '+str(sco))
      sys.stdout.write('\n')

    ### Clear variables for next nbest set ###
    LOGL[:] = []
    SYM[:] = []
    RNG[:] = []
    SCO[:] = []
    DIC.clear()

### Initialize nbest set variables ###
setSAMP = ''
setFrames = 0
setLOGL = []
setSYM = []
setRNG = []
setSCO = []
setDIC = {}

### Loop for processing each alignment ###
with sys.stdin if args.alignments == '-' else open(args.alignments) as input_file:
  for line in input_file:
    line = line.split('\t')
    samp = line.pop(0)
    frames = int(line.pop(0))
    logl = float(line.pop(0))

    if setSAMP != samp:
      score_nbest( setSAMP, setFrames, setLOGL, setSYM, setRNG, setSCO, setDIC )
      setSAMP = samp
      setFrames = frames

    elif setSAMP == samp:
      if setFrames != frames:
        raise ValueError('number of frames differs within nbest set: '+samp+'\n')

    SYM = []
    RNG = []
    SCO = []

    for v in line:
      [ srng, erng, sym, sco ] = v.split()
      SYM.append( sym )
      RNG.append( [ int(srng), int(erng) ] )
      SCO.append( float(sco) )
      if not sym in setDIC:
        setDIC[sym] = len(setDIC)

    setLOGL.append( logl )
    setSYM.append( SYM )
    setRNG.append( RNG )
    setSCO.append( SCO )

score_nbest( setSAMP, setFrames, setLOGL, setSYM, setRNG, setSCO, setDIC )
