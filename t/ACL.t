# ************************************************************************* 
# Copyright (c) 2014-2015, SUSE LLC
# 
# All rights reserved.
# 
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
# 
# 1. Redistributions of source code must retain the above copyright notice,
# this list of conditions and the following disclaimer.
# 
# 2. Redistributions in binary form must reproduce the above copyright
# notice, this list of conditions and the following disclaimer in the
# documentation and/or other materials provided with the distribution.
# 
# 3. Neither the name of SUSE LLC nor the names of its contributors may be
# used to endorse or promote products derived from this software without
# specific prior written permission.
# 
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE
# LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
# CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
# SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
# INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
# CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
# ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
# POSSIBILITY OF SUCH DAMAGE.
# ************************************************************************* 
#
# tests for ACL.pm
#

#!perl
use 5.012;
use strict;
use warnings;

#use App::CELL::Test::LogToFile;
use App::CELL qw( $meta $site );
use Data::Dumper;
use App::Dochazka::REST::ACL qw( check_acl );
use App::Dochazka::REST::Test;
use Test::Fatal;
use Test::More;

note( 'initialize, connect to database, and set up a testing plan' );
my $status = initialize_unit();
if ( $status->not_ok ) {
    plan skip_all => "not configured or server not running";
}

note( 'check_acl() tests' );

my $profile = 'passerby';
note( "check privlevel logic: $profile" );
ok( check_acl( profile => $profile, privlevel => 'passerby' ) );
ok( check_acl( profile => $profile, privlevel => 'inactive' ) );
ok( check_acl( profile => $profile, privlevel => 'active' ) );
ok( check_acl( profile => $profile, privlevel => 'admin' ) );

$profile = 'inactive';
note( "check privlevel logic: $profile" );
ok( ! check_acl( profile => $profile, privlevel => 'passerby' ) );
ok( check_acl( profile => $profile, privlevel => 'inactive' ) );
ok( check_acl( profile => $profile, privlevel => 'active' ) );
ok( check_acl( profile => $profile, privlevel => 'admin' ) );

$profile = 'active';
note( "check privlevel logic: $profile" );
ok( ! check_acl( profile => $profile, privlevel => 'passerby' ) );
ok( ! check_acl( profile => $profile, privlevel => 'inactive' ) );
ok( check_acl( profile => $profile, privlevel => 'active' ) );
ok( check_acl( profile => $profile, privlevel => 'admin' ) );

$profile = 'admin';
note( "check privlevel logic: $profile" );
ok( ! check_acl( profile => $profile, privlevel => 'passerby' ) );
ok( ! check_acl( profile => $profile, privlevel => 'inactive' ) );
ok( ! check_acl( profile => $profile, privlevel => 'active' ) );
ok( check_acl( profile => $profile, privlevel => 'admin' ) );

note( 'forbidden functionality' );
foreach my $p ( qw( passerby inactive active admin ) ) {
    ok( ! check_acl( profile => 'forbidden', privlevel => $p ) );
}

done_testing;
