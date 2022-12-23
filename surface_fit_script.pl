#!/usr/bin/perl
#
# Modified from:
# https://github.com/FNNDSC/pl-surfaces-fetus/blob/5eca9f8c60cd6e010dd9a2ac1fad850f0468d319/scripts/fit_subplate.pl
#

use strict;
use warnings "all";
use File::Basename;
use File::Spec;
use File::Temp qw/ tempdir /;
use File::Copy;
use List::Util qw(max);

use Getopt::Tabular;
use MNI::Startup;
use MNI::FileUtilities;
use MNI::DataDir;

# --- set the help & usage strings ---
my $help = <<HELP;
Required parameters:
  laplace.mnc  : distance map or laplacian field
  start.obj    : starting surface
  output.obj   : output filename
HELP

my $usage = <<USAGE;
Usage: $ProgramName [options...] laplace.mnc start.obj output.obj
       $ProgramName -help to list options
USAGE

my $description = <<DESCRIPTION;
$usage
Wrapper for surface_fit.
Parameters should be specified as comma-separated values (CSV). Multiple values
per parameter means to run multiple iterations of surface_fit.

If some parameter values are given as CSV whereas others are given as singular, e.g.

    $ProgramName -sw 80,60,40 -size 81920

The singular value is reused for later iterations. The example above is interpreted the same as

    $ProgramName -sw 80,60,40 -size 81920,81920,81920

DESCRIPTION

Getopt::Tabular::SetHelp( $help, $description );

# default values
my $given_size = "81920";
my $given_sw = "100";
my $given_lw = "5e-6";
my $given_iter_outer = "1000";
my $given_iter_inner = "50";
my $given_iso = "10";
my $given_si = "0.10";
my $given_subsample = "0";
my $given_self = "0.01";
my $given_self_weight = "1";
my $given_taubin = "0";

my @options = (
   ['-size', 'string', 1, \$given_size, "number of polygons"],
   ['-sw', 'string', 1, \$given_sw, "stretch weight"],
   ['-lw', 'string', 1, \$given_lw, "laplacian weight"],
   ['-iter-outer', 'string', 1, \$given_iter_outer, "total number of iterations per stage"],
   ['-iter-inner', 'string', 1, \$given_iter_inner, "save every few iterations"],
   ['-iso-value', 'string', 1, \$given_iso, "Chamfer value of laplacian map indicating mask boundary (i.e. target value)"],
   ['-step-size', 'string', 1, \$given_si, "Step size per iteration"],
   ['-oversample', 'string', 1, \$given_subsample, "do subsampling (0=none, n=#points extra along edge)"],
   ['-self-dist', 'string', 1, \$given_self, "distance to check for self-intersection"],
   ['-self-weight', 'string', 1, \$given_self_weight, "weight for self-intersection constraint"],
   ['-taubin', 'string', 1, \$given_taubin, "iterations of taubin smoothing to perform between cycles of surface_fit"]
  );

GetOptions( \@options, \@ARGV ) or exit 1;
die "$usage\n" unless @ARGV == 3;

# positional arguments
my $chamfer = shift;
my $white_surface = shift;
my $surface = shift;

# parse CSV values as lists
my @a_size = map { int $_ } split(',', $given_size);
my @a_sw = map { $_ * 1.0 } split(',', $given_sw);
my @a_lw = map { $_ * 1.0 } split(',', $given_lw);
my @a_iter_outer = map { int $_ } split(',', $given_iter_outer);
my @a_iter_inner = map { int $_ } split(',', $given_iter_inner);
my @a_iso = map { $_ * 1.0 } split(',', $given_iso);
my @a_si = map { $_ * 1.0 } split(',', $given_si);
my @a_subsample = map { int $_ } split(',', $given_subsample);
my @a_self_dist = map { $_ * 1.0 } split(',', $given_self);
my @a_self_weight = map { $_ * 1.0 } split(',', $given_self_weight);
my @a_taubin = map { int $_ } split(',', $given_taubin);

my @schedule = ();
my $sched_size = 11;

my $num_rows = max(
  scalar @a_size,
  scalar @a_sw,
  scalar @a_lw,
  scalar @a_iter_outer,
  scalar @a_iter_inner,
  scalar @a_iso,
  scalar @a_si,
  scalar @a_subsample,
  scalar @a_self_dist,
  scalar @a_self_weight,
  scalar @a_taubin
);

for (my $i = 0; $i < $num_rows; $i++) {
  # size  number of triangles
  # sw    weight for mesh stretching (bigger means less stretch)
  #       small value will create a highly voxelated/bumpy surface,
  #       but with good detail.
  #       large value for sw creates a very smooth surface that
  #       destroys topological detail.
  #       sw>40 will not fit into concavities that are 2 voxels wide.
  # n_itr number of iterations
  # inc   save every 20 iters
  # lw    weight for Laplacian field: large value means tighter fit,
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

  my $size = at_or_first(\@a_size, $i);
  my $sw = at_or_first(\@a_sw, $i);
  my $n_itr = at_or_first(\@a_iter_outer, $i);
  my $inc = at_or_first(\@a_iter_inner, $i);
  my $lw = at_or_first(\@a_lw, $i);
  my $iso = at_or_first(\@a_iso, $i);
  my $si = at_or_first(\@a_si, $i);
  my $os = at_or_first(\@a_subsample, $i);
  my $iw = at_or_first(\@a_self_weight, $i);
  my $self_dist = at_or_first(\@a_self_dist, $i);
  my $t = at_or_first(\@a_taubin, $i);

  my @row = ($size, $sw, $n_itr, $inc, $lw, $iso, $si, $os, $iw, $self_dist, $t);

  print "i=$i row=@row\n";
  push(@schedule, @row);
}

copy($white_surface, $surface);

my $tmpdir = &tempdir( "ep-surface_fit_parametarized-XXXXXX", TMPDIR => 1, CLEANUP => 1 );

my $stretch_model = "$tmpdir/stretch_length_model.obj";
my $ICBM_white_model = MNI::DataDir::dir("surface-extraction") . "/white_model_320.obj";
copy($ICBM_white_model, $stretch_model);

my $self_dist2 = 0.001;
my $self_weight2 = 1e08;
my $n_selfs = 9;

my $stop_threshold = 1e-3;
my $stop_iters = 1000;
my $n_per = 5;
my $tolerance = 1.0e-03;
my $f_tolerance = 1.0e-06;

for ( my $i = 0;  $i < @schedule;  $i += $sched_size ) {

  my $row = $i / $sched_size + 1;
  print "Schedule row ${row} / ${num_rows}\n";

  my ( $size, $sw, $n_iters, $iter_inc, $laplacian_weight, $iso,
       $step_increment, $oversample, $self_weight, $self_dist,
       $smooth ) = @schedule[$i..$i+$sched_size-1];

  subdivide_mesh( $surface, $size, $surface );
  subdivide_mesh( $stretch_model, $size, $stretch_model );

  my $self2 = get_self_intersect( $self_weight, $self_weight2, $n_selfs,
                                  $self_dist, $self_dist2 );

  for( my $iter = 0;  $iter < $n_iters;  $iter += $iter_inc ) {
    print "$ProgramName:inner loop iter=$iter n_iters=$n_iters iter_inc=$iter_inc\n";
    my $ni = $n_iters - $iter;
    $ni = $iter_inc if( $ni > $iter_inc );

    my $command = "surface_fit " .
                  "-mode two -surface  $surface $surface" .
                  " -stretch $sw $stretch_model -.9 0 0 0" .
                  " -laplacian $chamfer $laplacian_weight 0 " .
                  " $iso $oversample " .
                  " $self2 -step $step_increment " .
                  " -fitting $ni $n_per $tolerance " .
                  " -ftol $f_tolerance " .
                  " -stop $stop_threshold $stop_iters ";
    print $command . "\n";
    system( $command ) == 0 or die "Command $command failed with status: $?";

    # Add a little bit of Taubin smoothing between cycles.
    &taubinize_surface( $surface, $smooth );
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

# Add a little bit of Taubin smoothing between cycles. This
# can introduce self-intersections, so try to fix those as
# well, in any. If the surface cannot be improved, return the
# original.

sub taubinize_surface {

  my $surf = shift;
  my $iter = shift;

  return if ( $iter == 0 ); # do nothing

  my $tmp_surf = "${tmpdir}/surface_taubin.obj";

  &run( 'adapt_object_mesh', $surf, $tmp_surf, 0, $iter, 0, 0 );
  my $tries = 0;
  do {
    &run( 'check_self_intersect', $tmp_surf, '-fix', $tmp_surf );
    my @ret = `check_self_intersect $tmp_surf`;
    $ret[1] =~ /Number of self-intersecting triangles = (\d+)/;
    if( $1 == 0 ) {
      `mv -f $tmp_surf $surf`;
      $tries = 9999;
    }
    $tries++;
  } while( $tries < 10 );
  unlink( $tmp_surf ) if( -e $tmp_surf );
}

# Execute a system call.

sub run {
  print "@_\n";
  system(@_)==0 or die "Command @_ failed with status: $?";
}


sub at_or_first {
  my $array = shift;
  my $index = shift;

  if ($index < @$array) {
    return @$array[$index];
  }
  return @$array[0];
}
