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

package App::Dochazka::REST;

use 5.012;
use strict;
use warnings;

use App::CELL qw( $CELL $log $meta $core $site );
use App::Dochazka::REST::ConnBank qw( $dbix_conn );
use App::Dochazka::REST::Mason;
use Data::Dumper;
use File::Path;
use File::ShareDir;
use File::Spec;
use Log::Any::Adapter;
use Params::Validate qw( :all );
use Try::Tiny;
use Web::Machine;
use Web::MREST::CLI qw( normalize_filespec );




=head1 NAME

App::Dochazka::REST - Dochazka REST server




=head1 VERSION

Version 0.506

=cut

our $VERSION = '0.506';


=head2 Development status

Alpha.




=head1 SYNOPSIS

Start the server with default settings:

    $ dochazka-rest

Point browser to:

    http://localhost:5000/

Use L<App::Dochazka::CLI> command-line interface to access full functionality:

    $ dochazka-cli


=head1 DESCRIPTION

This distribution, L<App::Dochazka::REST>, including all the modules in C<lib/>,
the scripts in C<bin/>, and the configuration files in C<config/>, constitutes
the REST server component of Dochazka, the open-source Attendance/Time Tracking
(ATT) system. 

Dochazka as a whole aims to be a convenient, open-source ATT solution.


=head2 Architecture

Dochazka consists of three main components:

=over

=item * REST server (this module)

The REST server listens for and processes incoming HTTP requests. Processing includes
authentication and authorization. The server attempts to map the request URI to a 
Dochazka resource. The resource handler takes action on the request, depending on the
HTTP method (GET, PUT, POST, DELETE). Typically, this action will culminate in 
one or more SQL statements which are sent to the PostgreSQL database for
execution. The results are sent back to the client in the HTTP reponse.

=item * PostgreSQL database

The PostgreSQL database is configured to listen for incoming SQL statements
from the REST server. Based on these statements, it creates, retrieves,
updates, and deletes (CRUD) employee attendance records and related data in the
Dochazka database.

=item * Dochazka clients

Dochazka clients, such as L<App::Dochazka::WWW>, L<App::Dochazka::CLI>, and
perhaps others, present a user interface (UI) to employees, by which they try
to divine their intent and express it in terms of HTTP requests to the REST
server.

The HTTP protocol is used in all communication between client and server. In
Dochazka, the term "client" should be understood in a broad sense to mean
anything that communicates with the server using the HTTP protocol. This
encompasses stand-alone report generators, specialized administration
utilities, cronjobs, web browsers, etc., in addition to the purpose-built
clients or just plain C<curl>.

=back


=head2 Client-server communication

As stated above, communication between the server and its clients takes place
using the HTTP protocol. More abstractly, the communication takes the form of
requests (from client to server) and responses (from server back to client) to
those requests. In other words, communication is never initiated by the server,
but always by the clients.

=head3 HTTP request

An HTTP request has the following basic components:

=over

=item * Method 

Dochazka supports GET, PUT, POST, and DELETE

=item * URI 

Universal Resource Indicator specifying a Dochazka resource

=item * Headers

More on these below

=item * Request entity

Data accompanying the request - may or may not be present

=back


=head4 Method

The Dochazka REST server accepts the following HTTP methods:  
C<GET>, C<PUT>, C<POST>, and C<DELETE>.

=over

=item C<GET>

A C<GET> request on a resource is a request for information - in other words,
it is "read-only": C<GET> requests never change the underlying data. In
Dochazka, C<GET> requests frequently map to C<SELECT> statements.

=item C<PUT>

C<PUT> requests always refer to a concrete data entity, or chunk of data.
In simple cases, this will be a single record in the underlying database. If
the record already exists, the C<PUT> request is interpreted to mean
modification (or C<UPDATE> in SQL). If the record does not exist, then the
request will map to an C<INSERT> statement to create the resource. In both
cases, upon success the response status will be C<200 OK>.

=item C<POST>

Sometimes, especially for create operations, the exact specification of the
resource is not known beforehand. To address these cases, some resources accept
C<POST> requests. If the request causes a new resource to be created, the HTTP
response status will be C<201 Created> and there will be a C<Location> header
specifying the URI of the newly created resource.

=item C<DELETE>

As their name would suggest, C<DELETE> requests are issued when we want to
dissolve (destroy) a resource. Whether or not this actually happens is
determined by two factors: (1) whether the user issuing the request has the
requisite authorization and, (2), whether the underlying data record is
referred to by other records - in which case typically the C<DELETE> request
will fail with a C<500 Internal Server Error> status.

=back



=head4 URI

The purpose of the Universal Resource Indicator (URI, sometimes also known as
an URL) is to uniquely identify a resource.

URIs consist of several syntactical elements. An exhaustive description can be
found in RFC ..., but for Dochazka purposes we can present them as follows:

=over

=item C<https://>

This part of the URI says that we are using the HTTPS protocol (or SSL-encrypted
HTTP) to communicate. It is separated from the next component by two forward
slashes.

=item C<dochazka.site>

After the protocol, the next URI component is the REST server's domain name.
Obviously, this will differ from site to site. It is separated from the next
component (i.e. the resource specification) by a single forward slash.

=item Dochazka resource

As stated above, the domain name is terminated by a single forward slash.
Everything after that is interpreted as a resource specification. 

A single forward slash C<'/'> specifies the root resource.

=back

Of these three components, the first two are site-specific. It is possible, 
for example, to run the Dochazka server without SSL encryption, in which case
the protocol would be C<http://> instead of C<https://>.

Once the application's implementation at a given site has stabilized, these two
URI components will change very seldomly, if at all.

Dochazka resources are much more ephemeral. Different resources present
different ways that users can access and modify the data (in this case,
attendance data) in the underlying database. 

Some resources, such as C<employee/nick/simona>, refer directly to a unit of
information that may or may not exist in the database information. Other
resources, like C<interval/new>, are not linked to a specific database record.

Also, in programming terms the resources are generalized, so we think about,
e.g., C<employee/nick/simona> and C<employee/nick/wanda> as two instances of a
more generalized C<employee/nick/:nick> resource, where C<:nick> is like an
argument to a function call.

And, indeed, internally all resources resolve to function calls. The function
in this case is referred to as the "resource handler".

Some resources accept all four HTTP methods listed above, others accept two or
three, and still others accept only one.


=head4 Headers

HTTP headers are somewhat obscure because they are often hidden by the 
client. Nevertheless, they are an important part of the HTTP protocol. The
Dochazka REST server only accepts certain headers in the request.

#FIXME: describe the more common response headers


=head4 Body

C<PUT> and C<POST> requests may take a request body. If a request body is
expected or accepted, it must be a valid JSON string. (JSON is a simple way of
"stringifying" a data structure.)


=head3 HTTP response

The HTTP response returned by the REST server consists of:

=over

=item * Status code (e.g. 200, 400, 404, etc.)

=item * Headers

=item * Content body (or "response entity")

=back


=head4 Status

The HTTP standard stipulates a number of status codes. The server listens for
incoming requests. Under normal operation, the server processes each request.
The result of such processing is a "response", which is sent back to the client
that originated the request. Each response will contain one and only one status
code. The meanings of the various status codes are explained in the HTTP
standard. Some of the more common ones are as follows:

=over

=item C<200> (OK)

The request was accepted and processed. Refer to the response body for the
result.

=item C<204> ()

This code is returned on C<DELETE> requests when either the record was
successfully deleted or the resource did not exist in the first place.

=item C<404> (Not Found)

The resource specification given in the URI could not be associated with a
known resource.

=item C<405> (Method Not Allowed)

The resource was recognized but it is not defined for this method.

=item C<401> (Not authorized)

A valid method+resource combination was specified, but the user failed to
authenticate herself to the REST server.

=item C<403> (Forbidden)

A valid method+resource combination was specified and the user was successfully
authenticated, but the user is not authorized to perform the operation she is
requesting.

=item C<400> (Malformed)

A valid method+resource combination was specified and the user passed
authentication and authorization. However, the information provided by the user
in the resource specification or in the request body could not be parsed.

=back


=head4 Headers

HTTP responses are always accompanied by headers, which qualify the response in
various ways. For example, the C<Content-Encoding> header indicates how the
bytes in the response body string should be interpreted. In Dochazka's case, the 
response body will always be in JSON, which implies the C<UTF-8> encoding.

#FIXME: describe the more common response headers


=head4 Body

The response body holds the information returned by a "successful" request. Be
aware that "success" in this context only means that, from the perspective of
the REST server, the request was fully processed. It does I<not> means that 
that whatever the user was requesting was actually done. For example, if a
C<GET> request for a resource is sent and the reponse code is 200, the client
programmer can assume that a response body will be present, and that it will
be an L<App::CELL::Status> object, but that is all she can assume.
Particularly, she cannot assume that the payload of that status object 
contains the object requested.

As stated above, the response body will always be a JSON string. This string
can either be displayed to the user as-is, or it can be interpreted and further
processed by the client.

A body may be included in the response, provided the status code is C<200> (OK).
For the client, an HTTP response of 200 is a signal to look into the response
body for further information. For the purposes of Dochazka, a 200 status does
not provide any information beyond this imperative: "look into the response
body". 

Since looking into the response body is fundamental to the operation of
Dochazka clients, the REST server emits response bodies in a strictly defined
format detailed in L<App::CELL::Status>. Client developers, then, can count 
on the truthfulness of the following statements:

=over

=item "A response body will be sent if, and only if, the HTTP status code is 200"

=item "The response body will always be a JSON string"

=item "That JSON string will always be an App::CELL::Status object"

=back



While the HTTP protocol provides a range of general status codes, some of which
make sense for and are used by Dochazka, in some cases Dochazka needs to return
status codes that are not provided for by the standard. For this reason, the
information returned by Dochazka is further encapsulated in a Dochazka-specific
status structure, and this is what is returned in the response body.



=head2 Basic parameters

=head3 UTF-8

The server assumes all incoming requests are encoded in UTF-8, and it encodes
all of its responses in UTF-8 as well.

=head3 HTTP(S)

In order to protect user passwords from network sniffing and other nefarious
activities, it is recommended that the server be set up to accept HTTPS
requests only. 

=head3 Self-documenting

Another implication of REST is that the server provides "resources" and that
those resources are, to some extent at least, self-documenting.

L<App::Dochazka::REST> provides 'help' resources whose only purpose is to 
provide information about the resources available to the client at a 
particular base level. For example, the top-level help resource provides
a list of resources available at that level, some of which are lower-level
'help' resources.

For each resource, the 'help' resource provides a 'link' attribute with the
full URI of the resource and a 'description' attribute with a terse
description of what the resource is good for.

The definition of each resource includes an HTML string containing the
resource's documentation. This string can be accessed via POST request for
the C<docu> resource (provide the resource name in double quotes in the
request body).


=head2 Exploring the server

=head3 With a web browser

Only some of L<App::Dochazka::REST>'s resources (i.e, those that use the GET
method) are accessible using a web browser. That said, if we are only
interested in displaying information from the database, GET requests are all we
need and using a web browser can be convenient.  

To start exploring, fire up a standard web browser and point it to the base URI
of your L<App::Dochazka::REST> installation:

    http://dochazka.site

and entering one's credentials in the Basic Authentication dialog.


=head3 With a command-line HTTP client

To access all the resources, you will need a client that is capable of
generating POST, PUT, and DELETE requests as well as GET requests. Also, since
some of the information L<App::Dochazka::REST> provides is in the response
headers, the client needs to be capable of displaying those as well.

One such client is Daniel Stenberg's B<curl>.

In the HTTP request, the client may provide an C<Accept:> header specifying
either HTML (C<text/html>) or JSON (C<application/json>). For the convenience
of those using a web browser, HTML is the default.

Here are some examples of how to use B<curl> (or a web browser) to explore
resources. These examples assume a vanilla installation of
L<App::Dochazka::REST> with the default root password. The same commands can be
used with a production server, but keep in mind that the resources you will see
may be limited by your privilege level.

=over 

=item * GET resources

The GET method is used to search for and display information. The top-level
GET resources are listed at the top-level URI, either using B<curl>

    $ curl -v -H 'Accept: application/json' http://demo:demo@dochazka.site/

Similarly, to display a list of sub-resources under the 'privhistory' top-level
resource, enter the command:

    $ curl http://demo:demo@dochazka.site/employee -H 'Accept: application/json' 

Oops - no resources are displayed because the 'demo' user has only passerby
privileges, but all the privhistory resources require at least 'active'. To
see all the available resources, we can authenticate as 'root':

    $ curl http://root:immutable@dochazka.site/employee -H 'Accept: application/json' 


=item * POST resources

With the GET method, we could only access resources for finding and displaying
information: we could not add, change, or delete information. For that we will
need to turn to some other client than the web browser -- a client like B<curl>
that is capable of generating HTTP requests with methods like POST (as well as
PUT and DELETE).

Here is an example of how we would use B<curl> to display the top-level POST
resources:

    curl -v http://root:immutable@dochazka.site -X POST -H "Content-Type: application/json"

The "Content-Type: application/json" header is necessary because the server
only accepts JSON in the POST request body -- even though in this case we 
did not send a request body, most POST requests will have one. For best
results, the request body should be a legal JSON string represented as a
sequence of bytes encoded in UTF-8.

=item * PUT resources

The PUT method is used to add new resources and update existing ones. Since
the resources are derived from the underlying database, this implies executing 
INSERT and UPDATE statements on tables in the database.

PUT resources can be explored using a B<curl> command analogous to the one
given for the POST method.

=item * DELETE resources

Any time we need to delete information -- i.e., completely wipe it from
the database, we will need to use the DELETE method. 

DELETE resources can be explored using a B<curl> command analogous to the one
given for the POST method.

Keep in mind that the data integrity constraints in the underlying PostgreSQL
database may make it difficult to delete a resource if any other resources
are linked to it. For example, an employee cannot be deleted until all
intervals, privhistory records, schedhistory records, locks, etc. linked to
that employee have been deleted. Intervals, on the other hand, can be 
deleted as long as they are not subject to a lock.

=back


=head2 Documentation of REST resources

In order to be "self-documenting", the definition of each REST resource
contains a "short" description and a "long" POD string. At each build, the
entire resource tree is walked to generate L<App::Dochazka::REST::Docs::Resources>.

Thus, besides directly accessing resources on the REST server itself, there
is also the option of perusing the documentation of all resources together in a
single POD module.


=head2 Request-response cycle

Incoming HTTP requests are handled by L<App::Dochazka::REST::Resource>,
which inherits from L<Web::Machine::Resource>. The latter uses L<Plack> to
implement a PSGI-compliant stack.

L<Web::Machine> takes a "state-machine" approach to implementing the HTTP 1.1
standard. Requests are processed by running them through a state
machine, each "cog" of which is a L<Web::Machine::Resource> method that can
be overridden by a child module. In our case, this module is
L<App::Dochazka::REST::Resource>.

The behavior of the resulting web server can be characterized as follows:

=over

=item * B<Allowed methods test>

One of the first things the server looks at, when it receives a request, is 
the method. Only certain HTTP methods, such as 'GET' and 'POST', are accepted.
If this test fails, a "405 Method Not Allowed" response is sent.

=item * B<Internal and external authentication, session management>

After the Allowed methods test, the user's credentials are authenticated
against an external database (LDAP), an internal database (PostgreSQL
'employees' table), or both. Session management techniques are utilized
to minimize external authentication queries, which impose latency. The
authentication and session management algorithms are described in,
L<"AUTHENTICATION AND SESSION MANAGEMENT">. If authentication fails, a "401
Unauthorized" response is sent. 

In a web browser, repeated failed authentication attempts are typically
associated with repeated display of the credentials dialog (and no other
indication of what is wrong, which can be confusing to users but is probably a
good idea, because any error messages could be abused by attackers).

Authentication (validation of user credentials to determine her identity)
should not be confused with authorization (determination whether the user
has sufficient privileges to do what she is trying to do). Authorization is
dealt with in the next step ("Authorization/ACL check").

=item * B<Authorization/ACL check>

After the request is authenticated (i.e. associated with a known employee), the
server examines the ACL profile of the resource being requested and compares it
with the employee's privilege level. If the privilege level is too low for the
requested operation, a "403 Forbidden" response is sent.

The ACL profile is part of the resource definition. It can be specified either
as a single value for all HTTP methods, or as a hash, e.g.:

    {
        GET => 'passerby',
        PUT => 'admin',
        DELETE => 'admin',
    }

In certain operations (i.e., combinations of HTTP method and resource), the
full range of functionality may be available only to administrators. See These
operations are special cases. Their ACL profile is either 'inactive' or
'active', but a non-administrator employee may still get a 403 Forbidden error
on the operation if they are trying to do something, such as update an interval
belonging to a different employee, that is reserved for administrators.

=item * B<Test for resource existence>

The next test a request undergoes on its quest to become a response is the
test of resource existence. If the request is asking for a non-existent resource,
e.g. L<http://dochazka.site/employee/curent>, it cannot be fulfilled and a "404
Not Found" response will be sent.

For GET requests, this is ordinarily the last cog in the state machine: if the
test passes, a "200 OK" response is typically sent, along with a response body.
(There are exceptions to this rule, however - see L<the AUTHORIZATION
chapter|"AUTHORIZATION">.) Requests using other methods (POST, PUT, DELETE) are
subject to further processing as described below.

=back

=head3 Additional processing (POST and PUT)

Because they are expected to have a request body, incoming POST and PUT
requests are subject to the following additional test:

=over

=item * B<malformed_request>

This test examines the request body. If it is non-existent, the test
passes. If the body exists and is valid JSON, the test passes. Otherwise,
it fails.

=item * B<known_content_type>

Test the request for the 'Content-Type' header. POST and PUT requests
should have a header that says:

    Content-Type: application/json

If this header is not present, a "415 Unsupported Media Type" response is
sent.

=back

=head3 Additional processing (POST)

=over 

#=item * B<post_is_create>
#
#This test examines the POST request and places it into one of two
#categories: (1) generic request for processing, (2) a request that creates
#or otherwise manipulates a resource. 

=back


=head1 DATA MODEL

This section describes the C<App::Dochazka::REST> data model. Conceptually, 
Dochazka data can be seen to exist in the following classes of objects:

=over

=item * Policy (parameters set when database is first created)

=item * Employee (an individual employee)

=item * Privhistory (history of changes in an employee's privilege level)

=item * Schedule (a schedule)

=item * Schedhistory (history of changes in an employee's schedule)

=item * Activities (what kinds of work are recognized)

=item * Intervals (the "work", or "attendance", itself)

=item * Locks (determining whether a reporting period is locked or not)

=back

These classes are described in the following sections.


##=head2 Policy
##
##Dochazka is configurable in a number of ways. Some configuration parameters
##are set once at installation time and, once set, can never be changed --
##these are referred to as "site policy" parameters.  Others, referred to as
##"site configuration parameters" or "site params", are set in configuration
##files such as C<Dochazka_SiteConfig.pm> (see L</SITE CONFIGURATION>) and
##can be changed more-or-less at will.
##
##The key difference between site policy and site configuration is that 
##site policy parameters cannot be changed, because changing them would
##compromise the referential integrity of the underlying database. 
##
##Site policy parameters are set at installation time and are stored, as a
##single JSON string, in the C<SitePolicy> table. This table is rendered
##effectively immutable by a trigger.
##
##For details, see L<App::Dochazka::REST::Model::Policy>.


=head2 Employee

Users of Dochazka are referred to as "employees" regardless of their 
legal status -- in reality they might be independent contractors, or
students, or even household pets, but as far as Dochazka is concerned they
are employees. You could say that "employee" is the Dochazka term for "user". 

The purpose of the Employee table/object is to store whatever data the site
is accustomed to use to identify its employees.

Within Dochazka itself, employees are distinguished by an internal employee ID
number (EID), which is assigned by Dochazka itself when the employee record is
created. In addition, four other fields/properties are provided to identify
the employee: 

=over

=item * nick

=item * sec_id

=item * fullname

=item * email

=back

All four of these, plus the C<eid> field, have C<UNIQUE> constraints defined at
the database level, meaning that duplicate entries are not permitted. However,
of the four, only C<nick> is required.

Depending on how authentication is set up, employee passwords may also be
stored in this table, using the C<passhash> and C<salt> fields.

For details, see L<App::Dochazka::REST::Model::Employee>.


=head2 Privhistory

Dochazka has four privilege levels: C<admin>, C<active>, C<inactive>, and
C<passerby>: 

=over

=item * C<admin> -- employee can view, modify, and place/remove locks on her
own attendance data as well as that of other employees; she can also
administer employee accounts and set privilege levels of other employees

=item * C<active> -- employee can view her own profile, attendance data,
modify her own unlocked attendance data, and place locks on her attendance
data

=item * C<inactive> -- employee can view her own profile and attendance data

=item * C<passerby> -- employee can view her own profile

=back

Dochazka's C<privhistory> object is used to track changes in an employee's
privilege level over time. Each time an employee's privilege level changes, 
a Dochazka administrator (i.e., an employee whose current privilege level is
'admin'), a record is inserted into the database (in the C<privhistory>
table). Ordinary employees (i.e. those whose current privilege level is
'active') can read their own privhistory.

Thus, with Dochazka it is possible not only to determine not only an employee's
current privilege level, but also to view "privilege histories" and to
determine employees' privilege levels for any date (timestamp) in the past.

For details, see L<App::Dochazka::REST::Model::Privhistory> and L<When
history changes take effect>.


=head2 Schedule

In addition to actual attendance data, Dochazka sites may need to store
schedules. Dochazka defines the term "schedule" as a series of
non-overlapping "time intervals" (or "timestamp ranges" in PostgreSQL
terminology) falling within a single week. These time intervals express the
times when the employee is "expected" or "supposed" to work (or be "at work")
during the scheduling period.

Example: employee "Barb" is on a weekly schedule. That means her
scheduling period is "weekly" and her schedule is an array of
non-overlapping time intervals, all falling within a single week.

B<In its current form, Dochazka is only capable of handling weekly schedules
only.> Some sites, such as hospitals, nuclear power plants, fire departments,
and the like, might have employees on more complicated schedules such as "one
week on, one week off", alternating day and night shifts, "on call" duty, etc.

Dochazka can still be used to track attendance of such employees, but if their
work schedule cannot be expressed as a series of non-overlapping time intervals
contained within a contiguous 168-hour period (i.e. one week), then their
Dochazka schedule should be set to NULL.

For details, see L<App::Dochazka::REST::Model::Schedule>.


=head2 Schedhistory

The C<schedhistory> table contains a historical record of changes in the
employee's schedule. This makes it possible to determine an employee's
schedule for any date (timestamp) in the past, as well as (crucially) the
employee's current schedule.

Every time an employee's schedule is to change, a Dochazka administrator
must insert a record into this table. (Employees who are not administrators
can only read their own history; they do not have write privileges.) For
more information on privileges, see L</AUTHORIZATION>.

For details, see L<App::Dochazka::REST::Model::Schedhistory>.


=head2 Activity

While on the job, employees "work" -- i.e., they engage in various activities
that are tracked using Dochazka. The C<activities> table contains definitions
of all the possible activities that may be entered in the C<intervals> table. 

The initial set of activities is defined in the site install configuration
(C<DOCHAZKA_ACTIVITY_DEFINITIONS>) and enters the database at installation
time. Additional activities can be added later (by administrators), but
activities can be deleted only if no intervals refer to them.

Each activity has a code, or short name (e.g., "WORK") -- which is the
primary way of referring to the activity -- as well as an optional long
description. Activity codes must be all upper-case.

For details, see L<App::Dochazka::REST::Model::Activity>.


=head2 Interval

Intervals are the heart of Dochazka's attendance data. For Dochazka, an
interval is an amount of time that an employee spends doing an activity.
In the database, intervals are represented using the C<tsrange> range
operator introduced in PostgreSQL 9.2.

Optionally, an interval can have a C<long_desc> (employee's description
of what she did during the interval) and a C<remark> (admin remark).

For details, see L<App::Dochazka::REST::Model::Interval>.


=head2 Lock

In Dochazka, a "lock" is a record in the "locks" table specifying that
a particular user's attendance data (i.e. activity intervals) for a 
given period (tsrange) cannot be changed. That means, for intervals in 
the locked tsrange:

=over

=item * existing intervals cannot be updated or deleted

=item * no new intervals can be inserted

=back

Employees can create locks (i.e., insert records into the locks table) on their
own EID, but they cannot delete or update those locks (or any others).
Administrators can insert, update, or delete locks at will.

How the lock is used will differ from site to site, and some sites may not
even use locking at all. The typical use case would be to lock all the
employee's attendance data within the given period as part of pre-payroll
processing. For example, the Dochazka client application may be set up to
enable reports to be generated only on fully locked periods. 

"Fully locked" means either that a single lock record has been inserted
covering the entire period, or that the entire period is covered by multiple
locks.

Any attempts (even by administrators) to enter activity intervals that 
intersect an existing lock will result in an error.

Clients can of course make it easy for the employee to lock entire blocks
of time (weeks, months, years . . .) at once, if that is deemed expedient.

For details, see L<App::Dochazka::REST::Model::Lock>.



=head1 INSTALLATION

Installation is the process of creating (setting up, bootstrapping) a new
Dochazka instance, or "site" in Dochazka terminology.

It entails the following steps:

=over

=item * B<Server preparation>

Dochazka REST needs hardware (either physical or virtualized) to run on. 
The hardware will need to have a network connection, etc. Obviously, this
step is entirely beyond the scope of this document.

=item * B<Software installation>

Once the hardware is ready, the Dochazka REST software and all its
dependencies are installed on it.  This could be accomplished by
downloading and unpacking the tarball (or running C<git clone>) and
following the installation instructions, or, more expediently, by
installing a packaged version of Dochazka REST if one is available
(see
L<https://build.opensuse.org/package/show/home:smithfarm/perl-App-Dochazka-REST>).

=item * B<PostgreSQL setup>

One of Dochazka REST's principal dependencies is PostgreSQL server (version
9.2 or higher). This needs to be installed (should happen automatically
when using the packaged version of L<App::Dochazka::REST>). Steps to enable
it:

    bash# chkconfig postgresql on
    bash#  systemctl start postgresql.service
    bash# su - postgres
    bash$ psql postgres
    postgres-# ALTER ROLE postgres WITH PASSWORD 'mypass';
    ALTER ROLE

At this point, we exit C<psql> and, still as the user C<postgres>, we 
edit C<pg_hba.conf>. Using our favorite editor, we change the METHOD entry
for C<local> so it looks like this:

    # TYPE  DATABASE   USER   ADDRESS     METHOD
    local   all        all                password

For the audit triggers to work (and the application will not run otherwise), we
must to add the following line to the end of C<postgresql.conf>:

    dochazka.eid = -1

Then, as root, we restart the postgresql service:

    bash# systemctl restart postgresql.service

Lastly, check if you can connect to the C<postgres> database using the password:

    bash$ psql --username postgres postgres
    Password for user postgres: [...type 'mypass'...]
    psql (9.2.7)
    Type "help" for help.

    postgres=# \q
    bash$

=item * B<Site configuration>

Before the Dochazka REST database can be initialized, we will need to
tell L<App::Dochazka::REST> about the PostgreSQL superuser password
that we set in the previous step. This is done via a site parameter. 
There may be other site params we will want to set, but the following
is sufficient to run the test suite. 

First, create a sitedir:

    bash# mkdir /etc/dochazka-rest

and, second, a file therein:

    # cat << EOF > /etc/dochazka-rest/REST_SiteConfig.pm
    set( 'MREST_DEBUG_MODE', 1 );
    set( 'DBINIT_CONNECT_SUPERAUTH', 'mypass' );
    set( 'DOCHAZKA_REST_LOG_FILE', "dochazka-rest.log" );
    set( 'DOCHAZKA_REST_LOG_FILE_RESET', 1);
    EOF
    #

Where 'mypass' is the PostgreSQL password you set in the 'ALTER
ROLE' command, above.

The C<DBINIT_CONNECT_SUPERAUTH> setting is only needed for database
initialization (see below), when L<App::Dochazka::REST> connects to PostgreSQL
as user 'postgres' to drop/create the database. Once the database is created,
L<App::Dochazka::REST> connects to it using the PostgreSQL credentials of the
current user.

=item * B<Syslog setup>

The above site configuration includes C<DOCHAZKA_REST_LOG_FILE> so
L<App::Dochazka::REST> will write its log messages to a file in the home
directory of the user it is running as. Also, since
DOCHAZKA_REST_LOG_FILE_RESET is set to a true value, this log file will be
reset (zeroed) every time L<App::Dochazka::REST> starts. 

=item * B<Database initialization>

In the future, there might be a nifty C<dochazka-dbinit> script to make
this process less painful, but for now the easiest way to initialize the
database is to clone the git repo from SourceForge and run the test suite:

    bash# cd ~/src
    bash# git clone git://git.code.sf.net/p/dochazka/code dochazka
    ...
    bash# cd dochazka
    bash# perl Build.PL
    bash# ./Build test

Assuming the previous steps were completed correctly, all the tests should
complete without errors.

=item * B<Start the server>

The last step is to start the Dochazka REST server. In the future, this
will be possible using a command like C<systemctl start dochazka.service>.
At the moment, however, we are still in development/testing phase and we 
start the server like this (as a normal user):

    $ cd ~/src/dochazka/App-Dochazka-REST
    $ ../dev.sh server dochazka-rest

=item * B<Take it for a spin>

Point your browser to L<http://localhost:5000/>

=back



=head1 REPORT GENERATION

Generation of reports is a core function of any ATT system. This section
describes the infrastructure Dochazka provides for this purpose. This
infrastructure is built around the L<Mason|https://metacpan.org/pod/Mason>
templating system.

The templates for L<a sample report|/"A typical report"> are provided with
the Dochazka distribution. The idea is that site administrators will
develop and add more templates to meet their particular reporting needs.


=head2 Infrastructure

The Dochazka report generation infrastructure has three parts: a template
management API, a report population API, and the report generation
resource.

=head3 Template management API

The template management API is a set of REST resources for creating,
reading, updating, and deleting L<Mason|https://metacpan.org/pod/Mason>
components. It is built around a "Component" class, instances of which
correspond to individual Mason components.

=head3 Report population API

The report population API is, basically, the Dochazka data model itself.
Since L<Mason|https://metacpan.org/pod/Mason> enables Perl code to be
embedded in templates, and since the templates are processed by the
Dochazka server, template authors have the entire Dochazka data model at
their disposal.

=head3 Report generation resource

A REST resource, C<GET genreport>, that takes the path of the Mason component
to be run and a hash of arguments to pass to it. The Mason component is run
with the provided arguments and the result (a string of characters that can
be interpreted as, e.g., an HTML page) is returned in the response content
body.

=back


=head2 Component class

The C<Component> class is used to work with Mason components. Each instance
has the following three attributes:

=over

=item Relative path

The relative path to the component in the Mason component directory tree.

=item Source code

The source code of the component, e.g. a mixture of HTML with Mason
directives.

=item ACL profile

The ACL profile of the component, determining who can use it. As usual,
supervisors can generate reports pertaining to employees who report
directly to them.

=back

For the time being, the C<Component> class does not implement any argument
validation. It is up to the caller to provide valid arguments when the
component is called.


=head2 A typical report

Let us examine a typical reporting requirement: a summary of one employee's
activity over the course of a time interval.

In addition to the employee's name, etc., this will require a data set
consisting of the days of the month and the total number of hours of each
activity logged by (or for) the employee on each day.



=head1 CAVEATS


=head2 Unbounded intervals

Be careful when entering unbounded intervals: PostgreSQL 9.3 is picky about
how they are formatted. This, for example, is syntactically correct:

    select * from intervals where intvl && '[,)';

But this will generate a syntax error:

    select * from intervals where intvl && '[, )';

Even though this is OK:

    select * from intervals where intvl && '[, infinity)';


=head2 Weekly schedules only

Unfortunately, the weekly scheduling period is hard-coded at this time.
Dochazka does not care what dates are used to define the intervals -- only
that they fall within a contiguous 168-hour period. Consider the following
contrived example. If the scheduling intervals for EID 1 were defined like
this:

    "[1964-12-30 22:05, 1964-12-31 04:35)"
    "[1964-12-31 23:15, 1965-01-01 03:10)"

for Dochazka that would mean that the employee with EID 1 has a weekly schedule
of "WED/22:05-THU/04:35" and "THU/23:15-FRI/03:10", because the dates in the
ranges fall on a Wednesday (1964-12-30), a Thursday (1964-12-31), and a
Friday (1964-01-01), respectively.



=head2 When history changes take effect

The C<effective> field of the C<privhistory> and C<schedhistory> tables
contains the effective date/time of the history change. This field takes a
timestamp, and a trigger ensures that the value is evenly divisible by five
minutes (by rounding). In other words,

    '1964-06-13 14:45'

is a valid C<effective> timestamp, while

    '2014-01-01 00:00:01'

will be rounded to '2014-01-01 00:00'.



=head1 AUTHENTICATION AND SESSION MANAGEMENT

Employees do not access the database directly, but only via HTTP requests.
For authorization and auditing purposes, L<App::Dochazka::REST> needs to
associate each incoming request to an EID. 

When a request comes in, the headers and cookies are examined.
Requests that belong to an existing session have a cookie that looks like:

    Session ID: xdfke34irsdfslajoasdja;sldkf

while requests for a new session have a header that looks like this:

    Authorize: 


=head2 Existing session

In the former case, since the request is being intermediated by a Plack-aware
web server, the request will be accompanied by a Plack environment (hashref)
containing a 'psgix.session' key. The value of this key is a hashref that
contains the session state.

If the session state is valid, it will contain:

=over

=item * the Employee ID, C<eid>

=item * the IP address from which the session was first originated, C<ip_addr>

=item * the date/time when the session was last seen, C<last_seen>

=back

If any of these are missing, or the difference between C<last_seen> and the
current date/time is greater than the time interval defined in the
C<DOCHAZKA_REST_SESSION_EXPIRATION_TIME>, the request is rejected with 401
Unauthorized. 

This takes pace in the C<_validate_session> routine of
L<App::Dochazka::REST::Resource>.


=head2 New session

Requests for a new session are subject to HTTP Basic Authentication. To protect
employee credentials from network sniffing attacks, the HTTP traffic
must be encrypted. This can be accomplished using an SSL-capable HTTP
server or transparent proxy such as L<nginx|http://nginx.org/en/>.

If the C<DOCHAZKA_LDAP> site parameter is set to a true value, the
C<_authenticate> routine of L<App::Dochazka::REST::Resource> will attempt to 
authenticate the request against an external resource using the LDAP protocol.

LDAP authentication takes place in two phases:

=over

=item * lookup phase

=item * authentication phase

=back

The purpose of the lookup phase is to determine if the user exists in the 
LDAP resource and, if it does exist, to get its 'cn' property. In the second
phase, the password entered by the user is compared with the password stored
in the LDAP resource.

If the LDAP lookup phase fails, or if LDAP is disabled, L<App::Dochazka::REST>
falls back to "internal authentication", which means that the credentials are
compared against the C<nick>, C<passhash>, and C<salt> fields of the
C<employees> table in the database.

To protect user credentials from snooping, the actual passwords are not stored
in the database, Instead, they are run through a one-way hash function and
the hash (along with a random "salt" string) is stored in the database instead
of the password itself. Since some "one-way" hashing algorithms are subject to
brute force attacks, the Blowfish algorithm was chosen to provide the best
known protection.

If the request passes Basic Authentication, a session ID is generated and 
stored in a cookie. 



=head1 AUTHORIZATION



=head1 DEBUGGING

L<App::Dochazka::REST> offers the following debug facilities:

=over

=item * C<bin/dochazka-rest -- --early-debug=$TMPFILE>

Calling the server startup script as shown will cause the C<--early-debug>
parameter to be passed through to C<bin/mrest> (from the L<Web::MREST> distro).
This has the interesting effect of capturing even the earliest debug messages
to a temporary file, which the server must be able to C<touch>. Once the server
has started, the filename can also be determined by sending a C<GET
param/meta/MREST_EARLY_DEBUGGING> request.

=item * DOCHAZKA_DEBUG environment variable

If the C<DOCHAZKA_DEBUG> environment variable is set to a true value, the
entire 'context' will be returned in each JSON response, instead of just 
the 'entity'. For more information, see C<Resource.pm>.

=item * MREST_DEBUG_MODE site configuration parameter

If the C<MREST_DEBUG_MODE> site parameter is set to a true value,
debug messages will be logged.

=back

=head1 METHODS


=head2 run_sql

Takes a L<DBIx::Connector> object and an array of SQL statements. Runs them 
one by one until an exception is thrown or the last statement completes
successfully. Returns a status object which will be either OK or ERR.
If NOT_OK, the error text will be in C<< $status->text >>.

=cut

sub run_sql {
    my ( $conn, @stmts ) = @_;
    my $status;
    try {
        foreach my $stmt ( @stmts ) {
            $log->debug( "Running SQL statement $stmt" );
            $conn->run( fixup => sub { $_->do( $stmt ); } );
        }
    } catch {
        $status = $CELL->status_err( 'DOCHAZKA_DBI_ERR', args => [ $_ ] );
    };
    return $status if $status;
    return $CELL->status_ok;
}


sub _do_audit_triggers {
    my ( $mode, $conn ) = @_;

    my $sql;
    if ( $mode eq 'create' ) {
        $sql = $site->DBINIT_CREATE_AUDIT_TRIGGERS;
    } elsif ( $mode eq 'delete' ) {
        $sql = $site->DBINIT_DELETE_AUDIT_TRIGGERS;
    } else {
        die "AAADFDGGGGGGAAAAAAAHHH! " . __PACKAGE__ . "::_do_audit_triggers";
    }

    my @prepped_sql;
    foreach my $table ( @{ $site->DOCHAZKA_AUDIT_TABLES } ) {
        my $sql_copy = $sql;
        my $question_mark = quotemeta('?');
        $log->debug( "Replacing question mark with $table" );
        $sql_copy =~ s{$question_mark}{$table};
        push( @prepped_sql, $sql_copy );
    }
    my $status = run_sql( 
        $conn, 
        @prepped_sql,
    );
    return $status;
}


=head2 create_audit_triggers

Create the audit triggers. Wrapper for _do_audit_triggers

=cut

sub create_audit_triggers {
    my $conn = shift;
    return _do_audit_triggers( 'create', $conn );
}
    

=head2 delete_audit_triggers

Delete the audit triggers. Wrapper for _do_audit_triggers

=cut

sub delete_audit_triggers {
    my $conn = shift;
    return _do_audit_triggers( 'delete', $conn );
}
    

=head2 reset_mason_dir

Wipe out and re-create the Mason state directory. Returns status object.
Upon success, level will be 'OK' and payload will contain the full path
to the Mason component root.

=cut

sub reset_mason_dir {
    my $status;

    # wipe out
    my $statedir = $site->DOCHAZKA_STATE_DIR;
    die "OUCH!!! DOCHAZKA_STATE_DIR site parameter not defined!" unless $statedir;
    die "OUCH!!! DOCHAZKA_STATE_DIR is not readable by me!" unless -r $statedir;
    die "OUCH!!! DOCHAZKA_STATE_DIR is not writable by me!" unless -w $statedir;
    die "OUCH!!! DOCHAZKA_STATE_DIR is not executable by me!" unless -x $statedir;
    my $masondir = File::Spec->catfile( $statedir, 'Mason' );
    $log->debug( "Mason directory is $masondir" );
    rmtree( $masondir );
    mkpath( $masondir, 0, 0750 );

    # re-create
    my $comp_root = File::Spec->catfile( $masondir, 'comp_root' );
    mkpath( $comp_root, 0, 0750 );
    my $data_dir = File::Spec->catfile( $masondir, 'data_dir' );
    mkpath( $data_dir, 0, 0750 );
    $status = App::Dochazka::REST::Mason::init_singleton( 
        comp_root => $comp_root, 
        data_dir => $data_dir 
    );
    return $status unless $status->ok;
    $status->payload( $comp_root );
    return $status;
}


=head2 reset_db

Drop and re-create a Dochazka database. Takes superuser credentials as
arguments. 

Be very, _very_, _VERY_ careful with this function.

=cut

sub reset_db {
    my ( $superuser, $superpass ) = @_;

    my $status;
    my $dbname = $site->DOCHAZKA_DBNAME;
    my $dbuser = $site->DOCHAZKA_DBUSER;
    my $dbpass = $site->DOCHAZKA_DBPASS;
    $log->debug( "Entering " . __PACKAGE__ . "::reset_db to (re-)initialize database $dbname with superuser credentials $superuser / $superpass" );

    # PGTZ *must* be set
    $ENV{'PGTZ'} = $site->DOCHAZKA_TIMEZONE;

    my $conn = App::Dochazka::REST::ConnBank::get_arbitrary_dbix_conn(
        'postgres', $superuser, $superpass
    );
    $status = run_sql( 
        $conn,
        "DROP DATABASE IF EXISTS \"$dbname\"",
        "DROP ROLE IF EXISTS $dbuser",
        "CREATE ROLE \"$dbuser\" WITH LOGIN PASSWORD '$dbpass'",
        "CREATE DATABASE \"$dbname\"",
        "REVOKE CONNECT ON DATABASE \"$dbname\" FROM PUBLIC",
    );
    return $status unless $status->ok;

    # create:
    # - audit schema (see config/sql/audit_Config.pm)
    # - public schema (all application-specific tables, functions, triggers, etc.)
    # - the 'root' and 'demo' employees
    # - privhistory record for root
    $conn = App::Dochazka::REST::ConnBank::get_arbitrary_dbix_conn(
        $dbname, $superuser, $superpass
    );
    $status = run_sql(
        $conn,
        @{ $site->DBINIT_AUDIT },
        @{ $site->DBINIT_CREATE },
    );
    return $status unless $status->ok;

    # get EID of root employee that was just created, since
    # we will need it in the second round of SQL statements
    my $eids = get_eid_of( $conn, "root", "demo" );
    $site->set( 'DOCHAZKA_EID_OF_ROOT', $eids->{'root'} );
    $site->set( 'DOCHAZKA_EID_OF_DEMO', $eids->{'demo'} );

    # the second round of SQL statements to make root employee immutable
    # is taken from DBINIT_MAKE_ROOT_IMMUTABLE site param

    # prep DBINIT_MAKE_ROOT_IMMUTABLE
    # (replace ? with EID of root employee in all the statements
    # N.B.: we avoid the /r modifier here because we might be using Perl # 5.012)
    my @root_immutable_statements = map { 
        local $_ = $_; s/\?/$eids->{'root'}/g; $_; 
    } @{ $site->DBINIT_MAKE_ROOT_IMMUTABLE };

    # prep DBINIT_GRANTS (replace the strings '$dbuser' and '$dbpass' with
    # the DOCHAZKA_DBUSER and DOCHAZKA_DBPASS site params, respectively
    my $dbname_search = quotemeta( '$dbname' );
    my $dbuser_search = quotemeta( '$dbuser' );
    my $dbpass_search = quotemeta( '$dbpass' );
    my @grants = map {
        local $_ = $_; 
        s{$dbname_search}{$dbname}g; 
        s{$dbuser_search}{$dbuser}g; 
        s{$dbpass_search}{$dbpass}g; 
        $_; 
    } @{ $site->DBINIT_GRANTS };

    # run the modified statements
    $status = run_sql(
        $conn,
        @root_immutable_statements,
        @grants,
    );
    return $status unless $status->ok;

    # insert initial set of activities
    try {
        $conn->txn( fixup => sub {
            my $sth = $_->prepare( $site->SQL_ACTIVITY_INSERT );
            foreach my $actdef ( @{ $site->DOCHAZKA_ACTIVITY_DEFINITIONS } ) {
                $sth->bind_param( 1, $actdef->{code} );
                $sth->bind_param( 2, $actdef->{long_desc} );
                $sth->bind_param( 3, 'dbinit' );
                $sth->execute;
            }
        } );
    } catch {
        $status = $CELL->status_err( 'DOCHAZKA_DBI_ERR', args => [ $_ ] );
    };
    return $status unless $status->ok;
    
    # insert initial set of components
    try {
        $conn->txn( fixup => sub {
            my $sth = $_->prepare( $site->SQL_COMPONENT_INSERT );
            foreach my $actdef ( @{ $site->DOCHAZKA_COMPONENT_DEFINITIONS } ) {
                $sth->bind_param( 1, $actdef->{path} );
                $sth->bind_param( 2, $actdef->{source} );
                $sth->bind_param( 3, $actdef->{acl} );
                $sth->execute;
            }
        } );
    } catch {
        $status = $CELL->status_err( 'DOCHAZKA_DBI_ERR', args => [ $_ ] );
    };
    return $status unless $status->ok;
    
    # if auditing is enabled, create the audit triggers
    if ( $site->DOCHAZKA_AUDITING ) {
        $status = create_audit_triggers( $conn );
        return $status unless $status->ok;
    }
    
    $log->notice( "Database $dbname successfully (re-)initialized" );
    return $status;
}


=head2 get_eid_of

Obtain the EIDs of a list of employee nicks. Returns a reference to a hash
where the keys are the nicks and the values are the corresponding EIDs.

NOTE 1: This routine expects to receive a L<DBIx::Connector> object as its
first argument. It does not use the C<$dbix_conn> singleton.

NOTE 2: The nicks are expected to exist and no provision (other than logging a
DOCHAZKA_DBI_ERR) is made for their non-existence.

=cut

sub get_eid_of {
    my ( $conn, @nicks ) = @_;
    $log->debug( "Entering " . __PACKAGE__ . "::get_eid_of" );
    my ( %eids, $status );
    try {
        $conn->run( fixup => sub { 
            my $sth = $_->prepare( $site->DBINIT_SELECT_EID_OF );
            foreach my $nick ( @nicks ) {
                $sth->bind_param( 1, $nick );
                $sth->execute;
                ( $eids{$nick} ) = $sth->fetchrow_array();
                $log->debug( "EID of $nick is $eids{$nick}" );
            }
        } );
    } catch {
        $CELL->status_err( 'DOCHAZKA_DBI_ERR', args => [ $_ ] );
    };
    return \%eids;
}


=head2 version

Accessor method (to be called like a constructor) providing access to C<$VERSION> variable

=cut

sub version { $VERSION; }



=head1 GLOSSARY OF TERMS

In Dochazka, some commonly-used terms have special meanings:

=over

=item * B<employee> -- 
Regardless of whether they are employees in reality, for the
purposes of Dochazka employees are the folks whose attendance/time is being
tracked.  Employees are expected to interact with Dochazka using the
following functions and commands.

=item * B<administrator> -- 
In Dochazka, administrators are employees with special powers. Certain
REST/CLI functions are available only to administrators.

=item * B<CLI client> --
CLI stands for Command-Line Interface. The CLI client is the Perl script
that is run when an employee types C<dochazka> at the bash prompt.

=item * B<REST server> --
REST stands for ... . The REST server is a collection of Perl modules 
running on a server at the site.

=item * B<site> --
In a general sense, the "site" is the company, organization, or place that
has implemented (installed, configured) Dochazka for attendance/time
tracking. In a technical sense, a site is a specific instance of the
Dochazka REST server that CLI clients connect to.

=back



=head1 AUTHOR

Nathan Cutler, C<< <presnypreklad@gmail.com> >>




=head1 BUGS

Please report any bugs or feature requests to 
C<bug-dochazka-rest at rt.cpan.org>, or through the web interface at
L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=App-Dochazka-REST>.  The author
will be notified, and then you'll automatically be notified of progress on your
bug as he makes changes.




=head1 SUPPORT

The full documentation comes with the distro, and can be comfortable
perused at metacpan.org:

    https://metacpan.org/pod/App::Dochazka::REST

You can also read the documentation for individual modules using the
perldoc command, e.g.:

    perldoc App::Dochazka::REST
    perldoc App::Dochazka::REST::Model::Activity

Other resources:

=over 4

=item * RT: CPAN's request tracker (report bugs here)

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=App-Dochazka-REST>

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/App-Dochazka-REST>

=back




=head1 LICENSE AND COPYRIGHT

Copyright (c) 2014-2015, SUSE LLC
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

1. Redistributions of source code must retain the above copyright notice, this
list of conditions and the following disclaimer.

2. Redistributions in binary form must reproduce the above copyright notice,
this list of conditions and the following disclaimer in the documentation
and/or other materials provided with the distribution.

3. Neither the name of SUSE LLC nor the names of its contributors
may be used to endorse or promote products derived from this software without
specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.


=cut

1; # End of App::Dochazka::REST
