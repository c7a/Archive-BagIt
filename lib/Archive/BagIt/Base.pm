use strict;
use warnings;

package Archive::BagIt::Base;

use Moose;
use namespace::autoclean;

use utf8;
use open ':std', ':encoding(utf8)';
use Encode qw(decode);
use File::Find;
use File::Spec;
use File::stat;
use Digest::MD5;
use Class::Load qw(load_class);
use Carp;
use List::Util qw(uniq);

# VERSION

use Sub::Quote;

my $DEBUG=0;

=head1 NAME

Achive::BagIt::Base - The common base for both Bagit and dotBagIt

=head1 AUTHORS

=over

=item Robert Schmidt, E<lt>rjeschmi at gmail.comE<gt>

=item William Wueppelmann, E<lt>william at c7a.caE<gt>

=item Andreas Romeyke, E<lt>pause at andreas minus romeyke.deE<gt>

=back

=head1 CONTRIBUTORS

=over

=item Serhiy Bolkun

=item Russell McOrmond

=back

=head1 SOURCE

The original development version was on github at L<http://github.com/rjeschmi/Archive-BagIt>
and may be cloned from there.

The actual development version is available at L<https://art1pirat.spdns.org/art1/Archive-BagIt>

=head1 TODO

=over

=item Add support for non-Unix based filesystems

=item enhanced testsuite

=item improved plugin mechanism

=item reduce complexity

=item use modern perl code

=item add code to easily update outdated Bags to v1.0

=item add more ecamples in documentation

=back

=cut

has 'bag_path' => (
    is => 'rw',
);

has 'bag_path_arr' => (
    is => 'ro',
    lazy => 1,
    builder => '_build_bag_path_arr',
);

has 'metadata_path' => (
    is=> 'ro',
    lazy => 1,
    builder => '_build_metadata_path',
);

sub _build_metadata_path {
    my ($self) = @_;
    return $self->bag_path;
}


has 'metadata_path_arr' => (
    is =>'ro',
    lazy => 1,
    builder => '_build_metadata_path_arr',
);

has 'rel_metadata_path' => (
    is => 'ro',
    lazy => 1,
    builder => '_build_rel_metadata_path',
);

has 'payload_path' => (
    is => 'ro',
    lazy => 1,
    builder => '_build_payload_path',
);

sub _build_payload_path {
    my ($self) = @_;
    return $self->bag_path."/data";
}

has 'payload_path_arr' => (
    is => 'ro',
    lazy => 1,
    builder => '_build_payload_path_arr',
);

has 'rel_payload_path' => (
    is => 'ro',
    lazy => 1,
    builder => '_build_rel_payload_path',
);

has 'checksum_algos' => (
    is => 'ro',
    lazy => 1,
    builder => '_build_checksum_algos',
);

has 'bag_version' => (
    is       => 'ro',
    lazy     => 1,
    builder  => '_build_bag_version',
);

has 'bag_info' => (
    is      => 'rw',
    lazy    => 1,
    builder => '_build_bag_info',
);

# bag_info_by_key()
sub bag_info_by_key {
    my ($self, $searchkey) = @_;
    my $info = $self->bag_info();
    if (defined $searchkey) {
        foreach my $entry (@{$info}) {
            if (exists $entry->{$searchkey}) {
                return $entry->{$searchkey};
            }
        }
    }
    return;
}


sub _replace_bag_info_by_first_match {
    my ($self, $searchkey, $newvalue) = @_;
    my $info = $self->bag_info();
    if (defined $searchkey) {
        if ($searchkey =~ m/:/) { croak "key should not contain a colon! (searchkey='$searchkey')"; }
        my $size = scalar( @{$info});
        for (my $idx=0; $idx< $size; $idx++) {
            my %entry = %{ $info->[$idx] };
            my ($key, $value) = each %entry;
            if ((defined $key) && ($key eq $searchkey)) {
                $info->[$idx] = {$searchkey => $newvalue};
                return $idx;
            }
        }
    }
    return;
}

sub _add_or_replace_bag_info {
    my ($self, $searchkey, $newvalue) = @_;
    if (defined $searchkey) {
        if ($searchkey =~ m/:/) { croak "key should not contain a colon! (searchkey='$searchkey')"; }
        if (defined $self->{bag_info}) {
            my $idx = $self->_replace_bag_info_by_first_match( $searchkey, $newvalue);
            if (defined $idx) { return $idx;}
        }
        push @{$self->{bag_info}}, {$searchkey => $newvalue};
        return -1;
    }
}


has 'forced_fixity_algorithm' => (
    is   => 'ro',
    lazy => 1,
    builder  => '_build_forced_fixity_algorithm',
);

has 'bag_checksum' => (
    is => 'ro',
    lazy => 1,
    builder => '_build_bag_checksum',
);

has 'manifest_files' => (
    is => 'ro',
    lazy => 1,
    builder => '_build_manifest_files',
);

has 'tagmanifest_files' => (
    is => 'ro',
    lazy => 1,
    builder => '_build_tagmanifest_files',
);

has 'manifest_entries' => (
    is => 'ro',
    lazy => 1,
    builder => '_build_manifest_entries',
);

has 'tagmanifest_entries' => (
    is => 'ro',
    lazy => 1,
    builder => '_build_tagmanifest_entries',
);

has 'payload_files' => ( # relatively to bagit base
    is => 'ro',
    lazy => 1,
    builder => '_build_payload_files',
);

has 'non_payload_files' => (
    is=>'ro',
    lazy => 1,
    builder => '_build_non_payload_files',
);

has 'plugins' => (
    is=>'rw',
    isa=>'HashRef',
);

has 'manifests' => (
    is=>'rw',
    isa=>'HashRef',
);

has 'algos' => (
    is=>'rw',
    isa=>'HashRef',
);

=head2 BUILDARGS

The constructor sub, will create a bag with a single argument
=cut

around 'BUILDARGS' , sub {
    my $orig = shift;
    my $class = shift;
    if (@_ == 1 && !ref $_[0]) {
        return $class->$orig(bag_path=>$_[0]);
    } else {
        return $class->$orig(@_);
    }
};

sub BUILD {
    my ($self, $args) = @_;
    return $self->load_plugins(("Archive::BagIt::Plugin::Manifest::MD5", "Archive::BagIt::Plugin::Manifest::SHA512"));
}

sub _build_bag_path_arr {
    my ($self) = @_;
    my @split_path = File::Spec->splitdir($self->bag_path);
    return @split_path;
}

sub _build_payload_path_arr {
    my ($self) = @_;
    my @split_path = File::Spec->splitdir($self->payload_path);
    return @split_path;
}

sub _build_rel_payload_path {
    my ($self) = @_;
    my $rel_path = File::Spec->abs2rel( $self->payload_path, $self->bag_path ) ;
    return $rel_path;
}

sub _build_metadata_path_arr {
    my ($self) = @_;
    my @split_path = File::Spec->splitdir($self->metadata_path);
    return @split_path;
}

sub _build_rel_metadata_path {
    my ($self) = @_;
    my $rel_path = File::Spec->abs2rel( $self->metadata_path, $self->bag_path ) ;
    return $rel_path;
}

sub _build_checksum_algos {
    my($self) = @_;
    my $checksums = [ 'md5', 'sha1', 'sha256', 'sha512' ];
    return $checksums;
}

sub _build_bag_checksum {
  my($self) =@_;
  my $bagit = $self->{'bag_path'};
  open(my $SRCFILE, "<:raw",  $bagit."/manifest-md5.txt");
  my $srchex=Digest::MD5->new->addfile($SRCFILE)->hexdigest;
  close($SRCFILE);
  return $srchex;
}

sub _build_manifest_files {
  my($self) = @_;
  my @manifest_files;
  foreach my $algo (@{$self->checksum_algos}) {
    my $manifest_file = $self->metadata_path."/manifest-$algo.txt";
    if (-f $manifest_file) {
      push @manifest_files, $manifest_file;
    }
  }
  return \@manifest_files;
}

sub _build_tagmanifest_files {
  my ($self) = @_;
  my @tagmanifest_files;
  foreach my $algo (@{$self->checksum_algos}) {
    my $tagmanifest_file = $self->metadata_path."/tagmanifest-$algo.txt";
    if (-f $tagmanifest_file) {
      push @tagmanifest_files, $tagmanifest_file;
    }
  }
  return \@tagmanifest_files;
}

sub __build_xxxmanifest_entries {
  my ($self, $xxmanifestfiles) = @_;
  my @xxmanifests = @{$xxmanifestfiles};
  my $xxmanifest_entries = {};
  my $bag_path=$self->bag_path();
  foreach my $xxmanifest_file (@xxmanifests) {
    die("Cannot open $xxmanifest_file: $!") unless (open(my $XXMANIFEST,"<:encoding(utf8)", $xxmanifest_file));
    my $algo = $xxmanifest_file;
    $algo =~ s#//#/#g; # to fix problems with double path-separators
    $algo =~ s#^($bag_path/).bagit/#$1#; # FIXME: only for dotbagit-variant, if dotbagit will be outdated, this should be removed
    $algo =~ s#^$bag_path/##;
    $algo =~ s#tag(manifest-[a-z0-9]+\.txt)#$1#;
    $algo =~ s#.*manifest-([a-z0-9]+)\.txt$#$1#;
    if ($algo =~ m#/#) {
        die "wrong replacement of path $xxmanifest_file to determine algorithm '$algo' correctly, please contact author";
    }
    while (my $line = <$XXMANIFEST>) {
      chomp($line);
      my($digest,$file) = split(/\s+/, $line, 2);
      next unless ((defined $digest) && (defined $file)); # empty lines!
      $xxmanifest_entries->{$algo}->{$file} = $digest;
    }
    close($XXMANIFEST);
  }
  return $xxmanifest_entries;
}

sub _build_tagmanifest_entries {
  my ($self) = @_;
  my @tm_files = $self->tagmanifest_files();
  my $entries = $self->__build_xxxmanifest_entries(@tm_files);
  return $entries;
}

sub _build_manifest_entries {
  my ($self) = @_;
  my @m_files = $self->manifest_files();
  my $entries = $self->__build_xxxmanifest_entries(@m_files);
  return $entries;
}

sub _build_payload_files{
  my($self) = @_;
  my $payload_dir = $self->payload_path;
  my $payload_reldir = $self->rel_payload_path;
  my @payload=();
  File::Find::find( sub{
    $File::Find::name = decode ('utf8', $File::Find::name);
    $_ = decode ('utf8', $_);
    if (-f $_) {
        my $rel_path=File::Spec->catdir($self->rel_payload_path,File::Spec->abs2rel($File::Find::name, $payload_dir));
        push(@payload,$rel_path);
    }
    elsif($self->metadata_path_arr > $self->payload_path_arr && -d _ && $_ eq $self->rel_metadata_path) {
        #print "pruning ".$File::Find::name."\n";
        $File::Find::prune=1;
    }
    else {
        #payload directories
    }
    #print "name: ".$File::Find::name."\n";
  }, $payload_dir);
  return wantarray ? @payload : \@payload;

}

sub _build_bag_version {
    my($self) = @_;
    my $bagit = $self->metadata_path;
    my $file = join("/", $bagit, "bagit.txt");
    open(my $BAGIT, "<", $file) or die("Cannot read $file: $!");
    my $version_string = <$BAGIT>;
    my $encoding_string = <$BAGIT>;
    close($BAGIT);
    $version_string =~ /^BagIt-Version: ([0-9.]+)$/;
    return $1 || 0;
}

sub __sort_bag_info {
    my @sorted = sort {
        my %tmpa = %{$a};
        my %tmpb = %{$b};
        my ($ka, $va) = each %tmpa;
        my ($kb, $vb) = each %tmpb;
        my $kres = $ka cmp $kb;
        if ($kres != 0) {
            return $kres;
        } else {
            return $va cmp $vb;
        }
    } @_;
    return @sorted;
}

sub _parse_bag_info { # parses a bag-info textblob
    my ($self, $textblob) = @_;
    #    metadata elements are OPTIONAL and MAY be repeated.  Because "bag-
    #    info.txt" is intended for human reading and editing, ordering MAY be
    #    significant and the ordering of metadata elements MUST be preserved.
    #
    #    A metadata element MUST consist of a label, a colon ":", a single
    #    linear whitespace character (space or tab), and a value that is
    #    terminated with an LF, a CR, or a CRLF.
    #
    #    The label MUST NOT contain a colon (:), LF, or CR.  The label MAY
    #    contain linear whitespace characters but MUST NOT start or end with
    #    whitespace.
    #
    #    It is RECOMMENDED that lines not exceed 79 characters in length.
    #    Long values MAY be continued onto the next line by inserting a LF,
    #    CR, or CRLF, and then indenting the next line with one or more linear
    #    white space characters (spaces or tabs).  Except for linebreaks, such
    #    padding does not form part of the value.
    #
    #    Implementations wishing to support previous BagIt versions MUST
    #    accept multiple linear whitespace characters before and after the
    #    colon when the bag version is earlier than 1.0; such whitespace does
    #    not form part of the label or value.
    # find all labels
    my @labels;
    while ($textblob =~ s/^([^:\s]+)\s*:\s*//m) { # label if starts with chars not colon or whitespace followed by zero or more spaces, a colon, zero or more spaces
        # label found
        my $label = $1; my $value="";

        if ($textblob =~ s/(.+?)(?=^\S)//ms) {
            # value if rest string starts with chars not \r and/or \n until a non-whitespace after \r\n
            $value =$1;
            chomp $value;
        } elsif ($textblob =~ s/(.*)//s) {
            $value = $1;
            chomp $value;
        }
        if (defined $label) {
            push @labels, { "$label" => "$value" };
        }
    }
    # The RFC does not allow reordering:
    #my @sorted = __sort_bag_info(@labels);
    #return \@sorted;
    return \@labels;
}

sub _build_bag_info {
    my ($self) = @_;
    my $bagit = $self->metadata_path;
    my $file = join("/", $bagit, "bag-info.txt");
    open(my $BAGINFO, "<", $file) or die("Cannot read $file: $!");
    my @lines;
    foreach my $line (<$BAGINFO>) {
        push @lines, $line;
    }
    close($BAGINFO);
    my $lines = join("", @lines);
    return $self->_parse_bag_info ($lines);

}

sub _build_non_payload_files {
  my($self) = @_;

  my @non_payload = ();

  File::Find::find( sub{
    $File::Find::name = decode('utf8', $File::Find::name);
    $_=decode ('utf8', $_);
    if (-f $_) {
        my $rel_path=File::Spec->catdir($self->rel_metadata_path,File::Spec->abs2rel($File::Find::name, $self->metadata_path));
        #print "pushing ".$rel_path." payload_dir: $payload_dir \n";
        push(@non_payload,$rel_path);
    }
    elsif($self->metadata_path_arr < $self->payload_path_arr && -d _ && $_ eq $self->rel_payload_path) {
        #print "pruning ".$File::Find::name."\n";
        $File::Find::prune=1;
    }
    else {
        #payload directories
    }
    #print "name: ".$File::Find::name."\n";
  }, $self->metadata_path);

  return wantarray ? @non_payload : \@non_payload;

}

sub _build_forced_fixity_algorithm {
    my ($self) = @_;
    if ($self->bag_version() >= 1.0) {
        return Archive::BagIt::Plugin::Algorithm::SHA512->new(bagit => $self);
    }
    else {
        return Archive::BagIt::Plugin::Algorithm::MD5->new(bagit => $self);
    }
}

=head2 load_plugins

As default SHA512 and MD5 will be loaded and therefore used. If you want to create a bag only with one or a specific
checksum-algorithm, you could use this method to (re-)register it. It expects list of strings with namespace of type:
Archive::BagIt::Plugin::Algorithm::XXX where XXX is your chosen fixity algorithm.

=cut

sub load_plugins {
    my ($self, @plugins) = @_;

    #p(@plugins);
    my $loaded_plugins = $self->plugins;
    @plugins = grep { not exists $loaded_plugins->{$_} } @plugins;

    return if @plugins == 0;
    foreach my $plugin (@plugins) {
        load_class ($plugin) or die ("Can't load $plugin");
        $plugin->new({bagit => $self});
    }

    return 1;
}


sub _verify_XXX_manifests {
    my ($self, $xxprefix, $xxmanifest_entries, $files, $return_all_errors) =@_;
    # Read the manifest file
    my @payload = @{ $files };
    my %invalids;
    my $bagit = $self->bag_path;
    my $version = $self->bag_version();
    my %seen; # mark all processed files
    # Evaluate each file against the manifest
    foreach my $alg (keys %{$xxmanifest_entries}) {
        my $manifest_alg = $self->manifests->{$alg};
        if (! defined $manifest_alg) {
            next;
            # TODO: return Errormessage?
        }
        my $digestobj = $manifest_alg->algorithm();
        my $xxfilename = "${bagit}$xxprefix-$alg.txt";
        foreach my $local_name (@payload) {
            # local_name is relative to bagit base
            my ($digest);
            unless (exists $xxmanifest_entries->{$alg}->{$local_name}) { # localname as value should exist!
                die("file found which is not in $xxfilename: [$local_name] (bag-path:$bagit)");
            }
            if (!-r "$bagit/$local_name") {die("Cannot open $bagit/$local_name");}
            $digest = $digestobj->verify_file("$bagit/$local_name");
            print "digest " . $digestobj->name() . " of $bagit/$local_name: $digest\n" if $DEBUG;
            my $expected_digest = $xxmanifest_entries->{$alg}->{$local_name};
            unless ($digest eq $expected_digest) {
                if ($return_all_errors) {
                    $invalids{$local_name} = $digest;
                } else {
                    die("file: $bagit/$local_name invalid, digest ($alg) calculated=$digest, but expected=$expected_digest in file '$xxfilename'");
                }
            }
            $seen{$alg}{$local_name}=1;
        }
    }
    if($return_all_errors && keys(%invalids) ) {
        foreach my $invalid (keys(%invalids)) {
            print "invalid: $invalid hash: ".$invalids{$invalid}."\n";
        }
        die ("bag verify for bagit $version failed with invalid files");
    }
    # Make sure there are no missing files
    my @missed;
    foreach my $alg (keys %seen){
        foreach my $localfile ( keys %{ $xxmanifest_entries->{$alg} } ) {
            if (exists $seen{$alg}{$localfile} ) { next;}
            else {
                push @missed, "Missing file '$localfile' in bag '$bagit' for algorithm=$alg";
            }
        }
    }
    if (@missed){
        die join("\n", @missed);
    }
    return 1;
}

sub _verify_manifests {
    my ($self, $alg, $return_all_errors) = @_;
    $self->_verify_XXX_manifests(
        "manifest",
        $self->manifest_entries(),
        $self->payload_files(),
        $return_all_errors
    );
    return 1;
}

sub _verify_tagmanifests {
    my ($self, $alg, $return_all_errors) = @_;
    # filter tagmanifest-files
    my @non_payload_files = grep { $_ !~ m/tagmanifest-[a-z0-9]+\.txt/} @{ $self->non_payload_files };
    $self->_verify_XXX_manifests(
        "tagmanifest",
        $self->tagmanifest_entries(),
        \@non_payload_files,
        $return_all_errors
    );
    return 1;
}


=head2 verify_bag

An interface to verify a bag.

You might also want to check Archive::BagIt::Fast to see a more direct way of accessing files (and thus faster).


=cut

sub verify_bag {
    my ($self,$opts) = @_;
    #removed the ability to pass in a bag in the parameters, but might want options
    #like $return all errors rather than dying on first one
    my $bagit = $self->bag_path;
    my $version = $self->bag_version(); # to call trigger
    my $forced_fixity_alg = $self->forced_fixity_algorithm()->name();
    my $manifest_file = $self->metadata_path."/manifest-$forced_fixity_alg.txt"; # FIXME: use plugin instead
    my $payload_dir   = $self->payload_path;
    my $return_all_errors = $opts->{return_all_errors};



    die("$manifest_file is not a regular file for bagit $version") unless -f ($manifest_file);
    die("$payload_dir is not a directory") unless -d ($payload_dir);

    unless ($version > .95) {
        die ("Bag Version $version is unsupported");
    }

    # check forced fixity
    $self->_verify_manifests($forced_fixity_alg, $return_all_errors);
    $self->_verify_tagmanifests($forced_fixity_alg, $return_all_errors);

    # TODO: check if additional algorithms are used



    return 1;
}

=head2 calc_payload_oxum()

returns an array with octets and streamcount of payload-dir

=cut



sub calc_payload_oxum {
    my($self) = @_;
    my @payload = @{$self->payload_files};
    my $octets=0;
    my $streamcount = scalar @payload;
    foreach my $local_name (@payload) {# local_name is relative to bagit base
        my $file = $self->bag_path()."/$local_name";
        my $sb = stat($file);
        $octets += $sb->size;
    }
    return ($octets, $streamcount);
}

=head2 calc_bagsize()

returns a string with human readable size of paylod

=cut

sub calc_bagsize {
    my($self) = @_;
    my ($octets,$streamcount) = $self->calc_payload_oxum();
    if ($octets < 1024) { return "$octets B"; }
    elsif ($octets < 1024*1024) {return sprintf("%0.1f kB", $octets/1024); }
    elsif ($octets < 1024*1024*1024) {return sprintf "%0.1f MB", $octets/(1024*1024); }
    elsif ($octets < 1024*1024*1024*1024) {return sprintf "%0.1f GB", $octets/(1024*1024*1024); }
    else { return sprintf "%0.2f TB", $octets/(1024*1024*1024*1024); }
}

sub create_bagit {
    my($self) = @_;
    my $metadata_path = $self->metadata_path();
    open(my $BAGIT, ">", "$metadata_path/bagit.txt") or die("Can't open $metadata_path/bagit.txt for writing: $!");
    print($BAGIT "BagIt-Version: 1.0\nTag-File-Character-Encoding: UTF-8");
    close($BAGIT);
    return 1;
}

sub create_baginfo {
    use POSIX;
    my($self) = @_; # because bag-info.txt allows multiple key-value-entries, hash is replaced
    $self->_add_or_replace_bag_info('Bagging-Date', POSIX::strftime("%F", gmtime(time)));
    $self->_add_or_replace_bag_info('Bag-Software-Agent', 'Archive::BagIt <https://metacpan.org/pod/Archive::BagIt>');
    my ($octets, $streams) = $self->calc_payload_oxum();
    $self->_add_or_replace_bag_info('Payload-Oxum', "$octets.$streams");
    $self->_add_or_replace_bag_info('Bag-Size', $self->calc_bagsize());
    # The RFC does not allow reordering:
    my $metadata_path = $self->metadata_path();
    open(my $BAGINFO, ">", "$metadata_path/bag-info.txt") or die("Can't open $metadata_path/bag-info.txt for writing: $!");
    foreach my $entry (@{ $self->bag_info() }) {
        my %tmp = %{ $entry };
        my ($key, $value) = each %tmp;
        if ($key =~ m/:/) { carp "key should not contain a colon! (searchkey='$key')"; }
        print($BAGINFO "$key: $value\n");
    }
    close($BAGINFO);
    return 1;
}

=head2 store

store a bagit-obj if bagit directory-structure was already constructed,

=cut

sub store {
    my($self) = @_;
    $self->create_bagit();
    $self->create_baginfo();
    # it is important to create all manifest files first, because tagmanifest should include all manifest-xxx.txt
    foreach my $algorithm ( keys %{ $self->manifests }) {
        $self->manifests->{$algorithm}->create_manifest();
    }
    foreach my $algorithm ( keys %{ $self->manifests }) {
        $self->manifests->{$algorithm}->create_tagmanifest();
    }
    # retrigger builds
    $self->{checksum_algos} = $self->_build_checksum_algos();
    $self->{tagmanifest_files} = $self->_build_tagmanifest_files();
    $self->{manifest_files} = $self->_build_manifest_files();
    return 1;
}

=head2 init_metadata

A constructor that will just create the metadata directory

This won't make a bag, but it will create the conditions to do that eventually

=cut

sub init_metadata {
    my ($class, $bag_path) = @_;
    $bag_path =~ s#/$##; # replace trailing slash
    unless ( -d $bag_path) { die ( "source bag directory '$bag_path' doesn't exist"); }
    my $self = $class->new(bag_path=>$bag_path);
    warn "no payload path\n" if ! -d $self->payload_path;
    unless ( -d $self->payload_path) {
        rename ($bag_path, $bag_path.".tmp");
        mkdir  ($bag_path);
        rename ($bag_path.".tmp", $self->payload_path);
    }
    unless ( -d $self->metadata_path) {
        #metadata path is not the root path for some reason
        mkdir ($self->metadata_path);
    }

    $self->store();
    # FIXME: deprecated?
    #foreach my $algorithm (keys %{$self->manifests}) {
        #$self->manifests->{$algorithm}->create_bagit();
        #$self->manifests->{$algorithm}->create_baginfo();
    #}



    return $self;
}


=head2 make_bag

A constructor that will make and return a bag from a directory,

It expects a preliminary bagit-dir exists.
If there a data directory exists, assume it is already a bag (no checking for invalid files in root)


=cut

sub make_bag {
  my ($class, $bag_path) = @_;
  my $isa = ref $class;
  if ($isa eq "Archive::BagIt::Base") { # not a class, but an object!
    die "make_bag() only a class subroutine, not useable with objects. Try store() instead!\n";
  }
  my $self = $class->init_metadata($bag_path);
  return $self;
}


__PACKAGE__->meta->make_immutable;

1;
