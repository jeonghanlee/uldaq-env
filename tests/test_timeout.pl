#!/usr/bin/env perl
# Timeout test of the ULDAQ network configuration items DEV_CFG_NET_CONNECT_TIMEOUT and
# DEV_CFG_NET_COMMAND_TIMEOUT against an installed patched library.
#
# The library is the real one. Only the external TC32 endpoint is simulated by the fixture in
# tests/fixtures/TC32.pm, inside a network namespace that this script enters itself.
#
# Exit status: 0 all checks passed, 1 a check failed, 2 usage error or an environment or
# collection error that leaves the verdict incomplete.
use strict;
use warnings;

use Cwd qw(abs_path);
use Digest::SHA;
use FindBin qw($RealBin);
use Getopt::Long qw(GetOptions);
use IO::Select;
use POSIX qw(:sys_wait_h);
use Time::HiRes qw(clock_gettime CLOCK_MONOTONIC);

use lib "$RealBin/fixtures";
use TC32;

use constant NAMESPACE_MARK => 'ULDAQ_TIMEOUT_NAMESPACE';
use constant ADDRESS        => '192.0.2.2';
use constant PORT           => 54211;
use constant INTERFACE      => 'sim0';
use constant DEFAULT_MS     => 3000;

# Window of a wait that must last the expected time T: it cannot end earlier than T minus the
# millisecond truncation of the clock reads, and it ends no later than T plus the rounding up of
# the kernel timer wheel (at most 12.5 percent of T) plus a fixed allowance for scheduling.
use constant EARLY_SLACK_MS => 5;
use constant OVERSHOOT_RATE => 0.125;
use constant OVERSHOOT_MS   => 100;
use constant REPLY_BOUND_S  => 30;
use constant CMD_DIN        => 0x00;

my $USAGE = "Usage: test_timeout.pl --prefix DIR --workspace DIR\n"
    . "  --prefix DIR     installation prefix of the patched library (include and lib)\n"
    . "  --workspace DIR  new directory for the client binary and the evidence\n";

my @results;
my $fixture;
my $client_pid;
my ($client_in, $client_out);
my $client_buffer = '';
my $evidence = '';

sub now { return clock_gettime(CLOCK_MONOTONIC); }

sub fail_incomplete {
    my ($message) = @_;
    die "incomplete: $message\n";
}

sub find_command {
    my ($name) = @_;
    for my $dir (split(/:/, ($ENV{PATH} // '')), '/usr/sbin', '/sbin') {
        my $path = "$dir/$name";
        return $path if -x $path && !-d $path;
    }
    fail_incomplete("command not found: $name");
}

# Runs a command without a shell and returns when it exits with status 0.
sub run_command {
    my (@command) = @_;
    my $pid = fork();
    defined $pid or fail_incomplete("fork: $!");
    if (!$pid) {
        exec { $command[0] } @command or exit 127;
    }
    waitpid($pid, 0) == $pid or fail_incomplete("waitpid: $!");
    my $status = $?;
    if ($status != 0) {
        my $how = ($status & 127) ? 'signal ' . ($status & 127) : 'status ' . ($status >> 8);
        fail_incomplete("command failed with $how: @command");
    }
    return;
}

sub append_evidence {
    my ($name, $content) = @_;
    my $path = "$evidence/$name";
    open(my $handle, '>>', $path) or fail_incomplete("open $path: $!");
    print {$handle} $content or fail_incomplete("write $path: $!");
    close($handle) or fail_incomplete("close $path: $!");
    return;
}

sub enter_namespace {
    my (@args) = @_;
    exec { 'unshare' } 'unshare', '-Urn', '/usr/bin/env', NAMESPACE_MARK . '=1', $^X, abs_path($0), @args
        or fail_incomplete("cannot enter a network namespace with unshare -Urn: $!");
}

sub prepare_network {
    my $ip = find_command('ip');
    run_command($ip, 'link', 'set', 'lo', 'up');
    run_command($ip, 'link', 'add', INTERFACE, 'type', 'dummy');
    run_command($ip, 'addr', 'add', '192.0.2.1/24', 'dev', INTERFACE);
    run_command($ip, 'link', 'set', INTERFACE, 'up');
    run_command($ip, 'addr', 'add', ADDRESS . '/32', 'dev', 'lo');
    return;
}

sub build_client {
    my ($prefix) = @_;
    my $binary = "$evidence/timeout_client";
    my @command = (find_command('g++'), '-o', $binary, "$RealBin/timeout_client.cpp",
        "-I$prefix/include", "-L$prefix/lib", "-Wl,-rpath,$prefix/lib", '-luldaq');
    append_evidence('commands.txt', "@command\n");
    run_command(@command);
    return $binary;
}

sub start_client {
    my ($binary) = @_;
    pipe(my $in_read, my $in_write) or fail_incomplete("pipe: $!");
    pipe(my $out_read, my $out_write) or fail_incomplete("pipe: $!");
    my $pid = fork();
    defined $pid or fail_incomplete("fork: $!");
    if (!$pid) {
        close($in_write);
        close($out_read);
        open(STDIN, '<&', $in_read) or exit 126;
        open(STDOUT, '>&', $out_write) or exit 126;
        exec { $binary } $binary or exit 127;
    }
    close($in_read);
    close($out_write);
    $client_pid = $pid;
    $client_in = $in_write;
    $client_out = $out_read;
    return;
}

# Sends one command to the client and serves the fixture until the one-line reply arrives.
sub ask {
    my ($line) = @_;
    my $written = syswrite($client_in, "$line\n");
    defined $written && $written == length($line) + 1 or fail_incomplete("write to the client: $!");
    my $selector = IO::Select->new($client_out);
    my $limit = now() + REPLY_BOUND_S;
    while (1) {
        $fixture->poll(0.005);
        if ($selector->can_read(0)) {
            my $count = sysread($client_out, my $data, 4096);
            defined $count or fail_incomplete("read from the client: $!");
            $count or fail_incomplete("the client ended while answering: $line");
            $client_buffer .= $data;
        }
        if ($client_buffer =~ s/\A([^\n]*)\n//) {
            my $reply = $1;
            append_evidence('client.txt', "> $line\n< $reply\n");
            my @fields = split(/ /, $reply);
            my ($name) = split(/ /, $line);
            ($fields[0] // '') eq $name or fail_incomplete("unexpected reply '$reply' to '$line'");
            return @fields;
        }
        now() < $limit or fail_incomplete("no reply to '$line' within " . REPLY_BOUND_S . " s");
    }
}

sub check {
    my ($name, $condition, $detail) = @_;
    my $ok = $condition ? 1 : 0;
    push @results, [$name, $ok, $detail];
    printf "[%s] %s (%s)\n", $ok ? 'PASS' : 'FAIL', $name, $detail;
    append_evidence('checks.tsv', join("\t", $ok ? 'PASS' : 'FAIL', $name, $detail) . "\n");
    return;
}

sub window {
    my ($expected) = @_;
    return ($expected - EARLY_SLACK_MS, $expected * (1 + OVERSHOOT_RATE) + OVERSHOOT_MS);
}

sub within_window {
    my ($actual, $expected) = @_;
    my ($low, $high) = window($expected);
    return ($actual >= $low && $actual <= $high) ? 1 : 0;
}

sub window_detail {
    my ($actual, $expected) = @_;
    my ($low, $high) = window($expected);
    return sprintf('elapsed=%s ms window=%.1f..%.1f ms', $actual, $low, $high);
}

sub record_library {
    my ($prefix, $binary) = @_;
    my $library = abs_path("$prefix/lib/libuldaq.so");
    defined $library or fail_incomplete("no library at $prefix/lib/libuldaq.so");
    my $digest = Digest::SHA->new(256);
    $digest->addfile($library);
    append_evidence('library.txt', "library=$library\nsha256=" . $digest->hexdigest . "\nclient=$binary\n");
    return;
}

sub scenario {
    my ($line, @fields);

    # The fixture answers the discovery query while the descriptor is read.
    $fixture->{online} = 1;
    @fields = ask('descriptor ' . ADDRESS . ' ' . PORT . ' ' . INTERFACE);
    $fields[1] == 0 or fail_incomplete("the descriptor query failed with error $fields[1]");
    @fields = ask('create');
    $fields[1] == 0 or fail_incomplete('the device object was not created');

    # Defaults of a new device object.
    @fields = ask('get connect');
    check('default connection timeout', $fields[1] == 0 && $fields[2] == DEFAULT_MS, "error=$fields[1] value=$fields[2]");
    @fields = ask('get command');
    check('default command timeout', $fields[1] == 0 && $fields[2] == DEFAULT_MS, "error=$fields[1] value=$fields[2]");

    # A silent device and the default timeouts: the connection steps take the default 3000 ms.
    $fixture->{online} = 0;
    @fields = ask('connect');
    check('default connect fails against a silent device', $fields[1] != 0, "error=$fields[1]");
    check('default connect time', within_window($fields[2], DEFAULT_MS), window_detail($fields[2], DEFAULT_MS));
    $fixture->{online} = 1;

    # Set and read back.
    @fields = ask('set connect 700');
    my $set_connect = $fields[1];
    @fields = ask('set command 300');
    my $set_command = $fields[1];
    check('set both timeouts', $set_connect == 0 && $set_command == 0, "errors=$set_connect,$set_command");
    @fields = ask('get connect');
    my $got_connect = $fields[2];
    @fields = ask('get command');
    check('read back both timeouts', $got_connect == 700 && $fields[2] == 300, "connect=$got_connect command=$fields[2]");

    # Values that are not positive or do not fit are rejected, and the stored values stay.
    my $bad_config_value = 25;
    for my $value ('0', '-1', '2147483648') {
        @fields = ask("set connect $value");
        check("connection timeout $value rejected", $fields[1] == $bad_config_value, "error=$fields[1] expected=$bad_config_value");
        @fields = ask("set command $value");
        check("command timeout $value rejected", $fields[1] == $bad_config_value, "error=$fields[1] expected=$bad_config_value");
    }
    @fields = ask('get connect');
    $got_connect = $fields[2];
    @fields = ask('get command');
    check('rejected values leave the timeouts unchanged', $got_connect == 700 && $fields[2] == 300, "connect=$got_connect command=$fields[2]");

    # A silent device with connection 700 ms and command 300 ms: the connection steps take 700 ms.
    $fixture->{online} = 0;
    @fields = ask('connect');
    check('configured connect fails against a silent device', $fields[1] != 0, "error=$fields[1]");
    check('configured connect time', within_window($fields[2], 700), window_detail($fields[2], 700));
    $fixture->{online} = 1;

    # A command to a device that stops answering takes the command timeout plus the connection
    # timeout: connection 600 ms, command 400 ms.
    ask('set connect 600');
    ask('set command 400');
    @fields = ask('connect');
    $fields[1] == 0 or fail_incomplete("the connection to the answering device failed with error $fields[1]");
    my $faults_before = scalar @{$fixture->{faults}};
    $fixture->{fault} = [CMD_DIN, 'timeout'];
    @fields = ask('din');
    check('command to a silent device fails', $fields[1] != 0, "error=$fields[1]");
    check('silent command time', within_window($fields[2], 1000), window_detail($fields[2], 1000));
    my @reached = grep { $_->[0] == CMD_DIN && $_->[1] eq 'timeout' } @{$fixture->{faults}}[$faults_before .. $#{$fixture->{faults}}];
    check('the timeout fault reached the device', scalar(@reached) == 1, 'faults=' . scalar(@reached));

    # The same handle keeps its values when it is connected again.
    ask('disconnect');
    $fixture->{online} = 1;
    @fields = ask('connect');
    check('reconnect on the same handle', $fields[1] == 0, "error=$fields[1]");
    @fields = ask('get connect');
    $got_connect = $fields[2];
    @fields = ask('get command');
    check('values kept after reconnect', $got_connect == 600 && $fields[2] == 400, "connect=$got_connect command=$fields[2]");

    ask('disconnect');
    ask('release');
    check('the fixture recorded no unsupported request', scalar(@{$fixture->{errors}}) == 0, 'errors=' . scalar(@{$fixture->{errors}}));
    return;
}

sub stop_client {
    return unless $client_pid;
    syswrite($client_in, "quit\n");
    close($client_in);
    my $limit = now() + 5;
    while (now() < $limit) {
        my $done = waitpid($client_pid, WNOHANG);
        if ($done == $client_pid) { $client_pid = undef; return; }
        select(undef, undef, undef, 0.05);
    }
    kill 'KILL', $client_pid;
    waitpid($client_pid, 0);
    $client_pid = undef;
    return;
}

sub main {
    my (@args) = @_;
    my ($prefix, $workspace, $help);
    GetOptions('prefix=s' => \$prefix, 'workspace=s' => \$workspace, 'help' => \$help) or do {
        print STDERR $USAGE;
        return 2;
    };
    if ($help) { print $USAGE; return 0; }
    if (!defined $prefix || !defined $workspace || @ARGV) {
        print STDERR $USAGE;
        return 2;
    }
    -d "$prefix/lib" && -f "$prefix/include/uldaq.h" or do {
        print STDERR "test_timeout: no installed library under $prefix\n";
        return 2;
    };
    $prefix = abs_path($prefix);
    $workspace = abs_path($workspace) // $workspace;
    if (!$ENV{+NAMESPACE_MARK}) {
        enter_namespace('--prefix', $prefix, '--workspace', $workspace);
    }
    -e $workspace and do {
        print STDERR "test_timeout: workspace exists: $workspace\n";
        return 2;
    };
    mkdir($workspace) or do {
        print STDERR "test_timeout: mkdir $workspace: $!\n";
        return 2;
    };
    $evidence = $workspace;

    my $verdict = 'Incomplete';
    my $status = 2;
    my $ok = eval {
        prepare_network();
        my $binary = build_client($prefix);
        record_library($prefix, $binary);
        $fixture = TC32->new(ADDRESS, PORT, {mac => "\x02\0\0\0\0\x32"});
        start_client($binary);
        scenario();
        1;
    };
    my $error = $ok ? '' : $@;
    stop_client();
    $fixture->close() if $fixture;
    if ($ok) {
        my @failed = grep { !$_->[1] } @results;
        $status = @failed ? 1 : 0;
        $verdict = @failed ? 'Failed' : 'Passed';
    } else {
        print STDERR "test_timeout: $error";
    }
    printf "%s: %d checks, %d failed; evidence %s\n", $verdict, scalar(@results), scalar(grep { !$_->[1] } @results), $workspace;
    append_evidence('result.txt', "verdict=$verdict\nchecks=" . scalar(@results) . "\nerror=$error");
    return $status;
}

my $exit_status;
eval {
    $exit_status = main(@ARGV);
    defined $exit_status or die "internal error: main returned no exit status\n";
    1;
} or do {
    my $error = $@;
    print STDERR "test_timeout: $error";
    $exit_status = 2;
};
exit $exit_status;
