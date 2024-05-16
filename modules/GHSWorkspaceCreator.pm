package GHSWorkspaceCreator;

# ************************************************************
# Description   : A GHS Workspace creator for version 4.x
# Author        : Chad Elliott
# Create Date   : 7/3/2002
# ************************************************************

# ************************************************************
# Pragmas
# ************************************************************

use strict;

use GHSProjectCreator;
use WorkspaceCreator;
use GHSPropertyBase;

use vars qw(@ISA);
@ISA = qw(GHSPropertyBase WorkspaceCreator);

# ************************************************************
# Data Section
# ************************************************************

my %directives = ('I'          => 1,
                  'L'          => 1,
                  'D'          => 1,
                  'l'          => 1,
                  'G'          => 1,
                  'non_shared' => 1,
                  'bsp'        => 1,
                  'os_dir'     => 1,
                 );
my $tgt;
my $integrity  = '[INTEGRITY Application]';
my @integ_bsps;

# ************************************************************
# Subroutine Section
# ************************************************************

sub compare_output {
  #my $self = shift;
  return 1;
}


sub workspace_file_name {
  return $_[0]->get_modified_workspace_name('default', '.gpj');
}


sub pre_workspace {
  my($self, $fh) = @_;
  my $crlf = $self->crlf();
  my $prjs = $self->get_projects();

  ## Take the primaryTarget from the first project in the list
  if (defined $$prjs[0]) {
    my $fh      = new FileHandle();
    my $outdir  = $self->get_outdir();
    if (open($fh, "$outdir/$$prjs[0]")) {
      while(<$fh>) {
        if (/^#primaryTarget=(.+)$/) {
          $tgt = $1;
          last;
        }
      }
      close($fh);
    }
  }

  # TODO(sonndinh): Some platform information is configurable such as
  # the path to an INTEGRITY installation, bsp name.
  # Some other information is specific to ACE such as its root directory,
  # its compilation and linking requirements (C++ version, flags, etc).
  # These can be put in some form of input to MPC instead of hardcoded here.
  # Update: We can use environment variables and command-line options:
  # --expand_vars, -use_env. Or can use the -relative command-line option.
  # The first option requires setting environment variables.
  # The second option requires passing parameters to the -relative option.

  ## Try to read the INTEGRITY installation directory and BSP name from environment.
  ## Default values are the installation directory on Windows and the BSP name
  ## for the simulator for PowerPC architecture.
  my $ghs_os_dir = defined $ENV{GHS_OS_DIR} ? $ENV{GHS_OS_DIR} : 'C:\ghs\int1146';
  my $ghs_bsp_name = defined $ENV{GHS_BSP_NAME} ? $ENV{GHS_BSP_NAME} : "sim800";

  ## Print out the preliminary information
  print $fh "#!gbuild$crlf",
            "macro __OS_DIR=$ghs_os_dir$crlf",
            "macro __BSP_NAME=$ghs_bsp_name$crlf",
            "macro __BSP_DIR=\${__OS_DIR}\\\${__BSP_NAME}$crlf",
            "macro ACE_ROOT=%expand_path(.)$crlf",
            "macro __BUILD_DIR=\${ACE_ROOT}\\build$crlf",
            "macro __LIBS_DIR_BASE=\${__OS_DIR}\\libs$crlf",
            "primaryTarget=$tgt$crlf",
            "customization=\${__OS_DIR}\\target\\integrity.bod$crlf",
            "[Project]$crlf",
            "\t-gcc$crlf",
            "\t--c++14$crlf",
            "\t--libcxx$crlf",
            "\t:sourceDir=.$crlf",
            "\t:optionsFile=\${__OS_DIR}\\target\\\${__BSP_NAME}.opt$crlf",
	          "\t-I\${ACE_ROOT}$crlf",
	          "\t-language=cxx$crlf",
	          "\t--new_style_casts$crlf",
	          "\t-non_shared$crlf";
}

# TODO(sonndinh): Looks like this only support [INTEGRITY Application] with
# only one [Program] (i.e., executable) in the image. But this seems sufficient
# for most cases. How does a [INTEGRITY Application] gpj file look with more
# than one [Program]s and how does the corresponding .int file look?
sub create_integrity_project {
  my($self, $int_proj, $project, $type, $target) = @_;
  my $outdir   = $self->get_outdir();
  my $crlf     = $self->crlf();
  my $fh       = new FileHandle();
  my $int_file = $int_proj;
  $int_file =~ s/\.gpj$/.int/;

  if (open($fh, ">$outdir/$int_proj")) {
    ## First print out the project file
    print $fh "#!gbuild$crlf",
              "\t$integrity$crlf",
              "$project\t\t$type$crlf",
              "$int_file$crlf";
    foreach my $bsp (@integ_bsps) {
      print $fh "$bsp$crlf";
    }
    close($fh);

    ## Next create the integration file
    if (open($fh, ">$outdir/$int_file")) {
      print $fh "Kernel$crlf",
                "\tFilename\t\t\tDynamicDownload$crlf",
                "EndKernel$crlf$crlf",
                "AddressSpace$crlf",
                "\tFilename\t\t\t$target$crlf",
                "\tLanguage\t\t\tC++$crlf",
                #"\tLibrary\t\t\t\tlibINTEGRITY.so$crlf",
                #"\tLibrary\t\t\t\tlibc.so$crlf",
                #"\tLibrary\t\t\t\tlibscxx_e.so$crlf",
                "\tTask Initial$crlf",
                "\t\tStackLength\t\t0x8000$crlf",
                "\tEndTask$crlf",
                "EndAddressSpace$crlf";
      close($fh);
    }
  }
}


sub mix_settings {
  my($self, $project) = @_;
  my $rh     = new FileHandle();
  my $mix    = $project;
  my $outdir = $self->get_outdir();

  ## Things that seem like they should be set in the project
  ## actually have to be set in the controlling project file.
  if (open($rh, "$outdir/$project")) {
    my $crlf = $self->crlf();
    my $integrity_project = (index($tgt, 'integrity') >= 0);
    my($int_proj, $int_type, $target);

    # (sonndinh): Go through the lines in this project's gpj file.
    # Each line may result in some changes added to the workspace gpj file.
    # The changes are returned in the $mix variable.
    # In case the project is an
    while(<$rh>) {
      # (sonndinh): Don't need to add compiler/linker options to the workspace file.
      # The gpj file for each individual project should have those already.
      # In the workspace file (the top-level project file), only need to list the child projects.
      if (/^\s*(\[(Program|Library|Subproject)\])\s*$/) {
        my $type = $1;
        if ($integrity_project && $type eq '[Program]') {
          $int_proj = $project;             #E.g., tests/ARGV_Test.gpj
          $int_proj =~ s/(\.gpj)$/_int$1/;  #E.g., tests/ARGV_Test_int.gpj
          $int_type = $type;                #E.g., [Program]
          $mix =~ s/(\.gpj)$/_int$1/;       #E.g., tests/ARGV_Test_int.gpj
          $type = $integrity;               # [INTEGRITY Application]
        }
        $mix .= "\t\t$type$crlf";
        #$mix .= "\t\t$type$crlf" .
        #        "\t-object_dir=" . $self->mpc_dirname($project) .
        #        '/.obj' . $crlf;
      }
      elsif (/^\s*(\[Shared Object\])\s*$/) {
        $mix .= "\t\t$1$crlf";
        #$mix .= "\t\t$1$crlf" .
        #        "\t-pic$crlf" .
        #        "\t-object_dir=" . $self->mpc_dirname($project) .
        #        '/.shobj' . $crlf;
      }
      elsif ($integrity_project && /^(.*\.bsp)\s/) {
        push(@integ_bsps, $1);
      }
      else {
        if (/^\s*\-((\w)\w*)/) {
          ## Save the required options into the mixed project string
          if (defined $directives{$2} || defined $directives{$1}) {
            #$mix .= $_;
          }

          ## If this is an integrity project, we need to find out
          ## what the output file will be for the integrate file.
          if (defined $int_proj && /^\s*\-o\s+(.*)\s$/) {
            $target = $1;
          }
        }
      }
    }
    if (defined $int_proj) {
      $self->create_integrity_project($int_proj, $project,
                                      $int_type, $target);
    }
    close($rh);
  }

  return $mix;
}


sub write_comps {
  my($self, $fh) = @_;

  #my $projects = $self->get_projects();
  #my @list = $self->sort_dependencies($projects);

  #foreach (@list) {
  #  print "$_\n";
  #}

  # TODO(sonndinh): Looks like the individual project files are produced before this happens.
  # And this module relies on them to add contents to the workspace file (default.gpj in case of GHS).

  ## Print out each project
  foreach my $project ($self->sort_dependencies($self->get_projects(), 0)) {
    print $fh $self->mix_settings($project);
  }
}



1;
