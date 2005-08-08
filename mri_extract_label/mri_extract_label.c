#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <ctype.h>

#include "macros.h"
#include "error.h"
#include "cma.h"
#include "diag.h"
#include "mri.h"
#include "proto.h"
#include "gca.h"
#include "transform.h"
#include "version.h"

#define UNIT_VOLUME 128

static char vcid[] = "$Id: mri_extract_label.c,v 1.8 2005/08/08 02:08:55 fischl Exp $";

int main(int argc, char *argv[]) ;

static int  get_option(int argc, char *argv[]) ;
static void usage_exit(void) ;
static void print_usage(void) ;
static void print_help(void) ;
static void print_version(void) ;
static int  extract_labeled_image(MRI *mri_in, TRANSFORM *transform, int label, MRI *mri_out) ;

char *Progname ;
static char *out_like_fname = NULL ;

static char *xform_fname = NULL ;
static LTA  *lta = NULL;
static TRANSFORM *transform = NULL ;
static float sigma = 0 ;

int
main(int argc, char *argv[])
{
  char        **av, *in_fname, *out_fname ;
  int         ac, nargs, i, label ;
  MRI         *mri_in, *mri_out, *mri_kernel, *mri_smoothed ;

  /* rkt: check for and handle version tag */
  nargs = handle_version_option (argc, argv, "$Id: mri_extract_label.c,v 1.8 2005/08/08 02:08:55 fischl Exp $", "$Name:  $");
  if (nargs && argc - nargs == 1)
    exit (0);
  argc -= nargs;

  Progname = argv[0] ;
  ErrorInit(NULL, NULL, NULL) ;
  DiagInit(NULL, NULL, NULL) ;

  ac = argc ;
  av = argv ;
  for ( ; argc > 1 && ISOPTION(*argv[1]) ; argc--, argv++)
  {
    nargs = get_option(argc, argv) ;
    argc -= nargs ;
    argv += nargs ;
  }

  if (argc < 4)
    usage_exit() ;

  in_fname = argv[1] ;
  out_fname = argv[argc-1] ;

  printf("reading volume from %s...\n", in_fname) ;
  mri_in = MRIread(in_fname) ;
  if (!mri_in)
    ErrorExit(ERROR_NOFILE, "%s: could not read MRI volume %s", Progname, 
              in_fname) ;
  if (out_like_fname)
  {
    MRI *mri_tmp = MRIread(out_like_fname) ;
    if (!mri_tmp)
      ErrorExit(ERROR_NOFILE, "%s: could not read template volume from %s",out_like_fname) ;
    mri_out = MRIalloc(mri_tmp->width, mri_tmp->height, mri_tmp->depth, mri_tmp->type) ;
    /*    MRIcopyHeader(mri_tmp, mri_out) ;*/
    MRIfree(&mri_tmp) ;
  }
  else
    mri_out = MRIclone(mri_in, NULL) ;


  for (i = 2 ; i < argc-1 ; i++)
  {
    label = atoi(argv[i]) ;
    printf("extracting label %d (%s)\n", label, cma_label_to_name(label)) ;
    extract_labeled_image(mri_in, transform, label, mri_out) ;
  }
	if (!FZERO(sigma))
	{
		printf("smoothing extracted volume...\n") ;
		mri_kernel = MRIgaussian1d(sigma, 10*sigma) ;
		mri_smoothed = MRIconvolveGaussian(mri_out, NULL, mri_kernel) ;
		MRIfree(&mri_out) ; mri_out = mri_smoothed ;
	}
	/* removed for gcc3.3
	 * vsprintf(out_fname, out_fname, (va_list) &label) ;
	 */
	printf("writing output to %s.\n", out_fname) ;
	MRIwrite(mri_out, out_fname) ;
  

  exit(0) ;
  return(0) ;  /* for ansi */
}

/*----------------------------------------------------------------------
            Parameters:

           Description:
----------------------------------------------------------------------*/
static int
get_option(int argc, char *argv[])
{
  int  nargs = 0 ;
  char *option ;
  
  option = argv[1] + 1 ;            /* past '-' */
  if (!stricmp(option, "-help"))
    print_help() ;
  else if (!stricmp(option, "-version"))
    print_version() ;
  else if (!stricmp(option, "DEBUG_VOXEL"))
  {
    Gx = atoi(argv[2]) ;
    Gy = atoi(argv[3]) ;
    Gz = atoi(argv[4]) ;
    nargs = 3 ;
    printf("debugging voxel (%d, %d, %d)\n", Gx,Gy,Gz) ;
  }
  else if (!stricmp(option, "out_like") || !stricmp(option, "ol"))
  {
    out_like_fname = argv[2] ;
    nargs = 1 ;
    printf("shaping output to be like %s...\n", out_like_fname) ;
  }
  else switch (toupper(*option))
  {
  case 'S':
    sigma = atof(argv[2]) ;
    printf("applying sigma=%2.1f smoothing kernel after extraction...\n",sigma) ;
    nargs = 1 ;
    break ;
  case 'T':
    xform_fname = argv[2] ;
    printf("reading and applying transform %s...\n", xform_fname) ;
    nargs = 1 ;
    transform = TransformRead(xform_fname) ;
    if (!transform)
      ErrorExit(ERROR_NOFILE, "%s: could not read transform from %s", 
                Progname, xform_fname) ;

		if (transform->type != MORPH_3D_TYPE)
			lta = (LTA *)(transform->xform) ;
    break ;
  case 'V':
    Gdiag_no = atoi(argv[2]) ;
    nargs = 1 ;
    break ;
  case '?':
  case 'U':
    print_usage() ;
    exit(1) ;
    break ;
  default:
    fprintf(stderr, "unknown option %s\n", argv[1]) ;
    exit(1) ;
    break ;
  }

  return(nargs) ;
}

static void
usage_exit(void)
{
  print_usage() ;
  print_help() ;
  exit(1) ;
}

static void
print_usage(void)
{
  fprintf(stderr, 
          "usage: %s [options] <input volume> <label 1> <label 2> ... <output name>\n",
          Progname) ;
  fprintf(stderr, "where options are:\n") ;
  fprintf(stderr, 
          "\t-s <sigma>\tapply a Gaussian smoothing kernel\n"
          "\t-t <xform file>\tapply the transform in <xform file> to extracted volume\n");
}

static void
print_help(void)
{
  fprintf(stderr, 
          "\nThis program will extract a set of labeled voxels from an image\n") ;
  exit(1) ;
}

static void
print_version(void)
{
  fprintf(stderr, "%s\n", vcid) ;
  exit(1) ;
}

static int
extract_labeled_image(MRI *mri_src, TRANSFORM *transform, int label, MRI *mri_dst)
{
  MRI  *mri_binarized, *mri_tmp ;

  mri_binarized = MRIclone(mri_src, NULL) ;
  MRIcopyLabel(mri_src, mri_binarized, label) ;
  MRIbinarize(mri_binarized, mri_binarized, 1, 0, UNIT_VOLUME) ;
  if (transform)
    mri_tmp = TransformCreateDensityMap(transform, mri_binarized, NULL) ;
	else
		mri_tmp = MRIcopy(mri_binarized,NULL) ;

	MRIadd(mri_tmp, mri_dst, mri_dst) ;
  MRIfree(&mri_binarized) ; MRIfree(&mri_tmp) ;
  return(NO_ERROR) ;
}

