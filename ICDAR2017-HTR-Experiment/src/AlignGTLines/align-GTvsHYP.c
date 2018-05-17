/*****************************************************************************/
/*! \author  Alejandro H. Toselli <ahector@iti.upv.es>
 *  \version 1.0
 *  \date    2014
 */

/* Copyright (C) 2014 by Pattern Recognition and Human Language
   Technology Group, Technological Institute of Computer Science,
   Valencia University of Technology, Valencia (Spain).

   Permission to use, copy, modify, and distribute this software and
   its documentation for any purpose and without fee is hereby
   granted, provided that the above copyright notice appear in all
   copies and that both that copyright notice and this permission
   notice appear in supporting documentation.  This software is
   provided "as is" without express or implied warranty.
*/

/* To compile it:
 *                                                                           *
 *            gcc -Wall -O3 -ansi -o align-GTvsHYP align-GTvsHYP.c           *
 *                                                                           */
/*****************************************************************************/

#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <ctype.h>

#define MLL 32768                   /* Maximum Line Length */

typedef unsigned int uint;

typedef struct {
  uint i,j;        /* To address the node from which is arriving to */
  uint cost;       /* Accumulative cost */
  int idOP;        /* Operation Types: -3:None, -2:Deletion, -1:Insertion, 
		      0>=:Substitution */
} TrelNode;

int verbosity=0;



/*****************************************************************************/
/* Gets the minimum of three unsigned int values */
uint minimumLvDst(uint a, uint b, uint c)
{
  uint min=a;
  if(b < min) min=b;
  if(c<min) min=c;
  return min;
}

/*****************************************************************************/
/* Compute levenshtein distance between source and target strings */
uint levenshtein_distance(const char *source, const char *target) {
  uint k, i, j, n, m, cost, *dst, distance;
  n = source ? strlen(source) : 0;
  m = target ? strlen(target) : 0;
  if(n != 0 && m != 0) {
    m++; n++;
    dst = (uint*) malloc((sizeof(uint))*m*n);
    for(k=0; k<n; k++) dst[k]=k;
    for(k=0; k<m; k++) dst[k*n]=k;
    for(i=1; i<n; i++)
      for(j=1; j<m; j++) {
        if(source[i-1] == target[j-1]) cost=0;
        else cost=1;
        dst[j*n+i] = minimumLvDst(dst[(j-1)*n+i]+1, dst[j*n+i-1]+1, dst[(j-1)*n+i-1]+cost);
      }
    distance = dst[n*m-1];
    free(dst);
    return distance;
  }
  else {
    if ((m+n)==0) fprintf(stderr,"WARNING: both strings are NULL in the Lev-Dist computation!\n");
    return m+n;
  }
}



/*****************************************************************************/
/* Gets the minimum cost of the three trellis nodes: INSERTION, DELETION,
   and SUBSTITUTION. */
void minimum(TrelNode *tn, const TrelNode *ins, const TrelNode *del, 
	     const TrelNode *sus, uint uInsCst, uint uDelCst, uint uSusCst, \
	     uint i, uint j)
{
  tn->i = i; tn->j = j - 1;
  tn->cost = ins->cost + uInsCst;
  tn->idOP = -1;

  if ( del->cost + uDelCst < tn->cost ) {
    tn->i = i - 1; tn->j = j;
    tn->cost = del->cost + uDelCst; 
    tn->idOP = -2;
  }
  if ( sus->cost + uSusCst <= tn->cost ) {
    tn->i = i - 1; tn->j = j - 1;
    tn->cost = sus->cost + uSusCst; 
    tn->idOP = 0;
  }
}

/*****************************************************************************/
/* Print out information of the total number of hits and errors along
   broken-down into Ins+Del+Sus components. As well the total cost
   broken down into Ins+Del+Sus components along with the table of
   alignments operations can be claimed. */ 
void printAlign(const TrelNode *tn, const char **vGTs, const char **vHPs, \
		uint i, uint j, uint uGTNum, \
		uint *costI, uint *costD, uint *costS, \
		uint *numI, uint *numD, uint *numS, uint *numH, \
		float thrsS, const char **cIDs) { 
    
  uint auxdif;
  float cnfMsr;
  const TrelNode *node = &tn[j*uGTNum+i];

  if (node->idOP == -3) {
    if (verbosity>1 && verbosity!=4) {
      fprintf(stdout,"\n   Gr-Th          Ln-Ex\n");
      fprintf(stdout,"#Lin (#Chrs)   #Lin (#Chrs)     Cost     CnfMsr     IDs\n");
      fprintf(stdout,"---------------------------------------------------------------\n");
    }
    else if (verbosity==4) {
      fprintf(stdout,"\n=========================================================================\n");
    }
    return;
  }
  printAlign(tn, vGTs, vHPs, node->i, node->j, uGTNum, \
	     costI, costD, costS, numI, numD, numS, numH, thrsS, cIDs);

  if (node->idOP == -2) {	
    auxdif = (node->cost - tn[node->j*uGTNum+node->i].cost);
    *costD += auxdif; ++(*numD);
    if (verbosity>1 && verbosity!=4)
      fprintf(stdout,"%3d  (%3zu) -->    <DEL> \t%3d\t%6.2f\n",i,strlen(vGTs[i-1]),auxdif,0.0);
    else if (verbosity==4) {
      fprintf(stdout,"Ref-ln: %2d  <%s>\nHyp-ln: --  <DEL>\n",i,vGTs[i-1]);
      fprintf(stdout,"========================================================================= CST: %d\n", auxdif);
    } else {
      if (verbosity==-1) {
        if (i>1) fprintf(stdout," >>> %s",vGTs[i-1]);
        else fprintf(stdout,"<<< %s",vGTs[i-1]);
             /*fprintf(stderr,"\nWARNING: Transcription line %d was discarded: %s\n",i,vGTs[i-1]);*/
      }
    }
  }
  else if (node->idOP == -1) {
    auxdif = (node->cost - tn[node->j*uGTNum+node->i].cost);
    *costI += auxdif; ++(*numI);
    if (verbosity>1 && verbosity!=4)
      fprintf(stdout,"   <INS>   --> %3d  (%3zu)\t%3d\t%6.2f\t%10s\n",j,strlen(vHPs[j-1]),auxdif,0.0,cIDs[j-1]);
    else if (verbosity==4) {
      fprintf(stdout,"Ref-ln: --  <INS>\nHyp-ln: %2d  <%s> (%s)\n",j,vHPs[j-1],cIDs[j-1]);
      fprintf(stdout,"========================================================================= CST: %d\n", auxdif);
    } else if (verbosity==-1) fprintf(stdout,"\n<INS>");
  }
  else {	
    auxdif = (node->cost - tn[node->j*uGTNum+node->i].cost);
    *costS += auxdif;
    cnfMsr = 1.0 - (float)auxdif/strlen(vGTs[i-1]);
    if (cnfMsr<0) cnfMsr=0.0;
    if (auxdif <= (uint)strlen(vGTs[i-1])*(1.0 -thrsS)) {
      ++(*numH);
      if (verbosity>1 && verbosity!=4)
        fprintf(stdout,"%3d  (%3zu) --> %3d  (%3zu)\t%3d\t%6.2f\t%10s\n",i,strlen(vGTs[i-1]),j,strlen(vHPs[j-1]),auxdif,cnfMsr,cIDs[j-1]);
      else if (verbosity==4) {
        fprintf(stdout,"Ref-ln: %2d  <%s>\nHyp-ln: %2d  <%s> (%s)\n",i,vGTs[i-1],j,vHPs[j-1],cIDs[j-1]);
	fprintf(stdout,"========================================================================= CST: %d\n", auxdif);
      } else if (verbosity==-1) fprintf(stdout,"\n%s",vGTs[i-1]);
    } else {
      ++(*numS);
      if (verbosity>1 && verbosity!=4)
        fprintf(stdout,"%3d  (%3zu) --> %3d  (%3zu)\t%3d*\t%6.2f\t%10s\n",i,strlen(vGTs[i-1]),j,strlen(vHPs[j-1]),auxdif,cnfMsr,cIDs[j-1]);
      else if (verbosity==4) {
        fprintf(stdout,"Ref-ln: %2d  <%s>\nHyp-ln: %2d  <%s> (%s)\n",i,vGTs[i-1],j,vHPs[j-1],cIDs[j-1]);
	fprintf(stdout,"========================================================================= CST: %d*\n", auxdif);
      } else if (verbosity==-1) fprintf(stdout,"\n**<SUB>** %s",vGTs[i-1]);
    }
  }
}


/*****************************************************************************/
/* Read text lines from the input file and compute their lengths in
   terms of the number of characters. The read lines are stored in the
   'pVecStr' array after trimming spaces and removing commented lines
   (preceded by '#' character). If cIDs!=NULL, we assume that region
   and line IDs are placed at the begining of line separetd by $
   symbol. */
char** getVecStr(FILE *dFile, uint *uNumLin, uint *uNumChrs, char ***cIDs) {

  char **pVecStr = NULL, **auxIDs = NULL;
  char line[MLL], *pF, *pB, *pID, *pA;
  uint n = 0, len, flag, uTotNumChrs = 0;
  
  if (verbosity>2 && verbosity!=4)
    fprintf(stdout,"Num -- Length -- Transcription\n-------------------------------\n");
  
  while ( fgets(line, MLL, dFile) != NULL ) {
    /* Trim spaces from the start of the line */
    /* Beside lines begining with the character '#' are removed */
    pF = line; 
    while (isspace(*pF)) ++pF;
    /* if ( *pF=='#' || *pF=='\0') continue; */
    if ( *pF=='\0') continue;

    /* Read and store the region and line IDs */
    if (cIDs) {
      len=0; pID=pF;
      while (*(pF++) != '$') len++;
      pB = pF-2; while (isspace(*pB)) { --pB; len--; }
      auxIDs    = (char **) realloc(auxIDs, (n+1)*sizeof(char *));
      auxIDs[n] = (char *) malloc((len+1)*sizeof(char));
      strncpy(auxIDs[n], pID, len);
      while (isspace(*pF)) ++pF;
      /*if ( *pF=='#' || *pF=='\0') {*/
      /*if ( *pF=='\0') {
	fprintf(stderr,"ERROR: Syntax error reading hypotheses file: line %d\n", n+1);
	exit(1);
      };*/
    }

    /* Trim spaces from the end of the line */
    len = strlen(line);
    pB = line + len - 1;
    while (isspace(*pB)) --pB; *(pB+1)='\0';
    /* Remove extra consecutive spaces located in the middle of the line */
    pB = pF-1; flag = 0; len = 0;
    while (*(++pB) != '\0')
      if (isspace(*pB)) {
	if (!flag) { flag=1; len++; }
      } else { flag=0; len++; }

    pVecStr = (char **) realloc(pVecStr, (n+1)*sizeof(char *));
    pVecStr[n++] = (char *) malloc((len+1)*sizeof(char));
    uTotNumChrs += len;

    pB = pF-1; pA = pVecStr[n-1]; flag = 0;
    while (*(++pB) != '\0')
      if (isspace(*pB)) {
	if (!flag) { flag=1; *(pA++) = ' '; }
      } else { flag=0; *(pA++) = *pB; }
    *pA = '\0';

    if (verbosity>2 && verbosity!=4) {
      if (cIDs) fprintf(stdout,"%3d -- %3d -- <%s> (%s)\n", n, len, pVecStr[n-1], auxIDs[n-1]);
      else fprintf(stdout,"%3d -- %3d -- <%s>\n", n, len, pVecStr[n-1]);
    }
  }
  if (verbosity>2 && verbosity!=4) fprintf(stdout,"-------------------------------\n");
  
  *uNumLin = n;
  *uNumChrs = uTotNumChrs;
  if (cIDs) *cIDs = auxIDs;
  return pVecStr; 
}




/*****************************************************************************/
/* By using Dynamic Programing it is computed the best alignment at
   minimum cost between the sequence of text line lengths of the
   ground-truth (uGT) and the sequence of lengths of the extracted
   line images (uEX). */
int alignCost(const char **vGTs, uint uGTNum, uint nTotChrs, const char **vHPs, uint uHPNum, float thrsS, const char **cIDs) {
  
  uint k, i, j, cost, totalCost;
  TrelNode *trelNod;
  float confMsr;

  if(uGTNum && uHPNum) {
    uGTNum++; uHPNum++;
    trelNod = (TrelNode*) malloc( sizeof(TrelNode) * uHPNum * uGTNum );
    
    /* Initialization of the trellisMatrix node 0 0 */
    trelNod[0].i = 0; trelNod[0].j = 0; 
    trelNod[0].cost = 0;
    trelNod[0].idOP = -3;
    /* Initialization of the first trellis column: Deletions */
    for (k=1; k<uGTNum; k++) {
      trelNod[k].i = k-1; trelNod[k].j = 0;
      trelNod[k].cost = trelNod[k-1].cost + levenshtein_distance(vGTs[k-1], NULL);
      trelNod[k].idOP = -2;
    }
    /* Initialization of the first trellis row: Insertions */
    for (k=1; k<uHPNum; k++) {
      trelNod[k*uGTNum].i = 0; trelNod[k*uGTNum].j = k-1;
      trelNod[k*uGTNum].cost = trelNod[(k-1)*uGTNum].cost + levenshtein_distance(NULL, vHPs[k-1]);
      trelNod[k*uGTNum].idOP = -1;
    }
    /* Dynamic programming */
    for (i=1; i<uGTNum; i++)
      for (j=1; j<uHPNum; j++) {

	cost = (uint) levenshtein_distance(vGTs[i-1],vHPs[j-1]);

	/* Update trellisnode with the minimum cost */ 

	minimum(&trelNod[j*uGTNum+i], &trelNod[(j-1)*uGTNum+i],		\
		&trelNod[j*uGTNum+i-1],	&trelNod[(j-1)*uGTNum+i-1],	\
		strlen(vHPs[j-1]), strlen(vGTs[i-1]), cost, i, j	\
		);
      }
    totalCost = trelNod[uGTNum*uHPNum-1].cost;

    uint costI=0, costD=0, costS=0, numI=0, numD=0, numS=0, numH=0;    
    /* TrelNode tn = trelNod[uGTNum*uEXNum-1]; */
    
    printAlign(trelNod, vGTs, vHPs, uGTNum-1, uHPNum-1, uGTNum, \
    	       &costI, &costD, &costS, &numI, &numD, &numS, \
    	       &numH, thrsS, cIDs);
    if (verbosity==-1) fprintf(stdout,"\n");
    
    /*confMsr = (uGTNum!=uHPNum) ? 0.0 : 1.0 - (float)totalCost/nTotChrs; if (confMsr<0) confMsr=0.0;*/
    confMsr = 1.0 - (float)totalCost/nTotChrs; if (confMsr<0) confMsr=0.0;
    if (verbosity>=0)
      fprintf(stdout,"Errors:%d (I:%d D:%d S:%d)  Hits:%d  Cost:%d  CnfMsr:%5.3f\n", \
      	      numI+numD+numS, numI, numD, numS, numH, totalCost, confMsr);

    if (verbosity>0)
      fprintf(stdout,"\n Total-Cost:%d\t  (Ins:%d   Del:%d   Sus:%d)\n", totalCost, costI, costD, costS);

    free(trelNod);
    return (int)totalCost;
  }
  else return -1;
  /* A negative return value means that one or both GTNum and EXNum
     are zero. */
}


/*****************************************************************************/
void usage (const char* prog) {
  fprintf(stderr,"\nUsage: %s [-h] [-v <int>] [-t <float>] REF-file HYP-file\n\n", prog);
  fprintf(stderr,"\tOptions\n");
  fprintf(stderr,"\t\t-v <num>    Verbosity ([0:3] - def.:0)\n");
  fprintf(stderr,"\t\t    -1   write text lines for the \"insertTranscriptions\" Tool\n");
  fprintf(stderr,"\t\t     0   write info of Ins+Del+Sus Errors and Hits\n");
  fprintf(stderr,"\t\t     1 + write info of computed Ins+Del+Sus Costs\n");
  fprintf(stderr,"\t\t     2 + write table of Operation Alignments\n");
  fprintf(stderr,"\t\t     3 + write text lines read from: GT-file EX-file\n");
  fprintf(stderr,"\t\t     4   only write alignments between REF and HYP strings\n\n");
  fprintf(stderr,"\t\t-t <float>  Threshold of conf. measure alignment between Ref\n");
  fprintf(stderr,"\t\t            and Hyp strings under which a Substitution\n");
  fprintf(stderr,"\t\t            Error is considered ([0.0:1.0] - def.:0.2)\n\n");
  fprintf(stderr,"\t\t-h          This help\n\n");
  fprintf(stderr,"  \"REF-file\" and \"HYP-file\" are the Ground-Truth transcription\n\
  file and the recognized hypothesis file respectively.\n\n");
}

/*****************************************************************************/
int main (int argc, char **argv) {
 
  char *prog;
  for (prog = argv[0]+strlen(argv[0])-1; prog!=argv[0] && *(prog-1)!='/'; --prog);  

  FILE *dGTFile = NULL, *dHPFile = NULL;
  char *sNamGTf = NULL, *sNamHPf = NULL;
  char **vGTs = NULL, **vHPs = NULL, **cIDs = NULL;
  uint nLinGT, nChrsGT, nLinHP, nChrsHP;
  
  int i, n = 0, errs = 0; /* iInsDelCost=-1;*/ 
  float fprop = 0.2;

  for (i=1; i<argc; ++i) {
    if (strcmp(argv[i], "-v") == 0) { 
      if (++i>=argc-2) { usage(prog); errs++; break; }
      verbosity = atoi(argv[i]);
      if (verbosity<-1 || verbosity>4) { usage(prog); errs++; break; }
      n+=2; 
    } else if (strcmp(argv[i], "-t") == 0) { 
      if (++i>=argc-2) { usage(prog); errs++; break; }
      fprop = atof(argv[i]);
      if (fprop<0 || fprop>1) { usage(prog); errs++; break; }
      n+=2; 
    } else if (strcmp(argv[i], "-h") == 0) {
      usage(prog); return 0;
    }
  }

  argc--; n += 2;
  if (argc == n && !errs) 
    do {
      sNamGTf = argv[n-1];
      if ( (dGTFile = fopen(sNamGTf, "r")) == NULL) {
	fprintf(stderr,"ERROR: File \"%s\" cannot be opened!\n",sNamGTf);
	errs = 1;
	break;
      }
      
      sNamHPf = argv[n];
      if ( (dHPFile = fopen(sNamHPf, "r")) == NULL) {
	fprintf(stderr,"ERROR: File \"%s\" cannot be opened!\n",sNamHPf);
	errs = 1;
	break;
      }
      
      if (verbosity>2 && verbosity!=4) fprintf(stdout,"\nREFERENCE transcription: %s\n",sNamGTf);
      vGTs = getVecStr(dGTFile, &nLinGT, &nChrsGT, NULL);
      if (!vGTs || !nLinGT) { errs = 1; break; }
      /*for (i=0; i<nLinGT; i++) fprintf(stderr,"%d - %d - %d\n",nLinGT,vGTs[i]);*/

      if (verbosity>2 && verbosity!=4) fprintf(stdout,"\nHYPOTHESIS transcription: %s\n",sNamHPf);
      vHPs = getVecStr(dHPFile, &nLinHP, &nChrsHP, &cIDs);
      if (!vHPs || !nLinHP) { errs = 1; break; }
      /*for (i=0; i<nLinHP; i++) fprintf(stderr,"%d - %d\n",nLinHP,vHPs[i]);*/
      
      if (nLinGT != nLinHP)
	fprintf(stderr,"WARNING: Numers of lines of \"%s\" and \"%s\" differs: %d - %d\n", sNamGTf, sNamHPf, nLinGT, nLinHP);
      
      if (verbosity>-1) fprintf(stdout,"FILE: %s  ",sNamHPf);
      if ((alignCost((const char **)vGTs, nLinGT, nChrsGT, (const char **)vHPs, nLinHP, \
		     fprop, (const char **)cIDs))<0) errs++;

    } while (0);
  else { 
    usage(prog);
    errs++;
  }
  
  if (dGTFile) fclose(dGTFile); 
  if (dHPFile) fclose(dHPFile);
  if (vGTs) {
    for (i=0; i<nLinGT; i++) free(vGTs[i]);
    free(vGTs);
  }
  if (vHPs) {
    for (i=0; i<nLinHP; i++) free(vHPs[i]);
    free(vHPs);
  }
  if (cIDs) {
    for (i=0; i<nLinHP; ++i) free(cIDs[i]);
    free(cIDs);
  }

  if (errs) {
    fprintf(stdout,"ERROR: %s -- Program finished with errors\n", sNamHPf);
    return 1;
  }

  return 0;
}
