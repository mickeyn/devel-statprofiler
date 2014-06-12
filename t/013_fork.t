#!/usr/bin/env perl

use Config;
use if !$Config{d_fork}, 'Test::More' => skip_all =>
    "fork() not available";

use t::lib::Test tests => 12;

use Devel::StatProfiler::Reader;
use Time::HiRes qw(usleep);

my $profile_file;
BEGIN { $profile_file = temp_profile_file(); }

use Devel::StatProfiler -template => $profile_file, -interval => 1000;
my ($in_parent_before, $in_parent_after, $in_child);

usleep(50000); BEGIN { $in_parent_before = __LINE__ }

my @parent = glob $profile_file . '*';

my $pid = fork();
die "fork() failed: $!" unless defined $pid;

if ($pid) {
    usleep(50000); BEGIN { $in_parent_after = __LINE__ }
    0; # here to force Perl to generate a nextstate for the previous line...
} else {
    usleep(50000); BEGIN { $in_child = __LINE__ }
    exit 0;
}

die "waitpid() error: $!"
    if waitpid($pid, 0) != $pid;

Devel::StatProfiler::stop_profile();

my @files = glob $profile_file . '*';
@files = reverse @files if $files[0] ne $parent[0];

is(scalar @files, 2, 'both processes wrote a trace file');
my (@sleep_patterns, @genealogies);

for my $file (@files) {
    my $r = Devel::StatProfiler::Reader->new($file);
    my %sleep_pattern;

    while (my $trace = $r->read_trace) {
        my $frames = $trace->frames;

        for my $frame (grep $_->file =~ /013_fork/, @$frames) {
            $sleep_pattern{$frame->line} += $trace->weight;
        }
    }

    push @sleep_patterns, \%sleep_pattern;
    push @genealogies, $r->get_genealogy_info;
}

# parent
ok( exists $sleep_patterns[0]{$in_parent_before});
ok( exists $sleep_patterns[0]{$in_parent_after});
ok(!exists $sleep_patterns[0]{$in_child});
is($genealogies[0][2], "\x00" x 24);
is($genealogies[0][3], 0xffffffff);

#child
ok(!exists $sleep_patterns[1]{$in_parent_before});
ok(!exists $sleep_patterns[1]{$in_parent_after});
ok( exists $sleep_patterns[1]{$in_child});
is($genealogies[1][2], $genealogies[0][0]);
is($genealogies[1][3], $genealogies[0][1]);

# sanity
isnt($genealogies[0][0], $genealogies[1][0]);