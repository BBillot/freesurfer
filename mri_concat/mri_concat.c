/**
 * @file  mri_concat.c
 * @brief REPLACE_WITH_ONE_LINE_SHORT_DESCRIPTION
 *
 * REPLACE_WITH_LONG_DESCRIPTION_OR_REFERENCE
 */
/*
 * Original Author: REPLACE_WITH_FULL_NAME_OF_CREATING_AUTHOR 
 * CVS Revision Info:
 *    $Author: greve $
 *    $Date: 2007/04/27 21:28:54 $
 *    $Revision: 1.16 $
 *
 * Copyright (C) 2002-2007,
 * The General Hospital Corporation (Boston, MA). 
 * All rights reserved.
 *
 * Distribution, usage and copying of this software is covered under the
 * terms found in the License Agreement file named 'COPYING' found in the
 * FreeSurfer source code root directory, and duplicated here:
 * https://surfer.nmr.mgh.harvard.edu/fswiki/FreeSurferOpenSourceLicense
 *
 * General inquiries: freesurfer@nmr.mgh.harvard.edu
 * Bug reports: analysis-bugs@nmr.mgh.harvard.edu
 *
 */


// mri_concat.c
// $Id: mri_concat.c,v 1.16 2007/04/27 21:28:54 greve Exp $

#include <stdio.h>
#include <stdlib.h>
#include <math.h>
#include "macros.h"
#include "mrisurf.h"
#include "mrisutils.h"
#include "error.h"
#include "diag.h"
#include "mri.h"
#include "mri2.h"
#include "fmriutils.h"
#include "version.h"

static int  parse_commandline(int argc, char **argv);
static void check_options(void);
static void print_usage(void) ;
static void usage_exit(void);
static void print_help(void) ;
static void print_version(void) ;
static void argnerr(char *option, int n);
static void dump_options(FILE *fp);
//static int  singledash(char *flag);

int main(int argc, char *argv[]) ;

static char vcid[] = "$Id: mri_concat.c,v 1.16 2007/04/27 21:28:54 greve Exp $";
char *Progname = NULL;
int debug = 0;
char *inlist[5000];
int ninputs = 0;
char *out = NULL;
MRI *mritmp, *mritmp0, *mriout;
int DoMean=0;
int DoStd=0;
int DoMax=0;
int DoPaired=0;
int DoPairedAvg=0;
int DoPairedDiff=0;
int DoPairedDiffNorm=0;
int DoPairedDiffNorm1=0;
int DoPairedDiffNorm2=0;

/*--------------------------------------------------*/
int main(int argc, char **argv) {
  int nargs, nthin, nframestot=0, nr=0,nc=0,ns=0, fout;
  int r,c,s,f;
  double v, v1, v2, vavg;

  /* rkt: check for and handle version tag */
  nargs = handle_version_option (argc, argv, vcid, "$Name:  $");
  if (nargs && argc - nargs == 1) exit (0);
  argc -= nargs;

  Progname = argv[0] ;
  argc --;
  argv++;
  ErrorInit(NULL, NULL, NULL) ;
  DiagInit(NULL, NULL, NULL) ;

  if (argc == 0) usage_exit();

  parse_commandline(argc, argv);
  check_options();
  dump_options(stdout);

  printf("ninputs = %d\n",ninputs);
  for (nthin = 0; nthin < ninputs; nthin++) {
    if (Gdiag_no > 0) printf("%2d %s\n",nthin,inlist[nthin]);
    mritmp = MRIreadHeader(inlist[nthin],MRI_VOLUME_TYPE_UNKNOWN);
    if (mritmp == NULL) {
      printf("ERROR: reading %s\n",inlist[nthin]);
      exit(1);
    }
    if (nthin == 0) {
      nc = mritmp->width;
      nr = mritmp->height;
      ns = mritmp->depth;
    }
    if (mritmp->width != nc || mritmp->height != nr ||
        mritmp->depth != ns) {
      printf("ERROR: dimension mismatch between %s and %s\n",
             inlist[0],inlist[nthin]);
      exit(1);
    }

    nframestot += mritmp->nframes;
    MRIfree(&mritmp);
  }
  printf("nframestot = %d\n",nframestot);

  if (DoPaired) {
    if (remainder(nframestot,2) != 0) {
      printf("ERROR: --paired-xxx specified but there are an "
             "odd number of frames\n");
      exit(1);
    }
  }

  mriout = MRIallocSequence(nc,nr,ns,MRI_FLOAT,nframestot);
  if (mriout == NULL) exit(1);

  fout = 0;
  for (nthin = 0; nthin < ninputs; nthin++) {
    if (Gdiag_no > 0) {
      printf("---=====------=========----=======-----========---------\n");
      printf("#@# %d th input \n",nthin);
    }
    fflush(stdout);
    mritmp = MRIread(inlist[nthin]);
    if (nthin == 0) {
      MRIcopyHeader(mritmp, mriout);
      //mriout->nframes = nframestot;
    }
    for (f=0; f < mritmp->nframes; f++) {
      for (c=0; c < nc; c++) {
        for (r=0; r < nr; r++) {
          for (s=0; s < ns; s++) {
            v = MRIgetVoxVal(mritmp,c,r,s,f);
            MRIsetVoxVal(mriout,c,r,s,fout,v);
          }
        }
      }
      fout++;
    }
    MRIfree(&mritmp);
  }


  if (DoPaired) {
    printf("Combining pairs\n");
    mritmp = MRIcloneBySpace(mriout,-1,mriout->nframes/2);
    for (c=0; c < nc; c++) {
      for (r=0; r < nr; r++) {
        for (s=0; s < ns; s++) {
          fout = 0;
          for (f=0; f < mriout->nframes; f+=2) {
            v1 = MRIgetVoxVal(mriout,c,r,s,f);
            v2 = MRIgetVoxVal(mriout,c,r,s,f+1);
	    v = 0;
            if(DoPairedAvg) {
              v = (v1+v2)/2.0;
	    }
            if(DoPairedDiff) {
	      v = v1-v2; // difference
	    }
            if(DoPairedDiffNorm) {
	      v = v1-v2; // difference
              vavg = (v1+v2)/2.0;
              if (vavg != 0.0) v = v/vavg;
            }
            if(DoPairedDiffNorm1) {
	      v = v1-v2; // difference
              if (v1 != 0.0) v = v/v1;
              else v = 0;
            }
            if(DoPairedDiffNorm2) {
	      v = v1-v2; // difference
              if (v2 != 0.0) v = v/v2;
              else v = 0;
            }
            MRIsetVoxVal(mritmp,c,r,s,fout,v);
            fout++;
          }
        }
      }
    }
    MRIfree(&mriout);
    mriout = mritmp;
  }

  if (DoMean) {
    printf("Computing mean across frames\n");
    mritmp = MRIframeMean(mriout,NULL);
    MRIfree(&mriout);
    mriout = mritmp;
  }

  if (DoStd) {
    printf("Computing std across frames\n");
    if(mriout->nframes < 2){
      printf("ERROR: cannot compute std from one frame\n");
      exit(1);
    }
    //mritmp = fMRIvariance(mriout, -1, 1, NULL);
    mritmp = fMRIcovariance(mriout, 0, -1, NULL, NULL);

    MRIsqrt(mritmp, mritmp);
    MRIfree(&mriout);
    mriout = mritmp;
  }

  if (DoMax) {
    printf("Computing max across all frames \n");
    mritmp = MRIvolMax(mriout,NULL);
    MRIfree(&mriout);
    mriout = mritmp;
  }

  printf("Writing to %s\n",out);
  MRIwrite(mriout,out);

  return(0);
}
/*-----------------------------------------------------------------*/
/*-----------------------------------------------------------------*/
/*-----------------------------------------------------------------*/

/* --------------------------------------------- */
static int parse_commandline(int argc, char **argv) {
  int  nargc , nargsused;
  char **pargv, *option ;

  if (argc < 1) usage_exit();

  nargc   = argc;
  pargv = argv;
  while (nargc > 0) {

    option = pargv[0];
    if (debug) printf("%d %s\n",nargc,option);
    nargc -= 1;
    pargv += 1;

    nargsused = 0;

    if (!strcasecmp(option, "--help"))  print_help() ;
    else if (!strcasecmp(option, "--version")) print_version() ;
    else if (!strcasecmp(option, "--debug"))   debug = 1;
    else if (!strcasecmp(option, "--mean"))   DoMean = 1;
    else if (!strcasecmp(option, "--std"))    DoStd = 1;
    else if (!strcasecmp(option, "--max"))    DoMax = 1;
    else if (!strcasecmp(option, "--asl")){
      DoPairedDiff = 1;
      DoMean = 1;
    }
    else if (!strcasecmp(option, "--paired-avg")){
      DoPaired = 1;
      DoPairedAvg = 1;
    }
    else if (!strcasecmp(option, "--paired-diff")){
      DoPaired = 1;
      DoPairedDiff = 1;
    }
    else if (!strcasecmp(option, "--paired-diff-norm")) {
      DoPairedDiff = 1;
      DoPairedDiffNorm = 1;
      DoPaired = 1;
    } else if (!strcasecmp(option, "--paired-diff-norm1")) {
      DoPairedDiff = 1;
      DoPairedDiffNorm1 = 1;
      DoPaired = 1;
    } else if (!strcasecmp(option, "--paired-diff-norm2")) {
      DoPairedDiff = 1;
      DoPairedDiffNorm2 = 1;
      DoPaired = 1;
    } else if ( !strcmp(option, "--i") ) {
      if (nargc < 1) argnerr(option,1);
      inlist[ninputs] = pargv[0];
      ninputs ++;
      nargsused = 1;
    } else if ( !strcmp(option, "--o") ) {
      if (nargc < 1) argnerr(option,1);
      out = pargv[0];
      nargsused = 1;
    } else {
      inlist[ninputs] = option;
      ninputs ++;
      //fprintf(stderr,"ERROR: Option %s unknown\n",option);
      //if(singledash(option))
      //fprintf(stderr,"       Did you really mean -%s ?\n",option);
      //exit(-1);
    }
    nargc -= nargsused;
    pargv += nargsused;
  }
  return(0);
}
/* ------------------------------------------------------ */
static void usage_exit(void) {
  print_usage() ;
  exit(1) ;
}
/* --------------------------------------------- */
static void print_usage(void) {
  printf("USAGE: %s \n",Progname) ;
  printf("\n");
  printf("   --i invol <--i invol ...> (don't need --i) \n");
  printf("   --o out \n");
  printf("\n");
  printf("   --paired-avg  : compute paired avg (1+2, 3d+4, etc) \n");
  printf("   --paired-diff : compute paired diff (1-2, 3-4, etc) \n");
  printf("   --paired-diff-norm : same as paired-diff but scale by TP1,2 average \n");
  printf("   --paired-diff-norm1 : same as paired-diff but scale by TP1 \n");
  printf("   --paired-diff-norm2 : same as paired-diff but scale by TP2 \n");
  printf("\n");
  printf("   --mean : compute mean of concatenated volumes\n");
  printf("   --std  : compute std  of concatenated volumes\n");
  printf("   --max  : compute max  of concatenated volumes\n");
  printf("\n");
  printf("   --help      print out information on how to use this program\n");
  printf("   --version   print out version and exit\n");
  printf("\n");
  printf("%s\n", vcid) ;
  printf("\n");
}
/* --------------------------------------------- */
static void print_help(void) {
  print_usage() ;

  printf("Concatenates input data sets.\n");
  printf("EXAMPLES:\n");
  printf("  mri_concat --i f1.mgh --i f2.mgh --o cout.mgh\n");
  printf("  mri_concat f1.mgh f2.mgh --o cout.mgh\n");
  printf("  mri_concat f*.mgh --o cout.mgh\n");
  printf("  mri_concat f*.mgh --o coutmn.mgh --mean\n");
  printf("  mri_concat f*.mgh --o coutdiff.mgh --paired-diff\n");
  printf("  mri_concat f*.mgh --o coutdiff.mgh --paired-diff-norm\n");
  printf("  mri_concat f*.mgh --o coutdiff.mgh --paired-diff-norm1\n");

  exit(1) ;
}
/* --------------------------------------------- */
static void print_version(void) {
  printf("%s\n", vcid) ;
  exit(1) ;
}
/* --------------------------------------------- */
static void argnerr(char *option, int n) {
  if (n==1)
    fprintf(stderr,"ERROR: %s flag needs %d argument\n",option,n);
  else
    fprintf(stderr,"ERROR: %s flag needs %d arguments\n",option,n);
  exit(-1);
}
/* --------------------------------------------- */
static void check_options(void) {
  if (ninputs == 0) {
    printf("ERROR: no inputs specified\n");
    exit(1);
  }
  if (out == NULL) {
    printf("ERROR: no output specified\n");
    exit(1);
  }
  if(DoPairedDiff && DoPairedAvg) {
    printf("ERROR: cannot specify both --paried-diff-xxx and --paried-avg \n");
    exit(1);
  }
  if (DoPairedDiffNorm1 && DoPairedDiffNorm2) {
    printf("ERROR: cannot specify both --paried-diff-norm1 and --paried-diff-norm2 \n");
    exit(1);
  }
  if (DoPairedDiffNorm && DoPairedDiffNorm1) {
    printf("ERROR: cannot specify both --paried-diff-norm and --paried-diff-norm1 \n");
    exit(1);
  }
  if (DoPairedDiffNorm && DoPairedDiffNorm2) {
    printf("ERROR: cannot specify both --paried-diff-norm and --paried-diff-norm2 \n");
    exit(1);
  }
  if(DoMean && DoStd){
    printf("ERROR: cannot --mean and --std\n");
    exit(1);
  }
  return;
}

/* --------------------------------------------- */
static void dump_options(FILE *fp) {
  return;
}
/*---------------------------------------------------------------*/
#if 0
static int singledash(char *flag) {
  int len;
  len = strlen(flag);
  if (len < 2) return(0);

  if (flag[0] == '-' && flag[1] != '-') return(1);
  return(0);
}
#endif
