#!/usr/bin/perl

# Test the RPC::XML::Procedure class (and the ::Method and ::Function classes)

use strict;
use warnings;
use vars qw($obj $obj2 $flag $dir $vol $tmp);

use File::Spec;
use Test::More;

use RPC::XML qw($ALLOW_NIL RPC_INT);
use RPC::XML::Procedure;

plan tests => 60;

($vol, $dir, undef) = File::Spec->splitpath(File::Spec->rel2abs($0));
$dir = File::Spec->catpath($vol, $dir, '');

# The organization of the test suites is such that we assume anything that
# runs before the current suite is 100%. Thus, no consistency checks on
# any other classes are done, only on the data and return values of this
# class under consideration, RPC::XML::Procedure. As such, we are not testing
# any part of the RPC::XML::Server class here. Only the code for managing
# methods.

# Basic new() success, simple accessors and successful calling
$obj = RPC::XML::Procedure->new({ name      => 'test.test',
                                  signature => [ 'int' ],
                                  code      => sub { $flag = 1; } });
isa_ok($obj, 'RPC::XML::Procedure', '$obj');
SKIP: {
    skip 'Cannot test without object', 16
        unless (ref($obj) eq 'RPC::XML::Procedure');

    ok(($obj->name() eq 'test.test') &&
       ($obj->namespace() eq '') &&
       (scalar(@{$obj->signature}) == 1) &&
       ($obj->signature->[0] eq 'int'),
       'Basic accessors');
    $flag = 0;
    eval { $obj->code->(); };
    ok((! $@) && $flag, 'Calling the code');
    ok($obj->is_valid(), 'Test is_valid() method');

    # What about the missing values?
    is($obj->help(),      '', 'Null value for help()');
    is($obj->namespace(), '', 'Null value for namespace()');
    is($obj->version(),   0,  'Zero value for version()');
    is($obj->hidden(),    0,  'Zero value for hidden()');

    # Try changing the attributes that can change:
    $obj->help('help');
    is($obj->help(), 'help', 'help() changes correctly');
    $obj->version('1.1.1');
    is($obj->version(), '1.1.1', 'version() changes correctly');
    $obj->hidden(1);
    is($obj->hidden(), 1, 'hidden() changes correctly');
    my $sub = sub { 'foo' };
    $obj->code($sub);
    is($obj->code(), $sub, 'code() changes correctly');
    # Try a value that should be rejected
    $obj->code([]);
    is($obj->code(), $sub, 'code() did not change to a bad value');
    # Changing signature() is tricky
    $obj->signature([ 'int int', 'string string', 'double double' ]);
    is(scalar(@{$obj->signature}), 3, 'signature() changes correctly');
    # This one should fail
    my $err = $obj->signature([ qw(int double) ]);
    like($err, qr/Cannot have two different return values/,
         'signature() failed correctly on ambiguous data');
    is(scalar(@{$obj->signature}), 3, 'signature() reverted to old value');
    # This should fail for a different reason
    $err = $obj->signature(1);
    like($err, qr/Bad value '1'/, 'signature() failed correctly on bad input')
}

# Basic new() using faux hash table input
$obj = RPC::XML::Procedure->new(
    name      => 'test.test',
    hidden    => 1,
    signature => 'int int',
    signature => [ qw(string string) ],
    code      => sub { 1; }
);
isa_ok($obj, 'RPC::XML::Procedure', '$obj<2>');
SKIP: {
    skip 'Cannot test without object', 3
        unless (ref($obj) eq 'RPC::XML::Procedure');

    ok(($obj->name() eq 'test.test') &&
       ($obj->namespace() eq '') &&
       (scalar(@{$obj->signature}) == 2) &&
       ($obj->signature->[0] eq 'int int') &&
       ($obj->signature->[1] eq 'string string'),
       'Basic accessors <2>');
    $flag = eval { $obj->code->(); };
    ok((! $@) && $flag, 'Calling the code <2>');
    ok($obj->is_valid(), 'Test is_valid() method <2>');
}

# This should succeed, but "hidden" is false because the second overrides the
# first.
$obj = RPC::XML::Procedure->new(
    name      => 'test.test',
    hidden    => 1,
    hidden    => 0,
    signature => 'int int',
    signature => [ qw(string string) ],
    code      => sub { 1; }
);
isa_ok($obj, 'RPC::XML::Procedure', '$obj<3>');
is($obj->hidden(), 0, 'hidden() is correctly false');

# This should fail due to missing information (the signature)
$obj = RPC::XML::Method->new({ name => 'test.test2',
                               code => sub { $flag = 2; } });
ok(! ref($obj), 'Correct constructor failure [1]');

# This one fails because the signatures have a collision
$obj = RPC::XML::Method->new({ name      => 'test.test2',
                               signature => [ 'int int',
                                              'string int' ],
                               code      => sub { $flag = 2; } });
ok(! ref($obj), 'Correct constructor failure [2]');

# This file will not load due to missing required information
$obj = RPC::XML::Method->new(File::Spec->catfile($dir, 'meth_bad_1.xpl'));
like($obj, qr/missing/i, 'Bad XPL [1] not loaded');

# This file will not load due to an XML parsing error
$obj = RPC::XML::Method->new(File::Spec->catfile($dir, 'meth_bad_2.xpl'));
like($obj, qr/error parsing/i, 'Bad XPL [2] not loaded');

# And the third bowl of porridge was _just_ _right_...
$obj = RPC::XML::Method->new(File::Spec->catfile($dir, 'meth_good_1.xpl'));
isa_ok($obj, 'RPC::XML::Method');

SKIP: {
    skip 'Cannot test without a value $obj', 20
        if (ref($obj) ne 'RPC::XML::Method');

    # Check the basics
    ok(ref($obj) && $obj->name() && scalar(@{$obj->signature}) &&
       $obj->hidden() && $obj->version() && $obj->help(),
       'Good XPL load, basic accessors');

    # Is code() the type of ref we expect?
    ok(ref($obj) && (ref($obj->code) eq 'CODE'),
       'Good XPL load, code() accessor');

    # This looks more complex than it is. The code returns this specific key:
    is($obj->code->({ method_name => $obj->name }), $obj->name(),
       'Good XPL load, code() invocation');

    # Time to test cloning
    $obj2 = $obj->clone;

    # Did it?
    isa_ok($obj2, ref($obj), '$obj2');
  SKIP: {
        skip 'Clone failed, cannot test without second object', 4
            if (ref($obj2) ne ref $obj);

        # Primary accessors/data
        ok(($obj->name()    eq $obj2->name())    &&
           ($obj->version() eq $obj2->version()) &&
           ($obj->help()    eq $obj2->help()),
           'Compare accessors of clone and source');
        # Are the actual listrefs of signatures different?
        isnt($obj->signature(), $obj2->signature(),
         'Clone signature() accessor has different listref');
        # And yet, the contents are the same?
        ok((@{$obj->signature} == @{$obj2->signature}) &&
           # There's only one signature in the list
           ($obj->signature->[0] eq $obj2->signature->[0]),
           'Clone signature() value is same despite this');
        # Lastly, and very importantly, the coderefs are still the same
        is($obj->code(), $obj2->code(),
           'Clone code() ref value is same as source');

        undef $obj2; # Don't need it anymore
    }

    # Now let's play around with signatures a bit

    # Basic test of match_signature()
    is($obj->match_signature(''), 'string', 'Test match_signature()');

    # Add a new signature, simple
    is($obj->add_signature('int int'), $obj,
       'Adding via add_signature() returns obj ref');
    # There should now be two
    is(scalar(@{$obj->{signature}}), 2,
       'Number of signatures after add_signature()');
    # Does the new one match OK?
    is($obj->match_signature('int'), 'int', 'New signature matches correctly');
    # Try matching it with an array-ref
    is($obj->match_signature([ 'int' ]), 'int', 'Signature matches arrayref');

    # This addition should fail due to ambiguity
    isnt($tmp = $obj->add_signature([ 'double', 'int' ]), $obj,
         'Correct failure of adding ambiguous signature');
    # But did it fail for the right reasons?
    like($tmp, qr/make_sig_table/,
         'Signature failure returned correct message');

    # Test deletion
    is($obj->delete_signature('int int'), $obj, 'Test delete_signature()');
    # Which means checking the count again
    is(scalar(@{$obj->{signature}}), 1,
       'Correct signature count after delete');
    # Try deleting the last signature
    my $err = $obj->delete_signature('string');
    like($err, qr/Cannot delete last signature/,
         'Deleting last signature fails');
    # Note that deleting a non-existent signature "succeeds"
    is($obj->delete_signature([ 'int' ]), $obj,
       'Attempt to delete non-existent signature');
    is(scalar(@{$obj->{signature}}), 1,
       'Correct signature count after useless delete');

    # We're done with this one for now.
    undef $obj;
}

# Test procedures that utilize nil data-types
$ALLOW_NIL = 1;

# First a simple nil-return
$obj = RPC::XML::Procedure->new({ name      => 'test.test_nil',
                                  signature => [ 'nil' ],
                                  code      => sub { return; } });
isa_ok($obj, 'RPC::XML::Procedure');
SKIP: {
    skip 'Cannot test without object', 2
        unless (ref($obj) eq 'RPC::XML::Procedure');

    my $val;
    eval { $val = $obj->call({}); };
    ok(! $@, 'Calling test.test_nil');
    isa_ok($val, 'RPC::XML::nil', 'Return value');
}

# Nil return from a proc with argument(s)
$obj = RPC::XML::Procedure->new({ name      => 'test.test_nil2',
                                  signature => [ 'nil int' ],
                                  code      =>
                                  sub { my $int = shift; return; } });
isa_ok($obj, 'RPC::XML::Procedure');
SKIP: {
    skip 'Cannot test without object', 2
        unless (ref($obj) eq 'RPC::XML::Procedure');

    my $val;
    eval { $val = $obj->call({}, RPC_INT 1); };
    ok(! $@, 'Calling test.test_nil2');
    isa_ok($val, 'RPC::XML::nil', 'Return value');
}

# Return value properly ignored when the signature types it as nil
$obj = RPC::XML::Procedure->new({ name      => 'test.test_nil3',
                                  signature => [ 'nil' ],
                                  code      => sub { 1; } });
isa_ok($obj, 'RPC::XML::Procedure');
SKIP: {
    skip 'Cannot test without object', 2
        unless (ref($obj) eq 'RPC::XML::Procedure');

    my $val;
    eval { $val = $obj->call({}); };
    ok(! $@, 'Calling test.test_nil3');
    isa_ok($val, 'RPC::XML::nil', 'Return value');
}

# Make sure that the presence of nil in a signature doesn't interfere with
# proper look-ups
$obj = RPC::XML::Procedure->new({ name      => 'test.test_nil4',
                                  signature => [ 'nil int' ],
                                  code      => sub { return; } });
isa_ok($obj, 'RPC::XML::Procedure');
SKIP: {
    skip 'Cannot test without object', 2
        unless (ref($obj) eq 'RPC::XML::Procedure');

    is($obj->match_signature('int'), 'nil', 'Test match_signature() with nil');
    ok(! $obj->match_signature('string'),
       'Test match_signature() with nil [2]');
}

exit 0;
