#!/usr/bin/perl
#
# Modified from:
# https://github.com/FNNDSC/pl-surfaces-fetus/blob/5eca9f8c60cd6e010dd9a2ac1fad850f0468d319/scripts/fit_subplate.pl
#
# TODO parameterize and document all of these arguments.

use strict;
use warnings "all";
use File::Basename;
use File::Spec;
use File::Temp qw/ tempdir /;
use File::Copy;

use Getopt::Tabular;
use MNI::Startup;
use MNI::FileUtilities;
use MNI::DataDir;

# --- set the help & usage strings ---
my $help = <<HELP;
Required parameters:
  mask.mnc  : target volume to fit to
  wm.obj    : starting surface
  iz.obj    : output filename
HELP

my $usage = <<USAGE;
Usage: $ProgramName [options...] mask.mnc wm.obj iz.obj
       $ProgramName -help to list options
USAGE

my $description = <<DESCRIPTION;
$usage
Wrapper for surface_fit and using mincchamfer to create a radial distance map.
DESCRIPTION

Getopt::Tabular::SetHelp( $help, $description );

my $label = 0;
my $age = 0;
my $no_downsize = 0;
my $save_chamfer = undef;

my @options = (
  # no options
  );

GetOptions( \@options, \@ARGV ) or exit 1;
die "$usage\n" unless @ARGV == 3;

my $inner_mask = shift;
my $white_surface = shift;
my $surface = shift;

copy($white_surface, $surface);

my $tmpdir = &tempdir( "subplate-XXXXXX", TMPDIR => 1, CLEANUP => 1 );

my $stretch_model = "$tmpdir/stretch_length_model.obj";
my $ICBM_white_model = MNI::DataDir::dir("surface-extraction") .
                       "/white_model_320.obj";
copy($ICBM_white_model, $stretch_model);

my $simple = "${tmpdir}/simple_chamfer.mnc";
simple_chamfer( $inner_mask, $simple, $tmpdir );
copy( $simple, $save_chamfer ) if ( defined( $save_chamfer) );


my $self_dist2 = 0.001;
my $self_weight2 = 1e08;
my $n_selfs = 9;

my $stop_threshold = 1e-3;
my $stop_iters = 1000;
my $n_per = 5;
my $tolerance = 1.0e-03;
my $f_tolerance = 1.0e-06;
my $oo_scale = 0.5;

# size  number of triangles
# sw    weight for mesh stretching (bigger means less stretch)
#       small value will create a highly voxelated/bumpy surface,
#       but with good detail.
#       large value for sw creates a very smooth surface that
#       destroys topological detail.
#       sw>40 will not fit into concavities that are 2 voxels wide.
# n_itr number of iterations
# inc   save every 20 iters
# l_w   weight for Laplacian field: large value means tighter fit,
#       but it seems that a small value is better convergence wise
#       to ensure mesh quality.
# iso   target value of the LaPlacian field to converge to
# si    max step increment (large is faster, but risk of intersection)
# os    do subsampling (0=none, n=#points extra along edge);
#       (helps to get through isolated csf voxels in insula region,
#       but must finish off the job without subsampling)
# iw    weight for surface self-intersection
# self  min distance to check for surface self-intersection
#       (0.0625 found to be too high)
# t     iterations of taubin smoothing after cycles of surface_fit

my @schedule = (
#  size  sw  n_itr inc l_w   iso   si   os   iw  self  t  chamfer_algo
# -----  --- ----- --- ----  --- ----  ---  ---- ----  -- --------
  81920, 30,  800, 50, 5e-6, 10, 0.20, 0.0, 1e0, 0.01, 0, $simple,
);

# Do the fitting stages like gray surface expansion.
my $sched_size = 12;
my $num_steps = @schedule / $sched_size;
my $num_rows = @schedule / $sched_size;

for ( my $i = 0;  $i < @schedule;  $i += $sched_size ) {

  my $row = $i / $sched_size + 1;

  my ( $size, $sw, $n_iters, $iter_inc, $laplacian_weight, $iso,
       $step_increment, $oversample, $self_weight, $self_dist,
       $smooth, $chamfer_map ) = @schedule[$i..$i+$sched_size-1];

  subdivide_mesh( $surface, $size, $surface );
  subdivide_mesh( $stretch_model, $size, $stretch_model );

  $oversample *= $oo_scale;
  my $self2 = get_self_intersect( $self_weight, $self_weight2, $n_selfs,
                                  $self_dist, $self_dist2 );

  for( my $iter = 0;  $iter < $n_iters;  $iter += $iter_inc ) {
    print "echo Step ${size}: $iter / $n_iters    sw=$sw,  "
          . "Schedule row ${row} / ${num_rows}\n";

    my $ni = $n_iters - $iter;
    $ni = $iter_inc if( $ni > $iter_inc );

    my $command = "surface_fit " .
                  "-mode two -surface  $surface $surface" .
                  " -stretch $sw $stretch_model -.9 0 0 0" .
                  " -laplacian $chamfer_map $laplacian_weight 0 " .
                  " $iso $oversample " .
                  " $self2 -step $step_increment " .
                  " -fitting $ni $n_per $tolerance " .
                  " -ftol $f_tolerance " .
                  " -stop $stop_threshold $stop_iters ";
    print $command . "\n";
    system( $command ) == 0 or die "Command $command failed with status: $?";
  }
}
unlink( $stretch_model );


# ============================================================
#     HELPER FUNCTIONS
# ============================================================


# Check if the input surface has the same side orientation (left)
# as the default template model.

sub CheckFlipOrientation {

  my $obj = shift;

  my $npoly = `print_n_polygons $obj`;
  chomp( $npoly );

  my $ret = `tail -5 $obj`;
  my @verts = split( ' ', $ret );
  my @last3 = ( $verts[$#verts-2], $verts[$#verts-1], $verts[$#verts] );

  my $dummy_sphere = "${tmpdir}/dummy_sphere.obj";
  &run('create_tetra',$dummy_sphere,0,0,0,1,1,1,$npoly);
  $ret = `tail -5 $dummy_sphere`;
  unlink( $dummy_sphere );
  @verts = split( ' ', $ret );
  my @sphere3 = ( $verts[$#verts-2], $verts[$#verts-1], $verts[$#verts] );
  if( $last3[0] == $verts[$#verts-2] &&
      $last3[1] == $verts[$#verts-1] &&
      $last3[2] == $verts[$#verts-0] ) {
    return 0;
  } else {
    return 1;
  }
}


# subdivide a surface taking into account if it's a left or right hemisphere.
# does nothing if it's already the correct size.

sub subdivide_mesh {

  my $input = shift;
  my $npoly = shift;
  my $output = shift;

  my $npoly_input = `print_n_polygons $input`;
  chomp( $npoly_input );
  return if ($npoly_input == $npoly); # do nothing if sizes are same

  if( !CheckFlipOrientation( $input ) ) {
    &run( "subdivide_polygons", $input, $output, $npoly );
  } else {
    # flip right as left first before subdividing, then flip back.
    &run( "param2xfm", '-clobber', '-scales', -1, 1, 1,
          "${tmpdir}/flip.xfm" );
    my $input_flipped = "${tmpdir}/right_flipped.obj";
    &run( "transform_objects", $input,
          "${tmpdir}/flip.xfm", $input_flipped );
    &run( "subdivide_polygons", $input_flipped, $output, $npoly );
    &run( "transform_objects", $output,
          "${tmpdir}/flip.xfm", $output );  # flip.xfm is its own inverse
    unlink( $input_flipped );
    unlink( "${tmpdir}/flip.xfm" );
  }

  # downsizing number of polygons can result in self intersection
  my $fixed = "$tmpdir/resized_fixed.obj";
  &run( "check_self_intersect", $output, '-fix', $fixed );
  if ( -e $fixed ) {
    print "warning: subdivide_mesh caused self-intersections.\n";
    move($fixed, $output);
  }
}


sub simple_chamfer {

  my $wm_mask = shift;
  my $output_chamfer = shift;
  my $tmpdir = shift;
  my $mask = "${tmpdir}/wm_mask_defragged.mnc";

  &run( 'mincreshape', '-image_range', '0', '255', $wm_mask, $mask);
  &run( 'mincdefrag', $mask, $mask, 0, 6 );
  &run( 'mincdefrag', $mask, $mask, 1, 6 );
  &run( 'mincchamfer', '-quiet', '-max_dist', '20.0',
        $mask, "${tmpdir}/chamfer_outside.mnc" );
  &run( 'minccalc', '-quiet', '-clobber', '-expression', '1-A[0]',
        $mask, "${tmpdir}/wm_mask_negated.mnc" );
  &run( 'mincchamfer', '-quiet', '-max_dist', '5.0',
        "${tmpdir}/wm_mask_negated.mnc", "${tmpdir}/chamfer_inside.mnc" );
  unlink( "${tmpdir}/wm_mask_negated.mnc" );
  &run( 'minccalc', '-quiet', '-clob', '-expression', "10.0-A[0]+A[1]",
        "${tmpdir}/chamfer_inside.mnc", "${tmpdir}/chamfer_outside.mnc",
        $output_chamfer );
  unlink( "${tmpdir}/chamfer_outside.mnc" );
  unlink( "${tmpdir}/chamfer_inside.mnc" );
  return $output_chamfer;
}

# copied from lib/surface-extraction/deform_utils.pl
sub  get_self_intersect( $$$$$ )
{
  my( $self_weight, $self_weight2, $n_selfs, $self_dist, $self_dist2 ) = @_;
  my( $self, $weight, $weight_factor, $s, $dist );

  if( $self_weight > 0.0 ) {
    $self = "";
    $weight = $self_weight;
    $weight_factor = ( $self_weight2 / $self_weight ) **
                      ( 1.0 / $n_selfs );

    for( $s = 0;  $s < $n_selfs;  ++$s ) {
      $dist = $self_dist + ($self_dist2 - $self_dist) *
              $s / $n_selfs;
      $self = $self . " -self_intersect $weight $dist ";
      $weight *= $weight_factor;
    }
    $self = $self . " -self_intersect $self_weight2 $self_dist2 ";
  } else {
    $self = "";
  }
  $self;
}


# Execute a system call.

sub run {
  print "@_\n";
  system(@_)==0 or die "Command @_ failed with status: $?";
}
